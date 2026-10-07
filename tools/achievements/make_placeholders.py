#!/usr/bin/env python3
"""Заглушки картинок достижений: assets/images/achievements/<id>_<level>.png.

Пока настоящие значки не нарисованы, приложение показывает эти. Готовую
картинку кладут под тем же именем поверх заглушки — код менять не нужно.
У каждого достижения своя форма и свой символ (чтобы сетка на Профиле не
была рядом одинаковых щитов), металл зависит от уровня. Список порогов —
зеркало lib/data/models/achievement.dart; поменяли пороги там — поправьте
BADGES и перезапустите скрипт.

    python3 tools/achievements/make_placeholders.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/images/achievements"
FONT = ROOT / "assets/fonts/Onest-ExtraBold.ttf"
SIZE = 512
C = SIZE / 2

# id → (форма, символ, подписи четырёх уровней: число и слово).
BADGES = {
    "streak": ("shield", "flame", [("3", "ДНЯ"), ("7", "ДНЕЙ"), ("14", "ДНЕЙ"), ("30", "ДНЕЙ")]),
    "coverage": ("circle", "book", [("100", "ВОПРОСОВ"), ("300", "ВОПРОСОВ"), ("500", "ВОПРОСОВ"), ("800", "ВОПРОСОВ")]),
    "tickets": ("ticket", "ticket", [("1", "БИЛЕТ"), ("10", "БИЛЕТОВ"), ("20", "БИЛЕТОВ"), ("40", "БИЛЕТОВ")]),
    "attempts": ("hexagon", "bolt", [("100", "ОТВЕТОВ"), ("500", "ОТВЕТОВ"), ("1000", "ОТВЕТОВ"), ("3000", "ОТВЕТОВ")]),
    "exams": ("octagon", "cap", [("1", "ЭКЗАМЕН"), ("3", "ЭКЗАМЕНА"), ("5", "ЭКЗАМЕНОВ"), ("10", "ЭКЗАМЕНОВ")]),
    "flawless": ("rosette", "star", [("1", "БЕЗ ОШИБОК"), ("3", "БЕЗ ОШИБОК"), ("5", "БЕЗ ОШИБОК"), ("10", "БЕЗ ОШИБОК")]),
    "mistakes": ("square", "check", [("10", "ИСПРАВЛЕНО"), ("50", "ИСПРАВЛЕНО"), ("100", "ИСПРАВЛЕНО"), ("200", "ИСПРАВЛЕНО")]),
    "rank": ("decagon", "trophy", [("100", "ТОП"), ("10", "ТОП"), ("3", "ТОП"), ("1", "МЕСТО")]),
    "game": ("pentagon", "wheel", [("1000", "ОЧКОВ"), ("2500", "ОЧКОВ"), ("5000", "ОЧКОВ"), ("7500", "ОЧКОВ")]),
}

# Металл уровня: (светлый, тёмный). 1 бронза, 2 серебро, 3 золото, 4 платина.
METALS = [
    ((0xF0, 0xBC, 0x92), (0x9A, 0x5B, 0x34)),
    ((0xF4, 0xF6, 0xF9), (0x96, 0x9E, 0xAB)),
    ((0xFF, 0xE0, 0x80), (0xC2, 0x86, 0x1C)),
    ((0xE2, 0xEE, 0xFF), (0x5F, 0x82, 0xC4)),
]


def regular(n: int, r: float, rot: float = -math.pi / 2) -> list:
    return [(C + r * math.cos(rot + k * 2 * math.pi / n), C + r * math.sin(rot + k * 2 * math.pi / n))
            for k in range(n)]


def outline(shape: str, inset: float) -> list:
    r = C * (0.94 - inset)
    if shape == "shield":
        return [(C - r * .84, C - r * .9), (C + r * .84, C - r * .9), (C + r * .84, C + r * .2),
                (C, C + r), (C - r * .84, C + r * .2)]
    if shape == "circle":
        return regular(96, r * .97)
    if shape == "hexagon":
        return regular(6, r, rot=0)
    if shape == "octagon":
        return regular(8, r, rot=math.pi / 8)
    if shape == "decagon":
        return regular(10, r, rot=math.pi / 10)
    if shape == "pentagon":
        return regular(5, r * 1.02)
    if shape == "rosette":  # 16 зубцов
        return [(C + (r if k % 2 == 0 else r * .86) * math.cos(k * math.pi / 16),
                 C + (r if k % 2 == 0 else r * .86) * math.sin(k * math.pi / 16)) for k in range(32)]
    if shape == "square":  # скруглённый квадрат
        pts, R, h = [], r * .28, r * .86
        for cx, cy, a0 in [(C + h - R, C - h + R, -90), (C + h - R, C + h - R, 0),
                           (C - h + R, C + h - R, 90), (C - h + R, C - h + R, 180)]:
            pts += [(cx + R * math.cos(math.radians(a0 + t)), cy + R * math.sin(math.radians(a0 + t)))
                    for t in range(0, 91, 10)]
        return pts
    if shape == "ticket":  # прямоугольник с вырезами по бокам
        w, h, n = r * .95, r * .72, r * .2
        pts = [(C - w, C - h), (C + w, C - h)]
        pts += [(C + w - n * math.sin(math.radians(t)), C + n * -math.cos(math.radians(t)))
                for t in range(0, 181, 15)]
        pts += [(C + w, C + h), (C - w, C + h)]
        pts += [(C - w + n * math.sin(math.radians(t)), C + n * math.cos(math.radians(t)))
                for t in range(0, 181, 15)]
        return pts
    raise ValueError(shape)


def gradient(light, dark) -> Image.Image:
    """Ровный диагональный градиент: светлый угол сверху слева."""
    import numpy as np
    t = (np.add.outer(np.arange(SIZE), np.arange(SIZE)) / (2 * (SIZE - 1)))[..., None]
    rgb = np.array(light) + (np.array(dark) - np.array(light)) * t
    return Image.fromarray(rgb.astype("uint8")).convert("RGBA")


def symbol(d: ImageDraw.ImageDraw, kind: str, cx: float, cy: float, s: float, ink) -> None:
    """Символ достижения в квадрате ±s вокруг (cx, cy)."""
    if kind == "flame":
        outer = [(0, -1), (.3, -.55), (.62, -.12), (.72, .35), (.52, .78), (.2, .98), (-.2, .98),
                 (-.55, .76), (-.72, .32), (-.6, -.12), (-.38, .1), (-.3, -.35)]
        d.polygon([(cx + x * s, cy + y * s) for x, y in outer], fill=ink)
        inner = [(.02, -.12), (.25, .22), (.33, .55), (.15, .8), (-.15, .8), (-.32, .55), (-.22, .28)]
        d.polygon([(cx + x * s, cy + y * s) for x, y in inner], fill=(255, 255, 255, 110))
    elif kind == "book":
        w = 12
        d.polygon([(cx, cy - s * .45), (cx - s, cy - s * .7), (cx - s, cy + s * .55), (cx, cy + s * .8)], fill=ink)
        d.polygon([(cx, cy - s * .45), (cx + s, cy - s * .7), (cx + s, cy + s * .55), (cx, cy + s * .8)], fill=ink)
        d.line([(cx, cy - s * .45), (cx, cy + s * .8)], fill=(255, 255, 255, 90), width=w)
    elif kind == "ticket":
        d.rounded_rectangle([cx - s, cy - s * .6, cx + s, cy + s * .6], radius=s * .18, fill=ink)
        for x in (cx - s, cx + s):
            d.ellipse([x - s * .22, cy - s * .22, x + s * .22, cy + s * .22], fill=(0, 0, 0, 0))
        d.line([(cx + s * .35, cy - s * .45), (cx + s * .35, cy + s * .45)], fill=(255, 255, 255, 110), width=8)
    elif kind == "bolt":
        d.polygon([(cx + s * .25, cy - s), (cx - s * .6, cy + s * .15), (cx - s * .05, cy + s * .15),
                   (cx - s * .3, cy + s), (cx + s * .6, cy - s * .2), (cx + s * .05, cy - s * .2)], fill=ink)
    elif kind == "cap":
        d.polygon([(cx, cy - s * .75), (cx + s * 1.05, cy - s * .2), (cx, cy + s * .35), (cx - s * 1.05, cy - s * .2)], fill=ink)
        d.chord([cx - s * .6, cy - s * .35, cx + s * .6, cy + s * .75], 0, 180, fill=ink)
        d.line([(cx + s * .85, cy - s * .2), (cx + s * .85, cy + s * .55)], fill=ink, width=10)
        d.ellipse([cx + s * .74, cy + s * .5, cx + s * .96, cy + s * .72], fill=ink)
    elif kind == "star":
        pts = [(cx + (s if k % 2 == 0 else s * .42) * math.cos(-math.pi / 2 + k * math.pi / 5),
                cy + (s if k % 2 == 0 else s * .42) * math.sin(-math.pi / 2 + k * math.pi / 5)) for k in range(10)]
        d.polygon(pts, fill=ink)
    elif kind == "check":
        d.line([(cx - s * .8, cy), (cx - s * .2, cy + s * .6), (cx + s * .85, cy - s * .6)], fill=ink,
               width=int(s * .38), joint="curve")
    elif kind == "trophy":
        d.polygon([(cx - s * .62, cy - s * .8), (cx + s * .62, cy - s * .8), (cx + s * .5, cy + s * .1),
                   (cx + s * .2, cy + s * .42), (cx - s * .2, cy + s * .42), (cx - s * .5, cy + s * .1)], fill=ink)
        for sx in (-1, 1):
            d.arc([cx + sx * s * .55 - s * .45, cy - s * .7, cx + sx * s * .55 + s * .45, cy], 90 if sx < 0 else -90,
                  270 if sx < 0 else 90, fill=ink, width=int(s * .16))
        d.rectangle([cx - s * .1, cy + s * .4, cx + s * .1, cy + s * .72], fill=ink)
        d.rounded_rectangle([cx - s * .5, cy + s * .7, cx + s * .5, cy + s * .95], radius=s * .1, fill=ink)
    elif kind == "wheel":
        t = s * .22
        d.ellipse([cx - s, cy - s, cx + s, cy + s], outline=ink, width=int(t))
        d.ellipse([cx - s * .28, cy - s * .28, cx + s * .28, cy + s * .28], fill=ink)
        for a in (90, 210, 330):
            ra = math.radians(a)
            d.line([(cx, cy), (cx + s * .85 * math.cos(ra), cy + s * .85 * math.sin(ra))], fill=ink, width=int(t * .8))


def badge(shape: str, kind: str, level: int, number: str, word: str) -> Image.Image:
    light, dark = METALS[level - 1]
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    def layer(inset: float, fill: Image.Image) -> Image.Image:
        mask = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(mask).polygon(outline(shape, inset), fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(1.2))
        out.paste(fill, (0, 0), mask)
        return mask

    layer(0.0, gradient(dark, light))           # кант
    field = layer(0.08, gradient(light, dark))  # поле

    glare = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glare).polygon(
        [(SIZE * .58, 0), (SIZE * .7, 0), (SIZE * .3, SIZE), (SIZE * .18, SIZE)], fill=(255, 255, 255, 50))
    out.paste(Image.alpha_composite(out, glare), (0, 0), field)

    ink = tuple(max(0, v - 70) for v in dark) + (255,)
    sym = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    symbol(ImageDraw.Draw(sym), kind, C, SIZE * .36, SIZE * .13, ink)
    out.alpha_composite(sym)

    d = ImageDraw.Draw(out)
    size = 104 if len(number) <= 3 else 84
    num_font = ImageFont.truetype(str(FONT), size)
    word_font = ImageFont.truetype(str(FONT), 30 if len(word) <= 8 else 24)
    ny = SIZE * .6
    d.text((C + 3, ny + 3), number, font=num_font, anchor="mm", fill=(255, 255, 255, 110))
    d.text((C, ny), number, font=num_font, anchor="mm", fill=ink)
    d.text((C, ny + size * .62), word, font=word_font, anchor="mm", fill=ink)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for key, (shape, kind, levels) in BADGES.items():
        for i, (number, word) in enumerate(levels, start=1):
            badge(shape, kind, i, number, word).save(OUT / f"{key}_{i}.png", optimize=True)
    print(f"{sum(len(v[2]) for v in BADGES.values())} заглушек → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
