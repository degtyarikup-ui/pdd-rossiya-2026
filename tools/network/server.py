#!/usr/bin/env python3
"""Scene editor server (localhost only):

    ./scripts/network_editor.sh   ->  http://127.0.0.1:8950/

The editor reads and writes the road network (game_godot/network/<id>.json). Every save runs
the invariants (check.py), rebuilds the surfaces (build.py) and writes the game's scene file
(engine_sync.py). /api/preview checks and builds an unsaved scene, so the editor can show the
result while it is being edited. A save keeps the file's own number format (90.0 stays 90.0), so
git shows only what was changed.
"""
import json
import re
import shutil
import subprocess
import sys
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from shapely.geometry import LineString

sys.path.insert(0, str(Path(__file__).parent))
import build  # noqa: E402
import check  # noqa: E402
import engine_sync  # noqa: E402

HERE = Path(__file__).parent
EDITOR = HERE / "editor"
NET = check.NET
HISTORY = NET / "history"
PREVIEW = NET / "preview"
SIT = engine_sync.SIT
GAME = check.ROOT / "game_godot"
SCENERY = GAME / "scenery" / "index.json"
DETAIL = GAME / "textures" / "detail"
FONTS = check.ROOT / "assets" / "fonts"
QUESTIONS = check.ROOT / "assets" / "countries" / "ru" / "questions"
IMAGES = check.ROOT / "assets" / "countries" / "ru" / "images"
ID = re.compile(r"^[a-z0-9_]+$")
# The triangulation library keeps global state and crashes when two threads use it at once, and the
# geometry code (shapely, triangle) is not made for parallel use from here: every request that loads or
# builds a scene runs under this one lock. One editor, short requests: the lock costs nothing visible.
BUILD_LOCK = threading.RLock()   # re-entrant: the builds inside a request take it again
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# Limits of a texture edit: numbers the game can draw sensibly (scenery.gdshader).
TEXTURE_LIMITS = {"gain": (0.0, 8.0), "macro": (0.0, 0.5), "macroScale": (0.01, 2.0), "period": (0.4, 40.0)}
TYPES = {".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png",
         ".webp": "image/webp", ".glb": "model/gltf-binary", ".json": "application/json", ".svg": "image/svg+xml", ".ttf": "font/ttf"}
ASSET_RULES = [
    (re.compile(r"^scene/([a-z0-9_]+)/((scene|actor_\d+|light_\d+)\.glb)$"), lambda m: SIT / m[1] / m[2]),
    (re.compile(r"^scenery/([a-z0-9_/]+)\.glb$"), lambda m: GAME / "scenery" / f"{m[1]}.glb"),
    (re.compile(r"^models/([a-z0-9_/]+)\.glb$"), lambda m: GAME / "models" / f"{m[1]}.glb"),
    (re.compile(r"^texture/([A-Za-z]+)\.png$"), lambda m: DETAIL / f"{m[1]}.png"),
    (re.compile(r"^sign/([0-9.]+)\.svg$"), lambda m: GAME / "signs" / f"{m[1]}.svg"),
]
STREET_WIDTH = 8.4    # the street of the game: two 4.2 m lanes (scripts/street.gd ROAD_HALF)
EDGE_EPS = 0.05       # an edge is measured just inside the scene's square (m)
GODOT_RUN = {"proc": None}   # the game window the editor opened last (one at a time)


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
                       ("decor", "предмет"), ("lawns", "газон"), ("markings", "разметка")):
        before = {x.get("id") for x in old.get(key, []) if not x.get("auto")}
        after = {x.get("id") for x in new.get(key, []) if not x.get("auto")}
        out += [f"{label} {x}" for x in sorted(before - after)]
    return out


def keep_format(new, old):
    """The editor's JSON has no floats with a zero fraction (90.0 comes back as 90): where the file had
    the same number as a float, the float is kept, so a save does not rewrite untouched values."""
    if isinstance(new, dict) and isinstance(old, dict):
        return {k: keep_format(v, old.get(k)) for k, v in new.items()}
    if isinstance(new, list) and isinstance(old, list):
        return [keep_format(v, old[i] if i < len(old) else None) for i, v in enumerate(new)]
    if isinstance(new, int) and not isinstance(new, bool) and isinstance(old, float) and float(new) == old:
        return old
    return new


