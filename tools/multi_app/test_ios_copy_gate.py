"""Execute the actual Xcode pack-copy phase with isolated, synthetic game packs."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from tools.multi_app.test_pck import pack

ROOT = Path(__file__).resolve().parents[2]


class IosCopyGateTest(unittest.TestCase):
    def test_existing_pack_is_audited_even_without_running_exporter(self):
        project = (ROOT / 'apps/russia/ios/Runner.xcodeproj/project.pbxproj').read_text()
        block = project.split('/* Copy Godot game pack */ = {', 1)[1].split('\n\t\t};', 1)[0]
        script = json.loads(re.search(r'shellScript = ("(?:[^"\\]|\\.)*");', block)[1])
        for country in ('ru', 'by'):
            with self.subTest(country=country), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / 'ios/Godot/game.pck'
                source.parent.mkdir(parents=True)
                source.write_bytes(pack(country=country))
                tools = root / 'tools/multi_app'
                tools.mkdir(parents=True)
                for name in ('check_artifact.py', 'pck.py', 'size_budgets.json'):
                    shutil.copyfile(ROOT / 'tools/multi_app' / name, tools / name)
                app = root / 'Runner.app'
                app.mkdir()
                target = app / 'Runner.pck'
                target.write_bytes(b'previous pack')
                result = subprocess.run(['/bin/sh', '-c', script], env=dict(
                    os.environ, PROJECT_DIR=str(root / 'ios'),
                    CODESIGNING_FOLDER_PATH=str(app), EXECUTABLE_NAME='Runner'),
                    capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, country == 'ru', result.stderr)
                self.assertEqual(target.read_bytes(), source.read_bytes() if country == 'ru' else b'previous pack')


if __name__ == '__main__':
    unittest.main()
