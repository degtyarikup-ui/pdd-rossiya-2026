#!/usr/bin/env python3
"""Web editor server for the road network (localhost only):
    ./scripts/network_editor.sh   ->  http://127.0.0.1:8950/
Reads/writes game_godot/network/<id>.json, runs the invariants (check.py) and the
surface build (build.py) on every save."""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import build  # noqa: E402
import check  # noqa: E402

NET = check.NET
HTML = (Path(__file__).parent / "editor.html").read_bytes()
ID = re.compile(r"^[a-z0-9_]+$")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self.send(200, (Path(__file__).parent / "editor.html").read_bytes(), "text/html")
        if self.path == "/api/scenes":
            out = []
            for p in sorted(NET.glob("*.json")):
                s = json.loads(p.read_text(encoding="utf-8"))
                found = check.check_scene(s)
                out.append({"id": p.stem, "geometry": s.get("geometry"), "status": s.get("compliance", {}).get("status"),
                            "errors": sum(f["level"] == "error" for f in found), "warns": sum(f["level"] == "warn" for f in found)})
            return self.send(200, out)
        m = re.match(r"^/api/scene/([a-z0-9_]+)$", self.path)
        if m and (NET / f"{m[1]}.json").exists():
            s = check.load(m[1])
            return self.send(200, {"scene": s, "findings": check.check_scene(s)})
        self.send(404, {"error": "not found"})

    def do_POST(self):
        m = re.match(r"^/api/scene/([a-z0-9_]+)$", self.path)
        if not m or not ID.match(m[1]):
            return self.send(404, {"error": "not found"})
        scene = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        findings = check.check_scene(scene)
        (NET / f"{m[1]}.json").write_text(json.dumps(scene, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        build.main([m[1]])
        self.send(200, {"findings": findings})


if __name__ == "__main__":
    print("road network editor: http://127.0.0.1:8950/")
    ThreadingHTTPServer(("127.0.0.1", 8950), Handler).serve_forever()
