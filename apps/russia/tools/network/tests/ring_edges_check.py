"""Roundabout contours: actual editor output -> triangulated surfaces used by Godot."""
import copy
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


def fixture(radius, island, arms, offset):
    code = """
const L = require('./tools/network/editor/layout.js');
const [r,island,arms,offset] = JSON.parse(process.argv[1]);
const s = {id:'ring-test',crop:90,layout:L.template('ring',90),question:{maneuver:'straight'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
s.layout.nodes.find(n=>n.ring).ring = {r,island};
s.layout.nodes.forEach(n=>{n.x+=offset[0];n.z+=offset[1];});
s.layout.streets.forEach(st=>{st.edge=arms;st.centre='none';});
L.apply(s);s.markings=[];console.log(JSON.stringify(s));
"""
    return json.loads(subprocess.check_output(['node', '-e', code, json.dumps([radius,island,arms,offset])], cwd=build.ROOT))


for radius, island, offset in [(15,6,[0,0]), (20,9,[0,0]), (26,13,[7,-4])]:
    for arms in (False, True):
        s = fixture(radius,island,arms,offset)
        ring = next(r for r in s['roads'] if 'innerEdge' in r)
        baseline = build.build(s)
        paint = surface(baseline,'marking_white')
        inner_zone = Point(*offset).buffer(island + 0.7)
        outer_zone = Point(*offset).buffer(radius + 12).difference(inner_zone)
        inner = paint.intersection(inner_zone)
        assert inner.area > 0.8 * 2 * 3.14 * island * build.EDGE_WIDTH
        assert paint.intersection(outer_zone).area > 1
        results = {}
        for outer_on, inner_on in [(False,True),(True,False),(False,False)]:
            variant = copy.deepcopy(s)
            item = next(r for r in variant['roads'] if 'innerEdge' in r)
            item.update(outerEdge=outer_on,innerEdge=inner_on)
            out = build.build(variant)
            marks = surface(out,'marking_white')
            results[outer_on,inner_on] = marks
            if inner_on:
                assert marks.intersection(inner_zone).symmetric_difference(inner).area < 0.001
            else:
                assert marks.intersection(inner_zone).area < 0.001
            if not outer_on:
                rim = Point(*offset).buffer(radius + 0.1).difference(Point(*offset).buffer(radius - 1))
                assert marks.intersection(rim).area < 0.001
            # Edges are paint only: no geometry, kerb, walk or driving surface changes.
            assert out['kerbs'] == baseline['kerbs']
            assert [a for a in out['surfaces'] if a['id'] != 'marking_white'] == [a for a in baseline['surfaces'] if a['id'] != 'marking_white']
            far = build.crop_box(s).difference(Point(*offset).buffer(radius + 12))
            # Vertices are rounded to millimetres; retriangulating a long strip
            # can change its area by a few thousandths of a square metre.
            assert marks.intersection(far).symmetric_difference(paint.intersection(far)).area < 0.02, (radius,arms,outer_on,inner_on,marks.intersection(far).symmetric_difference(paint.intersection(far)).area)
        if not arms:
            assert results[False,False].intersection(inner_zone.union(outer_zone)).area < 0.001
            assert results[False,True].intersection(inner_zone.union(outer_zone)).symmetric_difference(inner).area < 0.001
        # Removing both contours cannot remove authored white or yellow paint.
        custom = copy.deepcopy(s)
        next(r for r in custom['roads'] if 'innerEdge' in r).update(outerEdge=False,innerEdge=False)
        x,z = offset
        custom['markings'] = [{'id':'manual-'+colour,'type':'solid','colour':colour,'width':0.2,
            'points':[[x+island+2,z+i],[x+radius-2,z+i]]} for i,colour in enumerate(['white','yellow'])]
        manual_out = build.build(custom)
        for colour in ('white','yellow'):
            assert surface(manual_out,'marking_'+colour).area > 0.1
        # Optional fields default to on, including a source that specifies only one.
        partial = copy.deepcopy(s)
        item = next(r for r in partial['roads'] if 'innerEdge' in r)
        item['outerEdge'] = False
        del item['innerEdge']
        marks = surface(build.build(partial),'marking_white')
        assert marks.intersection(inner_zone).symmetric_difference(inner).area < 0.001
print('Roundabout contours: all checks passed')
