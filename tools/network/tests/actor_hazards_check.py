#!/usr/bin/env python3
"""Editor sources -> exported scene, using only disposable files under scratch.

    tools/network/.venv/bin/python tools/network/tests/actor_hazards_check.py
"""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import check
import engine_sync


def write(path, data):
    path.write_text(json.dumps(data), encoding='utf-8')


archived = json.loads((engine_sync.SIT / 'ticket_33_8/engine.json').read_text(encoding='utf-8'))
assert archived['actors'][0]['config']['hazard'] is True

with tempfile.TemporaryDirectory(prefix='actor-hazards-', dir=check.ROOT / 'scratch') as tmp:
    temp = Path(tmp)
    fixtures = temp / 'sources.json'
    subprocess.run(['node', str(HERE / 'actor_hazards_check.js'), str(fixtures)], check=True)
    sit, net = temp / 'situations', temp / 'network'
    template, output = sit / 'hazard-template', sit / 'fixture'
    (template / 'parts').mkdir(parents=True)
    output.mkdir(parents=True)
    net.mkdir()
    write(template / 'engine.json', archived)
    write(output / 'engine.json', archived)
    # Geometry is irrelevant to this export test; a copyable pristine part exercises
    # the real template lookup/copy without modifying any authored GLB or scene.
    (template / 'parts/actor_0.glb').write_bytes(b'disposable actor fixture')
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(check, 'NET', net), patch.object(engine_sync, 'SIT', sit):
            for fixture in json.loads(fixtures.read_text()):
                source = copy.deepcopy(fixture['scene'])
                actor = source['actors'][0]
                actor['asset'] = 'hazard-template/actor_0.glb'
                source['lights'] = []
                write(net / 'fixture.json', source)
                before = copy.deepcopy(source)
                engine_sync.sync('fixture')
                exported = json.loads((output / 'scene.json').read_text())['actors'][0]
                name = fixture['name']
                assert exported['hazards'] is fixture['expected'], name
                assert exported['config']['hazard'] is fixture['expected'], name
                assert exported['staysPut'] is actor['behaviour']['staysPut'], name
                for key in ('waitsForPlayer', 'stopAtDistance', 'stopFor', 'holdFor', 'signalPlan'):
                    if key in actor['behaviour']:
                        assert exported[key] == actor['behaviour'][key], (name, key)
                position = [actor['pos'][0], 0.0, actor['pos'][1]]
                assert exported['pos'] == position and exported['yaw'] == actor['yaw'], name
                route = next((r for r in source['routes'] if r['id'] == actor['route']), None)
                if route:
                    assert exported['path'] == [[x, 0.0, z] for x, z in route['points']], name
                    assert exported['length'] == engine_sync.length_of(route['points']), name
                else:
                    assert exported['path'] == [position, position] and exported['length'] == 0.0, name
                assert check.load('fixture') == before, 'export leaves the author source intact'
                assert (output / 'actor_0.glb').read_bytes() == b'disposable actor fixture'
                print(f'PASS {name}: hazards/behaviour/path/export')
    finally:
        engine_sync.engine_base.cache_clear()

print('Actor emergency signals pipeline: all checks passed')
