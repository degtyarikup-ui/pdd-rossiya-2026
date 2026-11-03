#!/usr/bin/python3
"""Publishes a built release to Google Play, App Store Connect and RuStore.

Keys never live in this public repository: they are read from the macOS
login Keychain (services `codex.pdd-russia.*`, see docs/release/store-api.md)
and are never printed. Tokens exist only in this process.

  /usr/bin/python3 tools/store_release/publish.py status
  /usr/bin/python3 tools/store_release/publish.py play    <app.aab> <notes.json>
  /usr/bin/python3 tools/store_release/publish.py appstore <build> <notes.json>
  /usr/bin/python3 tools/store_release/publish.py rustore <app.apk> <notes.json>

notes.json: {"version": "2.2.7", "ru": "...", "en": "...", "kk": "..."}.
Every store publishes automatically after approval (owner's policy).
Runs on the system Python, which ships `cryptography`.
"""
import base64
import datetime
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.client import HTTPException
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

ANDROID_PACKAGE = 'ru.pdd.pdd_app'
IOS_BUNDLE = 'ru.pdd.pddApp'
ASC_KEY_ID = 'G3JJFBDVMQ'
ASC_ISSUER = 'be47fdd6-0b1d-402a-95ea-e9e54805578d'
PLAY_ACCOUNT = 'codex-releases@gen-lang-client-0736141197.iam.gserviceaccount.com'
RUSTORE_KEY_ID = '2351034241'
INTEGRATIONS = Path.home() / 'Library/Application Support/CodexIntegrations'
# RuStore uses certificates of the Russian Trusted CA (Gosuslugi).
RUSTORE_CA = INTEGRATIONS / 'rustore/ca-bundle.pem'


def keychain(service, account):
    out = subprocess.run(
        ['/usr/bin/security', 'find-generic-password', '-s', service, '-a', account, '-w'],
        capture_output=True, text=True,
    )
    if out.returncode:
        sys.exit(f'В Связке ключей нет {service} ({account})')
    value = out.stdout.strip()
    # `security -w` prints hex when the secret contains line breaks.
    try:
        return bytes.fromhex(value)
    except ValueError:
        return value.encode()


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def jwt(header, claims, sign):
    head = b64url(json.dumps(header).encode()) + '.' + b64url(json.dumps(claims).encode())
    return head + '.' + b64url(sign(head.encode()))


class HttpError(SystemExit):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


class FileBody:
    """A file (optionally wrapped in multipart) streamed by urllib."""

    def __init__(self, path, prefix=b'', suffix=b''):
        self.parts = [prefix, open(path, 'rb'), suffix]
        self.length = len(prefix) + os.path.getsize(path) + len(suffix)

    def read(self, size=1 << 20):
        while self.parts:
            part = self.parts[0]
            chunk = part.read(size) if hasattr(part, 'read') else part
            if chunk:
                if not hasattr(part, 'read'):
                    self.parts.pop(0)
                return chunk
            if hasattr(part, 'close'):
                part.close()
            self.parts.pop(0)
        return b''


def http(method, url, headers=None, body=None, context=None, timeout=120):
    headers = dict(headers or {})
    data = body
    if isinstance(body, (dict, list)):
        data = json.dumps(body).encode()
        headers.setdefault('Content-Type', 'application/json')
    if isinstance(body, FileBody):
        headers['Content-Length'] = str(body.length)
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, context=context, timeout=timeout) as response:
            text = response.read().decode()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors='replace')[:1500]
        raise HttpError(error.code, f'{method} {url.split("?")[0]} → HTTP {error.code}: {detail}') from None
    return json.loads(text) if text.strip() else {}


# ── Google Play ──────────────────────────────────────────────────────────────

