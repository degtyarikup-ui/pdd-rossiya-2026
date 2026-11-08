"""Standalone letters: real HTTP save/reload/history and export, isolated from author scenes."""
import copy
from contextlib import ExitStack
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
import check
import engine_sync
import question_pool
import server

with tempfile.TemporaryDirectory(prefix='answer-marks-', dir=build.ROOT/'scratch') as tmp:
    root = Path(tmp)
    net, sit = root/'network', root/'situations'
    net.mkdir(); sit.mkdir()
    with ExitStack() as stack:
        for module, name, value in [(server,'NET',net),(server,'SIT',sit),(server,'HISTORY',net/'history'),
                (server,'PREVIEW',net/'preview'),(server,'QUESTION_POOL',question_pool.QuestionPool(network=net)),
                (check,'NET',net),(build,'NET',net),(build,'BUILD',net/'build'),
                (engine_sync,'NET',net),(engine_sync,'SIT',sit)]:
            stack.enter_context(patch.object(module,name,value))
        engine_sync.engine_base.cache_clear()
        httpd = server.Server(('127.0.0.1',0),server.Handler)
        worker = threading.Thread(target=httpd.serve_forever,daemon=True); worker.start()
        def request(path, body=None):
            req = Request(f'http://127.0.0.1:{httpd.server_port}{path}',
                data=json.dumps(body).encode() if body is not None else None, headers={'Content-Type':'application/json'})
            with urlopen(req, timeout=30) as response: return json.load(response)
        try:
            scene = request('/api/scene/ticket_1_12')['scene']
            original = copy.deepcopy(scene)
            scene['routes'] = [r for r in scene['routes'] if r['kind'] != 'choice'] + [
                {'id':'choice_А','kind':'choice','label':'А','display':'letter','points':[], 'labelPosition':[25,-20]},
                {'id':'choice_Б','kind':'choice','label':'Б','display':'letter','points':[[0,-15],[5,-15]], 'labelPosition':[25,-15]},
                {'id':'choice_В','kind':'choice','label':'В','arrowhead':False,'points':[[0,-10],[3,-10]], 'labelPosition':[3,-10]},
            ]
            # Letters may stand anywhere, including off the asphalt; hidden paths have no validation footprint.
            assert not [f for f in check.check_scene(scene) if f.get('ref',{}).get('id') in ('choice_А','choice_Б')]
            for bad in (None, [], [1], [True,2], ['1',2], [float('nan'),0], [float('inf'),0]):
                invalid = copy.deepcopy(scene); invalid['routes'][-3]['labelPosition'] = bad
                assert any(f['code']=='label-position' for f in check.check_scene(invalid)), bad
            response = request('/api/scene/ticket_1_12',scene)
            assert not [f for f in response['findings'] if f['level']=='error'], response['findings']
            saved = request('/api/scene/ticket_1_12')['scene']
            assert saved['routes'] == scene['routes'], 'save/reload retains letter display and remembered line'
            assert saved['roads'] == original['roads'] and saved['stop'] == original['stop']
            exported_path = sit/'ticket_1_12/scene.json'
            exported = json.loads(exported_path.read_text())
            assert [t['points'] for t in exported['trajectories']] == [[],[],[[0,-10],[3,-10]]]
            assert [l['pos'] for l in exported['labels']] == [[25,.8,-20],[25,.8,-15],[3,.8,-10]]
            # Only standalone letters: no fallback arrow or remembered route may reappear at runtime.
            scene['routes'] = [r for r in scene['routes'] if r.get('label') != 'В']
            request('/api/scene/ticket_1_12',scene)
            result = subprocess.run(['godot','--headless','--path',str(build.ROOT/'game_godot'),
                '--script','res://tests/answer_mark_check.gd','--',str(exported_path)],capture_output=True,text=True,timeout=60)
            assert result.returncode == 0 and 'Standalone letters runtime PASS' in result.stdout, result.stdout+result.stderr
            print(result.stdout.strip())
            scene['routes'] = [r for r in scene['routes'] if r['kind'] != 'choice']
            request('/api/scene/ticket_1_12',scene)
            exported = json.loads(exported_path.read_text())
            assert not exported['labels'] and not exported['trajectories'], 'deleted letters stay deleted'
            assert list((net/'history/ticket_1_12').glob('*.json'))
        finally:
            httpd.shutdown(); httpd.server_close(); worker.join(); engine_sync.engine_base.cache_clear()
print('Standalone letters: validation, HTTP save/reload/delete/history, preserved paths, mixed export and runtime PASS')
