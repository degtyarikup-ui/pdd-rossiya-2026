"""Android build helpers: offline tests with fake upstream data and local HTTP."""
import concurrent.futures
import contextlib
import hashlib
import http.client
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_dev
import download
import environment
import maven_bridge


class DownloadTests(unittest.TestCase):
    def test_ranges_are_ordered_and_checked_before_publishing(self):
        payload = bytes(range(251)) * 600
        calls = []

        def fake_curl(url, directory, *, start, end):
            calls.append((start, end))
            return 206, {'content-range': f'bytes {start}-{end}/{len(payload)}'}, payload[start:end + 1]

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(download, 'curl', side_effect=fake_curl):
            target = Path(tmp) / 'artifact.jar'
            download.download('https://example.invalid/file', target, len(payload),
                              sha1=hashlib.sha1(payload).hexdigest().upper(), workers=2)
            self.assertEqual(target.read_bytes(), payload)
            self.assertEqual(sorted(calls), [(0, 65535), (65536, 131071), (131072, len(payload) - 1)])
            self.assertEqual(list(Path(tmp).iterdir()), [target])

    def test_invalid_range_and_short_body_preserve_previous_artifact(self):
        cases = [
            (206, {'content-range': 'bytes 1-3/4'}, b'data', 'Content-Range'),
            (206, {'content-range': 'bytes 0-3/4'}, b'dat', 'Incomplete'),
            (200, {}, b'x' * download.CHUNK, 'HTTP 200'),
        ]
        for status, headers, body, message in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as tmp:
                target = Path(tmp) / 'artifact.jar'
                target.write_bytes(b'previous')
                size = download.CHUNK + 1 if status == 200 else 4
                with mock.patch.object(download, 'curl', return_value=(status, headers, body)) as request:
                    with self.assertRaisesRegex(RuntimeError, message):
                        download.download('https://example.invalid/file', target, size, workers=1)
                    self.assertEqual(request.call_count, 3)
                self.assertEqual(target.read_bytes(), b'previous')
                self.assertEqual(list(Path(tmp).iterdir()), [target])

    def test_checksum_failure_removes_partial_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'artifact.jar'
            with mock.patch.object(download, 'curl', return_value=(200, {}, b'data')):
                with self.assertRaisesRegex(RuntimeError, 'checksum'):
                    download.download('https://example.invalid/file', target, 4, sha1='0' * 40)
            self.assertFalse(target.exists())
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_transient_timeout_is_retried(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'artifact.jar'
            with mock.patch.object(download, 'curl', side_effect=[
                    subprocess.TimeoutExpired('curl', 30), (200, {}, b'data')]) as request:
                download.download('https://example.invalid/file', target, 4)
                self.assertEqual(request.call_count, 2)
            self.assertEqual(target.read_bytes(), b'data')

    def test_empty_file_and_negative_size(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(download, 'curl') as request:
            target = Path(tmp) / 'empty'
            download.download('https://example.invalid/file', target, 0)
            self.assertEqual(target.read_bytes(), b'')
            with self.assertRaisesRegex(ValueError, 'Negative'):
                download.download('https://example.invalid/file', target, -1)
            request.assert_not_called()

    def test_curl_uses_final_http_header_after_proxy_connect(self):
        def fake_run(command, **kwargs):
            Path(command[command.index('-D') + 1]).write_bytes(
                b'HTTP/1.1 200 Connection established\r\n\r\n'
                b'HTTP/2 206\r\nContent-Range: bytes 0-3/4\r\nContent-Length: 4\r\n\r\n')
            Path(command[command.index('-o') + 1]).write_bytes(b'data')
            return subprocess.CompletedProcess(command, 0, stdout=b'', stderr=b'')

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(download.subprocess, 'run', side_effect=fake_run):
            status, headers, body = download.curl('https://example.invalid/file', tmp, start=0, end=3)
        self.assertEqual(status, 206)
        self.assertEqual(headers['content-range'], 'bytes 0-3/4')
        self.assertEqual(body, b'data')

    def test_metadata_accepts_missing_artifact_but_rejects_upstream_error(self):
        with mock.patch.object(download, 'curl', return_value=(404, {}, b'')):
            self.assertEqual(download.metadata('https://example.invalid/missing', Path('.')), (404, {}))
        with mock.patch.object(download, 'curl', return_value=(503, {}, b'')):
            with self.assertRaisesRegex(RuntimeError, 'HTTP 503'):
                download.metadata('https://example.invalid/file', Path('.'))


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.payload = b'fake jar payload'
        self.headers = {'content-length': str(len(self.payload)), 'content-type': 'application/java-archive',
                        'etag': 'v1', 'last-modified': 'Tue, 13 Oct 2026 00:00:00 GMT'}
        self.meta_patch = mock.patch.object(maven_bridge, 'metadata', return_value=(200, self.headers))
        self.metadata = self.meta_patch.start()
        self.download_patch = mock.patch.object(maven_bridge, 'download', side_effect=self.fake_download)
        self.download = self.download_patch.start()
        self.server = maven_bridge.Bridge(Path(self.tmp.name))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.download_patch.stop()
        self.meta_patch.stop()
        self.tmp.cleanup()

    def fake_download(self, url, destination, size, *, workers):
        # Give concurrent requests time to enter the server before publishing.
        time.sleep(0.02)
        self.assertEqual(size, len(self.payload))
        self.assertEqual(workers, 4)
        Path(destination).write_bytes(self.payload)

    def request(self, method='GET', path='/androidx/sample/1.0/sample-1.0.jar'):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def restart_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.server = maven_bridge.Bridge(Path(self.tmp.name))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def test_head_describes_get_without_downloading(self):
        status, headers, body = self.request('HEAD')
        self.assertEqual(status, 200)
        self.assertEqual(headers['Content-Length'], str(len(self.payload)))
        self.assertEqual(headers['Last-Modified'], self.headers['last-modified'])
        self.assertEqual(body, b'')
        self.download.assert_not_called()
        status, headers, body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(headers['Content-Type'], 'application/java-archive')
        self.assertEqual(body, self.payload)
        self.assertEqual(self.download.call_count, 1)
        self.metadata.assert_called_with(maven_bridge.UPSTREAM + '/androidx/sample/1.0/sample-1.0.jar',
                                         self.server.cache)

    def test_missing_file_and_invalid_query_do_not_download(self):
        self.metadata.return_value = (404, {})
        self.assertEqual(self.request()[0], 404)
        self.assertEqual(self.request('HEAD')[0], 404)
        self.assertEqual(self.request(path='/artifact.jar?other=1')[0], 400)
        self.download.assert_not_called()

    def test_parallel_requests_share_download_then_corrupt_cache_is_repaired(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            responses = list(pool.map(lambda _: self.request(), range(6)))
        self.assertTrue(all(status == 200 and body == self.payload for status, _, body in responses))
        self.assertEqual(self.download.call_count, 1)
        self.assertEqual(self.request()[2], self.payload)
        self.assertEqual(self.download.call_count, 1)
        artifact = next(path for path in Path(self.tmp.name).iterdir() if not path.suffix)
        artifact.write_bytes(b'X' * len(self.payload))
        self.assertEqual(self.request()[2], self.payload)
        self.assertEqual(self.download.call_count, 2)

    def test_metadata_is_reused_across_builds_until_expiry_and_corruption_is_ignored(self):
        with mock.patch.object(maven_bridge.time, 'time', return_value=5000):
            self.assertEqual(self.request('HEAD')[0], 200)
        self.assertEqual(self.metadata.call_count, 1)
        self.restart_server()
        with mock.patch.object(maven_bridge.time, 'time', return_value=5500):
            self.assertEqual(self.request()[2], self.payload)
        self.assertEqual(self.metadata.call_count, 1)
        self.assertEqual(self.download.call_count, 1)
        self.restart_server()
        with mock.patch.object(maven_bridge.time, 'time', return_value=9000):
            self.assertEqual(self.request('HEAD')[0], 200)
        self.assertEqual(self.metadata.call_count, 2)
        saved = next(Path(self.tmp.name).glob('head-*.json'))
        saved.write_text('{invalid-json')
        self.restart_server()
        with mock.patch.object(maven_bridge.time, 'time', return_value=9100):
            self.assertEqual(self.request('HEAD')[0], 200)
        self.assertEqual(self.metadata.call_count, 3)
        self.assertEqual(self.download.call_count, 1)

    def test_upstream_failure_is_bad_gateway_without_cache_artifact(self):
        self.download.side_effect = RuntimeError('simulated transfer failure')
        with mock.patch('builtins.print'):
            self.assertEqual(self.request()[0], 502)
        artifacts = [path for path in Path(self.tmp.name).iterdir()
                     if not (path.name.startswith('head-') and path.suffix == '.json')]
        self.assertEqual(artifacts, [])


class FallbackTests(unittest.TestCase):
    def test_bridge_closes_if_private_gradle_home_cannot_be_prepared(self):
        with tempfile.TemporaryDirectory() as tmp:
            scratch = Path(tmp).resolve()
            original = scratch / 'unwritable-gradle'
            servers = []
            mkdir = Path.mkdir

            def fail_original_home(path, *args, **kwargs):
                if path == original:
                    raise PermissionError('simulated permission error')
                return mkdir(path, *args, **kwargs)

            def bridge(cache):
                result = maven_bridge.Bridge(cache)
                servers.append(result)
                return result

            with mock.patch.object(build_dev, 'SCRATCH', scratch), \
                    mock.patch.object(build_dev, 'Bridge', side_effect=bridge), \
                    mock.patch.object(Path, 'mkdir', new=fail_original_home):
                with self.assertRaisesRegex(PermissionError, 'simulated'):
                    with build_dev.fallback({'GRADLE_USER_HOME': str(original)}):
                        self.fail('Fallback must not start the build after preparation fails')
            # Also close it on a regression, so the test itself never leaks a server.
            closed = servers[0].socket.fileno() == -1
            if not closed:
                servers[0].shutdown()
                servers[0].server_close()
            self.assertTrue(closed, 'Bridge leaked after Gradle home preparation failed')

    def test_gradle_home_and_daemon_are_isolated_and_cleaned_on_build_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            original = root / 'user gradle'
            original.mkdir()
            (original / 'gradle.properties').write_text('org.gradle.jvmargs=-Xmx2G\n')
            (original / 'init.d').mkdir()
            original_init = original / 'init.d/user.gradle'
            original_init.write_text('// user init\n')
            scratch = root / 'scratch'
            scratch.mkdir()
            servers = []
            bridge_class = maven_bridge.Bridge

            def bridge(cache):
                result = bridge_class(cache)
                servers.append(result)
                return result

            env = {'GRADLE_USER_HOME': str(original), 'JAVA_HOME': '/fake/jdk'}
            with mock.patch.object(build_dev, 'SCRATCH', scratch), \
                    mock.patch.object(build_dev, 'Bridge', side_effect=bridge), \
                    mock.patch.object(build_dev.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as stop, \
                    mock.patch('builtins.print'):
                with self.assertRaisesRegex(RuntimeError, 'build failed'):
                    with build_dev.fallback(env) as child:
                        home = Path(child['GRADLE_USER_HOME'])
                        self.assertNotEqual(home, original)
                        self.assertEqual(child['JAVA_HOME'], env['JAVA_HOME'])
                        self.assertEqual((home / 'caches').resolve(), original / 'caches')
                        self.assertFalse((home / 'gradle.properties').is_symlink())
                        self.assertIn('org.gradle.jvmargs=-Xmx2G', (home / 'gradle.properties').read_text())
                        self.assertIn('org.gradle.daemon=false', (home / 'gradle.properties').read_text())
                        self.assertEqual((home / 'init.d/user.gradle').resolve(), original_init)
                        self.assertTrue((home / 'init.d/pdd-google-maven.gradle').is_file())
                        self.assertTrue(child['PDD_GOOGLE_MAVEN_URL'].startswith('http://127.0.0.1:'))
                        raise RuntimeError('build failed')
                self.assertFalse(home.exists())
                stop.assert_not_called()
            self.assertEqual(env, {'GRADLE_USER_HOME': str(original), 'JAVA_HOME': '/fake/jdk'})
            self.assertEqual(original_init.read_text(), '// user init\n')
            self.assertEqual((original / 'gradle.properties').read_text(), 'org.gradle.jvmargs=-Xmx2G\n')
            self.assertEqual(sorted(path.name for path in (original / 'init.d').iterdir()), ['user.gradle'])
            self.assertEqual(servers[0].socket.fileno(), -1)

    def test_build_uses_fallback_child_environment_and_passes_failure_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sdk = root / 'sdk'
            cmake = sdk / 'cmake' / build_dev.CMAKE_VERSION / 'bin/cmake'
            cmake.parent.mkdir(parents=True)
            cmake.write_text('fake cmake')
            child = {'GRADLE_USER_HOME': str(root / 'isolated')}
            with mock.patch.object(build_dev, 'ROOT', root), \
                    mock.patch.object(build_dev, 'prerequisites', return_value=sdk), \
                    mock.patch.object(build_dev, 'fallback', return_value=contextlib.nullcontext(child)) as fallback, \
                    mock.patch.object(build_dev.subprocess, 'check_output', return_value='abc123\n'), \
                    mock.patch.object(build_dev.shutil, 'which', return_value=None), \
                    mock.patch.object(build_dev.subprocess, 'run',
                                      return_value=subprocess.CompletedProcess([], 7)) as run, \
                    mock.patch.dict(build_dev.os.environ, {'DEVICE_REGION': 'RU'}, clear=True), \
                    mock.patch.object(sys, 'argv', ['build_dev.py', '--arm64', '--download-fallback']), \
                    mock.patch('builtins.print'):
                self.assertEqual(build_dev.main(), 7)
            command = run.call_args[0][0]
            self.assertIn('-Pdev', command)
            self.assertIn('--dart-define=DEVICE_REGION=RU', command)
            self.assertIn('--dart-define=GIT_COMMIT=abc123', command)
            self.assertEqual(command[command.index('--target-platform') + 1], 'android-arm64')
            self.assertEqual(run.call_args[1]['env'], child)
            self.assertEqual(fallback.call_args[0][0]['ANDROID_HOME'], str(sdk))

    def test_dev_build_refreshes_cached_game_and_stops_on_failed_export(self):
        for cached, godot, export_code in [(True, '/bin/godot', 0), (False, '/bin/godot', 0),
                                            (True, '/bin/godot', 9), (True, None, 1)]:
            with self.subTest(cached=cached, godot=godot, export_code=export_code), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                sdk = root / 'sdk'
                cmake = sdk / 'cmake' / build_dev.CMAKE_VERSION / 'bin/cmake'
                cmake.parent.mkdir(parents=True)
                cmake.touch()
                if cached:
                    asset = root / 'android/godot/assets/project.binary'
                    asset.parent.mkdir(parents=True)
                    asset.write_bytes(b'old exported game')
                with mock.patch.object(build_dev, 'ROOT', root), \
                        mock.patch.object(build_dev, 'prerequisites', return_value=sdk), \
                        mock.patch.object(build_dev.shutil, 'which', return_value=godot), \
                        mock.patch.object(build_dev.subprocess, 'check_output', return_value='abc123\n'), \
                        mock.patch.object(build_dev.subprocess, 'run', side_effect=[
                            subprocess.CompletedProcess([], export_code), subprocess.CompletedProcess([], 0)]) as run, \
                        mock.patch.dict(build_dev.os.environ, {}, clear=True), \
                        mock.patch.object(sys, 'argv', ['build_dev.py']), \
                        mock.patch('builtins.print'):
                    self.assertEqual(build_dev.main(), export_code)
                self.assertEqual(run.call_args_list[0].args[0], ['bash', str(root / 'scripts/godot_android_assets.sh')])
                self.assertEqual(run.call_args_list[0].kwargs['env']['ANDROID_HOME'], str(sdk))
                if export_code:
                    self.assertEqual(run.call_count, 1, 'failed export must never package the old game')
                else:
                    self.assertEqual(run.call_count, 2)
                    self.assertEqual(run.call_args_list[1].args[0][:3], ['flutter', 'build', 'apk'])


class EnvironmentTests(unittest.TestCase):
    def test_prerequisites_rejects_flutter_sdk_conflict_before_setup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'android').mkdir()
            sdk = root / 'selected-sdk'
            sdk.mkdir()
            scratch = root / 'scratch'
            (root / 'android/local.properties').write_text(f'sdk.dir={sdk}\n')
            with mock.patch.object(environment, 'ROOT', root), \
                    mock.patch.object(environment, 'SCRATCH', scratch), \
                    mock.patch.dict(environment.os.environ, {}, clear=True), \
                    mock.patch.object(environment.shutil, 'which', return_value='/fake/bin/tool'), \
                    mock.patch.object(environment.subprocess, 'check_output', side_effect=[
                        'openjdk version "17.0.20"\n', '{"android-sdk": "/sdk/other"}']):
                with self.assertRaisesRegex(RuntimeError, 'flutter config --android-sdk=') as failure:
                    environment.prerequisites()
            self.assertIn(str(sdk), str(failure.exception))
            self.assertIn('/sdk/other', str(failure.exception))
            self.assertFalse(scratch.exists(), 'Conflicting SDK must fail before preparing downloads')

    def test_local_sdk_takes_precedence_over_environment_and_flutter(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'android').mkdir()
            sdk = root / 'SDK with spaces'
            (root / 'android/local.properties').write_text(f'sdk.dir={sdk}\n')
            with mock.patch.object(environment, 'ROOT', root), \
                    mock.patch.dict(environment.os.environ, {'ANDROID_HOME': '/wrong/sdk'}, clear=True), \
                    mock.patch.object(environment.subprocess, 'check_output') as flutter:
                self.assertEqual(environment.android_sdk(), sdk)
                flutter.assert_not_called()

    def test_environment_sdk_precedence_and_flutter_config_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(environment, 'ROOT', Path(tmp)), \
                    mock.patch.dict(environment.os.environ, {'ANDROID_HOME': '/sdk/home',
                                                            'ANDROID_SDK_ROOT': '/sdk/root'}, clear=True), \
                    mock.patch.object(environment.subprocess, 'check_output') as flutter:
                self.assertEqual(environment.android_sdk(), Path('/sdk/home'))
                flutter.assert_not_called()
            with mock.patch.object(environment, 'ROOT', Path(tmp)), \
                    mock.patch.dict(environment.os.environ, {}, clear=True), \
                    mock.patch.object(environment.subprocess, 'check_output',
                                      return_value='{"android-sdk": "/sdk/flutter"}'):
                self.assertEqual(environment.android_sdk(), Path('/sdk/flutter'))


if __name__ == '__main__':
    unittest.main()
