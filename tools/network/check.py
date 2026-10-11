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
DRIVEN_TYPES = ("car", "truck", "bus", "motorcycle", "tram", "van", "special", "tanker")


def road_area(scene: dict):
    polys = []
    for r in scene.get("roads", []):
        outer = Polygon(r["outer"])
        for h in r.get("holes", []):
            outer = outer.difference(Polygon(h))
        polys.append(outer)
    return unary_union(polys) if polys else Polygon()


def finding(out, level, code, message, ref=None):
    """ref points the editor at the object: {"type": route|road|stop|light|question|actor|prop, "id": ...}."""
    out.append({"level": level, "code": code, "message": message, "ref": ref})


def check_scene(scene: dict) -> list:
    out = []
    if scene.get("schema") != 1:
        finding(out, "error", "schema", f"неизвестная версия схемы: {scene.get('schema')!r}")
    roads = scene.get("roads", [])
    if not roads:
        finding(out, "error", "no-road", "в сцене нет ни одной дороги")
    for r in roads:
        p = Polygon(r["outer"])
        if len(r["outer"]) < 3 or not p.is_valid or p.area < 1.0:
            finding(out, "error", "road-invalid", f"{r.get('id')}: контур дороги не является корректным многоугольником",
                    {"type": "road", "id": r.get("id")})
        for h in r.get("holes", []):
            hp = Polygon(h)
            if not hp.is_valid or not p.buffer(0.05).covers(hp):
                finding(out, "error", "hole-outside", f"{r.get('id')}: островок лежит вне дороги",
                        {"type": "road", "id": r.get("id")})
    area = road_area(scene)
    stop = scene.get("stop") or {}
    stop_pt = Point(stop.get("x", 0.0), stop.get("z", 0.0))
    if not area.buffer(0.3).covers(stop_pt):
        finding(out, "error", "stop-off-road", f"стоп-линия ({stop_pt.x:.2f}, {stop_pt.y:.2f}) не на дороге",
                {"type": "stop"})

    routes = {r["id"]: r for r in scene.get("routes", [])}
    for r in scene.get("routes", []):
        pts = r.get("points", [])
        if len(pts) < 2:
            finding(out, "error", "route-short", f"{r['id']}: меньше двух точек", {"type": "route", "id": r["id"]})
            continue
        if r["kind"] in DRIVEN_KINDS:
            line = LineString(pts)
            outside = line.difference(area.buffer(0.15))
            if not outside.is_empty and outside.length > 0.3:
                finding(out, "error" if r["kind"] != "choice" else "warn", "route-off-road",
                        f"{r['id']}: {outside.length:.1f} м маршрута идёт вне дороги", {"type": "route", "id": r["id"]})
    if "approach" not in routes:
        finding(out, "error", "no-approach", "нет подъезда к стоп-линии", {"type": "stop"})
    else:
        end = Point(routes["approach"]["points"][-1])
        if end.distance(stop_pt) > 0.5:
            finding(out, "error", "approach-stop-gap", f"подъезд заканчивается в {end.distance(stop_pt):.2f} м от стоп-линии",
                    {"type": "stop"})

    for l in scene.get("lights", []):
        if not area.buffer(4.0).covers(Point(l["pos"])):
            finding(out, "warn", "light-far", f"{l['id']} стоит дальше 4 м от дороги", {"type": "light", "id": l["id"]})

    q = scene.get("question") or {}
    options = (q.get("text") or {}).get("ru", {}).get("options", [])
    correct = q.get("correct")
    if correct is None or not (0 <= correct < len(options)):
        finding(out, "error", "correct-index", f"номер правильного ответа {correct!r} вне диапазона из {len(options)} вариантов",
                {"type": "question"})
    manoeuvre = q.get("maneuver")
    if manoeuvre in MANOEUVRES and manoeuvre != "straight":
        if f"manoeuvre_{manoeuvre}" not in routes:
            finding(out, "error", "no-manoeuvre", f"у манёвра по условию «{manoeuvre}» нет маршрута",
                    {"type": "question"})
    labels = [r.get("label") for r in scene.get("routes", []) if r["kind"] == "choice"]
    if len(labels) != len(set(labels)):
        finding(out, "error", "label-dup", "два варианта ответа с одной буквой", {"type": "question"})

    # Added for the editor: things a person moves by hand and can break without noticing.
    choices = [r for r in scene.get("routes", []) if r["kind"] == "choice"]
    for r in choices:
        if not r.get("labelPosition"):
            finding(out, "warn", "label-missing", f"{r['id']}: на дороге нет буквы {r.get('label')}", {"type": "route", "id": r["id"]})
    for a in scene.get("actors", []):
        if not a.get("route") and not (a.get("behaviour") or {}).get("staysPut"):
            finding(out, "warn", "actor-no-route", f"{a['id']}: никуда не едет (нет пути) и не припаркован",
                    {"type": "actor", "id": a["id"]})
        elif a.get("type") in DRIVEN_TYPES and not area.buffer(0.5).covers(Point(a["pos"])):
            finding(out, "warn", "actor-off-road", f"{a['id']}: машина стоит вне дороги",
                    {"type": "actor", "id": a["id"]})
    for d in scene.get("decor", []):
        if area.buffer(0.5).covers(Point(d["pos"])):
            finding(out, "warn", "prop-on-road", f"{d['prop']} стоит на проезжей части", {"type": "prop", "id": d.get("id")})

    status = (scene.get("compliance") or {}).get("status")
    if status not in ("unverified", "ok", "fixed"):
        finding(out, "warn", "compliance", f"статус сверки с билетом: {status!r}", {"type": "question"})
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
