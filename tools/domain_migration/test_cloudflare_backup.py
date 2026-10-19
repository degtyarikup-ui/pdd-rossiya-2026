"""Offline verification: no credentials or production requests are used."""

import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import quote

from cloudflare_backup import ApiError, BackupError, Client, Collector, load_token


ACCOUNT = 'a' * 32
NAMESPACE = 'b' * 32
ZONE = 'c' * 32
BASE = '/accounts/' + ACCOUNT
WORKER = BASE + '/workers/scripts/test-worker'


def response(result, info=None):
    body = {'success': True, 'result': result}
    if info is not None:
        body['result_info'] = info
    return json.dumps(body).encode(), {'Content-Type': 'application/json'}


class FakeClient:
    def __init__(self, routes):
        self.routes = routes
        self.paths = []
        self.bulk_calls = []

    def get(self, path):
        self.paths.append(path)
        value = self.routes.get(path, ApiError(404))
        if isinstance(value, Exception):
            raise value
        return value

    def bulk_get(self, path, keys):
        self.bulk_calls.append((path, keys))
        values = {}
        for key in keys:
            value = self.routes.get(path.replace('/bulk/get', '/values/') + quote(key, safe=''))
            try:
                values[key] = {'value': value[0].decode('utf-8'), 'metadata': None}
            except (TypeError, UnicodeError):
                values[key] = None
        return response({'values': values})


