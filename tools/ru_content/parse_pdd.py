#!/usr/bin/env python3
"""Парсер официального текста ПДД РФ в pdd_sections.json.

Текст Правил — приложение к постановлению Правительства РФ от 23.10.1993 № 1090,
официальный документ государственного органа. По ст. 1259 п. 6 ГК РФ такие
документы не являются объектом авторского права, поэтому текст можно
воспроизводить дословно. Источник разметки — avto-russia.ru (постраничная
публикация актуальной редакции), сам текст сверяется по нумерации разделов
и пунктов.

До этого в приложении лежал авторский пересказ на 10 КБ: 17 разделов с
перенумерованными заголовками, 70 пунктов вместо нескольких сотен. Разборы
вопросов ссылались на «пункт 13.11», а раздел 13 в приложении назывался
«Перевозка людей и грузов» — то есть проверить ссылку было невозможно.

Скачивание:
    cd tools/ru_content/raw
    for i in $(seq 1 26); do curl -s -A Mozilla/5.0 \
        "https://avto-russia.ru/pdd/pdd$i.html" -o "pdd$i.html"; sleep 0.4; done

Запуск:  python3 tools/ru_content/parse_pdd.py
"""

import html
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
RAW = HERE / "raw"
OUT = ROOT / "assets" / "countries" / "ru" / "questions" / "pdd_sections.json"

SECTION_COUNT = 26

# Заголовок раздела: <title>Раздел 13 ПДД. Проезд перекрестков …</title>
TITLE_RE = re.compile(r"<h1[^>]*>(.*?)</h1>", re.S)
# Тело: элементы списка внутри ul#sign-list.
LIST_RE = re.compile(
    r'<ul class="list-group" id="sign-list">(.*?)</ul>', re.S
)
ITEM_RE = re.compile(r"<li class=\"list-group-item\">(.*?)</li>", re.S)
POINT_RE = re.compile(r"^(\d{1,2}(?:\.\d{1,2}){1,3})\.")


def to_text(fragment: str) -> str:
    """HTML-фрагмент → чистый текст с сохранением абзацев."""
    # Картинки знаков и разметки внутри текста в приложении не показываем:
    # это отдельный справочник, а здесь они ломали бы вёрстку абзаца.
    fragment = re.sub(r"<img[^>]*>", "", fragment)
    # В официальном тексте часть пунктов пронумерована надстрочным индексом:
    # 9.1¹, 13.11¹, 2.1.1¹. Простым снятием тегов они склеиваются в «9.11» и
    # «13.111» — то есть превращаются в номера других, существующих пунктов.
    # Разворачиваем индекс в ещё один уровень: 9.1.1, 13.11.1 — именно так их
    # цитируют разборы вопросов, автошколы и справочники.
    fragment = re.sub(r"(?<=\d)<sup>(\d+)</sup>", r".\1", fragment)
    # Каждый <p>/<br> — граница абзаца, иначе пункты слипнутся в простыню.
    fragment = re.sub(r"</p\s*>|<br\s*/?>", "\n", fragment, flags=re.I)
    fragment = re.sub(r"<[^>]+>", "", fragment)
    text = html.unescape(fragment)
    # Неразрывные пробелы приходят из вёрстки и мешают поиску по тексту.
    text = text.replace("\xa0", " ")
    lines = [re.sub(r"[ \t]+", " ", ln).strip() for ln in text.split("\n")]
    return "\n".join(ln for ln in lines if ln)


def parse_section(path: pathlib.Path, number: int) -> dict:
    raw = path.read_text(encoding="utf-8", errors="replace")

    m = TITLE_RE.search(raw)
    if not m:
        raise ValueError(f"{path.name}: не найден заголовок раздела")
    title = to_text(m.group(1))
    # Заголовок приходит либо как «Раздел 13 ПДД. Проезд перекрестков», либо
    # уже как «13. Проезд перекрестков» — снимаем оба вида префикса, чтобы
    # номер не задвоился, и ставим свой из имени файла.
    title = re.sub(r"^Раздел\s+\d+\s+ПДД\.?\s*", "", title).strip()
    title = re.sub(r"^\d{1,2}\.\s*", "", title).strip()
    title = f"{number}. {title}"

    body = LIST_RE.search(raw)
    if not body:
        raise ValueError(f"{path.name}: не найден список пунктов")

    blocks = []
    for item in ITEM_RE.findall(body.group(1)):
        text = to_text(item)
        if not text:
            continue
        # У части пунктов в источнике после номера нет точки («9.1.1 На любых
        # дорогах…»). Дальше по номеру ищут и приложение, и человек глазами —
        # приводим все заголовки к одному виду.
        text = re.sub(r"^(\d{1,2}(?:\.\d{1,2}){1,3})(?!\.)\s+", r"\1. ", text)
        blocks.append(text)

    if not blocks:
        raise ValueError(f"{path.name}: раздел пуст")

    return {"title": title, "content": "\n\n".join(blocks)}


def main() -> int:
    if not RAW.exists():
        print(f"нет каталога {RAW} — сначала скачайте страницы", file=sys.stderr)
        return 1

    sections = []
    for n in range(1, SECTION_COUNT + 1):
        path = RAW / f"pdd{n}.html"
        if not path.exists():
            print(f"нет файла {path}", file=sys.stderr)
            return 1
        sections.append(parse_section(path, n))

    # Проверка, ради которой всё затевалось: нумерация пунктов внутри раздела
    # должна совпадать с номером раздела. Если раздел 13 наполнен пунктами
    # 22.x — значит источник поехал, и молча записывать это нельзя.
    problems = []
    for n, sec in enumerate(sections, start=1):
        prefixes = {
            m.group(1).split(".")[0]
            for m in (POINT_RE.match(b) for b in sec["content"].split("\n\n"))
            if m
        }
        foreign = prefixes - {str(n)}
        if foreign:
            problems.append(f"{sec['title']}: чужие пункты {sorted(foreign)}")
    if problems:
        print("нумерация разделов и пунктов расходится:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1

    OUT.write_text(
        json.dumps(sections, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    points = sum(
        1
        for sec in sections
        for b in sec["content"].split("\n\n")
        if POINT_RE.match(b)
    )
    size = OUT.stat().st_size
    print(f"разделов: {len(sections)}, пунктов: {points}, {size / 1024:.0f} КБ")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
