"""Flashing green persists through the real HTTP editor and exports its answer-gated runtime state."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from contextlib import ExitStack
from unittest.mock import patch
from urllib.request import Request,urlopen
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build,check,engine_sync,question_pool,server

with tempfile.TemporaryDirectory(prefix='flashing-green-',dir=build.ROOT/'scratch') as tmp:
    root=Path(tmp);net=root/'network';sit=root/'situations';net.mkdir();sit.mkdir()
    # Stage one real standard signal model; every write/copy remains inside this disposable tree.
    for part in engine_sync.SIT.glob('*/parts/light_0.glb'):
        engine=part.parents[1]/'engine.json'
        if not engine.exists():continue
        light=json.loads(engine.read_text()).get('lights',[{}])[0]
        if light.get('arrow') or light.get('tram'):continue
        target=sit/part.parents[1].name; (target/'parts').mkdir(parents=True)
        shutil.copy(part,target/'parts/light_0.glb');shutil.copy(engine,target/'engine.json');break
    else:raise AssertionError('A standard signal fixture is available')
    with ExitStack() as stack:
        for module,name,value in [(server,'NET',net),(server,'SIT',sit),(server,'HISTORY',net/'history'),
                (server,'PREVIEW',net/'preview'),(server,'QUESTION_POOL',question_pool.QuestionPool(network=net)),
                (check,'NET',net),(build,'NET',net),(build,'BUILD',net/'build'),(engine_sync,'NET',net),(engine_sync,'SIT',sit)]:
            stack.enter_context(patch.object(module,name,value))
        engine_sync.engine_base.cache_clear()
        httpd=server.Server(('127.0.0.1',0),server.Handler)
        worker=threading.Thread(target=httpd.serve_forever,daemon=True);worker.start()
        def request(path,body=None):
            req=Request(f'http://127.0.0.1:{httpd.server_port}{path}',data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
            with urlopen(req,timeout=30) as r:return json.load(r)
        try:
            scene=request('/api/scene/ticket_1_6')['scene'];before=copy.deepcopy(scene)
            scene['lights']=[{'id':f'light_{i}','state':'flashing_green','pos':[x,-4],'yaw':0,'scale':1,'arrow':None,'tram':None} for i,x in enumerate([-5,5])]
            scene['question']['redWait']=5 # An archived timer cannot reopen the closing signal.
            response=request('/api/scene/ticket_1_6',scene)
            assert not [f for f in response['findings'] if f['level']=='error'],response['findings']
            saved=request('/api/scene/ticket_1_6')['scene']
            assert saved['lights']==scene['lights']
            assert saved['roads']==before['roads'] and saved['routes']==before['routes']
            runtime=json.loads((sit/'ticket_1_6/scene.json').read_text())
            assert runtime['trafficLights']['state']=='flashing_green' and runtime['redWait'] is None
            for state in ['unknown',[],False,42]:
                bad=copy.deepcopy(scene);bad['lights'][0]['state']=state
                assert any(f['code']=='light-state' for f in check.check_scene(bad))
            for light in scene['lights']:light['state']='red'
            request('/api/scene/ticket_1_6',scene)
            runtime=json.loads((sit/'ticket_1_6/scene.json').read_text())
            assert runtime['trafficLights']['state']=='red' and runtime['redWait']==5
            scene['lights']=[];request('/api/scene/ticket_1_6',scene)
            assert json.loads((sit/'ticket_1_6/scene.json').read_text())['trafficLights'] is None
            assert list((net/'history/ticket_1_6').glob('*.json'))
        finally:
            httpd.shutdown();httpd.server_close();worker.join();engine_sync.engine_base.cache_clear()
    for command,marker in [(['node',str(Path(__file__).with_name('flashing_green_editor_check.js'))],'Flashing green editor:'),
            (['godot','--headless','--path',str(build.ROOT/'game_godot'),'--script','res://tests/flashing_green_check.gd'],'28 checks, 0 failures')]:
        result=subprocess.run(command,capture_output=True,text=True,timeout=60)
        assert result.returncode==0 and marker in result.stdout and 'SCRIPT ERROR' not in result.stderr,result.stdout+result.stderr
        print(result.stdout.strip())
print('Flashing green: HTTP save/reload/history, export, invalid states, legacy timers, deletion and real editor/runtime PASS')
