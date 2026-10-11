#!/usr/bin/env python3
"""Migrates the exported junction scenes (game_godot/situations/<id>/) into the
road-network format (game_godot/network/<id>.json), the source of truth the
Godot game and the web editor read and write.

    tools/network/.venv/bin/python tools/network/migrate.py [id ...]

What is converted and how:
- roads: the drivable mask road.png (0.25 m cells, the exact area the game
  drives on) is traced into polygons (even-odd, so islands become holes).
- routes: manoeuvre routes (scene exits), choice routes (the labelled А/Б/В
  routes the question shows), actor routes (scene actors' paths), and the
  approach route to the stop line (lane assist, as in game.js lane goal).
- stop / start / lights / decor / question: copied from scene.json, with the
  game's defaults where an older export left a field out.
Signs, road markings and kerbs stay in the baked scene.glb until the next
export moves them into data too (see docs/game/road-network.md).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from shapely.geometry import LineString, Polygon, mapping
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from skimage import measure

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "game_godot" / "situations"
DST = ROOT / "game_godot" / "network"

SCHEMA = 1
ROUTE_SIMPLIFY = 0.12    # m: routes keep their shape with ~1 point per 2-4 m
ROAD_SIMPLIFY = 0.08     # m: tolerance of the traced road outline
DEFAULT_WIDTH = 8.4


def trace_mask(path: Path, mask: dict):
    """Binary mask -> shapely geometry in metres (even-odd of all contours)."""
    cell = float(mask["cell"])
    img = np.array(Image.open(path).convert("L")) > 127
    padded = np.pad(img, 1, constant_values=False).astype(float)
    region = Polygon()
    rings = []
    for c in measure.find_contours(padded, 0.5):
        if len(c) < 4:
            continue
        # contour (row, col) in padded pixel-centre space -> world metres
        xs = mask["x"] + (c[:, 1] - 1 + 0.5) * cell
        zs = mask["z"] + (c[:, 0] - 1 + 0.5) * cell
        ring = Polygon(np.column_stack([xs, zs]))
        if ring.is_valid and ring.area > 0.01:
            rings.append(ring)
    # Even-odd: every ring toggles membership, so holes and islands come out right.
    rings.sort(key=lambda p: -p.area)
    for ring in rings:
        region = region.symmetric_difference(ring)
    region = region.simplify(ROAD_SIMPLIFY, preserve_topology=True)
    return region


def polygons_of(geom):
    if geom.is_empty:
        return []
    parts = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
    out = []
    for part in parts:
        if part.geom_type != "Polygon" or part.area < 0.2:
            continue
        part = orient(part, 1.0)   # outer counter-clockwise, holes clockwise
        out.append({
            "outer": [[round(x, 3), round(z, 3)] for x, z in part.exterior.coords[:-1]],
            "holes": [[[round(x, 3), round(z, 3)] for x, z in ring.coords[:-1]] for ring in part.interiors],
        })
    return out


def route(rid, kind, points, **extra):
    line = LineString([(p[0], p[2] if len(p) == 3 else p[1]) for p in points])
    if line.length > 0.5:
        line = line.simplify(ROUTE_SIMPLIFY, preserve_topology=False)
    pts = [[round(x, 3), round(z, 3)] for x, z in line.coords]
    return {"id": rid, "kind": kind, "points": pts, **extra}


def approach_route(scene: dict, crop: float):
    """The lane the car drives into the junction on (game.js lane assist):
    the lane centre -1.8 until the ticket's start lane, then the start lane."""
    stop_z = float(scene["stopZ"])
    start_x = scene.get("playerStartX")
    if start_x is None:
        return [[-1.8, -crop], [-1.8, stop_z]]
    start_x = float(start_x)
    if abs(start_x + 1.8) < 0.3:
        return [[-1.8, -crop], [-1.8, stop_z]]
    ease_from = stop_z - 14.0
    return [[-1.8, -crop], [-1.8, ease_from], [start_x, stop_z]]


