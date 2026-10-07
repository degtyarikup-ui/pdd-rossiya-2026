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
    page.on('pageerror', error => errors.push(error.stack || error.message));
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0;
      Math.random = () => 0.95; // Include the full three-person groups.
      window.events = [];
      window.FlutterChannel = { postMessage: message => window.events.push(JSON.parse(message)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
      window.__engineTest = {
        state, routeSpec, get scene() { return scene; }, THREE, player: () => playerCarGroup, camera: () => camera,
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
      const t = window.__engineTest, s = t.state, T = t.THREE, res = [];
      t.allScenarios().forEach((sc, i) => {
        t.selectAll(i); s.paused = false; t.approach();
        const it = s.activeIntersection; if (!it || it.situation.unmarkedCrossings) return;
        t.scene.updateMatrixWorld(true);
        const zebras = [];
        // Check the painted stripes individually: one bounding box around
        // zebras on both arms also covers the unmarked middle of the junction.
        t.scene.traverse(o => {
          if (!o.userData.crosswalk) return;
          const positions = o.geometry.attributes.position, index = o.geometry.index;
          for (let i = 0; i < (index?.count ?? positions.count); i += 3) {
            const points = [0, 1, 2].map(j => new T.Vector3()
              .fromBufferAttribute(positions, index ? index.getX(i + j) : i + j).applyMatrix4(o.matrixWorld));
            zebras.push(new T.Box3().setFromPoints(points).expandByScalar(0.8));
          }
        });
        window.game.proceedAfterAnswer(true, it.situation.id);
        window.game.releaseTraffic(it.situation.id);
        const bad = new Set(), crossed = new Set();
        const peds = () => (s.resolution?.motions || it.actors || []).filter(a => (a.config || {}).type === 'pedestrian');
        for (let k = 0; k < 60 * 12; k++) {
          t.tick(1/60);
          if (k % 10) continue;
          for (const a of peds()) {
            const p = a.mesh.getWorldPosition(new T.Vector3());
            const surf = t.surfaceAt(p.x, p.z);
            if (surf[0] === 'road') crossed.add(a.config.id);
            // Asphalt under a raised pavement is not a carriageway.
            if (surf[0] === 'road' && !zebras.some(b => b.containsPoint(new T.Vector3(p.x, b.min.y, p.z)))) bad.add(a.config.id + '@' + p.x.toFixed(0) + ',' + (p.z - it.centerZ).toFixed(0));
          }
          if (!s.resolution) break;
        }
        for (const a of peds()) if (!crossed.has(a.config.id)) bad.add(a.config.id + ': never crossed');
        if (bad.size) res.push({ id: sc.id, side: (it.situation.actorsConfig||[]).filter(a=>a.type==='pedestrian').map(a=>a.side+':'+(a.position||'')), cw: it.situation.crosswalks, bad: [...bad].slice(0, 4) });
      });
      return res;
    });
    // Marked junctions: pedestrians cross on the painted arms, including 20.13.
    assert.deepEqual(out, [], 'pedestrians off the zebra: ' + JSON.stringify(out));
    assert.deepEqual(errors, []);
    console.log('PASS: junction pedestrians cross on zebras');
  } finally { await browser.close(); }
})();
