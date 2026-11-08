import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / 'assets/countries/ru/questions'

def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools/ru_content' / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

class ReleaseContentTests(unittest.TestCase):
    def test_official_amendment_survives_regeneration_and_all_languages(self):
        amendment = json.loads((ROOT / 'tools/ru_content/amendment_2026_1088.json').read_text())
        parsed = module('parse_pdd').parse_section(ROOT / 'tools/ru_content/raw/pdd2.html', 2)
        self.assertEqual(parsed, json.loads((CONTENT / 'pdd_sections.json').read_text())[1])
        self.assertEqual(parsed['content'].count(amendment['footnoteAddition']), 1)
        self.assertLess(parsed['content'].index(amendment['footnoteAddition']), parsed['content'].index('- водительское удостоверение'))
        for language, sentence in amendment['translations'].items():
            sections = json.loads((CONTENT / f'pdd_sections_{language}.json').read_text())
            self.assertEqual(sections[1]['content'].count(sentence), 1)

    def test_repaired_diagrams_are_present_and_coordinate_bound(self):
        manifest = json.loads((ROOT / 'tools/ru_content/question_image_repairs.json').read_text())
        self.assertEqual(len(manifest['images']), 23)
        for image in manifest['images']:
            self.assertEqual(hashlib.sha256((ROOT / image['path']).read_bytes()).hexdigest(), image['sha256'])
            for lang in ['', '_en', '_kk']:
                tickets = json.loads((CONTENT / f"questions_{image['category']}{lang}.json").read_text())['tickets']
                question = next(t for t in tickets if t['number'] == image['ticket'])['questions'][image['number'] - 1]
                self.assertEqual(question['image'], image['newImage'])
        for category in ['ab', 'cd']:
            diagrams = {(r['ticket'], r['number']): r['sha256'] for r in manifest['images'] if r['category'] == category}
            for first, second in [((1,15),(9,15)),((4,9),(30,2)),((8,8),(10,8)),((23,1),(38,1))]:
                self.assertNotEqual(diagrams[first], diagrams[second])

    def test_identity_repair_is_idempotent(self):
        dest = ROOT / 'output/release-fixes-2026-10-18/content/identity-fixture'
        if dest.exists(): shutil.rmtree(dest)
        (dest / 'lib/data/models').mkdir(parents=True)
        shutil.copytree(CONTENT, dest / 'assets/countries/ru/questions')
        (dest / 'tools/ru_content').mkdir(parents=True)
        shutil.copy(ROOT / 'tools/ru_content/question_image_repairs.json', dest / 'tools/ru_content/question_image_repairs.json')
        tool = module('repair_question_identity')
        self.assertEqual(tool.repair(dest), {'ab': 6, 'cd': 5})
        files = [p for p in dest.rglob('*') if p.is_file()]
        first = {p: p.read_bytes() for p in files}
        tool.repair(dest)
        self.assertEqual(first, {p: p.read_bytes() for p in files})
        for p in files:
            relative = p.relative_to(dest)
            self.assertEqual(p.read_bytes(), (ROOT / relative).read_bytes(), str(relative))

if __name__ == '__main__': unittest.main()
