#!/usr/bin/env python3
"""Author six editable draft road questions; never promote or rewrite other scenes.

    tools/network/.venv/bin/python tools/network/author_batch_roads.py

Existing files are skipped. ``--overwrite`` rebuilds only this pending Codex batch;
it refuses reviewed scenes and any scene with a different provenance. After a
manual edit, keep the normal editor source as the authoritative version.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess
import sys

import build
import check
import engine_sync
from question_pool import QuestionPool, engine_template


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
IDS = ("ticket_2_1", "ticket_19_1", "ticket_5_1", "ticket_3_1", "ticket_4_7", "ticket_6_7")
BATCH = "2026-10-16-first-12"
PROVENANCE = {"author": "codex", "batch": BATCH, "status": "pending"}


class AuthorSources(QuestionPool):
    """Resolve the six official sources even after the review queue owns them."""
    def get(self, sid: str) -> dict | None:
        return self.source(sid) if sid in IDS else super().get(sid)


def prop(name: str, x: float, z: float, yaw: float = 0, tint: str | None = None) -> dict:
    return {"prop": name, "pos": [x, z], "yaw": yaw, "scale": [1, 1, 1], "tint": tint}


def urban_street() -> list[dict]:
    """Ordinary editable scenery, outside sidewalks and the complete car route."""
    result = []
    for side in (-1, 1):
        for index, z in enumerate((-60, -28, 25, 57)):
            result.append(prop(f"buildings/block_{index % 4}", side * 22, z,
                               0 if side == -1 else math.pi,
                               ("#e9d5cc", "#e8cfa8", "#c8d9c0", "#d5dce5")[index]))
            result.append(prop("trees/round_0", side * 13.5, z + 8, tint="#65894d"))
            result.append(prop("street/lamp", side * 10.5, z + 2))
    return result


def divided_street() -> list[dict]:
    result = []
    for side in (-1, 1):
        for index, z in enumerate((-57, -28, 5, 38, 67)):
            result.append(prop("trees/birch_0", side * (16 + index % 2 * 2), z, tint="#6f914f"))
            result.append(prop("street/lamp", side * 11, z + 5))
        for index, z in enumerate((15, 52)):
            result.append(prop(f"buildings/block_{index + 1}", side * 34, z,
                               0 if side == -1 else math.pi, "#d5dce5"))
    return result


def rural_junction() -> list[dict]:
    result = []
    for side in (-1, 1):
        for index, z in enumerate((-62, -40, -15, 22, 45, 68)):
            result.append(prop("trees/round_0", side * (17 + index % 3 * 4), z,
                               tint=("#65894d", "#76914e", "#507c48")[index % 3]))
        for x in (42, 63):
            result.append(prop("trees/birch_0", side * x, 17, tint="#789652"))
    return result


def priority_junction(left: bool) -> list[dict]:
    result = []
    # The forward-left diagonal of 4/7 remains free of buildings and trees.
    for side in (-1, 1):
        for index, z in enumerate((-54, -28, 35, 65)):
            if not left and side == 1 and z > 0:
                continue
            result.append(prop(f"buildings/home_{index % 4}", side * 28, z,
                               0 if side == -1 else math.pi,
                               ("#e8cfa8", "#e9d5cc", "#c8d9c0", "#d5dce5")[index]))
            result.append(prop("trees/birch_0", side * 14, z - 4, tint="#6f914f"))
        for x in (46, 70):
            result.append(prop("trees/round_0", side * x, -17, tint="#64874c"))
            result.append(prop("trees/round_0", side * x, 19, tint="#76914e"))
    return result


def layout_scene(scene: dict, kind: str, spec: dict) -> dict:
    script = r"""
