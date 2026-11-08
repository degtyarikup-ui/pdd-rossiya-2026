"""Zigzag paint: JS/Python parity, clipping, real HTTP save/reload and Godot road mesh."""
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from contextlib import ExitStack
from unittest.mock import patch
from urllib.request import Request,urlopen
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build,check,bus_stop_marking as bus,engine_sync,question_pool,server
from shapely.geometry import Polygon
from shapely.ops import unary_union

def surface_geometry(surface):
    pts=list(zip(surface['verts'][::2],surface['verts'][1::2]))
    return unary_union([Polygon([pts[j] for j in surface['idx'][i:i+3]]) for i in range(0,len(surface['idx']),3)])

with tempfile.TemporaryDirectory(prefix='bus-stops-',dir=build.ROOT/'scratch') as tmp:
    root=Path(tmp);fixtures=root/'geometry.json'
    subprocess.run(['node',str(Path(__file__).with_suffix('.js')),str(fixtures)],check=True)
    for fixture in json.loads(fixtures.read_text()):
        mark=fixture['mark'];expected=Polygon(fixture['polygons'][0]).buffer(0);actual=bus.geometry(mark)
        assert actual.is_valid and actual.area>0
        assert actual.symmetric_difference(expected).area<1e-8
        assert all(math.dist(a,b)<1e-9 for a,b in zip(bus.line(mark),fixture['line']))
    base={'id':'bus-stop','type':'bus_stop','points':[[-3,-20],[-3,0]],'side':-1,'depth':1.2,'step':1.5,'width':.12,'colour':'yellow'}
    tooth=bus.line(base);pitch=20/((len(tooth)-1)/2)
    assert 2*math.atan(pitch/2/base['depth'])<math.pi/2,'default teeth have acute points'
    assert bus.geometry(base).bounds[2]-bus.geometry(base).bounds[0]<1.5,'default occupies a kerbside band, not the carriageway'
    for changes in ({'points':[]},{'points':[[0,0],[0,0]]},{'points':[[0,0],[0,61]]},
                    {'points':[[0,0],[True,5]]},{'points':[[0,0],[float('nan'),5]]},
                    {'depth':0},{'depth':4},{'step':0},{'step':float('inf')},{'width':True},{'width':.5},{'side':0},{'side':True},{'colour':'white'}):
        invalid={**base,**changes};assert bus.error(invalid) and bus.geometry(invalid).is_empty,invalid
        findings=[];check.check_layers({'markings':[invalid]},Polygon([[-5,-30],[5,-30],[5,30],[-5,30]]),findings)
        assert any(f['code']=='marking-bus-stop' for f in findings)
    road={'id':'road','outer':[[-4,-25],[4,-25],[4,25],[-4,25]],'holes':[[[-2,-10],[0,-10],[0,-5],[-2,-5]]]}
    scene={'id':'clip','crop':30,'roads':[road],'lawns':[],'routes':[],'actors':[],'lights':[],'decor':[],
           'markings':[{**base,'points':[[-3.5,-20],[-3.5,20]],'depth':3}]}
    output=build.build(scene);paint=surface_geometry(next(s for s in output['surfaces'] if s['id']=='marking_yellow'))
    area,islands,_=build.road_geometry(scene)
    assert paint.difference(area.buffer(.003)).area<.001,'never paint the pavement'
    assert paint.intersection(islands.buffer(-.003)).area<.001,'never paint islands'
    findings=[];check.check_layers(scene,area,findings)
    assert any(f['code']=='marking-off-road' for f in findings)
    net,sit=root/'network',root/'situations';net.mkdir();sit.mkdir()
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
            scene=request('/api/scene/ticket_1_8')['scene'];before=copy.deepcopy(scene)
            mark={**base,'points':[[-3,15],[-3,35]]};scene['markings'].append(mark)
            response=request('/api/scene/ticket_1_8',scene)
            assert not [f for f in response['findings'] if f['level']=='error'],response['findings']
            saved=request('/api/scene/ticket_1_8')
            assert saved['scene']['markings']==scene['markings']
            assert saved['scene']['roads']==before['roads'] and saved['scene']['routes']==before['routes']
            paint=surface_geometry(next(s for s in saved['build']['surfaces'] if s['id']=='marking_yellow'))
            assert bus.geometry(mark).difference(paint.buffer(.003)).area<.002
            result=subprocess.run(['godot','--headless','--quit-after','2','--path',str(build.ROOT/'game_godot'),
                '--script','res://tests/bus_stop_marking_check.gd','--',str(net/'build/ticket_1_8.json')],capture_output=True,text=True,timeout=60)
            assert result.returncode==0 and 'Bus stop runtime PASS' in result.stdout,result.stdout+result.stderr
            print(result.stdout.strip())
            scene['markings'][-1]['depth']=.8;request('/api/scene/ticket_1_8',scene)
            assert list((net/'history/ticket_1_8').glob('*.json'))
        finally:
            httpd.shutdown();httpd.server_close();worker.join();engine_sync.engine_base.cache_clear()
print('Bus stops: 216 JS/Python shape fixtures, sharp narrow defaults, invalid data, road/island clipping, HTTP save/reload/history and Godot PASS')
