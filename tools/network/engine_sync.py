#!/usr/bin/env python3
"""Road network -> the scene file the Godot game reads (game_godot/situations/<id>/scene.json).

    tools/network/.venv/bin/python tools/network/engine_sync.py [id ...]   # all scenes by default
    tools/network/engine_sync.py --init [id ...]                           # once after an export

The network JSON (game_godot/network/<id>.json) is what people edit: roads, routes,
stop line, lights, participants, roadside props, the question's answer and rules.
The game still reads its scene.json, so this writes the same file from the network:
the geometry and the question fields are taken from the network, everything the
network does not describe (texts, camera, badges, signal plans, ...) is kept from
the engine base situations/<id>/engine.json, a copy of the export made by --init.

Participants and lights point at their model: asset "<scene>/actor_<k>.glb" names a
pristine part in situations/<scene>/parts/. A participant added in the editor takes
the first model of its type, so one of the exported ones.
Points are [x, z] in the network and [x, 0, z] (or [x, y, z]) in the engine file.
"""
from __future__ import annotations

import copy
import json
import math
import shutil
import sys
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check  # noqa: E402
import build  # noqa: E402
from surface_support import SurfaceSupport  # noqa: E402

ROOT = check.ROOT
SIT = ROOT / "game_godot" / "situations"
NET = check.NET


def scene_dir(sid: str) -> Path:
    return SIT / sid


@lru_cache(maxsize=None)
def engine_base(sid: str) -> dict:
    return json.loads((scene_dir(sid) / "engine.json").read_text(encoding="utf-8"))


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def init_scene(sid: str) -> None:
    """Keeps the export as it came out: the engine base and pristine GLB parts."""
    d = scene_dir(sid)
    if not (d / "engine.json").exists():
        shutil.copy(d / "scene.json", d / "engine.json")
    parts = d / "parts"
    parts.mkdir(exist_ok=True)
    for f in list(d.glob("actor_*.glb")) + list(d.glob("light_*.glb")):
        if not (parts / f.name).exists():
            shutil.copy(f, parts / f.name)


def find_template(kind: str, typ: str, name: str = "") -> str | None:
    """'<scene>/actor_<k>.glb' of the first exported participant of this type (name first)."""
    best = None
    for p in sorted(SIT.glob("*/engine.json")):
        sid = p.parent.name
        if kind == "actor":
            for k, a in enumerate(engine_base(sid).get("actors", [])):
                if a.get("type") == typ:
                    if name and a.get("name") == name:
                        return f"{sid}/actor_{k}.glb"
                    best = best or f"{sid}/actor_{k}.glb"
        else:
            lights = engine_base(sid).get("lights", [])
            for k, l in enumerate(lights):
                arr = l.get("arrow") or ""
                is_tram = bool(l.get("tram"))
                target_tram = (typ == "tram")
                if target_tram and is_tram:
                    return f"{sid}/light_{k}.glb"
                if not target_tram and not is_tram and arr == (typ or ""):
                    return f"{sid}/light_{k}.glb"
                if best is None and not arr and not is_tram and not target_tram:
                    best = f"{sid}/light_{k}.glb"
    if typ == "tram" and (SIT / "ticket_6_13" / "parts" / "light_0.glb").exists():
        return "ticket_6_13/light_0.glb"
    return best


def base_actor(asset: str) -> dict:
    sid, fname = asset.split("/")
    k = int(fname[len("actor_"):-len(".glb")])
    actors = engine_base(sid)["actors"]
    if k >= len(actors):
        raise ValueError(f"{asset}: the export of {sid} has {len(actors)} participants now")
    return copy.deepcopy(actors[k])


def length_of(points: list) -> float:
    return round(sum(math.dist(a, b) for a, b in zip(points, points[1:])), 3)


