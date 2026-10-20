#!/usr/bin/env python3
"""Export the app's branding assets from one square image, without repainting it.

Requires Pillow, Flutter/Dart and cwebp. Run from any directory:
    python3 tools/app_icons/generate.py --source /path/to/new-icon.jpg
    python3 tools/app_icons/generate.py  # reuse assets/images/app_icon.png
"""

import argparse
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "assets/images/app_icon.png"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=MASTER)
    args = parser.parse_args()
    image = ImageOps.exif_transpose(Image.open(args.source)).convert("RGB")
    if image.width != image.height:
        parser.error("Use a square source image; icons must not be cropped.")

    def png(relative, size):
        target = ROOT / relative
        image.resize((size, size), Image.Resampling.LANCZOS).save(
            target, optimize=True
        )

    png("assets/images/app_icon.png", 512)
    for relative in [
        "assets/images/google_play_icon_512.png",
        "store_assets/app_icon_512.png",
        "rustore_assets/icon_512.png",
        "game_godot/icon.png",
        "web/icons/Icon-512.png",
        "web/icons/Icon-maskable-512.png",
        "web_landing/ru/assets/icon-512.png",
    ]:
        shutil.copyfile(MASTER, ROOT / relative)

    for relative, size in [
        ("web/favicon.png", 64),
        ("web/icons/favicon.png", 64),
        ("web/icons/apple-touch-icon.png", 180),
        ("web/icons/Icon-192.png", 192),
        ("web/icons/Icon-maskable-192.png", 192),
        ("web_landing/ru/assets/favicon.png", 64),
        ("web_landing/ru/assets/apple-touch-icon.png", 180),
        ("web_landing/ru/assets/icon-192.png", 192),
    ]:
        png(relative, size)

    # Keep the established Android mask margin: 512 px on a 768 px canvas.
    foreground = Image.new("RGBA", (768, 768), (0, 0, 0, 0))
    foreground.paste(image.resize((512, 512), Image.Resampling.LANCZOS), (128, 128))
    foreground.save(ROOT / "assets/images/app_icon_foreground.png", optimize=True)
    subprocess.run([
        "cwebp", "-quiet", "-q", "88", "-resize", "192", "192",
        str(MASTER), "-o", str(ROOT / "assets/images/default_avatar.webp"),
    ], check=True)

    # Preserve the existing iPhone/iPad catalogue, including legacy sizes.
    catalog = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((catalog / "Contents.json").read_text())
    for entry in contents["images"]:
        if "filename" not in entry:
            continue
        width = float(entry["size"].split("x")[0])
        scale = float(entry["scale"].rstrip("x"))
        png((catalog / entry["filename"]).relative_to(ROOT), round(width * scale))

    dart = shutil.which("dart") or str(Path.home() / "flutter/bin/dart")
    subprocess.run([dart, "run", "flutter_launcher_icons"], cwd=ROOT, check=True)
    # The launcher generator detects the ru flavor and skips the main fallback.
    flavor = ROOT / "android/app/src/ru/res"
    fallback = ROOT / "android/app/src/main/res"
    paths = [*flavor.glob("*/ic_launcher.png"),
             *flavor.glob("*/ic_launcher_foreground.png"),
             flavor / "mipmap-anydpi-v26/ic_launcher.xml"]
    for source in paths:
        target = fallback / source.relative_to(flavor)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    print("Updated iOS, Android, web, stores, Godot and default avatar icons.")


if __name__ == "__main__":
    main()
