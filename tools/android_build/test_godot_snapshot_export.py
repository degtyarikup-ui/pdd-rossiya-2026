"""Export validation is independent of Godot's unreliable error exit status."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class SnapshotExportTests(unittest.TestCase):
    def export(self, root, platform, failure):
        (root / 'scripts').mkdir()
        script = f'godot_{platform}_assets.sh'
        shutil.copyfile(ROOT / 'scripts' / script, root / 'scripts' / script)
        scenery = root / 'game_godot/scenery/test.import'
        scenery.parent.mkdir(parents=True)
        scenery.write_text('author edits')
        (root / 'game_godot/export_presets.cfg').write_text('[preset.0.options]\npackage/signed=true\n[preset.1]\n')
        situation = root / 'game_godot/situations/ticket_1_1'
        situation.mkdir(parents=True)
        (situation / 'scene.json').write_text('{}')
        (situation / 'scene.glb').write_text('shared geometry')
        (situation / 'notes.md').write_text('not an export input')
        (root / 'assets').mkdir()
        (root / 'lib').mkdir()
        tools = root / 'tools/godot_export'
        tools.mkdir(parents=True)
        for name in ('ui', 'question_images'):
            (tools / f'export_{name}.py').write_text('pass\n')
        (tools / 'export_question_audio.py').write_text("import sys\nassert '--check' in sys.argv\n")
        home = root / 'home'
        templates = home / '.local/share/godot/export_templates/4.7.2.stable'
        templates.mkdir(parents=True)
        with zipfile.ZipFile(templates / 'android_source.zip', 'w') as archive:
            archive.writestr('libs/release/godot-lib.template_release.aar', 'fresh engine')
        output = root / ('android/godot' if platform == 'android' else 'build/web/godot')
        previous = output / ('assets/project.binary' if platform == 'android' else 'index.pck')
        previous.parent.mkdir(parents=True)
        previous.write_text('previous valid game')
        if platform == 'android': (output / 'godot-lib.aar').write_text('previous engine')
        binary = root / 'bin/godot'
        binary.parent.mkdir()
        binary.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, zipfile
if '--version' in sys.argv:
    print('4.7.2.stable.official.fixture'); sys.exit(0)
project = pathlib.Path(sys.argv[sys.argv.index('--path')+1])
(project/'scenery/test.import').write_text('importer rewrite')
stage = 'import' if '--import' in sys.argv else 'export'
if os.environ['FAIL_STAGE'] == stage:
    print('SCRIPT ERROR: intentional fixture error'); sys.exit(0)
if stage == 'export' and os.environ['FAIL_STAGE'] != 'missing':
    destination = pathlib.Path(sys.argv[-1])
    if destination.suffix == '.apk':
        with zipfile.ZipFile(destination,'w') as z: z.writestr('assets/project.binary','fresh validated game')
    else:
        for suffix in ('html','js','wasm','pck'):
            destination.with_suffix('.'+suffix).write_text('fresh validated game')
''')
        binary.chmod(0o755)
        env = dict(os.environ, HOME=str(home), FAIL_STAGE=failure,
                   PATH=str(binary.parent) + ':' + os.environ['PATH'])
        result = subprocess.run(['bash', 'scripts/' + script], cwd=root, env=env,
                                capture_output=True, text=True)
        self.assertEqual(scenery.read_text(), 'author edits')
        self.assertEqual(list((root / 'scratch').iterdir()), [])
        return result, previous, output

    def test_failed_or_missing_exports_preserve_previous_game_and_engine(self):
        for platform in ('android', 'web'):
            for stage in ('import', 'export', 'missing'):
                with self.subTest(platform=platform, stage=stage), tempfile.TemporaryDirectory() as tmp:
                    result, previous, output = self.export(Path(tmp), platform, stage)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(previous.read_text(), 'previous valid game')
                    if platform == 'android':
                        self.assertEqual((output / 'godot-lib.aar').read_text(), 'previous engine')

    def test_success_publishes_only_validated_private_snapshot(self):
        for platform in ('android', 'web'):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as tmp:
                result, previous, output = self.export(Path(tmp), platform, '')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(previous.read_text(), 'fresh validated game')
                if platform == 'web':
                    self.assertTrue((output / 'situations/ticket_1_1/scene.glb').is_file())
                    self.assertFalse((output / 'situations/ticket_1_1/notes.md').exists())


if __name__ == '__main__':
    unittest.main()
