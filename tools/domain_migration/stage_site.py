#!/usr/bin/env python3
"""Derive an isolated guest preview from an archived, deployed static site.

This does not build Flutter, deploy anything, migrate browser storage, contact an
API, or change the input archive. Serve ONLY with the accompanying HTTP headers
and a host that rejects API paths and non-GET/HEAD requests. The production build
is retained for comparison; network isolation deliberately disables account,
payment, analytics and cloud progress functionality.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import stat
from urllib.parse import unquote, urljoin, urlsplit


CSP = "; ".join((
    "default-src 'self'",
    "connect-src 'self'",
    "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'",
    "script-src-attr 'none'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self' data:",
    "media-src 'self' data: blob:",
    "worker-src 'self' blob:",
    "frame-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'none'",
    "manifest-src 'self'",
    "frame-ancestors 'self'",
))
HEADERS = {
    "Content-Security-Policy": CSP,
    "X-Robots-Tag": "noindex, nofollow, noarchive, nosnippet",
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
}
DISABLED = "/__staging_disabled__"
GENERATED = {
    "robots.txt", "_headers", "staging-provenance.json",
    "__staging/isolation.js", "__staging/warning.css",
}
SKIP = {"CNAME", "_headers", "_redirects", "_worker.js", "_routes.json"}
TEXT_SUFFIXES = {".html", ".htm", ".js", ".mjs", ".json", ".css", ".xml", ".txt", ".svg", ".webmanifest"}
DENIED_COMPONENTS = {".git", ".wrangler", ".ssh", "node_modules", "secrets", "backups", "backup"}
DENIED_SUFFIXES = {".jks", ".keystore", ".pem", ".key", ".p12", ".pfx", ".sqlite", ".sqlite3", ".db", ".sql", ".dump", ".bak", ".backup", ".zip", ".tar", ".gz", ".7z"}
BACKEND_HOSTS = (
    "pdd-install-notifier.sergei-pdd.workers.dev", "api.pdd-drive.app",
    "accounts.google.com", "appleid.apple.com", "oauth.yandex.ru",
    "login.yandex.ru", "oauth.telegram.org", "oauth.telegram.ru",
    "mc.yandex.ru", "mc.yandex.com", "www.google-analytics.com",
    "www.googletagmanager.com",
)
WARNING = """<aside id="staging-warning" aria-label="Тест / Test / Сынақ"><details>
<summary>Тестовая копия · Test copy · Сынақ көшірмесі</summary>
<p lang="ru">Тестовая копия. Вход, оплата и облачная синхронизация отключены. Прогресс сохраняется только в этом браузере и не перенесён с рабочего сайта. Не вводите личные данные.</p>
<p lang="en">Test copy. Sign-in, payments and cloud sync are disabled. Progress stays in this browser and has not been transferred from the live site. Do not enter personal information.</p>
<p lang="kk">Сынақ көшірмесі. Кіру, төлем және бұлтпен синхрондау өшірілген. Прогресс тек осы браузерде сақталады және негізгі сайттан көшірілмеген. Жеке деректерді енгізбеңіз.</p>
</details></aside>"""
WARNING_CSS = """#staging-warning{position:fixed;bottom:0;left:0;right:0;z-index:2147483647;background:#fff2cb;color:#252525;font:13px/1.4 Arial,sans-serif;border-top:2px solid #8a5200;padding:5px 12px}#staging-warning summary{cursor:pointer;text-align:center;font-weight:bold}#staging-warning p{margin:6px auto;max-width:1000px}#staging-warning details[open]{max-height:40vh;overflow:auto}\n"""
ISOLATION_JS = r"""// Isolated staging only. This never reads or deletes browser progress.
(() => {
  'use strict';
  const blocked = value => {
    try {
      const url = new URL(value, document.baseURI);
      const path = decodeURIComponent(url.pathname).replace(/\\/g, '/');
      return url.origin !== location.origin || !['http:', 'https:'].includes(url.protocol) ||
        /^\/(?:api(?:\/|$)|__staging_disabled__(?:\/|$))/.test(path);
    } catch (_) { return true; }
  };
  const deny = () => new DOMException('Disabled in isolated staging', 'SecurityError');
  const realFetch = window.fetch.bind(window);
  window.fetch = (input, options) => {
    const method = (options?.method || input?.method || 'GET').toUpperCase();
    if (blocked(input?.url || input) || !['GET', 'HEAD'].includes(method)) return Promise.reject(deny());
    return realFetch(input, options);
  };
  const realOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    if (blocked(url) || !['GET', 'HEAD'].includes(String(method).toUpperCase())) throw deny();
    return realOpen.call(this, method, url, ...rest);
  };
  Object.defineProperty(navigator, 'sendBeacon', {value: () => false});
  window.WebSocket = class { constructor() { throw deny(); } };
  window.EventSource = class { constructor() { throw deny(); } };
  const realWindowOpen = window.open.bind(window);
  window.open = (url, ...rest) => blocked(url) ? null : realWindowOpen(url, ...rest);
  document.addEventListener('click', event => {
    const link = event.target.closest?.('a,area');
    if (link && blocked(link.href)) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  document.addEventListener('submit', event => {event.preventDefault(); event.stopImmediatePropagation();}, true);
  if (navigator.serviceWorker) {
    navigator.serviceWorker.getRegistrations().then(items => items.forEach(item => item.unregister()));
    navigator.serviceWorker.register = () => Promise.reject(deny());
  }
  window.__PDD_ISOLATED_STAGING__ = true;
})();
"""


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def inventory(root: Path) -> dict[str, dict[str, int | str]]:
    """Reject symlinks, special files and accidentally mixed-in private archives."""
    entries = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(current) / name
            rel = path.relative_to(root)
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode) or not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ValueError(f"Unsafe source entry: {rel}")
            if (any(part.casefold() in DENIED_COMPONENTS for part in rel.parts)
                    or name.casefold().startswith(".env")
                    or path.suffix.casefold() in DENIED_SUFFIXES
                    or name.casefold() in {"users.json", "accounts.json", "payment_ledger.json", "wrangler.toml", "wrangler.jsonc"}):
                raise ValueError(f"Private/non-static source entry: {rel}")
            if any(ord(char) < 32 for char in str(rel)):
                raise ValueError("Control characters in a source path")
            if stat.S_ISREG(mode):
                entries[rel.as_posix()] = {"sha256": digest(path), "bytes": path.stat().st_size}
    return dict(sorted(entries.items()))


