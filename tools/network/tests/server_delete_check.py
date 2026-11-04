#!/usr/bin/env python3
"""Real HTTP deletion and stale-editor guards; all writes stay in temp copies.

Optional first argument is a source network/ticket_9_14.json to copy (read only).
"""
from __future__ import annotations

from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import shutil
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
from question_pool import QuestionPool
import server


def hashes(root):
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*") if path.is_file()}


sid = "ticket_9_14"
source = Path(sys.argv[1]) if len(sys.argv) > 1 else check.NET / f"{sid}.json"
source_game = source.parent.parent
questions = check.ROOT / "assets/countries/ru/questions"
images = check.ROOT / "assets/countries/ru/images"
source_before = source.read_bytes()
questions_before = hashes(questions)
image = QuestionPool(questions=questions).source(sid).get("image")
source_image = images / "questions_ab" / f"{image}.webp"
image_before = source_image.read_bytes() if source_image.exists() else None
situations_before = hashes(source_game / "situations" / sid)
scratch = check.ROOT / "scratch"
scratch.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="server-delete-check-", dir=scratch) as tmp:
    root = Path(tmp)
    network, situations = root / "game/network", root / "game/situations"
    network.mkdir(parents=True)
    situations.mkdir(parents=True)
    (network / f"{sid}.json").write_bytes(source_before)
    shutil.copytree(source_game / "situations" / sid, situations / sid)
    for folder, suffix in (("build", ".json"), ("preview", ".png")):
        (network / folder).mkdir()
        original = source.parent / folder / f"{sid}{suffix}"
        (network / folder / original.name).write_bytes(original.read_bytes() if original.exists() else b"fixture")
    (situations / "index.json").write_text(json.dumps([sid, "ticket_1_2"]), encoding="utf-8")
    (network.parent / "roads").mkdir()
    shutil.copy2(source_game / "roads/road_scenes.json", network.parent / "roads/road_scenes.json")
    pool = QuestionPool(questions, network, images)
    with ExitStack() as stack:
        for module, name, value in (
            (server, "NET", network), (server, "SIT", situations), (server, "HISTORY", network / "history"),
            (server, "PREVIEW", network / "preview"), (server, "QUESTION_POOL", pool),
            (check, "NET", network), (build, "NET", network), (build, "BUILD", network / "build"),
            (engine_sync, "NET", network), (engine_sync, "SIT", situations),
        ):
            stack.enter_context(patch.object(module, name, value))
        stack.enter_context(patch.object(server.Handler, "log_message", lambda *_args: None))
        engine_sync.engine_base.cache_clear()
        http = server.Server(("127.0.0.1", 0), server.Handler)
        worker = threading.Thread(target=http.serve_forever, daemon=True)
        worker.start()

        def request(path, body=None):
            data = body if isinstance(body, bytes) else json.dumps(body).encode() if body is not None else None
            req = Request(f"http://127.0.0.1:{http.server_port}{path}", data=data,
                          headers={"Content-Type": "application/json"})
            try:
                with urlopen(req, timeout=30) as response:
                    return response.status, json.loads(response.read())
            except HTTPError as error:
                return error.code, json.loads(error.read())

        try:
            status, loaded = request(f"/api/scene/{sid}")
            assert status == 200 and loaded["scene"] == json.loads(source_before)
            status, info = request(f"/api/scene/{sid}/deletion")
            assert status == 200 and sid in info["ids"] and info["hasScene"]
            before = hashes(root)
            assert request(f"/api/scene/{sid}/delete", {"revision": "stale"})[0] == 409
            assert hashes(root) == before
            # An edit made after the dialog opened invalidates that confirmation.
            (network / f"{sid}.json").write_bytes(source_before + b"\n")
            assert request(f"/api/scene/{sid}/delete", {"revision": info["revision"]})[0] == 409
            status, info = request(f"/api/scene/{sid}/deletion")
            assert status == 200
            status, deleted = request(f"/api/scene/{sid}/delete", {"revision": info["revision"]})
            assert status == 200 and deleted["ids"] == info["ids"]
            assert (Path(deleted["archive"]) / "network" / f"{sid}.json").read_bytes() == source_before + b"\n"
            assert not (situations / sid).exists()
            assert json.loads((situations / "index.json").read_text()) == ["ticket_1_2"]
            after = hashes(root)
            for deleted_id in deleted["ids"]:
                assert request(f"/api/scene/{deleted_id}")[0] == 410
                assert request(f"/api/questions/{deleted_id}/template")[0] == 410
                stale = {**loaded["scene"], "id": deleted_id}
                assert request(f"/api/scene/{deleted_id}", stale)[0] == 410
                assert request(f"/api/game/include/{deleted_id}", {"playable": True})[0] == 410
                assert request(f"/api/thumb/{deleted_id}", b"stale PNG callback")[0] == 410
                assert request(f"/api/questions/{deleted_id}/decision", {"decision": "yes"})[0] == 410
                assert request(f"/api/scene/{deleted_id}/delete", {"revision": info["revision"]})[0] == 404
            assert hashes(root) == after, "No stale request may recreate sources, previews, exports or decisions"
            # A source-free planned question follows the same deletion contract.
            planned = next(q for q in pool.list()["questions"] if q["status"] == "plan" and q["decision"] != "no" and not q["hasScene"])
            status, plan_info = request(f"/api/scene/{planned['id']}/deletion")
            assert status == 200 and not plan_info["hasScene"]
            assert request(f"/api/scene/{planned['id']}/delete", {"revision": plan_info["revision"]})[0] == 200
            assert request(f"/api/questions/{planned['id']}/template")[0] == 410
            for invalid in ("mini_regulator", "ticket_cd_1_1", "ticket_99_99", "not_a_scene"):
                assert request(f"/api/scene/{invalid}/deletion")[0] == 404
                assert request(f"/api/scene/{invalid}/delete", {"revision": "invalid"})[0] == 404
            # Persisted tombstones protect a fresh checkout without recovery history.
            shutil.rmtree(network / "history")
            assert request(f"/api/scene/{sid}", loaded["scene"])[0] == 410
            assert request(f"/api/questions/{sid}/template")[0] == 410
        finally:
            http.shutdown()
            http.server_close()
            worker.join()
            engine_sync.engine_base.cache_clear()

assert source.read_bytes() == source_before
assert hashes(source_game / "situations" / sid) == situations_before
assert hashes(questions) == questions_before, "Exam assets must remain immutable"
assert image_before is None or source_image.read_bytes() == image_before
print("server_delete_check: real native copy + plan, confirmation conflicts, removal, stale save/include/thumb/open guards, immutable exam assets passed")
