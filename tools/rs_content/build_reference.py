#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Разметка Сербии (латиница) — авторские краткие описания дорожной разметки.

Пишет:
  assets/countries/rs/questions/markup.json

ВАЖНО: этот скрипт больше НЕ трогает signs.json и pdd_sections.json — они
были заменены официальными источниками и этот файл их писать не должен
(раньше содержал устаревшие авторские версии обоих, что рисковало откатить
их при повторном запуске):
  - signs.json — реальные знаки (Венская конвенция, SVG с Wikimedia Commons),
    собирается download_signs.py + build_signs_final.py.
  - pdd_sections.json — дословный текст официального закона (Zakon o
    bezbednosti saobraćaja na putevima, Sl. glasnik RS 41/2009...19/2025,
    действующая редакция на 2026-07-14), собирается parse_law.py из
    сохранённого HTML propisi.net (см. этот файл — открытый консолидированный
    текст, включает поправки 19/2025 вступившие в силу с 2026-01-01).

Разметка (markup.json) пока остаётся авторским кратким изложением — если
понадобится дословный официальный источник (Pravilnik o saobraćajnoj
signalizaciji), сделать для неё отдельный парсер по аналогии с parse_law.py.
"""
import json
import os

# --- Дорожная разметка Сербии (латиница). ---
MARKUP = {
    "Horizontalna signalizacija": [
        ("Puna razdelna linija",
         "Razdvaja suprotne smerove ili trake; zabranjeno je preći je ili "
         "voziti po njoj."),
        ("Isprekidana razdelna linija",
         "Razdvaja trake; sme se preći kada je to bezbedno (npr. pri "
         "preticanju ili promeni trake)."),
        ("Dvostruka puna linija",
         "Razdvaja kolovozne trake suprotnih smerova; zabranjeno je preći je."),
        ("Zaustavna linija",
         "Poprečna puna linija na mestu na kome se vozilo zaustavlja (STOP, "
         "semafor)."),
        ("Pešački prelaz („zebra“)",
         "Obeleženi deo kolovoza namenjen prelasku pešaka."),
        ("Strelice za usmeravanje",
         "Označavaju dozvoljene smerove kretanja iz trake pred raskrsnicu."),
    ],
    "Vertikalna signalizacija": [
        ("Oznake na ivičnjacima",
         "Naizmenične oznake na ivičnjaku ističu mesta na kojima je "
         "zaustavljanje ograničeno ili opasno."),
        ("Oznake na preprekama",
         "Kose linije na branicima i preprekama upozoravaju na fizičku "
         "prepreku uz kolovoz."),
    ],
}

def build():
    out_dir = os.path.join("assets", "countries", "rs", "questions")
    os.makedirs(out_dir, exist_ok=True)

    markup = {
        group: [{"title": t, "description": d} for t, d in items]
        for group, items in MARKUP.items()
    }
    with open(os.path.join(out_dir, "markup.json"), "w", encoding="utf-8") as f:
        json.dump(markup, f, ensure_ascii=False, indent=2)

    print(f"markup groups: {len(markup)}")


if __name__ == "__main__":
    build()