class BackupTests(unittest.TestCase):
    def setUp(self):
        # All temporary files remain under the repository's ignored output/.
        parent = Path(__file__).resolve().parents[2] / 'output'
        parent.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=str(parent), prefix='backup-test-')
        self.output = Path(self.temp.name) / 'backup'

    def tearDown(self):
        self.temp.cleanup()

    def client(self):
        return FakeClient({
            WORKER + '/settings': response({'bindings': [{'type': 'kv_namespace', 'namespace_id': NAMESPACE}]}),
            WORKER: (b'--multipart-source--\x00', {'Content-Type': 'multipart/form-data'}),
            WORKER + '/deployments': response({'deployments': []}),
            WORKER + '/secrets': response([{'name': 'PRIVATE_SECRET', 'type': 'secret_text'}]),
            BASE + '/storage/kv/namespaces/' + NAMESPACE + '/keys?limit=1000': response([
                {'name': 'user:example', 'metadata': {'v': 4}, 'expiration': 2000000000},
            ], {'cursor': 'next-page'}),
            BASE + '/storage/kv/namespaces/' + NAMESPACE + '/keys?limit=1000&cursor=next-page': response([
                {'name': '../../binary/☃', 'metadata': None},
            ], {'cursor': ''}),
            BASE + '/storage/kv/namespaces/' + NAMESPACE + '/values/user%3Aexample': (b'{"progress": 7}', {}),
            BASE + '/storage/kv/namespaces/' + NAMESPACE + '/values/..%2F..%2Fbinary%2F%E2%98%83': (b'\x00\xff\x80', {}),
            BASE + '/workers/durable_objects/namespaces?page=1&per_page=100': response([
                {'id': 'd' * 32, 'class': 'AccountState', 'script': 'test-worker', 'use_sqlite': True},
                {'id': 'e' * 32, 'class': 'OtherClass', 'script': 'other-worker'},
            ]),
            BASE + '/workers/durable_objects/namespaces/' + 'd' * 32 + '/objects?limit=1000': response([
                {'id': 'f' * 64, 'hasStoredData': True},
            ], {'cursor': ''}),
            '/zones/' + ZONE: response({'id': ZONE, 'name': 'example.invalid'}),
            '/zones/' + ZONE + '/dns_records?page=1&per_page=100': response([{'type': 'A', 'name': 'example.invalid', 'content': '192.0.2.1'}]),
        })

    def test_collect_preserves_binary_ttl_and_metadata_and_declares_do_gap(self):
        client = self.client()
        result = Collector(client, self.output, ACCOUNT, 'test-worker').collect(zone_ids=[ZONE])
        self.assertTrue(result['collection_complete'])
        self.assertFalse(result['full_data_backup'])
        self.assertFalse(result['production_mutations'])
        self.assertEqual(result['kv'][0]['captured_keys'], 2)
        index = json.loads((self.output / result['kv'][0]['index']).read_text())
        self.assertEqual(index['keys'][0]['metadata'], {'v': 4})
        self.assertEqual(index['keys'][0]['expiration'], 2000000000)
        self.assertEqual((self.output / index['keys'][1]['file']).read_bytes(), b'\x00\xff\x80')
        self.assertEqual(len(result['durable_objects']), 1)
        self.assertFalse(result['durable_objects'][0]['data_exported'])
        self.assertEqual(result['zones'][0]['dns_records'], 1)
        self.assertFalse(any('/api/admin/' in path for path in client.paths))
        for path in self.output.rglob('*'):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700 if path.is_dir() else 0o600)

    def test_resume_reuses_verified_captures_and_retries_optional_resources(self):
        Collector(self.client(), self.output, ACCOUNT, 'test-worker').collect()
        client = self.client()
        Collector(client, self.output, ACCOUNT, 'test-worker').collect()
        self.assertFalse(any('/values/' in path for path in client.paths))
        self.assertNotIn(WORKER, client.paths)
        self.assertEqual(client.bulk_calls, [])

    def test_bulk_text_preserves_original_json_bytes_and_binary_uses_raw_get(self):
        client = self.client()
        original = ' { "name" : "Беларусь",\n "escaped" : "\\u0041" }\n'.encode()
        value_path = BASE + '/storage/kv/namespaces/' + NAMESPACE + '/values/user%3Aexample'
        client.routes[value_path] = (original, {})
        result = Collector(client, self.output, ACCOUNT, 'test-worker').collect()
        index = json.loads((self.output / result['kv'][0]['index']).read_text())
        self.assertEqual((self.output / index['keys'][0]['file']).read_bytes(), original)
        self.assertEqual(index['keys'][0]['source']['method'], 'POST bulk/get type=text')
        self.assertNotIn(value_path, client.paths)
        self.assertEqual((self.output / index['keys'][1]['file']).read_bytes(), b'\x00\xff\x80')
        self.assertTrue(any('/values/..' in path for path in client.paths))

    def test_bulk_unsupported_binary_splits_batch_and_falls_back_to_raw_get(self):
        client = self.client()
        original_bulk = client.bulk_get

        def bulk_with_binary_rejection(path, keys):
            if any(key.startswith('../') for key in keys):
                raise ApiError(400)
            return original_bulk(path, keys)

        client.bulk_get = bulk_with_binary_rejection
        result = Collector(client, self.output, ACCOUNT, 'test-worker').collect()
        self.assertEqual(result['kv'][0]['captured_keys'], 2)
        self.assertEqual(len(client.bulk_calls), 1)
        self.assertTrue(any('/values/..' in path for path in client.paths))

    def test_dns_forbidden_marks_gap_but_still_collects_kv_and_do(self):
        client = self.client()
        client.routes['/zones/' + ZONE + '/dns_records?page=1&per_page=100'] = ApiError(403)
        result = Collector(client, self.output, ACCOUNT, 'test-worker').collect(zone_ids=[ZONE])
        self.assertTrue(result['collection_complete'])
        self.assertEqual(result['kv'][0]['captured_keys'], 2)
        self.assertEqual(len(result['durable_objects']), 1)
        self.assertFalse(result['zones'][0]['dns_records_captured'])
        self.assertIsNone(result['zones'][0]['dns_records'])
        self.assertIn({'resource': 'DNS records', 'http_status': 403}, result['optional_resource_failures'])
        index = json.loads((self.output / result['zones'][0]['index']).read_text())
        self.assertFalse(index['listing_complete'])
        self.assertIsNone(index['dns_records'])

    def test_corrupted_capture_and_foreign_identity_fail_closed(self):
        Collector(self.client(), self.output, ACCOUNT, 'test-worker').collect()
        with self.assertRaises(BackupError):
            Collector(self.client(), self.output, '9' * 32, 'test-worker')
        journal = [json.loads(line) for line in (self.output / 'requests.jsonl').read_text().splitlines()]
        (self.output / journal[0]['file']).write_bytes(b'corrupt')
        with self.assertRaises(BackupError):
            Collector(self.client(), self.output, ACCOUNT, 'test-worker').collect()

    def test_incomplete_cursor_fails_and_repeated_cursor_fails(self):
        for info in ({'list_complete': False}, {'cursor': 'again'}):
            client = FakeClient({
                '/example?limit=1000': response([], info),
                '/example?limit=1000&cursor=again': response([], info),
            })
            collector = Collector(client, self.output / str(len(info)) / str(bool(info.get('cursor'))), ACCOUNT, 'test-worker')
            with self.assertRaises(BackupError):
                collector.cursor_list('/example', 'test inventory')

    def test_missing_value_recorded_but_forbidden_value_aborts(self):
        for status in (404, 403):
            client = self.client()
            client.routes[BASE + '/storage/kv/namespaces/' + NAMESPACE + '/values/user%3Aexample'] = ApiError(status)
            collector = Collector(client, self.output / str(status), ACCOUNT, 'test-worker')
            if status == 404:
                self.assertEqual(collector.collect()['kv'][0]['missing_at_read'], 1)
            else:
                with self.assertRaises(ApiError):
                    collector.collect()

    def test_network_client_allows_only_get_and_rejects_redirects(self):
        class Result:
            headers = {}
            def __enter__(self): return self
            def __exit__(self, *_): return None
            def read(self): return b'{}'

        with patch('urllib.request.build_opener') as factory:
            factory.return_value.open.return_value = Result()
            Client('test-only-token').get('/test')
            request = factory.return_value.open.call_args[0][0]
            self.assertEqual(request.get_method(), 'GET')
            self.assertIsNone(request.data)
            handler = factory.call_args[0][0]
            self.assertIsNone(handler.redirect_request(request, None, 302, '', {}, 'https://other.invalid'))
        with self.assertRaises(BackupError):
            Client('test').get('https://other.invalid')

    def test_network_client_post_allowlist_only_permits_bulk_get_text_reads(self):
        class Result:
            headers = {}
            def __enter__(self): return self
            def __exit__(self, *_): return None
            def read(self): return b'{}'

        path = BASE + '/storage/kv/namespaces/' + NAMESPACE + '/bulk/get'
        with patch('urllib.request.build_opener') as factory:
            factory.return_value.open.return_value = Result()
            Client('offline-only').bulk_get(path, ['key'])
            request = factory.return_value.open.call_args[0][0]
            self.assertEqual(request.get_method(), 'POST')
            self.assertEqual(json.loads(request.data), {'keys': ['key'], 'type': 'text', 'withMetadata': True})
        for other_path in (path.replace('/get', '/delete'), path.replace('/bulk/get', '/bulk'), path + '?write=true'):
            with self.assertRaises(BackupError):
                Client('offline-only').bulk_get(other_path, ['key'])
        for body in ({'keys': ['key'], 'type': 'json', 'withMetadata': True}, {'keys': ['key'], 'type': 'text', 'withMetadata': True, 'value': 'write'}):
            with self.assertRaises(BackupError):
                Client('offline-only').request('POST', path, body)
        with self.assertRaises(BackupError):
            Client('offline-only').bulk_get(path, ['key'] * 101)

    def test_token_file_read_without_credential_output(self):
        credentials = Path(self.temp.name) / 'default.toml'
        credentials.write_text('oauth_token = "offline-fixture-only"\n')
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(load_token(str(credentials)), 'offline-fixture-only')


if __name__ == '__main__':
    unittest.main()
