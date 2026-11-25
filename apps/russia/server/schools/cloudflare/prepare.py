"""Assemble Worker assets and the Python project in the specified output directory."""

import shutil
import sys
from pathlib import Path

source = Path(__file__).resolve().parent
app = source.parent
product = app.parents[1]
target = Path(sys.argv[1]).resolve()
target.mkdir(parents=True, exist_ok=True)
for name in (
    "entry.py",
    "school-mail.mjs",
    "school-identity.mjs",
    "pyproject.toml",
    "pylock.toml",
    "wrangler.jsonc",
):
    shutil.copy2(source / name, target / name)
vendor = target / "python_modules"
if not (vendor / "django").is_dir():
    sys.exit("Run pywrangler sync in the output directory, then run prepare.py again.")
# Django and allauth ship dozens of translation catalogs. The school UI is Russian.
for package in ("django", "allauth"):
    for catalog in (vendor / package).rglob("*.po"):
        catalog.unlink()
    for catalog in (vendor / package).rglob("*.mo"):
        if catalog.parent.parent.name not in ("ru", "en"):
            catalog.unlink()
shutil.copytree(
    app / "portal",
    vendor / "portal",
    dirs_exist_ok=True,
    ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "test*.py", "static"),
)
public = target / "public"
assets = public / "assets"
assets.mkdir(parents=True, exist_ok=True)
landing = product / "web_landing/ru/assets"
for name in ("style.css", "icon-192.png", "favicon.png"):
    shutil.copy2(landing / name, assets / name)
shutil.copytree(landing / "fonts", assets / "fonts", dirs_exist_ok=True)
shutil.copytree(
    product / "assets/icons/auth", assets / "auth-icons", dirs_exist_ok=True
)
shutil.copytree(app / "portal/static/schools", assets / "schools", dirs_exist_ok=True)
(public / "art").mkdir(exist_ok=True)
shutil.copy2(product / "assets/images/onboarding_car.png", public / "art/car.png")
(public / "robots.txt").write_text("User-agent: *\nDisallow: /\n")

shutil.copytree(source / "app-links", public / ".well-known", dirs_exist_ok=True)
(public / "_headers").write_text(
    "/.well-known/apple-app-site-association\n  Content-Type: application/json\n"
)