const fs = require('fs');
const Layout = require(process.argv[1]);
const data = JSON.parse(fs.readFileSync(0, 'utf8'));
const scene = data.scene, spec = data.spec;
scene.roads = []; scene.markings = []; scene.lawns = []; scene.routes = [];
scene.layout = Layout.template(data.kind, scene.crop);
for (const street of scene.layout.streets) Object.assign(street, {
  kind: spec.profile || 'street', centre: spec.centre || 'none',
  walk: spec.walk !== false, edge: spec.edge === true, ends: {}
});
if (spec.median) for (const street of scene.layout.streets) street.median = spec.median;
Object.assign(scene.layout.player, {lane: spec.lane || 0});
if (spec.questionAt) scene.layout.player.questionAt = spec.questionAt;
if (spec.sand) scene.layout.streets.find(s => s.id === 's1').surface = 'sand';
if (spec.diagonalNorth) scene.layout.streets.find(s => s.id === 's2').bend = [30, 35];
Layout.apply(scene);
process.stdout.write(JSON.stringify(scene));
"""
    result = subprocess.run(["node", "-e", script, str(HERE / "editor" / "layout.js")],
                            input=json.dumps({"scene": scene, "kind": kind, "spec": spec}),
                            text=True, capture_output=True, check=True, timeout=30)
    return json.loads(result.stdout)


def make_scene(sid: str, pool: QuestionPool | None = None) -> dict:
    """Build normal editor data in memory, with official ru/en/kk question text."""
    if sid not in IDS:
        raise ValueError(f"Scene is outside this batch: {sid}")
    scene = (pool or AuthorSources()).template(sid)
    scene["assistantReview"] = dict(PROVENANCE)
    # Source/photo verification is separate from the owner's pending approval.
    scene["compliance"] = {"status": "ok"}
    if sid in ("ticket_2_1", "ticket_19_1"):
        scene = layout_scene(scene, "straight", {"profile": "avenue", "median": 3,
                                                   "walk": False, "edge": True, "lane": 1})
        # Avenue's stock layout narrows its outside contour at the city join,
        # although its right-hand lane remains 6.75 m from the axis. Keep that
        # lane physically supported with an ordinary editable road polygon.
        # The generated grass median remains a real hole in the final road.
        scene["roads"].append({"id": "full_width_carriageway", "outer": [[-8.5, -91], [8.5, -91],
                                [8.5, 91], [-8.5, 91]], "holes": [], "surface": "asphalt",
                                "walk": False, "edge": True})
        scene["type"] = "road_divided"
        scene["decor"] = divided_street()
        scene["questionView"] = {"centre": [0, -3], "height": 45}
    elif sid == "ticket_5_1":
        scene = layout_scene(scene, "straight", {"profile": "avenue", "centre": "double", "lane": 1})
        scene["type"] = "road_undivided"
        scene["decor"] = urban_street()
        scene["questionView"] = {"centre": [0, -3], "height": 42}
    elif sid == "ticket_3_1":
        scene["question"].update({"maneuver": "right", "showPlayerGuide": True})
        scene = layout_scene(scene, "tee", {"walk": False, "centre": "none", "sand": True,
                                              "questionAt": 24})
        scene["type"] = "crossroad_dirt_approach"
        # A short hard-surfaced apron immediately before the junction does not
        # make the dirt approach equal in priority to the paved through road.
        # It is a normal manual road and survives Layout.apply/editor changes.
        scene["roads"].append({"id": "asphalt_apron", "outer": [[-4.2, -16], [4.2, -16],
                                [4.2, 0], [-4.2, 0]], "holes": [], "surface": "asphalt",
                                "walk": False, "edge": False})
        # Only the paved through road has the broken centre line from the photo.
        for x0, x1 in ((-90, -7), (7, 90)):
            scene["markings"].append({"id": f"main_centre_{x0}", "type": "dashed",
                                      "colour": "white", "points": [[x0, 0], [x1, 0]]})
        scene["decor"] = rural_junction()
        scene["questionView"] = {"centre": [0, -7], "height": 40}
    else:
        left = sid == "ticket_6_7"
        scene["question"].update({"maneuver": "left" if left else "right", "showPlayerGuide": True})
        scene = layout_scene(scene, "cross", {"centre": "none", "diagonalNorth": not left})
        scene["type"] = "crossroad_priority_turn"
        scene["signs"] = [{"id": "main_road", "code": "2.1", "pos": [-5.7, -11.8],
                            "yaw": -3.142, "mainRoad": ["south", "west" if left else "east"],
                            "roads": ["north", "south", "east", "west"] if left else
                                     ["nw", "south", "east", "west"]}]
        scene["decor"] = priority_junction(left)
        scene["questionView"] = {"centre": [0, -3], "height": 37}
    for index, item in enumerate(scene["decor"]):
        item["id"] = f"decor_{index}"
    russian = scene["question"]["text"]["ru"]
    scene["question"]["sourceTextLength"] = len(russian["title"]) + sum(map(len, russian["options"]))
    return scene


def write_scene(scene: dict) -> None:
    sid = scene["id"]
    findings = check.check_scene(scene)
    errors = [item for item in findings if item["level"] == "error"]
    if errors:
        raise ValueError(f"{sid}: {errors}")
    directory = engine_sync.SIT / sid
    directory.mkdir(parents=True, exist_ok=True)
    engine_sync.write_json(check.NET / f"{sid}.json", scene)
    engine = engine_template(scene)
    engine.update({"assistantReview": dict(PROVENANCE)})
    engine_sync.write_json(directory / "engine.json", engine)
    engine_sync.engine_base.cache_clear()
    build.BUILD.mkdir(parents=True, exist_ok=True)
    (build.BUILD / f"{sid}.json").write_text(json.dumps(build.build(scene), separators=(",", ":")), encoding="utf-8")
    engine_sync.sync(sid)
    print(f"{sid}: saved editable draft ({len(scene['decor'])} scenery objects; {len(findings)} findings)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="explicitly rebuild only this pending batch")
    args = parser.parse_args()
    pool = AuthorSources()
    # Complete all ownership checks before changing any file.
    pending = []
    for sid in IDS:
        path = check.NET / f"{sid}.json"
        if path.exists():
            if not args.overwrite:
                print(f"{sid}: already exists, preserving editor source")
                continue
            old = json.loads(path.read_text(encoding="utf-8"))
            if old.get("reviewed") is True or old.get("assistantReview") != PROVENANCE:
                parser.error(f"refusing to overwrite manually reviewed or foreign scene: {sid}")
        elif (engine_sync.SIT / sid).exists():
            parser.error(f"refusing to replace an existing scene directory without matching source: {sid}")
        pending.append(sid)
    for sid in pending:
        write_scene(make_scene(sid, pool))
    return 0


if __name__ == "__main__":
    sys.exit(main())
