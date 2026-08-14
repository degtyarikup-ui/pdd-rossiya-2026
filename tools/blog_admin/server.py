#!/usr/bin/env python3
"""Локальная админка блога pdd-drive.ru.

Запуск:  python3 tools/blog_admin/server.py   (или scripts/blog_admin.sh)
Открыть: http://127.0.0.1:8930/admin

Слушает только 127.0.0.1 — наружу не торчит, паролей/аккаунтов не требует.
Корень раздачи = web_landing/ru (чтобы предпросмотр статей с абсолютными
путями /assets, /blog работал). Публикация на сайт — кнопкой (deploy_landing.sh).
"""
import json
import os
import re
import subprocess
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SITE = os.path.join(REPO, "web_landing", "ru")
BLOG = os.path.join(SITE, "blog")
PORT = 8930

sys.path.insert(0, HERE)
import generator  # noqa: E402

try:
    from PIL import Image  # noqa: F401
    HAS_PIL = True
except Exception:
    HAS_PIL = False

SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FILE_RE = re.compile(r"[^a-z0-9._-]+")
TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
    "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
    "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c",
    "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}


def safe_filename(name):
    """Кириллица→латиница, чистка; гарантирует непустое латинское имя."""
    name = (name or "").strip().lower()
    name = "".join(TRANSLIT.get(c, c) for c in name)
    stem, dot, ext = name.rpartition(".")
    if not dot:
        stem, ext = name, "png"
    stem = FILE_RE.sub("-", stem).strip("-.")
    ext = FILE_RE.sub("", ext) or "png"
    if not stem:
        stem = "image"
    return "%s.%s" % (stem, ext)
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8", ".json": "application/json; charset=utf-8",
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".webp": "image/webp", ".svg": "image/svg+xml", ".txt": "text/plain; charset=utf-8",
    ".xml": "application/xml; charset=utf-8", ".ico": "image/x-icon",
}
TODAY = "2026-07-19"  # окружение сборки фиксирует дату; для dateModified


def today():
    # реальную дату берём из системы, но безопасно (без падения в песочнице)
    try:
        import datetime
        return datetime.date.today().isoformat()
    except Exception:
        return TODAY


