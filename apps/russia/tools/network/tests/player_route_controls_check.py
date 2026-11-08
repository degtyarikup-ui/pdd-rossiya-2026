#!/usr/bin/env python3
"""Build/export new sparse arrows into scratch for native runtime verification."""
import copy
import json
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build
import check
import engine_sync

folder = check.ROOT / 'scratch' / 'route-controls-check'
folder.mkdir(parents=True, exist_ok=True)
fixture = folder / 'fixture.json'
subprocess.run(['node', str(HERE / 'player_route_controls_check.js'), str(fixture)], check=True)
data = json.loads(fixture.read_text())
source = data['scene']
before = copy.deepcopy(source)
errors = [item for item in check.check_scene(source) if item['level'] == 'error']
assert not errors, errors
data['build'] = build.build(source)
target = folder / 'situations' / source['id']
target.mkdir(parents=True, exist_ok=True)
archived = copy.deepcopy(engine_sync.engine_base('ticket_27_14'))
with patch.object(check, 'load', return_value=source), \
        patch.object(engine_sync, 'SIT', target.parent), \
        patch.object(engine_sync, 'engine_base', return_value=archived):
    engine_sync.sync(source['id'])
data['exported'] = json.loads((target / 'scene.json').read_text())
for route in source['routes']:
    if route['kind'] == 'manoeuvre':
        assert data['exported']['exits'][route['exit']]['points'] == route['points']
assert source == before, 'export never changes source geometry or manual path controls'
fixture.write_text(json.dumps(data), encoding='utf-8')
print('Sparse player routes: validation, surfaces and exact export PASS; runtime fixture:', fixture)
