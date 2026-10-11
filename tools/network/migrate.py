#!/usr/bin/env python3
"""Migrates the exported junction scenes (game_godot/situations/<id>/) into the
road-network format (game_godot/network/<id>.json), the source of truth the
Godot game and the web editor read and write.

    tools/network/.venv/bin/python tools/network/migrate.py [id ...]           # base network (once per scene)
    tools/network/.venv/bin/python tools/network/migrate.py --layers [id ...]   # lawns and markings out of the baked scene

What is converted and how:
- roads: the drivable mask road.png (0.25 m cells, the exact area the game
  drives on) is traced into polygons (even-odd, so islands become holes).
- routes: manoeuvre routes (scene exits), choice routes (the labelled А/Б/В
  routes the question shows), actor routes (scene actors' paths), and the
  approach route to the stop line (lane assist, as in game.js lane goal).
- stop / start / lights / decor / question: copied from scene.json, with the
  game's defaults where an older export left a field out.
- --layers: the lawns (grass) and the paint on the carriageway are taken from
  the baked scene (baked.glb, the export as it came out) into `lawns` and
  `markings`; scene.glb is written again without them. See build.py for how the
  network draws them. Signs and kerb walls stay in the baked scene.
"""
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import shapely
from PIL import Image
from shapely.geometry import LineString, Polygon, mapping
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from skimage import measure

sys.path.insert(0, str(Path(__file__).parent))
import build  # noqa: E402
import glb  # noqa: E402

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
        "reviewed": bool(scene.get("reviewed", True)),
        "regulator": bool(scene.get("regulator", False)),
        "compliance": {"status": "unverified", "by": None, "notes": ""},
        "staticScene": f"{scene_id}/scene.glb",
    }


# ---- lawns and markings: taken out of the baked scene -------------------------------------
# The exporter bakes lawns and road markings into the static mesh. The network draws them now, so
# they move from the baked scene (scene.glb, kept as baked.glb) into the network JSON, and the
# game's scene.glb is written again without them. Classes of the baked triangles:
#   lawn    flat, 3 cm to 30 cm under the road level, grass layer (uv2 = 16, scenery.gd) or grass colour;
#   white / yellow   flat, 1.5 cm to 4.5 cm over the road level, paint colour, on the carriageway.
# The textured dirt blobs (tex_N, alpha) and everything else stay in the scene as they are.
GRASS_LAYER = 16
LAYER_SIMPLIFY = 0.005   # m: paint is thin, a 2 cm tolerance cost up to 3% of its area
GRASS_RGB = np.array([0.61, 0.65, 0.42])
LAWN_BAND = (-0.03, 0.0005)
MARK_BAND = (0.015, 0.045)


def road_cover_of(net: dict):
    """The carriageway (islands cut out) with 0.3 m of margin: markings are taken only from there."""
    polys = []
    for r in net.get("roads", []):
        p = Polygon(r["outer"]).buffer(0)
        for h in r.get("holes", []):
            p = p.difference(Polygon(h).buffer(0))
        polys.append(p)
    return unary_union(polys).buffer(0.3) if polys else Polygon()


def baked_classes(p: dict, road_cover):
    """Bool masks over the triangles of one baked primitive: (lawn, white, yellow)."""
    idx, pos = p["idx"], p["pos"]
    tri = pos[idx]
    flat = np.all(np.abs(tri[:, :, 1] - tri[:, :1, 1]) < 1e-3, axis=1)
    y = tri[:, 0, 1]
    first = idx[:, 0]
    lay = np.round(p["layer"][first, 0]) if p["layer"] is not None else np.zeros(len(idx))
    col = p["colour"][first, :3] if p["colour"] is not None else np.zeros((len(idx), 3))
    grass = np.all(np.abs(col - GRASS_RGB) < 0.011, axis=1)
    lawn = flat & (y > LAWN_BAND[0]) & (y < LAWN_BAND[1]) & ((lay == GRASS_LAYER) | grass)
    band = flat & (y > MARK_BAND[0]) & (y < MARK_BAND[1])
    white = band & np.all(col > 0.93, axis=1)
    yellow = band & (col[:, 0] > 0.9) & (col[:, 1] > 0.6) & (col[:, 1] < 0.85) & (col[:, 2] < 0.3)
    on = shapely.contains_xy(road_cover, tri[:, :, 0].mean(axis=1), tri[:, :, 2].mean(axis=1))
    return lawn, white & on, yellow & on


def union_of(tris: np.ndarray):
    """Triangles (T x 3 x 3, world) -> one geometry in metres (x, z)."""
    if not len(tris):
        return Polygon()
    polys = shapely.polygons(tris[:, :, [0, 2]])
    return shapely.union_all(polys).buffer(0)


