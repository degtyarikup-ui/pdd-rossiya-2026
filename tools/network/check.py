#!/usr/bin/env python3
"""Invariants of a road-network scene (game_godot/network/<id>.json).

    tools/network/.venv/bin/python tools/network/check.py [id ...]     # all scenes by default

Each finding is {level: error|warn, code, message}. Errors mean the scene
cannot be driven correctly (the car would leave the road, the question could
not be answered on the road); warnings are things to look at by hand.
The web editor calls check_scene() on every save.
"""
import json
import math
import re
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon
from shapely import make_valid
from shapely.ops import unary_union
import direction_marking

ROOT = Path(__file__).resolve().parents[2]
NET = ROOT / "game_godot" / "network"
DRIVEN_KINDS = ("manoeuvre", "approach", "choice", "guide")
MANOEUVRES = ("left", "right", "straight", "uturn")
DRIVEN_TYPES = ("car", "truck", "bus", "motorcycle", "tram", "van", "special", "tanker")


def road_area(scene: dict):
    # make_valid: an outline that crosses itself (a drawn road doubling back) is repaired for the sums;
    # its own finding (road-invalid) tells the user what is wrong.
    polys = []
    for r in scene.get("roads", []):
        outer = make_valid(Polygon(r["outer"]))
        for h in r.get("holes", []):
            outer = outer.difference(make_valid(Polygon(h)))
        polys.append(outer)
    return unary_union(polys) if polys else Polygon()


def finding(out, level, code, message, ref=None):
    """ref points the editor at the object: {"type": route|road|stop|light|question|actor|prop, "id": ...}."""
    out.append({"level": level, "code": code, "message": message, "ref": ref})


MARKING_TYPES = ("paint", "solid", "dashed", "stop", "zebra", "arrow")
MARKING_COLOURS = ("white", "yellow")
LINE_MARKINGS = ("solid", "dashed", "stop", "zebra")


def check_question_view(scene: dict, out: list) -> None:
    """Old centre/height frames remain valid; optional free-camera values must be finite."""
    view = scene.get("questionView")
    if view is None:
        return

    def number(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)

    valid = isinstance(view, dict)
    if valid:
        centre = view.get("centre")
        valid = (isinstance(centre, list) and len(centre) == 2
                 and all(number(v) for v in centre)
                 and number(view.get("height")) and view["height"] > 0)
        for key in ("yaw", "pitch", "elevation"):
            if key in view and not number(view[key]):
                valid = False
        if number(view.get("pitch")) and not 0 < view["pitch"] < math.pi / 2:
            valid = False
    if not valid:
        finding(out, "error", "question-camera", "Некорректный ракурс камеры вопроса: настройте кадр заново",
                {"type": "question"})


