#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Собирает assets/countries/rs/questions/signs.json из:
  - каталога категорий (signs_catalog.py),
  - сербских названий/описаний (sign_names_sr.json, из воркфлоу),
  - реально скачанных SVG (assets/countries/rs/images/signs/<code>.svg).

Формат как ожидает signs_screen: { категория: { код: {number,title,image,description} } }.
Знак попадает в JSON только если для него есть и SVG, и сербское название.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from signs_catalog import CATEGORIES  # noqa: E402

HERE = os.path.dirname(__file__)
IMG_DIR = os.path.join("assets", "countries", "rs", "images", "signs")
OUT = os.path.join("assets", "countries", "rs", "questions", "signs.json")


def build():
    names = {s["code"]: s for s in
             json.load(open(os.path.join(HERE, "sign_names_sr.json")))}
    have_svg = {f[:-4] for f in os.listdir(IMG_DIR) if f.endswith(".svg")}

    signs = {}
    missing = []
    for cat, items in CATEGORIES:
        bucket = {}
        for code, wiki, en in items:
            if code not in have_svg:
                missing.append((code, "no svg"))
                continue
            if code not in names:
                missing.append((code, "no name"))
                continue
            bucket[code] = {
                "number": code,
                "title": names[code]["naziv"],
                "image": f"{code}.svg",
                "description": names[code]["opis"],
            }
        if bucket:
            signs[cat] = bucket

    json.dump(signs, open(OUT, "w"), ensure_ascii=False, indent=2)
    total = sum(len(v) for v in signs.values())
    print(f"signs.json: {total} signs in {len(signs)} categories")
    for cat, b in signs.items():
        print(f"  {cat}: {len(b)}")
    if missing:
        print("skipped:", missing)


if __name__ == "__main__":
    build()
