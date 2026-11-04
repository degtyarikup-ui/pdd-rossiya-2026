"""Editable roadside pockets, in the editor's ground coordinates and radian yaw.

``pos`` is the midpoint of the mouth's straight part, ``length`` its usable
length, and entry/exit lengths are additional tapers. The same cubic profile
is drawn by editor/road_pocket.js; only this derived copy enters triangulation.
"""
import math


def number(value, default, minimum=None, maximum=None):
    try:
        result = float(value)
    except (TypeError, ValueError):
        result = default
    if not math.isfinite(result):
        result = default
    if minimum is not None:
        result = max(minimum, result)
    if maximum is not None:
        result = min(maximum, result)
    return result


def outline(pocket):
    """Closed by the caller; right is [-cos(yaw), sin(yaw)], as in Layout."""
    length = number(pocket.get("length"), 16, 1, 200)
    width = number(pocket.get("width"), 3, .5, 30)
    entry = number(pocket.get("entryLength"), 8, 1, 150)
    exit_length = number(pocket.get("exitLength"), 8, 1, 150)
    yaw = number(pocket.get("yaw"), 0)
    pos = pocket.get("pos")
    if not isinstance(pos, (list, tuple)) or len(pos) < 2:
        pos = (0, 0)
    x, z = number(pos[0], 0), number(pos[1], 0)
    side = -1 if pocket.get("side") in ("left", -1) else 1
    forward = (math.sin(yaw), math.cos(yaw))
    right = (-math.cos(yaw) * side, math.sin(yaw) * side)

    def point(along, across):
        return [x + forward[0] * along + right[0] * across,
                z + forward[1] * along + right[1] * across]

    def smooth(t):
        return t * t * (3 - 2 * t)

    points = []
    for i in range(max(8, math.ceil(entry / .5)) + 1):
        t = i / max(8, math.ceil(entry / .5))
        points.append(point(-length / 2 - entry + entry * t, width * smooth(t)))
    points.append(point(length / 2, width))
    for i in range(1, max(8, math.ceil(exit_length / .5)) + 1):
        t = i / max(8, math.ceil(exit_length / .5))
        points.append(point(length / 2 + exit_length * t, width * (1 - smooth(t))))
    return points


def with_roads(scene):
    """Expand pockets into derived road items without changing authored data.

    Their outlines bypass the legacy corner regularisation: a short or steep
    taper must retain its authored dimensions. All remaining road consumers
    (surface, sidewalk, edge switches, export) receive the same polygons.
    """
    if not scene.get("pockets"):
        return scene
    roads = list(scene.get("roads", []))
    roads.extend({"id": f"pocket_{p.get('id', i)}", "outer": outline(p), "holes": [],
                  "pocket": True, "walk": p.get("walk") is not False,
                  "edge": p.get("edge") is not False, "surface": "asphalt"}
                 for i, p in enumerate(scene["pockets"]) if isinstance(p, dict))
    return {**scene, "roads": roads, "pockets": []}