def check_layers(scene: dict, area, out: list) -> None:
    """Lawns and markings (build.py): polygons that are valid, known types, paint on the carriageway."""
    for l in scene.get("lawns", []):
        ref = {"type": "lawn", "id": l.get("id")}
        raw = Polygon(l.get("outer", []))
        p = make_valid(raw)
        if len(l.get("outer", [])) < 3 or not raw.is_valid or p.area < 1.0:
            finding(out, "error", "lawn-invalid", f"{l.get('id')}: контур газона не является корректным многоугольником", ref)
        for h in l.get("holes", []):
            if not Polygon(h).is_valid or not p.buffer(0.05).covers(make_valid(Polygon(h))):
                finding(out, "error", "lawn-hole", f"{l.get('id')}: дыра газона лежит вне газона", ref)
    for m in scene.get("markings", []):
        if m.get("colour") == "rail":
            continue  # Retired traced rails stay in source but are no longer drawn.
        ref = {"type": "marking", "id": m.get("id")}
        kind = m.get("type")
        if kind not in MARKING_TYPES:
            finding(out, "error", "marking-type", f"{m.get('id')}: неизвестный тип разметки {kind!r}", ref)
            continue
        if m.get("colour", "white") not in MARKING_COLOURS:
            finding(out, "error", "marking-colour", f"{m.get('id')}: неизвестный цвет разметки {m.get('colour')!r}", ref)
        if kind == "arrow":
            problem = direction_marking.error(m)
            if problem:
                finding(out, "error", "marking-arrow", f"{m.get('id')}: {problem}", ref)
                continue
            outside = direction_marking.geometry(m).difference(area.buffer(0.3)).area
            if outside > .1:
                finding(out, "warn", "marking-off-road", f"{m.get('id')}: {outside:.1f} м² стрелки вне дороги", ref)
        elif kind == "paint":
            parts = [Polygon(p["outer"]) for p in m.get("polygons", [])]
            if not parts or any(not p.is_valid for p in parts):
                finding(out, "error", "marking-invalid", f"{m.get('id')}: контур разметки не является корректным многоугольником", ref)
                continue
            outside = unary_union(parts).difference(area.buffer(0.3)).area
            if outside > 0.5:
                finding(out, "warn", "marking-off-road", f"{m.get('id')}: {outside:.1f} м² краски вне дороги", ref)
        elif kind in LINE_MARKINGS:
            pts = m.get("points", [])
            if len(pts) < 2:
                finding(out, "error", "marking-short", f"{m.get('id')}: у разметки меньше двух точек", ref)
                continue
            if kind == "zebra" and LineString(pts[:2]).length < 1.0:
                finding(out, "error", "marking-short", f"{m.get('id')}: зебра короче метра", ref)
            if LineString(pts).difference(area.buffer(0.3)).length > 0.3:
                finding(out, "warn", "marking-off-road", f"{m.get('id')}: часть разметки вне дороги", ref)


