// Construction safety on copies of authored scenes. No server or writes required.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Layout = require("../editor/layout");

function scene(id) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, "../../../game_godot/network", id + ".json"), "utf8"));
}

const straight = scene("ticket_3_12");
const baseline = JSON.stringify(straight);
for (const [a,b] of [[[0,26],[0,40]], [[0,40],[0,26]], [[0,0],[0,40]], [[0,26],[0,90]]]) {
  assert.deepEqual(Layout.addStreet(straight, a, b), []);
  assert.equal(JSON.stringify(straight), baseline, "an occupied segment must leave the graph intact");
}

// The authored quadratic is cut in half by a side street. Both pieces trace the
// original line, retain their respective end settings and keep the player's lane.
const curved = scene("ticket_8_13");
const source = curved.layout.streets.find(st => st.bend);
const line = Layout.centreline(curved.layout, source);
const mid = line[12], oldB = source.b;
source.ends = {a:{stop:true}, b:{zebra:true}};
const player = {street:source.id, toward:oldB, lane:1, questionAt:18, stopAt:8};
curved.layout.player = {...player};
const oldStop = Layout.playerPlan(curved).stop;
const manual = curved.routes.filter(r => r.manual).map(r => [r.id, JSON.stringify(r.points)]);
const branch = Layout.addStreet(curved, mid, [mid[0]-35,mid[1]]);
assert.equal(branch.length, 1);
const other = curved.layout.streets.find(st => st.a === source.b && st.b === oldB);
assert(other);
assert.deepEqual(source.ends, {a:{stop:true}});
assert.deepEqual(other.ends, {b:{zebra:true}});
assert.deepEqual(curved.layout.player, {...player, street:other.id});
const newStop = Layout.playerPlan(curved).stop;
assert(Math.hypot(newStop[0]-oldStop[0], newStop[1]-oldStop[1]) < .05, "player must retain its position in the lane");
const rebuilt = [...Layout.centreline(curved.layout, source, 12), ...Layout.centreline(curved.layout, other, 12).slice(1)];
line.forEach(([x,z], i) => assert(Math.hypot(rebuilt[i][0]-x,rebuilt[i][1]-z)<.002, "curve geometry moved after split"));
Layout.apply(curved);
for (const [id,points] of manual) assert.equal(JSON.stringify(curved.routes.find(r => r.id === id).points), points, id);

// Crossing the same curved street twice creates two distinct four-way junctions.
const horseshoe = {crop:90, layout:{
  nodes:[{id:"a", x:-20, z:0}, {id:"b", x:20, z:0}],
  streets:[{id:"arc", a:"a", b:"b", kind:"street", bend:[0,50]}],
}};
assert.equal(Layout.addStreet(horseshoe, [-45,15], [45,15]).length, 3);
const nodes = horseshoe.layout.nodes.filter(n => Math.abs(n.z-15)<.1 && Math.abs(n.x)<20);
assert.equal(nodes.length, 2);
assert(nodes.every(n => Layout.streetsAt(horseshoe.layout,n.id).length === 4));
assert.equal(horseshoe.layout.streets.filter(st => st.bend).length, 3);

const cross = scene("ticket_3_12");
Layout.addStreet(cross, [-45,0], [45,0]);
assert.equal(Layout.streetsAt(cross.layout,"c").length,4,"a stroke through an existing node joins it");

const nearby = {crop:90,layout:{nodes:[{id:"a",x:0,z:0},{id:"b",x:3,z:0}],streets:[]}};
assert.equal(Layout.snapPoint(nearby,[2.9,0]).node,"b","nearest node wins regardless of insertion order");
console.log("Road construction: overlap rejection, curved splits, player and manual paths, intersections and nearest snapping PASS");
