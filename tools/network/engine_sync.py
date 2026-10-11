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
            if engine_base(sid).get("lights"):
                return f"{sid}/light_0.glb"
    return best


def base_actor(asset: str) -> dict:
    sid, fname = asset.split("/")
    k = int(fname[len("actor_"):-len(".glb")])
    return copy.deepcopy(engine_base(sid)["actors"][k])


def length_of(points: list) -> float:
    return round(sum(math.dist(a, b) for a, b in zip(points, points[1:])), 3)


def sync(sid: str) -> dict:
    net = check.load(sid)
    base = engine_base(sid)
    out = copy.deepcopy(base)
    routes = {r["id"]: r for r in net.get("routes", [])}

    stop = net["stop"]
    out["stopZ"] = stop["z"]
    # The export leaves playerStartX null on the default lane: keep it that way.
    if not (base.get("playerStartX") is None and abs(stop["x"] + 1.8) < 1e-6):
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
        traj.append({"label": r["label"], "points": r["points"]})
        lp = r.get("labelPosition")
        if lp:
            labels.append({"letter": r["label"], "pos": [lp[0], 0.8, lp[1]]})
        elif r["label"] in base_labels:
            labels.append(base_labels[r["label"]])
    out["trajectories"] = traj
    out["labels"] = labels

    out["lights"] = [{"pos": [l["pos"][0], 0.0, l["pos"][1]], "yaw": l["yaw"], "scale": l["scale"], "arrow": l.get("arrow")}
                     for l in net.get("lights", [])]
    if net.get("lights") and net["lights"][0].get("state") is not None:
        out["trafficLights"] = {"state": net["lights"][0]["state"], "arrow": net["lights"][0].get("arrow")}

    actors = []
    for na in net.get("actors", []):
        asset = na.get("asset") or find_template("actor", na["type"], na.get("name", ""))
        if asset is None:
            raise ValueError(f"{sid}: no model for participant {na['id']} ({na['type']})")
        a = base_actor(asset)
        a.update({"id": na["id"], "type": na["type"], "name": na.get("name", a.get("name", ""))})
        pos = [na["pos"][0], 0.0, na["pos"][1]]
        a["pos"] = pos
        a["yaw"] = na["yaw"]
        a["scale"] = na["scale"]
        rt = routes.get(na.get("route"))
        if rt:
            a["path"] = [[x, 0.0, z] for x, z in rt["points"]]
            a["length"] = length_of(rt["points"])
            route_2d = rt["points"]
        else:
            a["path"] = [pos, pos]
            a["length"] = 0.0
            route_2d = [na["pos"], na["pos"]]
        for k in ("maxSpeed", "clearDistance", "halfLength", "halfWidth"):
            if na.get(k) is not None:
                a[k] = na[k]
        for k in ("stopAtDistance", "stopFor", "holdFor", "staysPut", "signalPlan", "waitsForPlayer"):
            if k in (na.get("behaviour") or {}):
                a[k] = na["behaviour"][k]
        cfg = a.get("config") or {}
        cfg.update({"id": na["id"], "type": na["type"], "name": a["name"], "position": pos,
                    "rotationY": na["yaw"], "route": route_2d})
        a["config"] = cfg
        actors.append((asset, a))
    out["actors"] = [a for _, a in actors]

    out["props"] = [{"prop": p["prop"], "pos": [p["pos"][0], 0.0, p["pos"][1]], "yaw": p["yaw"],
                     "scale": p["scale"], "tint": p.get("tint")} for p in net.get("decor", [])]

    q = net.get("question") or {}
    out["correctAnswerIndex"] = q.get("correct")
    for k in ("speedLimit", "requiredStop", "redWait"):
        if k in q:
            out[k] = q[k]
    out["spec"] = {**(out.get("spec") or {}), "maneuver": q.get("maneuver"), "yieldTo": q.get("yieldTo", [])}
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
        asset = l.get("asset") or find_template("light", "", "")
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
    """The game plays a scene that is reviewed and has no traffic controller (regulator)."""
    net = check.load(sid)
    return bool(net.get("reviewed", True)) and not net.get("regulator", False)


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
