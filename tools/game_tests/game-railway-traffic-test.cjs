// Carried-over traffic must queue at a closed crossing and let its train pass.
// Run with the same NODE_PATH / GAME_URL setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const hook = `
window.railTest = {
  state, actorFootprint, footprintsOverlap,
  player: () => playerCarGroup,
  cases() { return window.PDD_ROAD_SITUATIONS.filter(s => s.scene.railway?.train).map(s => s.id); },
  show(id, inheritedType = null) {
    resetGame(); state.attract = false;
    state.roadSegments.slice().forEach(disposeSegment);
    state.roadSegments = []; state.actors = []; state.intersections = [];
    state.activeIntersection = null; state.occluders = []; state.ambient = [];
    state.exitRoad = currentCorridor = null;
    const road = buildStraightSegment(-45, 200, true);
    state.roadSegments.push(road); state.exitRoad = currentCorridor = road; nextSegmentZ = 155;
    const situation = window.PDD_ROAD_SITUATIONS.find(s => s.id === id);
    let onTrack = null;
    if (inheritedType) {
      const old = new THREE.Group(); scene.add(old); state.roadSegments.push(old);
      const start = new THREE.Vector3(1.8, 0, 65 + situation.scene.railway.z);
      onTrack = addRoadActor(old, {id: 'already_on_tracks', type: inheritedType, color: '#6E86A6'},
        start, Math.PI, [start, start.clone().add(new THREE.Vector3(0, 0, -200))], 8);
      onTrack.waitsForPlayer = false;
    }
    const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
    const ev = state.roadEvent = buildQuestionEvent(group, -45, situation);
    playerCarGroup.position.set(-1.8, 0, ev.stopZ); playerCarGroup.rotation.y = 0;
    startRoadQuestion(); state.paused = false;
    // Keep the player within the task's live stretch, clear of both queues.
    playerCarGroup.position.x = -10;
    // Different, turned parents reproduce traffic inherited from earlier tasks.
    const inherited = new THREE.Group(); inherited.rotation.y = Math.PI / 2;
    inherited.position.set(30, 0, -50); scene.add(inherited); state.roadSegments.push(inherited);
    inherited.updateWorldMatrix(true, false);
    const cars = [1, -1].map(dir => {
      const start = new THREE.Vector3(-dir * 1.8, 0, ev.crossingZ - dir * 45);
      const end = new THREE.Vector3(start.x, 0, ev.crossingZ + dir * 200);
      const points = [start, end].map(p => inherited.worldToLocal(p.clone()));
      const a = addRoadActor(inherited, {id: 'inherited_' + dir, type: 'car', color: '#6E86A6'},
        points[0], (dir > 0 ? 0 : Math.PI) - inherited.rotation.y, points, 18);
      a.waitsForPlayer = false; a.direction = dir; return a;
    });
    return {ev, cars, onTrack};
  },
  tick(dt) { updateActors(dt); updateRoadEvent(dt); },
  snapshot(centerZ) {
    const width = 18, height = width * 844 / 390;
    const view = new THREE.OrthographicCamera(-width, width, height, -height, .1, 300);
    view.up.set(0, 0, 1); view.position.set(0, 80, centerZ); view.lookAt(0, 0, centerZ);
    playerCarGroup.position.x = -1.8;
    scene.updateMatrixWorld(true); renderer.render(scene, view);
  },
  pedestrians() {
    resetGame(); state.attract = false; state.roadSegments.slice().forEach(disposeSegment);
    state.roadSegments = []; state.actors = []; state.intersections = [];
    state.exitRoad = currentCorridor = null;
    situationBag = [SITUATIONS.find(s => s.id === 'ticket_20_13')]; buildInitialTrack();
    const it = state.intersections[0]; playerCarGroup.position.set(-1.8, 0, it.stopZ);
    updatePlayerMovement(0); state.paused = false;
    window.game.proceedAfterAnswer(true, it.situation.id); window.game.releaseTraffic(it.situation.id);
    for (let i = 0; i < 120; i++) updateActors(1/60);
    this.snapshot(it.centerZ);
  }
};
`;

(async () => {
  const browser = await chromium.launch({headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader']});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}}), errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0; Math.random = () => .35;
      window.events = []; window.FlutterChannel = {postMessage: m => window.events.push(JSON.parse(m))};
    });
    await page.route('**/game.js', async route => {
      const source = fs.readFileSync(process.env.GAME_BASELINE || path.join(__dirname, '../../assets/game/game.js'), 'utf8');
      await route.fulfill({contentType: 'application/javascript', body: source.replace('  // Run init on DOM ready', hook + '\n  // Run init on DOM ready')});
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'));
    const report = await page.evaluate(() => {
      const t = railTest, out = [];
      for (const id of t.cases()) for (const fps of [30, 60]) {
        const {ev, cars} = t.show(id), violations = new Set(), dt = 1 / fps;
        const offset = ev.crossingZ - ev.railBoundaryZ;
        const check = () => cars.forEach(a => {
          const b = t.actorFootprint(a);
          const boundary = a.direction > 0 ? ev.railBoundaryZ :
            ev.crossingZ + ((ev.scene.railway.tracks || 1) - 1) * 5 + offset;
          if (!ev.rail.open && a.direction * (b.p.z - boundary) + b.halfLength > .05)
            violations.add('entered closed crossing: ' + a.direction);
          if (!ev.rail.train.done && t.footprintsOverlap(b, t.actorFootprint(ev.rail.train), .02))
            violations.add('overlaps train: ' + a.direction);
        });
        for (let i = 0; i < fps * 8; i++) { t.tick(dt); check(); }
        const waiting = cars.every(a => a.speed < .1);
        window.game.proceedAfterAnswer(true, id);
        for (let i = 0; i < fps * 20; i++) { t.tick(dt); check(); }
        const passed = cars.every(a => a.direction * (t.actorFootprint(a).p.z - ev.crossingZ) > 12);
        out.push({id, fps, waiting, open: ev.rail.open, passed, violations: [...violations]});
      }
      for (const inheritedType of ['car', 'truck']) for (const fps of [30, 60]) {
        const {ev, cars, onTrack} = t.show('road_27_16', inheritedType), violations = new Set();
        const all = [...cars, onTrack], dt = 1 / fps;
        const check = () => all.forEach(a => {
          if (!ev.rail.train.done && t.footprintsOverlap(t.actorFootprint(a), t.actorFootprint(ev.rail.train), .02))
            violations.add('train spawned or moved through ' + a.config.id);
        });
        check(); window.game.proceedAfterAnswer(true, ev.situation.id);
        for (let i = 0; i < fps * 25; i++) { t.tick(dt); check(); }
        out.push({id: 'already-on-tracks/' + inheritedType, fps, waiting: true,
          open: ev.rail.open, passed: t.actorFootprint(onTrack).p.z < ev.crossingZ - 15, violations: [...violations]});
      }
      for (const fps of [30, 60]) {
        const {ev} = t.show('road_27_16');
        window.game.proceedAfterAnswer(true, ev.situation.id);
        const train = ev.rail.train;
        for (let i = 0; i < fps * 2; i++) t.tick(1 / fps);
        const before = train.distance;
        // Deliberately put the player on the moving train, rather than in
        // the ordinary queue which correctly waits before the crossing.
        t.player().position.copy(t.actorFootprint(train).p);
        t.player().rotation.y = 0;
        for (let i = 0; i < fps; i++) t.tick(1 / fps);
        out.push({id: 'player-impact', fps, waiting: true, open: true,
          passed: train.distance > before + 5 && !train.crashed && train.speed > 1,
          violations: []});
      }
      return out;
    });
    const bad = report.filter(r => !r.waiting || !r.open || !r.passed || r.violations.length);
    assert.deepEqual(bad, [], 'railway traffic deadlock: ' + JSON.stringify(bad));
    assert.deepEqual(errors, []);
    if (process.env.GAME_SHOTS) {
      fs.mkdirSync(process.env.GAME_SHOTS, {recursive: true});
      await page.evaluate(() => {
        const {ev} = railTest.show('road_27_16');
        for (let i = 0; i < 480; i++) railTest.tick(1/60);
        railTest.snapshot(ev.crossingZ);
      });
      await page.screenshot({path: path.join(process.env.GAME_SHOTS, 'railway-wait.png')});
      await page.evaluate(() => railTest.pedestrians());
      await page.screenshot({path: path.join(process.env.GAME_SHOTS, 'pedestrians-ticket20_13.png')});
    }
    console.log('PASS: inherited traffic waits and clears all ' + report.length + ' railway/fps cases');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
