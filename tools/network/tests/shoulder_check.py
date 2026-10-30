import sys,json,copy
from pathlib import Path
from shapely.geometry import Point,Polygon
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build
from surface_support import SurfaceSupport
scene=dict(id='shoulder',crop=30,roads=[dict(id='road',outer=[[-4,-30],[4,-30],[4,30],[-4,30]],walk=False,shoulder=2.5)],actors=[],routes=[],markings=[])
before=copy.deepcopy(scene)
built=build.build(scene)
assert scene==before
surface=next(s for s in built['surfaces'] if s['id']=='rural_shoulder')
v=surface['verts'];ids=surface['idx']
shape=unary_union([Polygon([(v[j*2],v[j*2+1]) for j in ids[i:i+3]]) for i in range(0,len(ids),3)])
assert shape.covers(Point(5,0)) and shape.covers(Point(-5,0))
assert not shape.covers(Point(0,0)) and not shape.covers(Point(7,0))
assert surface['layer']=='field' and SurfaceSupport(built).height(5,0)==0
assert not next(s for s in built['surfaces'] if s['id']=='pavement')['idx']
assert not built['kerbs']['segs']
no_shoulder=copy.deepcopy(scene);no_shoulder['roads'][0].pop('shoulder')
assert built['carriageway']==build.build(no_shoulder)['carriageway']
assert not any(s['id']=='rural_shoulder' for s in build.build(no_shoulder)['surfaces'])
(build.ROOT/'scratch/shoulder.json').write_text(json.dumps(built))
print('PASS shoulder width/both sides/car support/no kerbs/no sidewalk/unchanged carriageway/source')

# Vertex weights reach pure grass at scene cuts and the outside, and asphalt at the road.
weights=[surface['shares'][i:i+3] for i in range(0,len(surface['shares']),3)]
for (x,z),w in zip(zip(v[::2],v[1::2]),weights):
 assert abs(sum(w)-1)<1e-6 and min(w)>=-1e-6
 if abs(z)>29.99 or abs(x)>6.49: assert w[2]>.999,(x,z,w)
 if abs(z)<15 and abs(abs(x)-4)<.001: assert w[0]>.999,(x,z,w)
assert any(w[1]>.95 for w in weights), 'full earth away from transitions'
# An interior on/off boundary fades too; roads remain connected.
joined=copy.deepcopy(scene)
joined['roads'][0]['outer']=[[-4,0],[4,0],[4,30],[-4,30]]
joined['roads'].append(dict(id='before',outer=[[-4,-30],[4,-30],[4,0],[-4,0]],walk=False))
s=next(s for s in build.build(joined)['surfaces'] if s['id']=='rural_shoulder')
for i in range(0,len(s['verts']),2):
 if abs(s['verts'][i+1])<.01: assert s['shares'][i//2*3+2]>.999
print('PASS smooth road/earth/grass weights and crop/interior end fade')
