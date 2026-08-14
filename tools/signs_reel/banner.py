#!/usr/bin/env python3
"""Рекламная плашка в финале ролика — анимированный WebM с альфой.

Исходник (`banner.webm`) сделан вручную и лежит рядом с кодом. Он
раскодируется в PNG-последовательность один раз и потом читается с диска
покадрово: держать все кадры в памяти незачем — финал проходится один раз и
строго по порядку.

Альфу VP9 отдаёт только явно указанному декодеру `libvpx-vp9`; без него
ffmpeg вернёт кадр без прозрачности, и плашка приедет с чёрной подложкой.
"""

from __future__ import annotations

import functools
import subprocess
from pathlib import Path

from PIL import Image

from . import config as C

SOURCE = Path(__file__).resolve().parent / "banner.webm"
CACHE = Path(__file__).resolve().parent / ".cache" / "banner"


def _frames_dir(width: int) -> Path:
    return CACHE / f"w{width}"


def prepare(width: int = None) -> Path:
    """Раскодирует плашку в PNG-кадры нужной ширины (один раз)."""
    width = width or C.BANNER_W
    out = _frames_dir(width)
    if out.exists() and any(out.glob("*.png")):
        return out
    if not SOURCE.exists():
        raise SystemExit(f"нет файла плашки: {SOURCE}")

    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error",
         "-vcodec", "libvpx-vp9", "-i", str(SOURCE),
         "-vf", f"scale={width}:-1:flags=lanczos", "-r", str(C.FPS),
         "-pix_fmt", "rgba", str(out / "%04d.png")],
        check=True,
    )
    return out


@functools.lru_cache(maxsize=1)
def _files(width: int) -> tuple:
    return tuple(sorted(prepare(width).glob("*.png")))


@functools.lru_cache(maxsize=8)
def _load(path: str) -> Image.Image:
    return Image.open(path).convert("RGBA")


def frame(index: int, width: int = None) -> Image.Image:
    """Кадр плашки; после конца анимации держится последний."""
    width = width or C.BANNER_W
    files = _files(width)
    if not files:
        raise SystemExit("плашка не раскодировалась")
    return _load(str(files[min(index, len(files) - 1)]))


def draw(base: Image.Image, index: int, width: int = None) -> None:
    img = frame(index, width)
    base.paste(img, (C.W // 2 - img.width // 2, C.BANNER_CY - img.height // 2), img)
