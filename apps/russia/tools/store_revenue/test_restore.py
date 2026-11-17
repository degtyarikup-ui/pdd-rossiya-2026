import base64
import hashlib
import json
import unittest
from unittest.mock import patch

import restore


def signed(value):
    return 'header.' + base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=') + '.signature'


class RestoreTests(unittest.TestCase):
    def test_transaction_has_stable_private_id_and_true_utc_date(self):
        value = restore.transaction('appstore', '12345', 1790960400000,
                                    {'currency': 'RUB', 'milliunits': 99000})
        self.assertEqual(value['id'], hashlib.sha256(b'appstore:12345').hexdigest())
        self.assertEqual(value['purchasedAt'], '2026-10-02T17:00:00Z')
        self.assertNotIn('12345', json.dumps(value))
        self.assertTrue(value['paid'])

    def test_google_money_is_actual_total_not_tariff_or_developer_proceeds(self):
        self.assertEqual(restore.money_units({'currencyCode': 'USD', 'units': '3', 'nanos': 390000000}),
                         {'currency': 'USD', 'milliunits': 3390})
        self.assertEqual(restore.money_units({'currencyCode': 'KZT', 'units': '1790'}),
                         {'currency': 'KZT', 'milliunits': 1790000})
        self.assertIsNone(restore.money_units({'currencyCode': 'USD', 'units': '0'}))
        self.assertIsNone(restore.money_units({'currencyCode': 'bad', 'units': '99'}))

    def test_google_uses_processed_payment_date_and_exact_partial_refund(self):
        value = {'orderId': 'GPA.1234-5678-9012-34567', 'state': 'PARTIALLY_REFUNDED',
                 'lineItems': [{'productId': 'ru.pdd.pddapp.sub.week'}],
                 'createTime': '2026-11-16T20:59:00Z', 'total': {'currencyCode': 'USD', 'units': '10'},
                 'orderHistory': {'processedEvent': {'eventTime': '2026-11-16T21:01:00Z'},
                  'partialRefundEvents': [{'state': 'PROCESSED_SUCCESSFULLY',
                                          'refundDetails': {'total': {'currencyCode': 'USD', 'units': '2'}}}]}}
        result = restore.google_order_transaction(value)
        self.assertEqual(result['purchasedAt'], '2026-11-16T21:01:00Z')
        self.assertEqual(result['money']['milliunits'], 8000)
        self.assertFalse(result['refunded'])
        self.assertTrue(result['paid'])
        value['orderHistory']['partialRefundEvents'] = []
        with self.assertRaises(ValueError):
            restore.google_order_transaction(value)

    def test_google_test_and_return_flags_survive_normalization(self):
        value = {'orderId': 'GPA.1234-5678-9012-34567', 'state': 'REFUNDED',
                 'lineItems': [{'productId': 'ru.pdd.pddapp.sub.week'}],
                 'createTime': '2026-11-16T20:59:00Z', 'total': {'currencyCode': 'USD', 'units': '10'}}
        result = restore.google_order_transaction(value, is_test=True)
        self.assertTrue(result['isTest'])
        self.assertTrue(result['refunded'])

    def test_apple_history_pages_all_renewals_preserving_price_and_revocation(self):
        api = restore.AppleHistory.__new__(restore.AppleHistory)
        api.auth = lambda: {}
        calls = []
        def request(method, url, headers=None, body=None):
            calls.append(url)
            transaction = {'bundleId': restore.IOS_BUNDLE, 'environment': 'Production',
                           'productId': next(iter(restore.APPLE_PRODUCTS)),
                           'transactionId': str(len(calls)), 'purchaseDate': 1790960400000,
                           'price': 990, 'currency': 'USD'}
            if len(calls) == 2:
                transaction['revocationDate'] = 1790960401000
            return {'bundleId': restore.IOS_BUNDLE, 'environment': 'Production',
                    'signedTransactions': [signed(transaction)], 'hasMore': len(calls) == 1,
                    'revision': 'next' + str(len(calls))}
        with patch.object(restore, 'http', request):
            values = api.history('1')
        self.assertEqual(len(values), 2)
        self.assertIn('revision=next1', calls[1])
        self.assertEqual(values[0]['money'], {'currency': 'USD', 'milliunits': 990})
        self.assertFalse(values[0]['refunded'])
        self.assertTrue(values[1]['refunded'])

    def test_wrong_apple_app_is_rejected(self):
        api = restore.AppleHistory.__new__(restore.AppleHistory)
        api.auth = lambda: {}
        with patch.object(restore, 'http', return_value={'bundleId': 'other', 'environment': 'Production'}):
            with self.assertRaises(ValueError):
                api.history('1')

    def test_notification_history_is_read_only_and_recovers_deleted_account_seeds(self):
        api = restore.AppleHistory.__new__(restore.AppleHistory)
        api.auth = lambda: {}
        tx = {'bundleId': restore.IOS_BUNDLE, 'environment': 'Production', 'transactionId': '987'}
        payload = {'data': {'bundleId': restore.IOS_BUNDLE, 'environment': 'Production',
                            'signedTransactionInfo': signed(tx)}}
        with patch.object(restore, 'http', return_value={'notificationHistory': [{'signedPayload': signed(payload)}]}) as request:
            seeds, count = api.notification_seeds()
        self.assertEqual(seeds, {'987'})
        self.assertEqual(count, 1)
        args = request.call_args.args
        self.assertEqual(args[0], 'POST')
        self.assertEqual(args[1], 'https://api.storekit.apple.com/inApps/v1/notifications/history')
        self.assertLess(args[3]['startDate'], args[3]['endDate'])


if __name__ == '__main__':
    unittest.main()
