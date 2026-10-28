#!/usr/bin/env python3
"""Tram editor -> rail surfaces -> game source, using disposable scratch files."""
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

from shapely.geometry import Point

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build
import check
import engine_sync


def write(path, data):
    path.write_text(json.dumps(data), encoding="utf-8")


template = check.load("ticket_33_8")
sampled = build.sample_tram_route([[0, 0], [0, 8], [8, 8]])
assert len(sampled) == 41 and sampled[0] == [0, 0] and sampled[-1] == [8, 8]
assert sampled[10] == [-0.5, 4.0], "rails use the same curved movement, not the handle polyline"

with tempfile.TemporaryDirectory(prefix="tram-tracks-", dir=check.ROOT / "scratch") as tmp:
    temp = Path(tmp)
    fixture_file = temp / "editor.json"
    subprocess.run(["node", str(HERE / "tram_tracks_check.js"), str(fixture_file)], check=True)
    fixtures = json.loads(fixture_file.read_text())
    for fixture in fixtures:
        scene = {**copy.deepcopy(template), **fixture["scene"]}
        original = copy.deepcopy(scene)
        lines = build.tram_track_lines(scene)
        assert lines and sum(line.length for line in lines) > 10
        assert not build.rails(scene).is_empty
        assert scene == original, "the rail builder never rewrites authored sources"
        rail_surface = next(s for s in build.build(scene)["surfaces"] if s["id"] == "marking_rail")
        assert rail_surface["idx"], fixture["name"]
        if fixture["name"].startswith("automatic"):
            assert not build.track_lines(scene), "automatic rails cannot reshape handmade road/kerb geometry"
            without = copy.deepcopy(scene)
            without["actors"] = []
            before = [s for s in build.build(without)["surfaces"] if s["id"] != "marking_rail"]
            after = [s for s in build.build(scene)["surfaces"] if s["id"] != "marking_rail"]
            assert before == after, fixture["name"]
        else:
            assert all(line.distance(Point(40, 0)) > 9 for line in lines), "unused parallel authored rail is absent"
            assert all(line.distance(Point(0, 50)) > 20 for line in lines), "unused main continuation is absent"
        print(f"PASS {fixture['name']}: curved rails, source and road preservation")

    retired = copy.deepcopy(template)
    retired["actors"] = []
    retired["tracks"] = [{"id": "old", "points": [[0, -60], [50, -60]]}]
    retired["markings"].append({"id": "old-rail", "type": "solid", "colour": "rail", "points": [[0, -60], [50, -60]]})
    assert not build.track_lines(retired) and build.rails(retired).is_empty
    assert not any(s["id"] == "marking_rail" for s in build.build(retired)["surfaces"])
    assert not any(f["code"] == "marking-colour" for f in check.check_scene(retired)), "retired rail paint needs no source cleanup"
    visible = copy.deepcopy(retired)
    visible["tracks"][0]["render"] = True
    before_visible = copy.deepcopy(visible)
    drawn = build.authored_rails(visible)
    assert drawn.area > 8 and drawn.distance(Point(25, -60.762)) < .001
    rendered = next(s for s in build.build(visible)["surfaces"] if s["id"] == "authored_rails")
    assert rendered["idx"] and rendered["y"] == .047
    assert not any(s["id"] == "marking_rail" for s in build.build(visible)["surfaces"])
    assert visible == before_visible, "Showing standalone rails never changes the source or adds a tram"
    clean = copy.deepcopy(retired)
    clean["tracks"] = []
    clean["markings"] = [m for m in clean["markings"] if m["colour"] != "rail"]
    assert build.build(retired) == build.build(clean), "retired rails leave no bed or curb cuts"

    parked = copy.deepcopy(template)
    parked["actors"] = [{"id": "parked-tram", "type": "tram", "pos": [2, -1], "yaw": math.pi / 2,
                         "halfLength": 5, "behaviour": {"staysPut": True}}]
    line = build.tram_track_lines(parked)[0]
    assert abs(line.length - 14) < 1e-6 and line.distance(Point(2, -1)) < 1e-6
    assert not any(f["code"] == "actor-no-route" for f in check.check_scene(parked))
    parked["actors"][0]["behaviour"]["staysPut"] = False
    assert any(f["code"] == "actor-no-route" for f in check.check_scene(parked)), "missing moving routes are diagnosed"
    parked["actors"][0]["route"] = "missing"
    assert any(f["code"] == "actor-no-route" for f in check.check_scene(parked)), "a dangling route is diagnosed"
    parked["routes"].append({"id": "missing", "kind": "actor", "points": [[2, -1], [2, -1]]})
    assert any(f["code"] == "actor-no-route" for f in check.check_scene(parked)), "a zero-length route is diagnosed"

    # Save/export uses the ordinary actor path. Sampling remains derived, not a
    # second source which could lose future manual edits on reload.
    sit, net = temp / "situations", temp / "network"
    source_template, output = sit / "tram-template", sit / "fixture"
    (source_template / "parts").mkdir(parents=True)
    output.mkdir(parents=True)
    net.mkdir()
    archived = json.loads((engine_sync.SIT / "ticket_1_14/engine.json").read_text())
    write(source_template / "engine.json", archived)
    write(output / "engine.json", archived)
    (source_template / "parts/actor_0.glb").write_bytes(b"disposable tram actor fixture")
    engine_sync.engine_base.cache_clear()
    try:
        with patch.object(check, "NET", net), patch.object(engine_sync, "SIT", sit):
            for fixture in fixtures:
                scene = {**copy.deepcopy(template), **copy.deepcopy(fixture["scene"])}
                for actor in scene["actors"]:
                    actor.update({"asset": "tram-template/actor_0.glb", "scale": [1, 1, 1]})
                scene["lights"] = []
                write(net / "fixture.json", scene)
                engine_sync.sync("fixture")
                exported = json.loads((output / "scene.json").read_text())["actors"][0]
                actor = scene["actors"][0]
                route = next(r for r in scene["routes"] if r["id"] == actor["route"])
                assert exported["path"] == [[x, 0, z] for x, z in route["points"]], fixture["name"]
                assert exported["staysPut"] is actor["behaviour"]["staysPut"], fixture["name"]
                assert check.load("fixture") == scene, "export leaves author data intact"
            # The template's dimensions include its own scale (.75), so a new
            # editor tram at 1.5 must have twice that envelope, not 1.5 times.
            original_actor = archived["actors"][0]
            original_scale = original_actor["scale"]
            cases = [
                ([1.5, 1.5, 1.5], {}, "enlarged inherited body"),
                ([1.5, 0.75, 0.375], {}, "nonuniform body"),
                ([0.375, 0.375, 0.375], {}, "smaller body keeps conservative release"),
                ([1.5, 1.5, 1.5], {"halfWidth": 2.1, "halfLength": 8.0}, "explicit body with inherited release"),
                ([1.5, 1.5, 1.5], {"halfWidth": 2.1, "halfLength": 8.0, "clearDistance": 27.0}, "explicit body and release"),
            ]
            for scale, overrides, name in cases:
                scene = copy.deepcopy(template)
                actor = {"id": "scaled-tram", "type": "tram", "asset": "tram-template/actor_0.glb", "pos": [0, -20],
                         "yaw": 0.0, "scale": scale, "route": "scaled-route", "behaviour": {"staysPut": False}, **overrides}
                scene["actors"] = [actor]
                scene["lights"] = []
                scene["routes"].append({"id": "scaled-route", "kind": "actor", "points": [[0, -20], [0, 20]]})
                write(net / "fixture.json", scene)
                before = copy.deepcopy(scene)
                engine_sync.sync("fixture")
                exported = json.loads((output / "scene.json").read_text())["actors"][0]
                expected_width = overrides.get("halfWidth", original_actor["halfWidth"] * abs(scale[0] / original_scale[0]))
                expected_length = overrides.get("halfLength", original_actor["halfLength"] * abs(scale[2] / original_scale[2]))
                expected_clear = overrides.get("clearDistance", original_actor["clearDistance"] + max(0.0, expected_length - original_actor["halfLength"]))
                assert math.isclose(exported["halfWidth"], expected_width), name
                assert math.isclose(exported["halfLength"], expected_length), name
                assert math.isclose(exported["clearDistance"], expected_clear), name
                assert exported["scale"] == scale and exported["path"] == [[0, 0, -20], [0, 0, 20]], name
                assert check.load("fixture") == before, "scaled export leaves author data intact"
                print(f"PASS {name}: scaled body/rear clearance/source preservation")
    finally:
        engine_sync.engine_base.cache_clear()

print("Tram editor pipeline: automatic/manual/branch/stationary/retired/source/export PASS")
