"""Free actor placement: real built surfaces, HTTP save/reload and engine height/path export."""
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
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build, check, engine_sync, question_pool, server
from surface_support import SurfaceSupport

catalog = server.Handler.catalog(None)
original_sit = server.SIT
with tempfile.TemporaryDirectory(prefix='free-actors-', dir=build.ROOT/'scratch') as tmp:
    root = Path(tmp)
    scene = {'id':'support', 'crop':50, 'roads':[{'id':'street','outer':[[-4,-45],[4,-45],[4,45],[-4,45]],
        'holes':[[[-1,-2],[1,-2],[1,2],[-1,2]]]}], 'lawns':[], 'actors':[], 'routes':[],
        'markings':[{'id':'paint','type':'solid','points':[[0,10],[0,35]],'colour':'white'}]}
    samples = [{'name':name, 'x':x, 'z':z, 'y':y} for name,x,z,y in [
        ('asphalt and painted line',0,20,0), ('right sidewalk',6,20,.18),
        ('left sidewalk',-6,20,.18), ('raised island in road hole',0,0,.18),
        ('ground outside the scene',80,20,-.15)]]
    fixtures = [{'name':'straight road and island', 'build':build.build(scene), 'samples':samples}]
    lawn = copy.deepcopy(scene)
    lawn['lawns'] = [{'id':'bed','outer':[[3,12],[15,12],[15,30],[3,30]]}]
    fixtures.append({'name':'lawn cuts pavement','build':build.build(lawn),
        'samples':[{'name':'uncovered ground in flower bed','x':6,'z':21,'y':-.15}]})
    for fixture in fixtures:
        support = SurfaceSupport(fixture['build'])
        for sample in fixture['samples']:
            assert support.height(sample['x'],sample['z']) == sample['y'], (fixture['name'],sample)
    fixtures_file = root/'fixtures.json'
    fixtures_file.write_text(json.dumps(fixtures))
    subprocess.run(['node',str(Path(__file__).with_suffix('.js')),str(fixtures_file)],check=True)

    net, sit = root/'network', root/'situations'
    net.mkdir(); sit.mkdir()
    template = catalog['actorTypes']['car']
    source, fname = template['asset'].split('/')
    target = sit/source
    (target/'parts').mkdir(parents=True)
    shutil.copy2(original_sit/source/'engine.json',target/'engine.json')
    part = original_sit/source/'parts'/fname
    shutil.copy2(part if part.exists() else original_sit/source/fname,target/'parts'/fname)
    with ExitStack() as stack:
        for module,name,value in [(server,'NET',net),(server,'SIT',sit),(server,'HISTORY',net/'history'),
                (server,'PREVIEW',net/'preview'),(server,'QUESTION_POOL',question_pool.QuestionPool(network=net)),
                (check,'NET',net),(build,'NET',net),(build,'BUILD',net/'build'),
                (engine_sync,'NET',net),(engine_sync,'SIT',sit)]:
            stack.enter_context(patch.object(module,name,value))
        engine_sync.engine_base.cache_clear()
        httpd = server.Server(('127.0.0.1',0),server.Handler)
        worker = threading.Thread(target=httpd.serve_forever,daemon=True)
        worker.start()
        def request(path,body=None):
            req = Request(f'http://127.0.0.1:{httpd.server_port}{path}',
                data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json'})
            with urlopen(req,timeout=30) as response:
                return json.load(response)
        try:
            saved = request('/api/scene/ticket_3_12')['scene']
            saved.pop('layout',None)
            for key in ('roads','lawns','markings'):
                saved[key] = copy.deepcopy(scene[key])
            saved['actors'] = [{'id':'parked','type':'car','asset':template['asset'],'name':'Parked',
                'pos':[6,20],'yaw':.23,'scale':[1,1,1],'halfWidth':template['halfWidth'],
                'halfLength':template['halfLength'],'behaviour':{'staysPut':True}}]
            request('/api/scene/ticket_3_12',saved)
            reloaded = request('/api/scene/ticket_3_12')['scene']
            assert reloaded['actors'] == saved['actors'], 'save/reload never changes authored position or yaw'
            exported = json.loads((sit/'ticket_3_12/scene.json').read_text())['actors'][0]
            assert exported['pos'] == [6,.18,20]
            assert exported['path'] == [[6,.18,20],[6,.18,20]]
            assert exported['config']['position'] == exported['pos']
            saved['actors'][0].update(pos=[0,20],route='drive')
            saved['actors'][0]['behaviour']['staysPut'] = False
            saved['routes'].append({'id':'drive','kind':'actor','points':[[0,20],[6,25],[6,35]]})
            request('/api/scene/ticket_3_12',saved)
            exported = json.loads((sit/'ticket_3_12/scene.json').read_text())['actors'][0]
            assert exported['pos'] == [0,0,20], 'back on the road resets the height'
            assert exported['path'] == [[0,0,20],[6,.18,25],[6,.18,35]]
        finally:
            httpd.shutdown(); httpd.server_close(); worker.join()
            engine_sync.engine_base.cache_clear()
print('Free actors: supporting geometry/holes/lawn cuts, JS/Python parity, real HTTP save/reload and engine position/path heights PASS')
