import unittest
from import_pddby_preview import build_catalog


class ImportPreviewTest(unittest.TestCase):
    def bank(self):
        return {'checkedAt': '2026-11-09T00:00:00Z', 'source': 'https://pdd.by/tasks/online/',
                'questions': {'q': {'id': 'by:test:1', 'text': 'Question', 'answers': ['A', 'B'],
                    'correctIndex': 1, 'subject': 'pdd', 'imageUrls': [], 'hintHtml': '<b>Rule</b>'}}}

    def test_preserves_gold_but_never_approves_exam(self):
        result = build_catalog(self.bank(), {})
        self.assertEqual(result['questions'][0]['correctIndex'], 1)
        self.assertEqual(result['questions'][0]['explanation'], 'Rule')
        self.assertTrue(result['previewOnly'])
        self.assertEqual(result['reviewStatus'], 'pending')
        self.assertFalse(result['examRulesReviewed'])

    def test_duplicate_content_and_missing_media_rejected(self):
        bank = self.bank()
        bank['questions']['duplicate'] = dict(bank['questions']['q'], id='by:test:2')
        with self.assertRaises(ValueError): build_catalog(bank, {})
        bank = self.bank()
        bank['questions']['q']['imageUrls'] = ['https://pdd.by/img/tickets/a.jpg']
        with self.assertRaises(KeyError): build_catalog(bank, {})
