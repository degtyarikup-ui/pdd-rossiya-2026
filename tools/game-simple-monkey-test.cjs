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
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'), null, { timeout: 90000 });
    const out = await page.evaluate(() => {
      const t = window.__engineTest, s = t.state, res = [];
      window.game.setSimpleSteering(true);
      let seed = 31337; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
      for (let round = 0; round < 2; round++) t.scenarios().forEach((sc, i) => {
        t.select(i); s.paused = false;
        // Approach from further back, pressing arrows on the way.
        const it0 = s.intersections[0];
        t.player().position.set(-1.8, 0, it0.stopZ - 40); t.player().rotation.y = 0;
        const log = [];
        const before = window.events.length;
        let answered = false, frames = 0;
        for (; frames < 60 * 60; frames++) {
          if (s.isAtSituation && !answered && s.activeIntersection && !s.resolution) {
            answered = true;
            window.game.proceedAfterAnswer(true, s.activeIntersection.situation.id);
            window.game.releaseTraffic(s.activeIntersection.situation.id);
          }
          if (rnd() < 0.03) { const u = rnd(), d = u < 0.42 ? 'left' : u < 0.84 ? 'right' : 'uturn'; if (d === 'uturn') window.game.chooseUturn(); else window.game.changeLane(d); log.push(d[0] + (s.resolution ? 'J' : 'R') + Math.round(t.player().position.z - it0.centerZ)); }
          const r = s.resolution;
          const clear = !r || (r.yielding.every(a => a.cleared || a.done || a.held) && r.elapsed > 3);
          window.game.setGas(clear && s.speed < 9);
          const n0 = window.events.length;
          t.tick(1 / 60);
          window.events.slice(n0).filter(e => e.event === 'violation' && e.type === 'offroad').forEach(() => log.push('OFFROAD@' + t.player().position.x.toFixed(1) + ',' + (t.player().position.z - it0.centerZ).toFixed(1) + ' yaw=' + t.player().rotation.y.toFixed(2) + ' ch=' + s.resolution?.simpleChoice + ' path=' + !!s.autoPath + ' open=' + s.resolution?.simpleOpen));
          if (answered && !s.resolution) break;
          if (s.resolution?.recovery) break;
        }
        window.game.setGas(false);
        const faults = window.events.slice(before).filter(e => e.event === 'violation').map(e => e.type);
        const stuck = answered && s.resolution && !s.resolution.recovery;
        if (faults.includes('offroad') || stuck || !answered)
          res.push({ id: sc.id, g: sc.geometry, faults, stuck, answered, log: log.slice(-14).join(' '), pos: [+t.player().position.x.toFixed(1), +(t.player().position.z - it0.centerZ).toFixed(1)], choice: s.resolution?.simpleChoice });
      });
      return res;
    });
    // Random arrow presses at any moment (approach, stop line, mid-turn,
    // changing one's mind) never put the car on the kerb or leave it stuck.
    assert.deepEqual(out, [], JSON.stringify(out.slice(0, 5)));
    assert.deepEqual(errors, []);
    console.log('PASS: simple steering survives random arrow presses at every junction');
  } finally { await browser.close(); }
})();
