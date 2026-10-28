"""Annotations: validated source, real save/reload/export, and Godot geometry parity.

Only disposable scratch scenes are written; the author's scenes and decisions are untouched.
"""
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

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build
import check
import engine_sync
import question_pool
import server

with tempfile.TemporaryDirectory(prefix='annotation-lines-',dir=build.ROOT/'scratch') as tmp:
    root=Path(tmp)
    geometry_path=root/'geometry.json'
    subprocess.run(['node',str(Path(__file__).with_suffix('.js')),str(geometry_path)],check=True)
    net,sit=root/'network',root/'situations'
    net.mkdir();sit.mkdir()
    with ExitStack() as stack:
        for module,name,value in [(server,'NET',net),(server,'SIT',sit),(server,'HISTORY',net/'history'),
                                  (server,'PREVIEW',net/'preview'),(server,'QUESTION_POOL',question_pool.QuestionPool(network=net)),
                                  (check,'NET',net),(build,'NET',net),(build,'BUILD',net/'build'),
                                  (engine_sync,'NET',net),(engine_sync,'SIT',sit)]:
            stack.enter_context(patch.object(module,name,value))
        engine_sync.engine_base.cache_clear()
        httpd=server.Server(('127.0.0.1',0),server.Handler)
        worker=threading.Thread(target=httpd.serve_forever,daemon=True);worker.start()
        def request(path,body=None):
            req=Request(f'http://127.0.0.1:{httpd.server_port}{path}',data=json.dumps(body).encode() if body is not None else None,
                        headers={'Content-Type':'application/json'})
            with urlopen(req,timeout=30) as response:return json.load(response)
        try:
            scene=request('/api/scene/ticket_1_12')['scene']
            original=copy.deepcopy(scene)
            scene['routes'].append({'id':'choice_А','kind':'choice','label':'А','points':[[1,-20],[5,-20]],'labelPosition':[5,-20],'arrowhead':False})
            for i,style in enumerate(['line','arrow','both','line','arrow','both']):
                # Some dimensions extend onto the sidewalk; they must not be treated as vehicle paths.
                scene['routes'].append({'id':f'annotation_{i}','kind':'annotation','points':[[1,-22+i*2],[10,-22+i*2]],
                                        'style':style,'colour':'#20242b','width':.16})
            annotations=[r for r in scene['routes'] if r['kind']=='annotation']
            findings=check.check_scene(scene)
            assert not [f for f in findings if f.get('ref',{}).get('id','').startswith('annotation_')],findings
            for changes in ({'points':[]},{'points':[[0,0],[0,0]]},{'points':[[0,0],[float('nan'),1]]},
                            {'style':'unknown'},{'width':True},{'width':8},{'colour':'red'},{'colour':[]}):
                invalid=copy.deepcopy(scene);invalid['routes'][-1].update(changes)
                assert any(f['code']=='annotation-invalid' for f in check.check_scene(invalid))
            response=request('/api/scene/ticket_1_12',scene)
            assert not [f for f in response['findings'] if f['level']=='error']
            saved=request('/api/scene/ticket_1_12')['scene']
            assert saved['routes']==scene['routes']
            assert saved['roads']==original['roads'] and saved['stop']==original['stop']
            exported_path=sit/'ticket_1_12/scene.json'
            exported=json.loads(exported_path.read_text())
            assert len(exported['annotations'])==6 and len(exported['trajectories'])==1
            assert [l['letter'] for l in exported['labels']]==['А']
            assert exported['trajectories'][0]['arrowhead'] is False
            for source,target in zip(annotations,exported['annotations']):
                assert target=={key:source[key] for key in ('points','style','colour','width')}
                assert 'label' not in target
            result=subprocess.run(['godot','--headless','--path',str(build.ROOT/'game_godot'),
                '--script','res://tests/annotation_line_check.gd','--',str(geometry_path),str(exported_path)],
                capture_output=True,text=True,timeout=60)
            assert result.returncode==0 and 'Annotation runtime PASS' in result.stdout,result.stdout+result.stderr
            print(result.stdout.strip())
            scene['routes']=[r for r in scene['routes'] if r['kind']!='annotation']
            request('/api/scene/ticket_1_12',scene)
            assert json.loads(exported_path.read_text())['annotations']==[], 'deleted annotations cannot reappear from the engine base'
            assert list((net/'history/ticket_1_12').glob('*.json'))
        finally:
            httpd.shutdown();httpd.server_close();worker.join();engine_sync.engine_base.cache_clear()
print('Annotations: no letters/choice limit, independent export, validation, HTTP save/reload/delete/history and Godot PASS')
