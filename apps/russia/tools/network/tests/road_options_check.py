"""Regression: road profiles remove sidewalks/kerbs, suppress edge paint and blend sand."""
import copy
import json
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
from shapely.affinity import rotate
from shapely.geometry import Point, Polygon, LineString, box
from shapely.ops import unary_union


def surface(out, name):
    s = next(s for s in out['surfaces'] if s['id'] == name)
    pts = list(zip(s['verts'][::2], s['verts'][1::2]))
    return unary_union([Polygon([pts[j] for j in s['idx'][i:i+3]]) for i in range(0, len(s['idx']), 3)])


def scene(options, template="straight"):
    code = """
const L = require('./tools/network/editor/layout.js');
const s = {id:'test',crop:90,layout:L.template(process.argv[2],90),question:{maneuver:'straight'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
for (const st of s.layout.streets) Object.assign(st, JSON.parse(process.argv[1]));
L.apply(s);console.log(JSON.stringify(s));
"""
    return json.loads(subprocess.check_output(['node', '-e', code, json.dumps(options), template], cwd=build.ROOT))

normal = build.build(scene({}))
plain = build.build(scene({'walk': False, 'edge': False}))
assert surface(normal, 'pavement').area > 0
assert surface(plain, 'pavement').area < 0.01
assert len(plain['kerbs']['segs']) < len(normal['kerbs']['segs'])
assert surface(plain, 'marking_white').area < surface(normal, 'marking_white').area
s = scene({'surface': 'sand'})
assert all(r['walk'] is False and r['edge'] is False for r in s['roads'])
assert not s['markings']
sandy = build.build(s)
assert surface(sandy, 'sand').area > 0
# Millimetre-snapped cropped endpoints can leave less than 30 cm² of slivers.
assert surface(sandy, 'asphalt').area < 0.003
assert all(not x['idx'] for x in sandy['surfaces'] if x['id'].startswith('sand_join_'))
# A curved end must keep its drawn width, with grass outside and no legacy straight strip.
curved = scene({'surface': 'sand'})
for r in curved['roads']:
    r['outer'] = [[x + 0.35 * (1 - (z / 90) ** 2), z] for x, z in r['outer']]
curved_out = build.build(curved)
assert surface(curved_out, 'asphalt').area < 0.003
assert all(not x['idx'] for x in curved_out['surfaces'] if x['id'].startswith('sand_join_'))
raw = unary_union([build.polygon_of(r) for r in curved['roads']])
road, _, _, _ = build.ground(curved)
assert road.intersection(build.crop_box(curved).exterior.buffer(0.2)).difference(raw.buffer(0.02)).area < 0.001
assert surface(sandy, 'pavement').area < 0.01
# Add an asphalt branch: the road remains drivable and the join receives blended bands.
s['roads'].append({'id':'asphalt_branch','outer':[[-30,-4],[30,-4],[30,4],[-30,4]],'holes':[]})
mixed = build.build(s)
field = next(x for x in mixed['surfaces'] if x['id'] == 'dirt_field')
assert field['idx'] and any(0 < w < 1 for w in field['shares'][::3]), 'Current field mesh blends asphalt into dirt'
assert surface(mixed, 'asphalt').area > 0
# With all arm edges disabled, curved junction corners must contain no white fragments.
cross = scene({'edge': False, 'centre': 'none'}, 'cross')
cross['markings'] = []  # Keep this assertion specific to edge lines, excluding the player's stop line.
assert surface(build.build(cross), 'marking_white').area < 0.001
# Turning edges back on for one arm restores that arm, without restoring all roads.
arm = cross['layout']['streets'][0]['id']
for r in cross['roads']:
    if r['id'] == 'road_' + arm:
        r['edge'] = True
partial = surface(build.build(cross), 'marking_white').area
full = surface(build.build(scene({'centre': 'none'}, 'cross')), 'marking_white').area
assert 0 < partial < full
# Disable only the south sidewalk: neighbouring sidewalks reach the carriageway.
sidewalk = scene({}, 'cross')
for st in sidewalk['layout']['streets']:
    if any(next(n for n in sidewalk['layout']['nodes'] if n['id'] == nid)['z'] < -80 for nid in (st['a'], st['b'])):
        south_id = 'road_' + st['id']
