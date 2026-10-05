// One-way exits, road works (knockable props, legal detour), solid obstacle
// car and junction exits hugging the far kerb (formerly a dead end).
// Run with the same GAME_URL / NODE_PATH setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
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
      state, player: () => playerCarGroup,
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
      shotBay(z) { camera.position.set(0, 80, z); camera.lookAt(0, 0, z);
        camera.left = -18; camera.right = 18; camera.top = 39; camera.bottom = -39;
        camera.updateProjectionMatrix(); renderer.render(scene, camera); },
      forceRoad(kind) { state.forceRoadEvent = kind; state.roadTurn = 1; },
      corridorOneWay() { return currentCorridor?.userData.oneWay || null; },
      ows: () => oneWayStatus(), ends: () => corridorWorldEnds(),
      // A car driving the closed lane of the current road event.
      laneCar(z0, z1) {
        const ev = state.roadEvent, V = (x, z) => new THREE.Vector3(x, 0, z);
        const car = addRoadActor(ev.group, { id: 'test_lane_car', type: 'special', name: 'Спецмашина', color: '#0574F8', beacon: 'blue' },
          V(-1.8, z0), 0, [V(-1.8, z0), V(-1.8, z1)], 10);
        car.waitsForPlayer = false; car.active = true; ev.actors.push(car);
        playerCarGroup.position.set(-1.8, 0, z0 - 40); playerCarGroup.rotation.y = 0; state.speed = 0;
        let maxX = -9, frames = 0;
        for (; frames < 1500 && !car.done && car.distance < car.length - 1; frames++) { this.step(); maxX = Math.max(maxX, car.mesh.position.x); }
        const raker = ev.actors.find(a => a.config.id === 'road_worker');
        return { maxX: +maxX.toFixed(2), endX: +car.mesh.position.x.toFixed(2), done: car.distance >= car.length - 1, workerDown: !!raker?.fall, crashed: !!car.crashed };
      },
      nextZ: () => nextSegmentZ, ids: () => SITUATIONS.filter(s => window.PDD_SCENARIO_ROUTES[s.id]?.reviewed).map(s => s.id), halfAt: z => asphaltHalfAt(z), junctions: () => [...state.intersections.map(i => i.centerZ), state.sideJunction?.junctionZ].filter(v => v != null),
      roadAt: (x, z) => roadSupports(new THREE.Vector3(x, 0, z)),
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
  const ids = await page.evaluate(() => window.T.ids());
  const bad = [], seen = [];
  for (const id of ids.slice(0, 30)) {
    for (const kind of ['obstacle', 'roadworks']) {
      const r = await page.evaluate(([id, kind]) => {
        const T = window.T; T.select(id); T.forceRoad(kind); T.approach();
        window.game.proceedAfterAnswer(true, id);
        const c = T.state.resolution.intersection.centerZ; T.step(600); T.follow([[-1.8, c + 30]], 6);
        const ev = T.state.roadEvent;
        if (!ev || ev.kind !== kind) return { id, kind, got: ev?.kind };
        const z = kind === 'obstacle' ? ev.obstZ : ev.workZ, span = kind === 'obstacle' ? [-17, 5] : [-20, 22];
        T.follow([[1.8, z - 25], [1.8, z + 30]], 6, 2500); T.step(60);
        const hs = []; for (let d = span[0]; d <= span[1]; d += 2) hs.push(T.halfAt(z + d));
        const pz = T.pos()[1]; const prof = []; for (let d = -60; d <= 150; d += 5) prof.push(T.halfAt(pz + d)); return { sanity: [Math.round(T.nextZ() - z)], id, kind, z: Math.round(z), maxHalf: Math.max(...hs), minHalf: Math.min(...hs), junctions: T.junctions().map(j => Math.round(j - z)) };
      }, [id, kind]);
      seen.push(r);
      if (r.maxHalf > r.minHalf + 1.5 || r.junctions?.some(j => j > -30 && j < 15)) bad.push(r);
    }
  }
  // A lane blockage (broken-down car with its triangle, road works) never
  // stands where another road joins, nor near the next junction.
  assert.deepEqual(bad, [], JSON.stringify(bad.slice(0, 5)));
  assert.ok(seen.every(r => !r.got), 'the event is placed, not replaced: ' + JSON.stringify(seen.filter(r => r.got)));
  // Other roadside geometry also needs a junction-free span. The bus bay's
  // taper must reject pavement even though it lies inside its bounding box.
  const roadside = [];
  for (const id of ids.slice(0, 12)) for (const kind of ['busstop', 'courtyard', 'crosswalk']) {
    roadside.push(await page.evaluate(([id, kind]) => {
      const T = window.T; T.select(id); T.forceRoad(kind); T.approach();
      window.game.proceedAfterAnswer(true, id);
      const c = T.state.resolution.intersection.centerZ;
      T.step(600); T.follow([[-1.8, c + 30]], 6);
      const ev = T.state.roadEvent;
      if (ev?.kind !== kind) return { id, kind, fallback: ev?.kind };
      const z = ev.bayZ ?? ev.yardZ ?? ev.crosswalkZ;
      const span = kind === 'busstop' ? [-30, 45] : kind === 'courtyard' ? [-12, 18] : [-12, 12];
      const halves = [];
      for (let d = span[0]; d <= span[1]; d += 2) halves.push(T.halfAt(z + d));
      return { id, kind, z, maxHalf: Math.max(...halves), paved: T.roadAt(-1.8, z) && T.roadAt(-1.8, z + span[1]),
        tapered: kind !== 'busstop' || T.roadAt(-5.5, z) &&
          !T.roadAt(-6.7, z - 14) && !T.roadAt(-6.7, z + 14) && !T.roadAt(-7.1, z) };
    }, [id, kind]));
  }
  assert.ok(roadside.every(r => r.fallback === 'cyclist' || r.maxHalf < 9 && r.paved && r.tapered),
    'Roadside event touches a junction or allows driving on a bay taper: ' + JSON.stringify(roadside.filter(r => r.maxHalf >= 9 || !r.paved || !r.tapered || r.fallback && r.fallback !== 'cyclist')));
  if (process.env.GAME_SHOTS) {
    const visible = await page.evaluate(id => {
      const T = window.T; T.select(id); T.forceRoad('busstop'); T.approach();
      window.game.proceedAfterAnswer(true, id);
      const c = T.state.resolution.intersection.centerZ;
      T.step(600); T.follow([[-1.8, c + 30]], 6);
      const ev = T.state.roadEvent;
      if (ev?.kind !== 'busstop') return false;
      T.player().position.set(-1.8, 0, ev.bayZ - 38); T.player().rotation.y = 0;
      T.shotBay(ev.bayZ);
      return true;
    }, ids[0]);
    if (visible) {
      fs.mkdirSync(process.env.GAME_SHOTS, { recursive: true });
      await page.screenshot({ path: path.join(process.env.GAME_SHOTS, 'bus-bay.png') });
    }
  }
  console.log('PASS: broken-down cars and road works stand clear of junctions (' + seen.length + ' placements)');
  await browser.close();
})();
