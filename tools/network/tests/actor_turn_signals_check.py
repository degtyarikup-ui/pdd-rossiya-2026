#!/usr/bin/env python3
"""Real inspector source -> real game export, with disposable fixtures under scratch."""
import copy
import json
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import check
import engine_sync

folder = check.ROOT / 'scratch' / 'actor-turn-signals-check'
sit = folder / 'situations'
net = folder / 'network'
output = sit / 'fixture'
template = sit / 'template'
for directory in (output, template / 'parts', net):
    directory.mkdir(parents=True, exist_ok=True)
fixtures = folder / 'sources.json'
subprocess.run(['node', str(HERE / 'actor_turn_signals_check.js'), str(fixtures)], check=True)
archived = copy.deepcopy(engine_sync.engine_base('ticket_19_13'))
archived['actors'][0]['turnSignal'] = 'left'  # A stale model override must be cleared by Auto.
(template / 'engine.json').write_text(json.dumps(archived))
(output / 'engine.json').write_text(json.dumps(archived))
(template / 'parts' / 'actor_0.glb').write_bytes(b'disposable turn signal model')
results = []
engine_sync.engine_base.cache_clear()
try:
    with patch.object(check, 'NET', net), patch.object(engine_sync, 'SIT', sit):
        for case in json.loads(fixtures.read_text()):
            source = case['scene']
            actor = source['actors'][0]
            actor['asset'] = 'template/actor_0.glb'
            before = copy.deepcopy(source)
            (net / 'fixture.json').write_text(json.dumps(source))
            engine_sync.sync('fixture')
            exported = json.loads((output / 'scene.json').read_text())['actors'][0]
            setting = actor['behaviour'].get('turnSignal', 'auto')
            assert exported['turnSignal'] == setting
            assert exported['way'] == actor.get('way')
            assert exported['staysPut'] == actor['behaviour']['staysPut']
            assert exported['waitsForPlayer'] == actor['behaviour']['waitsForPlayer']
            assert exported['signalPlan'] == actor['behaviour']['signalPlan']
            route = next((r for r in source['routes'] if r['id'] == actor.get('route')), None)
            position = [actor['pos'][0], 0.0, actor['pos'][1]]
            assert exported['path'] == ([[x,0.0,z] for x,z in route['points']] if route else [position,position])
            assert source == before and check.load('fixture') == before
            results.append({'name':case['name'],'side':case['side'],'actor':exported,'source':source})
finally:
    engine_sync.engine_base.cache_clear()
(folder / 'fixture.json').write_text(json.dumps(results))
print(f'Actor turn signals export: {len(results)} fixtures, automatic reset and unchanged movement PASS')