def clean_parts(parts: list) -> list:
    """Holes that are slivers (a ring of zero area from the tracing) are dropped: they are not holes."""
    out = []
    for part in parts:
        holes = [h for h in part["holes"] if len(h) >= 3 and Polygon(h).is_valid and Polygon(h).area >= 0.2]
        out.append({"outer": part["outer"], "holes": holes})
    return out


def extract_layers(scene_id: str, net: dict):
    """(lawns, markings) of the baked scene: polygons for the network."""
    road_cover = road_cover_of(net)
    lawn_tris, white_tris, yellow_tris = [], [], []
    for p in glb.primitives(SRC / scene_id / "baked.glb"):
        if p["material"] != "scenery":
            continue
        lawn, white, yellow = baked_classes({"idx": p["idx"], "pos": p["world"], "colour": p["colour"], "layer": p["layer"]}, road_cover)
        lawn_tris.append(p["world"][p["idx"][lawn]])
        white_tris.append(p["world"][p["idx"][white]])
        yellow_tris.append(p["world"][p["idx"][yellow]])
    lawn_geom = union_of(np.concatenate(lawn_tris)) if lawn_tris else Polygon()
    # The baked grass also lies under the roads and the pavement: those the network draws itself.
    _, _, roads_all, ring = build.ground(net)
    lawn_geom = lawn_geom.difference(roads_all).difference(ring)
    lawn_geom = lawn_geom.simplify(LAYER_SIMPLIFY, preserve_topology=True)
    lawns = [{"id": f"lawn_{i}", **part} for i, part in enumerate(clean_parts(polygons_of(lawn_geom)))]
    markings = []
    for colour, tris in (("white", white_tris), ("yellow", yellow_tris)):
        geom = union_of(np.concatenate(tris)) if tris else Polygon()
        geom = geom.simplify(LAYER_SIMPLIFY, preserve_topology=True)
        parts = clean_parts(polygons_of(geom))
        if parts:
            markings.append({"id": f"paint_{colour}", "type": "paint", "colour": colour, "polygons": parts})
    return lawns, markings


def strip_layers(scene_id: str, net: dict) -> dict:
    """Writes situations/<id>/scene.glb without the lawn and marking triangles (from baked.glb)."""
    road_cover = road_cover_of(net)

    def drop(p):
        lawn, white, yellow = baked_classes(p, road_cover)
        return lawn | white | yellow

    return glb.strip_triangles(SRC / scene_id / "baked.glb", SRC / scene_id / "scene.glb", drop)


def migrate_layers(scene_id: str) -> str:
    """Once per scene: lawns and markings into the network JSON, the baked copies out of scene.glb.
    A scene that already has them keeps its network JSON (the editor's work); its scene.glb is rebuilt."""
    src = SRC / scene_id
    net_path = DST / f"{scene_id}.json"
    net = json.loads(net_path.read_text(encoding="utf-8"))
    if not (src / "baked.glb").exists():
        shutil.copyfile(src / "scene.glb", src / "baked.glb")
    state = "kept"
    if "lawns" not in net and "markings" not in net:
        lawns, markings = extract_layers(scene_id, net)
        net["lawns"] = lawns
        net["markings"] = markings
        net_path.write_text(json.dumps(net, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        state = "migrated"
    removed = strip_layers(scene_id, net)
    lawn_area = sum(Polygon(l["outer"]).area - sum(Polygon(h).area for h in l["holes"]) for l in net.get("lawns", []))
    marks = sum(len(m.get("polygons", [])) for m in net.get("markings", []))
    return (f"{scene_id:14} {state:8} lawns {len(net.get('lawns', []))} ({lawn_area:8.0f} m2)  "
            f"paint polygons {marks}  baked triangles removed {removed['triangles']}")


def main(argv):
    if "--layers" in argv:
        ids = [a for a in argv if not a.startswith("--")] or sorted(p.name for p in SRC.iterdir() if (p / "scene.json").exists())
        for scene_id in ids:
            print(migrate_layers(scene_id))
        return
    DST.mkdir(parents=True, exist_ok=True)
    ids = argv or sorted(p.name for p in SRC.iterdir() if (p / "scene.json").exists())
    for scene_id in ids:
        data = migrate(scene_id)
        (DST / f"{scene_id}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{scene_id:14} roads {len(data['roads'])}  routes {len(data['routes'])}  actors {len(data['actors'])}  decor {len(data['decor'])}")


if __name__ == "__main__":
    main(sys.argv[1:])
