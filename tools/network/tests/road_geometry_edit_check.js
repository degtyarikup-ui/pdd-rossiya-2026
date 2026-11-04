// Road editing uses copies only; no scene files or generated assets are written.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Layout = require("../editor/layout");
const clone = value => JSON.parse(JSON.stringify(value));
const near = (a, b, message) => assert(Math.hypot(a[0] - b[0], a[1] - b[1]) < .002, message);
const at = (scene, id) => { const n = Layout.nodeOf(scene.layout, id); return [n.x, n.z]; };
const fixture = () => ({crop:90, layout:{
  nodes:[{id:"a",x:0,z:-40},{id:"b",x:0,z:40},{id:"c",x:45,z:40}],
  streets:[{id:"road",a:"a",b:"b",kind:"avenue",median:3,ends:{b:{stop:true,zebra:true}}},
    {id:"next",a:"b",b:"c",kind:"street",bend:[15,48]}],
  player:{street:"road",toward:"b",lane:1},
}, roads:[],markings:[],lawns:[],routes:[],actors:[],stop:{x:-4,z:20,yaw:0},question:{maneuver:"straight"}});

// Moving near the original centreline must turn the road, not re-snap it to
// its own previous position. This was especially visible on small drags.
const endpoint = fixture();
let target = Layout.moveNode(endpoint,"a",[2,-30]);
near(at(endpoint,"a"),[2,-30],"endpoint stuck to its own old centreline");
assert(!target.street);
const beforeCollapse = JSON.stringify(endpoint);
assert(Layout.moveNode(endpoint,"a",at(endpoint,"b")).blocked);
assert.equal(JSON.stringify(endpoint),beforeCollapse,"a collapsed road must be rejected atomically");

// Exact placement bypasses node, street and border magnetism.
const free = fixture();
Layout.moveNode(free,"a",[1,-89],{snap:false});
near(at(free,"a"),[1,-89]);
Layout.moveNode(free,"a",[10,-80],{snap:false});
Layout.moveNode(free,"a",[1,-89]);
near(at(free,"a"),[0,-90]);
Layout.moveNode(free,"a",[2,-89]);
near(at(free,"a"),[2,-90],"a node already at a port must be free to change direction");
free.layout.nodes.push({id:"join",x:20,z:-25});
target = Layout.moveNode(free,"a",[21,-24]);
assert.equal(target.node,"join");
near(at(free,"a"),[20,-25]);

// A visible street snap produces a real T-junction when released, rather than
// leaving disconnected roads drawn on top of each other. Curve shape survives.
const joined = fixture();
joined.layout.streets[0].bend = [20,0];
joined.layout.nodes.push({id:"tip",x:40,z:0},{id:"outer",x:70,z:0});
joined.layout.streets.push({id:"branch",a:"outer",b:"tip",kind:"yard",ends:{a:{zebra:true}}});
const curveBefore = Layout.centreline(joined.layout,joined.layout.streets[0]);
target = Layout.moveNode(joined,"tip",curveBefore[12]);
assert.equal(target.street,"road");
const junction = Layout.connectNode(joined,"tip",target);
assert(junction);
assert(!Layout.nodeOf(joined.layout,"tip"));
assert.equal(Layout.streetsAt(joined.layout,junction).length,3);
const first = Layout.streetOf(joined.layout,"road");
const second = joined.layout.streets.find(st => st.a === junction && st.b === "b");
const curveAfter = [...Layout.centreline(joined.layout,first,12),...Layout.centreline(joined.layout,second,12).slice(1)];
curveBefore.forEach((p,i) => near(curveAfter[i],p,"connecting an endpoint altered the receiving curve"));
assert.deepEqual(second.ends,{b:{stop:true,zebra:true}});
assert.equal(joined.layout.player.street,second.id);
const joinedJson = JSON.stringify(joined);
assert.equal(Layout.connectNode(joined,"a",{node:"b"}),null);
assert.equal(JSON.stringify(joined),joinedJson,"stale snap mutated the graph");