class Play:
    BASE = f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{ANDROID_PACKAGE}'
    UPLOAD = f'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{ANDROID_PACKAGE}'

    def __init__(self, scope='https://www.googleapis.com/auth/androidpublisher'):
        info = json.loads(keychain('codex.pdd-russia.googleplay', PLAY_ACCOUNT))
        key = serialization.load_pem_private_key(info['private_key'].encode(), None)
        now = int(time.time())
        assertion = jwt(
            {'alg': 'RS256', 'typ': 'JWT'},
            {'iss': info['client_email'], 'scope': scope,
             'aud': info['token_uri'], 'iat': now, 'exp': now + 3600},
            lambda m: key.sign(m, padding.PKCS1v15(), hashes.SHA256()),
        )
        token = http('POST', info['token_uri'], {'Content-Type': 'application/x-www-form-urlencoded'},
                     urllib.parse.urlencode({'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                                             'assertion': assertion}).encode())
        self.auth = {'Authorization': 'Bearer ' + token['access_token']}

    def call(self, method, path, body=None, upload=False, timeout=120):
        return http(method, (self.UPLOAD if upload else self.BASE) + path, self.auth, body, timeout=timeout)

    def status(self):
        edit = self.call('POST', '/edits')['id']
        try:
            for release in self.call('GET', f'/edits/{edit}/tracks/production').get('releases', []):
                print('Google Play production:', release.get('name'), release.get('status'),
                      release.get('versionCodes'))
        finally:
            self.call('DELETE', f'/edits/{edit}')

    def upload_resumable(self, url, path, chunk=8 << 20, attempts=8):
        """Uploads in 8 MB pieces; a dropped connection resumes from the last stored byte.
        A single 290 MB request was reset by the network twice in a row (2.2.8)."""
        size = os.path.getsize(path)
        start = urllib.request.Request(url + '?uploadType=resumable', data=b'', method='POST', headers={
            **self.auth, 'X-Upload-Content-Type': 'application/octet-stream',
            'X-Upload-Content-Length': str(size), 'Content-Length': '0'})
        with urllib.request.urlopen(start, timeout=120) as response:
            session = response.headers['Location']
        offset, failures = 0, 0
        with open(path, 'rb') as file:
            while True:
                file.seek(offset)
                data = file.read(chunk)
                end = offset + len(data) - 1
                request = urllib.request.Request(session, data=data, method='PUT', headers={
                    'Content-Length': str(len(data)), 'Content-Range': f'bytes {offset}-{end}/{size}'})
                try:
                    with urllib.request.urlopen(request, timeout=300) as response:
                        return json.loads(response.read().decode())
                except urllib.error.HTTPError as error:
                    if error.code != 308:
                        if error.code < 500:
                            raise HttpError(error.code, f'upload → HTTP {error.code}: '
                                            f'{error.read().decode(errors="replace")[:1500]}') from None
                        failures += 1
                    else:
                        failures = 0
                        stored = error.headers.get('Range')
                        offset = int(stored.split('-')[1]) + 1 if stored else 0
                        continue
                except (OSError, HTTPException) as error:
                    failures += 1
                    print('Google Play: обрыв загрузки, продолжаю:', error)
                if failures >= attempts:
                    raise RuntimeError('Google Play: загрузка AAB не удалась')
                time.sleep(min(30, 2 ** failures))
                # Ask how much the server has stored before resending.
                probe = urllib.request.Request(session, data=b'', method='PUT', headers={
                    'Content-Length': '0', 'Content-Range': f'bytes */{size}'})
                try:
                    with urllib.request.urlopen(probe, timeout=120) as response:
                        return json.loads(response.read().decode())
                except urllib.error.HTTPError as error:
                    if error.code == 308:
                        stored = error.headers.get('Range')
                        offset = int(stored.split('-')[1]) + 1 if stored else 0
                except (OSError, HTTPException):
                    pass

    def publish(self, aab, notes):
        edit = self.call('POST', '/edits')['id']
        try:
            bundle = self.upload_resumable(f'{self.UPLOAD}/edits/{edit}/bundles', aab)
            code = str(bundle['versionCode'])
            print('Google Play: загружен AAB, versionCode', code)
            self.call('PUT', f'/edits/{edit}/tracks/production', {
                'track': 'production',
                'releases': [{
                    'name': notes['version'], 'versionCodes': [code], 'status': 'completed',
                    'releaseNotes': [{'language': lang, 'text': notes[key]}
                                     for lang, key in (('ru-RU', 'ru'), ('en-US', 'en'), ('kk', 'kk'))],
                }],
            })
            # Without managed publishing changes go to review on commit; the
            # changesNotSentForReview flag is rejected in this state.
            self.call('POST', f'/edits/{edit}:commit')
            print('Google Play: релиз', notes['version'], f'({code}) отправлен на проверку')
        except BaseException:
            try:
                self.call('DELETE', f'/edits/{edit}')
            except BaseException:
                pass
            raise


# ── App Store Connect ────────────────────────────────────────────────────────

class AppStore:
    API = 'https://api.appstoreconnect.apple.com'

    def __init__(self):
        self.key = serialization.load_pem_private_key(
            keychain('codex.pdd-russia.appstoreconnect', ASC_KEY_ID), None)

    def token(self):
        now = int(time.time())

        def sign(message):
            r, s = decode_dss_signature(self.key.sign(message, ec.ECDSA(hashes.SHA256())))
            return r.to_bytes(32, 'big') + s.to_bytes(32, 'big')

        return jwt({'alg': 'ES256', 'kid': ASC_KEY_ID, 'typ': 'JWT'},
                   {'iss': ASC_ISSUER, 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'}, sign)

    def call(self, method, path, body=None, **query):
        url = self.API + path + ('?' + urllib.parse.urlencode(query) if query else '')
        for attempt in range(3):
            try:
                return http(method, url, {'Authorization': 'Bearer ' + self.token()}, body)
            except HttpError as error:
                # App Store Connect sometimes answers UNEXPECTED_ERROR (500) once;
                # every step here is idempotent, so a short retry is safe.
                if error.status < 500 or attempt == 2:
                    raise
                time.sleep(20)

    def app(self):
        return self.call('GET', '/v1/apps', **{'filter[bundleId]': IOS_BUNDLE})['data'][0]['id']

    def editable_version(self, app):
        for version in self.call('GET', f'/v1/apps/{app}/appStoreVersions', limit=5)['data']:
            if version['attributes']['appStoreState'] in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED',
                                                         'REJECTED', 'METADATA_REJECTED'):
                return version
        return None

    def status(self):
        app = self.app()
        for version in self.call('GET', f'/v1/apps/{app}/appStoreVersions', limit=3)['data']:
            a = version['attributes']
            print('App Store:', a['versionString'], a['appStoreState'], a.get('releaseType'))

    def publish(self, build_number, notes):
        app = self.app()
        version = self.editable_version(app)
        if version is None:
            version = self.call('POST', '/v1/appStoreVersions', {'data': {
                'type': 'appStoreVersions',
                'attributes': {'platform': 'IOS', 'versionString': notes['version'],
                               'releaseType': 'AFTER_APPROVAL'},
                'relationships': {'app': {'data': {'type': 'apps', 'id': app}}}}})['data']
        if version['attributes']['versionString'] != notes['version']:
            sys.exit(f"Редактируемая версия в ASC — {version['attributes']['versionString']}, "
                     f"а не {notes['version']}")
        if version['attributes'].get('releaseType') != 'AFTER_APPROVAL':
            self.call('PATCH', f"/v1/appStoreVersions/{version['id']}", {'data': {
                'type': 'appStoreVersions', 'id': version['id'],
                'attributes': {'releaseType': 'AFTER_APPROVAL'}}})
        build = None
        for _ in range(90):  # Apple processes an upload in 5–40 minutes.
            found = self.call('GET', '/v1/builds', **{
                'filter[app]': app, 'filter[version]': str(build_number),
                'filter[preReleaseVersion.version]': notes['version']})['data']
            build = found[0] if found else None
            state = build['attributes']['processingState'] if build else 'NOT_FOUND'
            if state == 'VALID':
                break
            if state in ('FAILED', 'INVALID'):
                sys.exit(f'Apple отклонил сборку {build_number}: {state}')
            print(f'App Store: сборка {build_number} — {state}, жду…', flush=True)
            time.sleep(60)
        else:
            sys.exit(f'Сборка {build_number} не обработана Apple за 90 минут')
        if build['attributes'].get('usesNonExemptEncryption') is None:
            self.call('PATCH', f"/v1/builds/{build['id']}", {'data': {
                'type': 'builds', 'id': build['id'], 'attributes': {'usesNonExemptEncryption': False}}})
        self.call('PATCH', f"/v1/appStoreVersions/{version['id']}/relationships/build",
                  {'data': {'type': 'builds', 'id': build['id']}})
        for loc in self.call('GET', f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']:
            lang = loc['attributes']['locale'].split('-')[0]
            text = notes.get(lang) or notes['ru']
            self.call('PATCH', f"/v1/appStoreVersionLocalizations/{loc['id']}", {'data': {
                'type': 'appStoreVersionLocalizations', 'id': loc['id'], 'attributes': {'whatsNew': text}}})
        submission = None
        for item in self.call('GET', '/v1/reviewSubmissions', **{
                'filter[app]': app, 'filter[state]': 'READY_FOR_REVIEW', 'filter[platform]': 'IOS'})['data']:
            submission = item
        if submission is None:
            submission = self.call('POST', '/v1/reviewSubmissions', {'data': {
                'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
                'relationships': {'app': {'data': {'type': 'apps', 'id': app}}}}})['data']
        items = self.call('GET', f"/v1/reviewSubmissions/{submission['id']}/items")['data']
        if not items:
            self.call('POST', '/v1/reviewSubmissionItems', {'data': {
                'type': 'reviewSubmissionItems', 'relationships': {
                    'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': submission['id']}},
                    'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}}}})
        self.call('PATCH', f"/v1/reviewSubmissions/{submission['id']}", {'data': {
            'type': 'reviewSubmissions', 'id': submission['id'], 'attributes': {'submitted': True}}})
        print('App Store:', notes['version'], f'({build_number}) отправлена на проверку, '
              'публикация автоматически после одобрения')


# ── RuStore ──────────────────────────────────────────────────────────────────

class RuStore:
    BASE = 'https://public-api-m.rustore.ru'

    def __init__(self):
        self.context = ssl.create_default_context(cafile=str(RUSTORE_CA))
        key = serialization.load_der_private_key(
            base64.b64decode(keychain('codex.pdd-russia.rustore', RUSTORE_KEY_ID)), None)
        stamp = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds')
        signature = base64.b64encode(
            key.sign((RUSTORE_KEY_ID + stamp).encode(), padding.PKCS1v15(), hashes.SHA512())).decode()
        auth = self.call('POST', '/public/auth/', {'keyId': RUSTORE_KEY_ID, 'timestamp': stamp,
                                                    'signature': signature}, token=False)
        self.token = auth['body']['jwe']

    def call(self, method, path, body=None, token=True, headers=None, timeout=120):
        headers = dict(headers or {})
        if token:
            headers['Public-Token'] = self.token
        result = http(method, self.BASE + path, headers, body, self.context, timeout)
        if result.get('code') not in ('OK', 0, '0', None):
            sys.exit(f'RuStore {path}: {result.get("code")} {result.get("message")}')
        return result

    def versions(self):
        path = f'/public/v1/application/{ANDROID_PACKAGE}/version?page=0&size=5'
        return self.call('GET', path)['body'].get('content') or []

    def status(self):
        for v in self.versions()[:3]:
            print('RuStore:', v['versionName'], v['versionCode'], v['versionStatus'], v.get('publishType'))

    def draft_has_apk(self, version_id, wait=180):
        deadline = time.time() + wait
        while time.time() < deadline:
            time.sleep(15)
            draft = next((v for v in self.versions() if v['versionId'] == version_id), None)
            if draft and draft.get('versionCode', -1) > 0:
                return True
        return False

    def publish(self, apk, notes):
        app = f'/public/v1/application/{ANDROID_PACKAGE}/version'
        for attempt in range(1, 6):
            # A new draft replaces any earlier one; other fields copy from the
            # active version. A fresh draft per attempt matters: RuStore's proxy
            # can answer 503 although the APK did arrive, and a second main APK
            # in the same draft cannot be submitted.
            created = self.call('POST', app, {'whatsNew': notes['ru'], 'publishType': 'INSTANTLY'})['body']
            version_id = created['versionId'] if isinstance(created, dict) else created
            boundary = uuid.uuid4().hex
            prefix = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
                      f'filename="{Path(apk).name}"\r\n'
                      'Content-Type: application/vnd.android.package-archive\r\n\r\n').encode()
            body = FileBody(apk, prefix, f'\r\n--{boundary}--\r\n'.encode())
            try:
                self.call('POST', f'{app}/{version_id}/apk?servicesType=Unknown&isMainApk=true', body,
                          headers={'Content-Type': f'multipart/form-data; boundary={boundary}'}, timeout=3600)
                break
            except HttpError as error:
                if error.status < 500 or attempt == 5:
                    raise
                print(f'RuStore: загрузка APK оборвалась (HTTP {error.status}), повтор {attempt + 1}/5', flush=True)
            except (OSError, HTTPException) as error:
                # RuStore's proxy resets the connection after receiving the whole APK
                # (2.2.8): the draft gets the build a few seconds later.
                if self.draft_has_apk(version_id):
                    break
                if attempt == 5:
                    raise
                print(f'RuStore: обрыв загрузки APK ({error}), повтор {attempt + 1}/5', flush=True)
                time.sleep(10 * attempt)
        print('RuStore: APK загружен в черновик', version_id)
        self.call('POST', f'{app}/{version_id}/commit')
        print('RuStore: версия', notes['version'], 'отправлена на модерацию, публикация сразу после неё')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command = sys.argv[1]
    if command == 'status':
        Play().status()
        AppStore().status()
        RuStore().status()
        return
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    target, notes = sys.argv[2], json.loads(Path(sys.argv[3]).read_text())
    for key in ('version', 'ru', 'en', 'kk'):
        if not notes.get(key):
            sys.exit(f'В {sys.argv[3]} нет поля {key}')
    if len(notes['ru']) > 500 or len(notes['en']) > 500 or len(notes['kk']) > 500:
        sys.exit('Google Play принимает до 500 символов «Что нового» на язык')
    if command == 'play':
        Play().publish(target, notes)
    elif command == 'appstore':
        AppStore().publish(int(target), notes)
    elif command == 'rustore':
        RuStore().publish(target, notes)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
