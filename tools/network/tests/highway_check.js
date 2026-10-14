// Source fixtures for continuous highways and explicitly authored 3+3 -> 2+2 ends.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const L = require('../editor/layout.js');
const clone = s => JSON.parse(JSON.stringify(s));
const fixtures = [];
const near = (a, b, message) => assert.ok(Math.abs(a - b) < .001, `${message}: ${a} != ${b}`);

function scene(template = 'highway', lane = 0, maneuver = 'straight', crop = 90) {
  const s = {schema: 1, id: 'highway-test', crop, layout: L.template(template, crop),
    question: {maneuver, correct: 0, text: {ru: {options: ['Да']}}}, compliance: {status: 'ok'},
    roads: [], markings: [], lawns: [], routes: [], actors: [], lights: []};
  for (const st of s.layout.streets) st.kind = 'highway';
  s.layout.player = {...(s.layout.player || {}), lane};
  L.apply(s);
  return s;
}

function setPort(st, end, port) {
  st.ends = {...st.ends, [end]: {...(st.ends || {})[end], port}};
}

function retain(s, name, footprints = false) {
  s.testCase = name;
  s.testFootprints = footprints;
  // Record intended sections independently of the generated outline for native parity checks.
  s.expectedPorts = {};
  for (const st of s.layout.streets) for (const end of ['a', 'b']) {
    const nid = st[end];
    if (L.nodeKind(s.layout, L.nodeOf(s.layout, nid), s.crop) !== 'border') continue;
    const full = st.kind === 'highway' && (st.ends || {})[end]?.port !== 'avenue';
    s.expectedPorts[nid] = {lanes: full ? 6 : 4, width: full ? L.widthOf(st) : 14,
      median: full ? L.medianOf(st) : 0};
  }
  const before = JSON.stringify(s);
  L.apply(s);
  assert.equal(JSON.stringify(s), before, `${name}: generated data remains stable`);
  const reloaded = clone(s);
  L.apply(reloaded);
  assert.deepEqual(reloaded, s, `${name}: save/load keeps end choices and geometry`);
  fixtures.push(s);
  return s;
}

assert.equal(L.widthOf({kind: 'highway'}), 24);
assert.deepEqual(L.laneOffsets({kind: 'highway'}), [3.25, 6.75, 10.25]);
const settings = {kind: 'highway', ends: {a: {stop: true, zebra: true, approachOffset: -3}, b: {port: 'avenue', stop: false}}};
const settingsBefore = clone(settings);
assert.equal(L.highwayPort(settings, 'a'), 'highway');
assert.deepEqual(settings, settingsBefore, 'reading the implicit end setting never edits the source');
L.setHighwayPort(settings, 'a', 'avenue');
assert.deepEqual(settings.ends.a, {...settingsBefore.ends.a, port: 'avenue'}, 'changing the connection keeps other end controls');
assert.deepEqual(settings.ends.b, settingsBefore.ends.b, 'the opposite end is independent');
L.setHighwayPort(settings, 'a', 'highway');
assert.deepEqual(settings, settingsBefore, 'reset returns to the implicit full highway without stale taper data');

// Preserve the original turn/lane matrix. A normal highway never narrows at a scene edge.
for (const template of ['highway', 'cross', 'ring']) for (const lane of [0, 1, 2]) {
  for (const maneuver of template === 'highway' ? ['straight'] : ['straight', 'left', 'right', 'uturn']) {
    const s = scene(template, lane, maneuver), plan = L.playerPlan(s);
    assert.equal(plan.laneIndex, lane);
    assert.equal(L.medianOf(plan.st), 3);
    for (const st of s.layout.streets) {
      const total = L.polyLen(L.centreline(s.layout, st));
      for (const d of [0, 24, total / 2, total - 24, total]) {
        assert.deepEqual(L.streetProfile(s.layout, st, d, s.crop), {width: 24, median: 3, blend: 1},
          `${template}: implicit highway ends retain all six lanes`);
      }
    }
    retain(s, `${template}-${lane}-${maneuver}`, template === 'highway');
  }
}

const straight = fixtures[0];
assert.equal(straight.markings.filter(m => m.type === 'dashed').length, 4, 'two boundaries per carriageway');
assert.equal(straight.markings.filter(m => m.type === 'solid').length, 0, 'divider continues instead of double centre paint');

