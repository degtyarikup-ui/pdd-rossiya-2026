"""Godot may exit zero on script errors; never package that export."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/godot_android_assets.sh'
IOS_SCRIPT = SCRIPT.with_name('godot_ios_assets.sh')


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


class GodotIosExportTests(unittest.TestCase):
    def run_export(self, root, stage):
        (root / 'scripts').mkdir()
        shutil.copyfile(IOS_SCRIPT, root / 'scripts/godot_ios_assets.sh')
        scenery = root / 'game_godot/scenery'
        scenery.mkdir(parents=True)
        (scenery / 'test.import').write_text('author uncommitted scenery')
        tools = root / 'tools/godot_export'
        tools.mkdir(parents=True)
        for name in ('ui', 'question_images', 'question_audio'):
            (tools / f'export_{name}.py').write_text('pass\n')
        (tools / 'export_question_audio.py').write_text(
            "import sys\nassert '--check' in sys.argv, 'shared audio must be read-only'\n")
        (root / 'assets').mkdir()
        (root / 'lib').mkdir()
        previous = root / 'ios/Godot/game.pck'
        previous.parent.mkdir(parents=True)
        previous.write_text('previous valid game')
        home = root / 'home'
        templates = home / 'Library/Application Support/Godot/export_templates/4.7.2.stable'
        templates.mkdir(parents=True)
        with zipfile.ZipFile(templates / 'ios.zip', 'w') as archive:
            archive.writestr('libgodot.ios.release.xcframework/ios-arm64/libgodot.a', b'!<arch>\n')
            archive.writestr('MoltenVK.xcframework/ios-arm64/fixture', b'fixture')
        binary = root / 'bin/godot'
        binary.parent.mkdir()
        binary.write_text('''#!/usr/bin/env bash
if [[ "$1" == --version ]]; then echo 4.7.2.stable.official.test; exit 0; fi
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == --path ]]; then
    j=$((i+1)); project="${!j}"
    echo 'importer rewrote fixture' > "$project/scenery/test.import"
  fi
done
if [[ "$*" == *--import* && "$FAIL_STAGE" == import ]] ||
   [[ "$*" == *--export-pack* && "$FAIL_STAGE" == export ]]; then
  echo 'SCRIPT ERROR: Parse Error: broken game script'
  exit 0
fi
if [[ "$*" == *--export-pack* && "$FAIL_STAGE" != missing ]]; then
  echo 'fresh validated game' > "${!#}"
fi
exit 0
''')
        binary.chmod(0o755)
        env = dict(os.environ, HOME=str(home), FAIL_STAGE=stage,
                   PATH=str(binary.parent) + ':' + os.environ['PATH'])
        result = subprocess.run(['bash', 'scripts/godot_ios_assets.sh'], cwd=root,
                                env=env, capture_output=True, text=True)
        self.assertEqual((scenery / 'test.import').read_text(), 'author uncommitted scenery')
        self.assertEqual(list((root / 'scratch').iterdir()), [])
        return result, previous

    def test_errors_and_missing_pack_keep_previous_export_and_author_edits(self):
        for stage in ('import', 'export', 'missing'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                result, previous = self.run_export(root, stage)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                if stage != 'missing':
                    self.assertIn('SCRIPT ERROR', result.stdout)
                self.assertEqual(previous.read_text(), 'previous valid game')
                self.assertTrue((root / 'output/godot/ios-export.log').exists())
                self.assertFalse((root / 'ios/Godot/engine.xcconfig').exists())

    def test_success_publishes_validated_pack_from_private_import(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result, previous = self.run_export(root, '')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(previous.read_text(), 'fresh validated game\n')
            self.assertTrue((root / 'ios/Godot/engine.xcconfig').exists())
            self.assertTrue((root / 'ios/Godot/libgodot.ios.release.xcframework').exists())


if __name__ == '__main__':
    unittest.main()
