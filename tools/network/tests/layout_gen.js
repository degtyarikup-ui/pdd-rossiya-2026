// Generates a scene from every ready-made road plan (editor/layout.js) on top of a real scene,
// for layout_check.py: node tools/network/tests/layout_gen.js <scene.json>  ->  JSON list on stdout.
const fs = require("fs");
const path = require("path");
const Layout = require(path.join(__dirname, "..", "editor", "layout.js"));

const base = JSON.parse(fs.readFileSync(process.argv[2], "utf-8"));
const out = [];
for (const t of Layout.TEMPLATES) {
  for (const maneuver of ["straight", "left", "right", "uturn"]) {
    const s = JSON.parse(JSON.stringify(base));
    s.layout = Layout.template(t.id, s.crop || 90);
    s.question.maneuver = maneuver;
    s.actors = [];
    s.lights = [];
    s.routes = s.routes.filter((r) => r.kind === "choice");
    s.markings = [];
    s.lawns = [];
    Layout.apply(s);
    out.push({ template: t.id, maneuver, scene: s });
  }
}
// Drawing: a cross laid with the street tool, two strokes crossing in the middle.
const s = JSON.parse(JSON.stringify(base));
s.layout = { nodes: [], streets: [] };
Layout.addStreet(s, [0, -90], [0, 90]);
Layout.addStreet(s, [-90, 0], [90, 0]);
s.actors = []; s.lights = []; s.markings = []; s.lawns = [];
s.routes = s.routes.filter((r) => r.kind === "choice");
Layout.apply(s);
out.push({ template: "drawn-cross", maneuver: s.question.maneuver, scene: s, nodes: s.layout.nodes.length, streets: s.layout.streets.length });
// A participant dropped on the east street, sent left.
const car = { id: "car_1", type: "car", pos: [20, -1.5], yaw: -Math.PI / 2, way: "left", scale: [1, 1, 1] };
const ways = Layout.waysFrom(s, car.pos, car.yaw);
const p = Layout.pathFrom(s, car.pos, car.yaw, "left");
out.push({ template: "actor-path", ways, path: p });
// Multi-lane player lane selection test.
const sav = JSON.parse(JSON.stringify(base));
sav.layout = Layout.template("avenue", sav.crop || 90);
sav.layout.player = { street: "s3", toward: "c", lane: 1 };
sav.question.maneuver = "straight";
sav.actors = []; sav.lights = []; sav.markings = []; sav.lawns = [];
sav.routes = sav.routes.filter((r) => r.kind === "choice");
Layout.apply(sav);
out.push({ template: "avenue-lane-1", maneuver: "straight", scene: sav });
process.stdout.write(JSON.stringify(out));
