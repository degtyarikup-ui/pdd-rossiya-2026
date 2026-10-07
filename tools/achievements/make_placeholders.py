#!/usr/bin/env python3
"""Заглушки картинок достижений: assets/images/achievements/<id>_<level>.png.

Пока настоящие значки не нарисованы, приложение показывает эти. Готовую
картинку кладут под тем же именем поверх заглушки — код менять не нужно.
Список достижений и порогов — зеркало lib/data/models/achievement.dart;
поменяли пороги там — поправьте BADGES и перезапустите скрипт.

    python3 tools/achievements/make_placeholders.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/images/achievements"
FONT = ROOT / "assets/fonts/Onest-ExtraBold.ttf"
SIZE = 512

# id → подписи четырёх уровней (число, слово под ним).
BADGES = {
    "streak": [("3", "ДНЯ"), ("7", "ДНЕЙ"), ("14", "ДНЕЙ"), ("30", "ДНЕЙ")],
    "coverage": [("100", "ВОПРОСОВ"), ("300", "ВОПРОСОВ"), ("500", "ВОПРОСОВ"), ("800", "ВОПРОСОВ")],
    "tickets": [("1", "БИЛЕТ"), ("10", "БИЛЕТОВ"), ("20", "БИЛЕТОВ"), ("40", "БИЛЕТОВ")],
    "attempts": [("100", "ОТВЕТОВ"), ("500", "ОТВЕТОВ"), ("1000", "ОТВЕТОВ"), ("3000", "ОТВЕТОВ")],
    "exams": [("1", "ЭКЗАМЕН"), ("3", "ЭКЗАМЕНА"), ("5", "ЭКЗАМЕНОВ"), ("10", "ЭКЗАМЕНОВ")],
    "flawless": [("1", "БЕЗ ОШИБОК"), ("3", "БЕЗ ОШИБОК"), ("5", "БЕЗ ОШИБОК"), ("10", "БЕЗ ОШИБОК")],
    "mistakes": [("10", "ИСПРАВЛЕНО"), ("50", "ИСПРАВЛЕНО"), ("100", "ИСПРАВЛЕНО"), ("200", "ИСПРАВЛЕНО")],
    "game": [("1000", "ОЧКОВ"), ("2500", "ОЧКОВ"), ("5000", "ОЧКОВ"), ("7500", "ОЧКОВ")],
}

# Металл уровня: (светлый, тёмный). 1 бронза, 2 серебро, 3 золото, 4 платина.
METALS = [
    ((0xE8, 0xB0, 0x86), (0x9A, 0x5B, 0x34)),
    ((0xF2, 0xF4, 0xF7), (0x9A, 0xA1, 0xAD)),
    ((0xFF, 0xDD, 0x7A), (0xC2, 0x86, 0x1C)),
    ((0xDD, 0xEB, 0xFF), (0x6F, 0x8F, 0xC9)),
]


def shape(level: int, inset: float) -> list[tuple[float, float]]:
    """Форма значка растёт с уровнем: щит → круг → шестиугольник → ромб."""
    c, r = SIZE / 2, SIZE / 2 * (0.92 - inset)
    if level == 1:  # щит
        return [(c - r * 0.82, c - r * 0.9), (c + r * 0.82, c - r * 0.9),
                (c + r * 0.82, c + r * 0.25), (c, c + r), (c - r * 0.82, c + r * 0.25)]
    if level == 2:  # круг (многоугольник с большим числом сторон)
        import math
        return [(c + r * math.cos(a / 64 * 2 * math.pi), c + r * math.sin(a / 64 * 2 * math.pi))
                for a in range(64)]
    if level == 3:  # шестиугольник
        import math
        return [(c + r * math.cos(math.pi / 6 + k * math.pi / 3),
                 c + r * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]  # ромб


def gradient(light, dark) -> Image.Image:
    """Диагональный металлический градиент: светлый угол сверху слева."""
    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * SIZE)
            px[x, y] = tuple(int(light[i] + (dark[i] - light[i]) * t) for i in range(3)) + (255,)
    return img


def badge(level: int, number: str, word: str) -> Image.Image:
    light, dark = METALS[level - 1]
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    def layer(inset: float, fill: Image.Image) -> None:
        mask = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(mask).polygon(shape(level, inset), fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(1.2))
        out.paste(fill, (0, 0), mask)

    layer(0.0, gradient(dark, light))     # кант: градиент наоборот
    layer(0.07, gradient(light, dark))    # поле значка

    # Блик — косая полоса, как на примере.
    glare = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glare).polygon(
        [(SIZE * 0.55, 0), (SIZE * 0.68, 0), (SIZE * 0.32, SIZE), (SIZE * 0.19, SIZE)],
        fill=(255, 255, 255, 46))
    clip = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(clip).polygon(shape(level, 0.07), fill=255)
    out.paste(Image.alpha_composite(out, glare), (0, 0), clip)

    draw = ImageDraw.Draw(out)
    ink = tuple(max(0, v - 60) for v in dark)
    size = 190 if len(number) <= 2 else (150 if len(number) == 3 else 118)
    num_font = ImageFont.truetype(str(FONT), size)
    word_font = ImageFont.truetype(str(FONT), 44 if len(word) <= 8 else 34)
    cy = SIZE * (0.44 if level == 1 else 0.46)
    draw.text((SIZE / 2 + 4, cy + 4), number, font=num_font, anchor="mm", fill=(255, 255, 255, 120))
    draw.text((SIZE / 2, cy), number, font=num_font, anchor="mm", fill=ink)
    draw.text((SIZE / 2, cy + size * 0.62), word, font=word_font, anchor="mm", fill=ink)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for key, levels in BADGES.items():
        for i, (number, word) in enumerate(levels, start=1):
            badge(i, number, word).save(OUT / f"{key}_{i}.png", optimize=True)
    print(f"{sum(map(len, BADGES.values()))} заглушек → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
