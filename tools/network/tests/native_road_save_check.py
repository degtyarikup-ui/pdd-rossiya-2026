"""Save/reopen/export a copy of the authored cul-de-sac, without touching real scenes."""
import copy
import json
import shutil
import subprocess
import sys
import tempfile
import threading
from contextlib import ExitStack
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build, check, engine_sync, question_pool, server

sid = "ticket_9_14"
original = json.loads((build.NET / f"{sid}.json").read_text())
assert len(original["roads"][0]["outer"]) == 139
original_bytes = (build.NET / f"{sid}.json").read_bytes()
base_sit = engine_sync.SIT

with tempfile.TemporaryDirectory(prefix="native-save-", dir=build.ROOT / "scratch") as tmp:
    root = Path(tmp)
    net, sit = root / "network", root / "situations"
    net.mkdir(); sit.mkdir()
    # Actor meshes and the archived engine are read from real data, copied to
    # the sandbox before the exporter writes anything.
    shutil.copytree(base_sit / sid, sit / sid)
    (net / f"{sid}.json").write_bytes(original_bytes)
    with ExitStack() as stack:
        for module, name, value in [
            (server, "NET", net), (server, "SIT", sit), (server, "HISTORY", net / "history"),
            (server, "PREVIEW", net / "preview"),
            (server, "QUESTION_POOL", question_pool.QuestionPool(network=net)),
            (check, "NET", net), (build, "NET", net), (build, "BUILD", net / "build"),
            (engine_sync, "NET", net), (engine_sync, "SIT", sit),
        ]:
            stack.enter_context(patch.object(module, name, value))
        engine_sync.engine_base.cache_clear()
        httpd = server.Server(("127.0.0.1", 0), server.Handler)
        worker = threading.Thread(target=httpd.serve_forever, daemon=True); worker.start()
        def request(body=None):
            req = Request(f"http://127.0.0.1:{httpd.server_port}/api/scene/{sid}",
                          data=None if body is None else json.dumps(body).encode(),
                          headers={"Content-Type": "application/json"})
            with urlopen(req, timeout=30) as response:
                return json.loads(response.read())
        def exported():
            return json.loads((sit / sid / "scene.json").read_text())
        try:
            loaded = request()["scene"]
            request(loaded)
            native_export = exported()
            assert request()["scene"] == original, "plain save must retain the authored source"
            code = """
const fs=require('node:fs'), Layout=require('./tools/network/editor/layout.js');
const s=JSON.parse(fs.readFileSync(0,'utf8'));
Layout.ensureEditablePlan(s); Layout.addStreet(s,[30,25],[30,55],'avenue'); Layout.apply(s);
process.stdout.write(JSON.stringify(s));
"""
            addition = json.loads(subprocess.check_output(["node", "-e", code], input=json.dumps(loaded).encode(), cwd=build.ROOT))
            request(addition)
            reopened = request()["scene"]
            assert reopened == addition, "overlay plan and exact contours must survive save/reopen"
            for key, value in original.items():
                if key in ("roads", "markings", "lawns"):
                    assert reopened[key][:len(value)] == value, key
                else:
                    assert reopened[key] == value, key
            runtime = exported()
            for key in ("stopZ", "playerStartX", "playerStartRotY", "exits", "trajectories", "labels", "approachW", "exitWidths", "spec", "actors"):
                assert runtime.get(key) == native_export.get(key), f"gameplay changed: {key}"
            assert build.road_geometry(original)[0].difference(build.road_geometry(reopened)[0]).area < 1e-6
            # A later contour edit changes just that point; it does not invoke the detector.
            changed = copy.deepcopy(reopened)
            changed["roads"][0]["outer"][50][0] += .25
            request(changed)
            assert request()["scene"] == changed
            assert len(changed["roads"][0]["outer"]) == 139
        finally:
            httpd.shutdown(); httpd.server_close(); worker.join()
            engine_sync.engine_base.cache_clear()

assert (build.NET / f"{sid}.json").read_bytes() == original_bytes
print("Native road HTTP save/reload/export: 139-point cul-de-sac, paint, routes, player and additions preserved PASS")
