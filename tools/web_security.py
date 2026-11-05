"""Apply per-document CSP to static deployment output (GitHub Pages has no header API).

This does not pretend that a meta tag supplies HSTS or X-Content-Type-Options.
Those headers are supplied by the optional site-edge Worker, after DNS setup.
"""
import argparse
import base64
import hashlib
import html
from html.parser import HTMLParser
from pathlib import Path
import re


class Scripts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.inline = []
        self.active = False
        self.parts = []
    def handle_starttag(self, tag, attrs):
        if tag == "script":
            self.active = not dict(attrs).get("src")
            self.parts = []
    def handle_data(self, value):
        if self.active:
            self.parts.append(value)
    def handle_endtag(self, tag):
        if tag == "script" and self.active:
            self.inline.append("".join(self.parts))
            self.active = False


def policy(document):
    parser = Scripts()
    parser.feed(document)
    hashes = sorted({"'sha256-" + base64.b64encode(hashlib.sha256(s.encode()).digest()).decode() + "'" for s in parser.inline})
    scripts = "'self' 'wasm-unsafe-eval' " + " ".join(hashes) + " https://accounts.google.com https://apis.google.com https://mc.yandex.ru https://mc.yandex.com https://yastatic.net https://www.gstatic.com"
    return "; ".join([
        "default-src 'self'", "script-src " + scripts, "script-src-attr 'none'",
        "object-src 'none'", "base-uri 'self'", "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://accounts.google.com",
        "font-src 'self' data: https://fonts.gstatic.com", "img-src 'self' data: blob: https:",
        "media-src 'self' blob: https:", "worker-src 'self' blob:",
        "frame-src 'self' https://accounts.google.com https://www.youtube.com https://www.youtube-nocookie.com",
        "connect-src 'self' https://pdd-install-notifier.sergei-pdd.workers.dev https://api.pdd-drive.app https://accounts.google.com https://*.googleapis.com https://*.gstatic.com https://mc.yandex.ru https://mc.yandex.com https://yandex.ru",
        "form-action 'self'", "upgrade-insecure-requests",
    ])


def secure_html(document):
    # Idempotent: remove policies before calculating script hashes.
    document = re.sub(r'<meta\b[^>]*http-equiv\s*=\s*["\']Content-Security-Policy["\'][^>]*>\s*', '', document, flags=re.I)
    document = re.sub(r'<meta\b[^>]*name\s*=\s*["\']referrer["\'][^>]*>\s*', '', document, flags=re.I)
    tags = '<meta http-equiv="Content-Security-Policy" content="' + html.escape(policy(document), quote=True) + '">\n<meta name="referrer" content="strict-origin-when-cross-origin">'
    # Encoding declaration must come first in the initial 1024 bytes.
    charset = re.search(r'<meta\b[^>]*charset=[^>]+>', document, flags=re.I)
    if charset:
        return document[:charset.end()] + '\n' + tags + '\n' + document[charset.end():].lstrip()
    return re.sub(r'(<head\b[^>]*>)', lambda m: m[0] + '\n<meta charset="utf-8">\n' + tags + '\n', document, count=1, flags=re.I)


def apply(root):
    count = 0
    for path in root.rglob("*.html"):
        if ".git" in path.parts:
            continue
        source = path.read_text()
        secured = secure_html(source)
        if secured != source:
            path.write_text(secured)
            count += 1
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    print("Applied static security policies to %d HTML documents" % apply(args.directory))