for r in sidewalk['roads']:
    if r['id'] == south_id:
        r['walk'] = False
out = build.build(sidewalk)
pave = surface(out, 'pavement')
assert not pave.intersects(Point(6, -40).buffer(0.5))
assert pave.contains(Point(40, -6)) and pave.contains(Point(-40, -6))
# Cut ends are closed by curbs along the actual pavement boundary.
road, _, _, ring = build.ground(sidewalk)
original = unary_union([Polygon(p['outer'], p['holes']).boundary for p in build.polygons_json(ring)] + [road.boundary]).buffer(0.06)
segs = out['kerbs']['segs']
ends = [LineString([(segs[i],segs[i+1]),(segs[i+2],segs[i+3])]) for i in range(0,len(segs),4)]
ends = [line for line in ends if line.length > 0.001 and not original.covers(line)]
assert ends
assert all(pave.buffer(0.02).covers(line) for line in ends)
# A disabled side exit must never cut the far sidewalk, even on a narrow 5 m road.
# Exercise generated roadside lawns too: they cannot erase the enabled sidewalk.
for kind, half in [("yard",2.5),("street",4.2),("avenue",7.0)]:
    code = """
const L=require('./tools/network/editor/layout.js');
const s={id:'sidewalk-join',crop:90,layout:L.template('tee-left',90),question:{maneuver:'straight'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
for(const st of s.layout.streets){st.kind=process.argv[1];st.walk=st.id!=='s3';}
L.apply(s);console.log(JSON.stringify(s));
"""
    fixture = json.loads(subprocess.check_output(['node','-e',code,kind],cwd=build.ROOT))
    before = copy.deepcopy(fixture)
    result = build.build(fixture)
    pavement = surface(result,'pavement')
    road = surface(result,'asphalt')
    assert box(-half-build.SIDEWALK+.1,-30,-half-.1,30).difference(pavement).area < .001, kind
    # At the middle of the sidewalk, both ends touch the asphalt instead of
    # retreating into capsule-shaped caps. Keep the genuine road fillet.
    cut = pavement.intersection(LineString([(half+1.6,-25),(half+1.6,25)]))
    pieces = list(cut.geoms) if hasattr(cut,'geoms') else [cut]
    tips = [Point(p) for piece in pieces for p in [piece.coords[0],piece.coords[-1]] if abs(p[1])<20]
    assert len(tips)==2 and all(road.distance(p)<.005 for p in tips), kind
    assert fixture==before, 'Derived geometry must not rewrite the authored scene'
    # Rotated joins retain their opposite continuous path.
    for angle in [90,180,270,33]:
        turned=copy.deepcopy(fixture)
        for item in turned['roads']+turned['lawns']:
            item['outer']=[list(p) for p in rotate(Polygon(item['outer']),angle,origin=(0,0)).exterior.coords[:-1]]
            item['holes']=[[list(p) for p in rotate(Polygon(h),angle,origin=(0,0)).exterior.coords[:-1]] for h in item.get('holes',[])]
        rotated_pave=surface(build.build(turned),'pavement')
        probe=rotate(box(-half-build.SIDEWALK+.1,-30,-half-.1,30),angle,origin=(0,0))
        assert probe.difference(rotated_pave).area<.01,(kind,angle)
    # A lawn drawn by hand still overrides pavement explicitly.
    fixture['lawns'].append({'id':'handmade-lawn','outer':[[-half-5.5,-18],[-half+.5,-18],[-half+.5,-8],[-half-5.5,-8]],'holes':[]})
    custom=surface(build.build(fixture),'pavement')
    assert not custom.contains(Point(-half-1.5,-13))
print('Road options: profiles, narrow/wide/rotated sidewalk joins, flush endings, manual lawns and source preservation PASS')