// Translate each shared node and bend once. Only half of an adjacent curve's
// endpoints moves, so only half of the translation reaches its control point.
const translated = fixture();
translated.layout.streets[0].bend = [18,0];
const metadata = clone(translated.layout.streets.map(({bend,...rest}) => rest));
assert.deepEqual(Layout.moveNodes(translated,["a","b","a"],[10,5]),[10,5]);
near(at(translated,"a"),[10,-35]); near(at(translated,"b"),[10,45]);
near(translated.layout.streets[0].bend,[28,5]);
near(translated.layout.streets[1].bend,[20,50.5]);
assert.deepEqual(translated.layout.streets.map(({bend,...rest}) => rest),metadata);
assert.deepEqual(Layout.moveNodes(translated,["a","b"],[100,0]),[80,0]);
near(at(translated,"a"),[90,-35]); near(at(translated,"b"),[90,45]);

// Rotate and lengthen a bent street around A. Every centreline sample follows
// the same similarity transform, preserving the authored shape and end roles.
const shaped = fixture();
const street = shaped.layout.streets[0];
street.bend = [20,0];
const oldLine = Layout.centreline(shaped.layout,street);
const oldPlayer = clone(shaped.layout.player), oldEnds = clone(street.ends);
assert(Layout.setStreetGeometry(shaped,"road",{heading:Math.PI/2,length:60,anchor:"a"}));
near(at(shaped,"a"),[0,-40]); near(at(shaped,"b"),[60,-40]);
near(street.bend,[30,-55]);
const nextLine = Layout.centreline(shaped.layout,street);
oldLine.forEach(([x,z],i) => near(nextLine[i],[(z+40)*.75,-40-x*.75],"bend changed shape after rotation"));
assert(Math.abs(Layout.polyLen(nextLine)/Layout.polyLen(oldLine)-.75)<.00001);
assert.deepEqual(street.ends,oldEnds); assert.deepEqual(shaped.layout.player,oldPlayer);
near(shaped.layout.streets[1].bend,[45,8],"neighbour bend did not follow shared endpoint");
const shapeSnapshot = JSON.stringify(shaped);
assert.equal(Layout.setStreetGeometry(shaped,"road",{length:200,anchor:"a"}),false);
assert.equal(Layout.setStreetGeometry(shaped,"road",{length:NaN}),false);
assert.equal(JSON.stringify(shaped),shapeSnapshot,"rejected numeric edit changed the scene");

// No-op placement must not round old author coordinates or otherwise migrate
// data. A successful edit still preserves unrelated source objects verbatim.
const precise = fixture();
precise.layout.nodes[0].x = 0.123456789;
const preciseJson = JSON.stringify(precise);
Layout.moveNodes(precise,["a","b"],[0,0]);
Layout.moveNode(precise,"a",at(precise,"a"),{snap:false});
assert.equal(JSON.stringify(precise),preciseJson);

const sourceDirectory = path.join(__dirname,"../../../game_godot/network");
let authored = 0;
for (const file of fs.readdirSync(sourceDirectory).filter(name => name.endsWith(".json"))) {
  const source = JSON.parse(fs.readFileSync(path.join(sourceDirectory,file),"utf8"));
  if (!source.layout?.streets?.length) continue;
  const copy = clone(source), before = JSON.stringify(copy);
  for (const st of copy.layout.streets) {
    // Reading geometry and making a no-op edit must not migrate older scenes.
    Layout.centreline(copy.layout,st);
    assert.equal(Layout.setStreetGeometry(copy,st.id,{}),false);
    Layout.moveNodes(copy,[st.a,st.b],[0,0]);
  }
  for (const n of copy.layout.nodes) Layout.moveNode(copy,n.id,[n.x,n.z],{snap:false});
  assert.equal(JSON.stringify(copy),before,file);
  const first = copy.layout.streets[0];
  const unrelated = JSON.stringify({actors:copy.actors,lights:copy.lights,signs:copy.signs,routes:copy.routes,roads:copy.roads});
  Layout.moveNodes(copy,[first.a,first.b],[1,0]);
  assert.equal(JSON.stringify({actors:copy.actors,lights:copy.lights,signs:copy.signs,routes:copy.routes,roads:copy.roads}),unrelated,file);
  authored++;
}

// Generated paint and road footprint follow the newly bent plan immediately.
const generated = fixture();
Layout.apply(generated);
const originalRoad = JSON.stringify(generated.roads);
generated.layout.streets[0].bend = [30,0];
Layout.apply(generated);
assert.notEqual(JSON.stringify(generated.roads),originalRoad);
assert(generated.roads.some(r => r.auto));
console.log(`Road geometry editing PASS: endpoint freedom, exact snapping, shared translation, shape-preserving rotation, atomic rejection, ${authored} authored layouts unchanged by inspection`);
