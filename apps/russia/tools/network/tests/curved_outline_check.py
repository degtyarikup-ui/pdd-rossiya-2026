"""Sharp offset bends must produce valid road/lawn rings without moving authored nodes."""
import json, subprocess, sys
from pathlib import Path
from shapely.geometry import Polygon
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build, check
script = r'''
const L=require('./tools/network/editor/layout.js');
const all=[];
for (const mirror of [1,-1]) for(const kind of ['street','avenue','highway']) {
 const s={id:'curved',crop:90,roads:[],lawns:[],actors:[],routes:[],markings:[],lights:[],question:{maneuver:'straight'},layout:{
 nodes:[{id:'a',x:-1.5*mirror,z:-5},{id:'b',x:-1*mirror,z:30}],
 streets:[{id:'s2',a:'a',b:'b',kind,bend:[-3.048*mirror,27.162],walk:false,shoulder:2.5}],player:{street:'s2',toward:'b',questionAt:10,lane:0}}};
 const original=JSON.stringify(s.layout);Object.assign(s,L.generate(s));
 if(JSON.stringify(s.layout)!==original) throw Error('authored layout changed');
 all.push(s);
}
process.stdout.write(JSON.stringify(all));
'''
scenes=json.loads(subprocess.check_output(['node','-e',script],cwd=build.ROOT))
for s in scenes:
 for item in s['roads']+s['lawns']:
  p=Polygon(item['outer'])
  assert p.is_valid and p.area>1,(item['id'],p.wkt)
 assert not [f for f in check.check_scene(s) if f['code'] in ('road-invalid','lawn-invalid')]
 assert build.build(s)['surfaces']
print('PASS sharp and mirrored bends: valid road/lawn contours, all widths, unchanged authored layout')
