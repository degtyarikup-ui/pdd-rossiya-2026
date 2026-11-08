#!/usr/bin/env python3
"""Попиксельный рендер кадров ролика (PIL).

Кадр повторяет экран приложения: светлый фон, белая карточка со скруглением
16 pt, синий номер знака над названием, чип таймера — как чип экзамена.
Каждый кадр считается один раз и уходит в ffmpeg потоком, поэтому тысяча
PNG-файлов на диске не появляется.
"""

from __future__ import annotations

import functools
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from . import config as C

# ── Шрифты ─────────────────────────────────────────────────────────────────
# Приложение рисуется системным шрифтом (Roboto/SF). Для кадра берём первый
# доступный из списка — все кандидаты проверены на полную кириллицу.
# Onest — фирменный шрифт роликов, вариативный: одним файлом закрываются все
# начертания. Лежит в репозитории вместе с лицензией (OFL), чтобы сборка не
# зависела ни от системных шрифтов, ни от соседних проектов.
ONEST = str(Path(__file__).resolve().parent / "fonts" / "Onest[wght].ttf")
ROBOTO = str(Path.home() / "Library/Fonts/Roboto.ttf")
VARIATION = {"black": "Black", "bold": "Bold", "medium": "Medium", "regular": "Regular"}
FALLBACK = {
    "black": ["/System/Library/Fonts/Supplemental/Arial Black.ttf"],
    "bold": ["/System/Library/Fonts/Supplemental/Arial Bold.ttf"],
    "medium": ["/System/Library/Fonts/Supplemental/Arial.ttf"],
    "regular": ["/System/Library/Fonts/Supplemental/Arial.ttf"],
}


@functools.lru_cache(maxsize=256)
def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    for path in (ONEST, ROBOTO):
        if not Path(path).exists():
            continue
        f = ImageFont.truetype(path, size)
        try:
            f.set_variation_by_name(VARIATION[weight])
            return f
        except (OSError, AttributeError):
            continue  # не вариативная сборка — пробуем следующий файл
    for path in FALLBACK[weight]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    raise RuntimeError(f"не найден шрифт «{weight}»: проверьте {ROBOTO}")


def text_size(draw: ImageDraw.ImageDraw, s: str, f: ImageFont.FreeTypeFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), s, font=f)
    return box[2] - box[0], box[3] - box[1]


def wrap(draw: ImageDraw.ImageDraw, s: str, f: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    words, lines, cur = s.split(), [], ""
    for word in words:
        probe = f"{cur} {word}".strip()
        if text_size(draw, probe, f)[0] <= max_w or not cur:
            cur = probe
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit_text(
    draw: ImageDraw.ImageDraw,
    s: str,
    weight: str,
    max_w: int,
    size_max: int,
    size_min: int,
    max_lines: int = 2,
) -> tuple[ImageFont.FreeTypeFont, list[str]]:
    """Подбирает максимальный кегль, при котором текст влезает в max_lines строк."""
    for size in range(size_max, size_min - 1, -2):
        f = font(weight, size)
        lines = wrap(draw, s, f, max_w)
        if len(lines) <= max_lines:
            return f, lines
    f = font(weight, size_min)
    return f, wrap(draw, s, f, max_w)[:max_lines]


def draw_lines(
    draw: ImageDraw.ImageDraw,
    lines: list[str],
    f: ImageFont.FreeTypeFont,
    cx: int,
    cy: int,
    fill,
    leading: float = 1.22,
) -> None:
    """Рисует блок строк по центру (cx, cy)."""
    line_h = int(f.size * leading)
    total = line_h * len(lines)
    y = cy - total // 2
    for line in lines:
        w, _ = text_size(draw, line, f)
        draw.text((cx - w // 2, y), line, font=f, fill=fill)
        y += line_h


# Теней нет: карточку от фона отделяет цвет (белая на #F8F9FA), как в
# приложении. Размытая тень в видео к тому же шумит на компрессии.


# ── Состояние одного знака в кадре ─────────────────────────────────────────

@dataclass
class SignCard:
    number: str
    title: str
    note: str
    image: Image.Image           # уже вписанный в SIGN_BOX RGBA
    revealed: bool = False
    progress: float = 1.0        # 1 → полоса полная, 0 → время вышло
    reveal_k: float = 0.0        # 0..1 — анимация появления ответа


@dataclass
class Frame:
    """Всё, что нужно нарисовать в конкретный момент времени."""
    header: str
    cards: list = field(default_factory=list)
    # (карточка, смещение по x в долях ширины экрана, масштаб, альфа)
    timer_text: str = ""
    timer_ratio: float = 1.0
    timer_answered: bool = False
    step: int = 0          # какой знак сейчас (1-based), 0 — нет ряда номеров
    steps_total: int = 0
    intro: dict = None
    outro: dict = None


# ── Фон ────────────────────────────────────────────────────────────────────

def cover(img: Image.Image) -> Image.Image:
    """Вписывает картинку в кадр по короткой стороне и подрезает."""
    k = max(C.W / img.width, C.H / img.height)
    scaled = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))),
                        Image.LANCZOS)
    x = (scaled.width - C.W) // 2
    y = (scaled.height - C.H) // 2
    return scaled.crop((x, y, x + C.W, y + C.H))


