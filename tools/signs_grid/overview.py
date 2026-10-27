#!/usr/bin/env python3
"""Общий план ролика «Тест по знакам: 9 знаков, 4 варианта».

Кадр 1080×1920: сетка 3×3, под каждым знаком — четыре варианта с чекбоксами.
Все варианты — настоящие названия знаков из signs.json: дистрактор тоже
должен быть реальным знаком, иначе ролик учит несуществующему.

    /usr/bin/python3 -m tools.signs_grid.overview [--answers]
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw

from tools.signs_reel import config as C
from tools.signs_reel.frames import font, text_size
from tools.signs_reel.raster import rasterize

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / "assets" / "countries" / "ru"
OUT = REPO / "output" / "signs_grid"

# (номер знака, четыре варианта; верный — тот, что совпадает с названием знака)
QUIZ = [
    ("3.27", ["Стоянка запрещена", "Въезд запрещен", "Остановка запрещена", "Движение запрещено"]),
    ("1.15", ["Неровная дорога", "Скользкая дорога", "Крутой спуск", "Выброс гравия"]),
    ("1.20.1", ["Сужение дороги", "Двустороннее движение", "Ограничение ширины", "Неровная дорога"]),
    ("2.4", ["Главная дорога", "Въезд запрещен", "Конец главной дороги", "Уступите дорогу"]),
    ("3.18.2", ["Разворот запрещен", "Поворот налево запрещен", "Движение налево", "Поворот направо запрещен"]),
    ("4.3", ["Место для разворота", "Разворот запрещен", "Движение прямо", "Круговое движение"]),
    ("1.21", ["Реверсивное движение", "Сужение дороги", "Двустороннее движение", "Обгон запрещен"]),
    ("5.21", ["Пешеходная зона", "Жилая зона", "Дети", "Конец жилой зоны"]),
    ("3.20", ["Разворот запрещен", "Ограничение ширины", "Движение запрещено", "Обгон запрещен"]),
]

# ── Геометрия ──────────────────────────────────────────────────────────────
HEADER_Y = 110
GRID_X = 30
GRID_Y = 250
COLS = 3
CELL_W = (C.W - 2 * GRID_X) // COLS      # 340
CELL_H = 440
GAP = 0
SIGN_BOX = 200
IMG_W = CELL_W - 36                      # картинка-кадр (регулировщик) во всю ширину клетки
HEADER = "ТЕСТ ПО ЗНАКАМ"
SIGN_TOP = 22
OPT_TOP = SIGN_TOP + SIGN_BOX + 22
OPT_STEP = 44
OPT_SIZE = 25
BOX = 24
LINE = (214, 222, 235)


def load_db() -> dict[str, dict]:
    raw = json.loads((ROOT / "questions" / "signs.json").read_text(encoding="utf-8"))
    return {item.get("number", n): item for items in raw.values() for n, item in items.items()}


def sign_image(item: dict, box: int) -> Image.Image:
    img = rasterize(ROOT / str(item["image"]).lstrip("./"), max(512, box * 2)).convert("RGBA")
    img = img.crop(img.getbbox())
    k = box / max(img.size)
    return img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)


@dataclass
class Cell:
    """Клетка сетки: картинка, четыре варианта и верный из них."""
    image: Callable[[int, int], Image.Image]   # (ширина, высота) → RGBA, вписанная в рамку
    options: list[str]
    answer: str


def sign_cells(quiz=None) -> list[Cell]:
    """Клетки теста по знакам. Все варианты — названия знаков из базы."""
    db = load_db()
    titles = {i["title"].strip().rstrip(".").lower() for i in db.values()}
    cells = []
    for number, options in (quiz or QUIZ):
        item = db[number]
        title = item["title"].strip().rstrip(".")
        assert title in options, f"{number}: верного ответа «{title}» нет среди вариантов"
        for o in options:
            assert o.lower() in titles, f"{number}: «{o}» — не название знака из базы"
        # Знак вписывается в квадрат по высоте рамки, а не растягивается на ширину.
        cells.append(Cell(lambda w, h, item=item: sign_image(item, min(w, h)), list(options), title))
    return cells


def cell_rect(i: int) -> tuple[int, int, int, int]:
    """Клетка i-го знака в координатах кадра 1080×1920."""
    x0 = GRID_X + (i % COLS) * CELL_W
    y0 = GRID_Y + 40 + (i // COLS) * CELL_H
    return x0, y0, x0 + CELL_W, y0 + CELL_H


def option_rows(image_h: int = SIGN_BOX) -> tuple[int, int]:
    """Верх первого варианта и шаг между вариантами при картинке высотой image_h.

    Картинка выше — варианты плотнее, но последний всегда кончается там же,
    где при знаке: под ним в видео идёт полоса времени.
    """
    top = SIGN_TOP + image_h + 22
    last = OPT_TOP + 3 * OPT_STEP
    return top, (last - top) / 3


def render(answered=False, scale: float = 1.0, cells: list[Cell] = None,
           header: str = HEADER, image_h: int = SIGN_BOX) -> Image.Image:
    """Кадр общего плана.

    answered — True (все ответы), False (ни одного) или множество индексов
    знаков, у которых ответ уже подсвечен. scale — во сколько раз крупнее
    рисовать: видео наезжает камерой на клетку, и при наезде в ~2,7 раза
    кадр 1:1 поплыл бы мылом.
    """
    cells = cells if cells is not None else sign_cells()
    if answered is True:
        answered = set(range(len(cells)))
    elif not answered:
        answered = set()

    def S(v: float) -> int:
        return round(v * scale)

    base = Image.new("RGB", (S(C.W), S(C.H)), C.ACCENT)
    d = ImageDraw.Draw(base)

    # Шапка — белый текст прямо на синем, без плашки
    head = header
    size = 84
    while font("black", size).getlength(head) > C.W - 2 * GRID_X - 20:
        size -= 2
    hf = font("black", S(size))
    hb = d.textbbox((0, 0), head, font=hf)
    hw, hh = hb[2] - hb[0], hb[3] - hb[1]
    d.text(((S(C.W) - hw) // 2 - hb[0], S(HEADER_Y + 40) - hh // 2 - hb[1]), head, font=hf,
           fill=C.WHITE)

    # Сетка
    rows = (len(cells) + COLS - 1) // COLS
    gx0, gy0 = GRID_X, GRID_Y + 40
    gx1, gy1 = gx0 + CELL_W * COLS, gy0 + CELL_H * rows
    d.rounded_rectangle((S(gx0), S(gy0), S(gx1), S(gy1)), radius=S(C.CARD_RADIUS), fill=C.WHITE)
    for c in range(1, COLS):
        x = S(gx0 + c * CELL_W)
        d.line((x, S(gy0), x, S(gy1)), fill=LINE, width=S(3))
    for r in range(1, rows):
        y = S(gy0 + r * CELL_H)
        d.line((S(gx0), y, S(gx1), y), fill=LINE, width=S(3))

    for i, cell in enumerate(cells):
        options, title = cell.options, cell.answer
        cx0, cy0, _, _ = cell_rect(i)
        img = cell.image(S(IMG_W), S(image_h))
        base.paste(img, (S(cx0) + (S(CELL_W) - img.width) // 2,
                         S(cy0 + SIGN_TOP) + (S(image_h) - img.height) // 2), img)
        opt_top, opt_step = option_rows(image_h)

        # Один кегль на клетку: если самый длинный вариант не влезает, мельчают
        # все четыре, иначе по разному кеглю угадывается «особенный» вариант.
        size = OPT_SIZE
        while max(font("medium", size).getlength(o) for o in options) > CELL_W - 18 - BOX - 12 - 10:
            size -= 1
        f = font("medium", S(size))
        for k, opt in enumerate(options):
            oy = cy0 + opt_top + k * opt_step
            bx = cx0 + 18
            right = i in answered and opt == title
            if right:
                d.rounded_rectangle((S(cx0 + 10), S(oy - 7), S(cx0 + CELL_W - 10), S(oy + BOX + 7)),
                                    radius=S(10), fill=C.GREEN_SURFACE)
            d.rounded_rectangle((S(bx), S(oy), S(bx + BOX), S(oy + BOX)), radius=S(5),
                                outline=C.GREEN if right else C.PRIMARY_TEXT,
                                fill=C.GREEN if right else C.WHITE, width=S(3))
            if right:
                d.line((S(bx + 5), S(oy + 12), S(bx + 10), S(oy + 18), S(bx + 19), S(oy + 6)),
                       fill=C.WHITE, width=S(4), joint="curve")
            tb = d.textbbox((0, 0), opt, font=f)
            d.text((S(bx + BOX + 12), S(oy + BOX / 2) - (tb[1] + tb[3]) // 2), opt, font=f,
                   fill=C.PRIMARY_TEXT)

    return base


def main() -> None:
    answers = "--answers" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / ("overview_answers.png" if answers else "overview.png")
    render(answers).save(path)
    print(path)


if __name__ == "__main__":
    main()
