#!/usr/bin/env python3
"""Generated free poses -> checks/build/export, without touching any authored scene.

    tools/network/.venv/bin/python tools/network/tests/free_player_check.py
"""
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build
import check
import engine_sync
from shapely.geometry import Polygon
from shapely.ops import unary_union

failures=[]
def expect(ok, message):
    print(('ok   ' if ok else 'FAIL ')+message)
    if not ok: failures.append(message)

with tempfile.TemporaryDirectory(prefix='free-player-',dir=check.ROOT/'scratch') as scratch:
    temp=Path(scratch)
    result=subprocess.run(['node',str(HERE/'free_player_check.js'),str(temp/'cases.json')],check=True,capture_output=True,text=True)
    print(result.stdout.strip())
    for item in json.loads((temp/'cases.json').read_text()):
        s=item['scene']; name=f"{item['template']} {s['stop']}"
        errors=[e for e in check.check_scene(s) if e['level']=='error']
        expect(not errors,f"{name}: no check errors {[e['message'] for e in errors]}")
        b=build.build(s)
        area=unary_union([Polygon(r['outer'],r.get('holes',[])) for r in b['carriageway']])
        pose=s['stop']; c=math.cos(pose['yaw']); n=math.sin(pose['yaw'])
        body=Polygon([(pose['x']+u*c+v*n,pose['z']-u*n+v*c) for u,v in [(-.95,-2.4),(.95,-2.4),(.95,2.4),(-.95,2.4)]])
        expect(area.buffer(.02).covers(body),f'{name}: full body lies on built carriageway')
        # Deliberately stale denormalised stop: explicit placement must win during export.
        engine_sync.check.load=lambda sid: copy.deepcopy(s)
        engine_sync.engine_base=lambda sid:{'playerStartX':None,'actors':[],'lights':[],'labels':[]}
        engine_sync.scene_dir=lambda sid:temp
        saved_stop=s['stop'];s['stop']={'x':-1.8,'z':-13.1,'yaw':0}
        engine_sync.sync('fixture')
        out=json.loads((temp/'scene.json').read_text())
        s['stop']=saved_stop
        expect(out['playerPlacement']=='free' and out['playerStartX']==s['layout']['player']['pose']['x'] and out['stopZ']==s['layout']['player']['pose']['z'] and out['playerStartRotY']==s['layout']['player']['pose']['yaw'],f'{name}: explicit pose/yaw exported')
        expect(all(e['points'][0]==[saved_stop['x'],saved_stop['z']] for e in out['exits'].values()),f'{name}: exported manoeuvres begin at pose')
print(f'Free player pipeline: {len(failures)} failures')
sys.exit(1 if failures else 0)
