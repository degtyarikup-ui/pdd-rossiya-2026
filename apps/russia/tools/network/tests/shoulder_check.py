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
road_outline=build.road_geometry(scene)[2]
weights=[surface['shares'][i:i+3] for i in range(0,len(surface['shares']),3)]
for (x,z),w in zip(zip(v[::2],v[1::2]),weights):
 assert abs(sum(w)-1)<1e-6 and min(w)>=-1e-6
 if abs(z)>29.99 or road_outline.distance(Point(x,z))>2.499: assert w[2]>.999,(x,z,w)
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

# A bent continuous road must retain soil around its rounded inner corner.
corner=dict(id='corner',crop=40,roads=[dict(id='a',outer=[[-4,-35],[4,-35],[4,4],[-4,4]],walk=False,shoulder=2.5),dict(id='b',outer=[[-4,-4],[35,-4],[35,4],[-4,4]],walk=False,shoulder=2.5)],actors=[],routes=[],markings=[])
s=next(s for s in build.build(corner)['surfaces'] if s['id']=='rural_shoulder')
soil=[(s['verts'][i],s['verts'][i+1]) for i in range(0,len(s['verts']),2) if s['shares'][i//2*3+1]>.5]
assert any(4<x<10 and -10<z<-4 for x,z in soil), 'inner bend lost its shoulder'
print('PASS continuous shoulder around rounded bend')

# Junction filler has walk=false by design, but two enabled arms own its whole ring.
walk=copy.deepcopy(corner)
for r in walk['roads']: r['walk']=True; r.pop('shoulder')
walk['roads'][0]['id']='road_a';walk['roads'][1]['id']='road_b'
walk['roads'].append(dict(id='road_c',outer=[[-4,-4],[4,-4],[4,4],[-4,4]],walk=False))
walk['layout']={'nodes':[{'id':'c'}],'streets':[{'id':'a','a':'start','b':'c','walk':True},{'id':'b','a':'c','b':'end','walk':True}]}
support=build.sidewalk_support(walk)
ring=build.ground(walk)[3]
assert ring.difference(support).area<.01, 'enabled corner sidewalk is clipped'
print('PASS sidewalk follows full connected corner')
