// PDD matrix, anatomical handedness and shared seasonal assets (no GPU needed).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const THREE = require(path.join(root, 'assets/game/three.min.js'));
const context = vm.createContext({ THREE, window: {}, console });
vm.runInContext(fs.readFileSync(path.join(root, 'assets/game/seasons.js'), 'utf8'), context);
const seasons = context.window.PDD_SEASONS;
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

  const miniScene = new THREE.Scene();
  const count = lowEnd ? 6 : 12;
  const mini = seasons.createLeaves(miniScene, {count, scaleMin: 0.55, scaleMax: 0.85,
    spanX: 32, spanZ: 44, height: 7, spreadEvenly: true, palette: () => seasons.palettes.autumn.canopy});
  mini.update(0, {enabled: true, centre});
  assert.equal(mini.mesh.count, count);
  const columns = Math.ceil(Math.sqrt(count)), rows = Math.ceil(count / columns);
  const matrix = new THREE.Matrix4(), position = new THREE.Vector3(), scale = new THREE.Vector3(), rotation = new THREE.Quaternion();
  for (let i = 0; i < count; i++) {
    mini.mesh.getMatrixAt(i, matrix);
    matrix.decompose(position, rotation, scale);
    assert(scale.x >= 0.549 && scale.x <= 0.851, 'Mini leaves must stay small');
    assert(position.x >= ((i % columns) / columns - 0.5) * 32 - 0.001);
    assert(position.x <= (((i % columns) + 1) / columns - 0.5) * 32 + 0.001);
    assert(position.z >= (Math.floor(i / columns) / rows - 0.5) * 44 - 0.001);
    assert(position.z <= ((Math.floor(i / columns) + 1) / rows - 0.5) * 44 + 0.001);
  }
  for (let i = 0; i < 1200; i++) mini.update(0.05, {enabled: true, centre});
  assert.equal(miniScene.children.length, 1);
  assert(Array.from(mini.mesh.instanceMatrix.array).every(Number.isFinite));
}
console.log('Shared crossroads seasonal assets: 12 calendar months and batched leaves passed.');