def source_tree_hash(entries: dict) -> str:
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def isolate_urls(text: str, origin: str) -> str:
    # Keep these paths on the preview. Never use the new apex as the API host.
    text = re.sub(r"https?://(?:www\.)?pdd-drive\.ru(?=[:/\s\"'<>?#]|$)", origin, text, flags=re.I)
    text = re.sub(r"https?://app\.pdd-drive\.ru(?=[:/\s\"'<>?#]|$)", origin + "/app", text, flags=re.I)
    for host in BACKEND_HOSTS:
        text = re.sub(r"(?:https?:)?//" + re.escape(host) + r"(?=[:/\s\"'<>?#]|$)", DISABLED, text, flags=re.I)
    return text


class SafeHTML(HTMLParser):
    def __init__(self, path: str, origin: str):
        super().__init__(convert_charrefs=False)
        self.path = path
        self.origin = origin
        self.output: list[str] = []
        self.drop_script = False
        self.in_head = False
        self.injected = False
        self.body_seen = False

    def inject(self):
        if self.injected:
            return
        self.injected = True
        # frame-ancestors is header-only. The host MUST also send HEADERS.
        meta_csp = CSP.replace("; frame-ancestors 'self'", "")
        self.output.append('<meta charset="utf-8"><meta name="robots" content="noindex,nofollow,noarchive,nosnippet">'
                           '<meta http-equiv="Content-Security-Policy" content="' + html.escape(meta_csp, quote=True) + '">'
                           '<script src="/__staging/isolation.js"></script>'
                           '<link rel="stylesheet" href="/__staging/warning.css">')

    def start(self, tag, attrs, closed=False):
        attrs_dict = {key.lower(): value for key, value in attrs}
        if tag == "head":
            self.in_head = True
        if tag == "script":
            src = attrs_dict.get("src", "")
            resolved = urlsplit(urljoin(self.origin + "/" + self.path, src))
            # Landing inline JS includes lead collection and analytics. Keep only
            # the audited cosmetic script; Flutter/Godot need their own scripts.
            allowed = (self.path.startswith("app/") and (not src or resolved.netloc == urlsplit(self.origin).netloc)) or resolved.path == "/assets/site.js"
            self.drop_script = not allowed
            if self.drop_script:
                return
        if tag == "meta" and (attrs_dict.get("name", "").lower() in {"robots", "googlebot", "yandex"}
                or attrs_dict.get("http-equiv", "").lower() in {"content-security-policy", "refresh"}):
            return
        if tag in {"iframe", "object", "embed"} and not self.path.startswith("app/"):
            return
        clean = []
        for key, value in attrs:
            if key.lower().startswith("on") or key.lower() in {"ping", "formaction"}:
                continue
            if value is not None:
                value = isolate_urls(value, self.origin)
                if key in {"href", "src", "action", "poster", "data"}:
                    resolved = urlsplit(urljoin(self.origin + "/" + self.path, value))
                    if (resolved.scheme not in {"http", "https"} or resolved.netloc != urlsplit(self.origin).netloc
                            or unquote(resolved.path).startswith(("/api/", DISABLED))):
                        if tag in {"a", "area"}:
                            value = "#staging-warning"
                        elif tag == "form":
                            value = DISABLED
                        else:
                            continue
            clean.append(key if value is None else f'{key}="{html.escape(value, quote=True)}"')
        if tag == "form":
            clean = [item for item in clean if not item.startswith("action=")]
            clean.append(f'action="{DISABLED}"')
        if tag in {"input", "button", "select", "textarea"} and not self.path.startswith("app/"):
            clean.append("disabled")
        self.output.append("<" + tag + (" " + " ".join(clean) if clean else "") + ("/>" if closed else ">"))
        if tag == "head":
            self.inject()
        if tag == "body":
            self.body_seen = True
            self.output.append(WARNING)

    def handle_starttag(self, tag, attrs):
        self.start(tag, attrs)

    def handle_startendtag(self, tag, attrs):
        self.start(tag, attrs, closed=True)

    def handle_endtag(self, tag):
        if tag == "script" and self.drop_script:
            self.drop_script = False
            return
        if not self.drop_script:
            self.output.append(f"</{tag}>")

    def handle_data(self, data):
        if not self.drop_script:
            self.output.append(isolate_urls(data, self.origin))

    def handle_entityref(self, name):
        if not self.drop_script:
            self.output.append("&" + name + ";")

    def handle_charref(self, name):
        if not self.drop_script:
            self.output.append("&#" + name + ";")

    def handle_comment(self, data):
        if not self.drop_script:
            self.output.append("<!--" + data + "-->")

    def handle_decl(self, decl):
        self.output.append("<!" + decl + ">")

    def result(self):
        if not self.injected or not self.body_seen:
            raise ValueError(f"HTML must have explicit head and body: {self.path}")
        return "".join(self.output)


