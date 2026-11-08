#!/usr/bin/env python3
"""Question deletion, exact duplicate scope, archives and rollback in temp copies."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from question_pool import QuestionPool
import scene_delete


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def snapshot(root):
    return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}


def question(key, title, image=None):
    return {"id": key, "question": title, "image": image,
            "answers": [{"text": "Да", "correct": True}, {"text": "Нет", "correct": False}]}


def fixture(root):
    questions, network, situations = root / "questions", root / "game/network", root / "game/situations"
    network.mkdir(parents=True)
    situations.mkdir(parents=True)
    write(questions / "questions_ab.json", {"tickets": [
        {"number": 1, "questions": [question("same", "Исходный вопрос", "a"),
                                     question("same", "Исходный вопрос", "b"),
                                     question("planned", "Ещё не построено"),
                                     question("road", "Дорожный вопрос")]},
        {"number": 2, "questions": [question("duplicate", "Исходный вопрос", "a")]}]})
    write(questions / "questions_cd.json", {"immutable": True})
    write(root / "images/a.webp", {"immutable": "source image"})
    for sid, extra in (("ticket_1_1", {"reviewed": True, "roads": [{"outer": [[0, 0], [9, 0], [0, 9]]}]}),
                       ("ticket_2_1", {"reviewed": False, "layout": {"nodes": [], "streets": []},
                                       "assistantReview": {"author": "codex", "status": "pending"}}),
                       ("ticket_1_2", {"reviewed": True})):
        write(network / f"{sid}.json", {"id": sid, **extra})
        write(network / "build" / f"{sid}.json", {"id": sid, "surfaces": [1, 2, 3]})
        (network / "preview").mkdir(exist_ok=True)
        (network / "preview" / f"{sid}.png").write_bytes(b"preview")
        write(situations / sid / "engine.json", {"id": sid, "actors": []})
        write(situations / sid / "scene.json", {"id": sid})
        (situations / sid / "parts").mkdir()
        (situations / sid / "parts/actor_0.glb").write_bytes(b"pristine model")
        (situations / sid / "actor_0.glb").write_bytes(b"rendered model")
    write(situations / "index.json", ["ticket_1_1", "ticket_1_2", "ticket_2_1"])
    write(network.parent / "roads/road_scenes.json", {"schema": 1, "count": 6, "extra": "keep", "scenes": [
        {"id": "road_1_1", "category": "ab"},
        {"id": "road_2_1", "category": "ab"},
        {"id": "legacy", "sourceQuestionId": "same", "sourceImage": "a"},
        {"id": "legacy-other-picture", "sourceQuestionId": "same", "sourceImage": "b"},
        {"id": "road_1_1", "category": "cd"},
        {"id": "road_1_4", "category": "ab"}]})
    pool = QuestionPool(questions, network, root / "images")
    write(pool.decisions_path, {"schema": 1, "decisions": {"ticket_1_1": "yes", "ticket_1_2": "yes"}, "extra": "keep"})
    return pool, situations, network / "history"


def remove(sid, pool, situations, history):
    info = scene_delete.describe(sid, pool, situations, history)
    return scene_delete.delete(sid, info["revision"], pool, situations, history)


scratch = HERE.parents[2] / "scratch"
scratch.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="scene-delete-check-", dir=scratch) as tmp:
    base = Path(tmp)
    pool, situations, history = fixture(base / "complete")
    before = snapshot(base / "complete")
    info = scene_delete.describe("ticket_2_1", pool, situations, history)
    assert snapshot(base / "complete") == before, "Describing must never create history or edit sources"
    assert info["id"] == "ticket_1_1" and info["ids"] == ["ticket_1_1", "ticket_2_1"]
    assert info["hasScene"] and info["hasRoadQuestion"] and not info["hasSharedAssets"]
    assert all(copy["hasScene"] for copy in info["copies"])
    assert set(info["roadIds"]) == {"road_1_1", "road_2_1", "legacy"}
    result = scene_delete.delete("ticket_2_1", info["revision"], pool, situations, history)
    archive = Path(result["archive"])
    for sid in result["ids"]:
        assert scene_delete.is_deleted(sid, history)
        assert not (pool.network / f"{sid}.json").exists()
        assert not (pool.network / "build" / f"{sid}.json").exists()
        assert not (pool.network / "preview" / f"{sid}.png").exists()
        assert not (situations / sid).exists()
        assert (archive / "network" / f"{sid}.json").read_bytes() == before[f"game/network/{sid}.json"]
        assert (archive / "situations" / sid / "parts/actor_0.glb").read_bytes() == b"pristine model"
        try:
            scene_delete.describe(sid, pool, situations, history)
            raise AssertionError("Deleted questions must not be reopened as plan templates")
        except scene_delete.SceneDeleteNotFound:
            pass
    assert json.loads((situations / "index.json").read_text()) == ["ticket_1_2"]
    roads = json.loads((pool.network.parent / "roads/road_scenes.json").read_text())
    assert roads["count"] == 3 and roads["extra"] == "keep"
    assert [road["id"] for road in roads["scenes"]] == ["legacy-other-picture", "road_1_1", "road_1_4"]
    assert pool.get("ticket_1_1")["decision"] == "no"
    assert pool.get("ticket_1_2")["decision"] == "yes"
    for name, content in before.items():
        if name.startswith(("questions/", "images/", "game/network/ticket_1_2", "game/situations/ticket_1_2/")):
            assert (base / "complete" / name).read_bytes() == content, name
    # No source/build/situation was ever materialized for a planned question.
    assert not scene_delete.describe("ticket_1_3", pool, situations, history)["hasScene"]
    remove("ticket_1_3", pool, situations, history)
    assert scene_delete.is_deleted("ticket_1_3", history) and pool.get("ticket_1_3")["decision"] == "no"
    remove("ticket_1_4", pool, situations, history)
    assert not any(road["id"] == "road_1_4" for road in json.loads((pool.network.parent / "roads/road_scenes.json").read_text())["scenes"])
    assert scene_delete.is_deleted("ticket_1_1", history), "Later deletions must retain earlier tombstones"

    # Shared source GLBs and engine metadata remain usable by another scene.
    pool, situations, history = fixture(base / "shared")
    other = json.loads((pool.network / "ticket_1_2.json").read_text())
    other["actors"] = [{"asset": "ticket_1_1/actor_0.glb"}]
    write(pool.network / "ticket_1_2.json", other)
    write(situations / "ticket_1_2/engine.json", {"resource": "res://situations/ticket_2_1/light_0.glb"})
    other_bytes = (pool.network / "ticket_1_2.json").read_bytes()
    info = scene_delete.describe("ticket_1_1", pool, situations, history)
    assert info["hasSharedAssets"] and info["sharedAssetIds"] == ["ticket_1_1", "ticket_2_1"]
    shared_before = {sid: snapshot(situations / sid) for sid in info["ids"]}
    result = remove("ticket_1_1", pool, situations, history)
    for sid in info["ids"]:
        assert not (situations / sid / "scene.json").exists()
        assert (situations / sid / "engine.json").read_bytes() == (Path(result["archive"]) / "situations" / sid / "engine.json").read_bytes()
        assert (situations / sid / "parts/actor_0.glb").read_bytes() == b"pristine model"
        assert snapshot(situations / sid) == {name: data for name, data in shared_before[sid].items() if name != "scene.json"}
    assert (pool.network / "ticket_1_2.json").read_bytes() == other_bytes

    # Exact source, compiled files, model resources and new references all invalidate
    # the confirmation. Nothing except the intentional intervening edit changes.
    for name in ("source", "build", "preview", "engine", "part", "reference", "decisions", "index", "roads", "missing-revision"):
        pool, situations, history = fixture(base / ("conflict-" + name))
        info = scene_delete.describe("ticket_1_1", pool, situations, history)
        edits = {
            "source": pool.network / "ticket_1_1.json", "build": pool.network / "build/ticket_2_1.json",
            "preview": pool.network / "preview/ticket_1_1.png", "engine": situations / "ticket_2_1/engine.json",
            "part": situations / "ticket_1_1/parts/actor_0.glb", "reference": pool.network / "ticket_1_2.json",
            "decisions": pool.decisions_path, "index": situations / "index.json",
            "roads": pool.network.parent / "roads/road_scenes.json"}
        if name in ("preview", "part"):
            edits[name].write_bytes(b"changed binary")
        elif name == "reference":
            write(edits[name], {"id": "ticket_1_2", "actors": [{"asset": "ticket_1_1/actor_0.glb"}]})
        elif name in edits:
            edits[name].write_text(edits[name].read_text() + "\n")
        before = snapshot(base / ("conflict-" + name))
        try:
            scene_delete.delete("ticket_1_1", "" if name == "missing-revision" else info["revision"], pool, situations, history)
            raise AssertionError(f"Changed {name} must reject stale confirmation")
        except scene_delete.SceneDeleteConflict:
            pass
        assert snapshot(base / ("conflict-" + name)) == before, name

    # Fail once at each mutation stage; rollback must restore byte-for-byte originals,
    # remove newly created decisions/tombstones and leave no misleading archive.
    for fail_at in ("archive", "source", "directory", "index", "roads", "decisions", "tombstones"):
        root = base / ("rollback-" + fail_at)
        pool, situations, history = fixture(root)
        if fail_at == "tombstones":
            pool.decisions_path.unlink()
        info = scene_delete.describe("ticket_1_1", pool, situations, history)
        before = snapshot(root)
        failed = [False]
        original_remove, original_write, original_copy = scene_delete._remove, scene_delete._atomic_json, scene_delete._copy

        def fail_once(stage):
            if not failed[0] and stage == fail_at:
                failed[0] = True
                raise OSError("Injected failure at " + stage)

        def removing(path):
            fail_once("source" if path == pool.network / "ticket_2_1.json" else
                      "directory" if path == situations / "ticket_1_1" else "")
            return original_remove(path)

        def writing(path, value):
            stages = {situations / "index.json": "index", pool.network.parent / "roads/road_scenes.json": "roads",
                      pool.decisions_path: "decisions", pool.network / "question_review/deleted.json": "tombstones"}
            fail_once(stages.get(path))
            return original_write(path, value)

        def copying(source, target):
            fail_once("archive")
            return original_copy(source, target)

        with patch.object(scene_delete, "_remove", removing), patch.object(scene_delete, "_atomic_json", writing), patch.object(scene_delete, "_copy", copying):
            try:
                scene_delete.delete("ticket_1_1", info["revision"], pool, situations, history)
                raise AssertionError("Injected failure must escape")
            except OSError:
                pass
        assert failed[0], fail_at
        assert snapshot(root) == before, fail_at
        assert not scene_delete.is_deleted("ticket_1_1", history)
        assert not list((history / "deleted").glob("*"))

    pool, situations, history = fixture(base / "standalone")
    write(pool.network / "ticket_99_1.json", {"id": "ticket_99_1"})
    remove("ticket_99_1", pool, situations, history)
    assert scene_delete.is_deleted("ticket_99_1", history)
    # A fresh checkout has tracked tombstones without the author's local history.
    import shutil
    shutil.rmtree(history)
    assert scene_delete.is_deleted("ticket_99_1", history)
    for invalid in ("../ticket_1_1", "ticket_99_99", "", "../../outside", "mini_regulator", "custom_scene", "ticket_cd_1_1"):
        try:
            scene_delete.describe(invalid, pool, situations, history)
            raise AssertionError("Unknown/path-traversal IDs must fail")
        except scene_delete.SceneDeleteNotFound:
            pass

print("scene_delete_check: grouped native/graph/assistant/planned/road deletion, shared models, archives, 10 conflicts and 7 rollback stages passed")
