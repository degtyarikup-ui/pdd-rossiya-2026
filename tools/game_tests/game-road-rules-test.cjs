// Road questions with a rule to drive by (railway crossings, a junction
// ahead, a detour): driving as the ticket says costs nothing, the fault the
// ticket warns about is flagged. Run with the same GAME_URL / NODE_PATH /
// CHROME_PATH setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0;
      window.events = [];
      window.FlutterChannel = { postMessage: m => window.events.push(JSON.parse(m)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
        window.__roadRules = {
          state, player: () => playerCarGroup,
          // The question's stretch on a fresh straight, the player stopped for it.
          show(id) {
            resetGame(); state.attract = false;
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.actors = []; state.intersections = [];
            state.activeIntersection = null; state.occluders = []; state.ambient = [];
            state.exitRoad = currentCorridor = null;
            const road = buildStraightSegment(-45, 200, true); state.roadSegments.push(road);
            state.exitRoad = currentCorridor = road; nextSegmentZ = 155;
            const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
            const s = window.PDD_ROAD_SITUATIONS.find(s => s.id === id);
            const ev = state.roadEvent = buildQuestionEvent(group, -45, s);
            playerCarGroup.position.set(-1.8, 0, ev.stopZ); playerCarGroup.rotation.y = 0;
            startRoadQuestion();
            state.paused = false;
            return ev;
          },
          answer() { startRoadManual(); },
          tick() {
            updateActors(1 / 60); updatePlayerMovement(1 / 60); updateRoadEvent(1 / 60); updateCamera(1 / 60);
          },
          // Keeps to lane x at up to speed m/s: a plain steering controller.
          drive(x, speed, look = 9) {
            const p = playerCarGroup.position, yaw = playerCarGroup.rotation.y;
            const target = Math.atan2(x - p.x, look);
            window.game.setSteering(Math.max(-1, Math.min(1, (target - yaw) * 3)));
            window.game.setGas(speed > 0 && state.speed < speed);
            window.game.setBrake(speed <= 0 && state.speed > 0.2);
            this.tick();
          }
        };
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.__roadRules);
    await page.evaluate(() => { window.game.setPaused(true); window.game.setSimpleSteering(false); });

    // Runs one scripted drive: plan(t, ev) -> [laneX, speed] per frame, until
    // the question's stretch is over. Returns the violations it cost.
    const run = (id, plan) => page.evaluate(([id, planSource]) => {
      const t = window.__roadRules, s = t.state;
      const ev = t.show(id);
      const mark = window.events.length;
      t.answer();
      const plan = eval(planSource)();
      let frames = 0;
      for (; frames < 60 * 90 && s.roadEvent === ev; frames++) {
        const [x, speed, look] = plan(t, ev);
        t.drive(x, speed, look);
      }
      window.game.setGas(false); window.game.setSteering(0);
      const done = s.roadEvent !== ev;
      return { done, frames, faults: window.events.slice(mark).filter(e => e.event === 'violation').map(e => e.type) };
    }, [id, plan.toString()]);

    const results = {};
    const own = -1.8, oncoming = 1.8;

    // 2.16: wait behind the truck at the closed barrier, go after it once the
    // booms are up — clean; going round it through the oncoming lane is not.
    results.waitAtBarrier = await run('road_2_16', () => (t, ev) =>
      [-1.8, ev.rail.open && t.player().position.z < ev.actors[0].mesh.position.z - 10 ? 9 : 0]);
    assert.ok(results.waitAtBarrier.done && !results.waitAtBarrier.faults.length, JSON.stringify(results.waitAtBarrier));
    // Pulling out sharply from right behind it, as a player going round would.
    results.roundTheTruck = await run('road_2_16', () => (t, ev) => t.player().position.z < ev.crossingZ + 20 ?
      [1.8, t.player().position.x < 0.3 ? 2.5 : 7, 2.5] : [-1.8, 7]);
    assert.equal(results.roundTheTruck.faults[0], 'railway', JSON.stringify(results.roundTheTruck));

    // 10.11: overtaking the tractor is fine while it is over 100 m before the
    // crossing, not once inside that zone.
    results.overtakeEarly = await run('road_10_11', () => (t, ev) => {
      const tractor = ev.actors[0].mesh.position.z, z = t.player().position.z;
      return [z < tractor + 9 && z < ev.crossingZ - 125 ? 1.8 : -1.8, 14];
    });
    assert.ok(results.overtakeEarly.done && !results.overtakeEarly.faults.length, JSON.stringify(results.overtakeEarly));
    results.overtakeLate = await run('road_10_11', () => (t, ev) => {
      const lead = ev.actors[0].mesh.position.z, z = t.player().position.z;
      const pullOut = z > ev.crossingZ - 95 && z < ev.crossingZ - 60;
      return [pullOut ? 1.8 : -1.8, pullOut ? 16 : Math.min(14, Math.max(0, (lead - z - 11) * 2))];
    });
    assert.equal(results.overtakeLate.faults[0], 'overtaking', JSON.stringify(results.overtakeLate));

    // 17.11 and 21.11: overtaking starts only past the crossing.
    for (const id of ['road_17_11', 'road_21_11']) {
      const after = await run(id, () => (t, ev) => {
        const lead = ev.actors[0].mesh.position.z, z = t.player().position.z;
        const pastCrossing = z > ev.crossingZ + 6;
        return [pastCrossing && z < lead + 9 ? 1.8 : -1.8, pastCrossing ? 14 : Math.min(9, Math.max(0, (lead - z - 11) * 2))];
      });
      assert.ok(after.done && !after.faults.length, id + ' after the crossing: ' + JSON.stringify(after));
      const before = await run(id, () => (t, ev) => t.player().position.z < ev.crossingZ ?
        [1.8, t.player().position.x < 0.3 ? 2.5 : 8, 2.5] : [-1.8, 8]);
      assert.equal(before.faults[0], 'overtaking', id + ' before the crossing: ' + JSON.stringify(before));
      results[id] = { after, before };
    }

    // 12.11: the cart may be overtaken before the junction, not on it.
    results.cartEarly = await run('road_12_11', () => (t, ev) => {
      const cart = ev.actors[0].mesh.position.z, z = t.player().position.z;
      return [z < cart + 9 && z < ev.junctionZ - 60 ? 1.8 : -1.8, 14];
    });
    assert.ok(results.cartEarly.done && !results.cartEarly.faults.length, JSON.stringify(results.cartEarly));
    results.onJunction = await run('road_12_11', () => (t, ev) => {
      const lead = ev.actors[0].mesh.position.z, z = t.player().position.z;
      const pullOut = Math.abs(z - ev.junctionZ) < 20;
      return [pullOut ? 1.8 : -1.8, pullOut ? 12 : Math.min(14, Math.max(0, (lead - z - 11) * 2)), pullOut ? 4 : 9];
    });
    assert.equal(results.onJunction.faults[0], 'overtaking', JSON.stringify(results.onJunction));

    // 35.5: round the barrier on the left over the solid line (4.2.2) is
    // clean; driving on into it is a roadworks fault.
    results.detourLeft = await run('road_35_5', () => (t, ev) => {
      const z = t.player().position.z;
      return [z > ev.obstZ - 22 && z < ev.obstZ + 7 ? 1.8 : -1.8, 9];
    });
    assert.ok(results.detourLeft.done && !results.detourLeft.faults.length, JSON.stringify(results.detourLeft));
    results.intoBarrier = await run('road_35_5', () => () => [-1.8, 9]);
    assert.equal(results.intoBarrier.faults[0], 'roadworks', JSON.stringify(results.intoBarrier));

    assert.deepEqual(errors, []);
    console.log(JSON.stringify(results));
    console.log('PASS: railway crossings, a junction ahead and a detour follow their tickets');
  } finally { await browser.close(); }
})();
