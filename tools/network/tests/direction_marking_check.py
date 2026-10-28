"""Lane-arrow geometry, real HTTP save/reload/export and Godot-ready triangles.

All generated scenes and history live in a disposable scratch directory.
"""
import copy
from contextlib import ExitStack
import json
import math
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
import direction_marking as arrows
import engine_sync
import question_pool
import server
from shapely.geometry import Polygon
from shapely.ops import unary_union


def surface_polygon(surface):
    points = list(zip(surface['verts'][::2], surface['verts'][1::2]))
    return unary_union([Polygon([points[j] for j in surface['idx'][i:i+3]])
                        for i in range(0, len(surface['idx']), 3)])


with tempfile.TemporaryDirectory(prefix='direction-marking-', dir=build.ROOT/'scratch') as tmp:
    root = Path(tmp)
    fixtures_path = root/'polygons.json'
    subprocess.run(['node', str(Path(__file__).with_suffix('.js')), str(fixtures_path)], check=True)
    for fixture in json.loads(fixtures_path.read_text()):
        mark = fixture['mark']
        expected = unary_union([Polygon(ring) for ring in fixture['polygons']])
        actual = build.marking_geometry(mark)
        assert actual.is_valid and actual.area > 1
        assert actual.symmetric_difference(expected).area < 1e-8, 'editor and game use the same orientation and shape'
    base = {'id':'a', 'type':'arrow', 'points':[[0,0],[0,6]], 'width':2.6}
    left, right = [arrows.geometry({**base,'direction':key}) for key in ('left','right')]
    assert left.centroid.x > 0 and right.centroid.x < 0, 'branches follow the driver facing +Z'
    straight = arrows.geometry(base)
    assert straight.bounds[3] == 6 and straight.bounds[1] == 0
    for colour in ('white', 'yellow'):
        clip_scene = {'id':'arrow_clip','crop':30,'roads':[{'id':'road','outer':[[-4,-12],[4,-12],[4,12],[-4,12]],
                     'holes':[[[-1,-1],[1,-1],[1,1],[-1,1]]]}],
                     'markings':[{**base,'colour':colour,'direction':'all','points':[[3,-3],[3,3]],'width':6},
                                 {**base,'id':'island','colour':colour,'points':[[0,-3],[0,3]]}],
                     'lawns':[],'routes':[],'actors':[],'lights':[],'decor':[]}
        output = build.build(clip_scene)
        painted = surface_polygon(next(s for s in output['surfaces'] if s['id']==f'marking_{colour}'))
        road,islands,_ = build.road_geometry(clip_scene)
        assert painted.intersection(islands.buffer(-.003)).area < .001, 'islands never receive arrow paint'
        assert painted.difference(road.buffer(.303)).area < .001, 'paint is clipped to the carriageway'
        findings=[]
        check.check_layers(clip_scene,road,findings)
        assert any(f['code']=='marking-off-road' for f in findings), 'off-road arrows show a warning'
    for invalid in ({'points':[]},{'points':[[0,0],[0,0]]},{'width':0},{'width':float('nan')},
                    {'points':[[0,0],[0,40]]},{'direction':'unknown'},{'direction':[]}):
        mark = {**base,**invalid}
        assert arrows.error(mark) and arrows.geometry(mark).is_empty
        findings=[]
        check.check_layers({'markings':[mark]},Polygon([[-50,-50],[50,-50],[50,50],[-50,50]]),findings)
        assert any(f['level']=='error' and f['code']=='marking-arrow' for f in findings)
    net, sit = root/'network', root/'situations'
    net.mkdir();sit.mkdir()
    pool = question_pool.QuestionPool(network=net)
    with ExitStack() as stack:
        for module,name,value in [(server,'NET',net),(server,'SIT',sit),(server,'HISTORY',net/'history'),
                                  (server,'PREVIEW',net/'preview'),(server,'QUESTION_POOL',pool),
                                  (check,'NET',net),(build,'NET',net),(build,'BUILD',net/'build'),
                                  (engine_sync,'NET',net),(engine_sync,'SIT',sit)]:
            stack.enter_context(patch.object(module,name,value))
        engine_sync.engine_base.cache_clear()
        httpd = server.Server(('127.0.0.1',0),server.Handler)
        worker = threading.Thread(target=httpd.serve_forever,daemon=True);worker.start()
        def request(path, body=None):
            req=Request(f'http://127.0.0.1:{httpd.server_port}{path}',
                        data=json.dumps(body).encode() if body is not None else None,
                        headers={'Content-Type':'application/json'})
            with urlopen(req,timeout=30) as response: return json.load(response)
        try:
            scene = request('/api/scene/ticket_1_8')['scene']
            before = copy.deepcopy(scene)
            for i,key in enumerate(arrows.SHAPES):
                scene['markings'].append({**base,'id':f'arrow_{i}','direction':key,
                                          'points':[[3.5,15+i*9],[3.5,21+i*9]]})
            assert not [f for f in check.check_scene(scene) if f['level']=='error']
            response = request('/api/scene/ticket_1_8',scene)
            assert not [f for f in response['findings'] if f['level']=='error']
            saved = request('/api/scene/ticket_1_8')
            assert saved['scene']['markings'] == scene['markings']
            assert saved['scene']['roads'] == before['roads'] and saved['scene']['routes'] == before['routes']
            paint=surface_polygon(next(s for s in saved['build']['surfaces'] if s['id']=='marking_white'))
            for mark in scene['markings']:
                if mark['type']=='arrow': assert arrows.geometry(mark).difference(paint.buffer(.003)).area < .002
            assert (sit/'ticket_1_8/scene.json').exists() and (net/'build/ticket_1_8.json').exists()
            scene['markings'][-1]['direction']='right'
            request('/api/scene/ticket_1_8',scene)
            assert list((net/'history/ticket_1_8').glob('*.json')), 'previous arrow variant is retained in history'
            # Validate the real runtime mesh against the exported fixture without copying it into game data.
            result=subprocess.run(['godot','--headless','--path',str(build.ROOT/'game_godot'),
                '--script','res://tests/direction_marking_check.gd','--',str(net/'build/ticket_1_8.json')],
                capture_output=True,text=True,timeout=60)
            assert result.returncode==0 and 'Direction arrow runtime PASS' in result.stdout, result.stdout+result.stderr
            print(result.stdout.strip())
        finally:
            httpd.shutdown();httpd.server_close();worker.join();engine_sync.engine_base.cache_clear()
print('Direction arrows: seven variants, JS/Python geometry parity, validation, HTTP save/reload/history and Godot export PASS')
