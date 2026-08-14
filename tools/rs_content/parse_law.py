#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Парсер официального актуального текста Zakon o bezbednosti saobraćaja na
putevima (Sl. glasnik RS 41/2009...19/2025, действующая редакция) из сохранённого
HTML (propisi.net, открытый консолидированный текст закона).

Закон — официальный государственный документ, не объект авторского права.
Заменяет авторский пересказ (11 секций) на дословный текст 22 глав закона.

Собирает assets/countries/rs/questions/pdd_sections.json в формате приложения:
[{"title": "I. Osnovne odredbe", "content": "Član 1.\n...\n\nČlan 2.\n..."}, ...]

Использование: python3 tools/rs_content/parse_law.py <raw_html_path>
"""
import html as ihtml
import json
import os
import re
import sys

OUT = os.path.join('assets', 'countries', 'rs', 'questions', 'pdd_sections.json')

CHAPTER_RE = re.compile(r'<p class="P\d+"><span>([IVXLCDM]+)\.\s*([^<]{3,300})</span></p>')
END_MARKER = 'U REDAKCIJSKOM PREČIŠĆENOM TEKSTU NE NALAZE SE'


def strip_tags(s: str) -> str:
    s = re.sub(r'<br\s*/?>', '\n', s)
    s = re.sub(r'<[^>]+>', '', s)
    s = ihtml.unescape(s)
    s = s.replace('​', '').replace('﻿', '').replace('\xa0', ' ')
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r'\n{3,}', '\n\n', s)
    return s.strip()


def main():
    raw_path = sys.argv[1]
    html = open(raw_path, encoding='utf-8', errors='ignore').read()

    chapters = list(CHAPTER_RE.finditer(html))
    end_idx = html.index(END_MARKER)

    sections = []
    for i, m in enumerate(chapters):
        num, title = m.group(1), strip_tags(m.group(2))
        body_start = m.end()
        body_end = chapters[i + 1].start() if i + 1 < len(chapters) else end_idx
        body_html = html[body_start:body_end]

        # Собираем текст параграф-за-параграфом (каждый <p> — отдельный абзац).
        paras = re.findall(r'<p[^>]*>(.*?)</p>', body_html, re.DOTALL)
        text_paras = [strip_tags(p) for p in paras]
        text_paras = [p for p in text_paras if p]
        content = '\n\n'.join(text_paras)

        sections.append({'title': f'{num}. {title}', 'content': content})

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(sections, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    total_chars = sum(len(s['content']) for s in sections)
    print(f'OK: {len(sections)} glava, {total_chars} chars -> {OUT}')
    for s in sections:
        print(f"  {s['title'][:70]:70s} {len(s['content']):>7d} chars")


if __name__ == '__main__':
    main()
