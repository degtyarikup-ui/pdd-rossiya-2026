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


def scene(options):
    code = """
const L = require('./tools/network/editor/layout.js');
const s = {id:'test',crop:90,layout:L.template('straight',90),question:{maneuver:'straight'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
for (const st of s.layout.streets) Object.assign(st, JSON.parse(process.argv[1]));
L.apply(s);console.log(JSON.stringify(s));
"""
    return json.loads(subprocess.check_output(['node', '-e', code, json.dumps(options)], cwd=build.ROOT))

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
print('Road options: all checks passed')