def check_scene(scene: dict) -> list:
    out = []
    check_question_view(scene, out)
    if scene.get("schema") != 1:
        finding(out, "error", "schema", f"неизвестная версия схемы: {scene.get('schema')!r}")
    roads = scene.get("roads", [])
    if not roads:
        finding(out, "error", "no-road", "в сцене нет ни одной дороги")
    for r in roads:
        raw = Polygon(r["outer"])
        p = make_valid(raw)
        if len(r["outer"]) < 3 or not raw.is_valid or p.area < 1.0:
            finding(out, "error", "road-invalid", f"{r.get('id')}: контур дороги не является корректным многоугольником",
                    {"type": "road", "id": r.get("id")})
        for h in r.get("holes", []):
            hp = Polygon(h)
            if not hp.is_valid or not p.buffer(0.05).covers(make_valid(hp)):
                finding(out, "error", "hole-outside", f"{r.get('id')}: островок лежит вне дороги",
                        {"type": "road", "id": r.get("id")})
    area = road_area(scene)
    for message in scene.get("playerRouteErrors", []):
        finding(out, "error", "player-route", str(message), {"type": "stop"})
    stop = scene.get("stop") or {}
    stop_pt = Point(stop.get("x", 0.0), stop.get("z", 0.0))
    if not area.buffer(0.3).covers(stop_pt):
        finding(out, "error", "stop-off-road", f"стоп-линия ({stop_pt.x:.2f}, {stop_pt.y:.2f}) не на дороге",
                {"type": "stop"})

    routes = {r["id"]: r for r in scene.get("routes", [])}
    for r in scene.get("routes", []):
        pts = r.get("points", [])
        if r.get("kind") == "annotation":
            number = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
            valid_points = isinstance(pts, list) and len(pts) >= 2 and all(
                isinstance(p, (list, tuple)) and len(p) == 2 and all(number(v) for v in p) for p in pts)
            width = r.get("width", .16)
            if (not valid_points or (valid_points and LineString(pts).length < .1)
                    or r.get("style", "line") not in ("line", "arrow", "both")
                    or not number(width) or not .08 <= width <= .6
                    or not isinstance(r.get("colour", "#20242b"), str)
                    or not re.fullmatch(r"#[0-9a-fA-F]{6}", r.get("colour", "#20242b"))):
                finding(out, "error", "annotation-invalid", f"{r['id']}: проверьте точки, вид, толщину и цвет обозначения", {"type":"route", "id":r['id']})
            continue
        if len(pts) < 2:
            finding(out, "error", "route-short", f"{r['id']}: меньше двух точек", {"type": "route", "id": r["id"]})
            continue
        if r["kind"] in DRIVEN_KINDS:
            line = LineString(pts)
            outside = line.difference(area.buffer(0.15))
            if not outside.is_empty and outside.length > 0.3:
                finding(out, "warn" if r["kind"] in ("choice", "guide") else "error", "route-off-road",
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
    mini_regulator = scene.get("id") == "mini_regulator" and scene.get("miniGame") == "regulator"
    if not mini_regulator and (correct is None or not (0 <= correct < len(options))):
        finding(out, "error", "correct-index", f"номер правильного ответа {correct!r} вне диапазона из {len(options)} вариантов",
                {"type": "question"})
    manoeuvre = q.get("maneuver")
    if manoeuvre in MANOEUVRES:
        if f"manoeuvre_{manoeuvre}" not in routes:
            finding(out, "error", "no-manoeuvre", f"у манёвра по условию «{manoeuvre}» нет маршрута",
                    {"type": "question"})
    labels = [r.get("label") for r in scene.get("routes", []) if r["kind"] == "choice"]
    if mini_regulator:
        if len(scene.get("officers", [])) != 1:
            finding(out, "error", "regulator-count", "В мини-игре должен быть один регулировщик")
        for move in MANOEUVRES:
            route = routes.get(f"manoeuvre_{move}")
            if not route or len(route.get("points", [])) < 2:
                finding(out, "error", "regulator-route", f"Нет пути игрока: {move}")
            elif Point(route["points"][0]).distance(stop_pt) > .05:
                finding(out, "error", "regulator-route-start", f"Путь {move} должен начинаться у игрока")
    if len(labels) != len(set(labels)):
        finding(out, "error", "label-dup", "два варианта ответа с одной буквой", {"type": "question"})

    # Added for the editor: things a person moves by hand and can break without noticing.
    choices = [r for r in scene.get("routes", []) if r["kind"] == "choice"]
    for r in choices:
        if not r.get("labelPosition"):
            finding(out, "warn", "label-missing", f"{r['id']}: на дороге нет буквы {r.get('label')}", {"type": "route", "id": r["id"]})
    for a in scene.get("actors", []):
        if a.get("type") == "pedestrian" and (
                a.get("pedestrianPose", "stand") not in ("stand", "hail", "forward", "raised")
                or a.get("poseArm", "right") not in ("left", "right")
                or ("pedestrianLook" in a and (type(a["pedestrianLook"]) is not int or not 0 <= a["pedestrianLook"] < 12))):
            finding(out, "error", "actor-appearance", f"{a['id']}: неизвестная поза пешехода", {"type":"actor","id":a['id']})
        if a.get("type") == "motorcycle" and "sidecar" in a and not isinstance(a["sidecar"], bool):
            finding(out, "error", "actor-appearance", f"{a['id']}: выберите мотоцикл с коляской или без неё", {"type":"actor","id":a['id']})
        tram_points = routes.get(a.get("route"), {}).get("points", [])
        missing_tram_path = a.get("type") == "tram" and (len(tram_points) < 2 or LineString(tram_points).length < 0.01)
        if (not a.get("route") or missing_tram_path) and not (a.get("behaviour") or {}).get("staysPut"):
            finding(out, "warn", "actor-no-route", f"{a['id']}: никуда не едет (нет пути) и не припаркован",
                    {"type": "actor", "id": a["id"]})
        elif a.get("type") in DRIVEN_TYPES and not area.buffer(0.5).covers(Point(a["pos"])):
            finding(out, "warn", "actor-off-road", f"{a['id']}: машина стоит вне дороги",
                    {"type": "actor", "id": a["id"]})
    for d in scene.get("decor", []):
        if area.buffer(0.5).covers(Point(d["pos"])):
            finding(out, "warn", "prop-on-road", f"{d['prop']} стоит на проезжей части", {"type": "prop", "id": d.get("id")})

    check_layers(scene, area, out)

    status = (scene.get("compliance") or {}).get("status")
    if status not in ("unverified", "ok", "fixed") and not mini_regulator:
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
