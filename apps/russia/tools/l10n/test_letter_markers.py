import unittest
from unittest.mock import patch

from fix_letter_markers import EXPLICIT_LETTER_ANSWERS, validate_marker_overrides


class LetterMarkerTest(unittest.TestCase):
    def test_reviewed_pairs_preserve_both_languages(self):
        validate_marker_overrides()

    def test_a_b_to_a_v_regression_is_rejected(self):
        broken = {'В направлениях А и Б': ('In directions А and Б', 'А және В бағыттары бойынша')}
        with patch.dict(EXPLICIT_LETTER_ANSWERS, broken):
            with self.assertRaises(ValueError):
                validate_marker_overrides()


if __name__ == '__main__':
    unittest.main()
