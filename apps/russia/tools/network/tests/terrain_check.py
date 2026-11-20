"""Actual mesh heights, topology, marking clearance, JS parity and flat-scene compatibility."""
import copy,json,math,sys,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build,check,terrain
root=Path(__file__).resolve().parents[3]
for sid in ['ticket_8_2','ticket_19_3','ticket_24_5']:
 s=json.loads((root/'game_godot/network'/f'{sid}.json').read_text());assert not [f for f in check.check_scene(s)if f['level']=='error']
 result=build.build(s)
 base=copy.deepcopy(s);del base['terrain'];flat=build.build(base)
 for surface in result['surfaces']:
  assert len(surface['heights'])*2==len(surface['verts'])
  for i,h in enumerate(surface['heights']):
   # Height deformation preserves each layer's existing clearance.
   assert math.isclose(h-surface['y'],terrain.height(s['terrain'],*surface['verts'][i*2:i*2+2]),abs_tol=1e-6)
  assert all(math.isfinite(h)for h in surface['heights'])
 assert result['carriageway']==flat['carriageway']
 assert max(max(p['heights'],default=0)for p in result['surfaces'])>.07
 for x,z in [(-2,-18),(0,3.8),(2,22),(-1,40),(0,90)]:
  js="const s=require('./tools/network/editor/surface_support.js');process.stdout.write(String(s.terrainHeight(JSON.parse(process.argv[1]),Number(process.argv[2]),Number(process.argv[3]))));"
  y=float(subprocess.check_output(['node','-e',js,json.dumps(s['terrain']),str(x),str(z)],cwd=root,text=True))
  assert abs(y-terrain.height(s['terrain'],x,z))<1e-8
 invalid=copy.deepcopy(s);invalid['terrain']={'profile':[[0,1],[0,2]]}
 assert any(f['code']=='terrain-invalid'for f in check.check_scene(invalid))
 # Removing the feature restores the old build byte-for-byte.
 assert json.dumps(build.build(base),sort_keys=True)==json.dumps(flat,sort_keys=True)
print('Terrain: three real scenes, per-vertex heights, layer clearance, topology, JS parity, validation, flat round-trip PASS')
