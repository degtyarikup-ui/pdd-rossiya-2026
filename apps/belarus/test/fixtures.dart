Map<String, dynamic> bankJson({int pdd = 12, int other = 3}) => {
  'schemaVersion': 1,
  'country': 'by',
  'revision': 'unit-test-only',
  'reviewStatus': 'approved',
  'examRulesReviewed': true,
  'sources': [
    {
      'id': 'synthetic',
      'url': 'https://example.com/tests',
      'license': 'Synthetic test fixture; not learning material',
      'revision': '1',
      'checkedAt': '2026-11-09',
      'reviewStatus': 'approved',
    },
  ],
  'questions': List.generate(
    pdd + other,
    (i) => {
      'id': 'by:test:$i',
      'text': 'Fixture $i',
      'answers': ['A', 'B'],
      'correctIndex': 0,
      'subject': i < pdd ? 'pdd' : 'other',
      'sourceId': 'synthetic',
      'explanation': 'Test fixture only',
    },
  ),
};
