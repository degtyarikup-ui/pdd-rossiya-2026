"""Yield triangles survive validation and the real surface build consumed by editor and Godot."""
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
import check
from shapely.geometry import Polygon
from shapely.ops import unary_union


def surface_geometry(surface):
    vertices = list(zip(surface['verts'][::2], surface['verts'][1::2]))
    return unary_union([Polygon([vertices[j] for j in surface['idx'][i:i + 3]])
                        for i in range(0, len(surface['idx']), 3)])


with tempfile.TemporaryDirectory(prefix='yield-line-', dir=build.ROOT / 'scratch') as tmp:
    path = Path(tmp) / 'fixtures.json'
    subprocess.run(['node', str(Path(__file__).with_suffix('.js')), str(path)], check=True)
    for scene in json.loads(path.read_text()):
        assert not [e for e in check.check_scene(scene) if e['level'] == 'error']
        output = build.build(scene)
        paint = surface_geometry(next(s for s in output['surfaces'] if s['id'] == 'marking_white'))
        road, islands, _ = build.road_geometry(scene)
        for mark in (m for m in scene['markings'] if m['type'] == 'stop'):
            geometry = build.marking_geometry(mark)
            (ax, az), (bx, bz) = mark['points']
            length = math.hypot(bx - ax, bz - az)
            ux, uz = (bx - ax) / length, (bz - az) / length
            nx, nz = -uz, ux
            triangles = list(geometry.geoms) if hasattr(geometry, 'geoms') else [geometry]
            for triangle in triangles:
                assert len(triangle.exterior.coords) == 4
                assert abs(triangle.area - .15) < 1e-8
                depths = sorted((x - ax) * nx + (z - az) * nz for x, z in list(triangle.exterior.coords)[:3])
                assert abs(depths[0]) < 1e-8 and abs(depths[1]) < 1e-8
                assert abs(depths[2] - .6) < 1e-8, 'tips face approaching traffic on every arm'
            expected = geometry.intersection(road.buffer(.3).difference(islands))
            assert expected.difference(paint.buffer(.002)).area < .001, 'all triangles reach the game mesh'
            other_marks = unary_union([build.marking_geometry(m) for m in scene['markings'] if m is not mark]
                                      + [build.edge_lines(road, build.crop_box(scene))])
            gaps = geometry.convex_hull.difference(geometry.buffer(.002)).difference(other_marks.buffer(.002))
            assert paint.intersection(gaps).area < .001, 'gaps stay empty apart from other road markings'
            solid = build.marking_geometry({k: v for k, v in mark.items() if k != 'stopStyle'})
            assert abs(solid.area - length * .4) < 1e-8, 'old stop lines are unchanged'

assert build.marking_geometry({'type':'stop','stopStyle':'yield','points':[[0,0],[0,0]]}).is_empty
assert build.marking_geometry({'type':'stop','stopStyle':'yield','points':[[0,0],[.3,0]]}).is_empty
assert build.marking_geometry({'type':'stop','stopStyle':'yield','points':[]}).is_empty
print('Yield line geometry: triangles, spacing, traffic direction, validator and game surfaces PASS')
