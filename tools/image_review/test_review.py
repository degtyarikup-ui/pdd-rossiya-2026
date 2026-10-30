import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('review', Path(__file__).with_name('server.py'))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

class ReviewTest(unittest.TestCase):
    def test_export_only_flagged_official_images_and_persist_notes(self):
        with tempfile.TemporaryDirectory() as temp:
            review.DATA = Path(temp)/'data'
            (review.DATA/'official').mkdir(parents=True)
            (review.DATA/'official/a.jpg').write_bytes(b'official-image')
            (review.DATA/'ours.jpg').write_bytes(b'app-image-must-not-export')
            q = dict(key='01-02', ticketNumber=1, questionNumber=2, official=dict(file='a.jpg',url='https://example.test/original.pdf'))
            with review.db() as con:
                con.execute('INSERT INTO reviews VALUES (?,?,?)', ('01-02','fix','Wrong sign'))
                con.execute('INSERT INTO reviews VALUES (?,?,?)', ('01-03','ok',''))
            self.assertEqual(review.state()['01-02']['note'], 'Wrong sign')
            result=review.export_selection([q,dict(q,key='01-03')],Path(temp)/'desktop')
            folder=Path(result['path'])
            self.assertEqual(result['count'],1)
            self.assertEqual((folder/'Билет_01_Вопрос_02.jpg').read_bytes(), b'official-image')
            self.assertEqual(len(list(folder.iterdir())),2)
            self.assertEqual(json.loads((folder/'Источники.json').read_text())[0]['key'],'01-02')
            with review.db() as con:
                con.execute('UPDATE reviews SET status="new"')
            with self.assertRaises(ValueError):
                review.export_selection([q],Path(temp)/'desktop')

    def test_missing_reference_does_not_create_incomplete_export(self):
        with tempfile.TemporaryDirectory() as temp:
            review.DATA=Path(temp)
            with review.db() as con:
                con.execute('INSERT INTO reviews VALUES (?,?,?)', ('02-01','fix',''))
            with self.assertRaises(ValueError):
                review.export_selection([dict(key='02-01',official=None)],Path(temp)/'desktop')
            self.assertFalse((Path(temp)/'desktop').exists())

if __name__=='__main__': unittest.main()
