// Run with NODE_PATH pointing at a Playwright installation and a local HTTP server.
// Instrumentation is injected into the response only; no debug API ships in the app.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    // Deterministic randomness (avenue widths, traffic, the situation bag):
    // a failure repeats with the same TEST_SEED.
    await page.addInitScript(seed => {
      let s = seed * 2654435761 % 2147483647 || 1;
      if (seed) Math.random = () => (s = s * 16807 % 2147483647) / 2147483647;
      window.events = [];
      window.FlutterChannel = { postMessage: message => window.events.push(JSON.parse(message)) };
    }, Number(process.env.TEST_SEED ?? 2));
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
      window.__engineTest = {
        state, routeSpec, player: () => playerCarGroup, camera: () => camera,
        scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed && !isRegulatorSituation(s)),
        allScenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed),
        drawSituation: nextSituation,
        randomSequence(n) { situationBag = []; state.regulatorAt = Infinity; return Array.from({ length: n }, () => nextSituation().id); },
        updateActors, updateCamera,
        roadQueue(ids) { roadBag = ids.map(id => window.PDD_ROAD_SITUATIONS.find(r => r.id === id)).reverse(); },
        actorInView,
        createTrafficLight,
        maybeReverseWorld, corridorWorldEnds,
        playerOnRoad, playerFootprint, actorFootprint, footprintsOverlap, integrateDriving,
        audioSnapshot: () => gameAudio.snapshot(), updateAudio: (dt, elapsed) => gameAudio.update(dt, elapsed),
        surfaceAt(x, z) {
          scene.updateMatrixWorld(true);
          const ray = new THREE.Raycaster(new THREE.Vector3(x, 30, z), new THREE.Vector3(0, -1, 0));
          const surfaces = [];
          state.roadSegments.forEach(seg => seg.traverse(o => { if (o.userData.surface) surfaces.push(o); }));
          return ray.intersectObjects(surfaces, false).filter(hit =>
            hit.object.userData.surface && (hit.object.material.clippingPlanes || []).every(p => p.distanceToPoint(hit.point) >= -0.001))
            .map(hit => hit.object.userData.surface);
        },
        drive(maxFrames = 2400) {
          const r = state.resolution;
          if (!r) return;
          this.tick(20);
          let progress = 0;
          for (let frame = 0; frame < maxFrames && state.resolution; frame++) {
            let nearest = progress, best = Infinity;
            for (let t = progress; t <= Math.min(1, progress + 0.12); t += 0.005) {
              const d = r.path.getPointAt(t).distanceTo(playerCarGroup.position);
              if (d < best) { best = d; nearest = t; }
            }
            progress = nearest;
            const target = progress > 0.94 ? r.path.getPointAt(1).addScaledVector(r.path.getTangentAt(1), 20) :
              r.path.getPointAt(Math.min(1, progress + 2.5 / r.length));
            const heading = Math.atan2(target.x - playerCarGroup.position.x, target.z - playerCarGroup.position.z);
            const error = Math.atan2(Math.sin(heading - playerCarGroup.rotation.y), Math.cos(heading - playerCarGroup.rotation.y));
            window.game.setSteering(Math.max(-1, Math.min(1, error * 3 / (Math.max(1, state.speed) * 0.32))));
            window.game.setGas(state.speed < 4);
            this.tick(1 / 60);
            if (r.recovery) return { failure: 'impact', position: playerCarGroup.position.toArray(), faults: [...r.faults] };
          }
          window.game.setGas(false); window.game.setSteering(0);
          return { complete: !state.resolution };
        },
        tick(seconds) {
          for (let i = 0; i < Math.ceil(seconds * 60); i++) {
            if (reveal) { updateReveal(1/60); continue; }
            if (!state.paused) {
              updateAttract(1/60);
              updateActors(1/60);
              if (state.resolution) updateResolution(1/60); else updatePlayerMovement(1/60);
              updateRoadEvent(1/60);
            }
            updateBlinkers(1/60); gameAudio.update(1/60, performance.now() / 1000); updateCamera(1/60); checkAndSpawnNext();
          }
          if (seconds >= 0.1) renderer.render(scene, camera);
        },
        select(index) {
          resetGame();
          state.roadSegments.forEach(disposeSegment);
          state.roadSegments = []; state.intersections = [];
          situationIndex = index; situationBag = [this.scenarios()[index]]; buildInitialTrack();
        },
        selectAll(index) {
          resetGame();
          state.roadSegments.forEach(disposeSegment);
          state.roadSegments = []; state.intersections = [];
          situationIndex = index; situationBag = [this.allScenarios()[index]]; buildInitialTrack();
        },
        approach() {
          if (!state.intersections.length) {
            playerCarGroup.position.z = nextSegmentZ - 100;
            checkAndSpawnNext();
          }
          playerCarGroup.position.z = state.intersections[0].stopZ;
          updatePlayerMovement(0);
        }
      };
      // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'), null, { timeout: 90000 });

    // «Простое управление»: an arrow is a whole lane change or junction exit,
    // driven by the engine along a planned curve — never free steering.
    const result = await page.evaluate(() => {
      const t = window.__engineTest, s = t.state;
      const events = () => window.events.filter(e => e.event === 'violation').map(e => e.type);
      window.game.setSimpleSteering(true);
      // 1. Lane change on the approach straight: exactly centred, straight.
      t.select(0); s.paused = false;
      t.player().position.set(-1.8, 0, s.intersections[0].stopZ - 110); t.player().rotation.y = 0;
      window.game.setGas(true); t.tick(1);
      window.game.changeLane('left'); t.tick(1.6);
      const leftLane = { x: t.player().position.x, yaw: t.player().rotation.y };
      window.game.changeLane('left'); t.tick(0.4); // no third lane: ignored
      const noThird = { x: t.player().position.x };
      window.game.setSteering(1); t.tick(0.6); // holding: no free steering
      const held = { x: t.player().position.x, yaw: t.player().rotation.y };
      window.game.changeLane('right'); t.tick(1.6);
      const back = { x: t.player().position.x, yaw: t.player().rotation.y, atSituation: s.isAtSituation };
      window.game.setGas(false); window.game.setSteering(0);
      // 2. Every reviewed junction: choose the correct exit with the arrow.
      const junctions = [];
      t.scenarios().forEach((sc, i) => {
        t.select(i); s.paused = false; t.approach();
        const it = s.activeIntersection, maneuver = t.routeSpec(it.situation).maneuver;
        if (maneuver === 'uturn') return;
        const before = events().length;
        window.game.proceedAfterAnswer(true, it.situation.id);
        window.game.releaseTraffic(it.situation.id);
        t.tick(0.2);
        if (maneuver === 'left' || maneuver === 'right') window.game.changeLane(maneuver);
        let frames = 0;
        for (; frames < 60 * 90 && s.resolution; frames++) {
          const r = s.resolution;
          // A careful driver: gives way first, then drives the chosen exit.
          const clear = r.yielding.every(a => a.cleared || a.done || a.held) && r.elapsed > 3;
          window.game.setGas(clear && s.speed < 7);
          t.tick(1 / 60);
          if (s.resolution?.recovery) break;
        }
        if (!s.resolution) { window.game.setGas(true); t.tick(3); }
        window.game.setGas(false);
        const hit = s.resolution?.motions?.filter(a => a.crashed || a.fall).map(a => [a.config.id, a.config.type, !!s.resolution.yielding.includes(a), a.waitsForPlayer, +a.mesh.position.x.toFixed(1), +(a.mesh.position.z - it.centerZ).toFixed(1)]);
        const faults = events().slice(before).filter(f => f !== 'speeding');
        junctions.push({ id: it.situation.id, geometry: it.situation.geometry, maneuver, hit,
          // Lane centres of the road the exit leads onto: an avenue arm
          // (avenueExits) keeps its two lanes, W/8 and 3W/8 from the centre.
          lanes: (w => w > 8.5 ? [w / 8, w * 3 / 8] : [1.8])(it.exitWidths?.[maneuver] || 8.4),
          done: !s.resolution, faults, yaw: +t.player().rotation.y.toFixed(3), x: +t.player().position.x.toFixed(2) });
      });
      // 3. T-junction: the car waits at the turn with the gas held and moves
      // off the moment an arrow is pressed (no second press of the gas).
      const tees = [];
      t.scenarios().forEach((sc, i) => {
        t.select(i); s.paused = false; t.approach();
        const it = s.activeIntersection;
        if (it.previews.straight) return;
        window.game.proceedAfterAnswer(true, it.situation.id);
        window.game.releaseTraffic(it.situation.id);
        window.game.setGas(true); t.tick(4);
        const waited = s.speed === 0 && !!s.resolution;
        window.game.changeLane('right'); t.tick(6);
        window.game.setGas(false);
        tees.push({ id: sc.id, waited, turned: !s.resolution });
      });
      // 4. Reverse retraces the way the car came, never straight across.
      const reverse = [];
      t.select(0); s.paused = false;
      t.player().position.set(-1.8, 0, s.intersections[0].stopZ - 110); t.player().rotation.y = 0;
      window.game.setGas(true); t.tick(1); window.game.changeLane('left'); t.tick(0.5);
      window.game.setGas(false); window.game.setBrake(true); t.tick(5); window.game.setBrake(false); t.tick(0.5);
      const faultsBefore = window.events.length;
      reverse.push({ kind: 'lane', x: +t.player().position.x.toFixed(2), yaw: +t.player().rotation.y.toFixed(3) });
      const turnIndex = t.scenarios().findIndex(sc => t.routeSpec(sc).maneuver === 'right' && !sc.geometry);
      t.select(turnIndex); s.paused = false; t.approach();
      const it = s.activeIntersection, stopX = t.player().position.x, stopZ = t.player().position.z;
      window.game.proceedAfterAnswer(true, it.situation.id); window.game.releaseTraffic(it.situation.id);
      t.tick(0.2); window.game.changeLane('right');
      window.game.setGas(true); t.tick(1.6); window.game.setGas(false);
      const midYaw = t.player().rotation.y;
      t.tick(0.6); window.game.setBrake(true); t.tick(8); window.game.setBrake(false); t.tick(0.3);
      reverse.push({ kind: 'turn', midYaw: +midYaw.toFixed(2), x: +(t.player().position.x - stopX).toFixed(2), z: +(t.player().position.z - stopZ).toFixed(2), yaw: +t.player().rotation.y.toFixed(3) });
      const reverseFaults = window.events.slice(faultsBefore).filter(e => e.event === 'violation' && e.type === 'offroad').length;
      // 5. Ticket 26·13 (13.7): stop at the median stop line, wait for its
      // light, then finish the left turn; an arrow pressed while standing
      // there still counts.
      const med = t.allScenarios().findIndex(sc => sc.id === 'ticket_26_13');
      t.selectAll(med); s.paused = false; t.approach();
      const mit = s.activeIntersection, n26 = window.events.length;
      window.game.proceedAfterAnswer(true, mit.situation.id);
      let medianHeld = 0, green = false;
      window.game.setGas(true);
      for (let f = 0; f < 60 * 30 && s.resolution; f++) {
        if (f === 90) window.game.changeLane('left');
        t.tick(1 / 60);
        if (s.resolution?.medianWait && s.speed === 0) medianHeld++;
        if (s.resolution?.medianGreen) green = true;
      }
      window.game.setGas(false);
      const median = { held: medianHeld, green, done: !s.resolution, v: window.events.slice(n26).filter(e => e.event === 'violation').map(e => e.type) };
      // 6. The U-turn button: offered at a U-turn-capable junction, pressed
      // again — straight on; the left arrow is only ever a left turn.
      const uIndex = t.scenarios().findIndex(sc => t.routeSpec(sc).maneuver === 'uturn');
      const uturnPresses = [];
      if (uIndex >= 0) {
        t.select(uIndex); s.paused = false; t.approach();
        const uit = s.activeIntersection, um = window.events.length;
        window.game.proceedAfterAnswer(true, uit.situation.id);
        t.tick(0.2);
        const offered = window.events.slice(um).filter(e => e.event === 'exit_choice').some(e => e.uturn === true);
        uturnPresses.push(offered);
        window.game.chooseUturn(); uturnPresses.push(s.resolution?.simpleChoice);
        window.game.chooseUturn(); uturnPresses.push(s.resolution?.simpleChoice);
        window.game.changeLane('left'); uturnPresses.push(s.resolution?.simpleChoice);
        window.game.changeLane('left'); uturnPresses.push(s.resolution?.simpleChoice);
      }
      return { leftLane, noThird, held, back, junctions, tees, reverse, reverseFaults, median, uturnPresses };
    });
    const near = (a, b, eps) => Math.abs(a - b) < eps;
    assert(near(result.leftLane.x, 1.8, 0.05) && near(result.leftLane.yaw, 0, 0.01), 'Lane change ends centred: ' + JSON.stringify(result.leftLane));
    assert(near(result.noThird.x, 1.8, 0.05), 'No lane beyond the road');
    assert(near(result.held.x, 1.8, 0.05) && near(result.held.yaw, 0, 0.01), 'Holding does not steer');
    assert(near(result.back.x, -1.8, 0.05) && near(result.back.yaw, 0, 0.01), 'Lane change back ends centred');
    // Collisions with crossing traffic are the driver's braking, not the path.
    const bad = result.junctions.filter(j => (!j.done && !j.faults.includes('collision')) || j.faults.some(f => ['offroad', 'wrong_maneuver', 'oncoming'].includes(f)));
    console.log(JSON.stringify({ junctions: result.junctions.length, bad, ends: result.junctions.filter(j => j.done).map(j => [j.id, j.geometry || "", j.maneuver, j.x, j.yaw]) }));
    assert.equal(bad.length, 0, 'Every junction drives cleanly with arrows');
    const skew = result.junctions.filter(j => j.done && (j.lanes.every(c => Math.abs(Math.abs(j.x) - c) > 0.1) || Math.abs(Math.sin(j.yaw)) > 0.02));
    assert.deepEqual(skew, [], 'After a junction the car is centred and straight');
    assert(result.tees.length && result.tees.every(x => x.waited && x.turned), 'T-junction: wait, then turn on the arrow: ' + JSON.stringify(result.tees));
    console.log(JSON.stringify(result.reverse), result.reverseFaults);
    const [laneBack, turnBack] = result.reverse;
    // Backed out through the lane change: on the starting lane, straight.
    assert(near(laneBack.x, -1.8, 0.1) && near(laneBack.yaw, 0, 0.02), 'Reverse retraces the lane change: ' + JSON.stringify(laneBack));
    assert(Math.abs(turnBack.midYaw) > 0.2 && near(turnBack.yaw, 0, 0.03) && near(turnBack.x, 0, 0.15), 'Reverse out of a turn: ' + JSON.stringify(turnBack));
    assert.equal(result.reverseFaults, 0, 'no kerb while reversing');
    assert(result.median.held > 60 && result.median.green && result.median.done && !result.median.v.includes('wrong_maneuver'),
      '26·13: wait at the median line for green, then turn left: ' + JSON.stringify(result.median));
    assert.deepEqual(result.uturnPresses, [true, 'uturn', 'straight', 'left', 'straight'], 'U-turn button and arrows: ' + JSON.stringify(result.uturnPresses));
    assert.deepEqual(errors, []);
    console.log('PASS: simple steering — centred lane changes, no free steering, clean junctions');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
