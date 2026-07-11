#!/usr/bin/env python3
"""Парсер официального текста ПДД РБ из сохранённых HTML-глав (adrive.by).

Текст ПДД — официальный документ (Указ №551), не объект авторского права.
Собирает assets/countries/by/questions/pdd_sections.json в формате приложения:
[{"title": "...", "content": "..."}, ...]
"""
import html as ihtml
import json
import os
import re

RAW = os.path.join(os.path.dirname(__file__), 'raw')
OUT = os.path.join(
    os.path.dirname(__file__), '..', '..',
    'assets', 'countries', 'by', 'questions', 'pdd_sections.json')


def strip_tags(s: str) -> str:
    s = re.sub(r'<br\s*/?>', '\n', s)
    s = re.sub(r'<[^>]+>', '', s)
    s = ihtml.unescape(s)
    s = s.replace('\xa0', ' ')
    return re.sub(r'[ \t]+', ' ', s).strip()


def parse_chapter(path: str):
    s = open(path, encoding='utf-8', errors='ignore').read()
    m = re.search(r'<h3>(Глава\s*\d+)<br\s*/?>(.*?)</h3>', s)
    if not m:
        return None
    num = strip_tags(m.group(1))          # «Глава 11»
    name = strip_tags(m.group(2))         # «Скорость движения…»
    n = re.search(r'\d+', num).group(0)
    title = f'{n}. {name}'

    points = []
    for item in re.finditer(
            r'<div class="pdd-item"[^>]*>\s*<div class="text">(.*?)</div>\s*</div>',
            s, re.DOTALL):
        text = strip_tags(item.group(1))
        if text:
            points.append(text)
    if not points:
        # fallback: без обёртки .text
        for item in re.finditer(
                r'<span class="pdd-num">(.*?)</span>\s*<span class="pdd-text">(.*?)</span>',
                s, re.DOTALL):
            points.append(
                (strip_tags(item.group(1)) + ' ' + strip_tags(item.group(2))).strip())
    return {'n': int(n), 'title': title, 'content': '\n\n'.join(points)}


def main():
    sections = []
    for i in range(1, 28):
        p = os.path.join(RAW, f'ch{i}.html')
        if not os.path.exists(p):
            continue
        sec = parse_chapter(p)
        if sec and sec['content']:
            sections.append(sec)
        else:
            print(f'WARN: empty chapter ch{i}')
    sections.sort(key=lambda x: x['n'])
    out = [{'title': s['title'], 'content': s['content']} for s in sections]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    total = sum(len(s['content']) for s in out)
    print(f'OK: {len(out)} chapters, {total} chars -> {os.path.relpath(OUT)}')


if __name__ == '__main__':
    main()
