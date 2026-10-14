"""Build the six-lane sources and test their actual surface and actor/player paths."""
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import check
import build
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
import math

path=check.ROOT/'scratch/highway-fixtures.json'
subprocess.run(['node',str(Path(__file__).with_suffix('.js')),str(path)],check=True)
fixtures=json.loads(path.read_text())
for i,s in enumerate(fixtures):
 errors=[f for f in check.check_scene(s) if f['level']=='error']
 assert not errors,(i,errors)
 built=build.build(s)
 area=unary_union([Polygon(r['outer'],r['holes']) for r in built['carriageway']])
 # Every saved route centre and a real car footprint at sampled approach points fit the build.
 for route in s['routes']:
  assert LineString(route['points']).intersection(build.crop_box(s)).difference(area.buffer(.15)).length < .3,(i,route['id'])
  if route['kind']!='approach':continue
  pts=route['points']
  for j in range(1,len(pts)-1, max(1,len(pts)//12)):
   x,z=pts[j];dx=pts[j+1][0]-pts[j-1][0];dz=pts[j+1][1]-pts[j-1][1];yaw=math.atan2(dx,dz)
   if max(abs(x),abs(z))>s['crop']-5:continue
   c,n=math.cos(yaw),math.sin(yaw)
   body=Polygon([(x+u*c+v*n,z-u*n+v*c) for u,v in [(-.95,-2.4),(.95,-2.4),(.95,2.4),(-.95,2.4)]])
   assert area.buffer(.06).covers(body),(i,j,'car footprint outside taper')
 # Runtime parity fixtures use disposable source/build dictionaries, never authors' scenes.
 s['build']=built
path.write_text(json.dumps(fixtures))
print(f'Highway build: {len(fixtures)} sources, drivable tapers/routes/car footprints PASS')