def sync(sid: str) -> dict:
    if sid == "mini_regulator":
        return {"miniGame": "regulator", "source": "network/mini_regulator.json"}
    net = check.load(sid)
    base = engine_base(sid)
    out = copy.deepcopy(base)
    routes = {r["id"]: r for r in net.get("routes", [])}
    support = SurfaceSupport(build.build(net))

    player = (net.get("layout") or {}).get("player") or {}
    free_pose = player.get("pose") if player.get("mode") == "free" else None
    stop = free_pose if isinstance(free_pose, dict) else net["stop"]
    out["playerPlacement"] = "free" if free_pose else "street"
    out["stopZ"] = stop["z"]
    # The export leaves playerStartX null on the default lane: keep it that way.
    if free_pose or not (base.get("playerStartX") is None and abs(stop["x"] + 1.8) < 1e-6):
        out["playerStartX"] = stop["x"]
    else:
        out["playerStartX"] = None
    out["playerStartRotY"] = stop.get("yaw", 0.0)

    exits = {}
    for r in net.get("routes", []):
        if r["kind"] == "manoeuvre":
            exits[r["exit"]] = {"points": r["points"], "exitYaw": r.get("exitYaw", 0.0)}
    out["exits"] = exits or base.get("exits", {})

    traj, labels = [], []
    base_labels = {l["letter"]: l for l in base.get("labels", [])}
    for r in net.get("routes", []):
        if r["kind"] != "choice":
            continue
        # Keep a label-only entry so the runtime does not invent a fallback player arrow.
        # Remembered editor points are exported again only when its line is restored.
        traj.append({"label": r["label"], "points": [] if r.get("display") == "letter" else r["points"],
                     "arrowhead": r.get("arrowhead", True) is not False})
        lp = r.get("labelPosition")
        if lp:
            labels.append({"letter": r["label"], "pos": [lp[0], 0.8, lp[1]]})
        elif r["label"] in base_labels:
            labels.append(base_labels[r["label"]])
    out["trajectories"] = traj
    out["labels"] = labels
    # Overlays have no answer labels and must not suppress the fallback player guide.
    out["annotations"] = [{"points": r["points"], "style": r.get("style", "line"),
                           "colour": r.get("colour", "#20242b"), "width": r.get("width", .16), "text": str(r.get("text", ""))[:120]}
                          for r in net.get("routes", []) if r["kind"] == "annotation"]

    out["lights"] = [{"pos": [l["pos"][0], 0.0, l["pos"][1]], "yaw": l["yaw"], "scale": l["scale"],
                      "arrow": l.get("arrow"), "tram": l.get("tram"), "mountedSigns": l.get("mountedSigns", []), "mountedMainRoad": l.get("mountedMainRoad", [])}
                     for l in net.get("lights", [])]
    if not net.get("lights"):
        out["trafficLights"] = None
    if net.get("lights") and net["lights"][0].get("state") is not None:
        out["trafficLights"] = {"state": net["lights"][0]["state"], "arrow": net["lights"][0].get("arrow"),
                                "tram": net["lights"][0].get("tram")}

    actors = []
    for na in net.get("actors", []):
        asset = na.get("asset")
        if asset:
            src, fname = asset.split("/")
            k = int(fname[len("actor_"):-len(".glb")])
            if not (SIT / src / "parts" / fname).exists() or k >= len(engine_base(src)["actors"]):
                # The scene it came from was exported again and no longer has this participant:
                # the first model of its type stands in for it.
                asset = find_template("actor", na["type"], na.get("name", ""))
        else:
            asset = find_template("actor", na["type"], na.get("name", ""))
        if asset is None:
            raise ValueError(f"{sid}: no model for participant {na['id']} ({na['type']})")
        a = base_actor(asset)
        base_scale = a.get("scale", [1.0, 1.0, 1.0])
        base_half_length = float(a.get("halfLength", 0.0))
        a.update({"id": na["id"], "type": na["type"], "name": na.get("name", a.get("name", ""))})
        # Keep the optional editor paint separate from the template's original
        # colours so clearing the swatch restores the model's default colour.
        a["paint"] = na.get("paint")
        # The editor's chosen direction overrides archived signal sides at runtime.
        a["way"] = na.get("way")
        a["driverSignal"] = na.get("driverSignal", "none")
        if na["type"] == "pedestrian":
            a["pedestrianPose"] = na.get("pedestrianPose", "stand")
            a["poseArm"] = na.get("poseArm", "right")
            if "pedestrianLook" in na:
                a["pedestrianLook"] = na["pedestrianLook"]
        if na["type"] == "motorcycle" and isinstance(na.get("sidecar"), bool):
            a.setdefault("config", {})["sidecar"] = na["sidecar"]
        signal = (na.get("behaviour") or {}).get("turnSignal")
        a["turnSignal"] = signal if signal in ("left", "right", "off") else "auto"
        pos = [na["pos"][0], support.height(*na["pos"]), na["pos"][1]]
        a["pos"] = pos
        a["yaw"] = na["yaw"]
        a["scale"] = na["scale"]
        # Template dimensions already include its archived scale. A new actor
        # can use the same mesh at a different size; keep its inherited body
        # envelope proportional without multiplying the archived scale twice.
        for dimension, axis in (("halfWidth", 0), ("halfLength", 2)):
            if dimension in a:
                ratio = abs(float(na["scale"][axis])) / max(abs(float(base_scale[axis])), 1e-6)
                a[dimension] = float(a[dimension]) * ratio
        rt = routes.get(na.get("route"))
        if rt:
            a["path"] = [[x, support.height(x, z), z] for x, z in rt["points"]]
            a["length"] = length_of(rt["points"])
            route_2d = rt["points"]
        else:
            a["path"] = [pos, pos]
            a["length"] = 0.0
            route_2d = [na["pos"], na["pos"]]
        for k in ("maxSpeed", "halfLength", "halfWidth"):
            if na.get(k) is not None:
                a[k] = na[k]
        if na["type"] == "motorcycle" and isinstance(na.get("sidecar"), bool):
            a["halfWidth"] = (.957 if na["sidecar"] else .34) * abs(float(na["scale"][0]))
            a["halfLength"] = 1.075 * abs(float(na["scale"][2]))
        if na.get("clearDistance") is not None:
            a["clearDistance"] = na["clearDistance"]
        elif a.get("clearDistance") is not None:
            # The inherited release distance includes the old tram's rear.
            # Enlarging that rear must not release traffic while it remains in
            # the crossing; an explicitly authored distance keeps precedence.
            a["clearDistance"] = float(a["clearDistance"]) + max(0.0, float(a.get("halfLength", 0.0)) - base_half_length)
        for k in ("stopAtDistance", "stopFor", "holdFor", "staysPut", "signalPlan", "waitsForPlayer"):
            if k in (na.get("behaviour") or {}):
                a[k] = na["behaviour"][k]
        cfg = a.get("config") or {}
        behaviour = na.get("behaviour") or {}
        # Explicit editor settings override the archived actor template, even off.
        a["hazards"] = behaviour.get("hazards", (behaviour.get("config") or {}).get("hazard", False)) is True
        cfg.update({"id": na["id"], "type": na["type"], "name": a["name"], "position": pos,
                    "rotationY": na["yaw"], "route": route_2d, "hazard": a["hazards"]})
        a["config"] = cfg
        actors.append((asset, a))
    out["actors"] = [a for _, a in actors]

    out["props"] = [{"prop": p["prop"], "pos": [p["pos"][0], 0.0, p["pos"][1]], "yaw": p["yaw"],
                     "scale": p["scale"], "tint": p.get("tint")} for p in net.get("decor", [])]

    q = net.get("question") or {}
    out["correctAnswerIndex"] = q.get("correct")
    # Only an explicit editor false hides the visual hint. Always overwrite
    # the archived value so clearing the option restores its default.
    out["showPlayerGuide"] = q.get("showPlayerGuide") is not False
    guide = next((r for r in net.get("routes", []) if r["kind"] == "guide"), None)
    if guide and len(guide.get("points", [])) >= 2:
        out["playerGuidePoints"] = guide["points"]
    else:
        out.pop("playerGuidePoints", None)
    for k in ("speedLimit", "requiredStop", "redWait"):
        if k in q:
            out[k] = q[k]
    # This signal closes after an answer; an archived red-wait timer must never reopen it.
    if (out.get("trafficLights") or {}).get("state") == "flashing_green":
        out["redWait"] = None
    out["spec"] = {**(out.get("spec") or {}), "maneuver": q.get("maneuver"), "yieldTo": q.get("yieldTo", [])}
    if net.get("questionView"):
        out["questionView"] = net["questionView"]     # the question's camera, framed in the editor
    else:
        out.pop("questionView", None)
    out["officers"] = net.get("officers", [])        # traffic controllers (editor: «Регулировщик»)
    out["approachW"] = net.get("approachWidth", out.get("approachW"))
    out["exitWidths"] = net.get("exitWidths", out.get("exitWidths"))

    d = scene_dir(sid)
    write_json(d / "scene.json", out)
    for old in d.glob("actor_*.glb"):
        old.unlink()
    for i, (asset, _) in enumerate(actors):
        src_scene, fname = asset.split("/")
        shutil.copy(SIT / src_scene / "parts" / fname, d / f"actor_{i}.glb")
    for old in d.glob("light_*.glb"):
        old.unlink()
    for i, l in enumerate(net.get("lights", [])):
        arrow = l.get("arrow") or ""
        is_tram = bool(l.get("tram"))
        typ = "tram" if is_tram else arrow
        asset = l.get("asset")
        if asset:
            src_scene, fname = asset.split("/")
            k = int(fname[len("light_"):-len(".glb")]) if fname.startswith("light_") else 0
            base_lights = engine_base(src_scene).get("lights", [])
            base_arrow = (base_lights[k].get("arrow") or "") if k < len(base_lights) else ""
            base_is_tram = bool(base_lights[k].get("tram")) if k < len(base_lights) else False
            if is_tram != base_is_tram or (not is_tram and arrow != base_arrow):
                asset = find_template("light", typ)
        else:
            asset = find_template("light", typ)
        src_scene, fname = asset.split("/")
        shutil.copy(SIT / src_scene / "parts" / fname, d / f"light_{i}.glb")
    return {"actors": len(actors), "lights": len(out["lights"]), "props": len(out["props"]),
            "exits": sorted(exits), "trajectories": len(traj)}


