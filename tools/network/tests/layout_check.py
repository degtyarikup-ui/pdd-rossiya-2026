#!/usr/bin/env python3
"""The road plans of the editor (tools/network/editor/layout.js) make scenes the game can drive:

    tools/network/.venv/bin/python tools/network/tests/layout_check.py

Every ready-made plan with every question manoeuvre is generated on top of a real scene (node), then
checked (check.py: no errors) and built (build.py). Also: the player's stop of a crossroad is the
game's usual one, exits turn the right way (+x is the driver's left), a street drawn across another
makes a junction, and a participant dropped on a lane gets a path through it.
"""
import json
import math
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build  # noqa: E402
import check  # noqa: E402

failures = []


def expect(ok, what):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


def main():
    base = check.NET / "ticket_10_13.json"
    out = json.loads(subprocess.run(["node", str(HERE / "layout_gen.js"), str(base)], check=True,
                                    capture_output=True, text=True).stdout)
    for item in out:
        if item["template"] == "actor-path":
            expect("left" in item["ways"] and "straight" in item["ways"], f"participant on a lane: ways {item['ways']}")
            p = item["path"]
            expect(p is not None and len(p) > 5, "participant path through the junction")
            if p:
                # Coming from the east (+x, driving toward -x, on the -z side) and turning left: the driver's left is +z.
                expect(p[-1][1] > 10, f"participant turning left ends on the north street (z {p[-1][1]:.1f})")
            continue
        s = item["scene"]
        name = f"{item['template']} / {item['maneuver']}"
        errors = [f for f in check.check_scene(s) if f["level"] == "error"]
        expect(not errors, f"{name}: no check errors {[e['message'] for e in errors][:3]}")
        built = build.build(s)
        expect(sum(len(x["idx"]) for x in built["surfaces"]) > 0, f"{name}: builds")
        routes = {r["id"]: r for r in s["routes"]}
        expect("approach" in routes, f"{name}: approach")
        if item["template"] == "cross" and item["maneuver"] == "straight":
            expect(abs(s["stop"]["x"] + 1.8) < 1e-6 and abs(s["stop"]["z"] + 13.1) < 1e-6 and s["stop"]["yaw"] == 0,
                   f"cross: stop at the game's usual place {s['stop']}")
            left, right = routes["manoeuvre_left"], routes["manoeuvre_right"]
            expect(left["points"][-1][0] > 15 and abs(left["exitYaw"] - math.pi / 2) < 0.01, "cross: left goes to +x, exitYaw +90")
            expect(right["points"][-1][0] < -15 and abs(right["exitYaw"] + math.pi / 2) < 0.01, "cross: right goes to -x, exitYaw -90")
            expect(abs(routes["manoeuvre_straight"]["points"][-1][0] + 1.8) < 0.01, "cross: straight keeps the lane")
            expect(s["exitWidths"] == {"straight": 8.4, "left": 8.4, "right": 8.4, "uturn": 8.4}, f"cross: exit widths {s['exitWidths']}")
        if item["template"] == "ring" and item["maneuver"] == "straight":
            pts = routes["manoeuvre_right"]["points"]
            # Round the island keeping it on the left: the first exit (right, -x) is reached quickly.
            ring_pts = [p for p in pts if math.hypot(*p) < 20]
            expect(ring_pts and min(p[0] for p in ring_pts) < -5 and max(p[0] for p in ring_pts) < 8,
                   "ring: the right exit is the short way round")
        if item["template"] == "drawn-cross":
            expect(item["nodes"] == 5 and item["streets"] == 4, f"drawn cross: 5 nodes, 4 streets ({item['nodes']}, {item['streets']})")
        if item["template"].startswith("bend"):
            key = "left" if item["template"] == "bend-left" else "right"
            expect(f"manoeuvre_{key}" in routes, f"{item['template']}: one way, {key}")
    print(f"{len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
