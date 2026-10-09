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
        state, routeSpec, THREE, get camera3() { return camera; }, updateCameraNow: dt => updateCamera(dt), player: () => playerCarGroup, camera: () => camera,
        scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed && !isRegulatorSituation(s)),
        allScenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed),
        drawSituation: nextSituation,
        drainScenery() { while (processSceneryJobs(1000).pending) {} },
        randomSequence(n) { situationBag = []; state.regulatorAt = Infinity; return Array.from({ length: n }, () => nextSituation().id); },
        updateActors, updateCamera,
        roadQueue(ids) { roadBag = ids.map(id => window.PDD_ROAD_SITUATIONS.find(r => r.id === id)).reverse(); },
        actorInView,
        createTrafficLight,
        maybeReverseWorld, corridorWorldEnds,
        playerOnRoad, playerFootprint, actorFootprint, footprintsOverlap, integrateDriving,
        roadSupports, refreshRoadBounds, extendQuestionCorridor, clearRoadside, buildStraightSegment,
        setCorridor(road, next) { currentCorridor = road; state.exitRoad = road; nextSegmentZ = next; },
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

    // Bugs found by the soak test (tools/game-soak-test.cjs), each pinned.
    const result = await page.evaluate(() => {
      const t = window.__engineTest, s = t.state, T = t.THREE, out = {};
      const faults = from => window.events.slice(from).filter(e => e.event === 'violation').map(e => e.type);

      // 1. An answer that arrives while the engine is paused is applied on
      // resume (it used to be dropped: the car waited at the question for
      // good).
      t.select(0); s.paused = false; t.approach();
      let it = s.activeIntersection;
      window.game.setPaused(true);
      window.game.proceedAfterAnswer(true, it.situation.id);
      window.game.setPaused(false);
      t.tick(0.5);
      out.answerWhilePaused = !!s.resolution;

      // 2. A pause half-way through a turn keeps the turn (it used to go
      // straight on after the pause: a wrong manoeuvre).
      window.game.setSimpleSteering(true);
      const i22 = t.allScenarios().findIndex(sc => sc.id === 'ticket_22_13');
      t.selectAll(i22); s.paused = false; t.approach();
      it = s.activeIntersection;
      let mark = window.events.length;
      window.game.proceedAfterAnswer(true, it.situation.id); window.game.releaseTraffic(it.situation.id);
      t.tick(0.3); window.game.changeLane('left');
      window.game.setGas(true); t.tick(2.2);
      window.game.setPaused(true); t.tick(2); window.game.setPaused(false); window.game.setGas(true);
      for (let f = 0; f < 60 * 20 && s.resolution; f++) t.tick(1 / 60);
      window.game.setGas(false);
      out.pauseMidTurn = { done: !s.resolution, faults: faults(mark) };

      // 3. Simple steering never takes a car left on the centre line across
      // into the oncoming lane; a car overtaking in that lane stays there.
      t.select(0); s.paused = false;
      const p = t.player().position, z0 = s.intersections[0].stopZ - 110;
      p.set(0.3, 0, z0); t.player().rotation.y = 0;
      window.game.setGas(true); t.tick(3); window.game.setGas(false);
      out.fromCentreLine = +p.x.toFixed(2);
      p.set(1.8, 0, z0); t.player().rotation.y = 0; s.laneChangeX = null; s.autoPath = null;
      window.game.setGas(true); t.tick(2); window.game.setGas(false);
      out.overtaking = +p.x.toFixed(2);

      // 4. A building between the camera and the car is faded, wherever the
      // car is in the frame (the camera is orthographic).
      t.select(0); s.paused = false;
      t.drainScenery();
      t.tick(0.5);
      const building = s.occluders.find(b => b.parent);
      const box = new T.Box3().setFromObject(building), c = box.getCenter(new T.Vector3());
      const d = t.camera().getWorldDirection(new T.Vector3());
      const behind = c.clone().addScaledVector(d, c.y / -d.y);
      p.set(behind.x, 0, behind.z);
      t.updateCameraNow(1 / 60);
      let faded = false;
      building.traverse(part => { if (part.material && part.material.transparent && part.material.opacity < 0.5) faded = true; });
      out.occluderFaded = faded;

      // 5. Clearing the roadside for a bus stop takes houses away, never a
      // piece of the road: a stretch added for a long question used to go
      // whole, leaving no asphalt ahead (the car stood there for good).
      t.select(0); s.paused = false;
      const road = t.buildStraightSegment(400, 200, true);
      s.roadSegments.push(road);
      t.setCorridor(road, 600);
      t.extendQuestionCorridor(680);
      t.clearRoadside(640);
      t.refreshRoadBounds();
      out.extensionKept = [610, 640, 670].every(z => t.roadSupports(new T.Vector3(-1.8, 0, z)));

      // 6. A kerbed island of a street cut off after a turn is not drawn
      // beyond the cut, and is not felt there either.
      const island = new T.Mesh(new T.PlaneGeometry(1, 1), new T.MeshBasicMaterial());
      island.userData.noRoad = () => true;
      island.material.clippingPlanes = [new T.Plane(new T.Vector3(0, 0, -1), 500)];
      road.add(island);
      t.refreshRoadBounds();
      out.islandCut = { drawn: t.roadSupports(new T.Vector3(-1.8, 0, 450)), cutOff: t.roadSupports(new T.Vector3(-1.8, 0, 550)) };
      road.remove(island);

      // 7. A U-turn in simple steering is one round loop driven at a
      // turning speed: it used to kink (80° within a metre) at up to
      // 58 km/h, its button came back half-way round, and a press there
      // re-planned the route.
      const iU = t.allScenarios().findIndex(sc => sc.id === 'ticket_4_15');
      t.selectAll(iU); s.paused = false; t.approach();
      it = s.activeIntersection;
      window.game.proceedAfterAnswer(true, it.situation.id); window.game.releaseTraffic(it.situation.id);
      t.tick(0.3); window.game.chooseUturn();
      mark = window.events.length;
      let prev = t.player().rotation.y, maxStep = 0, arcSpeed = 0, pressed = false;
      for (let f = 0; f < 60 * 30 && s.resolution; f++) {
        const r = s.resolution;
        window.game.setGas(!(r.phase === 'manual' && r.elapsed < 3 && r.yielding.some(a => !a.cleared && !a.done)));
        t.tick(1 / 60);
        if (!s.resolution) break;
        const yaw = t.player().rotation.y;
        maxStep = Math.max(maxStep, Math.abs(Math.atan2(Math.sin(yaw - prev), Math.cos(yaw - prev))));
        prev = yaw;
        if (Math.abs(Math.sin(yaw)) > 0.5) arcSpeed = Math.max(arcSpeed, s.speed);
        if (!pressed && Math.cos(yaw) < -0.3) { window.game.chooseUturn(); pressed = true; }
      }
      window.game.setGas(false);
      const flags = window.events.slice(mark).filter(e => e.event === 'exit_choice').map(e => e.uturn);
      out.uturn = { done: !s.resolution, smooth: maxStep < 0.08, slow: arcSpeed < 9,
        offeredOnce: flags.lastIndexOf(true) < flags.indexOf(false) || !flags.includes(true),
        refused: window.events.slice(mark).some(e => e.event === 'input_refused') };
      return out;
    });
    console.log(JSON.stringify(result));
    assert.equal(result.answerWhilePaused, true, 'answer while paused is applied on resume');
    assert.deepEqual(result.pauseMidTurn, { done: true, faults: [] }, 'a pause mid-turn keeps the turn');
    assert(Math.abs(result.fromCentreLine + 1.8) < 0.1, 'back to its own lane from the centre line: ' + result.fromCentreLine);
    assert(Math.abs(result.overtaking - 1.8) < 0.1, 'an overtaking car keeps the oncoming lane: ' + result.overtaking);
    assert.equal(result.occluderFaded, true, 'a building hiding the car is faded');
    assert.equal(result.extensionKept, true, 'a bus stop never takes a piece of the road away');
    assert.deepEqual(result.islandCut, { drawn: false, cutOff: true }, 'an island is felt only where it is drawn');
    assert.deepEqual(result.uturn, { done: true, smooth: true, slow: true, offeredOnce: true, refused: true }, 'a smooth, slow U-turn that cannot be re-planned half-way');
    assert.deepEqual(errors, []);
    console.log('PASS: robustness — paused answers, pause mid-turn, own lane, faded occluders, road kept by bus stops, cut-off islands, U-turn');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
