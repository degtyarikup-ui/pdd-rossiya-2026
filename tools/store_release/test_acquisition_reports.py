import gzip
import unittest
from unittest.mock import patch

import acquisition_reports as reports


class AcquisitionReportsTest(unittest.TestCase):
    def test_play_utf16_aggregates_only_the_target_app(self):
        content = ('Date,Package name,Traffic source,Store listing acquisitions\n'
                   '2026-10-24,ru.pdd.pdd_app,Google Play explore,3\n'
                   '2026-10-24,ru.pdd.pdd_app,Google Play explore,2\n').encode('utf-16')
        self.assertEqual(reports.aggregate(content, 'googleplay', reports.ANDROID_PACKAGE),
                         {'2026-10-24': {'Google Play explore': 5}})
        with self.assertRaises(ValueError):
            reports.aggregate(content, 'googleplay', 'some.other.app')

    def test_apple_replaces_corrected_day_with_all_segments_and_skips_retries(self):
        header = 'Date\tApp Apple Identifier\tSource Type\tDownload Type\tCounts\n'
        content = gzip.compress((header + '2026-10-24\t123\tApp Store search\tFirst-time Download\t3\n'
                                 + '2026-10-24\t123\tApp Store search\tRedownload\t20\n').encode())
        endpoints = {'analyticsReportRequests': [{'id': 'r', 'attributes':
                     {'accessType': 'ONGOING', 'stoppedDueToInactivity': False}}],
                     'reports': [{'id': 'downloads', 'attributes': {'name': 'App Store Downloads Standard'}}],
                     'instances': [{'id': 'i', 'attributes': {'processingDate': '2026-10-26'}}],
                     'segments': [{'attributes': {'url': 'part1'}}, {'attributes': {'url': 'part2'}}]}
        def pages(api, path, **kwargs):
            return iter(endpoints[path.rsplit('/', 1)[1]])
        with patch.object(reports, 'AppStore') as client, patch.object(reports, 'pages', pages), \
                patch.object(reports, 'download', return_value=content) as download:
            client.return_value.app.return_value = '123'
            result = reports.apple_report({'days': {'2026-10-24': {'App Store browse': 9}}}, '2026-01-01')
            self.assertEqual(result['days'], {'2026-10-24': {'App Store search': 6}})
            self.assertEqual(reports.apple_report(result, '2026-01-01'), result)
            self.assertEqual(download.call_count, 2)
