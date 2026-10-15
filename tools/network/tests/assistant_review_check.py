#!/usr/bin/env python3
"""Real editor HTTP save/approval lifecycle, with every write isolated in scratch/."""
import copy
import json
from contextlib import ExitStack
from pathlib import Path
import sys
import tempfile
import threading
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
import check
import engine_sync
import question_pool
import server


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


with tempfile.TemporaryDirectory(prefix="assistant-review-", dir=check.ROOT / "scratch") as temporary:
    root = Path(temporary)
    questions, network, situations = root / "questions", root / "network", root / "situations"
    network.mkdir()
    situations.mkdir()
    write(questions / "questions_ab.json", {"tickets": [{"number": 1, "questions": [
        {"id": "source-1", "question": "Разрешён ли поворот?", "answers": [{"text": "Да", "correct": True}]},
        {"id": "source-2", "question": "Другой вопрос", "answers": [{"text": "Нет", "correct": True}]}]}]})
    pool = question_pool.QuestionPool(questions, network, root / "images")
    scene = pool.template("ticket_1_1")
    review = {"author": "codex", "batch": "2026-10-16-first-12", "status": "pending", "note": "keep provenance"}
    scene["assistantReview"] = review.copy()
    write(network / "ticket_1_1.json", scene)
    write(situations / "ticket_1_1" / "engine.json", question_pool.engine_template(scene))
    write(pool.decisions_path, {"schema": 1, "decisions": {"ticket_1_1": "yes", "ticket_1_2": "no"}})
    decisions_before = pool.decisions_path.read_bytes()
    overrides = [(server, "NET", network), (server, "SIT", situations),
                 (server, "HISTORY", network / "history"), (server, "PREVIEW", network / "preview"),
                 (server, "QUESTION_POOL", pool), (check, "NET", network),
                 (engine_sync, "NET", network), (engine_sync, "SIT", situations),
                 (build, "NET", network), (build, "BUILD", network / "build")]
    with ExitStack() as stack:
        for module, name, value in overrides:
            stack.enter_context(patch.object(module, name, value))
        engine_sync.engine_base.cache_clear()
        http = server.Server(("127.0.0.1", 0), server.Handler)
        worker = threading.Thread(target=http.serve_forever, daemon=True)
        worker.start()

        def request(path, body=None):
            req = Request(f"http://127.0.0.1:{http.server_port}" + path,
                          data=json.dumps(body).encode() if body is not None else None,
                          headers={"Content-Type": "application/json"})
            try:
                with urlopen(req, timeout=30) as response:
                    return response.status, json.loads(response.read())
            except HTTPError as error:
                return error.code, json.loads(error.read())

        try:
            listed = request("/api/scenes")[1]
            assert len(listed) == 1 and listed[0]["assistantReview"] == review
            assert listed[0]["playable"] is False
            assert pool.get("ticket_1_1") is None, "Assistant drafts have their own queue, not duplicate plan entries"
            assert pool.list()["counts"]["total"] == 1
            assert engine_sync.write_index() == []
            reopened = request("/api/scene/ticket_1_1")[1]
            assert reopened["scene"]["assistantReview"] == review and not reopened["playable"]
            edited = reopened["scene"]
            edited["decor"] = [{"id": "owner-tree", "prop": "trees/oak", "pos": [35, 34], "yaw": .75, "scale": [1, 1, 1]}]
            edited["questionView"] = {"centre": [1, 3], "height": 35}
            edited["reviewed"] = True
            edited["assistantReview"] = {"author": "someone-else", "status": "approved"}
            status, saved = request("/api/scene/ticket_1_1", edited)
            assert status == 200, saved
            source = check.load("ticket_1_1")
            assert source["reviewed"] is False and source["assistantReview"] == review
            assert source["questionPool"] == scene["questionPool"]
            assert source["decor"] == edited["decor"] and source["questionView"] == edited["questionView"]
            assert saved["assistantReview"] == review and saved["reviewed"] is False
            exported = json.loads((situations / "ticket_1_1" / "scene.json").read_text())
            assert exported["props"][0]["pos"] == [35, 0, 34]
            assert exported["questionView"] == edited["questionView"]
            assert engine_sync.write_index() == [], "Saving changes must not approve a scene"

            # Validation must reject an explicit approval of an incomplete scene.
            broken = copy.deepcopy(source)
            broken["question"]["correct"] = 99
            assert request("/api/scene/ticket_1_1", broken)[0] == 200
            assert request("/api/game/include/ticket_1_1", {"playable": True})[0] == 400
            assert check.load("ticket_1_1")["assistantReview"]["status"] == "pending"
            assert request("/api/scene/ticket_1_1", source)[0] == 200

            approved = {**review, "status": "approved"}
            status, response = request("/api/game/include/ticket_1_1", {"playable": True})
            assert status == 200 and response["playable"] and response["assistantReview"] == approved
            source = check.load("ticket_1_1")
            assert source["assistantReview"] == approved and source["reviewed"] is True
            assert "questionPool" not in source
            assert source["decor"] == edited["decor"] and source["questionView"] == edited["questionView"]
            assert engine_sync.write_index() == ["ticket_1_1"]
            assert request("/api/scenes")[1][0]["assistantReview"] == approved

            # A stale pre-approval browser copy may edit geometry, never approval/provenance.
            edited["decor"][0]["pos"] = [37, 32]
            assert request("/api/scene/ticket_1_1", edited)[0] == 200
            source = check.load("ticket_1_1")
            assert source["assistantReview"] == approved and source["reviewed"] is True
            assert "questionPool" not in source and source["decor"][0]["pos"] == [37, 32]
            assert request("/api/game/include/ticket_1_1", {"playable": False})[1]["assistantReview"] == review
            withdrawn = check.load("ticket_1_1")
            assert withdrawn["reviewed"] is False and withdrawn["decor"] == source["decor"]
            assert pool.get("ticket_1_1") is None and engine_sync.write_index() == []
            assert request("/api/game/include/ticket_1_1", {"playable": True})[1]["assistantReview"] == approved
            assert check.load("ticket_1_1")["decor"] == source["decor"]
            assert pool.decisions_path.read_bytes() == decisions_before
            assert len(list((network / "history" / "ticket_1_1").glob("*.json"))) >= 7
        finally:
            http.shutdown()
            http.server_close()
            worker.join(timeout=5)
            engine_sync.engine_base.cache_clear()

print("Codex approval: pending/edit/validation/approve/stale-save/withdraw/reapprove, real HTTP/export/history PASS")
