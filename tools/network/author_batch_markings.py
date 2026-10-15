#!/usr/bin/env python3
"""Author six pending, editable A/B drafts through the normal scene pipeline.

Run with tools/network/.venv/bin/python tools/network/author_batch_markings.py.
Existing scenes are protected; --overwrite only accepts this batch's own pending
drafts. After a human edits a draft, use the editor's Save, not this authoring tool.
No decision, reviewed scene, or situations/index.json is changed.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
import subprocess
from unittest.mock import patch

import build
import check
import engine_sync
import question_pool

ROOT = Path(__file__).resolve().parents[2]
IDS = ("ticket_25_7", "ticket_32_4", "ticket_25_5", "ticket_23_5", "ticket_38_5", "ticket_24_6")
BATCH = "2026-10-16-first-12"
PROVENANCE = {"author": "codex", "batch": BATCH, "status": "pending"}
GOST = "https://www.mos.ru/upload/documents/files/1106/GOSTR51256-2018TehnicheskiesredstvaorganizaciidorojnogodvijeniyaR_.pdf"
FOLIAGE_TINTS = {"trees/pine_0": "#3e7c42", "trees/round_0": "#5f8f3e",
                 "trees/birch_0": "#7fa34a", "street/bush": "#467e3c"}


class AuthorSources(question_pool.QuestionPool):
    """Read the official source even when an existing pending draft is hidden in the pool."""
    def get(self, sid: str):
        return self.source(sid) if sid in IDS else None


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def layout_scene(scene: dict, template: str, **settings) -> dict:
    script = """
