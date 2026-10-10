// PDD matrix, anatomical handedness and shared seasonal assets (no GPU needed).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const THREE = require(path.join(root, 'assets/game/three.min.js'));
const context = vm.createContext({ THREE, navigator: {hardwareConcurrency: 4},
  document: {}, window: {addEventListener() {}}, console });
for (const file of ['seasons.js', 'traffic-controller-model.js', 'street-models.js', 'traffic-controller.js']) {
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
console.log('32 PDD scenarios, four anatomical poses, 12 calendar months, main and sparse mini-game leaves passed.');

// Exercise the real mini-game layout for five minutes at both quality levels.
// Test-only exports do not add a debugging API to the shipped scene.
for (const weak of [true, false]) {
  const streetContext = vm.createContext({THREE, navigator: {hardwareConcurrency: weak ? 4 : 8},
    document: {}, window: {addEventListener() {}, PDD_VEHICLES: {applyModelEdits: (_, model) => model}}, console});
  for (const file of ['seasons.js', 'traffic-controller-model.js', 'street-models.js', 'traffic-controller.js']) {
    let source = fs.readFileSync(path.join(root, 'assets/game', file), 'utf8');
    if (file === 'traffic-controller.js') source = source.replace('window.TrafficControllerGame = {',
      'window.streetTest = {buildPedestrians, updatePedestrians, walkers, buildStreetFurniture}; window.TrafficControllerGame = {');
    vm.runInContext(source, streetContext);
  }
  const street = streetContext.window.streetTest;
  const pavement = new THREE.Group();
  street.buildPedestrians(pavement, 13.6);
  assert.equal(street.walkers.length, weak ? 4 : 8);
  for (let step = 0; step < 1200; step++) {
    street.updatePedestrians(0.25);
    for (const {mesh} of street.walkers) {
      assert(mesh.userData.ambient && mesh.userData.noCollision);
      assert(Math.abs(mesh.position.x) > 7.55 && Math.abs(mesh.position.z) > 7.55);
      assert(Number.isFinite(mesh.rotation.y));
      if (step % 60 === 0) {
        const box = new THREE.Box3().setFromObject(mesh);
        assert(box.min.x > 6.8 || box.max.x < -6.8, 'Whole pedestrian stays outside the north/south road');
        assert(box.min.z > 6.8 || box.max.z < -6.8, 'Whole pedestrian stays outside the east/west road');
      }
    }
  }
  const furniture = new THREE.Group();
  street.buildStreetFurniture(furniture, 13.6);
  assert.equal(furniture.children.length, 2, 'All lamps stay in two draw calls');
  assert.equal(furniture.children[0].material.type, 'MeshLambertMaterial');
  assert.equal(furniture.children[0].material.color.getHex(), 0x5B646A, 'Main-game grey lamp material');
  assert.equal(furniture.children[1].material.color.getHex(), 0xE6E9D8);
}
assert(!/tramMesh|buildTramTracks|buildRussianTram/.test(miniSource), 'No tram models or tracks in the mini-game');
console.log('Shared grey lamps (two batches) and 4/8 pedestrians stayed safely on pavements for five minutes.');

// Every visible street corner receives rain at the most distant game zoom.
for (const [height, distance] of [[4.5, 22], [38, 50]]) {
  const camera = new THREE.PerspectiveCamera(50, 575 / 1280, 0.1, 500);
  camera.position.set(2.4, height, distance); camera.lookAt(0, 0, 0);
  const bounds = api.getRainBounds(camera);
  for (const nx of [-1, 1]) for (const ny of [-1, 1]) {
    const ray = new THREE.Vector3(nx, ny, 0.5).unproject(camera).sub(camera.position).normalize();
    const t = -camera.position.y / ray.y;
    if (t > 0 && t <= 180) {
      const corner = camera.position.clone().addScaledVector(ray, t);
      assert(corner.x >= bounds.minX && corner.x <= bounds.maxX);
      assert(corner.z >= bounds.minZ && corner.z <= bounds.maxZ);
    }
  }
  assert(Object.values(bounds).every(Number.isFinite));
}
console.log('Rain covers near and maximum-zoom street footprints');
