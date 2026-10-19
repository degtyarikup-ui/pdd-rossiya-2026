#!/usr/bin/env python3
"""Read-only, resumable Cloudflare Worker/KV backup (Python 3.9+, stdlib).

All requests are reads: GETs and the exact KV bulk/get POST at api.cloudflare.com.
The destination contains
personal data and tokens; encrypt it before moving or retaining it elsewhere.
Durable Object inventories are NOT Durable Object data backups. Production
AccountState data, private Apple tokens, queues and alarms cannot be exported by
the documented REST endpoints used here. No restore command is provided.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request


API = 'https://api.cloudflare.com/client/v4'
FORMAT_VERSION = 1


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink():
        raise ValueError('Backup destination must not be a symbolic link')
    path.chmod(0o700)


def private_write(path, data):
    private_dir(path.parent)
    temporary = path.with_name(path.name + '.partial')
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(str(temporary), flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(path))
        path.chmod(0o600)
    except BaseException:
        if temporary.exists():
            temporary.unlink()
        raise


def write_json(path, value):
    private_write(path, (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode())


class BackupError(Exception):
    pass


class ApiError(BackupError):
    def __init__(self, status):
        self.status = status
        super().__init__('Cloudflare API request failed (HTTP {})'.format(status))


def load_token(credentials_file=None):
    token = os.environ.get('CLOUDFLARE_API_TOKEN')
    if token:
        return token
    candidates = [Path(credentials_file)] if credentials_file else [
        Path.home() / 'Library/Preferences/.wrangler/config/default.toml',
        Path.home() / '.config/.wrangler/config/default.toml',
        Path.home() / '.wrangler/config/default.toml',
    ]
    for path in candidates:
        if path.is_file():
            match = re.search(r'^\s*oauth_token\s*=\s*"([^"\r\n]+)"', path.read_text(), re.M)
            if match:
                return match.group(1)
    raise BackupError('Set CLOUDFLARE_API_TOKEN or supply a Wrangler credentials file')


class Client:
    def __init__(self, token, attempts=4):
        self.token = token
        self.attempts = attempts
        self.last_request_at = 0.0

    def get(self, path):
        return self.request('GET', path)

    def bulk_get(self, path, keys):
        return self.request('POST', path, {'keys': keys, 'type': 'text', 'withMetadata': True})

    def request(self, method, path, body=None):
        if not path.startswith('/') or '://' in path or '\r' in path or '\n' in path:
            raise BackupError('Invalid API path')
        if method == 'POST':
            if not re.fullmatch(r'/accounts/[a-fA-F0-9]{32}/storage/kv/namespaces/[a-fA-F0-9]{32}/bulk/get', path):
                raise BackupError('Only the read-only KV bulk/get POST is allowed')
            if not isinstance(body, dict) or set(body) != {'keys', 'type', 'withMetadata'} or body['type'] != 'text' or body['withMetadata'] is not True:
                raise BackupError('Invalid read-only KV bulk/get body')
            if not isinstance(body['keys'], list) or not 1 <= len(body['keys']) <= 100 or any(not isinstance(key, str) for key in body['keys']):
                raise BackupError('KV bulk/get requires 1..100 string keys')
        elif method != 'GET' or body is not None:
            raise BackupError('Only read-only Cloudflare operations are allowed')
        request = Request(API + path, method=method, data=json.dumps(body, ensure_ascii=False).encode() if body is not None else None, headers={
            'Authorization': 'Bearer ' + self.token,
            'User-Agent': 'pdd-domain-migration-readonly-backup/1',
            **({'Content-Type': 'application/json'} if body is not None else {}),
        })
        # Cloudflare's API should not redirect. Disable redirects to prevent
        # forwarding authorization if an endpoint's behavior changes.
        from urllib.request import HTTPRedirectHandler, build_opener

        class RejectRedirect(HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None

        opener = build_opener(RejectRedirect())
        for attempt in range(self.attempts):
            # Account control API rate limit is shared with other tools.
            # Stay below four reads per second even on very small responses.
            time.sleep(max(0, 0.26 - (time.monotonic() - self.last_request_at)))
            self.last_request_at = time.monotonic()
            try:
                with opener.open(request, timeout=30) as response:
                    return response.read(), dict(response.headers)
            except HTTPError as error:
                status = error.code
                # Never emit the error body: Cloudflare can include names or
                # copied request fields in error messages.
                error.close()
                if status not in (429, 500, 502, 503, 504) or attempt + 1 == self.attempts:
                    raise ApiError(status) from None
            except (URLError, TimeoutError, OSError):
                if attempt + 1 == self.attempts:
                    raise BackupError('Cloudflare API transport failed; rerun to resume') from None
            time.sleep(min(2 ** attempt, 8))
        raise BackupError('Cloudflare API retry limit reached')


class Collector:
    def __init__(self, client, output, account_id, script):
        self.client = client
        self.output = Path(output).absolute()
        self.account_id = account_id
        self.script = script
        private_dir(self.output)
        self.journal = self.output / 'requests.jsonl'
        self.records = {}
        if self.journal.exists():
            self.journal.chmod(0o600)
            journal_data = self.journal.read_bytes()
            # A process may die during the final append. The captured file is
            # safe to refetch if that journal entry never completed.
            if journal_data and not journal_data.endswith(b'\n'):
                journal_data = journal_data[:journal_data.rfind(b'\n') + 1]
                private_write(self.journal, journal_data)
            for line in journal_data.decode().splitlines():
                try:
                    entry = json.loads(line)
                except ValueError:
                    raise BackupError('Invalid backup journal; preserve it and use a new output directory') from None
                self.records[entry.get('request_key', entry['path'])] = entry
        metadata = self.output / 'backup.json'
        if metadata.exists():
            self.metadata = json.loads(metadata.read_text())
            if (self.metadata.get('account_id'), self.metadata.get('script'), self.metadata.get('format_version')) != (account_id, script, FORMAT_VERSION):
                raise BackupError('Existing backup belongs to a different account, Worker, or format')
        else:
            if self.records:
                raise BackupError('Backup identity is missing; preserve this output directory')
            self.metadata = {
                'format_version': FORMAT_VERSION, 'account_id': account_id,
                'script': script, 'started_at': now(), 'method': 'Read-only Cloudflare GET and KV bulk/get POST',
            }
            write_json(metadata, self.metadata)
        self.metadata['method'] = 'Read-only Cloudflare GET and KV bulk/get POST'
        write_json(metadata, self.metadata)
        self.base = '/accounts/' + quote(account_id, safe='')
        self.worker = self.base + '/workers/scripts/' + quote(script, safe='')
        self.optional_failures = []

    def reuse(self, request_key):
        entry = self.records.get(request_key)
        if entry:
            target = self.output / entry['file']
            if not target.is_file() or target.is_symlink() or digest(target.read_bytes()) != entry['sha256']:
                raise BackupError('A saved backup file failed integrity verification')
            return target.read_bytes(), entry
        return None, None

    def save_capture(self, path, label, data, headers=None, request_key=None, source=None):
        request_key = request_key or path
        name = 'captures/' + digest(request_key.encode()) + '.bin'
        private_write(self.output / name, data)
        entry = {
            'path': path, 'request_key': request_key, 'resource': label, 'file': name,
            'sha256': digest(data), 'bytes': len(data), 'captured_at': now(),
            'content_type': (headers or {}).get('Content-Type', (headers or {}).get('content-type', '')),
        }
        if source:
            entry['source'] = source
        flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0)
        fd = os.open(str(self.journal), flags, 0o600)
        with os.fdopen(fd, 'a') as journal:
            os.fchmod(journal.fileno(), 0o600)
            journal.write(json.dumps(entry, ensure_ascii=False) + '\n')
            journal.flush()
            os.fsync(journal.fileno())
        self.records[request_key] = entry
        return data, entry

    def get(self, path, label, optional=False):
        data, entry = self.reuse(path)
        if entry:
            return data, entry
        try:
            data, headers = self.client.get(path)
        except ApiError as error:
            if optional and error.status in (400, 403, 404):
                self.optional_failures.append({'resource': label, 'http_status': error.status})
                return None, None
            raise
        return self.save_capture(path, label, data, headers)

    def bulk(self, path, keys):
        payload = {'keys': keys, 'type': 'text', 'withMetadata': True}
        request_key = 'POST ' + path + '#' + digest(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode())
        data, entry = self.reuse(request_key)
        if not entry:
            data, headers = self.client.bulk_get(path, keys)
            data, entry = self.save_capture(path, 'KV bulk text read', data, headers, request_key)
        try:
            body = json.loads(data)
            if body.get('success') is not True or not isinstance(body.get('result', {}).get('values'), dict):
                raise ValueError()
        except (ValueError, AttributeError):
            raise BackupError('Cloudflare did not return valid bulk text values') from None
        return body['result']['values'], entry

    def prefetch_kv(self, base, keys):
        def binary(key):
            metadata = key.get('metadata')
            mime = metadata.get('type', '') if isinstance(metadata, dict) else ''
            return key['name'].startswith('ntimg:') or str(mime).startswith(('image/', 'audio/', 'video/', 'application/octet-stream'))

        pending = [key for key in keys if not binary(key) and base + '/values/' + quote(key['name'], safe='') not in self.records]

        def batch_read(batch):
            try:
                values, capture = self.bulk(base + '/bulk/get', [key['name'] for key in batch])
            except ApiError as error:
                if error.status not in (400, 413, 422):
                    raise
                if len(batch) > 1:
                    middle = len(batch) // 2
                    batch_read(batch[:middle])
                    batch_read(batch[middle:])
                # A single unsupported value will use the raw GET below.
                return
            for key in batch:
                item = values.get(key['name'])
                value = item.get('value') if isinstance(item, dict) else None
                if not isinstance(value, str) or '\ufffd' in value or '\x00' in value or value.startswith('\ufeff'):
                    continue
                try:
                    data = value.encode('utf-8', errors='strict')
                except UnicodeError:
                    continue
                path = base + '/values/' + quote(key['name'], safe='')
                self.save_capture(path, 'KV value', data, source={
                    'method': 'POST bulk/get type=text', 'response_file': capture['file'],
                    'metadata': item.get('metadata'), 'expiration': item.get('expiration'),
                })

        for offset in range(0, len(pending), 100):
            batch_read(pending[offset:offset + 100])
            print(json.dumps({'phase': 'kv-bulk-read', 'processed': min(offset + 100, len(pending)), 'listed': len(keys)}), file=sys.stderr, flush=True)

    def get_json(self, path, label, optional=False):
        data, entry = self.get(path, label, optional)
        if data is None:
            return None
        try:
            body = json.loads(data)
        except ValueError:
            raise BackupError('Cloudflare API returned invalid JSON for ' + label) from None
        if not isinstance(body, dict) or body.get('success') is not True:
            raise BackupError('Cloudflare API did not confirm success for ' + label)
        return body

    def page_list(self, path, label, per_page=100):
        result, page = [], 1
        while True:
            separator = '&' if '?' in path else '?'
            body = self.get_json(path + separator + urlencode({'page': page, 'per_page': per_page}), label)
            rows = body.get('result', [])
            if not isinstance(rows, list):
                raise BackupError('Unexpected list response for ' + label)
            result.extend(rows)
            info = body.get('result_info', {})
            total_pages = info.get('total_pages')
            if total_pages is not None:
                if page >= total_pages:
                    break
            elif len(rows) < per_page:
                break
            page += 1
            if page > 100000:
                raise BackupError('Pagination limit reached for ' + label)
        return result

    def cursor_list(self, path, label, limit=1000):
        rows, cursor, seen = [], None, set()
        while True:
            params = {'limit': limit}
            if cursor:
                params['cursor'] = cursor
            body = self.get_json(path + '?' + urlencode(params), label)
            batch = body.get('result', [])
            if not isinstance(batch, list):
                raise BackupError('Unexpected cursor response for ' + label)
            rows.extend(batch)
            info = body.get('result_info', {})
            next_cursor = info.get('cursor') or (info.get('cursors') or {}).get('after')
            if not next_cursor:
                if body.get('list_complete') is False or info.get('list_complete') is False:
                    raise BackupError('Incomplete cursor boundary for ' + label)
                break
            if next_cursor in seen:
                raise BackupError('Repeated pagination cursor for ' + label)
            seen.add(next_cursor)
            cursor = next_cursor
        return rows

    def backup_kv(self, namespace_id):
        base = self.base + '/storage/kv/namespaces/' + quote(namespace_id, safe='')
        keys = self.cursor_list(base + '/keys', 'KV keys')
        names = [key.get('name') for key in keys]
        if any(not isinstance(name, str) for name in names) or len(set(names)) != len(names):
            raise BackupError('KV listing contains invalid or repeated key names')
        self.prefetch_kv(base, keys)
        entries = []
        for key in keys:
            path = base + '/values/' + quote(key['name'], safe='')
            data, capture = self.get(path, 'KV value', optional=True)
            entry = {'name': key['name'], 'metadata': key.get('metadata'), 'expiration': key.get('expiration')}
            if data is None:
                status = self.optional_failures[-1]['http_status']
                # A 403 is an access failure, not a disappeared key.
                if status != 404:
                    raise ApiError(status)
                entry['status'] = 'missing_at_read'
                entry['read_at'] = now()
            else:
                entry.update({
                    'status': 'captured', 'file': capture['file'],
                    'sha256': capture['sha256'], 'bytes': capture['bytes'],
                    'captured_at': capture['captured_at'],
                })
                if capture.get('source'):
                    entry['source'] = capture['source']
            entries.append(entry)
            if len(entries) % 100 == 0:
                print(json.dumps({'phase': 'kv-values', 'processed': len(entries), 'listed': len(keys)}), file=sys.stderr, flush=True)
        index = {'namespace_id': namespace_id, 'keys': entries, 'listing_complete': True, 'index_written_at': now()}
        relative = 'kv/' + namespace_id + '.json'
        write_json(self.output / relative, index)
        return {
            'namespace_id': namespace_id, 'index': relative, 'listing_complete': True,
            'listed_keys': len(entries), 'captured_keys': sum(item['status'] == 'captured' for item in entries),
            'missing_at_read': sum(item['status'] != 'captured' for item in entries),
            'all_listed_values_captured': all(item['status'] == 'captured' for item in entries),
            'atomic_snapshot': False,
            'bytes': sum(item.get('bytes', 0) for item in entries),
        }

    def collect(self, namespace_ids=None, zone_ids=None):
        settings = self.get_json(self.worker + '/settings', 'Worker settings')['result']
        self.get(self.worker, 'Worker source')
        self.get_json(self.worker + '/deployments', 'Worker deployments')
        for suffix, label in [('/versions', 'Worker versions'),
                              ('/secrets', 'Worker secret names'), ('/schedules', 'Worker schedules')]:
            self.get_json(self.worker + suffix, label, optional=True)
        self.get_json(self.base + '/workers/subdomain', 'Workers subdomain', optional=True)
        self.get_json(self.base + '/workers/domains', 'Worker custom domains', optional=True)
        zones = []
        for identifier in sorted(set(zone_ids or [])):
            base = '/zones/' + quote(identifier, safe='')
            self.get_json(base, 'Zone configuration')
            try:
                records = self.page_list(base + '/dns_records', 'DNS records')
                dns_records_captured = True
            except ApiError as error:
                if error.status != 403:
                    raise
                # An OAuth token can read zone metadata without DNS.read.
                # Preserve that explicit coverage gap and continue KV/DO.
                self.optional_failures.append({'resource': 'DNS records', 'http_status': error.status})
                records = None
                dns_records_captured = False
            self.get_json(base + '/dnssec', 'Zone DNSSEC', optional=True)
            self.get_json(base + '/workers/routes', 'Zone Worker routes', optional=True)
            relative = 'zones/' + identifier + '.json'
            write_json(self.output / relative, {
                'zone_id': identifier, 'dns_records': records,
                'dns_records_captured': dns_records_captured, 'listing_complete': dns_records_captured,
            })
            zones.append({'zone_id': identifier, 'index': relative,
                          'dns_records': len(records) if records is not None else None,
                          'dns_records_captured': dns_records_captured})
        if not namespace_ids:
            bindings = settings.get('bindings', [])
            namespace_ids = sorted({binding['namespace_id'] for binding in bindings
                                    if binding.get('type') == 'kv_namespace' and binding.get('namespace_id')})
        if not namespace_ids:
            raise BackupError('No bound KV namespaces found; specify --kv-namespace explicitly')
        kv = [self.backup_kv(identifier) for identifier in sorted(set(namespace_ids))]
        namespaces = self.page_list(self.base + '/workers/durable_objects/namespaces', 'DO namespaces')
        durable = []
        for namespace in namespaces:
            if namespace.get('script') != self.script:
                continue
            identifier = namespace['id']
            objects = self.cursor_list(self.base + '/workers/durable_objects/namespaces/' + quote(identifier, safe='') + '/objects', 'DO object inventory')
            relative = 'durable_objects/' + identifier + '.json'
            write_json(self.output / relative, {'namespace': namespace, 'objects': objects, 'inventory_complete': True, 'data_exported': False})
            durable.append({
                'namespace_id': identifier, 'class': namespace.get('class'), 'inventory': relative,
                'objects': len(objects), 'objects_with_stored_data': sum(bool(item.get('hasStoredData')) for item in objects),
                'inventory_complete': True, 'data_exported': False,
            })
        expected_classes = {binding.get('class_name') for binding in settings.get('bindings', [])
                            if binding.get('type') == 'durable_object_namespace'
                            and binding.get('script_name', self.script) == self.script}
        inventoried_classes = {item['class'] for item in durable}
        manifest = {
            **self.metadata, 'completed_at': now(), 'collection_complete': True,
            'full_data_backup': False, 'production_mutations': False,
            'worker_source_captured': True, 'worker_settings_captured': True,
            'worker_deployments_baseline_captured': True,
            'kv_all_listed_values_captured': all(item['all_listed_values_captured'] for item in kv),
            'do_expected_classes_inventoried': expected_classes.issubset(inventoried_classes),
            'kv': kv, 'durable_objects': durable, 'zones': zones,
            'optional_resource_failures': self.optional_failures,
            'limitations': [
                'Durable Object storage, chunks, outboxes, alarms and private Apple tokens are NOT exported.',
                'Worker encrypted secret values cannot be read from this API; secret names only are captured.',
                'KV is a live, eventually consistent projection, not an atomic snapshot or AccountState authority.',
                'Concurrent KV writes/deletions/expiration can change data during enumeration and reads.',
                'Resuming reuses integrity-verified captures; this preserves the original collection window.',
                'KV absolute expiration and metadata are preserved in indexes; nothing is restored automatically.',
                'Guest browser-only progress and device-local data are not accessible from Cloudflare.',
            ],
            'captures': len(self.records),
        }
        write_json(self.output / 'manifest.json', manifest)
        return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--account-id', required=True)
    parser.add_argument('--script', default='pdd-install-notifier')
    parser.add_argument('--output', required=True)
    parser.add_argument('--credentials-file')
    parser.add_argument('--kv-namespace', action='append', default=[])
    parser.add_argument('--zone-id', action='append', default=[])
    args = parser.parse_args(argv)
    os.umask(0o077)
    try:
        if not re.fullmatch(r'[a-fA-F0-9]{32}', args.account_id):
            raise BackupError('Account ID must be 32 hexadecimal characters')
        if any(not re.fullmatch(r'[a-fA-F0-9]{32}', identifier) for identifier in args.kv_namespace):
            raise BackupError('KV namespace IDs must be 32 hexadecimal characters')
        if any(not re.fullmatch(r'[a-fA-F0-9]{32}', identifier) for identifier in args.zone_id):
            raise BackupError('Zone IDs must be 32 hexadecimal characters')
        manifest = Collector(Client(load_token(args.credentials_file)), args.output, args.account_id, args.script).collect(args.kv_namespace, args.zone_id)
        # Only aggregate counts; never key names, user data, tokens or API bodies.
        print(json.dumps({
            'collection_complete': True, 'full_data_backup': False,
            'kv_namespaces': len(manifest['kv']),
            'kv_values': sum(item['captured_keys'] for item in manifest['kv']),
            'kv_missing_at_read': sum(item['missing_at_read'] for item in manifest['kv']),
            'do_namespaces_inventoried': len(manifest['durable_objects']),
            'do_data_exported': False,
        }))
        return 0
    except (BackupError, ValueError, OSError) as error:
        # OS exceptions may include private paths; do not print them.
        detail = str(error) if isinstance(error, BackupError) else 'Local backup operation failed'
        print('Backup incomplete: ' + detail, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
