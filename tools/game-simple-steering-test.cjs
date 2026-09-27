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
    await page.addInitScript(() => {
      window.events = [];
      window.FlutterChannel = { postMessage: message => window.events.push(JSON.parse(message)) };
    });
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
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'));

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
      return { leftLane, noThird, held, back, junctions, tees };
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
    const skew = result.junctions.filter(j => j.done && (Math.abs(Math.abs(j.x) - 1.8) > 0.1 || Math.abs(Math.sin(j.yaw)) > 0.02));
    assert.deepEqual(skew, [], 'After a junction the car is centred and straight');
    assert(result.tees.length && result.tees.every(x => x.waited && x.turned), 'T-junction: wait, then turn on the arrow: ' + JSON.stringify(result.tees));
    assert.deepEqual(errors, []);
    console.log('PASS: simple steering — centred lane changes, no free steering, clean junctions');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
