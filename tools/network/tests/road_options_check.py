"""Regression: road profiles remove sidewalks/kerbs, suppress edge paint and blend sand."""
import json
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
from shapely.geometry import Point, Polygon
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
assert surface(sandy, 'pavement').area < 0.01
# Add an asphalt branch: the road remains drivable and the join receives blended bands.
s['roads'].append({'id':'asphalt_branch','outer':[[-30,-4],[30,-4],[30,4],[-30,4]],'holes':[]})
mixed = build.build(s)
assert sum(len(x['idx']) for x in mixed['surfaces'] if x['id'].startswith('sand_join_')) > 0
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
# Disable only the south sidewalk: neighbouring ends are rounded, not pointed cuts.
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
# Rounded end curbs sit away from the original road edge and use multiple short segments.
road, _, _, ring = build.ground(sidewalk)
original = unary_union([Polygon(p['outer'], p['holes']).boundary for p in build.polygons_json(ring)] + [road.boundary]).buffer(0.06)
from shapely.geometry import LineString
segs = out['kerbs']['segs']
ends = [LineString([(segs[i],segs[i+1]),(segs[i+2],segs[i+3])]) for i in range(0,len(segs),4)]
ends = [line for line in ends if line.length > 0.001 and not original.covers(line)]
assert len(ends) > 8
assert all(pave.buffer(0.02).covers(line) for line in ends)
print('Road options: all checks passed')
