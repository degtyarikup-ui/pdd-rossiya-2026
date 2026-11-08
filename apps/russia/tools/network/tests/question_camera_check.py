#!/usr/bin/env python3
"""Free camera data survives export; invalid frames are caught without changing authored scenes."""
import copy
import json
import math
from pathlib import Path
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import check
import engine_sync

target = check.ROOT / 'scratch' / 'question-camera-check' / 'situations' / 'fixture'
target.mkdir(parents=True, exist_ok=True)
source = check.load('ticket_3_13')
source['actors'] = []
source['lights'] = []
source.pop('questionView', None)
archived = copy.deepcopy(engine_sync.engine_base('ticket_3_13'))
archived['questionView'] = {'centre': [99, 99], 'height': 10, 'yaw': 2}
legacy = {'centre': [-1.75, -8], 'height': 28}
free = {'centre': [19.25, -17.8], 'height': 1.5,
        'yaw': math.radians(179), 'pitch': math.radians(10), 'elevation': 2.6}
cases = [('automatic', None), ('legacy', legacy), ('free', free),
         ('top', {**free, 'pitch': math.radians(85), 'elevation': 30})]
reference = None
for name, view in cases:
    scene = copy.deepcopy(source)
    if view is not None:
        scene['questionView'] = copy.deepcopy(view)
    before = copy.deepcopy(scene)
    errors = []
    check.check_question_view(scene, errors)
    assert not errors, (name, errors)
    with patch.object(check, 'load', return_value=scene), \
            patch.object(engine_sync, 'SIT', target.parent), \
            patch.object(engine_sync, 'engine_base', return_value=archived):
        engine_sync.sync('fixture')
    exported = json.loads((target / 'scene.json').read_text())
    assert exported.pop('questionView', None) == view, name
    if reference is None:
        reference = exported
    else:
        assert exported == reference, (name, 'camera must not affect drive or answer data')
    assert scene == before, (name, 'source must remain untouched')

invalid = [False, [], {}, {**free, 'centre': [0]}, {**free, 'centre': [0, float('nan')]},
           {**free, 'centre': [False, 0]}, {**free, 'height': 0}, {**free, 'height': '10'},
           {**free, 'yaw': float('inf')}, {**free, 'pitch': 0},
           {**free, 'pitch': math.pi / 2}, {**free, 'elevation': None}]
for view in invalid:
    errors = []
    check.check_question_view({'questionView': view}, errors)
    assert len(errors) == 1 and errors[0]['code'] == 'question-camera', view

print(f'Question camera export: {len(cases)} poses, automatic reset, unchanged driving; '
      f'{len(invalid)} invalid frames detected PASS')