// Only the chosen end creates a taper; the opposite end can join another highway question.
for (const ends of [['a'], ['b'], ['a', 'b']]) for (const lane of [0, 1, 2]) {
  const s = scene('highway', lane), st = s.layout.streets[0];
  for (const end of ends) setPort(st, end, 'avenue');
  L.apply(s);
  const total = L.polyLen(L.centreline(s.layout, st));
  for (const end of ['a', 'b']) for (const d of [0, 24, 34]) {
    const profile = L.streetProfile(s.layout, st, end === 'a' ? d : total - d, s.crop);
    assert.deepEqual(profile, ends.includes(end) ? {width: 14, median: 0, blend: 0} : {width: 24, median: 3, blend: 1},
      `${ends}: contact plus blend zone at ${end}/${d}`);
  }
  assert.deepEqual(L.streetProfile(s.layout, st, total / 2, s.crop), {width: 24, median: 3, blend: 1},
    'full-size question section remains between ordinary end transitions');
  retain(s, `transition-${ends.join('')}-${lane}`, true);
}

// Explicit highway choices, different medians and reloads preserve the continuous section.
for (const median of [2, 3, 5]) {
  const s = scene('highway', 2), st = s.layout.streets[0];
  st.median = median;
  setPort(st, 'a', 'highway'); setPort(st, 'b', 'highway');
  L.apply(s);
  for (const d of [0, 24, 90, 156, 180]) {
    assert.deepEqual(L.streetProfile(s.layout, st, d, s.crop), {width: 21 + median, median, blend: 1});
  }
  near(Math.abs(s.routes.find(r => r.kind === 'manoeuvre').points.at(-1)[0]), median / 2 + 8.75,
    'outer lane continues as the outer lane through the next highway edge');
  retain(s, `median-${median}`, true);
}

const early = scene('highway', 2);
early.layout.player.questionAt = 65;
L.apply(early); retain(early, 'earlier-question', true);

for (const taper of [false, true]) {
  const curved = scene('highway', 2), st = curved.layout.streets[0];
  st.bend = [18, 0];
  if (taper) { setPort(st, 'a', 'avenue'); setPort(st, 'b', 'avenue'); }
  L.apply(curved); retain(curved, `curve-${taper ? 'ordinary-ends' : 'continuous'}`, true);
}

// Internal highway-to-avenue joints still narrow; highway-to-highway joints stay wide.
for (const kind of ['avenue', 'highway']) {
  const joint = scene('highway', 2);
  joint.layout.nodes.push({id: 'join', x: 0, z: 35});
  const st = joint.layout.streets[0]; st.b = 'join';
  joint.layout.streets.push({id: 'tail', a: 'join', b: 'n', kind});
  L.apply(joint);
  const profile = L.streetProfile(joint.layout, st, 125, joint.crop);
  assert.equal(profile.width, kind === 'avenue' ? 14 : 24, 'internal neighbour defines its joint');
  assert.equal(profile.median, kind === 'avenue' ? 0 : 3);
  retain(joint, `internal-${kind}`, true);
}

// Small scenes stay continuous, or safely remain 2+2 when two transition plateaus overlap.
const short = scene('highway', 2, 'straight', 40);
retain(short, 'short-continuous', true);
const shortTaper = scene('highway', 2, 'straight', 30), shortStreet = shortTaper.layout.streets[0];
setPort(shortStreet, 'a', 'avenue'); setPort(shortStreet, 'b', 'avenue');
L.apply(shortTaper);
for (const d of [0, 24, 30, 36, 60]) {
  assert.deepEqual(L.streetProfile(shortTaper.layout, shortStreet, d, shortTaper.crop), {width: 14, median: 0, blend: 0},
    'overlapping ordinary contact plateaus must not form a narrow highway bubble');
}
retain(shortTaper, 'short-ordinary-ends', true);

const manual = scene('highway', 2);
manual.layout.streets[0].manualMarks = true;
L.apply(manual);
assert.equal(manual.markings.filter(m => m.type === 'solid' || m.type === 'dashed').length, 0,
  'manual paint suppresses generated lane dividers');
retain(manual, 'manual-paint', true);

// Keep the ordinary reference last for the runtime fixture consumers.
const ordinary = scene(); ordinary.layout.streets[0].kind = 'avenue';
L.apply(ordinary); ordinary.reference = true;
retain(ordinary, 'ordinary-reference', true);

if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(fixtures));
console.log(`Highway: ${fixtures.length} full/tapered ends, three lanes, medians, turns, short/curved roads, persistence/manual paint PASS`);
