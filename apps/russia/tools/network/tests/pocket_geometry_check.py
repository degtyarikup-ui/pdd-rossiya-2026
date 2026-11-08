"""Pockets join real terrain; precise preset kerbs survive export. No scene writes."""
import copy
import json
import math
from pathlib import Path
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
import check
import pocket_geometry
from surface_support import SurfaceSupport


def mesh_shape(built, name):
    surface = next(s for s in built["surfaces"] if s["id"] == name)
    v, ids = surface["verts"], surface["idx"]
    return unary_union([Polygon([(v[j * 2], v[j * 2 + 1]) for j in ids[i:i + 3]])
                        for i in range(0, len(ids), 3)])


def fixture(yaw=0, side="right", walk=True, edge=True):
    forward = [math.sin(yaw), math.cos(yaw)]
    right = [-math.cos(yaw), math.sin(yaw)]
    sign = -1 if side == "left" else 1

    def point(along, across):
        return [forward[k] * along + right[k] * across * sign for k in (0, 1)]

    scene = {"schema": 1, "id": "pocket", "crop": 60,
             "roads": [{"id": "road", "outer": [point(-55, -4), point(55, -4), point(55, 4), point(-55, 4)],
                        "walk": walk, "edge": edge}],
             "pockets": [{"id": "bay", "pos": point(0, 4), "yaw": yaw, "side": side,
                          "length": 16, "width": 3, "entryLength": 8, "exitLength": 12,
                          "walk": walk, "edge": edge}],
             "stop": {"x": point(0, 5.5)[0], "z": point(0, 5.5)[1]},
             "actors": [], "routes": [], "markings": [], "lawns": []}
    return scene, point


fixtures = []
for angle in (0, .37, math.pi / 2, math.pi, -math.pi / 2):
    for side in ("left", "right"):
        scene, point = fixture(angle, side)
        before = copy.deepcopy(scene)
        built = build.build(scene)
        assert scene == before, "Building never rewrites the author's pocket"
        assert built == build.build(json.loads(json.dumps(scene))), "Save/reload keeps exact geometry"
        road, islands, _, _ = build.ground(scene)
        assert road.geom_type == "Polygon", "The open mouth joins the road without a seam"
        for along, across in ((0, 5.5), (-12, 4.8), (14, 4.8)):
            assert road.covers(Point(point(along, across))), "Flat bay and both tapers are drivable"
        assert not road.covers(Point(point(0, 7.2)))
        assert not road.covers(Point(point(-17, 4.5)))
        assert not road.covers(Point(point(21, 4.5)))
        asphalt = mesh_shape(built, "asphalt")
        assert asphalt.symmetric_difference(road).area < .05
        sidewalk = mesh_shape(built, "pavement")
        assert sidewalk.covers(Point(point(0, 8.5))), "Sidewalk moves outside the bay"
        assert not sidewalk.covers(Point(point(0, 5.5))), "No sidewalk across the pocket"
        assert sidewalk.intersection(asphalt).area < .02
        kerbs = built["kerbs"]["segs"]
        for i in range(0, len(kerbs), 4):
            segment = LineString([kerbs[i:i + 2], kerbs[i + 2:i + 4]])
            assert segment.distance(Point(point(0, 4))) > 2.9, "The mouth has no blocking kerb"
        support = SurfaceSupport(built)
        assert support.height(*point(0, 5.5)) == 0
        assert support.height(*point(0, 8.5)) == build.KERB
        assert check.road_area(scene).covers(Point(point(0, 5.5)))
        assert not any(f["code"] == "stop-off-road" for f in check.check_scene(scene))
        fixtures.append({"name": f"pocket-{angle}-{side}", "scene": scene, "build": built,
                         "drive": point(0, 5.5), "walk": point(0, 8.5)})
print("PASS pockets: left/right, rotation, smooth entries, connected carriageway, curb/pavement, save parity")

# Independent switches, a free-standing pocket, legacy source-preserving plans.
plain, point = fixture(walk=False, edge=False)
plain_built = build.build(plain)
assert not mesh_shape(plain_built, "pavement").area
assert not mesh_shape(plain_built, "marking_white").area
assert not plain_built["kerbs"]["segs"]
standalone = {**plain, "roads": []}
assert build.ground(standalone)[0].covers(Point(point(0, 5.5)))
mixed = copy.deepcopy(fixtures[0]["scene"])
mixed["layout"] = {"preserveSource": True, "nodes": [], "streets": []}
assert build.ground(mixed)[0].symmetric_difference(build.ground(fixtures[0]["scene"])[0]).area < .001
old = copy.deepcopy(fixtures[0]["scene"])
old.pop("pockets")
without = {**old, "pockets": []}
assert build.build(old) == build.build(without), "Legacy scenes remain byte-equivalent"
print("PASS switches, detached bay, preserveSource and unchanged scenes without pockets")

# Narrow exact pump islands and a separate pavement outside the forecourt.
preset = {"id": "precise-preset", "crop": 40, "roads": [
    {"id": "forecourt", "outer": [[-10, -10], [10, -10], [10, 10], [-10, 10]],
     "holes": [[[-.15, -3], [.15, -3], [.15, 3], [-.15, 3]]],
     "exact": True, "walk": False, "edge": False},
    {"id": "walkway", "outer": [[10, -10], [12, -10], [12, 10], [10, 10]],
     "surface": "pavement", "exact": True, "walk": False, "edge": False}], "markings": []}
result = build.build(preset)
road, islands, _, _ = build.ground(preset)
assert abs(islands.area - 41.8) < 1e-6
assert not road.covers(Point(0, 0)), "A 30 cm pump island must not vanish"
assert not road.covers(Point(11, 0)), "The outside walkway is not driveable asphalt"
assert abs(road.area - (400 - 1.8)) < 1e-6, "No fake asphalt surrounds the walkway"
assert mesh_shape(result, "island").covers(Point(11, 0))
assert SurfaceSupport(result).height(11, 0) == build.KERB
assert not check.road_area(preset).covers(Point(11, 0))
segments = result["kerbs"]["segs"]
assert any(LineString([segments[i:i+2], segments[i+2:i+4]]).distance(Point(12, 0)) < .001
           for i in range(0, len(segments), 4)), "The external walkway has its outside kerb"
assert not mesh_shape(result, "pavement").area, "No automatically invented pavement ring"
fixtures.append({"name": "fuel-preset", "scene": preset, "build": result,
                 "drive": [5, 0], "walk": [11, 0]})
target = build.ROOT / "scratch" / "pocket-fixtures.json"
target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(fixtures), encoding="utf-8")
print("PASS precise forecourt, 30 cm island, separate pavement, native fixtures:", target)
