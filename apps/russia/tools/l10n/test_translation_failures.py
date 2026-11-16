import unittest
from unittest.mock import patch

from translate_content import translate_single, translate_pdd_sections_file, validate_answer_labels


class TranslationFailureTest(unittest.TestCase):
    def test_failed_rule_chunk_does_not_publish_russian_fallback(self):
        text = 'Первый абзац. ' * 100 + '\n' + 'Второй абзац. ' * 100
        with patch('translate_content.translate_simple', side_effect=['First paragraph.', None]):
            self.assertIsNone(translate_single(text, 'en'))

    def test_all_rule_chunks_must_succeed(self):
        text = 'Первый абзац. ' * 100 + '\n' + 'Второй абзац. ' * 100
        with patch('translate_content.translate_simple', side_effect=['First paragraph.', 'Second paragraph.']):
            self.assertEqual(translate_single(text, 'en'), 'First paragraph.\nSecond paragraph. ')

    def test_bad_point_number_is_rejected_before_writing_the_section(self):
        source = [{'title': '19. Внешние световые приборы', 'content': '19.11. Для предупреждения об обгоне.'}]
        cache = {source[0]['content']: '11.19. To warn of overtaking.'}
        with patch('translate_content.load_json', return_value=source), patch('translate_content.save_json') as save:
            with self.assertRaises(ValueError):
                translate_pdd_sections_file('pdd_sections_en.json', cache)
            save.assert_not_called()

    def test_bad_diagram_label_is_rejected_for_tickets_and_topics(self):
        for group in ['tickets', 'topics']:
            def data(text):
                return {group: [{'questions': [{'id': 'q', 'answers': [{'text': text}]}]}]}
            with self.assertRaises(ValueError):
                validate_answer_labels(data('В направлениях А и Б'), data('А және В бағыттары бойынша'), group)


if __name__ == '__main__':
    unittest.main()
