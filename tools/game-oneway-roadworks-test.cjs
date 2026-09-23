// One-way exits, road works (knockable props, legal detour), solid obstacle
// car and junction exits hugging the far kerb (formerly a dead end).
// Run with the same GAME_URL / NODE_PATH setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--use-angle=swiftshader'] });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.addInitScript(() => { window.events = []; window.FlutterChannel = { postMessage: m => window.events.push(JSON.parse(m)) }; window.requestAnimationFrame = () => 0; });
  await page.route('**/game.js', async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace('  // Run init on DOM ready', `
    window.T = {
      state,
      step(n = 1) { for (let i = 0; i < n; i++) { const dt = 1/60; updateAttract(dt); updateActors(dt);
        if (state.resolution) updateResolution(dt); else updatePlayerMovement(dt);
        updateRoadEvent(dt); updateBlinkers(dt); updateCamera(dt); checkAndSpawnNext(); } },
      select(id) { resetGame(); state.attract = false; state.roadSegments.forEach(disposeSegment); state.roadSegments = []; state.intersections = [];
        situationBag = [SITUATIONS.find(s => s.id === id)]; buildInitialTrack(); state.viewportInsets = {top: 110, bottom: 300}; state.viewportTarget = null; },
      approach() { playerCarGroup.position.z = state.intersections[0].stopZ; updatePlayerMovement(0); },
      // drive along a polyline of world points
      follow(points, speed = 5, maxFrames = 3000) {
        const P = points.map(([x, z]) => new THREE.Vector3(x, 0, z)); let k = 0;
        for (let f = 0; f < maxFrames && k < P.length; f++) {
          const p = playerCarGroup.position; if (p.distanceTo(P[k]) < 2.5) { k++; continue; }
          const h = Math.atan2(P[k].x - p.x, P[k].z - p.z), e = Math.atan2(Math.sin(h - playerCarGroup.rotation.y), Math.cos(h - playerCarGroup.rotation.y));
          window.game.setSteering(Math.max(-1, Math.min(1, e * 3 / (Math.max(1, state.speed) * 0.32)))); window.game.setGas(state.speed < speed); this.step();
        }
        window.game.setGas(false); window.game.setSteering(0); return k;
      },
      pos() { const p = playerCarGroup.position; return [+p.x.toFixed(2), +p.z.toFixed(2), +playerCarGroup.rotation.y.toFixed(2)]; },
      shot() { renderer.render(scene, camera); },
      forceRoad(kind) { state.forceRoadEvent = kind; state.roadTurn = 1; },
      corridorOneWay() { return currentCorridor?.userData.oneWay || null; },
      ows: () => oneWayStatus(), ends: () => corridorWorldEnds(),
      props() { return { props: state.props.length, flying: state.flying.length, settled: state.flying.filter(f => f.settled).length }; },
    };
    // Run init on DOM ready`);
    await route.fulfill({ response, body });
  });
  await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
  await page.waitForFunction(() => window.T && window.game);
  const events = () => page.evaluate(() => window.events.splice(0).filter(e => ['violation', 'lane_changed'].includes(e.event)));
  const types = list => list.filter(e => e.event === 'violation').map(e => e.type);
  for (const [id, turn, mode] of [['ticket_18_8', 'right', 'with'], ['ticket_18_8', 'left', 'against'],
    ['ticket_14_8', 'left', 'with'], ['ticket_14_8', 'right', 'against']]) {
    await page.evaluate(id => { window.T.select(id); window.T.forceRoad('crosswalk'); window.T.approach(); window.game.proceedAfterAnswer(true, id); window.events.length = 0; }, id);
    const r = await page.evaluate(turn => {
      const T = window.T, c = T.state.resolution.intersection.centerZ, s = turn === 'right' ? -1 : 1, lane = turn === 'right' ? -1.8 : 1.8;
      T.follow([[-1.8, c - 5], [s * 4, c - 1.8], [s * 30, c + lane], [s * 40, c + lane]]);
      const z0 = T.pos()[1];
      T.follow([[1.8, z0 + 10], [1.8, z0 + 110]], 10); // the left lane for 100 m
      return { exited: !T.state.resolution, oneWay: T.corridorOneWay() };
    }, turn);
    const ev = await events();
    assert.ok(r.exited, `${id} ${turn}: exit taken`);
    assert.equal(r.oneWay, mode, `${id} ${turn}: one-way corridor`);
    if (mode === 'with') {
      assert.ok(!ev.some(e => e.event === 'lane_changed' && e.oncoming), `${id} ${turn}: no oncoming lane on a one-way road ${JSON.stringify(ev)}`);
      assert.ok(!types(ev).some(t => ['oncoming', 'one_way', 'wrong_maneuver'].includes(t)), `${id} ${turn}: ${types(ev)}`);
    } else {
      assert.ok(types(ev).includes('one_way') && !types(ev).includes('oncoming'), `${id} ${turn}: against the flow ${types(ev)}`);
      assert.equal(types(ev).filter(t => t === 'one_way').length, 1, 'one ongoing violation');
    }
  }
  const toEvent = kind => page.evaluate(kind => {
    const T = window.T; T.select('ticket_3_13'); T.forceRoad(kind); T.approach(); window.game.proceedAfterAnswer(true, 'ticket_3_13');
    const c = T.state.resolution.intersection.centerZ; T.step(600); T.follow([[-1.8, c + 30]], 6); window.events.length = 0;
    return T.state.roadEvent;
  }, kind);
  // Driving into the closed lane knocks the barrier apart: one violation.
  let ev = await toEvent('roadworks');
  let r = await page.evaluate(w => { const T = window.T; T.follow([[-1.8, w + 1.5]], 8); T.step(240); return T.props(); }, ev.workZ);
  assert.ok(r.flying >= 3 && r.settled === r.flying, `barrier parts fly and settle ${JSON.stringify(r)}`);
  assert.deepEqual(types(await events()), ['roadworks']);
  // The detour through the oncoming lane (4.2.2) is legal.
  ev = await toEvent('roadworks');
  r = await page.evaluate(w => { const T = window.T; T.follow([[-1.8, w - 30], [1.8, w - 22], [1.8, w + 20], [-1.8, w + 28], [-1.8, w + 40]], 8); return T.props(); }, ev.workZ);
  assert.equal(r.flying, 0, 'nothing knocked on the detour');
  assert.deepEqual(types(await events()), []);
  // The broken-down car is solid.
  ev = await toEvent('obstacle');
  const z = await page.evaluate(w => { window.T.follow([[-1.8, w + 5]], 6, 900); return window.T.pos()[1]; }, ev.obstZ);
  assert.ok(z < ev.obstZ - 2 && types(await events()).includes('collision'), 'no driving through the obstacle car');
  // A turn finishing along the far kerb still hands over the exit road.
  await page.evaluate(() => { window.T.select('ticket_18_8'); window.T.forceRoad('crosswalk'); window.T.approach(); window.game.proceedAfterAnswer(true, 'ticket_18_8'); });
  r = await page.evaluate(() => { const T = window.T, c = T.state.resolution.intersection.centerZ;
    T.follow([[-1.8, c - 7], [-2.5, c - 3], [-7, c + 3.0], [-14, c + 3.6], [-60, c + 3.7]], 5); return !T.state.resolution; });
  assert.ok(r, 'far-kerb exit taken');
  assert.deepEqual(errors, []);
  console.log('PASS: one-way exits, road works, obstacle, far-kerb exit');
  await browser.close();
})();
