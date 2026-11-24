"""Add the school sign-in build to an existing, deployed /app/ tree."""

import hashlib
import re
import shutil
import sys
from pathlib import Path

build, app = (Path(arg) for arg in sys.argv[1:])
target = app / "school-login"
target.mkdir(exist_ok=True)
main = build / "main.dart.js"
digest = hashlib.sha256(main.read_bytes()).hexdigest()[:16]
shutil.copy2(main, target / f"main.{digest}.js")
bootstrap = (build / "flutter_bootstrap.js").read_text()
bootstrap, count = re.subn(
    r'"mainJsPath":"main\.dart\.js\?release=[0-9a-f]+"',
    f'"mainJsPath":"school-login/main.{digest}.js"',
    bootstrap,
)
if count != 1:
    raise ValueError("Missing versioned Flutter entry")
# This transient sign-in flow uses the existing /app/ assets and needs no service worker.
bootstrap = (
    bootstrap[: bootstrap.rindex("_flutter.loader.load(")] + "_flutter.loader.load();\n"
)
(target / f"bootstrap.{digest}.js").write_text(bootstrap)
launcher = Path(__file__).with_name("web_entry.js")
shutil.copy2(launcher, target / "entry.js")
index = app / "index.html"
html = index.read_text()
pattern = r'<script src="(flutter_bootstrap\.js\?release=[a-f0-9]+)" async></script>'
tag = (
    r'<script src="school-login/entry.js" data-app="\1" '
    f'data-school="school-login/bootstrap.{digest}.js" async></script>'
)
html, count = re.subn(pattern, tag, html)
if count != 1:
    raise ValueError("Expected one deployed Flutter bootstrap")
index.write_text(html)
