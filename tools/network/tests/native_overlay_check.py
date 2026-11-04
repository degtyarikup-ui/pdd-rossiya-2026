#!/usr/bin/env python3
"""Build native/overlay scene copies in memory. Never saves scene or build files."""
import json
import subprocess
import sys
from pathlib import Path

from shapely.geometry import Polygon
from shapely.ops import unary_union

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build


def triangles(surface):
    v, idx = surface["verts"], surface["idx"]
    return unary_union([Polygon([(v[2*i], v[2*i+1]) for i in idx[k:k+3]]) for k in range(0,len(idx),3)])


def main():
    fixtures = json.loads(subprocess.check_output(["node", str(HERE/"native_overlay_check.js"), "--fixtures"], text=True))
    source = fixtures["source"]
    original = json.dumps(source)
    baseline = build.build(source)
    original_mesh = triangles(next(s for s in baseline["surfaces"] if s["id"] == "asphalt"))
    road, islands, all_roads, _ = build.ground(source)
    for key in ("empty", "deleted"):
        assert build.build(fixtures[key]) == baseline, f"{key} overlay changed native compiled surfaces"
    for key in ("added", "bent"):
        scene = fixtures[key]
        now, new_islands, _, _ = build.ground(scene)
        assert road.difference(now).area < 1e-8, f"{key} removed native road area"
        assert islands.difference(new_islands).area < 1e-8, f"{key} removed native islands"
        result = build.build(scene)
        assert all(s["id"] != "ground" for s in result["surfaces"]), "overlay covered all baked ground"
        asphalt = next(s for s in result["surfaces"] if s["id"] == "asphalt")
        # Vertex export rounds to millimetres; intersections add rounded edge
        # vertices but cannot remove a meaningful part of the existing mesh.
        assert original_mesh.difference(triangles(asphalt)).area < .005, f"{key} removed native road in actual mesh"
        assert scene["roads"][0] == source["roads"][0]
        assert scene["markings"][0] == source["markings"][0]
        assert scene["routes"] == source["routes"]
        assert scene["stop"] == source["stop"]
    # The dead end was invisible to the old boundary-only detector; it is now
    # retained from the original outline in every new-road preview and export.
    assert road.bounds[0] < -84
    assert json.dumps(source) == original
    print("Native overlay build PASS: empty overlay byte-equivalent surfaces; original road/islands retained under new and curved streets; no full-ground cover; source arrays and gameplay unchanged")


if __name__ == "__main__":
    main()
