#!/usr/bin/env python3
"""Стенд игры: просмотр сцен против билетов, езда с клавиатуры, редактор знаков/декора.

Запуск:  python3 tools/game_lab/server.py      (или scripts/game_lab.sh)
Открыть: http://127.0.0.1:8940/

Только 127.0.0.1. Игра берётся прямо из assets/game (в game.js на лету
вставляется lab-hook.js — в приложение он не попадает). Правки сцен пишутся в
assets/game/scene-edits.js (их применяет сама игра), отметки проверки — в
tools/game_lab/review.json.
"""
import json
import mimetypes
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(REPO, "assets", "game")
CONTENT = os.path.join(REPO, "assets", "countries", "ru")
EDITS = os.path.join(GAME, "scene-edits.js")
MODELS = os.path.join(GAME, "model-edits.js")
REVIEW = os.path.join(HERE, "review.json")
PORT = int(os.environ.get("GAME_LAB_PORT", "8940"))
HEADER = "// Hand edits from the game lab (tools/game_lab) — generated, do not edit by hand.\n"
MARK = "  // Run init on DOM ready"


def read_js(path):
    try:
        text = open(path, encoding="utf-8").read()
        return json.loads(text.split("=", 1)[1].strip().rstrip(";"))
    except (OSError, IndexError, ValueError):
        return {}


def write_js(path, name, data):
    body = json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(HEADER + f"window.{name} = " + body + ";\n")


def read_edits():
    return read_js(EDITS)


def write_edits(data):
    write_js(EDITS, "PDD_SCENE_EDITS", data)


# One build at a time: "собрать и поставить на телефон" (scripts/install_dev.sh --build).
BUILD = {"running": False, "log": [], "code": None}


def run_build():
    BUILD.update(running=True, log=[], code=None)
    proc = subprocess.Popen(["./scripts/install_dev.sh", "--build"], cwd=REPO,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in proc.stdout:
        BUILD["log"].append(line.rstrip())
        del BUILD["log"][:-400]
    BUILD.update(running=False, code=proc.wait())


def read_review():
    try:
        return json.load(open(REVIEW, encoding="utf-8"))
    except (OSError, ValueError):
        return {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def file(self, root, rel):
        path = os.path.abspath(os.path.join(root, rel))
        if not path.startswith(root + os.sep) or not os.path.isfile(path):
            return self.send(404, "not found", "text/plain")
        data = open(path, "rb").read()
        if os.path.basename(path) == "game.js" and root == GAME:
            hook = open(os.path.join(HERE, "lab-hook.js"), encoding="utf-8").read()
            data = data.decode("utf-8").replace(MARK, hook + "\n" + MARK, 1).encode("utf-8")
        self.send(200, data, mimetypes.guess_type(path)[0] or "application/octet-stream")

    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        if path in ("/", "/index.html"):
            return self.file(HERE, "lab.html")
        if path.startswith("/lab/"):
            return self.file(HERE, path[5:])
        if path.startswith("/game/"):
            return self.file(GAME, path[6:])
        if path.startswith("/content/"):
            return self.file(CONTENT, path[9:])
        if path == "/api/edits":
            return self.send(200, json.dumps(read_edits(), ensure_ascii=False))
        if path == "/api/review":
            return self.send(200, json.dumps(read_review(), ensure_ascii=False))
        if path == "/api/models":
            return self.send(200, json.dumps(read_js(MODELS), ensure_ascii=False))
        if path == "/api/build":
            return self.send(200, json.dumps(BUILD, ensure_ascii=False))
        self.send(404, "not found", "text/plain")

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            return self.send(400, '{"error":"bad json"}')
        if path == "/api/edits":
            # One scenario per request: {id, objects}; empty objects removes it.
            edits = read_edits()
            if data.get("objects"):
                edits[data["id"]] = {"objects": data["objects"]}
            else:
                edits.pop(data.get("id"), None)
            write_edits(edits)
            return self.send(200, '{"ok":true}')
        if path == "/api/models":
            models = read_js(MODELS)
            if data.get("edit"):
                models[data["id"]] = data["edit"]
            else:
                models.pop(data.get("id"), None)
            write_js(MODELS, "PDD_MODEL_EDITS", models)
            return self.send(200, '{"ok":true}')
        if path == "/api/build":
            if not BUILD["running"]:
                threading.Thread(target=run_build, daemon=True).start()
            return self.send(200, '{"ok":true}')
        if path == "/api/review":
            review = read_review()
            review[data["id"]] = {"status": data.get("status", ""), "note": data.get("note", "")}
            json.dump(review, open(REVIEW, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
            return self.send(200, '{"ok":true}')
        self.send(404, '{"error":"not found"}')


if __name__ == "__main__":
    print(f"Стенд игры: http://127.0.0.1:{PORT}/")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
