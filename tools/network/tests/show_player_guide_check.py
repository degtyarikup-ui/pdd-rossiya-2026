#!/usr/bin/env python3
"""Visual guide preferences survive export without changing any drive or answer data."""
import copy
import json
from pathlib import Path
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build
import check
import engine_sync

folder = check.ROOT / 'scratch' / 'player-guide-check'
target = folder / 'situations' / 'fixture'
target.mkdir(parents=True, exist_ok=True)
source = check.load('ticket_3_13')
source['actors'] = []
source['lights'] = []
source['routes'] = [route for route in source['routes'] if route['kind'] != 'choice']
archived = copy.deepcopy(engine_sync.engine_base('ticket_3_13'))
archived['showPlayerGuide'] = False  # A stale archived false must never become the new default.
result = {'source': copy.deepcopy(source), 'build': build.build(source)}
for choices in (False, True):
    scene = copy.deepcopy(source)
    if choices:
        scene['routes'] += [
            {'id': 'choice_a', 'kind': 'choice', 'label': 'А',
             'points': [[-1.75, -10], [10, 1.75]], 'labelPosition': [10, 1.75]},
            {'id': 'choice_b', 'kind': 'choice', 'label': 'Б', 'arrowhead': False,
             'points': [[-1.75, -10], [-10, -1.75]], 'labelPosition': [-10, -1.75]},
        ]
    exports = {}
    for name, value in (('missing', None), ('off', False), ('on', True), ('null', None), ('zero', 0)):
        if name == 'missing':
            scene['question'].pop('showPlayerGuide', None)
        else:
            scene['question']['showPlayerGuide'] = value
        before = copy.deepcopy(scene)
        with patch.object(check, 'load', return_value=scene), \
                patch.object(engine_sync, 'SIT', target.parent), \
                patch.object(engine_sync, 'engine_base', return_value=archived):
            engine_sync.sync('fixture')
        exported = json.loads((target / 'scene.json').read_text())
        assert exported['showPlayerGuide'] is (value is not False), (choices, name)
        assert scene == before, 'export never modifies the authored network'
        exports[name] = exported
    reference = copy.deepcopy(exports['on'])
    reference.pop('showPlayerGuide')
    for name, exported in exports.items():
        actual = copy.deepcopy(exported)
        actual.pop('showPlayerGuide')
        assert actual == reference, (choices, name, 'only visual preference may differ')
    if choices:
        assert [item['label'] for item in exports['off']['trajectories']] == ['А', 'Б']
        assert [item['letter'] for item in exports['off']['labels']] == ['А', 'Б']
    result['choices' if choices else 'fallback'] = exports
(folder / 'fixture.json').write_text(json.dumps(result), encoding='utf-8')
print('Player guide export: explicit off/default reset, unchanged complete drive data and choice guides PASS')
