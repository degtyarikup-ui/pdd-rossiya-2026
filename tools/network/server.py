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
import subprocess
import sys
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs

from shapely.geometry import LineString

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
                       ("decor", "предмет"), ("lawns", "газон"), ("markings", "разметка")):
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
    """The picture of a texture as it is now, kept before it is replaced (\"Вернуть прежнюю\")."""
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


# ---- stitching: how a scene meets its neighbour in the game ---------------------------------
# The game lays a junction into the street: the junction's crop square ends where the street goes on, and
# the carriageway of its edge must be the street's (8.4 m, centred on x = 0). Two scenes that touch must
# also meet each other. Only moves (no turns): the neighbour is placed by (dx, dz) from the origin.
STITCH_EPS = 0.05     # the seam is measured just inside each scene's edge (m)
STREET_WIDTH = 8.4    # the street of the game: two 4.2 m lanes (scripts/street.gd ROAD_HALF)
OPPOSITE = {"n": "s", "s": "n", "e": "w", "w": "e"}


def seam_line(side: str, c: float) -> LineString:
    """The line at distance c from the centre on a side (n: z = c, s: z = -c, e: x = c, w: x = -c)."""
    if side in ("n", "s"):
        z = c if side == "n" else -c
        return LineString([(-400, z), (400, z)])
    x = c if side == "e" else -c
    return LineString([(x, -400), (x, 400)])


def stitch(a_id: str, b_id: str, side: str, dx=None, dz=None) -> dict:
    A, B = check.load(a_id), check.load(b_id)
    _, _, roads_a, ring_a = build.ground(A)
    _, _, roads_b, ring_b = build.ground(B)
    ca, cb = float(A.get("crop", 90.0)), float(B.get("crop", 90.0))
    horizontal = side in ("n", "s")
    lo_hi = (lambda b: (b[0], b[2])) if horizontal else (lambda b: (b[1], b[3]))

    def profile(geom, line):
        inter = geom.intersection(line)
        return None if inter.is_empty else lo_hi(inter.bounds)

    a_road = profile(roads_a, seam_line(side, ca - STITCH_EPS))
    a_pave = profile(ring_a, seam_line(side, ca - STITCH_EPS))
    facing = OPPOSITE[side]
    b_road = profile(roads_b, seam_line(facing, cb - STITCH_EPS))
    b_pave = profile(ring_b, seam_line(facing, cb - STITCH_EPS))
    if a_road is None or b_road is None:
        return {"match": False, "error": "У края нет проезжей части", "auto": None}

    def centre(p):
        return (p[0] + p[1]) / 2

    # Placed to touch: the neighbour's facing edge on this scene's edge, its road centred on this one's.
    along = centre(a_road) - centre(b_road)
    if horizontal:
        auto = {"dx": along, "dz": ca + cb if side == "n" else -(ca + cb)}
    else:
        auto = {"dx": ca + cb if side == "e" else -(ca + cb), "dz": along}
    dx = auto["dx"] if dx is None else float(dx)
    dz = auto["dz"] if dz is None else float(dz)
    shift = dx if horizontal else dz
    b_road = (b_road[0] + shift, b_road[1] + shift)
    # The gap between the two edges: positive where the street fills the space, negative where they overlap.
    gap = {"n": (dz - cb) - ca, "s": -ca - (dz + cb), "e": (dx - cb) - ca, "w": -ca - (dx + cb)}[side]
    width_a, width_b = a_road[1] - a_road[0], b_road[1] - b_road[0]
    offset = centre(b_road) - centre(a_road)
    seam_at = {"n": ca, "s": -ca, "e": ca, "w": -ca}[side]
    if horizontal:
        seam = [[a_road[0], seam_at], [a_road[1], seam_at]]
    else:
        seam = [[seam_at, a_road[0]], [seam_at, a_road[1]]]

    def street(p):
        return abs((p[1] - p[0]) - STREET_WIDTH) < 0.15 and abs(centre(p)) < 0.15

    return {
        "auto": {"dx": round(auto["dx"], 3), "dz": round(auto["dz"], 3)},
        "dx": round(dx, 3), "dz": round(dz, 3), "gap": round(gap, 3), "offset": round(offset, 3),
        "widthDiff": round(width_b - width_a, 3),
        "a": {"width": round(width_a, 3), "centre": round(centre(a_road), 3),
              "street": street(a_road)},
        "b": {"width": round(width_b, 3), "centre": round(centre(b_road), 3),
              "street": street(b_road)},
        "seam": seam, "match": abs(offset) < 0.1 and abs(width_b - width_a) < 0.1 and abs(gap) < 0.2,
    }


def reimport_game() -> bool:
    """Godot draws a texture from its import cache, so a changed PNG reaches the game only after
    `--import`: about 5 s, and no tracked file changes. False when Godot is not installed."""
    try:
        r = subprocess.run(["godot", "--headless", "--path", str(GAME), "--import"], capture_output=True, timeout=180)
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

    def body(self):
        return json.loads(self.rfile.read(int(self.headers["Content-Length"])))

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
        if path == "/api/textures":
            return self.send(200, self.texture_list())
        m = re.match(r"^/api/stitch/([a-z0-9_]+)/([a-z0-9_]+)$", path)
        if m and (NET / f"{m[1]}.json").exists() and (NET / f"{m[2]}.json").exists():
            q = {k: v[0] for k, v in parse_qs(self.path.partition("?")[2]).items()}
            if q.get("side") not in OPPOSITE:
                return self.send(400, {"error": "side: n, s, e или w"})
            return self.send(200, stitch(m[1], m[2], q["side"], q.get("dx"), q.get("dz")))
        m = re.match(r"^/api/scene/([a-z0-9_]+)$", path)
        if m and (NET / f"{m[1]}.json").exists():
            s = check.load(m[1])
            with BUILD_LOCK:
                built = build.build(s)
            return self.send(200, {"scene": s, "findings": check.check_scene(s), "build": built,
                                   "source": ticket_question(m[1])})
        self.send(404, {"error": "not found"})

    def route_post(self):
        path = self.path.split("?")[0]
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
            with BUILD_LOCK:
                built = build.build(scene)
            return self.send(200, {"findings": findings, "build": built})
        target = NET / f"{m[2]}.json"
        removed = removed_items(check.load(m[2]) if target.exists() else {}, scene)
        keep_history(m[2])
        target.write_text(json.dumps(scene, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        with BUILD_LOCK:
            build.main([m[2]])
        try:
            synced = engine_sync.sync(m[2])
        except (ValueError, KeyError) as e:
            return self.send(422, {"error": str(e), "findings": findings})
        self.send(200, {"findings": findings, "synced": synced, "removed": removed})

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
            length = int(self.headers.get("Content-Length", 0))
            if length > 8_000_000:
                return self.send(413, {"error": "Картинка больше 8 МБ"})
            data = self.rfile.read(length)
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
            title = ((q.get("text") or {}).get("ru") or {}).get("ticket", "")
            out.append({"id": p.stem, "title": title, "status": (s.get("compliance") or {}).get("status"),
                        "errors": sum(f["level"] == "error" for f in found),
                        "warns": sum(f["level"] == "warn" for f in found),
                        "playable": bool(s.get("reviewed", True)) and not s.get("regulator", False),
                        "regulator": bool(s.get("regulator", False))})
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


class Server(ThreadingHTTPServer):
    request_queue_size = 64      # the scene list asks for ~150 previews at once; the default queue refuses most
    daemon_threads = True


if __name__ == "__main__":
    print("scene editor: http://127.0.0.1:8950/")
    Server(("127.0.0.1", 8950), Handler).serve_forever()
