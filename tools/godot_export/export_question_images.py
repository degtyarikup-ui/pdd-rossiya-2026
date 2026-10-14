#!/usr/bin/env python3
"""Build the game's picture index from the canonical Flutter assets.
Embedded games read Flutter pictures directly; no WebP copies are kept here.
--standalone creates temporary links for exporting a game without Flutter.
    python3 tools/godot_export/export_question_images.py
"""
import argparse
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game_godot" / "questions"
IMAGES = ROOT / "assets" / "countries" / "ru" / "images" / "questions_ab"
tickets = json.loads((ROOT / "assets/countries/ru/questions/questions_ab.json").read_text(encoding="utf-8"))["tickets"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--standalone", action="store_true", help="link pictures for an export without Flutter")
args = parser.parse_args()
index = {}
for p in sorted((ROOT / "game_godot" / "network").glob("ticket_*.json")):
    m = re.match(r"ticket_(\d+)_(\d+)$", p.stem)
    q = tickets[int(m[1]) - 1]["questions"][int(m[2]) - 1]
    if q.get("image"):
        index[p.stem] = q["image"]
for s in json.loads((ROOT / "game_godot/roads/road_scenes.json").read_text(encoding="utf-8"))["scenes"]:
    if s.get("sourceImage"):
        index[s["id"]] = s["sourceImage"]
sources = [IMAGES / f"{h}.webp" for h in sorted(set(index.values()))]
for src in sources:
    if not src.is_file():
        raise FileNotFoundError(f"Missing canonical question image: {src}")
OUT.mkdir(parents=True, exist_ok=True)
# Clear obsolete copies and links, including their old import metadata.
for pattern in ("*.webp", "*.webp.import"):
    for old in OUT.glob(pattern):
        old.unlink()
for src in sources:
    if args.standalone:
        dst = OUT / src.name
        dst.symlink_to(os.path.relpath(src, OUT))
        # Keep the original WebP, which PackFiles decodes from bytes at runtime.
        (OUT / f"{src.name}.import").write_text('[remap]\n\nimporter="keep"\n')
(OUT / "index.json").write_text(json.dumps(index, indent=1) + "\n", encoding="utf-8")
print(f"{len(index)} scenes, {len(set(index.values()))} shared pictures" +
      (" (temporary standalone links)" if args.standalone else " (no copies)"))
