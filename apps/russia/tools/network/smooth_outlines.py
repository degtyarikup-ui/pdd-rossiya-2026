#!/usr/bin/env python3
"""Smooths the traced outlines of every junction scene's roads, islands and lawns (game_godot/network/<id>.json).

    tools/network/.venv/bin/python tools/network/smooth_outlines.py [--dry] [scene_id ...]

A scene whose outlines are already smooth is left alone (the check is the mean turn of its outlines), so
the script can run again. Then rebuild the surfaces: build.py <id> (or save the scene in the editor).
The formatting of the files is the editor's own (indent 1, UTF-8), so only the outlines differ in git.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check  # noqa: E402
import outline  # noqa: E402

SMOOTH_BELOW = 3.0   # degrees: a mean turn below this is a smooth outline already


def mean_turn(pts: list) -> float:
    n = len(pts)
    if n < 3:
        return 0.0
    total = 0.0
    for i in range(n):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
        v1 = (b[0] - a[0], b[1] - a[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        l1, l2 = math.hypot(*v1) or 1.0, math.hypot(*v2) or 1.0
        cos = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)))
        total += math.degrees(math.acos(cos))
    return total / n


def smooth_scene(scene: dict) -> int:
    """Smooths the scene in place; returns how many outlines changed."""
    crop = float(scene.get("crop", 90.0))
    changed = 0
    items = [r for r in scene.get("roads", [])] + [l for l in scene.get("lawns", [])]
    for item in items:
        for key in ("outer", "holes"):
            rings = [item[key]] if key == "outer" else item[key]
            for k, ring in enumerate(rings):
                if mean_turn(ring) < SMOOTH_BELOW:
                    continue
                new = outline.smooth_ring(ring, crop)
                if key == "outer":
                    item["outer"] = new
                else:
                    item["holes"][k] = new
                changed += 1
    return changed


def main(argv: list) -> None:
    dry = "--dry" in argv
    ids = [a for a in argv if not a.startswith("--")] or sorted(p.stem for p in check.NET.glob("*.json"))
    total = 0
    for sid in ids:
        path = check.NET / f"{sid}.json"
        scene = json.loads(path.read_text(encoding="utf-8"))
        n = smooth_scene(scene)
        if not n:
            continue
        total += n
        print(f"{sid}: {n} outlines smoothed")
        if not dry:
            path.write_text(json.dumps(scene, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(("dry run: " if dry else "") + f"{total} outlines in {len([i for i in ids])} scenes checked")


if __name__ == "__main__":
    main(sys.argv[1:])
