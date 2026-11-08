"""Validate shifted approach geometry through the real build, using disposable fixtures."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
import check
from shapely.geometry import Polygon
from shapely.ops import unary_union

with tempfile.TemporaryDirectory(prefix="median-position-", dir=build.ROOT / "scratch") as tmp:
    path=Path(tmp)/"fixtures.json"
    subprocess.run(["node",str(Path(__file__).with_suffix(".js")),str(path)],check=True)
    for case in json.loads(path.read_text()):
        old,new=case["original"],case["shifted"]
        errors=[e for e in check.check_scene(new) if e["level"]=="error"]
        assert not errors, errors
        def islands(scene):
            out=build.build(scene)
            surface=next(s for s in out["surfaces"] if s["id"]=="median")
            pts=list(zip(surface["verts"][::2],surface["verts"][1::2]))
            return unary_union([Polygon([pts[j] for j in surface["idx"][i:i+3]]) for i in range(0,len(surface["idx"]),3)])
        before,after=islands(old),islands(new)
        assert after.difference(before).area > 5, "built island extends toward junction"
        assert before.difference(after).area < .01, "old part of island stays fixed"
print("Median position pipeline: check/build PASS")
