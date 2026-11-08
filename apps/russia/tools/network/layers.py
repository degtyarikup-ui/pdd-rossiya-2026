#!/usr/bin/env python3
"""Layers test: horizontal surfaces of a junction that overlap must lie at least 3 cm apart.

    tools/network/.venv/bin/python tools/network/layers.py [id ...]     # all scenes by default

What is drawn: the network's surfaces (build.py: asphalt, islands, pavement, lawns, markings) and
the baked scene (scene.glb), filtered the way the game filters it (scripts/situation.gd
_without_baked_ground, the static mesh only; textured meshes are drawn as they are). Flat triangles
are grouped by height; a pair of groups closer than 3 cm (or at the same height, from different
sources) that overlap on more than 0.05 m2 is reported. Exit status 1 when any pair is found.
"""
import sys
from pathlib import Path

import numpy as np
import shapely
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).parent))
import build  # noqa: E402
import check  # noqa: E402
import glb  # noqa: E402

MIN_GAP = 0.03
MIN_AREA = 0.05
GROUND_MAX = 0.25    # m: pairs with both surfaces above this are objects (roofs, platforms), not the road
SIT = check.ROOT / "game_godot" / "situations"


def flat_triangles(verts_xy: np.ndarray, idx: np.ndarray, y: float):
    tri = np.zeros((len(idx), 3, 3))
    tri[:, :, 0] = verts_xy[idx][:, :, 0]
    tri[:, :, 2] = verts_xy[idx][:, :, 1]
    tri[:, :, 1] = y
    return tri


def network_groups(scene: dict):
    """(height, geometry) per network surface; the drawn triangles are the build's."""
    b = build.build(scene)
    out = []
    for s in b["surfaces"]:
        if not s["idx"]:
            continue
        v = np.array(s["verts"], dtype=float).reshape(-1, 2)
        idx = np.array(s["idx"], dtype=int).reshape(-1, 3)
        polys = shapely.polygons(v[idx])
        out.append((float(s["y"]), f"net:{s['id']}", shapely.union_all(polys)))
    return out, b


def baked_triangles(sid: str, covers):
    """Triangles of the static mesh the game keeps (its filter) and of the textured meshes."""
    kept_static, kept_other = [], []
    for p in glb.primitives(SIT / sid / "scene.glb"):
        tri = p["world"][p["idx"]]
        if p["material"] != "scenery":
            kept_other.append(tri)
            continue
        flat = np.all(np.abs(tri[:, :, 1] - tri[:, :1, 1]) < 1e-3, axis=1)
        a = tri[:, 0, 1]
        lo = tri[:, :, 1].min(axis=1)
        hi = tri[:, :, 1].max(axis=1)
        drop = np.zeros(len(tri), dtype=bool)
        drop |= flat & (a < -0.001) & (a > -0.5)
        drop |= flat & (a > 0.17) & (a < 0.215)
        centre_x = tri[:, :, 0].mean(axis=1)
        centre_z = tri[:, :, 2].mean(axis=1)
        under = flat & (a >= -0.001) & (a < 0.035)
        drop |= under & shapely.contains_xy(covers, centre_x, centre_z)
        drop |= (~flat) & (lo > -0.02) & (hi < 0.215)
        kept_static.append(tri[~drop])
    return np.concatenate(kept_static) if kept_static else np.zeros((0, 3, 3)), \
        np.concatenate(kept_other) if kept_other else np.zeros((0, 3, 3))


def baked_groups(sid: str, covers):
    static, other = baked_triangles(sid, covers)
    out = []
    for tris, tag in ((static, "baked"), (other, "textured")):
        flat = np.all(np.abs(tris[:, :, 1] - tris[:, :1, 1]) < 1e-3, axis=1) if len(tris) else np.zeros(0, bool)
        tris = tris[flat]
        if not len(tris):
            continue
        heights = np.round(tris[:, 0, 1], 3)
        for h in np.unique(heights):
            part = tris[heights == h]
            geom = shapely.union_all(shapely.polygons(part[:, :, [0, 2]]))
            out.append((float(h), f"{tag}", geom))
    return out


def check_scene(sid: str):
    scene = check.load(sid)
    net, b = network_groups(scene)
    covers = unary_union([g for _, _, g in net])
    groups = net + baked_groups(sid, covers)
    groups.sort(key=lambda g: g[0])
    found = []
    for i, (h1, s1, g1) in enumerate(groups):
        for h2, s2, g2 in groups[i + 1:]:
            dh = h2 - h1
            if dh >= MIN_GAP - 1e-9:
                break
            if dh <= 1e-9 and s1 == s2:
                continue
            if dh <= 1e-9 and s1.startswith("net") and s2.startswith("net"):
                continue
            area = g1.intersection(g2).area
            if area > MIN_AREA:
                found.append((round(h1, 3), s1, round(h2, 3), s2, round(area, 2)))
    ground = [f for f in found if max(f[0], f[2]) <= GROUND_MAX]
    objects = [f for f in found if max(f[0], f[2]) > GROUND_MAX]
    return ground, objects


def main(argv):
    ids = argv or sorted(p.stem for p in check.NET.glob("*.json"))
    bad = objects = 0
    for sid in ids:
        if not (SIT / sid / "scene.glb").exists():
            continue
        ground, above = check_scene(sid)
        objects += len(above)
        if ground:
            bad += 1
            for h1, s1, h2, s2, area in ground:
                print(f"{sid}: {s1} at {h1:+.3f} and {s2} at {h2:+.3f} overlap {area} m2")
    print(f"checked {len(ids)} scenes: {bad} with ground surfaces closer than 3 cm; "
          f"object pairs above {GROUND_MAX} m (not road, not judged): {objects}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