def normalised(scene: dict, old: dict) -> dict:
    """The scene as it will be written: the old file's number format, and no empty lists the file
    did not have (the editor works with empty lawns and markings where a file has none)."""
    out = keep_format(scene, old)
    for key in ("lawns", "markings"):
        if key not in old and out.get(key) == []:
            out.pop(key)
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


def scenery_index() -> dict:
    return json.loads(SCENERY.read_text(encoding="utf-8"))


def texture_entry(index: dict, kind: str):
    return next((t for t in index["textures"] if t["kind"] == kind), None)


def png_size(head: bytes):
    """(width, height) of a PNG from its first 24 bytes, or None if they are not a PNG header."""
    if len(head) < 24 or not head.startswith(PNG_SIGNATURE) or head[12:16] != b"IHDR":
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def texture_backups(kind: str) -> list:
    folder = HISTORY / "textures" / kind
    return sorted(folder.glob("*.png")) if folder.is_dir() else []


def keep_texture_backup(kind: str, keep: int = 10) -> None:
    """The picture of a texture as it is now, kept before it is replaced ("Вернуть прежнюю")."""
    src = DETAIL / f"{kind}.png"
    if not src.exists():
        return
    folder = HISTORY / "textures" / kind
    folder.mkdir(parents=True, exist_ok=True)
    (HISTORY / ".gdignore").touch()   # Godot skips this folder: the backups are not game assets to import
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    (folder / f"{stamp}.png").write_bytes(src.read_bytes())
    for old in texture_backups(kind)[:-keep]:
        old.unlink()


# ---- edges: how the scene meets the game's street -----------------------------------------
# The game lays a junction into its street: the street comes in at the south side and goes on from the
# side of the exit taken (turned so the exit runs along +z through x = 0). So every side the road reaches
# must have the street's carriageway: 8.4 m, centred on the middle of the side.
def seam_line(side: str, c: float) -> LineString:
    """The line at distance c from the centre on a side (n: z = c, s: z = -c, e: x = c, w: x = -c)."""
    if side in ("n", "s"):
        z = c if side == "n" else -c
        return LineString([(-400, z), (400, z)])
    x = c if side == "e" else -c
    return LineString([(x, -400), (x, 400)])


def edges(scene: dict) -> dict:
    """For each side: the carriageway that reaches it (width, centre) and whether it is the street's."""
    _, _, roads, _ = build.ground(scene)
    crop = float(scene.get("crop", 90.0))
    out = {}
    for side in ("n", "s", "e", "w"):
        inter = roads.intersection(seam_line(side, crop - EDGE_EPS))
        if inter.is_empty:
            out[side] = None
            continue
        b = inter.bounds
        lo, hi = (b[0], b[2]) if side in ("n", "s") else (b[1], b[3])
        width, centre = hi - lo, (lo + hi) / 2
        out[side] = {"width": round(width, 2), "centre": round(centre, 2),
                     "street": abs(width - STREET_WIDTH) < 0.2 and abs(centre) < 0.2}
    return out


