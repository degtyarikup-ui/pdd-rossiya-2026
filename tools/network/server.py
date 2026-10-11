#!/usr/bin/env python3
"""Scene editor server (localhost only):

    ./scripts/network_editor.sh   ->  http://127.0.0.1:8950/

The editor reads and writes the road network (game_godot/network/<id>.json). Every save runs
the invariants (check.py), rebuilds the surfaces (build.py) and writes the game's scene file
(engine_sync.py). /api/preview checks and builds an unsaved scene, so the editor can show the
result while it is being edited.
"""
import json
import re
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import build  # noqa: E402
import check  # noqa: E402
import engine_sync  # noqa: E402

HERE = Path(__file__).parent
EDITOR = HERE / "editor"
NET = check.NET
HISTORY = NET / "history"
SIT = engine_sync.SIT
GAME = check.ROOT / "game_godot"
QUESTIONS = check.ROOT / "assets" / "countries" / "ru" / "questions"
IMAGES = check.ROOT / "assets" / "countries" / "ru" / "images"
ID = re.compile(r"^[a-z0-9_]+$")
TYPES = {".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png",
         ".webp": "image/webp", ".glb": "model/gltf-binary", ".json": "application/json", ".svg": "image/svg+xml"}
ASSET_RULES = [
    (re.compile(r"^scene/([a-z0-9_]+)/((scene|actor_\d+|light_\d+)\.glb)$"), lambda m: SIT / m[1] / m[2]),
    (re.compile(r"^scenery/([a-z0-9_/]+)\.glb$"), lambda m: GAME / "scenery" / f"{m[1]}.glb"),
    (re.compile(r"^models/([a-z0-9_/]+)\.glb$"), lambda m: GAME / "models" / f"{m[1]}.glb"),
]


def ticket_question(sid: str):
    """The original ticket question of ticket_N_M: its picture, text, answers and comment (verbatim)."""
    m = re.match(r"^ticket_(\d+)_(\d+)$", sid)
    if not m:
        return None
    for cat in ("ab", "cd"):
        path = QUESTIONS / f"questions_{cat}.json"
        if not path.exists():
            continue
        tickets = json.loads(path.read_text(encoding="utf-8"))["tickets"]
        n, k = int(m[1]), int(m[2])
        if 1 <= n <= len(tickets) and 1 <= k <= len(tickets[n - 1]["questions"]):
            q = tickets[n - 1]["questions"][k - 1]
            return {"ticket": n, "number": k, "category": cat, "question": q["question"],
                    "answers": q["answers"], "comment": q.get("comment", ""), "image": q.get("image")}
    return None


def removed_items(old: dict, new: dict) -> list:
    """What this save takes away from the scene (routes, participants, lights, roads, props)."""
    out = []
    for key, label in (("routes", "маршрут"), ("actors", "участник"), ("lights", "светофор"), ("roads", "дорога"),
                       ("decor", "предмет")):
        before = {x.get("id") for x in old.get(key, [])}
        after = {x.get("id") for x in new.get(key, [])}
        out += [f"{label} {x}" for x in sorted(before - after)]
    return out


def keep_history(sid: str, keep: int = 30) -> None:
    """A copy of the scene before each save, so a save can always be undone from disk."""
    src = NET / f"{sid}.json"
    if not src.exists():
        return
    folder = HISTORY / sid
    folder.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    (folder / f"{stamp}.json").write_bytes(src.read_bytes())
    for old in sorted(folder.glob("*.json"))[:-keep]:
        old.unlink()


