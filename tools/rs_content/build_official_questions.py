#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Собирает official_questions.json из полной официальной базы MUP +
подтверждённых ответов (см. rs_official_answers_workflow.js).

Вход:
  - master dataset: список вопросов {gid, category, question, options[],
    points, image (путь к PNG или null)} — из extract_questions.py по всем
    7 категориям, после структурного фильтра mup_lib.is_garbled и исключения
    вопросов с несколькими верными ответами (мультиселект — отдельная фича,
    пока не реализован UI).
  - confirmed answers: [{"gid": ..., "index": <0-based верный>, "source":
    "agreed"|"judge"}] — только вопросы, где сошлись оба независимых прохода
    определения ответа (либо разрешил третий агент-судья). Вопросы без
    консенсуса ИЛИ с провалившимся батчем в выход не попадают — точность
    важнее полноты.

Делает:
  - конвертирует картинки вопросов PNG→JPG в assets/countries/rs/images/questions_ab/,
  - формирует список вопросов в схеме приложения, topic = отображаемое имя
    официальной категории MUP (для вкладки «Oblasti»).

Использование: python3 build_official_questions.py <master.json> <confirmed.json> <out.json>
"""
import glob
import json
import os
import re
import sys

import fitz  # PNG -> JPG через pixmap

QIMG_DIR = os.path.join("assets", "countries", "rs", "images", "questions_ab")

# Официальные PDF MUP формулируют вопрос как начало предложения, а варианты
# ответа — как его грамматическое продолжение («...voziti:» + «brzinom od
# 50 km/h,» / «...80 km/h.»), поэтому почти все варианты в сыром тексте
# заканчиваются запятой или точкой. В UI варианты — самостоятельные пункты
# списка, а не части одного предложения (как и в RU/BY), так что финальную
# пунктуацию убираем; смысл и формулировка не меняются.
def clean_answer_text(t):
    return re.sub(r'[\s,.]+$', '', t)

TOPIC_NAMES = {
    'pravila': 'Pravila saobraćaja',
    'sig': 'Saobraćajna signalizacija',
    'vozaci': 'Vozači',
    'vozila': 'Vozila',
    'osnove': 'Osnove bezbednosti saobraćaja i pojmovi',
    'mere': 'Posebne mere i ovlašćenja',
    'posledice': 'Posledice nepoštovanja propisa',
}
# Порядок вкладки «Oblasti» — по значимости для экзамена A/B (знаки и правила
# первыми), не порядок появления в PDF.
CATEGORY_ORDER = ['pravila', 'sig', 'vozaci', 'vozila', 'osnove', 'mere', 'posledice']


def png_to_jpg(src_png, dst_jpg):
    pix = fitz.Pixmap(src_png)
    if pix.alpha:
        pix = fitz.Pixmap(pix, 0)
    pix.save(dst_jpg, jpg_quality=88)


def build(master_path, confirmed_path, out_path):
    master = {q['gid']: q for q in json.load(open(master_path, encoding='utf-8'))}
    confirmed = json.load(open(confirmed_path, encoding='utf-8'))

    os.makedirs(QIMG_DIR, exist_ok=True)
    # Чистим каталог картинок вопросов от прошлых прогонов — чтобы не оставались
    # осиротевшие JPG (у вопросов другая нумерация gid между прогонами).
    for old in glob.glob(os.path.join(QIMG_DIR, "*.jpg")):
        os.remove(old)
    by_category = {cat: [] for cat in CATEGORY_ORDER}
    skipped_bad_index = 0
    for c in confirmed:
        q = master.get(c['gid'])
        if not q:
            continue
        idx = c['index']
        if idx < 0 or idx >= len(q['options']):
            skipped_bad_index += 1
            continue

        img_name = None
        if q['image'] and os.path.exists(q['image']):
            base = f"rs_{q['gid']}"
            dst = os.path.join(QIMG_DIR, f"{base}.jpg")
            png_to_jpg(q['image'], dst)
            img_name = base

        by_category.setdefault(q['category'], []).append({
            'id': f"rs_{q['gid']}",
            'question': q['question'],
            'answers': [{'text': clean_answer_text(t), 'correct': (i == idx)}
                        for i, t in enumerate(q['options'])],
            'comment': '',
            'pddPoints': [],
            'points': q.get('points', 1),
            'image': img_name,
            'topic': [TOPIC_NAMES.get(q['category'], q['category'])],
        })

    # Порядок вкладки «Oblasti» = CATEGORY_ORDER, не порядок появления в PDF.
    out = [q for cat in CATEGORY_ORDER for q in by_category.get(cat, [])]

    json.dump(out, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    n_img = sum(1 for q in out if q['image'])
    print(f"official_questions.json: {len(out)} questions "
          f"(with image: {n_img}) | skipped_bad_index={skipped_bad_index}")


if __name__ == '__main__':
    _, master_path, confirmed_path, out_path = sys.argv[:4]
    build(master_path, confirmed_path, out_path)
