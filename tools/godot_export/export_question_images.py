#!/usr/bin/env python3
"""The original ticket pictures of the game's questions -> game_godot/questions/<hash>.webp
and game_godot/questions/index.json ({scene id: hash}). The question card shows the picture
when the ticket chip is tapped.
    python3 tools/godot_export/export_question_images.py
"""
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game_godot" / "questions"
IMAGES = ROOT / "assets" / "countries" / "ru" / "images" / "questions_ab"
tickets = json.loads((ROOT / "assets/countries/ru/questions/questions_ab.json").read_text(encoding="utf-8"))["tickets"]
index = {}
for p in sorted((ROOT / "game_godot" / "network").glob("ticket_*.json")):
    m = re.match(r"ticket_(\d+)_(\d+)$", p.stem)
    q = tickets[int(m[1]) - 1]["questions"][int(m[2]) - 1]
    if q.get("image"):
        index[p.stem] = q["image"]
for s in json.loads((ROOT / "game_godot/roads/road_scenes.json").read_text(encoding="utf-8"))["scenes"]:
    if s.get("sourceImage"):
        index[s["id"]] = s["sourceImage"]
OUT.mkdir(parents=True, exist_ok=True)
copied = 0
for h in sorted(set(index.values())):
    src = IMAGES / f"{h}.webp"
    if src.exists():
        shutil.copy(src, OUT / f"{h}.webp")
        copied += 1
(OUT / "index.json").write_text(json.dumps(index, indent=1) + "\n", encoding="utf-8")
print(f"{len(index)} scenes, {copied} pictures")