# ---- road plan of a traced scene ------------------------------------------------------------
def detect_layout(scene: dict) -> dict:
    """A road plan (editor/layout.js) that matches a traced scene: its arms where the road meets the
    sides, a junction where they cross, a roundabout where an island sits in the middle."""
    crop = float(scene.get("crop", 90.0))
    road, islands, _, _ = build.ground(scene)
    sides = edges(scene)

    def kind(w):
        return "yard" if w < 6.5 else "street" if w < 11.0 else "avenue"

    arms = {k: v for k, v in sides.items() if v}
    cx = sum(arms[k]["centre"] for k in ("n", "s") if k in arms) / max(1, sum(1 for k in ("n", "s") if k in arms))
    cz = sum(arms[k]["centre"] for k in ("e", "w") if k in arms) / max(1, sum(1 for k in ("e", "w") if k in arms))
    port = {"n": lambda a: (a["centre"], crop), "s": lambda a: (a["centre"], -crop),
            "e": lambda a: (crop, a["centre"]), "w": lambda a: (-crop, a["centre"])}
    nodes, streets = [], []
    centre = {"id": "c", "x": round(cx, 2), "z": round(cz, 2)}
    ring = None
    parts = list(islands.geoms) if hasattr(islands, "geoms") else ([islands] if not islands.is_empty else [])
    for p in parts:
        c = p.centroid
        if p.area > 40 and abs(c.x - cx) < 8 and abs(c.y - cz) < 8:
            island = (p.area / 3.14159) ** 0.5
            ring = {"r": round(min(30.0, island + 10.0), 1), "island": round(island, 1)}
            centre.update({"x": round(c.x, 2), "z": round(c.y, 2), "ring": ring})
    order = [k for k in ("s", "n", "e", "w") if k in arms]
    if len(order) == 2 and not ring:
        a, b = order
        na = {"id": a, "x": round(port[a](arms[a])[0], 2), "z": round(port[a](arms[a])[1], 2)}
        nb = {"id": b, "x": round(port[b](arms[b])[0], 2), "z": round(port[b](arms[b])[1], 2)}
        nodes += [na, nb]
        st = {"id": "s1", "a": a, "b": b, "kind": kind(arms[a]["width"]), "ends": {}}
        if {a, b} != {"n", "s"} and {a, b} != {"e", "w"}:
            st["bend"] = [centre["x"], centre["z"]]
        streets.append(st)
        return {"nodes": nodes, "streets": streets, "player": {"street": "s1", "toward": b if a == "s" else a}}
    nodes.append(centre)
    for k in order:
        x, z = port[k](arms[k])
        nodes.append({"id": k, "x": round(x, 2), "z": round(z, 2)})
        st = {"id": f"s_{k}", "a": k, "b": "c", "kind": kind(arms[k]["width"]), "ends": {}}
        if k == "s":
            st["ends"] = {"b": {"stop": True}}
        streets.append(st)
    player = {"street": "s_s", "toward": "c"} if "s" in arms else None
    out = {"nodes": nodes, "streets": streets}
    if player:
        out["player"] = player
    return out


# ---- the game -----------------------------------------------------------------------------
def find_godot():
    found = shutil.which("godot")
    if found:
        return found
    for c in (Path("/Applications/Godot.app/Contents/MacOS/Godot"), Path("/Applications/Godot_4.app/Contents/MacOS/Godot")):
        if c.is_file():
            return str(c)
    return None


def run_game(sid: str, auto: bool) -> dict:
    """Opens the game on one junction (the car just before it); the window opened before is closed."""
    godot = find_godot()
    if not godot:
        return {"launched": False, "error": "Godot не найден: поставьте Godot 4.7.2 (docs/game/README.md)"}
    # The game loads the junction's models from Godot's import cache: files the save has just copied
    # (participants, lights) must be imported first, or an older junction shows up.
    reimport_game()
    old = GODOT_RUN["proc"]
    if old and old.poll() is None:
        old.terminate()
    args = [godot, "--path", str(GAME), "--", f"--situation={sid}", "--near"]
    if auto:
        args.append("--auto")
    GODOT_RUN["proc"] = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"launched": True}


