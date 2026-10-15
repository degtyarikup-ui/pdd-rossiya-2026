#!/usr/bin/env python3
"""A/B-only question coverage, persistent sorting and real editor save/promotion.

All writes and HTTP routes use disposable directories below scratch/. The author's
network scenes, decisions and situation assets are never changed by this check.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import tempfile
import threading
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build
import check
import engine_sync
import question_pool
import server


def write(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def question(sid, title, image=None):
    return {"id": sid, "question": title, "image": image, "comment": "Официальный разбор",
            "answers": [{"text": "Да", "correct": True}, {"text": "Нет", "correct": False}], "topic": ["Тема"]}


scratch = check.ROOT / "scratch"
scratch.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="question-pool-check-", dir=scratch) as temporary:
    root = Path(temporary)
    questions, images = root / "questions", root / "images"
    network, situations = root / "game_godot" / "network", root / "game_godot" / "situations"
    network.mkdir(parents=True)
    situations.mkdir(parents=True)
    # Repeated source IDs alone must never discard different parking pictures.
    ab = [[question("shared", "Общий вопрос без фото"),
           question("built", "Уже реализовано", "a" * 32),
           question("ab-specific", "Можно ли ехать легковому автомобилю?", "b" * 32),
           question("collision", "Где разрешено стоять?", "c" * 32),
           question("linked", "Связанный вопрос", "d" * 32)],
          [question("collision", "Где разрешено стоять?", "e" * 32),
           question("road", "Дорожной вопрос уже реализован"),
           question("linked-copy", "Связанный вопрос", "f" * 32),
           question("exact-copy", "Связанный вопрос", "d" * 32)]]
    cd = copy.deepcopy(ab)
    cd[0][0]["id"] = "shared-cd"   # Different IDs may still denote the same source task.
    cd[0][1]["image"] = "1" * 32  # Same ticket/task, category-specific cabin illustration.
    cd[0][2] = question("cd-specific", "Можно ли ехать грузовому автомобилю?", "2" * 32)
    cd[0][4]["image"] = "f" * 32  # Former C/D links must no longer merge different A/B pictures.
    for category, tickets in (("ab", ab), ("cd", cd)):
        data = {"tickets": [{"number": i, "questions": qs} for i, qs in enumerate(tickets, 1)]}
        write(questions / f"questions_{category}.json", data)
        for language in ("en", "kk"):
            translated = copy.deepcopy(data)
            for ticket in translated["tickets"]:
                for q in ticket["questions"]:
                    q["question"] = f"{language}: " + q["question"]
            write(questions / f"questions_{category}_{language}.json", translated)
        for q in (q for ticket in tickets for q in ticket):
            if q["image"]:
                path = images / f"questions_{category}" / f"{q['image']}.webp"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"fixture {category} {q['image']}".encode())
    write(network / "ticket_1_2.json", {"id": "ticket_1_2", "reviewed": False})
    write(network.parent / "roads" / "road_scenes.json", {"scenes": [{"id": "road_2_2", "category": "ab", "sourceQuestionId": "road"}]})

    pool = question_pool.QuestionPool(questions, network, images)
    result = pool.list()
    records = {q["id"]: q for q in result["questions"]}
    assert set(records) == {"ticket_1_1", "ticket_1_3", "ticket_1_4", "ticket_1_5", "ticket_2_1", "ticket_2_3"}
    assert all(record["category"] == "ab" and record["categories"] == ["ab"] for record in records.values())
    assert all(o["category"] == "ab" for record in records.values() for o in record["occurrences"])
    assert len(records["ticket_1_5"]["occurrences"]) == 2, "Identical A/B task+picture copies still combine"
    assert records["ticket_1_5"]["image"] != records["ticket_2_3"]["image"]
    assert records["ticket_1_4"]["sourceQuestionId"] == records["ticket_2_1"]["sourceQuestionId"]
    assert records["ticket_1_4"]["image"] != records["ticket_2_1"]["image"]
    assert not (network / "question_review").exists(), "Reading a pool must not write files"
    assert len(list(network.glob("*.json"))) == 1
    # Even approved/rejected legacy C/D decisions and saved drafts never reappear.
    write(pool.decisions_path, {"schema": 1, "decisions": {
        "ticket_1_5": "yes", "ticket_cd_1_3": "yes", "ticket_cd_2_1": "no"}})
    write(network / "ticket_cd_1_3.json", {"id": "ticket_cd_1_3", "questionPool": {"category": "cd"}})
    write(network / "ticket_cd_2_1.json", {"id": "ticket_cd_2_1", "reviewed": True})
    assert pool.get("ticket_1_5")["decision"] == "yes", "Existing A/B choices keep their stable keys"
    assert pool.get("ticket_2_3")["decision"] is None, "A different A/B picture must await its own review"
    assert pool.list()["counts"] == {"total": 6, "unreviewed": 5, "yes": 1, "no": 0}
    assert pool.source("ticket_cd_1_3") is None and pool.get("ticket_cd_1_3") is None
    try:
        pool.template("ticket_cd_1_3")
        raise AssertionError("C/D templates are unavailable, even for former approved questions")
    except KeyError:
        pass
    # Neither reading nor cache invalidation should consult the excluded source.
    (questions / "questions_cd.json").write_text("not JSON", encoding="utf-8")
    assert pool.list()["counts"]["total"] == 6
    assert question_pool.QuestionPool(questions, network, images).list()["counts"]["total"] == 6

    scene = pool.template("ticket_1_1")
    assert check.check_scene(scene) == []
    assert all(st["kind"] == "avenue" and st["edge"] is False and st["centre"] == "solid" and st["ends"] == {}
               for st in scene["layout"]["streets"])
    assert all(scene[key] == [] for key in ("actors", "decor", "lights", "officers", "signs", "tracks", "lawns"))
    assert len([m for m in scene["markings"] if m["type"] == "solid"]) == 4
    assert len([m for m in scene["markings"] if m["type"] == "dashed"]) == 8
    assert scene["question"]["showPlayerGuide"] is False
    assert scene["question"]["text"]["en"]["title"].startswith("en: ")
    assert scene["question"]["text"]["kk"]["title"].startswith("kk: ")
    engine = question_pool.engine_template(scene)
    assert engine["sourceTextLength"] > 0, "The first card warmup and answer timer require the source text length"
    scene["layout"]["nodes"][0]["x"] = 100
    assert pool.template("ticket_1_1")["layout"]["nodes"][0]["x"] == 0, "Template callers must own independent objects"

    pool.decide("ticket_1_1", "yes")
    pool.decide("ticket_2_1", "no")
    reopened = question_pool.QuestionPool(questions, network, images)
    assert reopened.get("ticket_1_1")["decision"] == "yes"
    assert reopened.get("ticket_2_1")["decision"] == "no"
    reopened.decide("ticket_1_1", None)
    assert reopened.get("ticket_1_1")["decision"] is None
    before = pool.decisions_path.read_bytes()
    for sid, decision in (("ticket_1_1", "invalid"), ("ticket_99_99", "yes"),
                          ("ticket_cd_1_3", "yes"), ("ticket_cd_2_1", "no"), ("ticket_cd_1_3", None)):
        try:
            pool.decide(sid, decision)
            raise AssertionError("Invalid/unknown decisions must fail")
        except (ValueError, KeyError):
            pass
    assert pool.decisions_path.read_bytes() == before
    assert not list(pool.decisions_path.parent.glob(".decisions-*")), "Atomic writes must clean up temporary files"

    # Exercise actual routes, triangulation, scene export, promotion and history.
    built_dir = network / "build"
    overrides = [(server, "NET", network), (server, "SIT", situations),
                 (server, "HISTORY", network / "history"), (server, "PREVIEW", network / "preview"),
                 (server, "QUESTION_POOL", pool), (server, "IMAGES", images),
                 (check, "NET", network), (engine_sync, "NET", network), (engine_sync, "SIT", situations),
                 (build, "NET", network), (build, "BUILD", built_dir)]
    patches = [patch.object(module, name, value) for module, name, value in overrides]
    for item in patches:
        item.start()
    engine_sync.engine_base.cache_clear()
    http = server.Server(("127.0.0.1", 0), server.Handler)
    worker = threading.Thread(target=http.serve_forever, daemon=True)
    worker.start()
    base_url = f"http://127.0.0.1:{http.server_port}"

    def request(path, body=None, raw=False):
        req = Request(base_url + path, data=json.dumps(body).encode() if body is not None else None,
                      headers={"Content-Type": "application/json"})
        try:
            with urlopen(req, timeout=30) as response:
                content = response.read()
                return response.status, content if raw else json.loads(content)
        except HTTPError as error:
            return error.code, json.loads(error.read())

    try:
        assert request("/api/questions")[1]["counts"]["total"] == 6
        assert request("/api/questions/ticket_1_1/decision", {"decision": "bad"})[0] == 400
        assert request("/api/questions/ticket_1_1/decision", {})[0] == 400
        assert request("/api/questions/ticket_99_1/decision", {"decision": "no"})[0] == 404
        assert request("/api/questions/ticket_1_1/decision", {"decision": "yes"})[1]["decision"] == "yes"
        status, response = request("/api/scene/ticket_1_1")
        assert status == 200 and response["virtual"] is True and response["playable"] is False
        assert response["scene"]["actors"] == [] and response["build"]["surfaces"]
        assert not (situations / "ticket_1_1").exists(), "Opening templates must never materialise engine files"
        assert request("/api/scene/ticket_99_99")[0] == 404
        assert request("/api/questions/ticket_cd_1_3/template")[0] == 404
        assert request("/api/scene/ticket_cd_1_3")[0] == 404
        assert request("/api/scene/ticket_cd_2_1")[0] == 404
        assert not any(item["id"].startswith("ticket_cd_") for item in request("/api/scenes")[1])
        assert request("/api/game/include/ticket_cd_2_1", {"playable": True})[0] == 404
        assert request("/api/game/run/ticket_cd_2_1", {})[0] == 404
        assert request("/api/scene/ticket_cd_1_3", {"id": "ticket_cd_1_3"})[0] == 400
        assert request("/api/questions/ticket_cd_1_3/decision", {"decision": "yes"})[0] == 404
        assert request("/api/questions/ticket_cd_2_1/decision", {"decision": "no"})[0] == 404
        assert request("/api/questions/ticket_cd_1_3/decision", {"decision": None})[0] == 404
        ab_source = request("/api/scene/ticket_1_3")[1]["source"]
        assert ab_source["category"] == "ab" and ab_source["imageUrl"].startswith("/asset/source/ab/")
        assert request(ab_source["imageUrl"], raw=True)[1].startswith(b"fixture ab ")
        scene = response["scene"]
        scene["decor"] = [{"id": "author-item", "prop": "trees/oak", "pos": [35, 35], "yaw": 0, "scale": [1, 1, 1]}]
        scene["reviewed"] = True  # Save alone must not publish a draft.
        status, saved = request("/api/scene/ticket_1_1", scene)
        assert status == 200, saved
        exported = json.loads((situations / "ticket_1_1" / "scene.json").read_text())
        assert exported["procedural"] is True and exported["actors"] == [] and exported["lights"] == []
        assert exported["props"][0]["prop"] == "trees/oak"
        assert exported["text"]["ru"] == scene["question"]["text"]["ru"]
        assert not list((situations / "ticket_1_1").glob("*.glb")), "No foreign baked scene or models may be copied"
        assert (built_dir / "ticket_1_1.json").exists()
        assert pool.get("ticket_1_1")["sceneExists"] is True and pool.get("ticket_1_1")["decision"] == "yes"
        assert json.loads((network / "ticket_1_1.json").read_text())["reviewed"] is False
        scene["decor"][0]["pos"] = [38, 32]
        assert request("/api/scene/ticket_1_1", scene)[0] == 200
        assert list((network / "history" / "ticket_1_1").glob("*.json"))
        assert request("/api/game/include/ticket_1_1", {"playable": True})[1]["playable"] is True
        assert pool.get("ticket_1_1") is None
        promoted = json.loads((network / "ticket_1_1.json").read_text())
        assert "questionPool" not in promoted and promoted["decor"][0]["pos"] == [38, 32]
        assert request("/api/game/include/ticket_1_1", {"playable": False})[1]["playable"] is False
        assert pool.get("ticket_1_1") is None, "Disabling a promoted scene must not put it back in Questions"
        promoted["questionPool"] = {"category": "ab"}  # A stale browser cannot undo promotion.
        assert request("/api/scene/ticket_1_1", promoted)[0] == 200
        assert "questionPool" not in json.loads((network / "ticket_1_1.json").read_text())
        assert request("/api/questions/ticket_1_1/decision", {"decision": "no"})[0] == 404
    finally:
        http.shutdown()
        http.server_close()
        worker.join(timeout=5)
        for item in reversed(patches):
            item.stop()
        engine_sync.engine_base.cache_clear()

# The complete checked-in corpus: no writes, and all unbuilt illustrated variants survive.
real_pool = question_pool.QuestionPool()
full = real_pool.list()
ids = {record["id"] for record in full["questions"]}
assert "ticket_5_12" in ids and "ticket_24_12" in ids
assert "ticket_1_16" not in ids, "The game's 45 road questions are already implemented too"
assert all(record["category"] == "ab" and record["categories"] == ["ab"] for record in full["questions"])
assert not any(record["id"].startswith("ticket_cd_") for record in full["questions"])
assert real_pool.source("ticket_cd_1_3") is None and real_pool.get("ticket_cd_1_3") is None
assert len(real_pool._sources) == 800
assert len(real_pool._groups) == 800
assert sum(full["counts"][key] for key in ("unreviewed", "yes", "no")) == full["counts"]["total"]
print(f"Question pool PASS: 800 A/B source questions/cards, {full['counts']['total']} remaining; C/D sources, saved approvals and templates excluded; HTTP sorting, blank geometry, export, history and permanent promotion")