class Handler(BaseHTTPRequestHandler):
    server_version = "PddBlogAdmin/1.0"

    def log_message(self, *a):
        sys.stderr.write("[admin] " + (a[0] % a[1:]) + "\n")

    # --- helpers ---
    def _send(self, code, body=b"", ctype="application/json; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False), "application/json; charset=utf-8")

    def _err(self, code, msg):
        self._json(code, {"ok": False, "error": msg})

    def _body(self):
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n) if n else b""

    # --- routing ---
    def do_GET(self):
        u = urlparse(self.path)
        p = u.path
        if p == "/admin" or p == "/admin/":
            return self._file(os.path.join(HERE, "admin.html"))
        if p == "/api/articles":
            arts = generator.load_articles(include_drafts=True)
            return self._json(200, [{
                "slug": a["slug"], "title": a["title"],
                "datePublished": a.get("datePublished", ""),
                "published": bool(a.get("published")), "cover": a.get("cover"),
            } for a in arts])
        m = re.match(r"^/api/articles/([a-z0-9-]+)$", p)
        if m:
            path = os.path.join(BLOG, m.group(1), "source.json")
            if not os.path.isfile(path):
                return self._err(404, "нет такой статьи")
            with open(path, encoding="utf-8") as f:
                return self._json(200, json.load(f))
        # иначе — раздача статических файлов сайта (предпросмотр)
        return self._static(p)

    def do_HEAD(self):
        self.do_GET()

    def do_POST(self):
        u = urlparse(self.path)
        p = u.path
        try:
            if p == "/api/articles":
                return self._save_article()
            if p == "/api/upload":
                return self._upload(parse_qs(u.query))
            if p == "/api/regen":
                slugs = generator.regen_all()
                return self._json(200, {"ok": True, "slugs": slugs})
            if p == "/api/deploy":
                return self._deploy()
        except Exception as e:  # noqa: BLE001
            return self._err(500, "%s: %s" % (type(e).__name__, e))
        return self._err(404, "неизвестный эндпоинт")

    # --- static ---
    def _safe_path(self, urlpath):
        rel = urlpath.lstrip("/")
        if rel == "" or rel.endswith("/"):
            rel += "index.html"
        full = os.path.normpath(os.path.join(SITE, rel))
        if not full.startswith(SITE):
            return None
        return full

    def _static(self, urlpath):
        full = self._safe_path(urlpath)
        if not full or not os.path.isfile(full):
            return self._send(404, "404 Not Found", "text/plain; charset=utf-8")
        return self._file(full)

    def _file(self, full):
        ext = os.path.splitext(full)[1].lower()
        ctype = CONTENT_TYPES.get(ext, "application/octet-stream")
        with open(full, "rb") as f:
            self._send(200, f.read(), ctype)

    # --- API impl ---
    def _save_article(self):
        try:
            a = json.loads(self._body().decode("utf-8"))
        except Exception:
            return self._err(400, "тело не является JSON")
        slug = (a.get("slug") or "").strip()
        if not SLUG_RE.match(slug):
            return self._err(400, "недопустимый slug (только строчные латиница/цифры/дефис)")
        for field in ("title", "description", "datePublished"):
            if not (a.get(field) or "").strip():
                return self._err(400, "не заполнено поле: %s" % field)

        d = os.path.join(BLOG, slug)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, "source.json")

        prev = None
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                prev = json.load(f)

        a.setdefault("schema", 1)
        a["slug"] = slug
        a.setdefault("dateModified", a["datePublished"])
        a.setdefault("faq", [])
        a.setdefault("readingMinutes", max(3, len(re.sub(r"<[^>]+>", "", a.get("bodyHtml", "")).split()) // 180))
        # если контент изменился и статья публикуется — обновить dateModified
        if prev is not None and a.get("published"):
            changed = any(prev.get(k) != a.get(k) for k in ("title", "description", "bodyHtml", "faq", "cover"))
            if changed:
                a["dateModified"] = today()

        with open(path, "w", encoding="utf-8") as f:
            json.dump(a, f, ensure_ascii=False, indent=2)

        warnings = []
        st, sd = len(a.get("shortTitle") or a["title"]), len(a["description"])
        if st > 62:
            warnings.append("shortTitle %d симв. (желательно ≤62)" % st)
        if not (120 <= sd <= 165):
            warnings.append("description %d симв. (желательно 140–160)" % sd)

        generator.regen_all()
        # Черновик regen_all не рендерит (он идёт только по опубликованным) —
        # но страница нужна для предпросмотра, поэтому собираем её отдельно.
        if not a.get("published"):
            generator.render_article(slug)
        return self._json(200, {"ok": True, "slug": slug, "warnings": warnings})

    def _upload(self, qs):
        slug = (qs.get("slug", [""])[0]).strip()
        if not SLUG_RE.match(slug):
            return self._err(400, "нужен корректный slug")
        d = os.path.join(BLOG, slug)
        os.makedirs(d, exist_ok=True)
        raw = self._body()
        if not raw:
            return self._err(400, "пустой файл")
        # Имя приходит percent-encoded (заголовки HTTP не переживают кириллицу).
        raw_name = unquote(self.headers.get("X-Filename", "image.png"))
        name = safe_filename(raw_name)
        # не затирать уже загруженные картинки с тем же именем
        stem, _, ext = name.rpartition(".")
        n = 2
        while os.path.exists(os.path.join(d, name)):
            name = "%s-%d.%s" % (stem, n, ext)
            n += 1
        dest = os.path.join(d, name)
        with open(dest, "wb") as f:
            f.write(raw)
        # уменьшить крупные картинки до 1600px по ширине
        if HAS_PIL:
            try:
                from PIL import Image
                small = None
                with Image.open(dest) as im:
                    im.load()  # дочитать файл целиком — сохраняем по тому же пути
                    if im.width > 1600:
                        h = round(im.height * 1600 / im.width)
                        base = im.convert("RGB") if im.mode in ("P", "CMYK") else im.copy()
                        small = base.resize((1600, h))
                if small is not None:
                    small.save(dest)
            except Exception as e:  # noqa: BLE001
                self.log_message("resize skipped: %s", e)
        return self._json(200, {"ok": True, "url": "/blog/%s/%s" % (slug, name), "file": name})

    def _deploy(self):
        log = []
        try:
            r = subprocess.run(
                [os.path.join(REPO, "scripts", "deploy_landing.sh"), "ru", "Публикация блога через админку"],
                cwd=REPO, capture_output=True, text=True, timeout=600,
            )
            log.append(r.stdout.strip())
            if r.returncode != 0:
                log.append("STDERR: " + r.stderr.strip())
                return self._json(200, {"ok": False, "log": "\n".join(log)})
        except Exception as e:  # noqa: BLE001
            return self._json(200, {"ok": False, "log": "деплой не запустился: %s" % e})

        # IndexNow-пинг всех URL из sitemap
        try:
            keyfile = None
            for fn in os.listdir(SITE):
                if fn.endswith(".txt") and len(fn) == 36 and re.match(r"^[0-9a-f]{32}\.txt$", fn):
                    keyfile = fn
                    break
            if keyfile:
                key = keyfile[:-4]
                sm = open(os.path.join(SITE, "sitemap.xml"), encoding="utf-8").read()
                urls = re.findall(r"<loc>(.*?)</loc>", sm)
                payload = json.dumps({
                    "host": "pdd-drive.ru", "key": key,
                    "keyLocation": "https://pdd-drive.ru/%s" % keyfile, "urlList": urls,
                }).encode("utf-8")
                req = urllib.request.Request(
                    "https://api.indexnow.org/indexnow", data=payload,
                    headers={"Content-Type": "application/json; charset=utf-8"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    log.append("IndexNow: HTTP %d (%d URL)" % (resp.status, len(urls)))
            else:
                log.append("IndexNow: ключ не найден, пропущено")
        except Exception as e:  # noqa: BLE001
            log.append("IndexNow ошибка (не критично): %s" % e)
        return self._json(200, {"ok": True, "log": "\n".join(log)})


def main():
    os.chdir(SITE)
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("Админка блога: http://127.0.0.1:%d/admin" % PORT)
    print("Корень предпросмотра: %s" % SITE)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