def reimport_game() -> bool:
    """Godot draws a texture from its import cache, so a changed PNG reaches the game only after
    `--import`: about 5 s, and no tracked file changes. False when Godot is not installed."""
    godot = find_godot()
    if not godot:
        return False
    try:
        r = subprocess.run([godot, "--headless", "--path", str(GAME), "--import"], capture_output=True, timeout=180)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


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

    def raw(self, limit=8_000_000) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        if length > limit:
            raise ValueError("слишком большой файл")
        return self.rfile.read(length)

    def body(self):
        return json.loads(self.raw() or b"{}")

    # A failure inside a scene's checks or build is an answer for the editor (422 with the reason), not a
    # dropped connection that looks like "Failed to fetch".
    def do_GET(self):
        with BUILD_LOCK:
            self.guarded(self.route_get)

    def do_POST(self):
        with BUILD_LOCK:
            self.guarded(self.route_post)

    def guarded(self, route):
        try:
            route()
        except Exception as e:  # noqa: BLE001 - reported to the editor, the server goes on
            self.send(422, {"error": f"Сцена не собралась: {type(e).__name__}: {e}"})

    def scene_exists(self, sid: str) -> bool:
        return bool(ID.match(sid)) and (NET / f"{sid}.json").exists()

    def route_get(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            return self.file(EDITOR / "index.html")
        if path.startswith("/static/fonts/"):
            # The app's own font (assets/fonts), so the editor reads like the app.
            name = path[len("/static/fonts/"):]
            return self.file(FONTS / name) if re.fullmatch(r"Onest-[A-Za-z]+\.ttf", name) else self.send(404, {"error": "not found"})
        if path.startswith("/static/"):
            rel = path[len("/static/"):]
            if ".." in rel:
                return self.send(404, {"error": "not found"})
            return self.file(EDITOR / rel)
        m = re.match(r"^/preview/([a-z0-9_]+)\.png$", path)
        if m:
            return self.file(PREVIEW / f"{m[1]}.png")
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
        if path == "/api/textures":
            return self.send(200, self.texture_list())
        m = re.match(r"^/api/scene/([a-z0-9_]+)$", path)
        if m and self.scene_exists(m[1]):
            s = check.load(m[1])
            built = build.build(s)
            return self.send(200, {"scene": s, "findings": check.check_scene(s), "build": built, "edges": edges(s),
                                   "source": ticket_question(m[1]), "playable": engine_sync.playable(m[1])})
        m = re.match(r"^/api/layout/detect/([a-z0-9_]+)$", path)
        if m and self.scene_exists(m[1]):
            return self.send(200, {"layout": detect_layout(check.load(m[1]))})
        self.send(404, {"error": "not found"})

    def route_post(self):
        path = self.path.split("?")[0]
        m = re.match(r"^/api/game/run/([a-z0-9_]+)$", path)
        if m and self.scene_exists(m[1]):
            return self.send(200, run_game(m[1], bool(self.body().get("auto"))))
        m = re.match(r"^/api/game/include/([a-z0-9_]+)$", path)
        if m and self.scene_exists(m[1]):
            return self.include(m[1], bool(self.body().get("playable")))
        m = re.match(r"^/api/thumb/([a-z0-9_]+)$", path)
        if m and self.scene_exists(m[1]):
            data = self.raw()
            if png_size(data[:24]) is None:
                return self.send(400, {"error": "Нужен PNG"})
            PREVIEW.mkdir(parents=True, exist_ok=True)
            (PREVIEW / f"{m[1]}.png").write_bytes(data)
            return self.send(200, {"ok": True})
        m = re.match(r"^/api/texture/([A-Za-z]+)(/image|/restore)?$", path)
        if m:
            return self.texture_post(m[1], m[2])
        m = re.match(r"^/api/(scene|preview)/([a-z0-9_]+)$", path)
        if not m or not ID.match(m[2]):
            return self.send(404, {"error": "not found"})
        scene = self.body()
        if scene.get("id") != m[2]:
            return self.send(400, {"error": "scene id does not match the URL"})
        findings = check.check_scene(scene)
        if m[1] == "preview":
            return self.send(200, {"findings": findings, "build": build.build(scene), "edges": edges(scene)})
        if not (SIT / m[2] / "engine.json").exists():
            return self.send(400, {"error": "У сцены нет основы игры (situations/<id>/engine.json)"})
        target = NET / f"{m[2]}.json"
        old = check.load(m[2]) if target.exists() else {}
        removed = removed_items(old, scene)
        keep_history(m[2])
        target.write_text(json.dumps(normalised(scene, old), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        build.main([m[2]])
        try:
            synced = engine_sync.sync(m[2])
        except (ValueError, KeyError) as e:
            return self.send(422, {"error": str(e), "findings": findings})
        self.send(200, {"findings": findings, "synced": synced, "removed": removed})

    def include(self, sid: str, playable: bool):
        """In the game or not: the scene's "reviewed" flag and the game's list of junctions."""
        target = NET / f"{sid}.json"
        s = check.load(sid)
        if playable and any(f["level"] == "error" for f in check.check_scene(s)):
            return self.send(400, {"error": "Сначала исправьте ошибки сцены"})
        if bool(s.get("reviewed", True)) != playable:
            s["reviewed"] = playable
            keep_history(sid)
            target.write_text(json.dumps(s, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        ids = engine_sync.write_index()
        return self.send(200, {"playable": engine_sync.playable(sid), "count": len(ids)})

    def texture_list(self):
        out = []
        for t in scenery_index()["textures"]:
            f = DETAIL / f"{t['kind']}.png"
            size = None
            if f.exists():
                with f.open("rb") as fh:
                    size = png_size(fh.read(24))
            out.append({**t, "width": size and size[0], "height": size and size[1],
                        "backups": len(texture_backups(t["kind"]))})
        return out

    def texture_post(self, kind: str, action):
        index = scenery_index()
        entry = texture_entry(index, kind)
        if entry is None:
            return self.send(404, {"error": f"Нет текстуры «{kind}»"})
        if action == "/image":
            data = self.raw()
            size = png_size(data[:24])
            if size is None:
                return self.send(400, {"error": "Нужен файл PNG"})
            keep_texture_backup(kind)
            (DETAIL / f"{kind}.png").write_bytes(data)
            return self.send(200, {"width": size[0], "height": size[1], "imported": reimport_game()})
        if action == "/restore":
            backups = texture_backups(kind)
            if not backups:
                return self.send(404, {"error": "Прежней картинки нет"})
            previous = backups[-1]
            keep_texture_backup(kind)
            (DETAIL / f"{kind}.png").write_bytes(previous.read_bytes())
            previous.unlink(missing_ok=True)
            return self.send(200, {"imported": reimport_game()})
        # Numbers of the texture (scenery/index.json): only the fields the editor shows, inside their limits.
        body = self.body()
        for key, (lo, hi) in TEXTURE_LIMITS.items():
            if key not in body or (key == "period" and not entry.get("period")):
                continue
            v = body[key]
            if not isinstance(v, (int, float)) or not lo <= v <= hi:
                return self.send(400, {"error": f"Параметр «{key}»: число от {lo} до {hi}"})
            entry[key] = float(v)
        SCENERY.write_text(json.dumps(index, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        self.send(200, {"texture": entry})

    def scene_list(self):
        out = []
        for p in sorted(NET.glob("*.json")):
            s = json.loads(p.read_text(encoding="utf-8"))
            found = check.check_scene(s)
            q = s.get("question") or {}
            ru = (q.get("text") or {}).get("ru") or {}
            out.append({"id": p.stem, "status": (s.get("compliance") or {}).get("status"),
                        "errors": sum(f["level"] == "error" for f in found),
                        "warns": sum(f["level"] == "warn" for f in found),
                        "playable": bool(s.get("reviewed", True)) and not s.get("regulator", False),
                        "regulator": bool(s.get("regulator", False)),
                        "layout": bool(s.get("layout")),
                        "preview": (PREVIEW / f"{p.stem}.png").exists(),
                        "questionText": ru.get("title", "")})
        return out

    def catalog(self):
        index = scenery_index()
        models = {}
        for p in sorted(SIT.glob("*/engine.json")):
            for k, a in enumerate(json.loads(p.read_text(encoding="utf-8")).get("actors", [])):
                models.setdefault(a.get("type"), []).append({
                    "asset": f"{p.parent.name}/actor_{k}.glb", "name": a.get("name", ""),
                    "maxSpeed": a.get("maxSpeed"), "clearDistance": a.get("clearDistance"),
                    "halfLength": a.get("halfLength"), "halfWidth": a.get("halfWidth")})
        signs = sorted((p.stem for p in (GAME / "signs").glob("*.svg")), key=lambda c: [int(x) for x in c.split(".")])
        return {"props": [{"id": k, "size": v.get("size")} for k, v in index["props"].items()], "signs": signs,
                "actorTypes": {t: v[0] for t, v in models.items()},
                "lightAsset": next((f"{p.parent.name}/light_0.glb" for p in sorted(SIT.glob("*/engine.json"))
                                    if json.loads(p.read_text(encoding="utf-8")).get("lights")), None)}


class Server(ThreadingHTTPServer):
    request_queue_size = 64      # the scene list asks for ~150 previews at once; the default queue refuses most
    daemon_threads = True


if __name__ == "__main__":
    print("scene editor: http://127.0.0.1:8950/")
    Server(("127.0.0.1", 8950), Handler).serve_forever()
