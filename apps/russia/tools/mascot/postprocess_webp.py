#!/usr/bin/env python3
"""Remove the baked floor shadow and make colours brighter, in place.

Applies to every delivery WebP in assets/mascot/raster/ (animations and
posters) and refreshes bytes/sha256 in manifest.json. Idempotent for the
shadow, but NOT for the colour boost: run it once on freshly encoded files.
"""
from __future__ import annotations
import hashlib, json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageSequence

DIR = Path(__file__).resolve().parents[2] / "assets/mascot/raster"


def fix(frame: Image.Image) -> Image.Image:
    a = np.array(frame.convert("RGBA")).astype(np.int16)
    rgb, al = a[..., :3], a[..., 3]
    sat = rgb.max(-1) - rgb.min(-1)
    ys = np.arange(a.shape[0])[:, None]
    # Shadow = grey, translucent, below the cone body.
    al = np.where((sat < 40) & (al < 240) & (ys > a.shape[0] * 0.62), 0, al)
    img = Image.fromarray(np.dstack([rgb, al]).astype(np.uint8))
    r, g, b, alpha = img.split()
    c = Image.merge("RGB", (r, g, b))
    # Gentle vibrance: richer colours without lifting highlights.
    c = ImageEnhance.Color(c).enhance(1.18)
    c = ImageEnhance.Contrast(c).enhance(1.03)
    return Image.merge("RGBA", (*c.split(), alpha))


def main():
    manifest_path = DIR / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for v in manifest["variants"]:
        path = DIR / v["file"]
        with Image.open(path) as im:
            durations = [f.info.get("duration", 0) for f in ImageSequence.Iterator(im)]
            frames = [fix(f.copy()) for f in ImageSequence.Iterator(im)]
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations,
                       loop=0, minimize_size=True, lossless=False, quality=v["quality"],
                       alpha_quality=100, method=v["compressionMethod"], background=(0, 0, 0, 0))
        data = path.read_bytes()
        v["bytes"], v["sha256"] = len(data), hashlib.sha256(data).hexdigest()
        poster = DIR / v["poster"]
        with Image.open(poster) as im:
            fix(im).save(poster, lossless=True, exact=True, method=6)
        v["posterBytes"] = poster.stat().st_size
        print(path.name, v["bytes"], len(frames))
    manifest["shadow"] = "removed in postprocess_webp.py; no background baked into frames"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
