"""Railway crossings: geometry, ramps, curved/oblique tracks and saved source round-trip."""
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
from shapely.geometry import Point, Polygon, LineString
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
from surface_support import SurfaceSupport

out = build.ROOT / 'scratch/railway'
out.mkdir(parents=True, exist_ok=True)
scene = dict(id='railway_fixture', crop=35, roads=[dict(id='road', outer=[[-4,-35],[4,-35],[4,35],[-4,35]])],
             tracks=[dict(id='rail', render=True, railType='railway', points=[[-30,0],[30,0]])],
             markings=[dict(id='centre', type='solid', points=[[0,-35],[0,35]])], lawns=[], actors=[], routes=[])

def area(s):
    v = s['verts']
    return unary_union([Polygon([(v[j*2],v[j*2+1]) for j in s['idx'][i:i+3]]) for i in range(0,len(s['idx']),3)])

fixtures = []
for name, pts in [('straight',[[-30,0],[30,0]]), ('oblique',[[-30,-13],[30,13]]),
                  ('curved',[[-30,-9],[-10,-3],[10,3],[30,-4]]), ('duplicates',[[-30,0],[-30,0],[30,0]]),
                  ('reversed',[[30,0],[-30,0]]), ('short',[[15,0],[15.1,0]])]:
    source = copy.deepcopy(scene)
    source['tracks'][0]['points'] = pts
    before = copy.deepcopy(source)
    result = build.build(source)
    assert before == source, 'building must not mutate roads/routes/source'
    assert result == build.build(json.loads(json.dumps(source))), 'save/reload produces identical geometry'
    surfaces = {s['id']:s for s in result['surfaces']}
    assert surfaces['railway_rail_heads']['idx']
    assert not any(s['id']=='authored_rails' for s in result['surfaces']), 'no old tram overlay under railway'
    for s in result['surfaces']:
        assert all(math.isfinite(v) for v in s['verts'])
        assert not s['idx'] or max(s['idx']) < len(s['verts'])//2
        if 'heights' in s:
            assert len(s['heights']) == len(s['verts'])//2
    if name != 'short':
        crossing = area(surfaces['railway_crossing'])
        for key in ['railway_sleepers_0','railway_sleepers_1','railway_ballast']:
            assert area(surfaces[key]).intersection(crossing).area < .005, (name,key)
        assert area(surfaces['marking_white']).intersection(crossing).area < .005
        assert area(surfaces['pavement']).intersection(crossing).area < .005
        segs = result['kerbs']['segs']
        for i in range(0,len(segs),4):
            assert LineString([segs[i:i+2],segs[i+2:i+4]]).intersection(crossing.buffer(-.02)).length < .001
    fixtures.append(dict(name=name,scene=source,build=result))
    print('PASS',name, 'triangles',sum(len(s['idx'])//3 for s in result['surfaces']))

support = SurfaceSupport(fixtures[0]['build'])
samples = [(6,0,.015),(6,.762,.015),(6,.85,.015),(6,1.8,.015),(6,2.4,.0975),(6,3,.18),(6,4,.18),(0,10,0)]
for x,z,y in samples:
    assert abs(support.height(x,z)-y)<.0001,(x,z,y,support.height(x,z))
# Old standalone tracks remain byte-for-byte equivalent to the tram default.
legacy = copy.deepcopy(scene); del legacy['tracks'][0]['railType']
explicit = copy.deepcopy(legacy); explicit['tracks'][0]['railType'] = 'tram'
assert build.build(legacy) == build.build(explicit)
hidden = copy.deepcopy(scene); hidden['tracks'][0]['render'] = False
empty = copy.deepcopy(scene); empty['tracks'] = []
assert build.build(hidden) == build.build(empty), 'hidden railway leaves no cuts, sleepers or deck'
fixtures[0]['samples'] = samples
(out/'fixtures.json').write_text(json.dumps(fixtures))
subprocess.run(['node',str(Path(__file__).with_name('railway_editor_check.js')),str(out/'fixtures.json')],check=True)
print('Railway geometry, source preservation, legacy/hide compatibility, ramp support PASS')
