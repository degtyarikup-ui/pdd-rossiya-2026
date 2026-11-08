#!/usr/bin/env python3
"""Edge switches cover curved joins and end caps in real compiled paint.

Uses generated fixtures and copies of authored scenes; never writes source or
build files. Optional source path reproduces an unsaved-to-Git local scene.
"""
import copy
import json
import subprocess
import sys
from pathlib import Path

from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import build


def generated(nodes, streets, overlay=False):
    code = """
const L = require('./tools/network/editor/layout.js');
const [nodes,streets,overlay] = JSON.parse(process.argv[1]);
const s = {id:'edge-regression',crop:90,layout:{nodes,streets},question:{maneuver:'straight'},
  roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[]};
if (overlay) Object.assign(s.layout,{preserveSource:true,generatedPrefix:'plan_'});
L.apply(s);s.markings=[];console.log(JSON.stringify(s));
"""
    return json.loads(subprocess.check_output(["node", "-e", code, json.dumps([nodes,streets,overlay])], cwd=build.ROOT))


def street(id, a, b, **options):
    return {"id":id,"a":a,"b":b,"kind":"street","edge":False,"centre":"none","ends":{},**options}


def nodes(*points):
    return [{"id":str(i),"x":p[0],"z":p[1]} for i,p in enumerate(points)]


def edge_geometry(scene):
    road, _, whole, _ = build.ground(scene)
    return build.edge_lines(road, build.crop_box(scene)).difference(build.disabled_edge_mask(scene, whole))


def paint(out, colour="white"):
    surface = next(s for s in out["surfaces"] if s["id"] == "marking_" + colour)
    vertices, indices = surface["verts"], surface["idx"]
    return unary_union([Polygon([(vertices[2*i],vertices[2*i+1]) for i in indices[k:k+3]]) for k in range(0,len(indices),3)])


def no_edges(scene, label):
    before = copy.deepcopy(scene)
    assert edge_geometry(scene).area < 1e-8, label + ": orphaned edge geometry"
    assert paint(build.build(scene)).area < .001, label + ": white triangles remain"
    assert scene == before, label + ": builder changed source"


def main():
    cases = 0
    for kind in ("yard","street","avenue","highway"):
        fixtures = [
            (nodes((-35,0),(35,0)), [street("a","0","1",kind=kind)]),
            (nodes((-35,-20),(35,20)), [street("a","0","1",kind=kind,bend=[-20,40])]),
            (nodes((-45,0),(0,0),(15,45)), [street("a","0","1",kind=kind),street("b","1","2",kind=kind)]),
            (nodes((-45,0),(0,0),(35,20)), [street("a","0","1",kind="yard"),street("b","1","2",kind=kind)]),
            (nodes((-45,-20),(0,0),(45,-20)), [street("a","0","1",kind=kind,bend=[-40,20]),street("b","1","2",kind=kind,bend=[40,20])]),
        ]
        for i, (points, roads) in enumerate(fixtures):
            for overlay in (False,True):
                scene = generated(points, roads, overlay)
                # Old saved node fillers omit edge; the fix must work without a
                # browser re-applying Layout or a migration touching source JSON.
                for node in points:
                    filler = next((r for r in scene["roads"] if r["id"].endswith("road_"+node["id"])),None)
                    if filler: assert "edge" not in filler
                no_edges(scene,f"{kind} shape{i} overlay={overlay}")
                cases += 1

    # Reproduce the user's short side branches and wider rounded dead end.
    scene = generated(nodes((0,-90),(0,0),(0,90),(90,0),(-90,0),(0,-24.67),(18.184,-24.95),(-16.626,-24.414),(-24.236,-24.481)), [
        street("south","0","5"),street("middle","5","1"),street("north","1","2"),
        street("east","1","3"),street("west","1","4"),street("narrow","5","6",kind="yard"),
        street("side","5","7",kind="yard"),street("cap","7","8"),
    ])
    no_edges(scene,"short side branches with wider dead end")

    # One enabled arm keeps its full remote edge and its own dead-end cap. The
    # disabled arm loses both its sides and its cap, without a global all-off hack.
    for angle_end in ((0,45),(30,35),(40,0)):
        points = nodes((-45,0),(0,0),angle_end)
        roads = [street("off","0","1"),street("on","1","2",edge=True)]
        partial = generated(points,roads)
        full = generated(points,[{**r,"edge":True} for r in roads])
        seen, all_edges = edge_geometry(partial), edge_geometry(full)
        assert seen.intersection(box(-60,-15,-15,15)).area < 1e-8
        enabled_tip = Point(*angle_end).buffer(6)
        assert seen.intersection(enabled_tip).area > .5
        assert seen.intersection(enabled_tip).symmetric_difference(all_edges.intersection(enabled_tip)).area < 1e-8
        assert 0 < seen.area < all_edges.area
        # Switches change paint only, not surfaces or kerbs.
        a,b = build.build(partial),build.build(full)
        assert a["kerbs"] == b["kerbs"]
        assert [s for s in a["surfaces"] if s["id"]!="marking_white"] == [s for s in b["surfaces"] if s["id"]!="marking_white"]

    # Explicit roundabout contours remain independent of every disabled arm.
    points = nodes((0,0),(0,-90),(0,90))
    points[0]["ring"] = {"r":20,"island":9}
    ring = generated(points,[street("south","1","0"),street("north","0","2")])
    assert edge_geometry(ring).intersection(Point(0,0).buffer(11)).area > 5
    assert edge_geometry(ring).intersection(Point(0,0).buffer(21).difference(Point(0,0).buffer(18))).area > 5

    # Hand-painted markings must survive even when all edge lines are off.
    custom = generated(nodes((-30,0),(30,0)),[street("a","0","1")])
    custom["markings"] = [{"id":"own-"+colour,"type":"solid","colour":colour,"width":.2,"points":[[-10,z],[10,z]]}
                          for colour,z in (("white",-.7),("yellow",.7))]
    output = build.build(custom)
    assert abs(paint(output).area-4) < .001
    assert abs(paint(output,"yellow").area-4) < .001

    # A real committed scene with internal endpoints, and optionally the user's
    # current local file, both exercise the unchanged saved source format.
    sources = [build.NET/"ticket_8_4.json"] + [Path(p) for p in sys.argv[1:]]
    for source in sources:
        scene = json.loads(source.read_text())
        assert all(st.get("edge") is False for st in scene["layout"]["streets"])
        before = copy.deepcopy(scene)
        assert edge_geometry(scene).area < 1e-8, source.name
        build.build(scene)
        assert scene == before, source.name
    print(f"Edge lines PASS: {cases} curved/angled/width-transition/dead-end/overlay fixtures, mixed switches, ring independence, authored paint and {len(sources)} source copies")


if __name__ == "__main__":
    main()
