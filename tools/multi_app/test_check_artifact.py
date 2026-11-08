import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import zipfile

from tools.multi_app.check_artifact import audit, inventory


class ArtifactIsolationTest(unittest.TestCase):
    def test_relocated_app_wrapper_enforces_country(self):
        script = Path(__file__).resolve().parents[2] / "apps/russia/tools/multi_app/check_artifact.py"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "assets/countries/ru/questions/q.json"
            path.parent.mkdir(parents=True)
            path.write_text("[]")
            for country, expected in (("ru", 0), ("by", 1)):
                result = subprocess.run([sys.executable, str(script), directory, "--country", country], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_android_and_ios_prefixes(self):
        for prefix in ('assets/flutter_assets/', 'base/assets/flutter_assets/',
                       'Payload/Runner.app/Frameworks/App.framework/flutter_assets/'):
            with self.subTest(prefix=prefix):
                entries = [(prefix + 'assets/countries/ru/questions/q.json', 20)]
                self.assertTrue(audit(entries, 'ru')['ok'])
                entries.append((prefix + 'assets/countries/by/images/sign.png', 40))
                report = audit(entries, 'ru')
                self.assertFalse(report['ok'])
                self.assertEqual(report['uncompressed_bytes'], 60)
                self.assertEqual(len(report['foreign_assets']), 1)

    def test_absent_content_fails_closed(self):
        self.assertFalse(audit([], 'ru')['ok'])
        self.assertFalse(audit([('assets/project.binary', 123)], 'ru')['ok'])
        self.assertFalse(audit([('assets/countries/by/q.json', 1)], 'ru')['ok'])

    def test_country_is_not_language(self):
        report = audit([('assets/countries/ru/questions/questions_ab_en.json', 1)], 'ru')
        self.assertTrue(report['ok'])

    def test_zip_and_web_inventory_match(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            web = root / 'web'
            path = web / 'assets/countries/by/questions/q.json'
            path.parent.mkdir(parents=True)
            path.write_bytes(b'[]')
            archive = root / 'app.apk'
            with zipfile.ZipFile(archive, 'w') as output:
                output.write(path, path.relative_to(web).as_posix())
            self.assertEqual(inventory(web), inventory(archive))
            self.assertTrue(audit(inventory(archive), 'by')['ok'])


if __name__ == '__main__':
    unittest.main()
