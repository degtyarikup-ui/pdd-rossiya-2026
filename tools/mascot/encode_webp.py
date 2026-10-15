#!/usr/bin/env python3
"""Encode transparent 24/30 fps mascot variants from deterministic RGBA renders.

Requires Pillow with its libwebp animation encoder. Temporary PNGs
remain in ignored output/; only delivery WebP/posters/manifest enter assets/.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, features
import PIL

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "output/mascot/webp-source"
DESTINATION = ROOT / "assets/mascot/raster"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quality", type=int, help="Override RGB quality for all variants; default: 70 for 384/30, 82 for others")
    parser.add_argument("--method", type=int, help="Override compression effort for all variants; default: 5 for 384/30, 4 for others")
    args = parser.parse_args()
    if args.quality is not None and not 0 <= args.quality <= 100:
        parser.error("quality must be between 0 and 100")
    if args.method is not None and not 0 <= args.method <= 6:
        parser.error("method must be between 0 and 6")
    if not features.check("webp"):
        raise SystemExit("Pillow was built without libwebp support")
    source = json.loads((SOURCE / "source.json").read_text())
    DESTINATION.mkdir(parents=True, exist_ok=True)
    variants = []
    for width in (384, 256):
        # Downsample in premultiplied alpha to prevent bright/dark edge halos.
        frame_directory = SOURCE / str(width)
        frame_directory.mkdir(exist_ok=True)
        for file in sorted(SOURCE.glob("frame-*.png")):
            destination = frame_directory / file.name
            if width == source["width"]:
                shutil.copyfile(file, destination)
            else:
                with Image.open(file) as image:
                    image.convert("RGBa").resize((width,width),Image.Resampling.LANCZOS).convert("RGBA").save(destination)
        poster_name = f"cone-juggling-poster-{width}.webp"
        with Image.open(frame_directory / "frame-0000.png") as poster:
            poster.save(DESTINATION / poster_name,lossless=True,exact=True,method=6)
        for fps in (30,24):
            # The integrated loader keeps every 384 px / 30 fps frame and
            # exact alpha, while moderate RGB compression saves about 20%.
            loader = width == 384 and fps == 30
            quality = args.quality if args.quality is not None else (70 if loader else 82)
            method = args.method if args.method is not None else (5 if loader else 4)
            frames = source["frames"][str(fps)]
            name = f"cone-juggling-{width}-{fps}.webp"
            # Offline encoding can hold source images; playback/probes decode
            # sequentially and never use this frame list inside the application.
            images = []
            try:
                for frame in frames:
                    with Image.open(frame_directory / frame["file"]) as image:
                        images.append(image.copy())
                images[0].save(DESTINATION / name,save_all=True,append_images=images[1:],
                    duration=[frame["durationMs"] for frame in frames],loop=0,
                    minimize_size=True,lossless=False,quality=quality,
                    alpha_quality=100,method=method,background=(0,0,0,0))
            finally:
                for image in images:
                    image.close()
            data = (DESTINATION / name).read_bytes()
            variants.append({"id":f"{width}-{fps}","file":name,"width":width,"height":width,
                             "fps":fps,"frames":len(frames),"durationMs":sum(f["durationMs"] for f in frames),
                             "bytes":len(data),"sha256":hashlib.sha256(data).hexdigest(),
                             "poster":poster_name,"posterBytes":(DESTINATION/poster_name).stat().st_size,
                             "quality":quality,"alphaQuality":100,"compressionMethod":method})
            print(f"{width}px / {fps} fps: {len(data):,} bytes",flush=True)
    manifest = {"version":1,"durationSeconds":source["durationMs"]/1000,"transparent":True,
                "recommended":"384-30","variants":variants,
                "sourceModelSha256":source["modelSha256"],
                "source":"tools/mascot/render_webp_frames.cjs + encode_webp.py",
                "encoder":f"Pillow {PIL.__version__} / libwebp {features.version('webp')}",
                "shadow":"black with alpha; no background baked into frames"}
    (DESTINATION/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")


if __name__ == "__main__":
    main()
