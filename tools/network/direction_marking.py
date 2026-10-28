"""Painted lane arrows, shared by editor previews and exported Godot surfaces."""
import json
import math
from pathlib import Path

from shapely.geometry import Polygon
from shapely.ops import unary_union

SHAPES = json.loads((Path(__file__).parent / "editor/direction_arrows.json").read_text())


def error(mark):
    if not isinstance(mark.get("direction", "straight"), str) or mark.get("direction", "straight") not in SHAPES:
        return "неизвестное направление стрелки"
    points = mark.get("points")
    number = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
    if not isinstance(points, list) or len(points) != 2 or any(
            not isinstance(p, (list, tuple)) or len(p) != 2 or not all(number(v) for v in p) for p in points):
        return "нужны две точки оси стрелки"
    if not 1 <= math.dist(*points) <= 30:
        return "длина стрелки должна быть от 1 до 30 м"
    width = mark.get("width", 2.6)
    if not number(width) or not .4 <= width <= 6:
        return "ширина стрелки должна быть от 0,4 до 6 м"
    return None


def geometry(mark):
    if error(mark):
        return Polygon()
    a, b = mark["points"]
    dx, dz = b[0] - a[0], b[1] - a[1]
    length, width = math.hypot(dx, dz), mark.get("width", 2.6)
    return unary_union([Polygon([
        (a[0] + dx * z - dz / length * x * width,
         a[1] + dz * z + dx / length * x * width)
        for x, z in ring]) for ring in SHAPES[mark.get("direction", "straight")]])
