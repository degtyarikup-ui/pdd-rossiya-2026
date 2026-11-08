// Sparse editor controls preserve both runtime readers and all manual edit operations.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const L = require('../editor/layout.js');
const copy = value => structuredClone(value);
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const routes = s => s.routes.filter(r => r.kind === 'manoeuvre');

function smooth(points, step = 0.08) {
  const out = [];
  for (let i = 0; i + 1 < points.length; i++) {
    const a = points[Math.max(0, i - 1)], b = points[i], c = points[i + 1], d = points[Math.min(points.length - 1, i + 2)];
    const count = Math.max(2, Math.ceil(distance(b, c) / step));
    for (let j = 0; j < count; j++) {
      const t = j / count;
      out.push([0, 1].map(k => 0.5 * (2 * b[k] + (c[k] - a[k]) * t
        + (2 * a[k] - 5 * b[k] + 4 * c[k] - d[k]) * t * t
        + (3 * b[k] - a[k] - 3 * c[k] + d[k]) * t * t * t)));
    }
  }
  return [...out, points.at(-1)];
}

function sampleLine(points) {
  const out = [points[0]];
  for (let i = 1; i < points.length; i++) {
    const n = Math.max(1, Math.ceil(distance(points[i - 1], points[i]) / 0.08));
    for (let j = 1; j <= n; j++) out.push(points[i].map((v, axis) => points[i - 1][axis] + (v - points[i - 1][axis]) * j / n));
  }
  return out;
}

function gap(a, b) {
  let worst = 0;
  for (const p of a) {
    let nearest = Infinity;
    for (let i = 1; i < b.length; i++) {
      const x = b[i][0] - b[i - 1][0], z = b[i][1] - b[i - 1][1], square = x * x + z * z;
      const t = square ? Math.max(0, Math.min(1, ((p[0] - b[i - 1][0]) * x + (p[1] - b[i - 1][1]) * z) / square)) : 0;
      nearest = Math.min(nearest, Math.hypot(p[0] - b[i - 1][0] - x * t, p[1] - b[i - 1][1] - z * t));
    }
    worst = Math.max(worst, nearest);
  }
  return worst;
}

const pairs = [];
for (const sweep of [Math.PI / 2, Math.PI, Math.PI * 1.6]) {
  const steps = Math.ceil(sweep * 10.5);
  const dense = Array.from({ length: steps + 1 }, (_, i) => [10.5 * Math.cos(sweep * i / steps), 10.5 * Math.sin(sweep * i / steps)]);
  const last = dense.at(-1), heading = [-Math.sin(sweep), Math.cos(sweep)];
  for (let i = 1; i <= 60; i++) dense.push(last.map((v, axis) => v + heading[axis] * i));
  const original = copy(dense), compact = L.compactRoutePoints(dense);
  assert.deepEqual(dense, original, 'simplification never mutates an author array');
  assert.deepEqual(compact[0], dense[0]);
  assert.deepEqual(compact.at(-1), dense.at(-1), 'explicit manual simplification keeps the complete tail');
  assert.ok(compact.length < dense.length / 2, 'sampling vertices are substantially reduced');
  for (const sample of [sampleLine, smooth]) {
    const a = sample(dense), b = sample(compact), error = Math.max(gap(a, b), gap(b, a));
    assert.ok(error <= 0.05 + 1e-6, `raw/spline shape error ${error} must stay within five centimetres`);
  }
  pairs.push({ dense, compact });
}

// Same small three-arm ring and free pose as the reported case, with independent
// disposable question data. Never load or save the user's live ticket_27_14.
const layout = L.template('ring', 90);
layout.nodes = layout.nodes.filter(n => n.id !== 'n');
layout.streets = layout.streets.filter(st => st.a !== 'n' && st.b !== 'n');
layout.nodes.find(n => n.id === 'c').ring = { r: 15, island: 6 };
const scene = { schema: 1, id: 'route_control_fixture', crop: 90, layout,
  question: { maneuver: 'left', correct: 0, yieldTo: [], text: { ru: { title: 'Проверка пути', options: ['Да', 'Нет'] } } },
  roads: [], routes: [], markings: [], lawns: [], actors: [], lights: [], decor: [] };
