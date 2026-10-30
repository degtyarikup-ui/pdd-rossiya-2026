"""Numeric sign validation, disposable HTTP save/reload/export, and pixel parity with Godot."""
import json
import sys
import tempfile
import threading
import subprocess
from pathlib import Path
from contextlib import ExitStack
from unittest.mock import patch
from urllib.request import Request, urlopen
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build, check, engine_sync, question_pool, server, number_sign

with tempfile.TemporaryDirectory(prefix='number-signs-',dir=build.ROOT/'scratch') as tmp:
    root=Path(tmp);net=root/'network';sit=root/'situations';net.mkdir();sit.mkdir()
    for code in number_sign.CODES:
        for value in [1,20,40,90,130,150] + ([3.5,500] if code not in ('3.24','3.25','4.6','4.7','6.2') else []): (root/f'{code}_{value}.svg').write_text(number_sign.svg(code,value))
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
            with urlopen(req,timeout=30) as r:return r.read()
        try:
            scene=json.loads(request('/api/scene/ticket_1_12'))['scene']
            scene['signs']=[{'id':'number_fixture','code':'3.24','number':40,'pos':[-6,-12],'yaw':0,'plateSign':'8.16','secondSign':{'code':'3.25','number':90}}]
            assert not [f for f in check.check_scene(scene) if f['code']=='sign-number']
            for bad in [True,0,151,40.5,'40',None]:
                scene['signs'][0]['number']=bad
                assert any(f['code']=='sign-number' for f in check.check_scene(scene)),bad
            scene['signs'][0]['number']=40
            response=json.loads(request('/api/scene/ticket_1_12',scene))
            assert not [f for f in response['findings'] if f['level']=='error'],response['findings']
            assert json.loads(request('/api/scene/ticket_1_12'))['scene']['signs']==scene['signs']
            runtime_network=json.loads((net/'ticket_1_12.json').read_text())
            assert runtime_network['signs']==scene['signs']
            assert request('/asset/sign/3.24_40.svg').decode()==number_sign.svg('3.24',40)
        finally:
            httpd.shutdown();httpd.server_close();worker.join();engine_sync.engine_base.cache_clear()
    result=subprocess.run(['godot','--headless','--quit-after','2','--path',str(build.ROOT/'game_godot'),'--script','res://tests/number_sign_check.gd','--',str(root)],capture_output=True,text=True,timeout=60)
    assert result.returncode==0 and 'Numeric speed signs runtime PASS' in result.stdout,result.stdout+result.stderr
    print(result.stdout)
print('Numeric signs: validation, HTTP asset/save/reload, exported top/bottom faces and Godot parity PASS')
