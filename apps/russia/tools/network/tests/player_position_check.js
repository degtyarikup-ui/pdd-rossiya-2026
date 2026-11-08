// Starting the question before the stop line must change the car/routes, not road paint.
const assert = require('node:assert/strict');
const Layout = require('../editor/layout.js');
for (const template of ['cross', 'avenue', 'tee', 'straight']) {
  const s = { id: 'test', crop: 90, layout: Layout.template(template, 90), question: { maneuver: 'straight' }, roads: [], routes: [], markings: [], lawns: [], actors: [], lights: [] };
  Layout.apply(s);
  const before = Layout.playerPlan(s), paint = JSON.stringify(s.markings), stop = {...s.stop};
  s.layout.player = { ...s.layout.player, street: before.st.id, toward: before.nid, questionAt: before.sd + 12 };
  Layout.apply(s);
  const after = Layout.playerPlan(s);
  assert.equal(after.sd, before.sd + 12);
  assert.equal(after.stopLineDistance, before.stopLineDistance);
  assert.equal(JSON.stringify(s.markings), paint, `${template}: markings must stay in place`);
  assert.ok(Math.hypot(s.stop.x - stop.x, s.stop.z - stop.z) > 10);
  assert.deepEqual(s.routes.find(r => r.kind === 'approach').points.at(-1), [s.stop.x, s.stop.z]);
  for (const route of s.routes.filter(r => r.kind === 'manoeuvre')) assert.deepEqual(route.points[0], [s.stop.x, s.stop.z]);
  const restored = JSON.parse(JSON.stringify(s));
  Layout.apply(restored);
  assert.deepEqual(restored.stop, s.stop, 'Question position survives saving/reloading');
  delete s.layout.player.questionAt;
  Layout.apply(s);
  assert.deepEqual(s.stop, stop, 'Reset returns the car to the original stop');
  assert.equal(JSON.stringify(s.markings), paint);
}
console.log('Independent player position: all checks passed');
