#!/usr/bin/env python3
"""Invariants of a road-network scene (game_godot/network/<id>.json).

    tools/network/.venv/bin/python tools/network/check.py [id ...]     # all scenes by default

Each finding is {level: error|warn, code, message}. Errors mean the scene
cannot be driven correctly (the car would leave the road, the question could
not be answered on the road); warnings are things to look at by hand.
The web editor calls check_scene() on every save.
"""
import json
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
NET = ROOT / "game_godot" / "network"
DRIVEN_KINDS = ("manoeuvre", "approach", "choice")
MANOEUVRES = ("left", "right", "straight", "uturn")


def road_area(scene: dict):
    polys = []
    for r in scene.get("roads", []):
        outer = Polygon(r["outer"])
        for h in r.get("holes", []):
            outer = outer.difference(Polygon(h))
        polys.append(outer)
    return unary_union(polys) if polys else Polygon()


def finding(out, level, code, message):
    out.append({"level": level, "code": code, "message": message})


def check_scene(scene: dict) -> list:
    out = []
    if scene.get("schema") != 1:
        finding(out, "error", "schema", f"unknown schema {scene.get('schema')!r}")
    roads = scene.get("roads", [])
    if not roads:
        finding(out, "error", "no-road", "the scene has no road polygons")
    for r in roads:
        p = Polygon(r["outer"])
        if len(r["outer"]) < 3 or not p.is_valid or p.area < 1.0:
            finding(out, "error", "road-invalid", f"{r.get('id')}: outline is not a valid polygon")
        for h in r.get("holes", []):
            hp = Polygon(h)
            if not hp.is_valid or not p.buffer(0.05).covers(hp):
                finding(out, "error", "hole-outside", f"{r.get('id')}: a hole is not inside its road")
    area = road_area(scene)
    stop = scene.get("stop") or {}
    stop_pt = Point(stop.get("x", 0.0), stop.get("z", 0.0))
    if not area.buffer(0.3).covers(stop_pt):
        finding(out, "error", "stop-off-road", f"stop point ({stop_pt.x:.2f}, {stop_pt.y:.2f}) is not on the road")

    routes = {r["id"]: r for r in scene.get("routes", [])}
    for r in scene.get("routes", []):
        pts = r.get("points", [])
        if len(pts) < 2:
            finding(out, "error", "route-short", f"{r['id']}: fewer than two points")
            continue
        if r["kind"] in DRIVEN_KINDS:
            line = LineString(pts)
            outside = line.difference(area.buffer(0.15))
            if not outside.is_empty and outside.length > 0.3:
                finding(out, "error" if r["kind"] != "choice" else "warn", "route-off-road",
                        f"{r['id']}: {outside.length:.1f} m of the route lies off the road")
    if "approach" not in routes:
        finding(out, "error", "no-approach", "no approach route to the stop line")
    else:
        end = Point(routes["approach"]["points"][-1])
        if end.distance(stop_pt) > 0.5:
            finding(out, "error", "approach-stop-gap", f"approach ends {end.distance(stop_pt):.2f} m from the stop point")

    for l in scene.get("lights", []):
        if not area.buffer(4.0).covers(Point(l["pos"])):
            finding(out, "warn", "light-far", f"{l['id']} stands more than 4 m from the road")

    q = scene.get("question") or {}
    options = (q.get("text") or {}).get("ru", {}).get("options", [])
    correct = q.get("correct")
    if correct is None or not (0 <= correct < len(options)):
        finding(out, "error", "correct-index", f"correct answer {correct!r} is not one of {len(options)} options")
    manoeuvre = q.get("maneuver")
    if manoeuvre in MANOEUVRES and manoeuvre != "straight":
        if f"manoeuvre_{manoeuvre}" not in routes:
            finding(out, "error", "no-manoeuvre", f"the question's manoeuvre '{manoeuvre}' has no route")
    labels = [r.get("label") for r in scene.get("routes", []) if r["kind"] == "choice"]
    if len(labels) != len(set(labels)):
        finding(out, "error", "label-dup", "two choice routes carry the same letter")

    status = (scene.get("compliance") or {}).get("status")
    if status not in ("unverified", "ok", "fixed"):
        finding(out, "warn", "compliance", f"compliance status is {status!r}")
    return out


def load(scene_id: str) -> dict:
    return json.loads((NET / f"{scene_id}.json").read_text(encoding="utf-8"))


def main(argv):
    ids = argv or sorted(p.stem for p in NET.glob("*.json"))
    errors = warns = 0
    for scene_id in ids:
        found = check_scene(load(scene_id))
        e = sum(1 for f in found if f["level"] == "error")
        w = sum(1 for f in found if f["level"] == "warn")
        errors += e
        warns += w
        if found:
            print(f"{scene_id}: {e} errors, {w} warnings")
            for f in found:
                print(f"  {f['level']:5} {f['code']}: {f['message']}")
    print(f"checked {len(ids)} scenes: {errors} errors, {warns} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
