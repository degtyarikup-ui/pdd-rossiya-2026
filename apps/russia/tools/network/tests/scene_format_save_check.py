"""Real save/reopen/export of format changes, inside a disposable scene library."""
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
import build, check, engine_sync, question_pool, server

sid = 'ticket_9_14'
source_path = build.NET / f'{sid}.json'
original_bytes = source_path.read_bytes()
original = json.loads(original_bytes)
with tempfile.TemporaryDirectory(prefix='scene-format-', dir=build.ROOT / 'scratch') as tmp:
    root = Path(tmp)
    net, sit = root / 'network', root / 'situations'
    net.mkdir(); sit.mkdir()
    shutil.copytree(engine_sync.SIT / sid, sit / sid)
    (net / f'{sid}.json').write_bytes(original_bytes)
    fixture = root / 'compact.json'
    subprocess.run(['node', str(Path(__file__).with_name('scene_format_check.js')), str(fixture)], check=True)
    compact = json.loads(fixture.read_text())
    with ExitStack() as stack:
        for module, name, value in [
            (server, 'NET', net), (server, 'SIT', sit), (server, 'HISTORY', net / 'history'),
            (server, 'PREVIEW', net / 'preview'), (server, 'QUESTION_POOL', question_pool.QuestionPool(network=net)),
            (check, 'NET', net), (build, 'NET', net), (build, 'BUILD', net / 'build'),
            (engine_sync, 'NET', net), (engine_sync, 'SIT', sit),
        ]: stack.enter_context(patch.object(module, name, value))
        engine_sync.engine_base.cache_clear()
        httpd = server.Server(('127.0.0.1', 0), server.Handler)
        worker = threading.Thread(target=httpd.serve_forever, daemon=True); worker.start()
        def request(body=None):
            req = Request(f'http://127.0.0.1:{httpd.server_port}/api/scene/{sid}', data=None if body is None else json.dumps(body).encode(), headers={'Content-Type':'application/json'})
            with urlopen(req, timeout=30) as response: return json.loads(response.read())
        def exported(): return json.loads((sit / sid / 'scene.json').read_text())
        try:
            request(original)
            legacy_export = exported()
            assert 'sceneFormat' not in legacy_export
            request(compact)
            assert request()['scene'] == compact, 'all source data survives save/reopen'
            runtime = exported()
            assert runtime['crop'] == 45 and runtime['startZ'] == -45
            assert runtime['sceneFormat'] == 'compact'
            mask = runtime['roadMask']
            assert mask['x'] == mask['z'] == -45
            assert mask['width'] * mask['cell'] == mask['height'] * mask['cell'] == 90
            assert runtime['stopZ'] == compact['stop']['z']
            assert len(runtime['actors']) == len(legacy_export['actors'])
            for key in ('text', 'spec', 'correctAnswerIndex', 'trafficLights', 'requiredStop', 'redWait'):
                assert runtime.get(key) == legacy_export.get(key), key
            # Explicitly returning to the original format restores its runtime footprint.
            standard = copy.deepcopy(original)
            standard['sceneFormat'] = 'standard'
            request(standard)
            assert exported()['crop'] == 90 and exported()['startZ'] == -90
            assert request()['scene'] == standard
            # Restoring an old source leaves the exported legacy representation unchanged.
            request(original)
            assert exported() == legacy_export
            assert request()['scene'] == original
        finally:
            httpd.shutdown(); httpd.server_close(); worker.join()
            engine_sync.engine_base.cache_clear()
assert source_path.read_bytes() == original_bytes
print('Scene format HTTP save/reopen/export: 90/180m footprints, masks, question/actor preservation and exact legacy restoration PASS')
