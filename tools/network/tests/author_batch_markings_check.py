#!/usr/bin/env python3
"""Six pending drafts: source fidelity, exact markings, editor save roundtrip.

All writes, HTTP saves and deliberate manual edits live under scratch/.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from unittest.mock import patch
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import author_batch_markings as author
import build
import check
import engine_sync
import question_pool
import server


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


protected = [author.ROOT / "game_godot/situations/index.json", question_pool.QuestionPool().decisions_path]
protected += [p for p in check.NET.glob("ticket_*.json") if p.stem not in author.IDS]
before = {p: sha(p) for p in protected}
scenes = {sid: read(check.NET / f"{sid}.json") for sid in author.IDS}
pool = author.AuthorSources()
for sid, scene in scenes.items():
    source = pool.source(sid)
    fresh = pool.template(sid)
    assert scene["question"]["text"] == fresh["question"]["text"], sid
    assert scene["question"]["correct"] == fresh["question"]["correct"], sid
    assert scene["question"]["sourceImage"] == source["image"]
    assert scene["questionPool"] == fresh["questionPool"]
    assert scene["assistantReview"] == author.PROVENANCE
    assert scene["reviewed"] is False and scene["procedural"] is True
    assert scene["actors"] == [] and scene["officers"] == [] and scene["tracks"] == []
    assert not [f for f in check.check_scene(scene) if f["level"] == "error"], sid
    assert scene["decor"] and all(d.get("id") and d.get("prop") for d in scene["decor"])
    assert all(d.get("tint") == author.FOLIAGE_TINTS[d["prop"]]
               for d in scene["decor"] if d["prop"] in author.FOLIAGE_TINTS), "White neutral foliage needs its catalogue tint"
    exported = read(engine_sync.SIT / sid / "scene.json")
    assert exported["procedural"] is True and exported["reviewed"] is False
    assert exported["assistantReview"] == author.PROVENANCE
    assert exported["text"] == scene["question"]["text"]
    assert exported["correctAnswerIndex"] == scene["question"]["correct"]
    assert not (engine_sync.SIT / sid / "scene.glb").exists()

for sid in ("ticket_23_5", "ticket_38_5"):
    scene = scenes[sid]
    marks = scene["markings"]
    assert len(marks) == 40
    assert all(m["type"] == "solid" and m["colour"] == "yellow" and m["width"] == .15 for m in marks)
    assert all(math.isclose(math.dist(*m["points"]), 1.0) for m in marks)
    assert all(math.isclose(math.dist(a["points"][1], b["points"][0]), 1.0) for a, b in zip(marks, marks[1:]))
    assert all(m["points"][0][0] == -4.0 for m in marks), "Yellow line is on the right-hand curb"
    assert scene["question"]["maneuver"] == "straight", "Forbidden parking is never driven after 23/5"
    evidence = next(r for r in scene["routes"] if r["kind"] == "choice")
    assert evidence["label"] == "" and evidence["points"][-1] == [-3.05, -.5]
    assert next(r for r in scene["routes"] if r.get("exit") == "straight")["points"] != evidence["points"]

marks = scenes["ticket_25_5"]["markings"]
assert all(m["colour"] == "white" and math.isclose(math.dist(*m["points"]), 3.0) for m in marks)
assert all(math.isclose(math.dist(a["points"][1], b["points"][0]), 9.0) for a, b in zip(marks, marks[1:]))
assert all(st["walk"] is False and st["centre"] == "none" for st in scenes["ticket_25_5"]["layout"]["streets"])

right = scenes["ticket_25_7"]
assert right["question"]["maneuver"] == "right" and right["signs"][0]["code"] == "4.1.2"
one_way = scenes["ticket_32_4"]
assert one_way["signs"][0]["code"] == "5.7.2"
assert one_way["question"]["maneuver"] == "straight"
choices = {r["label"]: r for r in one_way["routes"] if r["kind"] == "choice"}
assert set(choices) == {"А", "Б", "В"}
assert choices["А"]["points"][-1][1] > 0 and choices["Б"]["points"][-1][0] > 0
assert choices["Б"]["labelPosition"] == [9, 3.2], "Б remains comfortably within the phone's horizontal frame"
assert choices["В"]["points"][-1][0] > 0 and choices["В"]["points"][-1][1] < 0
flashing = scenes["ticket_24_6"]
assert len(flashing["lights"]) == 4 and all(l["state"] == "flashing_yellow" for l in flashing["lights"])
assert flashing["questionView"]["height"] == 25 and math.isclose(flashing["questionView"]["pitch"], math.radians(25))
assert read(engine_sync.SIT / "ticket_24_6/scene.json")["trafficLights"]["state"] == "flashing_yellow"

scratch = author.ROOT / "scratch/assistant-12-review"
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="markings-roundtrip-", dir=scratch) as temp:
    directory = Path(temp)
    network, situations = directory / "network", directory / "situations"
    network.mkdir()
    situations.mkdir()
    # The ordinary exporter borrows existing models. Read-only symlinks provide
    # its model catalogue; only the six new target directories are writable.
    for p in engine_sync.SIT.iterdir():
        if p.is_dir() and p.name not in author.IDS:
            (situations / p.name).symlink_to(p, target_is_directory=True)
    author.write_batch(network, situations)
    preserved = {sid: sha(network / f"{sid}.json") for sid in author.IDS}
    try:
        author.write_batch(network, situations)
        raise AssertionError("Authoring must not silently overwrite a saved draft")
    except FileExistsError:
        pass
    assert preserved == {sid: sha(network / f"{sid}.json") for sid in author.IDS}

    local_pool = question_pool.QuestionPool(network=network)
    overrides = [(server, "NET", network), (server, "SIT", situations),
                 (server, "HISTORY", network / "history"), (server, "PREVIEW", network / "preview"),
                 (server, "QUESTION_POOL", local_pool), (check, "NET", network),
                 (engine_sync, "NET", network), (engine_sync, "SIT", situations),
                 (build, "NET", network), (build, "BUILD", network / "build")]
    patches = [patch.object(module, name, value) for module, name, value in overrides]
    for item in patches:
        item.start()
    engine_sync.engine_base.cache_clear()
    http = server.Server(("127.0.0.1", 0), server.Handler)
    worker = threading.Thread(target=http.serve_forever, daemon=True)
    worker.start()

    def request(path, body=None):
        req = Request(f"http://127.0.0.1:{http.server_port}" + path,
                      data=json.dumps(body).encode() if body is not None else None,
                      headers={"Content-Type": "application/json"})
        with urlopen(req, timeout=30) as response:
            return json.loads(response.read())

    try:
        for sid in author.IDS:
            opened = request("/api/scene/" + sid)
            assert opened["playable"] is False and opened["source"]["category"] == "ab"
            edited = opened["scene"]
            edited["decor"][0]["pos"][0] += .25
            if edited["markings"]:
                for point in edited["markings"][0]["points"]:
                    point[1] += .02
            if edited["signs"]:
                edited["signs"][0]["pos"][1] -= .1
            if edited["lights"]:
                edited["lights"][0]["pos"][1] -= .1
            script = "const fs=require('fs'),L=require(process.argv[1]),s=JSON.parse(fs.readFileSync(0,'utf8'));L.apply(s);process.stdout.write(JSON.stringify(s));"
            applied = json.loads(subprocess.run(["node", "-e", script, str(HERE.parent / "editor/layout.js")],
                                 input=json.dumps(edited), check=True, capture_output=True, text=True).stdout)
            for field in ("decor", "signs", "markings", "question", "questionView", "questionPool", "assistantReview"):
                assert applied[field] == edited[field], sid + ": editable data survives road regeneration: " + field
            request("/api/scene/" + sid, applied)
            reopened = request("/api/scene/" + sid)["scene"]
            for field in ("decor", "signs", "markings", "question", "questionView", "questionPool", "assistantReview"):
                assert reopened[field] == applied[field], sid + ": actual editor Save preserves " + field
            assert reopened["reviewed"] is False
            exported = read(situations / sid / "scene.json")
            assert exported["props"][0]["pos"][0] == reopened["decor"][0]["pos"][0]
            assert exported["text"] == reopened["question"]["text"]
            assert not (situations / sid / "scene.glb").exists()
            assert list((network / "history" / sid).glob("*.json"))
    finally:
        http.shutdown()
        http.server_close()
        worker.join(timeout=5)
        for item in reversed(patches):
            item.stop()
        engine_sync.engine_base.cache_clear()

assert before == {p: sha(p) for p in protected}, "Other scenes, decisions and the playable index must remain untouched"
manifest = {"batch": author.BATCH, "ids": list(author.IDS), "gost": author.GOST,
            "marking1_10": {"width": .15, "dash": 1, "gap": 1},
            "marking1_5": {"width": .15, "dash": 3, "gap": 9},
            "scenes": [{"id": sid, "question": scenes[sid]["question"]["text"]["ru"]["title"],
                        "correct": scenes[sid]["question"]["correct"],
                        "answer": scenes[sid]["question"]["text"]["ru"]["options"][scenes[sid]["question"]["correct"]],
                        "sourceImage": scenes[sid]["question"]["sourceImage"],
                        "maneuver": scenes[sid]["question"]["maneuver"]} for sid in author.IDS]}
author.write_json(scratch / "markings-manifest.json", manifest)
print("Six pending marking/sign drafts: official source, exact geometry, guarded generator and HTTP editor roundtrip PASS")
