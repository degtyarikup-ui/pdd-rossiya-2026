// New tram routes, authored branches and stationary/manual choices survive rebuilds.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Layout = require('../editor/layout.js');
const Tracks = require('../editor/tracks.js');
const Signals = require('../editor/actor_signals.js');
const copy = value => JSON.parse(JSON.stringify(value));
const root = path.resolve(__dirname, '../../..');
const template = JSON.parse(fs.readFileSync(path.join(root, 'game_godot/network/ticket_33_8.json')));
const fixtures = [];

for (const way of ['left', 'straight', 'right', 'uturn']) {
  const scene = copy(template);
  scene.actors = [{id: 'new-tram', type: 'tram', pos: [-5.25, -35], yaw: 0,
    halfLength: 5, halfWidth: 1.2, way, behaviour: {staysPut: false}}];
  Layout.apply(scene);
  const actor = scene.actors[0], route = scene.routes.find(r => r.id === actor.route);
  assert.ok(route.auto && Layout.polyLen(route.points) > 10, `${way}: tram receives a route from ordinary arrows`);
  const saved = copy(scene);
  Layout.apply(scene); Tracks.apply(scene);
  assert.deepEqual(copy(scene), saved, `${way}: reload/rebuild is stable`);
  fixtures.push({name: `automatic ${way}`, scene});
}

const branchScene = {actors: [{id: 'new-tram', type: 'tram', pos: [0, -10], yaw: 0,
  track: 'main', branch: 'service', halfLength: 5, halfWidth: 1.2,
  behaviour: {staysPut: false, waitsForPlayer: true, hazards: true}}], routes: [],
  tracks: [{id: 'main', points: [[0, -60], [0, 60]]},
    {id: 'service', points: [[0, 20], [10, 25], [30, 25]], depot: true},
    {id: 'unused', points: [[40, -60], [40, 60]]}]};
Tracks.apply(branchScene);
const actor = branchScene.actors[0];
assert.deepEqual(branchScene.routes[0].points, [[0, -10], [0, 20], [10, 25], [30, 25]]);
assert.ok(actor.behaviour.hazards && actor.behaviour.waitsForPlayer && !actor.behaviour.staysPut);
fixtures.push({name: 'authored branch', scene: copy(branchScene)});

Signals.setMoving(actor, false);
const stopped = copy(branchScene);
Tracks.apply(branchScene);
assert.deepEqual(branchScene, stopped, 'a stopped bound tram stays stopped after an unrelated edit');
fixtures.push({name: 'stopped bound tram', scene: copy(branchScene)});
Signals.setMoving(actor, true);
Tracks.apply(branchScene);
assert.ok(!actor.behaviour.staysPut && actor.behaviour.hazards && actor.behaviour.waitsForPlayer);

const route = branchScene.routes[0];
Layout.editPlayerRoute(branchScene, route);
route.points[2] = [9, 28];
const manual = copy(branchScene);
Layout.applyActors(branchScene); Tracks.apply(branchScene);
assert.deepEqual(branchScene, manual, 'explicit rail actor route edits survive all rebuilds');
fixtures.push({name: 'manual bound tram route', scene: copy(branchScene)});

for (const rgb of [[142, 153, 156], [146, 154, 156]]) {
  const colour = rgb.map(v => v / 255);
  const linear = colour.map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
  for (const c of [colour, linear]) {
    assert.ok(Tracks.isBakedRailTriangle([.05, .05, .05], [c, c, c]), 'old ground rails are removed in either colour space');
    assert.ok(!Tracks.isBakedRailTriangle([.05, .05, 1], [c, c, c]), 'same grey on a post/building remains');
    assert.ok(!Tracks.isBakedRailTriangle([.05, .05, .05], [c, c, [.2, .3, .4]]), 'mixed-colour scenery remains');
  }
}
assert.ok(!Tracks.isBakedRailTriangle([.05, .05, .05], Array(3).fill([.5, .5, .5])), 'other grey ground remains');

if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(fixtures));
console.log(`Tram editor: ${fixtures.length} automatic/manual/stationary/branch cases and baked colour filter PASS`);