const fs = require('fs');
const Layout = require(process.argv[1]);
const input = JSON.parse(fs.readFileSync(0,'utf8'));
const scene = input.scene;
scene.layout = Layout.template(input.template, scene.crop);
for (const street of scene.layout.streets) {
  Object.assign(street, {centre:'none', edge:false, ends:{}, ...input.settings});
}
scene.layout.player.lane = 0;
scene.roads=[]; scene.markings=[]; scene.lawns=[]; scene.routes=[];
Layout.apply(scene);
process.stdout.write(JSON.stringify(scene));
"""
    result = subprocess.run(["node", "-e", script, str(Path(__file__).parent / "editor/layout.js")],
                            input=json.dumps({"scene": scene, "template": template, "settings": settings}),
                            capture_output=True, text=True, check=True, timeout=30)
    return json.loads(result.stdout)


def segment(scene: dict, name: str, a, b, colour="white", width=0.15) -> None:
    scene["markings"].append({"id": name, "type": "solid", "colour": colour,
                              "width": width, "points": [list(a), list(b)]})


def broken_line(scene: dict, name: str, start, end, dash: float, gap: float, colour="white") -> None:
    """Individual ordinary editable solid pieces, with the stated exact geometry."""
    length = math.dist(start, end)
    ux, uz = ((end[0] - start[0]) / length, (end[1] - start[1]) / length)
    distance, number = 0.0, 0
    while distance + dash <= length + 1e-8:
        a = [round(start[0] + ux * distance, 3), round(start[1] + uz * distance, 3)]
        b = [round(start[0] + ux * (distance + dash), 3), round(start[1] + uz * (distance + dash), 3)]
        segment(scene, f"{name}_{number:02d}", a, b, colour)
        distance += dash + gap
        number += 1


def sign(scene: dict, name: str, code: str, pos, yaw=math.pi) -> None:
    scene["signs"].append({"id": name, "code": code, "pos": list(pos), "yaw": round(yaw, 6)})


def prop(scene: dict, name: str, asset: str, x: float, z: float, yaw=0.0, scale=1.0, tint=None) -> None:
    item = {"id": name, "prop": asset, "pos": [x, z], "yaw": yaw, "scale": [scale] * 3}
    if tint is None:
        tint = FOLIAGE_TINTS.get(asset)
    if tint is not None:
        item["tint"] = tint
    scene["decor"].append(item)


def city(scene: dict, cross: bool) -> None:
    # Freestanding library props outside roads/sidewalks; every item stays editable.
    for side in (-1, 1):
        for number, z in enumerate((-65, -39, 31, 59)):
            x = side * (23 if cross else 18)
            prop(scene, f"house_{side}_{number}", f"buildings/block_{number % 4}", x, z,
                 yaw=math.pi / 2 * side, tint=("#ddd1bc", "#ccd6d9", "#e0d9ce", "#d5dfd0")[number])
            prop(scene, f"tree_{side}_{number}", "trees/round_0", side * (13 if cross else 9.6), z + 9,
                 scale=1.15)
        for number, z in enumerate((-61, -27, 28, 62)):
            # Crossroads keep the immediate corners clear, including the sign.
            prop(scene, f"lamp_{side}_{number}", "street/lamp", side * 7.5, z, yaw=side * math.pi / 2)
        for number, z in enumerate((-49, 43)):
            prop(scene, f"bush_{side}_{number}", "street/bush", side * 10.0, z, scale=1.5)


def forest(scene: dict) -> None:
    for side in (-1, 1):
        for number, z in enumerate(range(-78, 79, 13)):
            prop(scene, f"pine_{side}_{number}", "trees/pine_0", side * (12 + number % 3), z,
                 scale=1.2 + (number % 3) * 0.12)
            prop(scene, f"birch_{side}_{number}", "trees/birch_0", side * (20 + number % 4), z + 5,
                 scale=1.1)


def choice(scene: dict, label: str, points, label_position, name=None) -> None:
    scene["routes"].append({"id": name or f"choice_{label}", "kind": "choice", "label": label,
                            "points": points, "labelPosition": label_position, "arrowhead": True})


def bounded_manual_route(scene: dict, direction: str, spacing=2.0) -> None:
    """Keep the same curve; add modest straight supports for finite look-ahead.

    The ordinary debug driver picks whole supports. A single 20-metre tail
    would make its target jump across the corner instead of looking along it.
    These ordinary manual control points also remain editable in the inspector.
    """
    route = next(r for r in scene["routes"] if r.get("exit") == direction)
    points = [route["points"][0]]
    for a, b in zip(route["points"], route["points"][1:]):
        count = max(1, math.ceil(math.dist(a, b) / spacing))
        for number in range(1, count + 1):
            t = number / count
            points.append([round(a[0] + (b[0] - a[0]) * t, 3), round(a[1] + (b[1] - a[1]) * t, 3)])
    route.update({"points": points, "manual": True, "auto": False})
    scene["layout"].setdefault("paths", {})[direction] = copy.deepcopy(points)


def make_scenes(pool=None) -> list[dict]:
    pool = pool or AuthorSources()
    scenes = []
    for sid in IDS:
        scene = pool.template(sid)
        scene["assistantReview"] = copy.deepcopy(PROVENANCE)
        scene["question"]["requiredStop"] = None
        scene["question"]["redWait"] = None
        scene["question"]["speedLimit"] = None
        if sid == "ticket_25_7":
            scene["question"]["maneuver"] = "right"
            scene = layout_scene(scene, "cross")
            bounded_manual_route(scene, "right")
            sign(scene, "mandatory_right", "4.1.2", (-5.3, -10.5))
            # This road's centre marking is 1.5, not the editor's generic dash.
            for name, a, b in (("centre_s", (0, -87), (0, -11)), ("centre_n", (0, 11), (0, 87)),
                               ("centre_e", (11, 0), (87, 0)), ("centre_w", (-87, 0), (-11, 0))):
                broken_line(scene, name, a, b, 1.0, 3.0)
            city(scene, True)
            scene["questionView"] = {"centre": [-3.0, 1.5], "height": 39.0}
        elif sid == "ticket_32_4":
            scene = layout_scene(scene, "cross")
            sign(scene, "one_way_left_exit", "5.7.2", (-5.4, -10.4))
            # +X is the driver's LEFT. The crossing road's two lanes both go +X.
            sign(scene, "one_way_direction", "5.5", (-31.0, -5.3), -math.pi / 2)
            for name, a, b in (("centre_s", (0, -87), (0, -11)), ("centre_n", (0, 11), (0, 87)),
                               ("one_way_e", (11, 0), (87, 0)), ("one_way_w", (-87, 0), (-11, 0))):
                broken_line(scene, name, a, b, 1.0, 3.0)
            routes = {route.get("exit"): route for route in scene["routes"] if route["kind"] == "manoeuvre"}
            for letter, direction, pos in (("А", "straight", [-3.8, 17]), ("Б", "left", [9, 3.2]),
                                            ("В", "uturn", [4.5, -17])):
                choice(scene, letter, copy.deepcopy(routes[direction]["points"]), pos)
            city(scene, True)
            scene["questionView"] = {"centre": [0.0, 0.0], "height": 45.0}
        elif sid == "ticket_25_5":
            scene = layout_scene(scene, "straight", walk=False)
            # ГОСТ Р 51256-2018, appendix A: 1.5 dash:gap = 1:3 (3 m / 9 m).
            broken_line(scene, "centre_1_5", (0, -87), (0, 87), 3.0, 9.0)
            forest(scene)
            scene["questionView"] = {"centre": [0.0, 7.0], "height": 45.0}
        elif sid in ("ticket_23_5", "ticket_38_5"):
            scene = layout_scene(scene, "straight")
            # ГОСТ Р 51256-2018, appendix A, 1.10: width 0.15 m, 1 m dash / 1 m gap.
            # Separate editable solid pieces preserve the exact rhythm in both renderers.
            broken_line(scene, "yellow_1_10", (-4.0, -39.0), (-4.0, 41.0), 1.0, 1.0, "yellow")
            # The source photo has an UNLETTERED arrow indicating the intended place.
            # It is evidence, not the player's actual post-answer route. A correct
            # answer never makes the 23/5 player park inside the forbidden zone.
            choice(scene, "", [[-1.8, -11.0], [-2.5, -7.5], [-3.05, -4.5], [-3.05, -0.5]],
                   [-3.05, -0.5], "choice_intended_place")
            city(scene, False)
            scene["questionView"] = {"centre": [-1.0, 1.5], "height": 34.0}
        elif sid == "ticket_24_6":
            scene = layout_scene(scene, "cross")
            # This original question has no picture. Flashing yellow stays in
            # effect after the answer; it confers no right of way by itself.
            scene["lights"] = [
                {"id": "signal_s", "pos": [-5.4, -9.0], "yaw": math.pi, "scale": 1,
                 "arrow": None, "state": "flashing_yellow"},
                {"id": "signal_n", "pos": [5.4, 9.0], "yaw": 0.0, "scale": 1,
                 "arrow": None, "state": "flashing_yellow"},
                {"id": "signal_e", "pos": [9.0, -5.4], "yaw": math.pi / 2, "scale": 1,
                 "arrow": None, "state": "flashing_yellow"},
                {"id": "signal_w", "pos": [-9.0, 5.4], "yaw": -math.pi / 2, "scale": 1,
                 "arrow": None, "state": "flashing_yellow"},
            ]
            for light in scene["lights"]:
                light["scale"] = 1.3
            city(scene, True)
            # A closer, shallower front view makes the yellow aperture readable
            # on a phone while retaining the player and the junction context.
            scene["questionView"] = {"centre": [-1.0, -5.0], "height": 25.0, "pitch": math.radians(25)}
        else:
            raise AssertionError(sid)
        assert scene["reviewed"] is False and scene["questionPool"]["category"] == "ab"
        errors = [item for item in check.check_scene(scene) if item["level"] == "error"]
        if errors:
            raise ValueError(f"{sid}: {errors}")
        scenes.append(scene)
    return scenes


def write_batch(network=None, situations=None, overwrite=False) -> list[dict]:
    network = Path(network or check.NET)
    situations = Path(situations or engine_sync.SIT)
    scenes = make_scenes()
    # Validate the complete destination before writing even the first draft.
    for scene in scenes:
        target = network / f"{scene['id']}.json"
        if target.exists():
            saved = json.loads(target.read_text())
            if not overwrite or saved.get("assistantReview") != PROVENANCE or saved.get("reviewed") is not False:
                raise FileExistsError(f"Preserving existing scene: {target}")
        directory = situations / scene["id"]
        if directory.exists() and not target.exists():
            raise FileExistsError(f"Preserving unrelated situation directory: {directory}")
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(check, "NET", network), patch.object(engine_sync, "NET", network), patch.object(engine_sync, "SIT", situations):
            for scene in scenes:
                sid = scene["id"]
                write_json(network / f"{sid}.json", scene)
                write_json(network / "build" / f"{sid}.json", build.build(scene))
                base = question_pool.engine_template(scene)
                base.update({"questionPool": scene["questionPool"], "assistantReview": copy.deepcopy(PROVENANCE)})
                write_json(situations / sid / "engine.json", base)
                engine_sync.sync(sid)
    finally:
        engine_sync.engine_base.cache_clear()
    return scenes


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="Replace only this batch's own pending drafts")
    args = parser.parse_args()
    for item in write_batch(overwrite=args.overwrite):
        print(item["id"] + ": pending editable draft saved")
