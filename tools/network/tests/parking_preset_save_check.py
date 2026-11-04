"""Real editor placement, save/reopen and game export, using disposable scene files only."""
import copy
import json
import shutil
import subprocess
import sys
import tempfile
import threading
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build, check, engine_sync, parking_catalog, question_pool, server
from surface_support import SurfaceSupport

index = json.loads(server.SCENERY.read_text())
catalog = parking_catalog.load(server.GAME / 'scenery/parking/catalog.json', index['props'])
assert len(catalog['names']) >= 20
for prop in catalog['names']:
    assert (server.GAME / 'scenery' / f'{prop}.glb').is_file(), prop
    assert prop in index['props'], prop
preset = catalog['presets'][0]
assert preset['id'] == 'fuel_station'
assert sum(p['prop'] == 'parking/fuel_pump' for p in preset['decor']) == 4
assert any(r['surface'] == 'pavement' for r in preset['roads'])
assert all(r['exact'] and not r['walk'] and not r['edge'] for r in preset['roads'])
assert all(0 < h < 35 for h in preset['half']), 'preset excludes long through-road and distant scenery'

sid = 'ticket_9_14'
source_path = build.NET / f'{sid}.json'
original_bytes = source_path.read_bytes()
original = json.loads(original_bytes)
out = build.ROOT / 'scratch/editor-parking-check'
out.mkdir(parents=True, exist_ok=True)
(out / 'catalog.json').write_text(json.dumps(catalog))
(out / 'original.json').write_text(json.dumps(original))
subprocess.run(['node', str(Path(__file__).with_name('parking_presets_check.js')),
                str(out / 'catalog.json'), str(out / 'original.json'), str(out / 'placed.json')], check=True)
placed = json.loads((out / 'placed.json').read_text())
new_ids = {p['id'] for p in placed['decor'] if p['prop'].startswith('parking/')}
assert not [f for f in check.check_scene(placed) if f['code'] == 'prop-on-road' and f.get('ref', {}).get('id') in new_ids]
placed['pockets'] = [dict(id='pocket_test', pos=[4.2, 12], yaw=3.141592653589793,
                          length=14, width=3, entryLength=8, exitLength=6, side='right', walk=True, edge=True)]
with tempfile.TemporaryDirectory(prefix='save-', dir=out) as tmp:
    root = Path(tmp)
    net, sit = root / 'network', root / 'situations'
    net.mkdir(); sit.mkdir()
    shutil.copytree(engine_sync.SIT / sid, sit / sid)
    (net / f'{sid}.json').write_bytes(original_bytes)
    with ExitStack() as stack:
        for module, name, value in [
            (server, 'NET', net), (server, 'SIT', sit), (server, 'HISTORY', net / 'history'),
            (server, 'PREVIEW', net / 'preview'), (server, 'QUESTION_POOL', question_pool.QuestionPool(network=net)),
            (check, 'NET', net), (build, 'NET', net), (build, 'BUILD', net / 'build'),
            (engine_sync, 'NET', net), (engine_sync, 'SIT', sit),
        ]:
            stack.enter_context(patch.object(module, name, value))
        engine_sync.engine_base.cache_clear()
        httpd = server.Server(('127.0.0.1', 0), server.Handler)
        worker = threading.Thread(target=httpd.serve_forever, daemon=True); worker.start()
        def request(body=None):
            req = Request(f'http://127.0.0.1:{httpd.server_port}/api/scene/{sid}',
                          data=None if body is None else json.dumps(body).encode(),
                          headers={'Content-Type': 'application/json'})
            with urlopen(req, timeout=60) as response:
                return json.loads(response.read())
        try:
            request(placed)
            reopened = request()['scene']
            assert reopened == placed, 'all parts and pockets survive HTTP save/reopen'
            runtime = json.loads((sit / sid / 'scene.json').read_text())
            props = [p for p in runtime['props'] if p['prop'].startswith('parking/')]
            authored = [p for p in placed['decor'] if p['prop'].startswith('parking/')]
            support = SurfaceSupport(build.build(placed))
            assert len(props) == len(authored)
            for p, q in zip(props, authored):
                assert p['pos'] == [q['pos'][0], support.height(*q['pos']), q['pos'][1]]
                assert p['yaw'] == q['yaw'] and p['scale'] == q['scale']
            result = json.loads((net / 'build' / f'{sid}.json').read_text())
            assert result == build.build(placed), 'editor and game consume identical built geometry'
            assert runtime['roadMask'], 'game drive mask is exported'
            # One component remains independent after changing, saving and opening again.
            edited = copy.deepcopy(placed)
            next(p for p in edited['decor'] if p['prop'] == 'parking/fuel_pump')['pos'][0] += 2
            request(edited)
            assert request()['scene'] == edited
            assert edited['roads'] == placed['roads'] and edited['pockets'] == placed['pockets']
            (out / 'build.json').write_text(json.dumps(result))
            (out / 'runtime.json').write_text(json.dumps(runtime))
            request(original)
            assert request()['scene'] == original, 'removing additions restores source exactly'
        finally:
            httpd.shutdown(); httpd.server_close(); worker.join()
            engine_sync.engine_base.cache_clear()
assert source_path.read_bytes() == original_bytes
print('PASS parking catalogue, complete station, independent parts, pockets HTTP save/reopen and Godot export; authored scenes untouched')