@functools.lru_cache(maxsize=4)
def _background(key: str) -> Image.Image:
    raise RuntimeError  # заменяется в prepare_background


def prepare_background(image, tint: str) -> Image.Image:
    """Готовит фон кадра: сцена со знаками под брендовым синим или затемнением.

    В фазах загадки синий кладётся почти непрозрачно — иначе белая карточка
    теряется на пёстрой картинке. В интро и финале карточки нет, поэтому там
    сцена видна, и на ней читается синяя плашка субтитров.
    """
    if image is None:
        base = Image.new("RGB", (C.W, C.H), C.ACCENT if tint == "blue" else C.PRIMARY_TEXT)
        return base

    base = cover(image)
    if tint == "blue":
        overlay = Image.new("RGB", (C.W, C.H), C.ACCENT)
        return Image.blend(base, overlay, C.BG_BLUE_ALPHA)
    overlay = Image.new("RGB", (C.W, C.H), (10, 20, 40))
    return Image.blend(base, overlay, C.BG_DARK_ALPHA)


def subtitle(d: ImageDraw.ImageDraw, text: str, cy: int) -> None:
    """Субтитр: одна-две реплики крупно на синей плашке."""
    if not text:
        return
    # Кегль уменьшаем по ширине, а не через перенос: субтитр обязан быть
    # одной строкой целиком, иначе кусок фразы молча обрезается.
    max_w = C.W - 2 * C.SCREEN_PADDING - 2 * C.SUB_PAD_X
    f = font("black", C.SUB_SIZE_MAX)
    for size in range(C.SUB_SIZE_MAX, C.SUB_SIZE_MIN - 1, -2):
        f = font("black", size)
        if text_size(d, text, f)[0] <= max_w:
            break
    # Высота плашки — по метрикам шрифта, а не по чернилам конкретной строки:
    # иначе «знаки» и «Успеете» дают плашки разной высоты, а текст в них
    # каждый раз стоит на новой высоте.
    tw = text_size(d, text, f)[0]
    ascent, descent = f.getmetrics()
    box_w = tw + 2 * C.SUB_PAD_X
    box_h = ascent + descent + 2 * C.SUB_PAD_Y
    x0, y0 = C.W // 2 - box_w // 2, cy - box_h // 2
    d.rounded_rectangle((x0, y0, x0 + box_w, y0 + box_h),
                        radius=C.CHIP_RADIUS, fill=C.ACCENT)
    # Базовая линия ставится так, чтобы блок ascent+descent сел по центру.
    baseline = y0 + C.SUB_PAD_Y + ascent
    d.text((C.W // 2, baseline), text, font=f, fill=C.WHITE, anchor="ms")


SENTENCE = __import__("re").compile(r"(?<=[.!?])\s+")
NUMBER = __import__("re").compile(r"^\d+$")


def _units(sentence: str) -> list[str]:
    """Слова предложения, где число склеено со следующим словом.

    «за 3 секунды?» не должно разъехаться на «за 3» и «секунды?» — голое
    число в кадре читается как обрывок.
    """
    words = [w for w in sentence.replace("—", " ").split() if w]
    units, i = [], 0
    while i < len(words):
        if NUMBER.match(words[i]) and i + 1 < len(words):
            units.append(f"{words[i]} {words[i + 1]}")
            i += 2
        else:
            units.append(words[i])
            i += 1
    return units


def split_subtitles(text: str, per: int = None) -> list[str]:
    """Режет реплику на куски по 1–2 слова — равными частями, а не «пока влезает».

    Жадная нарезка оставляет хвост из одного слова, и это выглядит обрубком.
    Границы предложений куски не пересекают: «…за 3 секунды? Сегодня» —
    это конец одного вопроса и начало другого, вместе они не читаются.

    Точки в субтитрах не ставим — конец фразы виден и так, а точка на плашке
    читается мусором. Вопросительный знак остаётся: он меняет интонацию.
    """
    per = per or C.SUB_WORDS
    out: list[str] = []
    for sentence in SENTENCE.split(text.strip()):
        units = _units(sentence)
        if not units:
            continue
        chunks = max(1, round(len(units) / per))
        size = len(units) / chunks
        start = 0.0
        for i in range(chunks):
            end = len(units) if i == chunks - 1 else round((i + 1) * size)
            piece = " ".join(units[int(start):int(end)]).rstrip(".,;:")
            if piece:
                out.append(piece)
            start = end
    return out


def bar_color(ratio: float) -> tuple[int, int, int]:
    if ratio > C.BAR_GREEN_ABOVE:
        return C.GREEN
    if ratio > C.BAR_GOLD_ABOVE:
        return C.GOLD
    return C.RED


def surface_color(ratio: float) -> tuple[int, int, int]:
    if ratio > C.BAR_GREEN_ABOVE:
        return C.LIGHT_ACCENT
    if ratio > C.BAR_GOLD_ABOVE:
        return C.GOLD_SURFACE
    return C.RED_SURFACE


def timer_text_color(ratio: float) -> tuple[int, int, int]:
    if ratio > C.BAR_GREEN_ABOVE:
        return C.ACCENT
    if ratio > C.BAR_GOLD_ABOVE:
        return C.GOLD
    return C.RED


def render_card(card: SignCard) -> Image.Image:
    """Карточка знака на прозрачном холсте CARD_W×CARD_H."""
    img = Image.new("RGBA", (C.CARD_W, C.CARD_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, C.CARD_W - 1, C.CARD_H - 1), radius=C.CARD_RADIUS,
                        fill=C.WHITE + (255,))

    sign = card.image
    img.paste(sign, (C.CARD_W // 2 - sign.width // 2,
                     C.SIGN_CENTER_DY - sign.height // 2), sign)

    d.rounded_rectangle(
        (C.DIVIDER_INSET, C.DIVIDER_DY, C.CARD_W - C.DIVIDER_INSET, C.DIVIDER_DY + 3),
        radius=2, fill=C.DIVIDER + (255,),
    )

    if card.revealed:
        # Ответ проявляется и чуть подъезжает снизу — как ответ в приложении.
        k = max(0.0, min(1.0, card.reveal_k))
        alpha = int(255 * k)
        dy = int((1 - k) * 18)

        # Номер и название центрируются по своим осям; раньше номер стоял по
        # верхнему краю глифа и налезал на первую строку названия.
        f_num = font("bold", C.NUMBER_SIZE)
        d.text((C.CARD_W // 2, C.NUMBER_DY + dy), card.number,
               font=f_num, fill=C.ACCENT + (alpha,), anchor="mm")

        max_w = C.CARD_W - 2 * C.DIVIDER_INSET
        f_ans, lines = fit_text(d, card.title, "bold", max_w,
                                C.ANSWER_SIZE_MAX, C.ANSWER_SIZE_MIN,
                                max_lines=C.ANSWER_MAX_LINES)
        line_h = int(f_ans.size * C.ANSWER_LEADING)
        y = C.ANSWER_DY + dy - (line_h * len(lines)) // 2 + line_h // 2
        for line in lines:
            d.text((C.CARD_W // 2, y), line, font=f_ans,
                   fill=C.PRIMARY_TEXT + (alpha,), anchor="mm")
            y += line_h
    else:
        # «?» стоит по центру между разделителем и полосой времени — это
        # видимое окно карточки, а не абстрактная середина макета.
        f_q = font("black", C.QUESTION_MARK_SIZE)
        gap_top = C.DIVIDER_DY + 3
        gap_bottom = C.CARD_H - C.BAR_DY_FROM_BOTTOM
        d.text((C.CARD_W // 2, (gap_top + gap_bottom) // 2), "?",
               font=f_q, fill=C.ACCENT + (255,), anchor="mm")

    # Полоса времени: ложе остаётся на месте и после ответа — исчезающий
    # элемент читается как сбой вёрстки.
    bar_y = C.CARD_H - C.BAR_DY_FROM_BOTTOM
    bar_x1 = C.CARD_W - C.BAR_INSET
    d.rounded_rectangle((C.BAR_INSET, bar_y, bar_x1, bar_y + C.BAR_H),
                        radius=C.BAR_H // 2, fill=C.GRAY + (255,))
    ratio = max(0.0, min(1.0, card.progress))
    if ratio > 0.001:
        fill_w = int((bar_x1 - C.BAR_INSET) * ratio)
        if fill_w >= C.BAR_H:
            d.rounded_rectangle((C.BAR_INSET, bar_y, C.BAR_INSET + fill_w, bar_y + C.BAR_H),
                                radius=C.BAR_H // 2, fill=bar_color(ratio) + (255,))
    return img


def render_frame(frame: Frame, background=None) -> Image.Image:
    if frame.intro is not None:
        base = prepare_background(background, "dark")
        return render_intro(base, ImageDraw.Draw(base), frame.intro)
    if frame.outro is not None:
        base = prepare_background(background, "dark")
        return render_outro(base, ImageDraw.Draw(base), frame.outro)

    base = prepare_background(background, "blue")
    d = ImageDraw.Draw(base)

    # Карточки (во время свайпа их две).
    for card, dx, scale, alpha in frame.cards:
        img = render_card(card)
        if scale != 1.0:
            nw, nh = max(1, int(C.CARD_W * scale)), max(1, int(C.CARD_H * scale))
            img = img.resize((nw, nh), Image.LANCZOS)
        if alpha < 1.0:
            a = img.getchannel("A").point(lambda v: int(v * alpha))
            img.putalpha(a)

        cx = C.CARD_X + C.CARD_W // 2 + int(dx * C.W)
        cy = C.CARD_Y + C.CARD_H // 2
        base.paste(img, (cx - img.width // 2, cy - img.height // 2), img)

    # Пояснение под карточкой — только когда ответ открыт и карточка одна.
    # Во время свайпа оно не едет вместе с карточкой и читается как застрявший
    # кусок предыдущего знака.
    note = ""
    if len(frame.cards) == 1:
        card, _, _, alpha = frame.cards[0]
        if card.revealed and card.note and alpha > 0.9:
            note = card.note
    if note:
        f_note, lines = fit_text(d, note, "regular", C.W - 2 * C.SCREEN_PADDING - 40,
                                 C.NOTE_SIZE, 30, max_lines=C.NOTE_MAX_LINES)
        draw_lines(d, lines, f_note, C.W // 2, C.NOTE_CY, C.WHITE)

    if frame.steps_total:
        draw_steps(base, d, frame.step, frame.steps_total)

    return base


def draw_steps(base: Image.Image, d: ImageDraw.ImageDraw, step: int, total: int) -> None:
    """Ряд номеров знаков — как чипы вопросов в шапке приложения.

    На синем фоне синий чип не читался бы, поэтому роли перевёрнуты: текущий
    знак — белая плашка, пройденные и будущие — прозрачно-белые.
    """
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    f = font("bold", 34)
    w = C.DOTS_H
    row_w = total * w + (total - 1) * C.DOTS_GAP
    x = C.W // 2 - row_w // 2
    for i in range(1, total + 1):
        if i == step:
            fill, ink = C.WHITE + (255,), C.ACCENT + (255,)
        elif i < step:
            fill, ink = C.WHITE + (110,), C.WHITE + (255,)
        else:
            fill, ink = C.WHITE + (45,), C.WHITE + (150,)
        ld.rounded_rectangle((x, C.DOTS_Y, x + w, C.DOTS_Y + C.DOTS_H),
                             radius=C.SMALL_RADIUS, fill=fill)
        # anchor="mm" ставит цифру по оптическому центру плашки; ручной расчёт
        # по textbbox уводил её вниз на высоту верхнего выноса шрифта.
        ld.text((x + w // 2, C.DOTS_Y + C.DOTS_H // 2), str(i),
                font=f, fill=ink, anchor="mm")
        x += w + C.DOTS_GAP
    base.paste(layer, (0, 0), layer)


def render_intro(base: Image.Image, d: ImageDraw.ImageDraw, intro: dict) -> Image.Image:
    """Интро — только субтитры: то же, что звучит, по одному куску за раз."""
    subtitle(d, intro.get("subtitle", ""), C.INTRO_SUB_Y)
    return base


def render_outro(base: Image.Image, d: ImageDraw.ImageDraw, outro: dict) -> Image.Image:
    """Финал: все знаки выпуска разом и рекламная плашка внизу.

    Сетка повторяет экран знаков в приложении — белая карточка, синий номер
    по ГОСТ, название под ним, — чтобы зритель успел сверить свои ответы.
    Субтитров тут нет: их место занимает плашка со ссылками на сторы.
    """
    from . import banner

    draw_sign_grid(base, d, outro.get("signs", []))
    banner.draw(base, outro.get("banner_frame", 0))
    return base


def draw_sign_grid(base: Image.Image, d: ImageDraw.ImageDraw, signs: list) -> None:
    """Сетка знаков выпуска в две колонки — как список знаков в приложении."""
    if not signs:
        return
    cols = 2
    rows = (len(signs) + cols - 1) // cols
    gap = 28
    cell_w = (C.W - 2 * C.SCREEN_PADDING - (cols - 1) * gap) // cols
    avail = C.OUTRO_GRID_BOTTOM - C.OUTRO_GRID_Y
    cell_h = min(360, (avail - (rows - 1) * gap) // rows)

    img_box = int(cell_h * 0.46)
    f_num = font("bold", 34)
    f_title = font("medium", 28)

    for i, (number, title, image) in enumerate(signs):
        col, row = i % cols, i // cols
        x0 = C.SCREEN_PADDING + col * (cell_w + gap)
        y0 = C.OUTRO_GRID_Y + row * (cell_h + gap)
        d.rounded_rectangle((x0, y0, x0 + cell_w, y0 + cell_h),
                            radius=C.CARD_RADIUS, fill=C.WHITE)

        sign = image if max(image.size) <= img_box else image.copy()
        if max(sign.size) != img_box:
            k = img_box / max(sign.size)
            sign = sign.resize((max(1, round(sign.width * k)), max(1, round(sign.height * k))),
                               Image.LANCZOS)
        base.paste(sign, (x0 + cell_w // 2 - sign.width // 2,
                          y0 + 22 + img_box // 2 - sign.height // 2), sign)

        nw, _ = text_size(d, number, f_num)
        num_y = y0 + 30 + img_box
        d.text((x0 + cell_w // 2 - nw // 2, num_y), number, font=f_num, fill=C.ACCENT)

        lines = wrap(d, title, f_title, cell_w - 32)[:2]
        draw_lines(d, lines, f_title, x0 + cell_w // 2, num_y + 76, C.PRIMARY_TEXT, leading=1.2)