def backfill(sid: str) -> bool:
    """Once: points of the network become [x, z] everywhere, participants and lights name their model,
    choice routes get the position of their letter from the export. Idempotent."""
    net = check.load(sid)
    base = engine_base(sid)
    changed = False
    base_ids = [a["id"] for a in base.get("actors", [])]
    for na in net.get("actors", []):
        if len(na["pos"]) == 3:
            na["pos"] = [na["pos"][0], na["pos"][2]]
            changed = True
        if not na.get("asset") and na["id"] in base_ids:
            na["asset"] = f"{sid}/actor_{base_ids.index(na['id'])}.glb"
            changed = True
    for i, l in enumerate(net.get("lights", [])):
        if not l.get("asset") and base.get("lights"):
            l["asset"] = f"{sid}/light_{i}.glb"
            changed = True
    for i, d in enumerate(net.get("decor", [])):
        if not d.get("id"):
            d["id"] = f"decor_{i}"
            changed = True
    letters = {l["letter"]: l["pos"] for l in base.get("labels", [])}
    for r in net.get("routes", []):
        if r["kind"] == "choice" and not r.get("labelPosition") and r.get("label") in letters:
            r["labelPosition"] = [letters[r["label"]][0], letters[r["label"]][2]]
            changed = True
    if changed:
        write_json(NET / f"{sid}.json", net)
    return changed


def playable(sid: str) -> bool:
    """The game plays a city scene that has been reviewed."""
    if sid == "mini_regulator":
        return False  # Dedicated mini-game; never a junction in the city ride.
    net = check.load(sid)
    return net.get("reviewed") is True


def write_index() -> list:
    """situations/index.json: the scenes the game draws its exam questions from."""
    ids = [p.stem for p in sorted(NET.glob("*.json")) if playable(p.stem)]
    write_json(SIT / "index.json", ids)
    return ids


def main(argv: list) -> int:
    mode = "sync"
    if "--init" in argv:
        mode = "init"
    if "--backfill" in argv:
        mode = "backfill"
    ids = [a for a in argv if not a.startswith("--")] or sorted(p.stem for p in NET.glob("*.json"))
    for sid in ids:
        if sid == "mini_regulator" and mode != "sync":
            continue  # Mini-game source has no legacy engine.json to initialise/backfill.
        if mode == "init":
            init_scene(sid)
            engine_base.cache_clear()
        elif mode == "backfill":
            print(sid, "changed" if backfill(sid) else "ok")
        else:
            print(sid, sync(sid))
    if mode == "sync" and not [a for a in argv if not a.startswith("--")]:
        print("game index:", len(write_index()), "scenes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
