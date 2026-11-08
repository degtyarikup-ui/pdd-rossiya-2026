"""Studio recordings keep their source identity and remain shared across platforms."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("question_audio", Path(__file__).with_name("export_question_audio.py"))
audio = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audio)
QUESTION_ID = "a" * 32
IMAGE_ID = "b" * 32


class QuestionAudioTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "scratch").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "scratch")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.question = {"id": QUESTION_ID, "image": IMAGE_ID, "question": "Вопрос?",
                         "answers": [{"text": "Ответ один"}, {"text": "Ответ два"}]}
        self.scene = {"text": {"ru": {"title": "Вопрос?", "options": ["Ответ один", "Ответ два"]}}}
        self.road = {"id": "road_1_1", "sourceQuestionId": QUESTION_ID, "category": "ab",
                     "title": "Вопрос?", "options": ["Ответ один", "Ответ два"]}
        self.write("assets/countries/ru/questions/questions_ab.json", {"tickets": [{"questions": [self.question]}]})
        self.write("game_godot/situations/index.json", ["ticket_1_1"])
        self.write("game_godot/situations/ticket_1_1/scene.json", self.scene)
        self.write("game_godot/roads/road_scenes.json", {"scenes": [self.road]})
        self.source = self.root / f"assets/audio/feed/q_{QUESTION_ID}.opus"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"studio recording")
        self.mp3 = self.root / f"assets/audio/game_questions/q_{QUESTION_ID}.mp3"
        self.link = self.root / f"game_godot/question_audio/q_{QUESTION_ID}.mp3"
        self.encode_calls = 0

        def encode(source, destination):
            self.encode_calls += 1
            destination.write_bytes(b"MP3 " + source.read_bytes())
            return 12.25
        self.addCleanup(patch.stopall)
        patch.object(audio, "encode", side_effect=encode).start()
        patch.object(audio.shutil, "which", return_value="/installed/ffmpeg").start()

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def test_uses_question_identity_and_converts_shared_recording_once(self):
        index, converted, _ = audio.export(self.root)
        self.assertEqual(converted, 1)
        self.assertEqual(self.encode_calls, 1)
        self.assertEqual(index["language"], "ru")
        self.assertEqual(index["clips"]["ticket_1_1"], {
            "file": f"q_{QUESTION_ID}.mp3", "duration": 12.25, "sourceQuestionId": QUESTION_ID})
        self.assertEqual(index["clips"]["road_1_1"], index["clips"]["ticket_1_1"])
        self.assertFalse(self.link.exists())
        self.assertTrue(self.mp3.exists())
        self.assertEqual(self.source.read_bytes(), b"studio recording")

    def test_changed_game_text_and_answer_order_fail_before_conversion(self):
        self.scene["text"]["ru"]["options"].reverse()
        self.write("game_godot/situations/ticket_1_1/scene.json", self.scene)
        with self.assertRaisesRegex(ValueError, "does not match question/answers: ticket_1_1"):
            audio.export(self.root)
        self.assertEqual(self.encode_calls, 0)
        self.scene["text"]["ru"]["options"].reverse()
        self.write("game_godot/situations/ticket_1_1/scene.json", self.scene)
        self.road["title"] = "Другой вопрос"
        self.write("game_godot/roads/road_scenes.json", {"scenes": [self.road]})
        with self.assertRaisesRegex(ValueError, "does not match question/answers: road_1_1"):
            audio.export(self.root)

    def test_missing_recording_preserves_standalone_inputs(self):
        audio.export(self.root, standalone=True)
        self.source.unlink()
        with self.assertRaisesRegex(FileNotFoundError, "Missing studio recording"):
            audio.export(self.root)
        self.assertTrue(self.link.is_symlink())
        self.assertTrue(self.mp3.exists())

    def test_incremental_cache_rebuilds_changed_source_or_corrupt_output(self):
        audio.export(self.root)
        self.assertEqual(audio.export(self.root)[1], 0)
        self.source.write_bytes(b"corrected studio recording")
        self.assertEqual(audio.export(self.root)[1], 1)
        self.mp3.write_bytes(b"corrupt MP3")
        with self.assertRaisesRegex(ValueError, "Missing or stale shared studio MP3"):
            audio.export(self.root, check=True)
        self.assertEqual(audio.export(self.root)[1], 1)
        self.assertEqual(self.encode_calls, 3)

    def test_check_never_converts_or_changes_files_and_rejects_stale_index(self):
        audio.export(self.root)
        cache = self.mp3.parent / ".manifest.json"
        before = cache.read_bytes(), self.mp3.read_bytes()
        with patch.object(audio.shutil, "which", return_value=None):
            self.assertEqual(audio.export(self.root, check=True)[1], 0)
        self.assertEqual((cache.read_bytes(), self.mp3.read_bytes()), before)
        self.write("game_godot/questions/audio.json", {})
        with self.assertRaisesRegex(ValueError, "Missing or stale questions/audio.json"):
            audio.export(self.root, check=True)
        self.assertEqual(self.encode_calls, 1)

    def test_standalone_uses_links_then_cleanup_keeps_shared_recording(self):
        audio.export(self.root, standalone=True)
        self.assertTrue(self.link.is_symlink())
        self.assertEqual(self.link.resolve(), self.mp3)
        self.assertIn('importer="keep"', self.link.with_suffix(".mp3.import").read_text())
        audio.remove_links(self.root)
        self.assertFalse(self.link.exists())
        self.assertTrue(self.mp3.exists())
        self.assertTrue(self.source.exists())

    def test_obsolete_generated_clip_is_removed_after_successful_generation(self):
        audio.export(self.root)
        obsolete = self.mp3.parent / ("q_" + "c" * 32 + ".mp3")
        obsolete.write_bytes(b"obsolete derivative")
        audio.export(self.root)
        self.assertFalse(obsolete.exists())


if __name__ == "__main__":
    unittest.main()
