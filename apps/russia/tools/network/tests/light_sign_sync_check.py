"""Mounted sign survives the network-to-Godot scene export without changing light orientation."""
import copy
import json
import sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import engine_sync

sid = 'ticket_17_6'
net = copy.deepcopy(check.load(sid))
base = engine_sync.engine_base(sid)
net['actors'] = []
light = net['lights'][0]
light['mountedSigns'] = ['2.4', '8.13']
light['mountedMainRoad'] = ['south', 'east']
out = engine_sync.ROOT / 'scratch' / 'light-signs' / 'sync-check'
out.mkdir(parents=True, exist_ok=True)
with patch.object(check, 'load', return_value=net), patch.object(engine_sync, 'engine_base', return_value=base), patch.object(engine_sync, 'scene_dir', return_value=out), patch.object(engine_sync.shutil, 'copy'):
    engine_sync.sync(sid)
    saved = json.loads((out / 'scene.json').read_text())['lights'][0]
    assert saved['mountedSigns'] == ['2.4', '8.13']
    assert saved['mountedMainRoad'] == ['south', 'east']
    assert saved['yaw'] == light['yaw'] and saved['scale'] == light['scale']
    assert saved['pos'] == [light['pos'][0], 0.0, light['pos'][1]]
    del light['mountedSigns']
    engine_sync.sync(sid)
    assert not json.loads((out / 'scene.json').read_text())['lights'][0].get('mountedSigns')
print('Light sign export: all checks passed')