def stage_site(source: Path, destination: Path, origin: str, source_revision: str = "") -> dict:
    parsed_origin = urlsplit(origin)
    hostname = (parsed_origin.hostname or "").rstrip(".")
    if (parsed_origin.scheme != "https" or not parsed_origin.hostname or parsed_origin.username
            or parsed_origin.password or parsed_origin.path or parsed_origin.query or parsed_origin.fragment
            or any(ord(char) < 33 for char in origin)
            or parsed_origin.port not in (None, 443)
            or not re.fullmatch(r"[a-zA-Z0-9.-]+", parsed_origin.hostname)
            or hostname == "pdd-drive.ru" or hostname.endswith(".pdd-drive.ru")
            or hostname in BACKEND_HOSTS):
        raise ValueError("Preview origin must be a separate HTTPS origin without a path or credentials")
    if source.is_symlink() or destination.is_symlink():
        raise ValueError("Source/destination cannot be a symlink")
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if not source.is_dir() or destination.exists():
        raise ValueError("Source must be a directory; destination must not exist")
    if source in destination.parents or destination in source.parents:
        raise ValueError("Source and destination trees must be separate")
    if not destination.parent.is_dir():
        raise ValueError("Destination parent must already exist")
    before = inventory(source)
    if not {"index.html", "app/index.html", "app/flutter_bootstrap.js", "app/main.dart.js", "app/canvaskit/canvaskit.wasm", "app/canvaskit/canvaskit.js"}.issubset(before):
        raise ValueError("Expected an archived deployed landing site including its complete /app/ build")
    if GENERATED.intersection(before.keys()) - {"robots.txt", "_headers"}:
        raise ValueError("Source already contains staging files")
    created = False
    try:
        destination.mkdir(mode=0o700)
        created = True
        changed = []
        omitted = []
        for rel in before:
            if rel in SKIP or rel == "assets/tracker.js" or rel.endswith("flutter_service_worker.js"):
                omitted.append(rel)
                continue
            src = source / rel
            dst = destination / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.suffix.lower() in TEXT_SUFFIXES:
                original = src.read_text(encoding="utf-8")
                text = isolate_urls(original, origin)
                if src.suffix.lower() in {".html", ".htm"}:
                    parser = SafeHTML(rel, origin)
                    parser.feed(text)
                    parser.close()
                    text = parser.result()
                if rel == "app/flutter_bootstrap.js":
                    # Force bundled CanvasKit even when this release was built
                    # without --no-web-resources-cdn. No CDN exception in CSP.
                    token = "_flutter.loader.load({"
                    if text.count(token) != 1:
                        raise ValueError("Unknown Flutter bootstrap layout; refusing an unverified rewrite")
                    text = text.replace(token, token + '\n  config: {canvasKitBaseUrl: "/app/canvaskit/"},', 1)
                dst.write_text(text, encoding="utf-8")
                if text != original:
                    changed.append(rel)
            else:
                shutil.copyfile(src, dst)
            dst.chmod(0o644)
        (destination / "__staging").mkdir(exist_ok=True)
        (destination / "__staging/isolation.js").write_text(ISOLATION_JS, encoding="utf-8")
        (destination / "__staging/warning.css").write_text(WARNING_CSS, encoding="utf-8")
        (destination / "robots.txt").write_text("User-agent: *\nDisallow: /\n", encoding="utf-8")
        (destination / "_headers").write_text("/*\n" + "".join(f"  {key}: {value}\n" for key, value in HEADERS.items()), encoding="utf-8")
        after = inventory(source)
        if after != before:
            raise ValueError("Source changed during preparation; discard preview and recapture archive")
        output_hashes = inventory(destination)
        manifest = {
            "format": 1,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "origin": origin,
            "source_revision": source_revision,
            "source_tree_sha256": source_tree_hash(before),
            "source_files": before,
            "staged_files": output_hashes,
            "changed_files": changed,
            "omitted_files": omitted,
            "required_headers": HEADERS,
            "host_requirements": ["Reject non-GET/HEAD requests", "Return 403 for /api, /api/* and /__staging_disabled__*", "Never proxy missing files to production"],
            "limits": ["Isolated guest preview, not a data migration", "No sign-in, payments, analytics or cloud sync", "Existing browser progress is neither read nor imported", "Some games or remote fallback glyphs may require a fresh isolated build", "HTTP headers and host path/method enforcement are mandatory"],
        }
        (destination / "staging-provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return manifest
    except BaseException:
        # Only remove the newly-created destination, never either source tree.
        if created and destination.exists():
            shutil.rmtree(destination)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--origin", required=True)
    parser.add_argument("--source-revision", default="")
    args = parser.parse_args()
    try:
        manifest = stage_site(args.source, args.destination, args.origin, args.source_revision)
    except (OSError, ValueError, UnicodeError) as error:
        parser.exit(1, f"Staging preparation refused: {error}\n")
    print(json.dumps({"destination": str(args.destination.resolve()), "files": len(manifest["staged_files"]), "source_tree_sha256": manifest["source_tree_sha256"]}))


if __name__ == "__main__":
    main()
