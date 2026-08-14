#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Извлекает вопросы из официальных PDF MUP в структурированный JSON.

Формат PDF (см. вводный PDF): 2 колонки, ячейка вопроса =
  [номер, мелкий шрифт — может стоять В СЕРЕДИНЕ текста вопроса, если тот
   переносится на 2+ строки — НЕ надёжный маркер начала]
  [текст вопроса, 1+ строк]
  [рисунок/фото — если есть]
  [категория A/B/C/D/F | варианты а)б)в)... | число поенов — ЖИРНАЯ цифра
   1-3, всегда на строке ПОСЛЕДНЕГО варианта ответа — надёжный маркер КОНЦА
   вопроса].

Алгоритм v2: сегментируем колонку по позициям жирных «поены»-цифр (они же
конец последнего варианта ответа каждого вопроса) — это единственный
геометрически стабильный якорь в разметке PDF; номер вопроса и переносы
текста нестабильны.

Правильные ответы в публичном PDF НЕ отмечены (кроме 5 спец. вопросов),
поэтому здесь извлекаем всё, КРОМЕ ключа ответов — ключ определяется отдельно.

Выход (scratchpad): список вопросов
  {source, number, question, options[], points, category, multi, image}
Картинки вопросов сохраняются в out_images/<source>_<NNN>.png.

