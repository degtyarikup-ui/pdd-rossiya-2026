"""Canonical pictures stay shared; standalone exports only use temporary links."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/godot_export/export_question_images.py"
HASH = "76e8ace06d939a11ad53700fa4151134"


class QuestionImageTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "scratch").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "scratch")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        tool = self.root / "tools/godot_export/export_question_images.py"
        tool.parent.mkdir(parents=True)
        shutil.copyfile(SCRIPT, tool)
        self.tool = tool
        questions = self.root / "assets/countries/ru/questions"
        questions.mkdir(parents=True)
        (questions / "questions_ab.json").write_text(json.dumps({"tickets": [
            {"questions": [{"image": HASH}]}]}))
        for folder in ("game_godot/network", "game_godot/roads", "game_godot/questions"):
            (self.root / folder).mkdir(parents=True)
        (self.root / "game_godot/network/ticket_1_1.json").write_text("{}")
        (self.root / "game_godot/roads/road_scenes.json").write_text('{"scenes": []}')
        self.source = self.root / f"assets/countries/ru/images/questions_ab/{HASH}.webp"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"current photo")
        self.out = self.root / f"game_godot/questions/{HASH}.webp"

    def run_export(self, *args):
        return subprocess.run([sys.executable, str(self.tool), *args],
                              capture_output=True, text=True)

    def test_embedded_export_removes_stale_copies_and_keeps_only_index(self):
        self.out.write_bytes(b"old photo")
        self.out.with_suffix(".webp.import").write_text("old import")
        result = self.run_export()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.source.read_bytes(), b"current photo")
        self.assertEqual(list(self.out.parent.glob("*.webp*")), [])
        self.assertEqual(json.loads((self.out.parent / "index.json").read_text()),
                         {"ticket_1_1": HASH})

    def test_standalone_link_tracks_source_replacements_and_is_cleaned(self):
        result = self.run_export("--standalone")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.out.is_symlink())
        self.assertEqual(self.out.resolve(), self.source)
        self.source.write_bytes(b"replacement photo")
        self.assertEqual(self.out.read_bytes(), b"replacement photo")
        self.assertIn('importer="keep"', self.out.with_suffix(".webp.import").read_text())
        result = self.run_export()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.out.exists())

    def test_missing_source_fails_before_removing_existing_export_inputs(self):
        self.out.write_bytes(b"old photo")
        self.source.unlink()
        result = self.run_export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing canonical question image", result.stderr)
        self.assertEqual(self.out.read_bytes(), b"old photo")


if __name__ == "__main__":
    unittest.main()
