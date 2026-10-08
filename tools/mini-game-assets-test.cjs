// PDD matrix, anatomical handedness and shared seasonal assets (no GPU needed).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const THREE = require(path.join(root, 'assets/game/three.min.js'));
const context = vm.createContext({ THREE, navigator: {hardwareConcurrency: 4},
  document: {}, window: {addEventListener() {}}, console });
for (const file of ['seasons.js', 'traffic-controller-model.js', 'traffic-controller.js']) {
  vm.runInContext(fs.readFileSync(path.join(root, 'assets/game', file), 'utf8'), context);
}
const api = context.window.TrafficControllerGame;
const matrix = JSON.parse(fs.readFileSync(path.join(root, 'test/fixtures/traffic_controller_pdd_6_10.json')));
for (const row of matrix) {
  assert.deepEqual(Array.from(api.getAllowedMoves(row.gesture, row.approach, row.vehicle)).sort(), [...row.moves].sort());
}
const controller = context.window.PDD_CONTROLLER;
for (const pose of Object.keys(controller.poses)) {
  const model = controller.create(pose);
  const {right, left} = model.controllerRig;
  assert(right.position.x < 0, 'Right hand must be anatomical right (-X), facing +Z');
  assert(left.position.x > 0);
  const direction = new THREE.Vector3(0, -1, 0).applyEuler(right.rotation);
  if (pose === 'right_arm_forward') assert(direction.z > 0.99);
  if (pose === 'arms_sides') assert(direction.x < -0.99);
  if (pose === 'arm_up') assert(direction.y > 0.99);
  if (pose === 'arms_down') assert(direction.y < -0.99);
}
const seasons = context.window.PDD_SEASONS;
// These files are plain browser JS: check the seasonal asset contract so
// a typo cannot silently leave a lawn or roof with Three.js's white default.
const miniSource = fs.readFileSync(path.join(root, 'assets/game/traffic-controller.js'), 'utf8');
for (const [, key] of miniSource.matchAll(/\bseason\.([a-zA-Z]+)/g)) {
  for (const palette of Object.values(seasons.palettes)) assert(key in palette, `Unknown seasonal field: ${key}`);
}
const expected = ['winter','winter','summer','summer','summer','summer','summer','summer','autumn','autumn','autumn','winter'];
for (let m = 0; m < 12; m++) assert.equal(seasons.fromDate(new Date(2026, m, 15)), expected[m]);
for (const lowEnd of [true, false]) {
  const scene = new THREE.Scene();
  const leaves = seasons.createLeaves(scene, {lowEnd, palette: () => seasons.palettes.autumn.canopy});
  const centre = new THREE.Vector3();
  leaves.update(0.016, {enabled: true, centre});
  assert.equal(leaves.mesh.count, lowEnd ? 18 : 36);
  for (let i = 0; i < 180; i++) leaves.update(0.016, {enabled: true, centre});
  assert.equal(scene.children.length, 1, 'All leaves share one instanced mesh');
  assert(Array.from(leaves.mesh.instanceMatrix.array).every(Number.isFinite));
  leaves.update(0.016, {enabled: false, centre});
  assert.equal(leaves.mesh.visible, false);
}
console.log('32 PDD scenarios, four anatomical poses, 12 calendar months and instanced leaves passed.');