Запуск: python3 tools/rs_content/extract_questions.py <pdf> <source_tag> <out_json> <out_images_dir>
"""
import json
import os
import re
import sys

import fitz

sys.path.insert(0, os.path.dirname(__file__))
from mup_lib import to_latin, clean_ws  # noqa: E402

NUM_RE = re.compile(r"^(\d+)\.$")
OPT_RE = re.compile(r"^([абвгдежз])\)$")
INLINE_OPT_RE = re.compile(r"([абвгдежз])\)")
CAT_RE = re.compile(r"^([АВСDF])$")  # категория: заглавная (кир. А В С + лат. D F)
# Жирная цифра балла = якорь конца вопроса. Раньше был диапазон 1-3 (по
# наблюдаемым PDF), но как минимум одна серия вопросов (время отдыха
# водителей / тормозные системы, категория Vozila) весит 4 балла — с узким
# диапазоном её якорь не распознавался, и текст+варианты приклеивались к
# ПРЕДЫДУЩЕМУ вопросу как лишние ответы (см. PENDING_REVIEW.md, пункт про
# points=4). Расширено на всякий случай — верхняя граница неизвестна.
POINTS_RE = re.compile(r"^[1-9]$")
MULTI_RE = re.compile(r"[Зз]аокруж")  # «Заокружи два/три тачна одговора»
# Колонтитулы/копирайт MUP — вырезаем, чтобы не попадали в текст вопроса.
BOILER_RE = re.compile(
    r"РЕПУБЛИКА СРБИЈА|МИНИСТАРСТВО|Забрањено је|комерцијалне сврхе|"
    r"било којим средствима|REPUBLIKA SRBIJA|MINISTARSTVO|УПРАВА САОБРАЋАЈНЕ")


def spans_of(page):
    out = []
    for b in page.get_text("dict")["blocks"]:
        if "lines" not in b:
            continue
        for l in b["lines"]:
            for s in l["spans"]:
                t = s["text"]
                if not t.strip():
                    continue
                x0, y0, x1, y1 = s["bbox"]
                out.append({
                    "t": t, "x": x0, "y": y0, "x1": x1, "y1": y1,
                    "cx": (x0 + x1) / 2, "cy": (y0 + y1) / 2,
                    "sz": s["size"], "bold": bool(s["flags"] & 16),
                })
    return out


def parse_column(col_spans, images, y_top, y_bot, col_lo, col_hi):
    """Парсит один столбец: сегментирует по «поены»-якорям (см. модуль)."""
    col_spans = sorted(col_spans, key=lambda s: (s["y"], s["x"]))
    col_w = col_hi - col_lo

    # Якоря конца вопроса: жирная цифра 1-3 в правой трети столбца.
    points_anchors = [
        s for s in col_spans
        if s["bold"] and POINTS_RE.match(s["t"].strip())
        and s["x"] > col_lo + 0.6 * col_w
    ]
    if not points_anchors:
        return []

    questions = []
    seg_start = y_top
    for pi, pts in enumerate(points_anchors):
        seg_end = pts["y1"] + 1  # чуть ниже нижнего края цифры баллов
        seg = [s for s in col_spans if seg_start <= s["y"] < seg_end and s is not pts]
        q = parse_segment(seg, images, seg_start, seg_end, int(pts["t"].strip()))
        if q:
            questions.append(q)
        seg_start = seg_end
    return questions


def parse_segment(seg, images, y_start, y_end, points):
    seg = sorted(seg, key=lambda s: (round(s["y"]), s["x"]))

    # Убираем случайно попавшие сноски-колонтитулы посреди сегмента.
    seg = [s for s in seg if not BOILER_RE.search(s["t"])]

    # Номер вопроса (мелкий шрифт слева) — не участвует в тексте, только id.
    number = None
    num_span = None
    for s in seg:
        st = s["t"].strip()
        if s["sz"] < 9.5 and NUM_RE.match(st):
            number = int(NUM_RE.match(st).group(1))
            num_span = s
            break
    if num_span is not None:
        seg = [s for s in seg if s is not num_span]

    # Категория — одиночная заглавная A/В/С/D/F (сербская или латинская буква).
    category = ""
    cat_span = None
    for s in seg:
        st = s["t"].strip()
        if CAT_RE.match(st):
            category = to_latin(st)
            cat_span = s
            break
    if cat_span is not None:
        seg = [s for s in seg if s is not cat_span]

    # Маркеры вариантов (отдельные спаны "а)").
    markers = [(i, OPT_RE.match(s["t"].strip()).group(1))
               for i, s in enumerate(seg) if OPT_RE.match(s["t"].strip())]

    if markers:
        first_y = seg[markers[0][0]]["y"]
        q_text = clean_ws(" ".join(
            s["t"] for s in seg if s["y"] < first_y - 0.5))
        options = []
        for mi, (si, letter) in enumerate(markers):
            m_y = seg[si]["y"]
            m_x = seg[si]["x"]
            nxt_y = seg[markers[mi + 1][0]]["y"] if mi + 1 < len(markers) else 1e9
            parts = [s["t"] for s in seg
                     if s is not seg[si]
                     and (m_y - 0.5) <= s["y"] < (nxt_y - 0.5)
                     and s["x"] > m_x - 1]
            options.append(clean_ws(" ".join(parts)))
    else:
        # Инлайн-варианты: "а) 50 km/h, б) 70 km/h, в) 80 km/h" в одном тексте.
        full = clean_ws(" ".join(s["t"] for s in seg))
        m = INLINE_OPT_RE.search(full)
        if not m:
            return None
        q_text = full[:m.start()].strip()
        rest = full[m.start():]
        pieces = INLINE_OPT_RE.split(rest)
        options = []
        i = 1
        while i < len(pieces) - 1:
            options.append(clean_ws(pieces[i + 1]).rstrip(",; "))
            i += 2

    if not q_text or len(options) < 2:
        return None

    multi = bool(MULTI_RE.search(q_text)) or any(MULTI_RE.search(o) for o in options)
    # Картинка вопроса: центр в пределах сегмента по y.
    img = None
    for im in images:
        if y_start <= im["cy"] < y_end:
            img = im
            break

    return {
        "number": number,
        "question": to_latin(q_text),
        "options": [to_latin(o) for o in options],
        "points": points,
        "category": category,
        "multi": multi,
        "_img_rect": (img["rect"] if img else None),
    }


def extract(pdf_path, source, out_json, out_img_dir):
    doc = fitz.open(pdf_path)
    os.makedirs(out_img_dir, exist_ok=True)
    all_q = []
    for pno in range(doc.page_count):
        page = doc[pno]
        W, H = page.rect.width, page.rect.height
        mid = W / 2
        spans = spans_of(page)
        # Отсекаем колонтитулы (верх/низ страницы) и копирайт-боилерплейт.
        spans = [s for s in spans if 30 < s["cy"] < H - 24
                 and not BOILER_RE.search(s["t"])]
        # Картинки страницы с bbox.
        imgs = []
        for im in page.get_images(full=True):
            try:
                bb = page.get_image_bbox(im)
            except Exception:
                continue
            if bb.width < 20 or bb.height < 20:
                continue
            imgs.append({"xref": im[0], "cx": (bb.x0 + bb.x1) / 2,
                         "cy": (bb.y0 + bb.y1) / 2, "rect": (bb.x0, bb.y0, bb.x1, bb.y1)})
        for col, (lo, hi) in enumerate([(0, mid), (mid, W)]):
            cs = [s for s in spans if lo <= s["cx"] < hi]
            ci = [im for im in imgs if lo <= im["cx"] < hi]
            for q in parse_column(cs, ci, 30, H - 28, lo, hi):
                q["source"] = source
                q["page"] = pno
                # Сохраняем картинку вопроса.
                if q["_img_rect"]:
                    r = fitz.Rect(*q["_img_rect"])
                    pix = page.get_pixmap(clip=r, dpi=150)
                    fname = f"{source}_{len(all_q)+1:04d}.png"
                    pix.save(os.path.join(out_img_dir, fname))
                    q["image"] = fname
                else:
                    q["image"] = None
                del q["_img_rect"]
                all_q.append(q)
    json.dump(all_q, open(out_json, "w"), ensure_ascii=False, indent=1)
    with_img = sum(1 for q in all_q if q["image"])
    multi = sum(1 for q in all_q if q["multi"])
    print(f"{source}: {len(all_q)} questions | with image: {with_img} | "
          f"multi-answer: {multi}")
    return all_q


if __name__ == "__main__":
    _, pdf, source, out_json, out_img = sys.argv[:5]
    extract(pdf, source, out_json, out_img)
