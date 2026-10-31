"""Import aggregate RU store reports into the admin Worker's KV. See docs/release/store-api.md."""
import csv
import gzip
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from publish import ANDROID_PACKAGE, AppStore, Play, http

BUCKET = 'pubsite_prod_8172841311997997566'
WORKER = Path(__file__).resolve().parents[2] / 'server/install-notifier'
REPORT_PREFIX = f'stats/store_performance/store_performance_{ANDROID_PACKAGE}_'
WRANGLER = os.environ.get('WRANGLER_BIN', 'wrangler')


def download(url, headers=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=60) as response:
        return response.read()


def aggregate(content, store, app_id):
    apple = store == 'appstore'
    encoding = 'utf-16' if content.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig'
    rows = csv.DictReader(io.StringIO(content.decode(encoding)), delimiter='\t' if apple else ',')
    app = 'App Apple Identifier' if apple else 'Package name'
    source = 'Source Type' if apple else 'Traffic source'
    count = 'Counts' if apple else 'Store listing acquisitions'
    required = {'Date', app, source, count}
    if apple:
        required.add('Download Type')
    if not required.issubset(rows.fieldnames or []):
        raise ValueError('unexpected report columns')
    days = {}
    for row in rows:
        if row[app] != app_id:
            raise ValueError('unexpected app in report')
        day = date.fromisoformat(row['Date']).isoformat()
        sources = days.setdefault(day, Counter())
        if apple and row['Download Type'].casefold() != 'first-time download':
            continue
        amount = int(row[count])
        if amount < 0:
            raise ValueError('negative count')
        sources[row[source].strip() or 'Unavailable'] += amount
    return days


def google_report(previous, cutoff):
    auth = Play('https://www.googleapis.com/auth/devstorage.read_only').auth
    query = {'prefix': REPORT_PREFIX, 'fields': 'nextPageToken,items(name,generation)'}
    days, versions = {}, {}
    while True:
        page = http('GET', f'https://storage.googleapis.com/storage/v1/b/{BUCKET}/o?' +
                    urllib.parse.urlencode(query), auth)
        for obj in page.get('items', []):
            name = obj['name']
            match = re.fullmatch(re.escape(REPORT_PREFIX) + r'(\d{6})_traffic_source\.csv', name)
            if not match or match[1] < cutoff[:7].replace('-', ''):
                continue
            month = match[1][:4] + '-' + match[1][4:]
            versions[month] = obj['generation']
            if previous.get('versions', {}).get(month) == obj['generation']:
                days.update({k: v for k, v in previous['days'].items() if k.startswith(month)})
            else:
                data = download(f'https://storage.googleapis.com/{BUCKET}/{name}?generation=' + obj['generation'], auth)
                days.update(aggregate(data, 'googleplay', ANDROID_PACKAGE))
        if not page.get('nextPageToken'):
            break
        query['pageToken'] = page['nextPageToken']
    return {'days': days, 'versions': versions}


def pages(api, path, **query):
    while path:
        page = api.call('GET', path, **query)
        yield from page['data']
        link = page.get('links', {}).get('next')
        if link and not link.startswith(api.API + '/v1/'):
            raise ValueError('unexpected pagination URL')
        path, query = link[len(api.API):] if link else None, {}


def apple_report(previous, cutoff):
    api = AppStore()
    app = api.app()
    requests = list(pages(api, f'/v1/apps/{app}/analyticsReportRequests'))
    if not any(r['attributes']['accessType'] == 'ONGOING' and not r['attributes']['stoppedDueToInactivity']
               for r in requests):
        raise ValueError('ongoing Apple report request is inactive')
    instances = []
    for req in requests:
        reports = pages(api, f"/v1/analyticsReportRequests/{req['id']}/reports", limit=200)
        report = next((r for r in reports if r['attributes']['name'] == 'App Downloads Standard'), None)
        if report:
            instances.extend(pages(api, f"/v1/analyticsReports/{report['id']}/instances",
                                   **{'filter[granularity]': 'DAILY'}))
    days = dict(previous.get('days', {}))
    revisions = dict(previous.get('revisions', {}))
    processed = dict(previous.get('processed', {}))
    for item in sorted(instances, key=lambda x: x['attributes']['processingDate']):
        stamp, ident = item['attributes']['processingDate'], item['id']
        if ident in processed or stamp < cutoff:
            continue
        batch = {}
        segments = list(pages(api, f'/v1/analyticsReportInstances/{ident}/segments'))
        if not segments:
            continue
        for segment in segments:
            attrs = segment['attributes']
            data = download(attrs['url'])
            rows = aggregate(gzip.decompress(data), 'appstore', app)
            for day, sources in rows.items():
                batch.setdefault(day, Counter()).update(sources)
        # Each instance replaces the full event-date partition, including corrections.
        for day, sources in batch.items():
            if stamp >= revisions.get(day, ''):
                days[day] = sources
                revisions[day] = stamp
        processed[ident] = stamp
    return {'days': days, 'revisions': {k: v for k, v in revisions.items() if k >= cutoff},
            'processed': {k: v for k, v in processed.items() if v >= cutoff}}


def sync(store, fetch, cutoff):
    key = 'store-reports:v1:' + store
    cmd = [WRANGLER, 'kv', 'key']
    args = [key, '--binding', 'INSTALLS', '--remote']
    result = subprocess.run(cmd + ['get'] + args + ['--text'], cwd=WORKER, capture_output=True, text=True)
    if result.returncode and '404: Not Found' not in result.stderr:
        raise RuntimeError('KV read failed')
    previous = {} if result.returncode else json.loads(result.stdout)
    report = fetch(previous, cutoff)
    report['days'] = {k: v for k, v in report['days'].items() if k >= cutoff}
    report['checkedAt'] = datetime.now(timezone.utc).isoformat()
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8') as tmp:
        json.dump(report, tmp, ensure_ascii=False)
        tmp.flush()
        subprocess.run(cmd + ['put'] + args + ['--path', tmp.name], cwd=WORKER, check=True, stdout=subprocess.DEVNULL)
    print(f"{store}: {len(report['days'])} report dates, latest {max(report['days'], default='pending')}", flush=True)


if __name__ == '__main__':
    cutoff = (datetime.now(timezone.utc).date() - timedelta(days=365)).isoformat()
    failures = 0
    for store, fetch in [('googleplay', google_report), ('appstore', apple_report)]:
        try:
            sync(store, fetch, cutoff)
        except (Exception, SystemExit) as error:
            # HTTP errors may include temporary signed URLs. Log no URL or credentials.
            print(f'{store}: import failed ({type(error).__name__}, status {getattr(error, "status", None)})',
                  file=sys.stderr)
            failures += 1
    sys.exit(bool(failures))
