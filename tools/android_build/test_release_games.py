"""A release cannot silently omit games or reuse a failed engine export."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]


class ReleaseGameTests(unittest.TestCase):
    def fixture(self, root):
        (root / 'scripts').mkdir()
        for name in ('build.sh', 'android_env.sh'):
            shutil.copyfile(ROOT / 'scripts' / name, root / 'scripts' / name)
        tools = root / 'tools/godot_export'
        tools.mkdir(parents=True)
        (tools / 'export_question_audio.py').write_text('pass\n')
        version = root / 'tools/web/version_web_build.py'
        version.parent.mkdir(parents=True)
        version.write_text('pass\n')
        for platform in ('android', 'ios', 'web'):
            exporter = root / f'scripts/godot_{platform}_assets.sh'
            exporter.write_text(f'''#!/usr/bin/env bash
echo {platform} >> calls
if [[ "${{FAIL_GAME:-}}" == 1 ]]; then exit 19; fi
''')
            exporter.chmod(0o755)
        flutter = root / 'bin/flutter'
        flutter.parent.mkdir()
        flutter.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, zipfile
root = pathlib.Path('.')
with open('calls','a') as f: f.write('flutter ' + ' '.join(sys.argv[1:]) + '\\n')
if sys.argv[2] == 'web':
    (root/'build/web').mkdir(parents=True, exist_ok=True)
    sys.exit(0)
if sys.argv[2] == 'ipa': sys.exit(23)  # no upload in fixtures
path = root/('build/app/outputs/bundle/ruRelease/app-ru-release.aab' if sys.argv[2]=='appbundle' else 'build/app/outputs/flutter-apk/app-ru-release.apk')
path.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(path,'w') as z:
    z.writestr('assets/flutter_assets/assets/countries/ru/questions/questions_ab.json','{}')
    if os.environ.get('OMIT_PACK') != '1':
        z.writestr('assets/project.binary','fresh game')
        z.writestr('lib/arm64-v8a/libgodot_android.so','engine')
''')
        flutter.chmod(0o755)
        return dict(os.environ, PATH=str(flutter.parent) + ':' + os.environ['PATH'],
                    INSTALL_NOTIFY_SECRET=uuid.uuid4().hex,
                    SKIP_GODOT_WEB='1')

    def test_export_failure_blocks_all_native_release_targets_before_flutter(self):
        for target, platform in (('aab', 'android'), ('apk', 'android'),
                                 ('rustore-apk', 'android'), ('ipa', 'ios')):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                env = self.fixture(root)
                result = subprocess.run(['bash', 'scripts/build.sh', 'ru', target], cwd=root,
                                        env=dict(env, FAIL_GAME='1'), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((root / 'calls').read_text().strip(), platform)

    def test_android_releases_rebuild_before_flutter_and_verify_pack(self):
        for target in ('aab', 'apk', 'rustore-apk'):
            for omitted in ('0', '1'):
                with self.subTest(target=target, omitted=omitted), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    env = self.fixture(root)
                    result = subprocess.run(['bash', 'scripts/build.sh', 'ru', target], cwd=root,
                                            env=dict(env, OMIT_PACK=omitted), capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, omitted == '0', result.stdout + result.stderr)
                    calls = (root / 'calls').read_text().splitlines()
                    self.assertEqual(calls[0], 'android')
                    self.assertTrue(calls[1].startswith('flutter build '))

    def test_web_release_requires_game_even_with_legacy_skip_flag(self):
        for failed in ('0', '1'):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                env = self.fixture(root)
                result = subprocess.run(['bash', 'scripts/build.sh', 'ru', 'web'], cwd=root,
                                        env=dict(env, FAIL_GAME=failed), capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, failed == '0', result.stdout + result.stderr)
                self.assertEqual((root / 'calls').read_text().splitlines()[-1], 'web')


if __name__ == '__main__':
    unittest.main()
