#!/usr/bin/python3
"""Read real store transactions into a private, reviewable analytics snapshot.

No account, purchase, entitlement or production KV write is performed. API keys
come from the existing macOS Keychain integrations and stay in process memory.
Run from apps/russia: /usr/bin/python3 tools/store_revenue/restore.py
"""
import argparse
import base64
import csv
import hashlib
import io
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'store_release'))
from publish import (ANDROID_PACKAGE, IOS_BUNDLE, ASC_KEY_ID, ASC_ISSUER,
                     AppStore, Play, HttpError, http, jwt)
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

ACCOUNT = 'a4eee3dae596a9dd9ea14dc123874f9d'
NAMESPACE = '2c854aacc0b7483f9cb271c19a79ba5a'
BUCKET = 'pubsite_prod_8172841311997997566'
APPLE_PRODUCTS = {'u.pdd.pddApp.premium.week', 'ru.pdd.pddApp.sub.3months'}
GOOGLE_PRODUCTS = {'ru.pdd.pddapp.sub.week', 'ru.pdd.pddapp.sub.3months',
                   'ru.pdd.pddapp.premium.week', 'ru.pdd.pddapp.premium.3months'}


def utc_stamp(value):
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value / 1000, timezone.utc).isoformat().replace('+00:00', 'Z')
    return datetime.fromisoformat(str(value).replace('Z', '+00:00')).astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def money_units(value):
    if not isinstance(value, dict) or not re.fullmatch('[A-Z]{3}', value.get('currencyCode', '')):
        return None
    amount = Decimal(str(value.get('units', '0'))) + Decimal(str(value.get('nanos', 0))) / Decimal(1000000000)
    milliunits = int((amount * 1000).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    return {'currency': value['currencyCode'], 'milliunits': milliunits} if milliunits > 0 else None


def google_order_transaction(value, is_test=False):
    ident = value['orderId']
    if not re.fullmatch(r'GPA\.[\d.-]+', ident):
        raise ValueError('wrong Google order identifier')
    if not value.get('lineItems') or any(item.get('productId') not in GOOGLE_PRODUCTS for item in value['lineItems']):
        raise ValueError('unexpected Google product')
    state = value.get('state')
    money = money_units(value.get('total'))
    history = value.get('orderHistory') or {}
    if state == 'PARTIALLY_REFUNDED':
        refunds = [item for item in history.get('partialRefundEvents', []) if item.get('state') == 'PROCESSED_SUCCESSFULLY']
        if not refunds or not money:
            raise ValueError('partial refund amount unavailable')
        refunded = 0
        for item in refunds:
            amount = money_units((item.get('refundDetails') or {}).get('total'))
            if not amount or amount['currency'] != money['currency']:
                raise ValueError('partial refund currency unavailable')
            refunded += amount['milliunits']
        if refunded <= 0 or refunded >= money['milliunits']:
            raise ValueError('partial refund amount invalid')
        money = {**money, 'milliunits': money['milliunits'] - refunded}
    purchased_at = (history.get('processedEvent') or {}).get('eventTime') or value['createTime']
    return transaction('googleplay', ident, purchased_at, money,
                       paid=bool(money) and state in ('PROCESSED', 'PENDING_REFUND', 'PARTIALLY_REFUNDED', 'REFUNDED'),
                       refunded=state == 'REFUNDED', isTest=is_test,
                       checkedAt=utc_stamp(datetime.now(timezone.utc).isoformat()), source='googleplay_orders')


def transaction(method, ident, purchased_at, money, **fields):
    return {'id': hashlib.sha256((method + ':' + ident).encode()).hexdigest(), 'method': method,
            'app': 'ru', 'purchasedAt': utc_stamp(purchased_at), 'money': money,
            'paid': bool(money), 'isTest': False, 'refunded': False, **fields}


class Cloudflare:
    def __init__(self):
        config = (Path.home() / 'Library/Preferences/.wrangler/config/default.toml').read_text()
        match = re.search(r'^oauth_token\s*=\s*"([^"]+)"', config, re.MULTILINE)
        if not match:
            raise ValueError('Wrangler OAuth is unavailable')
        self.auth = {'Authorization': 'Bearer ' + match[1]}
        self.base = f'https://api.cloudflare.com/client/v4/accounts/{ACCOUNT}/storage/kv/namespaces/{NAMESPACE}'

    def keys(self, prefix):
        result, cursor = [], None
        while True:
            query = {'prefix': prefix, 'limit': 1000}
            if cursor:
                query['cursor'] = cursor
            page = http('GET', self.base + '/keys?' + urllib.parse.urlencode(query), self.auth)
            if page.get('success') is not True or not isinstance(page.get('result'), list):
                raise ValueError('Cloudflare directory unavailable')
            result.extend(page['result'])
            next_cursor = page.get('result_info', {}).get('cursor')
            if not next_cursor:
                break
            if cursor == next_cursor:
                raise ValueError('Cloudflare directory incomplete')
            cursor = next_cursor
        return result

    def get(self, key):
        return http('GET', self.base + '/values/' + urllib.parse.quote(key, safe=''), self.auth)


def store_seeds(kv):
    keys = kv.keys('user:')
    candidates = [key for key in keys if key.get('metadata', {}).get('app', 'ru') == 'ru'
                 and (any(key.get('metadata', {}).get(field)
                 for field in ('purchasedAt', 'storeVerifiedAt', 'hasPaidPurchase'))
                 or key.get('metadata', {}).get('premiumSource') in ('appstore', 'googleplay'))]
    apple, google, google_tokens = set(), set(), set()
    with ThreadPoolExecutor(max_workers=8) as pool:
        for profile in pool.map(lambda key: kv.get(key['name']), candidates):
            if profile.get('app', 'ru') != 'ru':
                continue
            refs = list((profile.get('verifiedPurchases') or {}).values())
            if profile.get('verifiedPurchase'):
                refs.append(profile['verifiedPurchase'])
            for reference in refs:
                if reference.get('store') == 'appstore':
                    ident = str(reference.get('transactionId') or '')
                    if re.fullmatch(r'\d{1,40}', ident):
                        apple.add(ident)
                elif reference.get('store') == 'googleplay':
                    token = reference.get('purchaseToken')
                    if token:
                        google_tokens.add(token)
                    ident = reference.get('orderId') or reference.get('latestOrderId')
                    if ident and re.fullmatch(r'GPA\.[\d.-]+', ident):
                        google.add(ident)
    for key in kv.keys('notified_purch:'):
        ident = key['name'][len('notified_purch:'):]
        if re.fullmatch(r'\d{1,40}', ident):
            apple.add(ident)
        elif re.fullmatch(r'GPA\.[\d.-]+', ident):
            google.add(ident)
    return apple, google, google_tokens, {'profilesScanned': len(candidates), 'profilesListed': len(keys)}


class AppleHistory:
    def __init__(self):
        self.api = AppStore()

    def auth(self):
        def sign(message):
            r, s = decode_dss_signature(self.api.key.sign(message, ec.ECDSA(hashes.SHA256())))
            return r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
        now = int(time.time())
        token = jwt({'alg': 'ES256', 'kid': ASC_KEY_ID, 'typ': 'JWT'},
                    {'iss': ASC_ISSUER, 'iat': now, 'exp': now + 1100,
                     'aud': 'appstoreconnect-v1', 'bid': IOS_BUNDLE}, sign)
        return {'Authorization': 'Bearer ' + token}

    def notification_seeds(self):
        """A read-only app-wide history query also covers deleted accounts."""
        now = int(time.time() * 1000)
        body = {'startDate': now - 179 * 86400000, 'endDate': now}
        self.notification_window = {'from': utc_stamp(body['startDate']), 'through': utc_stamp(body['endDate'])}
        seeds, token, notifications = set(), None, 0
        while True:
            url = 'https://api.storekit.apple.com/inApps/v1/notifications/history'
            if token:
                url += '?' + urllib.parse.urlencode({'paginationToken': token})
            page = http('POST', url, self.auth(), body)
            for item in page.get('notificationHistory', []):
                notifications += 1
                payload = json.loads(base64.urlsafe_b64decode(item['signedPayload'].split('.')[1] + '==='))
                data = payload.get('data') or {}
                if data.get('bundleId') != IOS_BUNDLE or data.get('environment') != 'Production':
                    continue
                if not data.get('signedTransactionInfo'):
                    continue
                value = json.loads(base64.urlsafe_b64decode(data['signedTransactionInfo'].split('.')[1] + '==='))
                ident = str(value.get('transactionId') or '')
                if value.get('bundleId') != IOS_BUNDLE or value.get('environment') != 'Production' or not re.fullmatch(r'\d{1,40}', ident):
                    raise ValueError('wrong Apple notification transaction')
                seeds.add(ident)
            if not page.get('hasMore'):
                break
            if not page.get('paginationToken') or token == page['paginationToken']:
                raise ValueError('Apple notifications incomplete')
            token = page['paginationToken']
        return seeds, notifications

    def history(self, ident):
        environment, revision, transactions = 'Production', None, []
        while True:
            host = 'api.storekit.apple.com' if environment == 'Production' else 'api.storekit-sandbox.apple.com'
            query = {'sort': 'ASCENDING'}
            if revision:
                query['revision'] = revision
            try:
                data = http('GET', f'https://{host}/inApps/v2/history/{ident}?' + urllib.parse.urlencode(query), self.auth())
            except HttpError as error:
                if error.status == 404 and environment == 'Production' and not revision:
                    environment = 'Sandbox'
                    continue
                raise
            if data.get('bundleId') != IOS_BUNDLE or data.get('environment') != environment:
                raise ValueError('wrong Apple history')
            for signed in data.get('signedTransactions', []):
                value = json.loads(base64.urlsafe_b64decode(signed.split('.')[1] + '==='))
                if value.get('bundleId') != IOS_BUNDLE or value.get('environment') != environment:
                    raise ValueError('wrong Apple transaction')
                if value.get('productId') not in APPLE_PRODUCTS:
                    continue
                ident_value = str(value.get('transactionId', ''))
                if not re.fullmatch(r'\d{1,40}', ident_value):
                    raise ValueError('wrong Apple transaction identifier')
                amount = value.get('price')
                currency = value.get('currency')
                money = {'currency': currency, 'milliunits': amount} if isinstance(amount, int) and amount > 0 and re.fullmatch('[A-Z]{3}', str(currency)) else None
                transactions.append(transaction('appstore', ident_value, value['purchaseDate'], money,
                                    isTest=environment != 'Production', refunded=bool(value.get('revocationDate')),
                                    checkedAt=utc_stamp(datetime.now(timezone.utc).isoformat()), source='appstore_server_history'))
            if not data.get('hasMore'):
                break
            if not data.get('revision') or revision == data['revision']:
                raise ValueError('Apple history pagination incomplete')
            revision = data['revision']
        return transactions


def google_sales_ids():
    auth = Play('https://www.googleapis.com/auth/devstorage.read_only').auth
    query = {'prefix': 'sales/', 'fields': 'nextPageToken,items(name,generation)'}
    order_ids, months = set(), []
    while True:
        page = http('GET', f'https://storage.googleapis.com/storage/v1/b/{BUCKET}/o?' + urllib.parse.urlencode(query), auth)
        for obj in page.get('items', []):
            name = obj['name']
            match = re.fullmatch(r'sales/salesreport_(\d{6})\.zip', name)
            if not match:
                continue
            months.append(match[1])
            url = f'https://storage.googleapis.com/{BUCKET}/{name}?generation=' + obj['generation']
            with urllib.request.urlopen(urllib.request.Request(url, headers=auth), timeout=60) as response:
                zipped = zipfile.ZipFile(io.BytesIO(response.read()))
            for filename in zipped.namelist():
                raw = zipped.read(filename)
                text = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig')
                rows = csv.DictReader(io.StringIO(text))
                if not {'Order Number', 'Package ID', 'Financial Status'}.issubset(rows.fieldnames or []):
                    raise ValueError('unexpected Google sales report')
                for row in rows:
                    if row['Package ID'] != ANDROID_PACKAGE:
                        continue
                    ident = row['Order Number']
                    if not re.fullmatch(r'GPA\.[\d.-]+', ident):
                        raise ValueError('wrong Google order identifier')
                    order_ids.add(ident)
        if not page.get('nextPageToken'):
            break
        query['pageToken'] = page['nextPageToken']
    return order_ids, sorted(months)


def google_orders(ids, tokens):
    api = Play()
    test_ids = set()
    for token in tokens:
        value = api.call('GET', '/purchases/subscriptionsv2/tokens/' + urllib.parse.quote(token, safe=''))
        token_ids = {item['latestSuccessfulOrderId'] for item in value.get('lineItems', []) if item.get('latestSuccessfulOrderId')}
        if value.get('latestOrderId'):
            token_ids.add(value['latestOrderId'])
        ids.update(token_ids)
        if value.get('testPurchase') is not None:
            test_ids.update(token_ids)
    records, states = [], Counter()
    for ident in sorted(ids):
        value = api.call('GET', '/orders/' + urllib.parse.quote(ident, safe=''))
        if value.get('orderId') != ident:
            raise ValueError('wrong Google order')
        state = value.get('state')
        states[state] += 1
        records.append(google_order_transaction(value, ident in test_ids))
    return records, dict(states)


def save_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch(mode=0o600, exist_ok=True)
    path.chmod(0o600)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def collect(output):
    apple_seeds, google_seeds, google_tokens, scanned = store_seeds(Cloudflare())
    google_report_ids, months = google_sales_ids()
    google_records, google_states = google_orders(google_seeds | google_report_ids, google_tokens)
    apple = AppleHistory()
    apple_records, errors = [], []
    try:
        notification_seeds, notification_count = apple.notification_seeds()
        apple_seeds |= notification_seeds
    except (Exception, SystemExit) as error:
        notification_count = None
        errors.append({'source': 'appstore_notifications', 'kind': type(error).__name__, 'status': getattr(error, 'status', None)})
    for index, ident in enumerate(sorted(apple_seeds)):
        try:
            apple_records.extend(apple.history(ident))
        except (Exception, SystemExit) as error:
            errors.append({'source': 'appstore', 'seed': index, 'kind': type(error).__name__, 'status': getattr(error, 'status', None)})
    records = {item['id']: item for item in apple_records + google_records}
    transactions = sorted(records.values(), key=lambda item: (item['purchasedAt'], item['id']))
    coverage = {'checkedAt': utc_stamp(datetime.now(timezone.utc).isoformat()), **scanned,
                'appleSeeds': len(apple_seeds), 'appleScope': 'customer_and_app_notification_history' if notification_count is not None else 'known_customer_transaction_history',
                'appleNotificationsScanned': notification_count,
                'appleNotificationWindow': getattr(apple, 'notification_window', None),
                'googleSalesMonths': months, 'googleOrders': len(google_records), 'googleOrderStates': google_states,
                'errors': errors}
    imported_at = utc_stamp(datetime.now(timezone.utc).isoformat())
    snapshot = {'version': 1, 'transactions': transactions, 'coverage': coverage, 'importedAt': imported_at,
                'replaceLegacyBefore': {'googleplay': imported_at}}
    if not any(error['source'] == 'appstore' for error in errors):
        snapshot['replaceLegacyBefore']['appstore'] = imported_at
    save_private(output, snapshot)
    totals, counts, excluded = {}, Counter(), Counter()
    for item in transactions:
        method = item['method']
        if item['isTest'] or item['refunded'] or not item['paid']:
            excluded[method] += 1
            continue
        counts[method] += 1
        money = item.get('money')
        if money:
            key = method + ':' + money['currency']
            totals[key] = totals.get(key, 0) + money['milliunits']
    summary = {'transactions': len(transactions), 'included': dict(counts), 'excluded': dict(excluded),
               'amountsMilliunits': totals, 'from': min((item['purchasedAt'] for item in transactions), default=None),
               'to': max((item['purchasedAt'] for item in transactions), default=None), 'coverage': coverage}
    save_private(output.with_name(output.stem + '-summary.json'), summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2] / 'output/store-revenue-restore/candidate.json')
    args = parser.parse_args()
    try:
        collect(args.output.resolve())
    except (Exception, SystemExit) as error:
        print(json.dumps({'error': type(error).__name__, 'status': getattr(error, 'status', None)}), file=sys.stderr)
        sys.exit(1)