def migrate(scene_id: str) -> dict:
    src = SRC / scene_id
    scene = json.loads((src / "scene.json").read_text(encoding="utf-8"))
    crop = float(scene.get("crop", 90.0))
    roads = polygons_of(trace_mask(src / "road.png", scene["roadMask"]))

    routes = []
    for action, data in (scene.get("exits") or {}).items():
        routes.append(route(f"manoeuvre_{action}", "manoeuvre", data["points"], exit=action,
                            exitYaw=data.get("exitYaw", 0.0)))
    for tr in scene.get("trajectories") or []:
        routes.append(route(f"choice_{tr['label']}", "choice", tr["points"], label=tr["label"],
                            labelPosition=tr.get("labelPosition")))
    routes.append(route("approach", "approach", approach_route(scene, crop)))
    actors = []
    for i, a in enumerate(scene.get("actors") or []):
        rid = f"actor_{a['id']}"
        if a.get("path"):
            routes.append(route(rid, "actor", a["path"]))
        actors.append({
            "id": a["id"], "type": a.get("type"), "name": a.get("name", ""),
            "route": rid if a.get("path") else None,
            "pos": a["pos"], "yaw": a.get("yaw", 0.0), "scale": a.get("scale", [1, 1, 1]),
            "halfLength": a.get("halfLength"), "halfWidth": a.get("halfWidth"),
            "maxSpeed": a.get("maxSpeed"), "clearDistance": a.get("clearDistance"),
            "behaviour": {k: a.get(k) for k in ("stopAtDistance", "stopFor", "holdFor", "staysPut",
                                                 "signalPlan", "waitsForPlayer", "config")},
            "wheelsRadius": 0.36,
        })

    question = {
        "text": scene.get("text", {}),
        "correct": scene.get("correctAnswerIndex"),
        "answerSeconds": None,
        "sourceTextLength": scene.get("sourceTextLength"),
        "redWait": scene.get("redWait"),
        "requiredStop": scene.get("requiredStop"),
        "speedLimit": scene.get("speedLimit"),
        "maneuver": (scene.get("spec") or {}).get("maneuver"),
        "yieldTo": (scene.get("spec") or {}).get("yieldTo", []),
        "legend": scene.get("legend", []),
    }
    lights = []
    state = (scene.get("trafficLights") or {}).get("state")
    for i, l in enumerate(scene.get("lights") or []):
        lights.append({"id": f"light_{i}", "pos": [l["pos"][0], l["pos"][2]], "yaw": l.get("yaw", 0.0),
                       "scale": l.get("scale", 1.0), "arrow": l.get("arrow"), "state": state})

    return {
        "schema": SCHEMA,
        "id": scene_id,
        "frame": "junction centre (0, 0); +z = direction of travel on the approach; +x = driver's left",
        "crop": crop,
        "geometry": scene.get("geometry"),
        "type": scene.get("type"),
        "roads": [{"id": f"road_{i}", **p} for i, p in enumerate(roads)],
        "routes": routes,
        "stop": {"x": round(-1.8 if scene.get("playerStartX") is None else float(scene["playerStartX"]), 3),
                 "z": round(float(scene["stopZ"]), 3), "yaw": float(scene.get("playerStartRotY", 0.0))},
        "lights": lights,
        "actors": actors,
        "decor": [{"prop": p["prop"], "pos": [p["pos"][0], p["pos"][2]], "yaw": p.get("yaw", 0.0),
                   "scale": p.get("scale", [1, 1, 1]), "tint": p.get("tint")} for p in scene.get("props", [])],
        "questionCamera": scene.get("questionCamera", []),
        "question": question,
        "approachWidth": scene.get("approachW", DEFAULT_WIDTH),
        "exitWidths": scene.get("exitWidths") or {"straight": DEFAULT_WIDTH, "left": DEFAULT_WIDTH, "right": DEFAULT_WIDTH},
        "compliance": {"status": "unverified", "by": None, "notes": ""},
        "staticScene": f"{scene_id}/scene.glb",
    }


def main(argv):
    DST.mkdir(parents=True, exist_ok=True)
    ids = argv or sorted(p.name for p in SRC.iterdir() if (p / "scene.json").exists())
    for scene_id in ids:
        data = migrate(scene_id)
        (DST / f"{scene_id}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{scene_id:14} roads {len(data['roads'])}  routes {len(data['routes'])}  actors {len(data['actors'])}  decor {len(data['decor'])}")


if __name__ == "__main__":
    main(sys.argv[1:])
