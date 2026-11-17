#!/usr/bin/env python3
"""Explicit car body survives export, overrides archive config and has matching dimensions."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import engine_sync
source=json.loads((check.NET/'ticket_10_15.json').read_text())
archive=engine_sync.engine_base('ticket_10_15')
dimensions=json.loads((check.ROOT/'game_godot/models/index.json').read_text())
with tempfile.TemporaryDirectory(prefix='actor-model-',dir=check.ROOT/'scratch') as tmp:
    root=Path(tmp)
    for name in ['template','fixture']:
        (root/name/'parts').mkdir(parents=True)
        (root/name/'engine.json').write_text(json.dumps(archive))
    for i in range(len(archive['actors'])):
        (root/'template/parts'/f'actor_{i}.glb').write_bytes(b'fixture')
    source['lights']=[]
    for i,a in enumerate(source['actors']): a['asset']=f'template/actor_{i}.glb'
    car=next(a for a in source['actors'] if a['type']=='car')
    car['scale']=[1.2,1,1.3]
    car['halfWidth']=99;car['halfLength']=99
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(engine_sync,'SIT',root),patch.object(check,'load',return_value=source):
            for model in ['hatch','sedan','coupe','wagon','suv','pickup','mini']:
                car['carModel']=model;before=copy.deepcopy(source)
                engine_sync.sync('fixture')
                result=next(a for a in json.loads((root/'fixture/scene.json').read_text())['actors'] if a['type']=='car')
                assert result['carModel']==model and result['config']['car_model']==model
                meta=dimensions['vehicles/'+model]['meta']
                assert abs(result['halfWidth']-meta['halfWidth']*1.2)<1e-9
                assert abs(result['halfLength']-meta['halfLength']*1.3)<1e-9
                assert source==before,'export cannot mutate source'
            del car['carModel'];engine_sync.sync('fixture')
            result=next(a for a in json.loads((root/'fixture/scene.json').read_text())['actors'] if a['type']=='car')
            assert 'carModel' not in result
            assert result['config'].get('car_model')==archive['actors'][0]['config'].get('car_model')
            for bad in ['cyber','missing','../../other']:
                car['carModel']=bad
                assert any(f['code']=='actor-appearance' and f['level']=='error' for f in check.check_scene(source))
    finally:engine_sync.engine_base.cache_clear()
print('Actor carModel: seven bodies, export/config/dimensions, clearing and invalid-model validation PASS')
