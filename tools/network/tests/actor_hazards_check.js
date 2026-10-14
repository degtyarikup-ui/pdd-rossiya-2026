// Authored emergency signals survive geometry rebuilds and source save/reload.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Layout = require('../editor/layout.js');
const Signals = require('../editor/actor_signals.js');
const copy = value => JSON.parse(JSON.stringify(value));
const root = path.resolve(__dirname, '../../..');
const original = JSON.parse(fs.readFileSync(path.join(root, 'game_godot/network/ticket_33_8.json')));
const cases = [];
// The author may edit the real question; its copied legacy stationary defaults
// are the regression fixture, not a constraint on what may be saved in the stand.
delete original.actors[0].behaviour.hazards;
original.actors[0].behaviour.staysPut = true;
original.actors[0].behaviour.stopAtDistance = 0;
original.actors[0].behaviour.stopFor = 'inf';
original.actors[0].behaviour.config.hazard = true;

for (const type of ['car', 'truck', 'bus', 'van', 'special', 'tanker', 'motorcycle', 'tram', 'tractor']) {
  assert.ok(Signals.supports(type), `${type} can use emergency signals`);
  assert.ok(Signals.hazards({type, behaviour: {hazards: true}}));
}
for (const type of ['pedestrian', 'cyclist', undefined]) {
  assert.ok(!Signals.supports(type));
  assert.ok(!Signals.hazards({type, behaviour: {hazards: true}}));
}
assert.ok(Signals.pulse(0) && !Signals.pulse(.34) && Signals.pulse(.67), 'both sides use a single blink phase');
assert.ok(!Signals.hazards({type: 'car'}), 'a new actor starts with emergency signals off');
assert.ok(!Signals.hazards({type: 'car', behaviour: {hazards: false, config: {hazard: true}}}), 'explicit off overrides legacy on');
assert.ok(Signals.hazards({type: 'car', behaviour: {hazards: true, config: {hazard: false}}}), 'explicit on overrides legacy off');

function preserved(scene, expected, label) {
  const actor = scene.actors[0];
  const before = copy(actor);
  const route = actor.route && copy(scene.routes.find(r => r.id === actor.route));
  Layout.apply(scene);
  const reloaded = copy(scene);
  Layout.apply(reloaded);
  assert.deepEqual(reloaded.actors[0], before, `${label}: actor behaviour/pose survives rebuild and reload`);
  if (route) assert.deepEqual(reloaded.routes.find(r => r.id === route.id), route, `${label}: manual path survives rebuild and reload`);
  assert.equal(Signals.hazards(reloaded.actors[0]), expected, `${label}: signal setting survives reload`);
  cases.push({name: label, expected, scene: reloaded});
}

const legacy = copy(original);
assert.equal(legacy.actors[0].id, 'parked');
assert.ok(legacy.actors[0].behaviour.staysPut);
assert.ok(legacy.actors[0].behaviour.config.hazard);
assert.ok(Signals.hazards(legacy.actors[0]), 'ticket 33 question 8 keeps its archived emergency signal');
preserved(legacy, true, 'legacy stationary vehicle');

for (const enabled of [true, false]) {
  const scene = copy(original), actor = scene.actors[0];
  const behaviour = copy(actor.behaviour);
  Signals.setHazards(actor, enabled);
  assert.deepEqual(actor.behaviour, {...behaviour, hazards: enabled}, 'toggle keeps all other behaviour fields');
  preserved(scene, enabled, `explicit ${enabled ? 'on' : 'off'} stationary vehicle`);
}

const moving = copy(original);
moving.actors[0].behaviour.staysPut = false;
moving.actors[0].behaviour.waitsForPlayer = true;
moving.actors[0].behaviour.stopAtDistance = 2;
moving.actors[0].behaviour.stopFor = 1;
moving.actors[0].behaviour.signalPlan = {before: 'right'};
moving.actors[0].behaviour.config.hazard = false;
Signals.setHazards(moving.actors[0], true);
preserved(moving, true, 'moving vehicle with emergency signals');

const normal = copy(moving);
normal.actors[0].behaviour = {staysPut: false, waitsForPlayer: true};
preserved(normal, false, 'normal vehicle reusing an archived hazard model');

const automatic = copy(moving), automaticActor = automatic.actors[0];
automaticActor.pos = [-5.25, -35];
automaticActor.yaw = 0;
automaticActor.way = 'right';
automatic.routes = automatic.routes.filter(r => r.id !== automaticActor.route);
Layout.apply(automatic);
const automaticRoute = automatic.routes.find(r => r.id === automaticActor.route);
assert.ok(automaticRoute.auto && automaticRoute.points.length > 2, 'moving vehicle receives a generated turn path');
preserved(automatic, true, 'moving vehicle with an automatic turn path');

const formerlyParked = copy(legacy), formerlyParkedActor = formerlyParked.actors[0];
const parkedBehaviour = copy(formerlyParkedActor.behaviour);
Signals.setMoving(formerlyParkedActor, true);
assert.deepEqual(formerlyParkedActor.behaviour, {...parkedBehaviour, staysPut: false, stopAtDistance: null, stopFor: null}, 'move clears only the legacy permanent stationary hold');
formerlyParkedActor.pos = [-5.25, -35];
formerlyParkedActor.yaw = 0;
formerlyParkedActor.way = 'right';
formerlyParked.routes = formerlyParked.routes.filter(r => r.id !== formerlyParkedActor.route);
Layout.apply(formerlyParked);
const formerRoute = formerlyParked.routes.find(r => r.id === formerlyParkedActor.route);
assert.ok(Layout.polyLen(formerRoute.points) > 2, 'formerly parked vehicle has a nonzero departure route');
preserved(formerlyParked, true, 'legacy parked vehicle changed to moving');

const temporaryHold = copy(moving);
temporaryHold.actors[0].behaviour.staysPut = true;
const heldBehaviour = copy(temporaryHold.actors[0].behaviour);
Signals.setMoving(temporaryHold.actors[0], true);
assert.deepEqual(temporaryHold.actors[0].behaviour, {...heldBehaviour, staysPut: false}, 'temporary stops remain authored when switching to moving');
preserved(temporaryHold, true, 'moving vehicle with a temporary hold');
const alreadyMoving = {type: 'car', behaviour: {staysPut: false, stopAtDistance: 10, stopFor: 'inf', hazards: true}};
const movingBehaviour = copy(alreadyMoving.behaviour);
Signals.setMoving(alreadyMoving, true);
assert.deepEqual(alreadyMoving.behaviour, movingBehaviour, 'an already moving simulation keeps its permanent stop');
Signals.setMoving(alreadyMoving, false);
assert.deepEqual(alreadyMoving.behaviour, {...movingBehaviour, staysPut: true}, 'standing still keeps the signal and stop fields');

const stationary = copy(original), actor = stationary.actors[0];
Signals.setHazards(actor, true);
delete actor.way;
stationary.routes = stationary.routes.filter(r => r.id !== actor.route);
actor.route = null;
preserved(stationary, true, 'stationary vehicle without a route');

if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(cases));
console.log(`Actor emergency signals: ${cases.length} source cases, toggle/persistence/legacy/defaults PASS`);
