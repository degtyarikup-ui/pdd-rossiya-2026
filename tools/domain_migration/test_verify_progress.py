import json
import unittest

import verify_progress as verification


class ProgressPreparationTest(unittest.TestCase):
    def test_inventory_matches_audited_sources_and_covers_fixture(self):
        inventory = verification.inventory()
        covered = inventory["cloudSnapshotFields"].keys() | inventory["localOnlyFields"].keys()
        self.assertEqual(set(verification.synthetic_preferences()), covered)
        self.assertIn("export only", inventory["cloudSnapshotFields"]["app_settings"])

    def test_web_encoding_preserves_nested_json_unicode_types_and_tombstones(self):
        prefs = verification.synthetic_preferences()
        encoded = verification.web_storage(prefs)
        self.assertIsInstance(json.loads(encoded["flutter.favorites_ab"]), str)
        restored = verification.restore_web_storage(json.loads(json.dumps(encoded)))
        self.assertEqual(restored, prefs)
        self.assertFalse(json.loads(restored["favorite_states_ab"])["q_1_2"]["present"])
        self.assertIs(restored["streak_celebration_pending"], True)
        self.assertIsInstance(restored["streak_current"], int)
        self.assertEqual(restored["streak_active_days"], ["2026-10-16", "2026-10-17", "2026-10-18"])

    def test_fixture_contains_no_authentication_or_premium_claims(self):
        prefs = verification.synthetic_preferences()
        self.assertFalse(any(key.startswith(("premium_", "auth_", "pending_sbp_")) for key in prefs))
        self.assertNotIn("pdd_server_session", prefs)

    def test_roundtrip_cannot_hide_a_missing_key(self):
        stored = verification.web_storage(verification.synthetic_preferences())
        del stored["flutter.game_run_pending"]
        self.assertNotEqual(verification.restore_web_storage(stored), verification.synthetic_preferences())

    def test_unfinished_exam_has_timer_answers_and_additional_phase(self):
        prefs = verification.synthetic_preferences("exam")
        exam = json.loads(prefs["unfinished_session"])
        self.assertEqual(exam["remainingSeconds"], 217)
        self.assertEqual(exam["answers"], [1, None])
        self.assertTrue(exam["additionalPhase"])
        self.assertEqual(verification.restore_web_storage(verification.web_storage(prefs)), prefs)

    def test_temporary_output_cannot_be_written_outside_ignored_directories(self):
        with self.assertRaises(ValueError):
            verification.write_artifacts(verification.ROOT / "docs/forbidden-test-output")


if __name__ == "__main__":
    unittest.main()
