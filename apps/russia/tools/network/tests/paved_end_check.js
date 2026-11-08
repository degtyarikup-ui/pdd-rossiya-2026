// A dirt street's paved stretch at a junction (ends.<a|b>.paved) is an editable setting:
// the generated roads split into dirt and asphalt, 0 removes it, values are clamped.
//   node tools/network/tests/paved_end_check.js
const assert = require("node:assert/strict");
const path = require("path");
const Layout = require(path.join(__dirname, "..", "editor", "layout.js"));

const scene = { crop: 90, roads: [], markings: [], lawns: [], actors: [], lights: [], routes: [], question: {},
  layout: { nodes: [{ id: "s", x: 0, z: -90 }, { id: "c", x: 0, z: 0 }, { id: "e", x: 90, z: 0 }, { id: "w", x: -90, z: 0 }],
    streets: [{ id: "d", a: "s", b: "c", kind: "street", surface: "sand", walk: false, edge: false, ends: {} },
      { id: "x", a: "c", b: "e", kind: "street" }, { id: "y", a: "c", b: "w", kind: "street" }] } };
Layout.apply(scene);
assert.ok(!scene.roads.some(r => r.id.startsWith("road_d_paved")), "no paved stretch by default");
assert.ok(Layout.setPavedEnd(scene, "d", "b", 16));
Layout.apply(scene);
const paved = scene.roads.find(r => r.id === "road_d_paved_b"), dirt = scene.roads.find(r => r.id === "road_d");
assert.equal(paved.surface, "asphalt");
assert.equal(dirt.surface, "sand");
const zs = pts => pts.map(p => p[1]);
assert.ok(Math.min(...zs(paved.outer)) > -17.5 && Math.max(...zs(dirt.outer)) <= -15.9, "16 m of asphalt, dirt up to it");
Layout.setPavedEnd(scene, "d", "b", 99);
assert.equal(Layout.pavedEnd(Layout.streetOf(scene.layout, "d"), "b"), Layout.PAVED_MAX, "clamped");
Layout.setPavedEnd(scene, "d", "b", 0);
Layout.apply(scene);
assert.ok(!scene.roads.some(r => r.id.startsWith("road_d_paved")) && !("paved" in scene.layout.streets[0].ends.b), "0 removes it");
console.log("Paved end of a dirt street: split, clamp, removal PASS");
