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
assert surface['layer']=='gravel' and SurfaceSupport(built).height(5,0)==0
assert not next(s for s in built['surfaces'] if s['id']=='pavement')['idx']
assert not built['kerbs']['segs']
no_shoulder=copy.deepcopy(scene);no_shoulder['roads'][0].pop('shoulder')
assert built['carriageway']==build.build(no_shoulder)['carriageway']
assert not any(s['id']=='rural_shoulder' for s in build.build(no_shoulder)['surfaces'])
(build.ROOT/'scratch/shoulder.json').write_text(json.dumps(built))
print('PASS shoulder width/both sides/car support/no kerbs/no sidewalk/unchanged carriageway/source')
