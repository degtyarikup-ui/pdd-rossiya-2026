"""A real car, not only its route centre, must fit every supported lane merge."""
import json
import math
from pathlib import Path
import subprocess
import tempfile
import sys

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT / "tools/network"))
import build
with tempfile.TemporaryDirectory(prefix="custom-lanes-", dir=ROOT / "scratch") as directory:
    fixtures = Path(directory) / "fixtures.json"
    subprocess.run(["node", "tools/network/tests/custom_lanes_check.js", str(fixtures)], cwd=ROOT, check=True)
    scenes = json.loads(fixtures.read_text())
    poses = 0
    for scene in scenes:
        authored = unary_union([Polygon(road["outer"], road.get("holes", [])).buffer(0) for road in scene["roads"]])
        rendered = build.road_geometry(scene)[0]
        asphalt = authored.intersection(rendered)
        assert asphalt.is_valid and not asphalt.is_empty, scene["testCase"]
        if "testSplitBefore" in scene:
            before = scene["testSplitBefore"]
            old = unary_union([Polygon(road["outer"],road.get("holes",[])) for road in before["roads"]])
            assert authored.boundary.hausdorff_distance(old.boundary) < .01, "split keeps the sampled edge within 1 cm"
            for route in scene["routes"]:
                former = next(r for r in before["routes"] if r["id"] == route["id"])
                assert LineString(route["points"]).hausdorff_distance(LineString(former["points"])) < .002
        for route in scene["routes"]:
            line = LineString(route["points"])
            for i in range(1, math.ceil(line.length * 2)):
                distance = i / 2
                if distance < 3 or distance > line.length-3:
                    continue
                point = line.interpolate(distance)
                # The engine supplies the next scene past these cuts; its seam
                # tests cover the car that straddles two cropped source meshes.
                if max(abs(point.x), abs(point.y)) > scene["crop"] - 3:
                    continue
                before = line.interpolate(max(0, distance - .25))
                after = line.interpolate(min(line.length, distance + .25))
                yaw = math.atan2(after.x - before.x, after.y - before.y)
                c, s = math.cos(yaw), math.sin(yaw)
                body = Polygon([(point.x + u*c + v*s, point.y - u*s + v*c)
                                for u, v in [(-.95,-2.4),(.95,-2.4),(.95,2.4),(-.95,2.4)]])
                missing = body.difference(asphalt).area
                assert missing < .01, (scene["testCase"], route["id"], list(point.coords), missing)
                poses += 1
    print(f"Custom lanes full body: {len(scenes)} cases, {poses} poses, 1.9 × 4.8 m chassis stays on asphalt PASS")
