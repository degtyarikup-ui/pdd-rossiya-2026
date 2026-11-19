"""Save/reopen a terrain fixture through the real authenticated localhost handler."""
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
from urllib.request import Request, build_opener, ProxyHandler
urlopen = build_opener(ProxyHandler({})).open

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build, check, engine_sync, question_pool, server

sid = "ticket_11_15"
original = json.loads((build.NET / f"{sid}.json").read_text())
original_bytes = (build.NET / f"{sid}.json").read_bytes()
base_sit = engine_sync.SIT

with tempfile.TemporaryDirectory(prefix="terrain-save-") as tmp:
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
        token=json.loads(urlopen(f"http://127.0.0.1:{httpd.server_port}/api/local-session").read())["token"]
        def request(body=None):
            req = Request(f"http://127.0.0.1:{httpd.server_port}/api/scene/{sid}",
                          data=None if body is None else json.dumps(body).encode(),
                          headers={"Content-Type": "application/json", "X-Local-Token":token})
            with urlopen(req, timeout=30) as response:
                return json.loads(response.read())
        def exported():
            return json.loads((sit / sid / "scene.json").read_text())
        try:
            loaded = request()["scene"]
            request(loaded)
            native_export = exported()
            reviewed = request()["scene"].get("reviewed")
            assert request()["scene"].get('terrain') == original.get('terrain')
            changed = copy.deepcopy(loaded)
            crop = changed.get('crop', 90)
            changed['terrain'] = {
                'profile': [[-crop, 0], [0, 10], [crop, 0]],
                'bumps': [{'centre': [0, 0], 'width': 7, 'length': 3.5, 'height': .12}],
            }
            request(changed)
            assert request()['scene']['terrain']==changed['terrain']
            generated=json.loads((net/'build'/f'{sid}.json').read_text())
            asphalt=next(s for s in generated['surfaces']if s['id']=='asphalt')
            assert max(asphalt['heights']) >= 10.119
            side = [h for i, h in enumerate(asphalt['heights'])
                    if abs(abs(asphalt['verts'][2*i]) - crop) < .001]
            assert side and all(abs(h - asphalt['y']) < .001 for h in side)
            assert request()['scene'].get('reviewed') == reviewed
            assert exported().get('reviewed') == native_export.get('reviewed')
            invalid=copy.deepcopy(changed);invalid['terrain']['bumps'][0]['length']=0
            from urllib.error import HTTPError
            try: request(invalid);raise AssertionError('invalid terrain saved')
            except HTTPError as e: assert e.code==400
            assert request()['scene']['terrain']==changed['terrain']
        finally:
            httpd.shutdown(); httpd.server_close(); worker.join()
            engine_sync.engine_base.cache_clear()

assert (build.NET / f"{sid}.json").read_bytes() == original_bytes
print("Terrain HTTP save/reopen/export, approval preservation, invalid save rejected, real source untouched PASS")
