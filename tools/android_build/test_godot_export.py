"""Godot may exit zero on script errors; never package that export."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/godot_android_assets.sh'


class GodotExportTests(unittest.TestCase):
    def test_script_errors_stop_import_and_export_even_with_exit_zero(self):
        for stage in ('import', 'export'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / 'scripts').mkdir()
                shutil.copyfile(SCRIPT, root / 'scripts/godot_android_assets.sh')
                scenery = root / 'game_godot/scenery'
                scenery.mkdir(parents=True)
                (scenery / 'test.import').write_text('original scenery')
                preset = root / 'game_godot/export_presets.cfg'
                original = '[preset.0.options]\npackage/signed=true\n[preset.1]\n'
                preset.write_text(original)
                ui = root / 'tools/godot_export/export_ui.py'
                ui.parent.mkdir(parents=True)
                ui.write_text('pass\n')
                (ui.parent / 'export_question_images.py').write_text('pass\n')
                (ui.parent / 'export_question_audio.py').write_text('pass\n')
                home = root / 'home'
                templates = home / '.local/share/godot/export_templates/4.7.2.stable'
                templates.mkdir(parents=True)
                with zipfile.ZipFile(templates / 'android_source.zip', 'w') as archive:
                    archive.writestr('libs/release/godot-lib.template_release.aar', b'fake engine')
                binary = root / 'bin/godot'
                binary.parent.mkdir()
                binary.write_text('''#!/usr/bin/env bash
if [[ "$1" == --version ]]; then echo 4.7.2.stable.official.test; exit 0; fi
if [[ "$*" == *--import* && "$FAIL_STAGE" == import ]] ||
   [[ "$*" == *--export-release* && "$FAIL_STAGE" == export ]]; then
  echo 'SCRIPT ERROR: Parse Error: broken game script'
  exit 0
fi
exit 0
''')
                binary.chmod(0o755)
                env = dict(os.environ, HOME=str(home), FAIL_STAGE=stage,
                           PATH=str(binary.parent) + ':' + os.environ['PATH'])
                result = subprocess.run(['bash', 'scripts/godot_android_assets.sh'], cwd=root,
                                        env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('SCRIPT ERROR', result.stdout)
                self.assertTrue((root / 'output/godot/android-export.log').exists())
                self.assertFalse((root / 'android/godot/assets').exists())
                self.assertEqual(preset.read_text(), original)
                self.assertEqual((scenery / 'test.import').read_text(), 'original scenery')


if __name__ == '__main__':
    unittest.main()
