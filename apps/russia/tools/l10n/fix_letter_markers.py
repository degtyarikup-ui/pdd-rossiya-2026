#!/usr/bin/env python3
"""
tools/l10n/fix_letter_markers.py

Ensures that in ticket and topic answers where questions refer to labels/trajectories/signs
marked as А, Б, В, Г on illustrations, the answer choices in English and Kazakh strictly
preserve Cyrillic letters: А (U+0410), Б (U+0411), В (U+0412), Г (U+0413).
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QUESTIONS_DIR = os.path.join(REPO_ROOT, "assets", "countries", "ru", "questions")
CACHE_EN = os.path.join(HERE, "cache_en.json")
CACHE_KK = os.path.join(HERE, "cache_kk.json")

# Cyrillic Unicode code points:
# А: \u0410
# Б: \u0411
# В: \u0412
# Г: \u0413

EXPLICIT_LETTER_ANSWERS = {
    # Single letters
    'А': ('А', 'А'),
    'Б': ('Б', 'Б'),
    'В': ('В', 'В'),
    'Г': ('Г', 'Г'),

    # Simple combinations
    'А и Б': ('А and Б', 'А және Б'),
    'А и В': ('А and В', 'А және В'),
    'А и Г': ('А and Г', 'А және Г'),
    'А или В': ('А or В', 'А немесе В'),
    'Б и В': ('Б and В', 'Б және В'),
    'Б и Г': ('Б and Г', 'Б және Г'),
    'Б или В': ('Б or В', 'Б немесе В'),
    'Б или Г': ('Б or Г', 'Б немесе Г'),
    'Б, В и Г': ('Б, В and Г', 'Б, В және Г'),
    'В и Г': ('В and Г', 'В және Г'),

    # Direction phrases
    'В направлениях А и Б': ('In directions А and Б', 'А және Б бағыттары бойынша'),
    'В направлениях А и В': ('In directions А and В', 'А және Б бағыттары бойынша'),
    'В направлениях А или Б': ('In directions А or Б', 'А немесе Б бағыттарында'),
    'В направлениях Б и В': ('In directions Б and В', 'Б және В бағыттары бойынша'),
    'В направлениях Б и Г': ('In directions Б and Г', 'Б және Г бағыттары бойынша'),
    'В направлениях Б или В': ('In directions Б or В', 'Б немесе В бағыттары бойынша'),
    'Во всех указанных направлениях, кроме Г': ('In all indicated directions except Г', 'Г-ден басқа барлық көрсетілген бағыттар бойынша'),

    # Trajectories
    'По А или Б': ('By А or Б', 'А немесе Б арқылы'),
    'По траекториям А или Б': ('On trajectories А or Б', 'А немесе Б траекториялары бойынша'),
    'По траекториям А или В': ('On trajectories А or В', 'А немесе В траекториялары бойынша'),
    'По траекториям Б или В': ('On trajectories Б or В', 'Б немесе В траекториялары бойынша'),
    'Разрешается только по траектории А': ('Allowed only along trajectory А', 'А траекториясы бойынша ғана рұқсат етіледі'),
    'Разрешается только по траектории Б': ('Allowed only along trajectory Б', 'Тек Б траекториясы бойынша рұқсат етіледі'),
    'Можно только по траектории А': ('Possible only along trajectory А', 'А траекториясы бойынша ғана мүмкін'),
    'Можно только по траектории Б': ('Possible only along trajectory Б', 'Тек Б траекториясы бойынша мүмкін'),
    'Только по траектории А': ('Only along trajectory А', 'Тек А траекториясы бойынша'),
    'Только по траектории Б': ('Only along trajectory Б', 'Тек Б траекториясы бойынша'),
    'Только по траектории В': ('Only along trajectory В', 'Тек В траекториясы бойынша'),
    'Только на перекрестке — по траектории А': ('Only at the intersection - along trajectory А', 'Тек қиылысында – А траекториясының бойымен'),
    'Только перед перекрестком — по траектории Б': ('Only before the intersection - along trajectory Б', 'Тек қиылыс алдында – Б траекториясы бойынша'),

    # "Only" letters
    'Только А': ('Only А', 'Тек А'),
    'Только Б': ('Only Б', 'Тек Б'),
    'Только В': ('Only В', 'Тек В'),
    'Только Г': ('Only Г', 'Тек Г'),
    'Только по А': ('Only on А', 'Тек А'),
    'Только по Б': ('Only on Б', 'Тек Б'),
    'Только на А': ('Only on А', 'Тек А'),
    'Только на Б': ('Only on Б', 'Тек Б'),
    'Только в направлении А': ('Only in direction А', 'Тек А бағытында'),
    'Только в направлении Б': ('Only in direction Б', 'Тек Б бағытында'),
    'Только в направлении В': ('Only in direction В', 'Тек В бағытында'),

    # Parenthesized markers
    'Перед знаком (А)': ('Before the sign (А)', '(А) белгісінің алдында'),
    'Перед перекрестком (Б)': ('Before the intersection (Б)', 'Қиылыс алдында (Б)'),
    'Перед краем пересекаемой проезжей части (В)': ('Before the edge of the intersecting roadway (В)', 'Қиылысатын жолдың шетіне дейін (В)'),

    # Vehicles and drivers
    'Автобусов А и Б': ('Buses А and Б', 'А және Б автобустары'),
    'Автомобилей А и Б': ('Cars А and Б', 'А және Б автомобильдері'),
    'Автомобилей А и В': ('Cars А and В', 'А және Б автомобильдері'),
    'Автомобилей Б и В': ('Cars Б and В', 'Б және В автомобильдері'),
    'Водители автомобилей А и Б': ('Drivers of cars А and Б', 'А және Б автокөліктерінің жүргізушілері'),
    'Водители автомобилей А и В': ('Drivers of cars А and В', 'А және В автокөліктерінің жүргізушілері'),
    'Маломестного автобуса Б и грузового автомобиля В': ('Small bus Б and truck В', 'Шағын автобус Б және жүк көлігі В'),
    'Можно, если грузовой автомобиль А двигается со скоростью менее 30 км/час': (
        'It is possible if truck А is moving at a speed of less than 30 km/h',
        'А жүк көлігі 30 км/сағ аз жылдамдықпен қозғалса мүмкін'
    ),
    'Только автобуса А': ('Only bus А', 'Тек А автобусы'),
    'Только автобуса Б': ('Only bus Б', 'Тек Б автобусы'),
    'Только автомобиля А': ('Only car А', 'Тек А көлігі'),
    'Только автомобиля Б': ('Only car Б', 'Тек Б көлігі'),
    'Только автомобиля В': ('Only car В', 'Тек В көлігі'),
    'Только водитель автомобиля А': ('Only the driver of car А', 'Тек көлік жүргізушісі А'),
    'Только водитель автомобиля Б': ('Only the driver of car Б', 'Тек көлік жүргізушісі Б'),
    'Только водитель автомобиля В': ('Only the driver of car В', 'Тек көлік жүргізушісі В'),
    'Только водитель мопеда А': ('Moped driver А only', 'Тек мопед жүргізушісі А'),
    'Только водитель мопеда Б': ('Moped driver Б only', 'Тек мопед жүргізушісі Б'),
    'Только водитель транспортного средства А': ('Only the driver of vehicle А', 'Тек көлік жүргізушісі А'),
    'Только водитель транспортного средства Б': ('Only the driver of vehicle Б', 'Тек көлік жүргізушісі Б'),
    'Только маломестного автобуса Б': ('Only small bus Б', 'Тек шағын автобус Б'),

    # Trams
    'Только трамваю А': ('Only tram А', 'Тек трамвай А'),
    'Только трамваю Б': ('Only tram Б', 'Тек Б трамвайы'),
    'Трамваю А и легковому автомобилю': ('Tram А and passenger car', 'А трамвай және жеңіл автокөлік'),
    'Трамваю Б и легковому автомобилю': ('Tram Б and passenger car', 'Б трамвай және жеңіл автокөлік'),
    'Трамваям А и Б': ('Trams А and Б', 'А және Б трамвайлары'),
    'Уступите дорогу только трамваю А': ('Give way only to tram А', 'Тек А трамвайына жол беріңіз'),
    'Уступите дорогу только трамваю Б': ('Give way only to tram Б', 'Тек Б трамвайына жол беріңіз'),
    'Уступить дорогу только трамваю А': ('Give way only to tram А', 'Тек А трамвайына жол беріңіз'),
    'Уступить дорогу только трамваю Б': ('Give way only to tram Б', 'Тек Б трамвайына жол беріңіз'),
}

def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)

def apply_fixes():
    # 1. Update caches
    cache_en = load_json(CACHE_EN)
    cache_kk = load_json(CACHE_KK)

    for ru_text, (en_text, kk_text) in EXPLICIT_LETTER_ANSWERS.items():
        cache_en[ru_text] = en_text
        cache_kk[ru_text] = kk_text

    # Also ensure marking question with letter 'А'
    for q_ru in ['Разметкой в виде буквы «А» обозначают?', 'Разметкой в виде буквы «А» обозначают:']:
        cache_en[q_ru] = 'Markings in the form of the letter “А” indicate:' if q_ru.endswith(':') else 'Markings in the form of the letter “А” indicate?'
        cache_kk[q_ru] = '«А» әрпі түріндегі белгілер мынаны көрсетеді:' if q_ru.endswith(':') else '«А» әрпі түріндегі таңбалар көрсетеді?'

    save_json(CACHE_EN, cache_en)
    save_json(CACHE_KK, cache_kk)
    print("Updated cache_en.json and cache_kk.json with 77 explicit letter answers.")

    # 2. Update questions files
    for cat in ['ab', 'cd']:
        for lang, cache in [('en', cache_en), ('kk', cache_kk)]:
            ru_file = os.path.join(QUESTIONS_DIR, f"questions_{cat}.json")
            target_file = os.path.join(QUESTIONS_DIR, f"questions_{cat}_{lang}.json")
            ru_data = load_json(ru_file)
            target_data = load_json(target_file)

            updated_answers = 0
            for t_idx, ru_ticket in enumerate(ru_data['tickets']):
                target_ticket = target_data['tickets'][t_idx]
                for q_idx, ru_q in enumerate(ru_ticket['questions']):
                    target_q = target_ticket['questions'][q_idx]
                    ru_q_text = ru_q['question']
                    if ru_q_text in cache:
                        target_q['question'] = cache[ru_q_text]
                    for a_idx, ru_a in enumerate(ru_q['answers']):
                        ru_ans_text = ru_a['text']
                        if ru_ans_text in EXPLICIT_LETTER_ANSWERS:
                            target_ans = target_q['answers'][a_idx]
                            new_val = cache[ru_ans_text]
                            if target_ans['text'] != new_val:
                                target_ans['text'] = new_val
                                updated_answers += 1

            save_json(target_file, target_data)
            print(f"Updated {target_file}: applied fixes to {updated_answers} answer options.")

    # 3. Update topics files
    for cat in ['ab', 'cd']:
        for lang, cache in [('en', cache_en), ('kk', cache_kk)]:
            ru_file = os.path.join(QUESTIONS_DIR, f"topics_{cat}.json")
            target_file = os.path.join(QUESTIONS_DIR, f"topics_{cat}_{lang}.json")
            ru_data = load_json(ru_file)
            target_data = load_json(target_file)

            updated_answers = 0
            for top_idx, ru_top in enumerate(ru_data['topics']):
                target_top = target_data['topics'][top_idx]
                for q_idx, ru_q in enumerate(ru_top['questions']):
                    target_q = target_top['questions'][q_idx]
                    ru_q_text = ru_q['question']
                    if ru_q_text in cache:
                        target_q['question'] = cache[ru_q_text]
                    for a_idx, ru_a in enumerate(ru_q['answers']):
                        ru_ans_text = ru_a['text']
                        if ru_ans_text in EXPLICIT_LETTER_ANSWERS:
                            target_ans = target_q['answers'][a_idx]
                            new_val = cache[ru_ans_text]
                            if target_ans['text'] != new_val:
                                target_ans['text'] = new_val
                                updated_answers += 1

            save_json(target_file, target_data)
            print(f"Updated {target_file}: applied fixes to {updated_answers} topic answer options.")

if __name__ == "__main__":
    apply_fixes()
