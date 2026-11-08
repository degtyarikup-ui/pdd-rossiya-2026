"""Verify built highway sections, median continuity, saved routes and complete car bodies."""
import json
import math
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check
import build
from shapely.geometry import Polygon, MultiPolygon, LineString
from shapely.ops import unary_union


def check_section(scene, area, nid, expected, inset):
    """Measure real carriageway spans, rather than trusting source width declarations."""
    nodes = {n['id']: n for n in scene['layout']['nodes']}
    st = next(st for st in scene['layout']['streets'] if nid in (st['a'], st['b']))
    if st.get('bend'):
        return False  # Native tests measure the real tangent and rendered curved cut.
    at = nodes[nid]
    other = nodes[st['b'] if st['a'] == nid else st['a']]
    dx, dz = at['x'] - other['x'], at['z'] - other['z']
    length = math.hypot(dx, dz)
    dx, dz = dx / length, dz / length
    x, z = at['x'] - dx * inset, at['z'] - dz * inset
    cut = area.intersection(LineString([(x - dz * 40, z + dx * 40), (x + dz * 40, z - dx * 40)]))
    lines = list(cut.geoms) if cut.geom_type == 'MultiLineString' else [cut]
    spans = sorted((min((p[0] - x) * dz - (p[1] - z) * dx for p in line.coords),
                    max((p[0] - x) * dz - (p[1] - z) * dx for p in line.coords))
                   for line in lines if line.geom_type == 'LineString' and line.length > .01)
    label = (scene['testCase'], nid, inset, spans)
    assert spans, label
    assert abs(spans[0][0] + expected['width'] / 2) < .05, label
    assert abs(spans[-1][1] - expected['width'] / 2) < .05, label
    if expected['median']:
        assert len(spans) == 2, ('continuous median is missing', label)
        assert abs(spans[1][0] - spans[0][1] - expected['median']) < .05, label
        assert all(abs(hi - lo - 10.5) < .05 for lo, hi in spans), label
    else:
        assert len(spans) == 1 and abs(cut.length - expected['width']) < .05, label
    return True


# A clipped divider can leave valid pavement components touching at a single point.
# Passing their duplicate vertex indices to Triangle together used to crash Python.
# Exercise the generic fix independently of highway geometry, including a retained hole.
for with_hole in [False, True]:
    first = Polygon([(0, 0), (6, 0), (6, 6), (0, 6)],
                    [[(2, 2), (4, 2), (4, 4), (2, 4)]] if with_hole else [])
    second = Polygon([(6, 6), (8, 6), (8, 8), (6, 8)])
    touching = MultiPolygon([first, second])
    assert touching.is_valid and first.intersection(second).geom_type == 'Point'
    verts, indices = build.triangulate(touching)
    points = list(zip(verts[::2], verts[1::2]))
    triangles = [Polygon([points[j] for j in indices[i:i + 3]]) for i in range(0, len(indices), 3)]
    assert triangles and all(t.is_valid and t.area > 0 for t in triangles)
    assert abs(sum(t.area for t in triangles) - touching.area) < 1e-6
    assert unary_union(triangles).symmetric_difference(touching).area < 1e-6, 'touching parts or hole changed during triangulation'


path = check.ROOT / 'scratch/highway-fixtures.json'
path.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['node', str(Path(__file__).with_suffix('.js')), str(path)], check=True)
fixtures = json.loads(path.read_text())
sections = bodies = 0
for s in fixtures:
    label = s['testCase']
    errors = [f for f in check.check_scene(s) if f['level'] == 'error']
    assert not errors, (label, errors)
    built = build.build(s)
    area = unary_union([Polygon(r['outer'], r['holes']) for r in built['carriageway']])
    for nid, expected in s['expectedPorts'].items():
        for inset in [.8, 24, 34]:
            sections += int(check_section(s, area, nid, expected, inset))
    # Check all centre paths, including turns. Straight/taper fixtures also exercise the
    # complete car through both the arrival path and the departure through the merge.
    for route in s['routes']:
        assert len(route['points']) >= 2, (label, route['id'], 'route has no segment')
        trace = LineString(route['points']).intersection(build.crop_box(s))
        assert trace.difference(area.buffer(.15)).length < .3, (label, route['id'])
        if route['kind'] != 'approach' and not s['testFootprints']:
            continue
        pts = route['points']
        for j in range(1, len(pts) - 1, max(1, len(pts) // 16)):
            x, z = pts[j]
            dx, dz = pts[j + 1][0] - pts[j - 1][0], pts[j + 1][1] - pts[j - 1][1]
            yaw = math.atan2(dx, dz)
            if max(abs(x), abs(z)) > s['crop'] - 5:
                continue
            c, n = math.cos(yaw), math.sin(yaw)
            body = Polygon([(x + u * c + v * n, z - u * n + v * c)
                            for u, v in [(-.95, -2.4), (.95, -2.4), (.95, 2.4), (-.95, 2.4)]])
            assert area.buffer(.06).covers(body), (label, route['id'], j, 'car body outside carriageway')
            bodies += 1
    # Runtime fixtures are disposable source/build dictionaries; no author scene is changed.
    s['build'] = built
path.write_text(json.dumps(fixtures))
print(f'Highway build: {len(fixtures)} sources, {sections} actual sections, {bodies} car bodies/routes PASS')
