"""Mount and lane state round-trip without altering archived ordinary lights."""
import copy
import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import engine_sync

sid = 'ticket_17_6'
net = copy.deepcopy(check.load(sid))
base = engine_sync.engine_base(sid)
net['actors'] = []
legacy = copy.deepcopy(net['lights'][0])
net['lights'] = [dict(legacy, id='reverse', reversible='yellow_left', mount='cantilever', reach=7.5, armSide='right', clearance=6), legacy]
with tempfile.TemporaryDirectory() as folder:
    out = Path(folder)
    with patch.object(check, 'load', return_value=net), patch.object(engine_sync, 'engine_base', return_value=base), patch.object(engine_sync, 'scene_dir', return_value=out), patch.object(engine_sync.shutil, 'copy'):
        before = copy.deepcopy(net)
        engine_sync.sync(sid)
        saved = json.loads((out/'scene.json').read_text())
        for key in ['reversible','mount','reach','armSide','clearance']:
            assert saved['lights'][0][key] == net['lights'][0][key]
            assert key not in saved['lights'][1]
        assert saved['trafficLights']['state'] == legacy['state']
        assert net == before
        net['lights'] = net['lights'][:1]
        engine_sync.sync(sid)
        assert json.loads((out/'scene.json').read_text())['trafficLights']['state'] == 'off'
print('Signal mount export: independent states, mounting, legacy fields and no source mutations PASS')
