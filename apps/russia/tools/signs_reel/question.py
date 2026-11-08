#!/usr/bin/env python3
"""Ролик «вопрос из билета»: один вопрос — одно видео.

    python3 -m tools.signs_reel.question --id <id вопроса>
    python3 -m tools.signs_reel.question --list

Отличия от формата со знаками: кадр строится вокруг иллюстрации вопроса,
диктор читает быстрее (вопрос и варианты — это уже много текста), а пауза на
размышление короче, потому что зритель к этому моменту уже всё прочитал.

Иллюстрация адаптируется под квадрат нейросетью (`qimage.py`) — кадр
достраивается вверх и вниз, боковые края не режутся. Шаг рискованный: модель
умеет и стереть служебную стрелку, и дорисовать несуществующие стрелки
траекторий с буквами «A» и «B». Поэтому каждый кадр кладётся рядом с
оригиналом в контактный лист и принимается глазами. Без ключа --ai-image
берётся исходная лента 1208×450, и панель дополняется её же размытым
продолжением.

После верного ответа ролик объясняет, почему он верный: текст берётся из
поля `comment` того же вопроса — это подсказка, которую видит пользователь
в приложении, а не сочинённое пояснение.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import warnings
import re
from dataclasses import dataclass, field
from pathlib import Path

warnings.filterwarnings("ignore")

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from . import audio, backgrounds, banner, config as C, frames, verify

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = Path.home() / "Desktop" / "pdd_reels"
WORK_DIR = Path(__file__).resolve().parent / ".work"
TTS_DIR = WORK_DIR / "tts_q"

ORDINALS = ["Первый", "Второй", "Третий", "Четвёртый", "Пятый"]

# Транслитерация для имён файлов: кириллица в названиях ломает часть
# загрузчиков и неудобна в командной строке.
TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}


def slugify(text: str, words: int = 4) -> str:
    """Короткий латинский слаг из первых слов вопроса."""
    out = []
    for word in re.sub(r"[^\w\s-]", " ", text.lower()).split()[:words]:
        out.append("".join(TRANSLIT.get(ch, ch if ch.isalnum() else "") for ch in word))
    return "-".join(filter(None, out))[:48]

# ── Раскладка кадра ────────────────────────────────────────────────────────
# Отступ сверху равен боковым: (1080 − 900) / 2 = 90.
PANEL_Y = 90
PANEL_SIDE = 900             # квадрат ровно по ширине вариантов ответа
PANEL_W_WIDE = 900           # для неадаптированной ленты 1208×450
PHOTO_INSET = 10             # рамка вокруг резкого кадра

BAR_UNDER_PANEL = 50         # от низа панели до полосы времени
EXPLAIN_GAP = 120            # от низа панели до блока разбора
Q_GAP_AFTER_BAR = 56         # от полосы времени до вопроса
OPT_GAP_TOP = 56             # от вопроса до первого варианта
CONTENT_BOTTOM = 1660        # ниже начинается интерфейс площадки
PANEL_MIN = 660              # меньше картинку ужимать уже некуда
# Пропорции, при которых кадр заполняет панель целиком: квадрат и 4:3.
PANEL_FILL_MIN, PANEL_FILL_MAX = 0.85, 1.45
Q_SIZE_MAX, Q_SIZE_MIN = 56, 38
OPT_W = 900                  # та же ширина, что у панели с картинкой
OPT_MIN_H = 110
OPT_GAP = 16
OPT_PAD_X = 34
OPT_TEXT_SIZE = 42
BADGE = 68                   # кружок с номером варианта

BAR_H = 30

# Полоса времени и подсветка ответа — ярче токенов приложения: в ленте
# соцсети приглушённые цвета не считываются с первого взгляда.
BRIGHT_GREEN = (0, 200, 83)
BRIGHT_GOLD = (255, 149, 0)
BRIGHT_RED = (235, 18, 18)   # #EB1212 — обводка и красная зона таймера
BAR_TRACK = (150, 195, 250)

# Блок объяснения после ответа
EXPL_SIZE = 36
EXPL_PAD = 34
EXPL_MAX_LINES = 7
SOURCE_SIZE = 30

CTA_BANNER_W = 820           # плашка в финале — по центру и чуть меньше

# ── Тайминги (сек) ─────────────────────────────────────────────────────────
T_QUESTION_TAIL = 0.35       # пауза после вопроса
T_OPTION_TAIL = 0.15         # пауза между вариантами — короткая, чтобы не тянуть
T_THINK = 4.0                # размышление
T_REVEAL_TAIL = 0.8
T_EXPLAIN_TAIL = 0.8
T_HIGHLIGHT = 0.8            # за сколько затемнение набирает силу
SPOTLIGHT_DIM = 0.62         # насколько гасим фон вокруг объекта
SPOTLIGHT_RADIUS = 26
SPOTLIGHT_FEATHER = 6
SPOTLIGHT_MIN_W = 0.22       # окно не меньше этой доли ширины панели
SPOTLIGHT_MIN_H = 0.16
T_OUTRO_TAIL = 1.2

# Объяснение длиннее этого зритель не дослушает, а ролик вылезет за минуту.
EXPLAIN_MAX_CHARS = 300

# Диктор для этого формата говорит быстрее: текста втрое больше, чем в
# роликах про знаки, и в прежнем темпе зритель заскучает.
CTA_TEXT = "Готовься к экзамену в нашем приложении."

VOICE_STYLE = (
    "Читай живо и в бодром темпе, как ведущий викторины: быстрее обычного, "
    "но разборчиво, без спешки в окончаниях. Произноси только заданный текст, "
    "ничего не добавляй."
)


@dataclass
class Question:
    id: str
    ticket: int
    text: str
    options: list
    correct: int
    image: Path
    comment: str


@dataclass
class Segment:
    kind: str
    start: int
    length: int
    index: int = -1

    @property
    def end(self) -> int:
        return self.start + self.length


@dataclass
class Voice:
    key: str
    text: str
    path: Path = field(default_factory=Path)
    samples: int = 0

    @property
    def seconds(self) -> float:
        return self.samples / C.SR


def load_questions(country: str = "ru") -> list:
    root = REPO / "assets" / "countries" / country
    raw = json.loads((root / "questions" / "questions_ab.json").read_text(encoding="utf-8"))
    out = []
    for ticket in raw["tickets"]:
        for q in ticket["questions"]:
            if not q.get("image"):
                continue
            image = root / "images" / "questions_ab" / f"{q['image']}.jpg"
            if not image.exists():
                continue
            correct = next((i for i, a in enumerate(q["answers"]) if a["correct"]), -1)
            if correct < 0:
                continue
            out.append(Question(
                id=q["id"], ticket=q.get("ticketNumber", ticket["number"]),
                text=q["question"].strip(),
                options=[a["text"].strip() for a in q["answers"]],
                correct=correct, image=image, comment=(q.get("comment") or "").strip(),
            ))
    return out


# ── Панель с иллюстрацией ──────────────────────────────────────────────────

def question_block(d: ImageDraw.ImageDraw, text: str) -> tuple:
    """Шрифт, строки и высота блока вопроса."""
    f, lines = frames.fit_text(d, text, "bold", C.W - 2 * C.SCREEN_PADDING,
                               Q_SIZE_MAX, Q_SIZE_MIN, max_lines=3)
    return f, lines, int(f.size * 1.18) * len(lines)


def panel_side_for(q_height: int, options_height: int, ratio: float = 1.0) -> int:
    """Ширина панели с картинкой — по остатку места под текст.

    Раньше все координаты были фиксированными, и трёхстрочный вопрос налезал
    на таймер сверху и упирался в ответы снизу. Теперь гибкая величина —
    картинка: она ужимается ровно настолько, чтобы текст встал свободно.
    """
    below = (BAR_UNDER_PANEL + BAR_H + Q_GAP_AFTER_BAR + q_height
             + OPT_GAP_TOP + options_height)
    available = CONTENT_BOTTOM - PANEL_Y - below
    return int(max(PANEL_MIN, min(PANEL_SIDE, available * max(ratio, 0.2))))


def panel_size(photo: Image.Image, side: int = None) -> tuple:
    """Размер панели под пропорции кадра.

    Квадратный кадр (после адаптации) кладём в квадратную панель — он
    заполняет её целиком, без полей и без размытой заливки по краям.
    Неадаптированную ленту 1208×450 кладём в широкую панель, где верх и низ
    дополняются её же размытым продолжением.
    """
    ratio = photo.width / photo.height
    side = side or PANEL_SIDE
    if PANEL_FILL_MIN <= ratio <= PANEL_FILL_MAX:
        # Кадр после адаптации (квадрат или 4:3) заполняет панель целиком —
        # без полей и без размытой заливки по краям.
        return side, round(side / ratio)
    height = round((side - 2 * PHOTO_INSET) * photo.height / photo.width)
    return side, max(420, height + 2 * PHOTO_INSET)


def build_panel(photo: Image.Image, side: int = None) -> Image.Image:
    """Панель с иллюстрацией."""
    pw, ph = panel_size(photo, side)
    panel = Image.new("RGB", (pw, ph))

    # Фон панели — тот же кадр, растянутый и размытый. Для квадратной панели
    # он не виден: резкий кадр закрывает её целиком.
    k = max(pw / photo.width, ph / photo.height)
    back = photo.resize((max(pw, int(photo.width * k)), max(ph, int(photo.height * k))),
                        Image.LANCZOS)
    back = back.crop(((back.width - pw) // 2, (back.height - ph) // 2,
                      (back.width - pw) // 2 + pw, (back.height - ph) // 2 + ph))
    back = back.filter(ImageFilter.GaussianBlur(28))
    back = Image.blend(back, Image.new("RGB", back.size, C.ACCENT), 0.35)
    panel.paste(back, (0, 0))

    # Резкий кадр: квадратный заполняет панель целиком, лента вписывается
    # по ширине. Пропорции не меняются ни в одном из случаев.
    ratio = photo.width / photo.height
    if PANEL_FILL_MIN <= ratio <= PANEL_FILL_MAX:
        sharp = photo.resize((pw, ph), Image.LANCZOS) if abs(ratio - pw / ph) < 0.02 else None
        if sharp is None:
            k = max(pw / photo.width, ph / photo.height)
            scaled = photo.resize((round(photo.width * k), round(photo.height * k)), Image.LANCZOS)
            sharp = scaled.crop(((scaled.width - pw) // 2, (scaled.height - ph) // 2,
                                 (scaled.width - pw) // 2 + pw, (scaled.height - ph) // 2 + ph))
        panel.paste(sharp, (0, 0))
    else:
        inner_w = pw - 2 * PHOTO_INSET
        sharp = photo.resize((inner_w, round(photo.height * inner_w / photo.width)), Image.LANCZOS)
        panel.paste(sharp, (PHOTO_INSET, (ph - sharp.height) // 2))

    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, pw - 1, ph - 1),
                                           radius=C.CARD_RADIUS, fill=255)
    rounded = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    rounded.paste(panel, (0, 0))
    rounded.putalpha(mask)
    return rounded


def draw_spotlight(base: Image.Image, boxes, panel_pos: tuple,
                   panel_size_px: tuple, k: float) -> None:
    """Затемняет кадр, оставляя просветы над названными объектами.

    Не прячет картинку, а приглушает её: зритель должен видеть всю сцену и
    понимать, где именно находится знак. Окон может быть несколько — в части
    вопросов ответ держится сразу на двух объектах; а может не быть ни
    одного, и тогда затемнения нет вовсе.
    """
    if k <= 0 or not boxes:
        return
    if isinstance(boxes[0], (int, float)):
        boxes = [boxes]
    px, py = panel_pos
    pw, ph = panel_size_px

    # Маска затемнения: сплошная заливка минус окна над объектами.
    mask = Image.new("L", (pw, ph), int(255 * SPOTLIGHT_DIM * min(1.0, k)))
    md = ImageDraw.Draw(mask)
    for x0, y0, x1, y1 in boxes:
        # Знак в кадре мелкий, и окно по его рамке не читается — расширяем
        # его вокруг центра объекта до размера, который виден с телефона.
        cx, cy = (x0 + x1) / 2 * pw, (y0 + y1) / 2 * ph
        half_w = max((x1 - x0) * pw / 2 + 0.022 * pw, SPOTLIGHT_MIN_W * pw / 2)
        half_h = max((y1 - y0) * ph / 2 + 0.030 * ph, SPOTLIGHT_MIN_H * ph / 2)
        md.rounded_rectangle((max(0, cx - half_w), max(0, cy - half_h),
                              min(pw, cx + half_w), min(ph, cy + half_h)),
                             radius=SPOTLIGHT_RADIUS, fill=0)
    mask = mask.filter(ImageFilter.GaussianBlur(SPOTLIGHT_FEATHER))

    # Скругление панели: затемнение не должно вылезать за её углы.
    corners = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(corners).rounded_rectangle((0, 0, pw - 1, ph - 1),
                                              radius=C.CARD_RADIUS, fill=255)
    mask = Image.composite(mask, Image.new("L", (pw, ph), 0), corners)

    base.paste(Image.new("RGB", (pw, ph), (0, 0, 0)), (px, py), mask)


# ── Рендер кадра ───────────────────────────────────────────────────────────

def option_layout(d: ImageDraw.ImageDraw, options: list) -> list:
    """Высоты и строки каждого варианта — считаются один раз на ролик."""
    layout = []
    max_w = OPT_W - 2 * OPT_PAD_X - BADGE - 24
    f = frames.font("medium", OPT_TEXT_SIZE)
    for text in options:
        lines = frames.wrap(d, text, f, max_w)
        height = max(OPT_MIN_H, 52 + len(lines) * int(OPT_TEXT_SIZE * 1.3))
        layout.append((lines, height))
    return layout


def draw_option(base: Image.Image, d: ImageDraw.ImageDraw, index: int, lines: list,
                y: int, height: int, state: str) -> None:
    """state: hidden | shown | correct | dim"""
    if state == "hidden":
        return
    x0 = (C.W - OPT_W) // 2
    fill, ink, badge_fill, badge_ink = C.WHITE, C.PRIMARY_TEXT, C.GRAY, C.SECONDARY_TEXT
    if state == "correct":
        # Верный ответ заливается ярко-зелёным целиком: в ленте бледная
        # подложка не считывается за те доли секунды, что на неё смотрят.
        fill, ink = BRIGHT_GREEN, C.WHITE
        badge_fill, badge_ink = C.WHITE, BRIGHT_GREEN
    elif state == "dim":
        fill, ink, badge_ink = C.WHITE, C.SECONDARY_TEXT, C.SECONDARY_TEXT

    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    # Неверные варианты глушим текстом, а не прозрачностью: на синем фоне
    # полупрозрачная белая плашка превращается в голубое привидение.
    alpha = 255
    ld.rounded_rectangle((x0, y, x0 + OPT_W, y + height), radius=C.CARD_RADIUS,
                         fill=fill + (alpha,))
    base.paste(layer, (0, 0), layer)

    bx, by = x0 + OPT_PAD_X, y + (height - BADGE) // 2
    d.ellipse((bx, by, bx + BADGE, by + BADGE), fill=badge_fill)
    f_badge = frames.font("bold", 34)
    d.text((bx + BADGE // 2, by + BADGE // 2), str(index + 1),
           font=f_badge, fill=badge_ink, anchor="mm")

    f = frames.font("medium", OPT_TEXT_SIZE)
    line_h = int(OPT_TEXT_SIZE * 1.3)
    ty = y + height // 2 - (line_h * len(lines)) // 2 + line_h // 2
    for line in lines:
        d.text((bx + BADGE + 24, ty), line, font=f, fill=ink, anchor="lm")
        ty += line_h


def bar_y(panel: Image.Image) -> int:
    """Полоса времени идёт сразу под панелью: под вариантами на неё уже
    не остаётся места, а объяснение занимает ту же зону, что и варианты."""
    return PANEL_Y + panel.height + BAR_UNDER_PANEL


def question_top(panel: Image.Image) -> int:
    return bar_y(panel) + BAR_H + Q_GAP_AFTER_BAR


def options_top(panel: Image.Image, q_height: int) -> int:
    return question_top(panel) + q_height + OPT_GAP_TOP


def render_frame(q: Question, panel: Image.Image, layout: list, background,
                 shown: int, revealed: bool, progress, banner_frame: int,
                 explain: tuple = None, circle: tuple = None,
                 circle_k: float = 0.0, only_banner: bool = False) -> Image.Image:
    base = frames.prepare_background(background, "blue")
    d = ImageDraw.Draw(base)

    if only_banner:
        # Финал: на экране остаётся одна плашка по центру кадра — всё
        # остальное своё уже отработало и только спорит с ней за внимание.
        img = banner.frame(max(0, banner_frame), CTA_BANNER_W)
        base.paste(img, (C.W // 2 - img.width // 2, C.H // 2 - img.height // 2), img)
        return base

    # Панель центрируется: её ширина зависит от пропорций кадра.
    panel_pos = ((C.W - panel.width) // 2, PANEL_Y)
    base.paste(panel, panel_pos, panel)
    if circle and circle_k > 0:
        draw_spotlight(base, circle, panel_pos, (panel.width, panel.height), circle_k)

    f_q, q_lines, q_height = question_block(d, q.text)
    if explain is None:
        frames.draw_lines(d, q_lines, f_q, C.W // 2,
                          question_top(panel) + q_height // 2, C.WHITE, leading=1.18)

    if explain is not None:
        # В фазе разбора уходят и варианты, и сам вопрос: он уже прочитан,
        # а разбору нужно место — иначе текст обрывается на полуслове.
        draw_explanation(base, d, q, PANEL_Y + panel.height + EXPLAIN_GAP,
                         explain[0], explain[1])
    else:
        y = options_top(panel, q_height)
        for i, (lines_i, height) in enumerate(layout):
            if revealed:
                state = "correct" if i == q.correct else "dim"
            elif i < shown:
                state = "shown"
            else:
                state = "hidden"
            draw_option(base, d, i, lines_i, y, height, state)
            y += height + OPT_GAP

    # Полоса времени — та же логика цвета, что в роликах со знаками.
    # Полоса появляется только на отсчёте: до него она ничего не сообщает,
    # а после ответа время уже не при чём.
    if progress is not None:
        by = bar_y(panel)
        bx0 = (C.W - OPT_W) // 2
        d.rounded_rectangle((bx0, by, bx0 + OPT_W, by + BAR_H), radius=BAR_H // 2,
                            fill=BAR_TRACK)
        ratio = max(0.0, min(1.0, progress))
        if ratio > 0.001:
            w = int(OPT_W * ratio)
            if w >= BAR_H:
                colour = (BRIGHT_GREEN if ratio > C.BAR_GREEN_ABOVE
                          else BRIGHT_GOLD if ratio > C.BAR_GOLD_ABOVE else BRIGHT_RED)
                d.rounded_rectangle((bx0, by, bx0 + w, by + BAR_H),
                                    radius=BAR_H // 2, fill=colour)

    return base


# Только название, стоящее сразу после номера знака: «Знак 6.16 «Стоп-линия»».
# Просто первые кавычки в разборе брать нельзя — там попадаются «свою»,
# «не работают», «правилом правой руки», и подсветка уедет на случайный куст.
SIGN_RE = __import__("re").compile(r"[Зз]нак[а-я]*\s+(\d+(?:\.\d+)*)\s*[«\"]([^»\"]{3,45})[»\"]")


def sign_number(q: Question) -> str:
    """Номер знака из разбора — по нему берётся эталон для проверки."""
    match = SIGN_RE.search(q.comment or "")
    return match.group(1) if match else ""


def circle_target(q: Question) -> str:
    """Что подсветить на кадре: знак, названный в разборе по номеру.

    Если такого нет, подсветки не будет: затемнить кадр вокруг случайного
    места хуже, чем не затемнять вовсе.
    """
    match = SIGN_RE.search(q.comment or "")
    if not match:
        return ""
    return f"дорожный знак «{match.group(2).strip()}» ({match.group(1)}) на этом кадре"


# Хвост-источник в конце разбора: «(«Дорожные знаки», пункт 6.2 ПДД)»,
# «(Пункт 8.11 ПДД)», «(«Дорожные знаки»)». Ловим любую концевую скобку,
# похожую на ссылку, иначе она уезжает в озвучку и звучит канцелярски.
SOURCE_RE = __import__("re").compile(r"\s*\(([^()]{3,140})\)\s*$")
SOURCE_HINT = __import__("re").compile(r"(ПДД|пункт|статья|раздел|«)", re.IGNORECASE)


def explanation(comment: str) -> tuple:
    """Текст объяснения и ссылка на пункт ПДД отдельной строкой.

    Комментарий вопроса заканчивается ссылкой вида «(«Дорожные знаки», пункт
    6.2 ПДД)» — в озвучке она звучит канцелярски, поэтому уходит на экран
    мелкой строкой, а диктор читает только само объяснение.
    """
    text = " ".join((comment or "").split())
    source = ""
    match = SOURCE_RE.search(text)
    if match and SOURCE_HINT.search(match.group(1)):
        source = match.group(1).strip()
        text = text[:match.start()].strip()

    if len(text) > EXPLAIN_MAX_CHARS:
        cut = text.rfind(". ", 0, EXPLAIN_MAX_CHARS)
        text = (text[:cut + 1] if cut > 80 else text[:EXPLAIN_MAX_CHARS].rstrip() + "…").strip()
    return text, source


def draw_explanation(base: Image.Image, d: ImageDraw.ImageDraw, q: Question,
                     top: int, text: str, source: str) -> None:
    """Зелёная строка с верным ответом и карточка с объяснением под ней."""
    x0 = (C.W - OPT_W) // 2

    f_ans = frames.font("bold", 40)
    ans = f"Верно: {q.options[q.correct]}"
    lines = frames.wrap(d, ans, f_ans, OPT_W - 2 * EXPL_PAD)[:2]
    ans_h = 40 + len(lines) * int(40 * 1.28)
    d.rounded_rectangle((x0, top, x0 + OPT_W, top + ans_h), radius=C.CARD_RADIUS,
                        fill=BRIGHT_GREEN)
    y = top + ans_h // 2 - (int(40 * 1.28) * len(lines)) // 2 + int(40 * 1.28) // 2
    for line in lines:
        d.text((C.W // 2, y), line, font=f_ans, fill=C.WHITE, anchor="mm")
        y += int(40 * 1.28)

    if not text:
        # Фаза плашки: разбор уже прочитан и убран, чтобы плашка не легла
        # поверх текста. На экране остаётся только верный ответ.
        return

    f = frames.font("medium", EXPL_SIZE)
    body = frames.wrap(d, text, f, OPT_W - 2 * EXPL_PAD)[:EXPL_MAX_LINES]
    line_h = int(EXPL_SIZE * 1.34)
    card_top = top + ans_h + 18
    card_h = 2 * EXPL_PAD + line_h * len(body) + (44 if source else 0)
    d.rounded_rectangle((x0, card_top, x0 + OPT_W, card_top + card_h),
                        radius=C.CARD_RADIUS, fill=C.WHITE)
    y = card_top + EXPL_PAD + line_h // 2
    for line in body:
        d.text((x0 + EXPL_PAD, y), line, font=f, fill=C.PRIMARY_TEXT, anchor="lm")
        y += line_h
    if source:
        f_src = frames.font("medium", SOURCE_SIZE)
        d.text((x0 + EXPL_PAD, y + 8), source, font=f_src, fill=C.SECONDARY_TEXT, anchor="lm")


# ── Сборка ─────────────────────────────────────────────────────────────────

def voice_lines(q: Question) -> list:
    lines = [Voice("q", q.text)]
    for i, text in enumerate(q.options):
        lines.append(Voice(f"opt{i}", f"{ORDINALS[i]}. {text}"))
    lines.append(Voice("answer", f"Правильный ответ — {ORDINALS[q.correct].lower()}."))
    text, _ = explanation(q.comment)
    if text:
        lines.append(Voice("explain", text))
    lines.append(Voice("cta", CTA_TEXT))
    return lines


def synthesize(lines: list, vc: audio.VoiceConfig) -> None:
    from concurrent.futures import ThreadPoolExecutor

    TTS_DIR.mkdir(parents=True, exist_ok=True)

    def one(v: Voice) -> None:
        v.path = TTS_DIR / f"q_{v.key}_{audio.tts_cache_key(v.text, vc)}.wav"
        audio.synthesize(v.text, v.path, vc)
        v.samples = len(audio.trim_silence(audio.read_wav(v.path)))

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(one, lines))
    missing = [v.key for v in lines if not v.path.exists() or v.samples == 0]
    if missing:
        raise SystemExit(f"озвучка не собралась: {', '.join(missing)}")


def build_timeline(q: Question, lines: list) -> list:
    by = {v.key: v for v in lines}
    segments, cursor = [], 0

    def add(kind, seconds, index=-1):
        nonlocal cursor
        seg = Segment(kind, cursor, max(1, int(round(seconds * C.FPS))), index)
        segments.append(seg)
        cursor = seg.end

    add("question", by["q"].seconds + T_QUESTION_TAIL)
    for i in range(len(q.options)):
        add("option", by[f"opt{i}"].seconds + T_OPTION_TAIL, i)
    add("think", T_THINK)
    add("reveal", by["answer"].seconds + T_REVEAL_TAIL)
    if "explain" in by:
        add("explain", by["explain"].seconds + T_EXPLAIN_TAIL)
    add("outro", by["cta"].seconds + T_OUTRO_TAIL)
    return segments


def build_audio(segments: list, lines: list, total_frames: int) -> np.ndarray:
    by = {v.key: v for v in lines}
    tracks = []
    for seg in segments:
        at = seg.start / C.FPS
        if seg.kind == "question":
            tracks.append((at, audio.trim_silence(audio.read_wav(by["q"].path))))
        elif seg.kind == "option":
            tracks.append((at, audio.trim_silence(audio.read_wav(by[f"opt{seg.index}"].path))))
        elif seg.kind == "think":
            tracks.append((at, audio.tick_track(seg.length / C.FPS)))
        elif seg.kind == "reveal":
            tracks.append((at, audio.reveal_chime()))
            tracks.append((at + 0.18, audio.trim_silence(audio.read_wav(by["answer"].path))))
        elif seg.kind == "explain" and "explain" in by:
            tracks.append((at, audio.trim_silence(audio.read_wav(by["explain"].path))))
        elif seg.kind == "outro":
            tracks.append((at, audio.trim_silence(audio.read_wav(by["cta"].path))))
    return audio.mix(tracks, total_frames / C.FPS)


def render_video(q: Question, segments: list, panel, layout, background, out: Path,
                 explain: tuple = None, circle: tuple = None) -> int:
    total = segments[-1].end
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.Popen(
        ["ffmpeg", "-y", "-v", "error",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{C.W}x{C.H}", "-r", str(C.FPS),
         "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "19",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out)],
        stdin=subprocess.PIPE,
    )
    try:
        for n in range(total):
            seg = next(s for s in segments if s.start <= n < s.end)
            k = (n - seg.start) / seg.length
            shown, revealed, progress, banner_frame = 0, False, None, -1
            block, circle_k, only_banner = None, 0.0, False
            if seg.kind == "question":
                shown = 0
            elif seg.kind == "option":
                shown = seg.index + 1
            elif seg.kind == "think":
                shown, progress = len(q.options), 1.0 - k
            elif seg.kind == "reveal":
                shown, revealed = len(q.options), True
            elif seg.kind == "explain":
                shown, revealed, block = len(q.options), True, explain
                circle_k = min(1.0, (n - seg.start) / (T_HIGHLIGHT * C.FPS))
            else:
                only_banner = True
                banner_frame = n - seg.start
            frame = render_frame(q, panel, layout, background, shown, revealed,
                                 progress, banner_frame, block, circle, circle_k,
                                 only_banner)
            proc.stdin.write(frame.tobytes())
            if n % 60 == 0:
                print(f"\r  кадры: {n}/{total}", end="", flush=True)
    finally:
        proc.stdin.close()
        proc.wait()
    print(f"\r  кадры: {total}/{total}")
    if proc.returncode != 0:
        raise SystemExit("ffmpeg не смог собрать видео")
    return total


def main() -> None:
    p = argparse.ArgumentParser(description="Ролик «вопрос из билета»")
    p.add_argument("--id", help="id вопроса")
    p.add_argument("--country", default="ru")
    p.add_argument("--voice", default="Algenib")
    p.add_argument("--background", help="имя фона")
    p.add_argument("--out", help="путь к mp4")
    p.add_argument("--index", type=int, help="номер ролика в серии (для имени файла)")
    p.add_argument("--list", action="store_true", help="показать короткие вопросы с картинкой")
    p.add_argument("--box", help="рамки подсветки: x0,y0,x1,y1 через ; для нескольких")
    p.add_argument("--auto-highlight", action="store_true",
                   help="искать знак автоматически (ненадёжно, см. README)")
    p.add_argument("--circle", help="что подсветить, если включён --auto-highlight")
    p.add_argument("--no-compose", action="store_true",
                   help="не вклеивать полосу оригинала в сгенерированный кадр")
    p.add_argument("--ai-image", action="store_true",
                   help="вертикально расширить иллюстрацию через image-to-image")
    p.add_argument("--skip-verify", action="store_true")
    args = p.parse_args()

    questions = load_questions(args.country)
    if args.list or not args.id:
        for q in questions[:40]:
            print(f"{q.id}  билет {q.ticket:>2}  {q.text[:70]}")
        print(f"\nвсего вопросов с картинкой: {len(questions)}")
        return

    q = next((x for x in questions if x.id == args.id), None)
    if q is None:
        raise SystemExit(f"нет вопроса с id {args.id}")

    print(f"Билет {q.ticket}: {q.text}")
    for i, text in enumerate(q.options):
        print(f"  {i + 1}{'*' if i == q.correct else ' '} {text}")

    vc = audio.VoiceConfig(voice=args.voice, style=VOICE_STYLE)
    lines = voice_lines(q)
    print("Озвучка…")
    synthesize(lines, vc)

    if not args.skip_verify:
        print("Сверка озвучки…")
        problems, skipped = verify.check_voice(lines, vc)
        if problems:
            for line in problems:
                print(f"  ✗ {line}")
            raise SystemExit("озвучка не прошла проверку")
        if skipped:
            print(f"  ⚠ {len(skipped)} реплик не проверено (расшифровка недоступна)")

    segments = build_timeline(q, lines)
    total_frames = segments[-1].end
    print(f"Хронометраж: {total_frames / C.FPS:.1f} с")

    seed = hashlib.sha1(q.id.encode()).hexdigest()[:8]
    background = backgrounds.load(args.background) if args.background else backgrounds.pick(q.id)
    circle = None
    source = q.image
    if args.ai_image:
        from . import qimage

        source = qimage.generate(q.image, q.id)
        # Вклейка оригинала уместна, когда генерация лишь достроила кадр.
        # Если модель перенесла объект на другой фон (знак с белого листа на
        # серую стену), вклеенная полоса ложится поверх чужого фона и даёт
        # двойную рамку — тогда шаг пропускается.
        if not args.no_compose:
            qimage.compose_square(q.image, source)
        sheet = qimage.contact_sheet(q.image, source, source.with_name(source.stem + "_sheet.jpg"))
        print(f"  кадр расширен: {source.name}; сверьте с оригиналом — {sheet}")
        if args.box:
            # Несколько рамок разделяются точкой с запятой: в части вопросов
            # ответ держится сразу на двух объектах.
            circle = [tuple(float(v) for v in part.split(","))
                      for part in args.box.split(";") if part.strip()]
            print(f"  подсветка по заданным рамкам: {circle}")
        elif args.auto_highlight:
            # Автопоиск оставлен ключом, но по умолчанию выключен: на пробе
            # трёх кадров он попал один раз из трёх, а окно поверх случайного
            # места хуже, чем его отсутствие.
            target = args.circle or circle_target(q)
            number = sign_number(q)
            if target:
                circle = qimage.locate_sign(source, target, number)
                print(f"  автоподсветка: «{target}» → {circle or 'не найдено'}")
    photo = Image.open(source).convert("RGB")
    probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    layout = option_layout(probe, q.options)
    options_height = sum(h + OPT_GAP for _, h in layout) - OPT_GAP
    _, _, q_height = question_block(probe, q.text)
    side = panel_side_for(q_height, options_height, photo.width / photo.height)
    panel = build_panel(photo, side)
    print(f"  панель {side} px (вопрос {q_height} px, варианты {options_height} px)")

    work = WORK_DIR / f"q_{seed}"
    work.mkdir(parents=True, exist_ok=True)
    silent = work / "video.mp4"
    print("Кадры…")
    explain = explanation(q.comment)
    render_video(q, segments, panel, layout, background, silent,
                 explain if explain[0] else None, circle)

    wav = audio.write_wav(work / "audio.wav", build_audio(segments, lines, total_frames))
    verify.check_durations(silent, wav, total_frames)

    if args.out:
        out = Path(args.out)
    else:
        prefix = f"{args.index:02d}_" if args.index else ""
        out = OUT_DIR / f"{prefix}bilet{q.ticket:02d}_{slugify(q.text)}.mp4"
    audio.mux(silent, wav, out)
    verify.check_result(out, total_frames)
    print(f"\nГотово: {out}  ({total_frames / C.FPS:.1f} с, "
          f"{out.stat().st_size / 1024 / 1024:.1f} МБ)")


if __name__ == "__main__":
    main()
