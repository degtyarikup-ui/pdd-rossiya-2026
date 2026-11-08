import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
from collect_pddby import Collector, parse_ticket, correct_index


class ParseTicketTest(unittest.TestCase):
    def test_text_answers_and_css_image(self):
        result = parse_ticket({'ticket': '''
          <ul><li class="b-question">Тест&nbsp; <b>вопроса</b>?</li>
          <li><div id="q-img"><b style="background-image: url('/img/tickets/test.jpg')"></b></div>
          <ul id="variants"><li>1. <span>Ответ <em>один</em>.</span></li>
          <li>2. <span>Ответ два.</span></li></ul></li></ul>
          <script>untrusted()</script>'''})
        self.assertEqual(result['text'], 'Тест вопроса?')
        self.assertEqual(result['answers'], ['Ответ один.', 'Ответ два.'])
        self.assertEqual(result['imageUrls'], ['https://pdd.by/img/tickets/test.jpg'])
        self.assertTrue(result['id'].startswith('by:pddby:'))

    def test_missing_markup_fails_instead_of_silently_skipping(self):
        with self.assertRaises(ValueError):
            parse_ticket({'ticket': '<p>Layout changed</p>'})

    def test_image_identity_changes_question_id(self):
        html = '<li class="b-question">Q</li><div id="q-img"><img src="/img/a.jpg"></div><ul id="variants"><li><span>A</span></li><li><span>B</span></li></ul>'
        first = parse_ticket({'ticket': html})
        second = parse_ticket({'ticket': html.replace('a.jpg', 'b.jpg')})
        self.assertNotEqual(first['id'], second['id'])

    def test_foreign_images_rejected(self):
        with self.assertRaises(ValueError):
            parse_ticket({'ticket': '<div id="q-img"><img src="https://other.example/a.jpg"></div>'})

    def test_server_answer_consistency(self):
        self.assertEqual(correct_index({'an': '1', 'answ': '3', 'result': False}, 1, 4), 2)
        self.assertEqual(correct_index({'an': '2', 'answ': '2', 'result': True}, 2, 4), 1)
        for response in [
            {'an': '1', 'answ': '5', 'result': False},
            {'an': '1', 'answ': '1', 'result': False},
            {'an': '2', 'answ': '2', 'result': True},
        ]:
            with self.assertRaises(ValueError):
                correct_index(response, 1, 4)


class FakeCollector(Collector):
    def __init__(self, directory, answer=2):
        super().__init__(directory, 0.35)
        self.answer = answer
        self.number = 1
        self.calls = []

    def fetch(self, path, params=None):
        return None

    def choose_answer(self, question):
        known = self.bank['questions'].get(question['id'])
        return known['correctIndex'] + 1 if known else 1

    def api(self, method, **params):
        self.calls.append((method, params))
        if method in ('start', 'select'):
            self.number = params.get('n', 1)
            return {'current': self.number - 1, 'ticket': f'<li class="b-question">Q{self.number}</li><ul id="variants"><li><span>A</span></li><li><span>B</span></li></ul>'}, 'raw/fake-question.json'
        if method == 'set':
            return {'an': params['n'], 'answ': self.answer, 'result': params['n'] == self.answer}, 'raw/fake-answer.json'
        return {}, 'raw/fake-exit.json'


class CollectorFlowTest(unittest.TestCase):
    def test_practice_choice_uses_observations_but_source_defines_truth(self):
        with tempfile.TemporaryDirectory() as folder:
            c = Collector(Path(folder), 0.35)
            for i in range(5):
                c.bank['questions'][str(i)] = {'answers': ['A', 'B'], 'correctIndex': 1}
            self.assertEqual(c.choose_answer({'id': 'new', 'answers': ['A', 'B']}), 2)
            # A contrary source response must still be stored as answer A.
            self.assertEqual(correct_index({'an': 2, 'answ': 1, 'result': False}, 2, 2), 0)

    @patch('collect_pddby.time.sleep')
    def test_second_wrong_answer_ends_ticket_and_keeps_checkpoint(self, _):
        with tempfile.TemporaryDirectory() as folder:
            c = FakeCollector(Path(folder))
            self.assertEqual(c.ticket(1), 2)
            self.assertEqual([p['n'] for m, p in c.calls if m == 'select'], [2])
            self.assertEqual(c.bank['history'][-1]['answered'], 2)
            self.assertTrue((Path(folder) / 'collected.json').exists())
            self.assertEqual(c.calls[-1][0], 'exit')

    @patch('collect_pddby.time.sleep')
    def test_known_answers_are_rechecked_and_new_answers_are_saved(self, _):
        with tempfile.TemporaryDirectory() as folder:
            c = FakeCollector(Path(folder))
            c.ticket(1)
            c.calls.clear()
            self.assertEqual(c.ticket(1), 2)
            submitted = [p['n'] for m, p in c.calls if m == 'set']
            self.assertEqual(submitted, [2, 2, 1, 1])
            self.assertEqual(len(c.bank['questions']), 4)


if __name__ == '__main__':
    unittest.main()