def source_image(image: str):
    for cat in ("questions_ab", "questions_cd"):
        f = IMAGES / cat / f"{image}.webp"
        if f.exists():
            return f
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if ctype.startswith(("text/", "application/json")) else ""))
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def file(self, path: Path):
        if not path.is_file():
            return self.send(404, {"error": "not found"})
        return self.send(200, path.read_bytes(), TYPES.get(path.suffix, "application/octet-stream"))

    def body(self):
        return json.loads(self.rfile.read(int(self.headers["Content-Length"])))

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            return self.file(EDITOR / "index.html")
        if path.startswith("/static/"):
            rel = path[len("/static/"):]
            if ".." in rel:
                return self.send(404, {"error": "not found"})
            return self.file(EDITOR / rel)
        m = re.match(r"^/preview/([a-z0-9_]+)\.png$", path)
        if m:
            return self.file(NET / "preview" / f"{m[1]}.png")
        m = re.match(r"^/asset/source/([a-f0-9]{32})\.webp$", path)
        if m:
            f = source_image(m[1])
            return self.file(f) if f else self.send(404, {"error": "not found"})
        if path.startswith("/asset/"):
            rel = path[len("/asset/"):]
            for rule, to in ASSET_RULES:
                hit = rule.match(rel)
                if hit:
                    return self.file(to(hit))
            return self.send(404, {"error": "not found"})
        if path == "/api/scenes":
            return self.send(200, self.scene_list())
        if path == "/api/catalog":
            return self.send(200, self.catalog())
        m = re.match(r"^/api/scene/([a-z0-9_]+)$", path)
        if m and (NET / f"{m[1]}.json").exists():
            s = check.load(m[1])
            return self.send(200, {"scene": s, "findings": check.check_scene(s), "build": build.build(s),
                                   "source": ticket_question(m[1])})
        self.send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        m = re.match(r"^/api/(scene|preview)/([a-z0-9_]+)$", path)
        if not m or not ID.match(m[2]):
            return self.send(404, {"error": "not found"})
        scene = self.body()
        if scene.get("id") != m[2]:
            return self.send(400, {"error": "scene id does not match the URL"})
        findings = check.check_scene(scene)
        if m[1] == "preview":
            return self.send(200, {"findings": findings, "build": build.build(scene)})
        target = NET / f"{m[2]}.json"
        removed = removed_items(check.load(m[2]) if target.exists() else {}, scene)
        keep_history(m[2])
        target.write_text(json.dumps(scene, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        build.main([m[2]])
        try:
            synced = engine_sync.sync(m[2])
        except (ValueError, KeyError) as e:
            return self.send(422, {"error": str(e), "findings": findings})
        self.send(200, {"findings": findings, "synced": synced, "removed": removed})

    def scene_list(self):
        out = []
        for p in sorted(NET.glob("*.json")):
            s = json.loads(p.read_text(encoding="utf-8"))
            found = check.check_scene(s)
            q = s.get("question") or {}
            title = ((q.get("text") or {}).get("ru") or {}).get("ticket", "")
            out.append({"id": p.stem, "title": title, "status": (s.get("compliance") or {}).get("status"),
                        "errors": sum(f["level"] == "error" for f in found),
                        "warns": sum(f["level"] == "warn" for f in found)})
        return out

    def catalog(self):
        index = json.loads((GAME / "scenery" / "index.json").read_text(encoding="utf-8"))
        models = {}
        for p in sorted(SIT.glob("*/engine.json")):
            for k, a in enumerate(json.loads(p.read_text(encoding="utf-8")).get("actors", [])):
                models.setdefault(a.get("type"), []).append({
                    "asset": f"{p.parent.name}/actor_{k}.glb", "name": a.get("name", ""),
                    "maxSpeed": a.get("maxSpeed"), "clearDistance": a.get("clearDistance"),
                    "halfLength": a.get("halfLength"), "halfWidth": a.get("halfWidth")})
        return {"props": [{"id": k, "size": v.get("size")} for k, v in index["props"].items()],
                "actorTypes": {t: v[0] for t, v in models.items()},
                "lightAsset": next((f"{p.parent.name}/light_0.glb" for p in sorted(SIT.glob("*/engine.json"))
                                    if json.loads(p.read_text(encoding="utf-8")).get("lights")), None)}


if __name__ == "__main__":
    print("scene editor: http://127.0.0.1:8950/")
    ThreadingHTTPServer(("127.0.0.1", 8950), Handler).serve_forever()
