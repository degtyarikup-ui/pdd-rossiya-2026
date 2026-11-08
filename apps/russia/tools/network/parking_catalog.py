"""Adapt exported ParkingLocations building blocks to the ordinary editor scene format."""
from __future__ import annotations

import copy
import json
import math
from pathlib import Path

from shapely.geometry import Polygon
from shapely.ops import unary_union


def polygons(geometry):
    parts = geometry.geoms if hasattr(geometry, "geoms") else [geometry]
    for p in parts:
        if p.geom_type != "Polygon" or p.is_empty:
            continue
        yield {"outer": [[round(x, 3), round(z, 3)] for x, z in list(p.exterior.coords)[:-1]],
               "holes": [[[round(x, 3), round(z, 3)] for x, z in list(r.coords)[:-1]] for r in p.interiors]}


def load(path: Path, prop_index: dict) -> dict:
    if not path.is_file():
        return {"names": {}, "presets": []}
    source = json.loads(path.read_text(encoding="utf-8"))
    names = {p["id"]: p["title"] for p in source.get("props", [])}
    presets = []
    for item in source.get("presets", []):
        preset = copy.deepcopy(item)
        preset["name"] = preset.get("title", preset["id"])
        preset["previewProp"] = preset.get("previewProp", "parking/fuel_canopy")
        roads = preset.setdefault("roads", [])
        areas = preset.pop("areas", [])
        for kind, surface, title in [("asphalt", "asphalt", "Площадка АЗС"), ("sidewalk", "pavement", "Тротуар АЗС")]:
            union = unary_union([Polygon(a["points"]).buffer(0) for a in areas if a["kind"] == kind])
            for shape in polygons(union):
                roads.append({**shape, "name": title, "surface": surface, "exact": True, "walk": False, "edge": False})
        # Centre the ready-made location at the pointer, including building footprints.
        points = [p for r in roads for p in r["outer"]]
        for prop in preset.get("decor", []):
            size = prop_index.get(prop["prop"], {}).get("size", [2, 2, 2])
            scale = prop.get("scale", [1, 1, 1])
            c, s = math.cos(prop.get("yaw", 0)), math.sin(prop.get("yaw", 0))
            for sx, sz in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
                x, z = sx * size[0] * scale[0] / 2, sz * size[2] * scale[2] / 2
                points.append([prop["pos"][0] + x*c + z*s, prop["pos"][1] + z*c - x*s])
        if not points:
            continue
        low = [min(p[i] for p in points) for i in (0, 1)]
        high = [max(p[i] for p in points) for i in (0, 1)]
        centre = [(low[i] + high[i]) / 2 for i in (0, 1)]
        def shift(p):
            return [round(p[i] - centre[i], 3) for i in (0, 1)]
        for prop in preset.get("decor", []):
            prop["pos"] = shift(prop["pos"])
        for road in roads:
            road["outer"] = list(map(shift, road["outer"]))
            road["holes"] = [list(map(shift, h)) for h in road.get("holes", [])]
        for mark in preset.get("markings", []):
            if "points" in mark:
                mark["points"] = list(map(shift, mark["points"]))
            for poly in mark.get("polygons", []):
                poly["outer"] = list(map(shift, poly["outer"]))
                poly["holes"] = [list(map(shift, h)) for h in poly.get("holes", [])]
        preset["half"] = [round((high[i] - low[i]) / 2, 3) for i in (0, 1)]
        presets.append(preset)
    return {"names": names, "presets": presets}
