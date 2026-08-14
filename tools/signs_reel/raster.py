#!/usr/bin/env python3
"""Растеризация SVG дорожных знаков в RGBA-картинки.

Знаки в ассетах — SVG, часть из них описывает заливки CSS-классами внутри
`<style>`. Такой файл нужно растеризовать движком, который эти стили понимает,
иначе знак приезжает чёрным силуэтом (та же грабля, что и в приложении —
см. tools/inline_svg_styles.py). Поэтому результат каждой растеризации
проверяется на «чёрный силуэт» и при провале пробуется следующий движок.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

CACHE_DIR = Path(__file__).resolve().parent / ".cache" / "signs"


class RasterError(RuntimeError):
    pass


def _import_cairosvg():
    """cairocffi не находит libcairo у /usr/bin/python3.

    SIP вырезает DYLD_FALLBACK_LIBRARY_PATH у системного python, поэтому
    ctypes.util.find_library('cairo') возвращает None, хотя brew-библиотека
    на месте. Экспорт DYLD_* не помогает — подменяем поиск точечно.
    """
    import ctypes.util

    brew_cairo = "/opt/homebrew/lib/libcairo.2.dylib"
    if Path(brew_cairo).exists():
        original = ctypes.util.find_library

        def patched(name):
            if name in ("cairo", "cairo-2", "libcairo-2"):
                return brew_cairo
            return original(name)

        ctypes.util.find_library = patched
    import cairosvg

    return cairosvg


def _via_cairosvg(svg: Path, out: Path, size: int) -> bool:
    try:
        cairosvg = _import_cairosvg()
    except (ImportError, OSError):
        return False
    cairosvg.svg2png(
        url=str(svg),
        write_to=str(out),
        output_width=size,
        output_height=size,
        background_color=None,
    )
    return out.exists()


def _via_rsvg(svg: Path, out: Path, size: int) -> bool:
    exe = shutil.which("rsvg-convert")
    if not exe:
        return False
    subprocess.run(
        [exe, "-w", str(size), "-h", str(size), "-a", "-f", "png", "-o", str(out), str(svg)],
        check=True,
        capture_output=True,
    )
    return out.exists()


def _via_inkscape(svg: Path, out: Path, size: int) -> bool:
    exe = shutil.which("inkscape")
    if not exe:
        return False
    subprocess.run(
        [exe, str(svg), "--export-type=png", f"--export-filename={out}",
         f"--export-width={size}", f"--export-height={size}"],
        check=True,
        capture_output=True,
    )
    return out.exists()


def _via_qlmanage(svg: Path, out: Path, size: int) -> bool:
    """Штатный macOS-рендер: WebKit, значит понимает CSS внутри SVG."""
    exe = shutil.which("qlmanage")
    if not exe:
        return False
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            [exe, "-t", "-s", str(size), "-o", tmp, str(svg)],
            check=True, capture_output=True,
        )
        produced = list(Path(tmp).glob("*.png"))
        if not produced:
            return False
        shutil.copy(produced[0], out)
    return out.exists()


# qlmanage последним: он рисует цвет верно, но заливает фон белым и не
# соблюдает запрошенный размер — годится только как аварийный выход.
ENGINES = [
    ("cairosvg", _via_cairosvg),
    ("rsvg-convert", _via_rsvg),
    ("inkscape", _via_inkscape),
    ("qlmanage", _via_qlmanage),
]


def _looks_monochrome(img: Image.Image) -> bool:
    """Правда ли, что от знака остался чёрный силуэт.

    Дорожные знаки цветные почти всегда; исключения — «конец всех ограничений»
    и подобные чёрно-белые. Поэтому чёрным силуэтом считаем картинку, где
    непрозрачные пиксели тёмные и при этом почти нет белого: у настоящего
    ч/б знака белого поля много.
    """
    small = img.convert("RGBA").resize((64, 64))
    px = [p for p in small.getdata() if p[3] > 64]
    if not px:
        return True
    dark = sum(1 for r, g, b, _ in px if r < 60 and g < 60 and b < 60)
    light = sum(1 for r, g, b, _ in px if r > 200 and g > 200 and b > 200)
    return dark / len(px) > 0.85 and light / len(px) < 0.05


def rasterize(svg_path: Path, size: int = 512) -> Image.Image:
    """SVG → RGBA-картинка `size`×`size` с прозрачным фоном (с кэшем на диске)."""
    svg_path = Path(svg_path)
    if not svg_path.exists():
        raise RasterError(f"нет файла знака: {svg_path}")

    digest = hashlib.sha1(f"{svg_path}|{size}".encode()).hexdigest()[:16]
    cached = CACHE_DIR / f"{digest}.png"
    if cached.exists():
        return Image.open(cached).convert("RGBA")

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    fallback: Image.Image | None = None

    for name, engine in ENGINES:
        out = CACHE_DIR / f"{digest}.{name}.png"
        try:
            if not engine(svg_path, out, size):
                continue
        except Exception as exc:  # движок есть, но упал на этом файле
            errors.append(f"{name}: {exc}")
            continue

        img = Image.open(out).convert("RGBA")
        out.unlink(missing_ok=True)
        if _looks_monochrome(img):
            errors.append(f"{name}: знак вышел чёрным силуэтом")
            fallback = fallback or img
            continue
        img.save(cached)
        return img

    if fallback is not None:
        # Все движки дали тёмную картинку — вероятно, знак и правда ч/б.
        fallback.save(cached)
        return fallback

    raise RasterError(f"не удалось растеризовать {svg_path.name}: {'; '.join(errors) or 'нет движков'}")


def fit(img: Image.Image, box: int) -> Image.Image:
    """Вписывает знак в квадрат `box`, сохраняя пропорции по видимой части."""
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    k = box / max(w, h)
    return img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
