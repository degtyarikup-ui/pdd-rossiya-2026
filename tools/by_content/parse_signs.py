#!/usr/bin/env python3
"""Сборка signs.json для Беларуси из приложения 2 к ПДД РБ (СТБ-номера).

Формат совместим с RU signs.json:
{"Категория": {"N.N": {"number", "title", "image", "description"}}}
Изображения знаков — стандартизованные символы гос. стандарта; файлы
кладутся в assets/countries/by/images/signs/ (качаются отдельно, см. URLS).
"""
import html as ihtml
import json
import os
import re

RAW = os.path.join(os.path.dirname(__file__), 'raw')
OUT_JSON = os.path.join(
    os.path.dirname(__file__), '..', '..',
    'assets', 'countries', 'by', 'questions', 'signs.json')
OUT_URLS = os.path.join(os.path.dirname(__file__), 'sign_image_urls.txt')

GROUPS = [
    ('ap2_ch1_pr1.html', 'Предупреждающие знаки'),
    ('ap2_ch1_pr2.html', 'Знаки приоритета'),
    ('ap2_ch1_pr3.html', 'Запрещающие знаки'),
    ('ap2_ch1_pr4.html', 'Предписывающие знаки'),
    ('ap2_ch1_pr5.html', 'Информационно-указательные знаки'),
    ('ap2_ch1_pr6.html', 'Знаки сервиса'),
    ('ap2_ch1_pr7.html', 'Дополнительные таблички'),
]

SIGN_RE = re.compile(
    r'<div class="sign-groupe">.*?<img[^>]+src="([^"]+)"[^>]*/>.*?'
    r'<span class="caption-sign">(.*?)</span>.*?'
    r'<span class="caption-groupe">(.*?)</span>',
    re.DOTALL)


def clean(s: str) -> str:
    s = re.sub(r'<[^>]+>', '', s)
    return ihtml.unescape(s).replace('\xa0', ' ').strip()


def main():
    result = {}
    urls = []
    total = 0
    for fname, group in GROUPS:
        path = os.path.join(RAW, fname)
        if not os.path.exists(path):
            print('WARN missing', fname)
            continue
        s = open(path, encoding='utf-8', errors='ignore').read()
        signs = {}
        for m in SIGN_RE.finditer(s):
            src, num, title = m.group(1), clean(m.group(2)), clean(m.group(3))
            if not num or not title:
                continue
            fname_img = os.path.basename(src)
            signs[num] = {
                'number': num,
                'title': title,
                'image': f'./images/signs/{fname_img}',
                'description': title,
            }
            urls.append('https://adrive.by' + src if src.startswith('/') else src)
        if signs:
            result[group] = signs
            total += len(signs)
            print(f'{group}: {len(signs)}')
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    json.dump(result, open(OUT_JSON, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    open(OUT_URLS, 'w').write('\n'.join(dict.fromkeys(urls)))
    print(f'TOTAL {total} signs -> {os.path.relpath(OUT_JSON)}')


if __name__ == '__main__':
    main()