L.apply(scene);
L.setPlayerMode(scene, 'free');
scene.layout.player.pose = { x: -8.66, z: -5.27, yaw: -0.524 };
L.apply(scene);
assert.equal(scene.playerRouteErrors, undefined);
const frozen = copy({ roads: scene.roads, markings: scene.markings, lawns: scene.lawns, layout: scene.layout, stop: scene.stop });
const left = routes(scene).find(r => r.exit === 'left');
assert.ok(left.points.length <= 30, `left ring arrow needs a manageable number of controls (${left.points.length})`);
assert.ok(left.points.at(-1)[0] < 45 && left.points.at(-1)[0] > 25, 'teaching arrow ends shortly after the turn');
assert.ok(scene.roads.some(road => road.outer.some(p => p[0] >= 90)), 'complete exit road remains available for runtime continuation');
const generated = copy(routes(scene));
// Simulate an old export with sampling vertices and an overlong teaching tail.
for (const route of routes(scene)) route.points = sampleLine(route.points);
L.refreshPlayerRoutes(scene);
assert.deepEqual(routes(scene), generated, 'opening an older auto route refreshes just its generated controls');
assert.deepEqual({ roads: scene.roads, markings: scene.markings, lawns: scene.lawns, layout: scene.layout, stop: scene.stop }, frozen,
  'route refresh leaves all authored geometry, paint, source paths and the player unchanged');

const editable = copy(scene), r = routes(editable).find(r => r.exit === 'left');
L.setPlayerRouteManual(editable, r, true);
L.apply(editable);
let manual = routes(editable).find(r => r.exit === 'left');
const beforeDrag = copy(manual.points), index = Math.floor(manual.points.length / 2);
const samePoints = manual.points;
L.editPlayerRoute(editable, manual);
assert.equal(manual.points, samePoints, 'drag initialization never changes selected point indices');
manual.points[index] = [manual.points[index][0] + 0.12, manual.points[index][1]];
L.apply(editable);
manual = routes(editable).find(r => r.exit === 'left');
assert.equal(manual.points.length, beforeDrag.length, 'drag never creates a new metre-by-metre sample grid');
const changed = copy(manual.points), sourcePaths = copy(editable.layout.freePaths);
const reload = copy(editable);
L.apply(reload);
assert.deepEqual(routes(reload).find(r => r.exit === 'left').points, changed, 'manual controls survive reload exactly');
L.refreshPlayerRoutes(reload);
assert.deepEqual(routes(reload).find(r => r.exit === 'left').points, changed, 'opening a manual route never simplifies or rewrites its controls');
assert.deepEqual(reload.layout.freePaths, sourcePaths);
manual = routes(editable).find(r => r.exit === 'left');
L.editPlayerRoute(editable, manual);
manual.points.splice(index, 0, manual.points[index].map((v, axis) => (v + manual.points[index - 1][axis]) / 2));
L.apply(editable);
assert.equal(routes(editable).find(r => r.exit === 'left').points.length, changed.length + 1, 'inserted point stays a single editable point');
manual = routes(editable).find(r => r.exit === 'left');
L.editPlayerRoute(editable, manual);
manual.points.splice(index, 1);
L.apply(editable);
assert.deepEqual(routes(editable).find(r => r.exit === 'left').points, changed, 'deleting the inserted point restores the exact manual route');
const undo = copy(scene);
assert.deepEqual(routes(undo), generated, 'restoring an editor snapshot restores the original auto controls');
L.setPlayerRouteManual(editable, routes(editable).find(r => r.exit === 'left'), false);
L.apply(editable);
assert.deepEqual(routes(editable).find(r => r.exit === 'left').points, left.points, 'reset returns the short automatic arrow');

if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify({ scene, pairs }));
console.log('Player route controls: raw+spline <= 5 cm, short ring arrows, source preservation, refresh, drag/insert/delete/reload/reset PASS');
