#!/usr/bin/env python3
"""Approved illustrated traffic-controller quiz: preview or narrated MP4.

python3 -m tools.signs_grid.regulator_illustrated --preview
python3 -m tools.signs_grid.regulator_illustrated

The approved character sheet is a source asset. Cropping/padding here only
places those illustrations into cards; it never redraws or mirrors a pose.
"""
from __future__ import annotations

import argparse
import functools
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image

from tools.signs_reel.build import Voice
from . import overview as O
from . import video as V

ROOT = Path(__file__).resolve().parent
SPEC = ROOT / "regulator_illustrated.json"
OUT = O.OUT / "regulator_illustrated"
IMAGE_H = 215


@functools.lru_cache(maxsize=1)
def specification() -> dict:
    data = json.loads(SPEC.read_text(encoding="utf-8"))
    answer_moves = [("none",), ("right",), ("right", "straight"),
                    ("left", "right", "straight", "uTurn")]
    for s in data["situations"]:
        if tuple(sorted(s["moves"])) != answer_moves[s["answerIndex"]]:
            raise ValueError(f"Answer mismatch: {s}")
    return data


@functools.lru_cache(maxsize=9)
def illustration(index: int) -> Image.Image:
    data = specification()
    s = data["situations"][index]
    with Image.open(ROOT / data["sheet"]) as sheet:
        if list(sheet.size) != data["sheetSize"]:
            raise ValueError("Character sheet dimensions changed; review crop rectangles")
        patch = sheet.convert("RGBA").crop(tuple(s["crop"]))
    # One physical scale and one baseline for all poses, including the raised
    # arm: trimming every figure independently would make its body smaller.
    frame = Image.new("RGBA", tuple(data["frameSize"]), "white")
    x = (frame.width - patch.width) // 2
    y = data["footBaseline"] - (s["feetY"] - s["crop"][1])
    frame.paste(patch, (x, y))
    return frame


def figure(index: int, w: int, h: int) -> Image.Image:
    im = illustration(index)
    k = min(w / im.width, h / im.height)
    return im.resize((round(im.width * k), round(im.height * k)), Image.Resampling.LANCZOS)


def cells() -> list[O.Cell]:
    data = specification()
    return [O.Cell(lambda w, h, i=i: figure(i, w, h), list(data["options"]),
                   data["options"][s["answerIndex"]])
            for i, s in enumerate(data["situations"])]


def voice_lines() -> list[Voice]:
    data = specification()
    return ([Voice("intro", data["intro"], Path())] +
            [Voice(f"sign{i}", c.answer + ".", Path()) for i, c in enumerate(cells())] +
            [Voice("outro", data["outro"], Path())])


def preview() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for answered, name in [(False, "overview"), (True, "answers")]:
        O.render(answered, cells=cells(), header=specification()["title"],
                 image_h=IMAGE_H).save(OUT / f"{name}.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--voice", default="Algenib")
    parser.add_argument("--out", type=Path, default=Path.home() / "Desktop" / "Тест — регулировщик.mp4")
    args = parser.parse_args()
    preview()
    if args.preview:
        print(OUT / "overview.png")
        return
    movie = OUT / "regulator.mp4"
    V.render_video(movie, args.voice, False, cells=cells(), lines=voice_lines(),
                   header=specification()["title"], image_h=IMAGE_H, workdir=OUT / ".work")
    # Put the MP4 index before media data so social platforms can stream it.
    final = OUT / "regulator-faststart.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(movie),
                    "-c", "copy", "-movflags", "+faststart", str(final)], check=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(final, args.out)
    if hashlib.sha256(final.read_bytes()).digest() != hashlib.sha256(args.out.read_bytes()).digest():
        raise RuntimeError("Desktop copy did not match rendered video")
    print(args.out)


if __name__ == "__main__":
    main()
