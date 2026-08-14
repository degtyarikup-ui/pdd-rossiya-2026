#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Каталог дорожных знаков Сербии: код, файл на Wikimedia, англ. имя, категория.

Источник изображений — Wikimedia Commons (свободная лицензия), имена файлов
вида ``Serbia_road_sign_<CODE>.svg``. Категории Сербии (Pravilnik o
saobraćajnoj signalizaciji):
  I-*   → «Znakovi opasnosti»          (предупреждающие)
  II-*  → «Znakovi izričitih naredbi»  (запрещающие/обязательные/приоритет)
  III-* → «Znakovi obaveštenja»        (информационные)

Только актуальные знаки (без устаревших «до 2014»). Сербские имена/описания
добавляются генератором в build_signs_from_catalog.py.
Формат записи: (code, wikimedia_filename, english_name).
"""

WARNING = [  # I-* «Znakovi opasnosti»
    ("I-1", "Serbia_road_sign_I-1.svg", "Curve to left"),
    ("I-1.1", "Serbia_road_sign_I-1.1.svg", "Curve to right"),
    ("I-2", "Serbia_road_sign_I-2.svg", "Double curve, first to left"),
    ("I-2.1", "Serbia_road_sign_I-2.1.svg", "Double curve, first to right"),
    ("I-3", "Serbia_road_sign_I-3.svg", "Steep uphill"),
    ("I-4", "Serbia_road_sign_I-4.svg", "Steep downhill"),
    ("I-5.1", "Serbia_road_sign_I-5.1.svg", "Road narrows on right side"),
    ("I-5.2", "Serbia_road_sign_I-5.2.svg", "Road narrows on left side"),
    ("I-7", "Serbia_road_sign_I-7.svg", "Quayside or riverbank"),
    ("I-8", "Serbia_road_sign_I-8.svg", "Uneven road"),
    ("I-9", "Serbia_road_sign_I-9.svg", "Dip"),
    ("I-10", "Serbia_road_sign_I-10.svg", "Bump"),
    ("I-11", "Serbia_road_sign_I-11.svg", "Slippery road"),
    ("I-12", "Serbia_road_sign_I-12.svg", "Loose gravel"),
    ("I-13", "Serbia_road_sign_I-13.svg", "Falling rocks from the left"),
    ("I-13.1", "Serbia_road_sign_I-13.1.svg", "Falling rocks from the right"),
    ("I-14", "Serbia_road_sign_I-14.svg", "Pedestrian crossing"),
    ("I-15", "Serbia_road_sign_I-15.svg", "Children"),
    ("I-16", "Serbia_road_sign_I-16.svg", "Cyclists"),
    ("I-17", "Serbia_road_sign_I-17.svg", "Cattle"),
    ("I-18", "Serbia_road_sign_I-18.svg", "Deer / wild animals"),
    ("I-19", "Serbia_road_sign_I-19.svg", "Roadworks"),
    ("I-22", "Serbia_road_sign_I-22.svg", "Crosswinds from left"),
    ("I-23", "Serbia_road_sign_I-23.svg", "Two-way traffic"),
    ("I-24", "Serbia_road_sign_I-24.svg", "Tunnel"),
    ("I-25", "Serbia_road_sign_I-25.svg", "Other dangers"),
    ("I-26", "Serbia_road_sign_I-26.svg", "Intersection with right-priority rule"),
    ("I-27", "Serbia_road_sign_I-27.svg", "Intersection on priority road"),
    ("I-30", "Serbia_road_sign_I-30.svg", "Roundabout ahead"),
    ("I-31", "Serbia_road_sign_I-31.svg", "Tramway"),
    ("I-32", "Serbia_road_sign_I-32.svg", "Level crossing with barriers ahead"),
    ("I-33", "Serbia_road_sign_I-33.svg", "Level crossing without barriers"),
    ("I-34", "Serbia_road_sign_I-34.svg", "Single track level crossing"),
    ("I-34.1", "Serbia_road_sign_I-34.1.svg", "Multi-track level crossing"),
    ("I-37", "Serbia_road_sign_I-37.svg", "Soft verges"),
    ("I-38", "Serbia_road_sign_I-38.svg", "Traffic queues"),
]

ORDERS = [  # II-* «Znakovi izričitih naredbi»
    ("II-1", "Serbia_road_sign_II-1.svg", "Give way"),
    ("II-2", "Serbia_road_sign_II-2.svg", "Stop"),
    ("II-3", "Serbia_road_sign_II-3.svg", "All vehicles prohibited both directions"),
    ("II-4", "Serbia_road_sign_II-4.svg", "No entry"),
    ("II-5", "Serbia_road_sign_II-5.svg", "No motor vehicles except motorcycles"),
    ("II-6", "Serbia_road_sign_II-6.svg", "No buses"),
    ("II-7", "Serbia_road_sign_II-7.svg", "No trucks"),
    ("II-12", "Serbia_road_sign_II-12.svg", "No motorcycles"),
    ("II-13", "Serbia_road_sign_II-13.svg", "No mopeds"),
    ("II-14", "Serbia_road_sign_II-14.svg", "No bicycles"),
    ("II-17", "Serbia_road_sign_II-17.svg", "No pedestrians"),
    ("II-20", "Serbia_road_sign_II-20.svg", "Maximum width"),
    ("II-21", "Serbia_road_sign_II-21.svg", "Maximum height"),
    ("II-22", "Serbia_road_sign_II-22.svg", "Maximum weight"),
    ("II-23", "Serbia_road_sign_II-23.svg", "Maximum weight per axle"),
    ("II-24", "Serbia_road_sign_II-24.svg", "Maximum length"),
    ("II-25", "Serbia_road_sign_II-25.svg", "Minimum following distance"),
    ("II-26", "Serbia_road_sign_II-26.svg", "No left turn"),
    ("II-26.1", "Serbia_road_sign_II-26.1.svg", "No right turn"),
    ("II-27", "Serbia_road_sign_II-27.svg", "No U-turn"),
    ("II-28", "Serbia_road_sign_II-28.svg", "No overtaking"),
    ("II-29", "Serbia_road_sign_II-29.svg", "No overtaking by trucks"),
    ("II-30", "Serbia_road_sign_II-30-40.svg", "Maximum speed limit"),
    ("II-31", "Serbia_road_sign_II-31.svg", "No horns"),
    ("II-33", "Serbia_road_sign_II-33.svg", "Give way to oncoming traffic"),
    ("II-34", "Serbia_road_sign_II-34.svg", "No stopping"),
    ("II-35", "Serbia_road_sign_II-35.svg", "No parking"),
    ("II-38", "Serbia_road_sign_II-38-40.svg", "Minimum speed limit"),
    ("II-39", "Serbia_road_sign_II-39.svg", "Snow chains mandatory"),
    ("II-40", "Serbia_road_sign_II-40.svg", "Bike path"),
    ("II-41", "Serbia_road_sign_II-41.svg", "Pedestrian path"),
    ("II-43", "Serbia_road_sign_II-43.svg", "Proceed straight"),
    ("II-43.1", "Serbia_road_sign_II-43.1.svg", "Turn right"),
    ("II-43.2", "Serbia_road_sign_II-43.2.svg", "Turn left"),
    ("II-44", "Serbia_road_sign_II-44.svg", "Proceed straight or turn left"),
    ("II-44.1", "Serbia_road_sign_II-44.1.svg", "Proceed straight or turn right"),
    ("II-45", "Serbia_road_sign_II-45.svg", "Pass onto right"),
    ("II-45.1", "Serbia_road_sign_II-45.1.svg", "Pass onto left"),
    ("II-45.2", "Serbia_road_sign_II-45.2.svg", "Roundabout (mandatory)"),
    ("II-46", "Serbia_road_sign_II-46.svg", "U-turn"),
]

INFO = [  # III-* «Znakovi obaveštenja»
    ("III-1", "Serbia_road_sign_III-1.svg", "Priority over oncoming traffic"),
    ("III-2", "Serbia_road_sign_III-2.svg", "One-way street"),
    ("III-3", "Serbia_road_sign_III-3.svg", "Priority road"),
    ("III-4", "Serbia_road_sign_III-4.svg", "End of priority road"),
    ("III-5", "Serbia_road_sign_III-5.svg", "Cyclist crossing"),
    ("III-6", "Serbia_road_sign_III-6.svg", "Pedestrian crossing"),
    ("III-9", "Serbia_road_sign_III-9.svg", "Dead end"),
    ("III-25", "Serbia_road_sign_III-25.svg", "End of overtaking prohibition"),
    ("III-30", "Serbia_road_sign_III-30-2017.svg", "Parking"),
    ("III-31", "Serbia_road_sign_III-31-2017.svg", "Parking garage"),
    ("III-34", "Serbia_road_sign_III-34.svg", "Hospital"),
    ("III-35", "Serbia_road_sign_III-35.svg", "First aid"),
    ("III-37", "Serbia_road_sign_III-37.svg", "Telephone"),
    ("III-38", "Serbia_road_sign_III-38.svg", "Petrol station"),
    ("III-39", "Serbia_road_sign_III-39.svg", "Hotel or motel"),
    ("III-40", "Serbia_road_sign_III-40.svg", "Restaurant"),
    ("III-49", "Serbia_road_sign_III-49.svg", "Bus stop"),
    ("III-50", "Serbia_road_sign_III-50.svg", "Tram stop"),
    ("III-53", "Serbia_road_sign_III-53.svg", "Information"),
    ("III-68", "Serbia_road_sign_III-68_2017.svg", "Motorway"),
    ("III-68.1", "Serbia_road_sign_III-68.1.svg", "End of motorway"),
    ("III-21", "Serbia_road_sign_III-21.svg", "Expressway"),
    ("III-22", "Serbia_road_sign_III-22.svg", "End of expressway"),
    ("III-23.1", "Serbia_road_sign_III-23.1.svg", "Built-up area"),
    ("III-24.1", "Serbia_road_sign_III-24.1.svg", "End of built-up area"),
]

CATEGORIES = [
    ("Znakovi opasnosti", WARNING),
    ("Znakovi izričitih naredbi", ORDERS),
    ("Znakovi obaveštenja", INFO),
]


def all_entries():
    """Возвращает [(category, code, wiki_filename, english)]."""
    out = []
    for cat, items in CATEGORIES:
        for code, wiki, en in items:
            out.append((cat, code, wiki, en))
    return out


if __name__ == "__main__":
    entries = all_entries()
    print(f"catalog: {len(entries)} signs in {len(CATEGORIES)} categories")
    for cat, items in CATEGORIES:
        print(f"  {cat}: {len(items)}")
