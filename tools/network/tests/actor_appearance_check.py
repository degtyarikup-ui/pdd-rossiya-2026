"""Actor pose/sidecar/source preservation and actual HTTP save/export using disposable scenes."""
import copy
from contextlib import ExitStack
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch
from urllib.request import Request,urlopen

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build,check,engine_sync,question_pool,server

catalog=server.Handler.catalog(None)
original_sit=server.SIT
with tempfile.TemporaryDirectory(prefix='actor-appearance-',dir=build.ROOT/'scratch') as tmp:
    root=Path(tmp);net=root/'network';sit=root/'situations';net.mkdir();sit.mkdir()
    fixtures=root/'vertices.json'
    subprocess.run(['node',str(Path(__file__).with_suffix('.js')),str(fixtures)],check=True)
    for typ in ('pedestrian','motorcycle','car'):
        asset=catalog['actorTypes'][typ]['asset'];source,fname=asset.split('/')
        target=sit/source;(target/'parts').mkdir(parents=True,exist_ok=True)
        shutil.copy2(original_sit/source/'engine.json',target/'engine.json')
        part=original_sit/source/'parts'/fname
        if not part.exists():part=original_sit/source/fname
        shutil.copy2(part,target/'parts'/fname)
    with ExitStack() as stack:
        for module,name,value in [(server,'NET',net),(server,'SIT',sit),(server,'HISTORY',net/'history'),
                                  (server,'PREVIEW',net/'preview'),(server,'QUESTION_POOL',question_pool.QuestionPool(network=net)),
                                  (check,'NET',net),(build,'NET',net),(build,'BUILD',net/'build'),
                                  (engine_sync,'NET',net),(engine_sync,'SIT',sit)]:stack.enter_context(patch.object(module,name,value))
        engine_sync.engine_base.cache_clear()
        httpd=server.Server(('127.0.0.1',0),server.Handler);worker=threading.Thread(target=httpd.serve_forever,daemon=True);worker.start()
        def request(path,body=None):
            req=Request(f'http://127.0.0.1:{httpd.server_port}{path}',data=json.dumps(body).encode() if body is not None else None,headers={'Content-Type':'application/json'})
            with urlopen(req,timeout=30) as response:return json.load(response)
        try:
            scene=request('/api/scene/ticket_2_3')['scene'];original=copy.deepcopy(scene)
            for typ,pos in [('pedestrian',[8,20]),('motorcycle',[3.5,20]),('car',[-3.5,20])]:
                template=catalog['actorTypes'][typ]
                scene['actors'].append({'id':typ,'type':typ,'asset':template['asset'],'name':typ,'pos':pos,'yaw':.4,'scale':[1,1,1],
                    'halfWidth':template['halfWidth'],'halfLength':template['halfLength'],'behaviour':{'staysPut':True,'waitsForPlayer':True}})
            person,moto,car=scene['actors'];car['driverSignal']='raised';car['behaviour']['turnSignal']='right';car['behaviour']['staysPut']=False;car['route']='lane-change';scene['routes'].append({'id':'lane-change','kind':'actor','manual':True,'points':[[-3.5,20],[-3.5,25],[0,35],[0,45]]});original['routes']=copy.deepcopy(scene['routes']);scene['tracks']=[{'id':'railway','render':True,'points':[[-30,0],[30,0]]}];person.update(pedestrianPose='hail',poseArm='left',pedestrianLook=0);moto['sidecar']=False
            scene['signs']=[{'id':'zone','code':'5.33','zoneVariant':'plain','pos':[8,12],'yaw':0}]
            for changes in ({'pedestrianPose':'invalid'},{'poseArm':'invalid'},{'pedestrianLook':True}):
                invalid=copy.deepcopy(scene);invalid['actors'][0].update(changes)
                assert any(f['code']=='actor-appearance' for f in check.check_scene(invalid))
            response=request('/api/scene/ticket_2_3',scene)
            assert not [f for f in response['findings'] if f['level']=='error'],response
            saved=request('/api/scene/ticket_2_3')['scene']
            assert saved['actors']==scene['actors'] and saved['signs']==scene['signs']
            assert saved['routes']==original['routes'] and saved['roads']==original['roads']
            exported_path=sit/'ticket_2_3/scene.json';exported=json.loads(exported_path.read_text())
            ped=next(a for a in exported['actors'] if a['type']=='pedestrian');bike=next(a for a in exported['actors'] if a['type']=='motorcycle')
            exported_car=next(a for a in exported['actors'] if a['type']=='car')
            assert exported_car['driverSignal']=='raised' and exported_car['turnSignal']=='right'
            assert exported_car['path']==[[-3.5,0.0,20],[-3.5,0.0,25],[0,0.0,35],[0,0.0,45]]
            assert any(s['id']=='authored_rails' and s['idx'] for s in build.build(saved)['surfaces'])
            assert ped['pedestrianPose']=='hail' and ped['poseArm']=='left' and ped['pedestrianLook']==0
            assert bike['config']['sidecar'] is False and abs(bike['halfWidth']-.34)<.001
            result=subprocess.run(['godot','--headless','--path',str(build.ROOT/'game_godot'),'--script','res://tests/actor_appearance_check.gd','--',str(fixtures),str(exported_path)],capture_output=True,text=True,timeout=60)
            assert result.returncode==0 and 'Actor appearance runtime PASS' in result.stdout,result.stdout+result.stderr
            print(result.stdout.strip())
            moto['sidecar']=True;request('/api/scene/ticket_2_3',scene)
            bike=next(a for a in json.loads(exported_path.read_text())['actors'] if a['type']=='motorcycle')
            assert bike['config']['sidecar'] is True and abs(bike['halfWidth']-.957)<.001
            del moto['sidecar'];person['pedestrianPose']='stand';request('/api/scene/ticket_2_3',scene)
            exported=json.loads(exported_path.read_text());bike=next(a for a in exported['actors'] if a['type']=='motorcycle')
            assert bike['config']['sidecar']==catalog['actorTypes']['motorcycle']['sidecar'],'Legacy sidecar is preserved when no override is authored'
        finally:httpd.shutdown();httpd.server_close();worker.join();engine_sync.engine_base.cache_clear()
print('Actor appearance: HTTP save/reload, validation, poses, sidecar on/off/legacy bounds, plain sign and Godot PASS')
