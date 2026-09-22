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
        state, player: () => playerCarGroup, camera: () => camera,
        scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed),
        drawSituation: nextSituation,
        randomSequence(n) { situationBag = []; return Array.from({ length: n }, () => nextSituation().id); },
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
    await page.evaluate(() => window.game.setPaused(true));

    const lanes = await page.evaluate(() => {
      const t = window.__engineTest;
      t.state.paused = false;
      t.player().position.x = 1.8;
      t.tick(2);
      t.tick(2);
      const leftX = t.player().position.x;
      t.player().position.x = -1.8; t.tick(2);
      const rightX = t.player().position.x;
      const count = window.events.filter(e => e.event === 'violation').length;
      t.player().position.x = 1.8; t.tick(4);
      t.state.paused = true;
      return { leftX, rightX, count, total: window.events.filter(e => e.event === 'violation').length };
    });
    assert(lanes.leftX > 1.7 && lanes.rightX < -1.7, 'Directions must match camera/driver coordinates');
    assert.equal(lanes.count, 1, 'One violation per continuous excursion');
    assert.equal(lanes.total, 2, 'A new excursion counts once again');

    const features = await page.evaluate(() => {
      const t = window.__engineTest;
      t.select(0); t.state.paused = false;
      window.game.configure({});
      window.game.setGas(true);
      window.dispatchEvent(new MouseEvent('mouseup'));
      window.game.setPaused(false);
      const pedalOwnedByFlutter = t.state.isAccelerating;
      window.game.setGas(false);
      const violations = () => window.events.filter(e => e.event === 'violation').length;
      const before = violations();
      t.player().position.x = 1.8;
      t.tick(1/60); t.tick(2.95);
      const grace = violations() === before && t.state.oncoming;
      window.game.setPaused(true); t.tick(5);
      const frozen = violations() === before;
      window.game.setPaused(false); t.tick(0.1); t.tick(3);
      const once = violations() === before + 1;
      t.player().position.x = -1.8; t.tick(0.1);
      t.player().position.x = 1.8; t.tick(2);
      t.player().position.x = -1.8; t.tick(2);
      const returnedInTime = violations() === before + 1;
      window.game.setGas(true); window.game.setSteering(0.4); t.tick(0.35);
      const heading = t.player().rotation.y;
      window.game.setSteering(0); t.tick(0.2);
      const freeSteering = heading > 0.01 && Math.abs(heading - t.player().rotation.y) < 0.001;
      window.game.setGas(false); t.tick(0.5);
      const models = [];
      window.game.setPaused(true);
      for (const id of ['hatch', 'sedan', 'suv', 'pickup']) {
        window.game.selectVehicle(id);
        models.push(t.player().userData.halfLength + ':' + t.player().userData.height);
      }
      const distinctCars = new Set(models).size === 4;
      window.game.selectVehicle('hatch');
      const n = t.scenarios().length;
      const bag = t.randomSequence(2 * n), otherBag = t.randomSequence(n);
      const shuffled = new Set(bag.slice(0, n)).size === n && new Set(bag.slice(n)).size === n &&
        bag[n - 1] !== bag[n] && bag.slice(0, n).join() !== otherBag.join();
      t.select(0); t.state.paused = false; t.approach();
      window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
      t.tick(0.1);
      const guideVisible = t.state.activeIntersection.guide.visible;
      const routeArrows = t.state.activeIntersection.guide.children.length > 8 &&
        t.state.activeIntersection.guide.children.every(child => child.userData.guideArrow === true);
      const light = t.createTrafficLight('red');
      const litColors = () => {
        const colors = [];
        light.traverse(o => { if (o.userData.signalGlow && o.visible) colors.push(o.material.color.getHex()); });
        return colors;
      };
      const redOnly = litColors().join() === String(0xFF3838);
      light.setLightState('green');
      const signalGlow = redOnly && litColors().join() === String(0x36FF88);
      const simultaneous = t.state.resolution.yielding.every(a => a.active);
      const pedestrian = t.state.resolution.motions.find(a => a.config.type === 'pedestrian');
      pedestrian.distance = pedestrian.length - 0.1;
      pedestrian.mesh.position.copy(pedestrian.path.getPointAt(1));
      t.camera().position.copy(pedestrian.mesh.position).add(new THREE.Vector3(0, 42, -44));
      t.camera().lookAt(pedestrian.mesh.position);
      t.camera().updateMatrixWorld(true);
      t.updateActors(0.2);
      const pedestrianPersists = pedestrian.distance > pedestrian.length && !pedestrian.done && pedestrian.mesh.visible;
      t.player().position.copy(pedestrian.mesh.position);
      t.player().rotation.y = 0.27;
      const impactPosition = t.player().position.clone(), impactYaw = t.player().rotation.y;
      t.tick(1/60);
      const collision = window.events.some(e => e.event === 'violation' && e.type === 'collision') && t.state.resolution.recovery > 0;
      t.tick(1.2);
      const falls = !!pedestrian.fall && pedestrian.mesh.userData.body.quaternion.angleTo(new THREE.Quaternion()) > 1 &&
        !pedestrian.mesh.userData.badge.visible;
      const fallenFootprintTracksBody = t.actorFootprint(pedestrian).p.distanceTo(
        pedestrian.mesh.getWorldPosition(new THREE.Vector3())) > 0.2;
      const collisionPreservesPose = !t.state.resolution.recovery &&
        t.player().position.distanceTo(impactPosition) < 0.01 && Math.abs(t.player().rotation.y - impactYaw) < 0.001;
      // The struck pedestrian stays down and is driven over without a second ДТП.
      const violationsAtFall = window.events.filter(e => e.event === 'violation').length;
      t.state.resolution.recovery = 0; t.state.speed = 6;
      pedestrian.mesh.position.set(-1.8, 0, t.state.resolution.intersection.centerZ - 12);
      t.player().position.copy(pedestrian.mesh.position).add(new THREE.Vector3(0, 0, -4)); t.player().rotation.y = 0;
      t.state.isAccelerating = true; t.integrateDriving(0.5); t.integrateDriving(0.5); t.state.isAccelerating = false;
      const fallRecovers = !!pedestrian.fall && !pedestrian.mesh.userData.badge.visible &&
        pedestrian.mesh.userData.body.quaternion.angleTo(new THREE.Quaternion()) > 1 &&
        t.player().position.z > pedestrian.mesh.position.z + 1 &&
        window.events.filter(e => e.event === 'violation').length === violationsAtFall;
      t.player().position.copy(pedestrian.mesh.position).add(new THREE.Vector3(10, 0, 10));
      t.tick(2.3);
      t.player().position.set(10, 0, t.state.resolution.intersection.centerZ - 10);
      t.tick(1/60);
      const offroad = window.events.some(e => e.event === 'violation' && e.type === 'offroad');
      t.tick(1.2);
      t.player().position.set(-1.8, 0, t.state.resolution.intersection.centerZ + 25);
      t.player().rotation.y = 0;
      t.tick(1/60);
      const wrongExit = window.events.some(e => e.event === 'violation' && e.type === 'wrong_maneuver');
      t.select(0); t.state.paused = false; t.approach();
      window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
      t.tick(20); window.game.setGas(true); t.tick(1.3);
      const fullSpeed = t.state.speed > 10;
      window.game.setGas(false);
      t.state.paused = true;
      return { freeSteering, distinctCars, guideVisible, routeArrows, signalGlow, falls, fallenFootprintTracksBody, fallRecovers: fallRecovers /* stays down, drivable over */, fullSpeed, pedalOwnedByFlutter, grace, frozen, once, returnedInTime, shuffled, simultaneous, pedestrianPersists, collision, collisionPreservesPose, offroad, wrongExit };
    });
    if (process.env.GAME_SHOTS) {
      fs.mkdirSync(process.env.GAME_SHOTS, { recursive: true });
      await page.screenshot({ path: path.join(process.env.GAME_SHOTS, 'guide-arrows.png') });
    }
    for (const [feature, passed] of Object.entries(features)) assert.equal(passed, true, feature);
    const interactions = await page.evaluate(() => {
      const t = window.__engineTest;
      t.select(0); t.state.paused = false;
      t.player().position.x = -2.9; t.player().rotation.y = -0.12;
      window.game.setGas(true); t.tick(1.3);
      const curbSlide = t.playerOnRoad() && t.player().position.z > 2 && !t.state.driveRecovery;
      window.game.setSteering(0.6); t.tick(1);
      const curbExit = t.playerOnRoad() && t.player().rotation.y > -0.1 && !t.state.driveRecovery;
      t.select(0); t.state.paused = false;
      t.player().position.set(-2.3, 0, 0); t.player().rotation.y = -Math.PI / 2;
      window.game.setGas(true); t.tick(1);
      window.game.setSteering(1); t.tick(3);
      const noseExit = t.playerOnRoad() && t.player().rotation.y > -1.3 && !t.state.driveRecovery;
      t.select(0); t.approach(); t.state.paused = false;
      const intersection = t.state.activeIntersection;
      window.game.releaseTraffic(intersection.situation.id);
      const count = t.state.actors.length;
      t.updateActors(1);
      const wrongAnswerTraffic = t.state.actors.some(a => a.distance > 0);
      window.game.proceedAfterAnswer(false, intersection.situation.id);
      const noTrafficRestart = t.state.actors.length === count && t.state.actors.some(a => a.distance > 0);
      const index = t.scenarios().findIndex(s => s.actorsConfig.some(a => !['pedestrian', 'cyclist'].includes(a.type)));
      function rearEnd(rotated) {
        t.select(index); t.approach(); t.state.paused = false;
        window.game.releaseTraffic(t.state.activeIntersection.situation.id);
        const a = t.state.actors.find(a => !['pedestrian', 'cyclist'].includes(a.config.type));
        t.state.actors = [a]; t.state.isAtSituation = false;
        a.path = new THREE.LineCurve3(new THREE.Vector3(-1.8, 0, -14), new THREE.Vector3(-1.8, 0, 40));
        a.length = 54; a.distance = 0; a.active = true; a.waitsForPlayer = false; a.dependencies = [];
        a.mesh.position.copy(a.path.getPointAt(0)); a.mesh.rotation.y = 0;
        if (rotated) { a.mesh.parent.rotation.y = Math.PI / 2; a.mesh.parent.position.set(3, 0, 5); }
        a.mesh.parent.updateMatrixWorld(true);
        t.player().position.set(-1.8, 0, 0).applyMatrix4(a.mesh.parent.matrixWorld);
        t.player().rotation.y = rotated ? Math.PI / 2 : 0;
        for (let i = 0; i < 240; i++) t.updateActors(1 / 60);
        // A following driver brakes to a gap behind the stationary player: no ДТП.
        const blocked = !a.crashed && a.speed < 0.6 && a.distance > 4 && a.distance < 14 &&
          !t.footprintsOverlap(t.playerFootprint(), t.actorFootprint(a), 0.1);
        const stoppedDistance = a.distance;
        const playerBefore = t.player().position.clone(), yawBefore = t.player().rotation.y;
        t.state.driveRecovery = 0; t.state.isAccelerating = true;
        t.integrateDriving(0.45);
        t.state.isAccelerating = false;
        const escaped = rotated || t.player().position.distanceTo(playerBefore) > 0.5;
        for (let i = 0; i < 30; i++) t.updateActors(1 / 60);
        // ...and resumes once the road ahead is free.
        return blocked && escaped && Math.abs(t.player().rotation.y - yawBefore) < 0.001 && a.distance > stoppedDistance;
      }
      const rearCollision = rearEnd(false), rebasedCollision = rearEnd(true);
      t.select(index); t.approach(); t.state.paused = false;
      window.game.releaseTraffic(t.state.activeIntersection.situation.id);
      const sideActor = t.state.actors.find(a => !['pedestrian', 'cyclist'].includes(a.config.type));
      const crossZ = t.state.activeIntersection.centerZ;
      t.state.actors = [sideActor]; t.state.isAtSituation = false;
      sideActor.path = new THREE.LineCurve3(new THREE.Vector3(-14, 0, crossZ), new THREE.Vector3(40, 0, crossZ));
      sideActor.length = 54; sideActor.distance = 0; sideActor.active = true; sideActor.waitsForPlayer = false; sideActor.dependencies = [];
      sideActor.mesh.position.copy(sideActor.path.getPointAt(0)); sideActor.mesh.rotation.y = Math.PI / 2;
      t.player().position.set(-1.8, 0, crossZ); t.player().rotation.y = 0;
      t.updateActors(3);
      const sideStart = t.player().position.clone();
      t.state.driveRecovery = 0; t.state.isAccelerating = true; t.integrateDriving(0.45); t.state.isAccelerating = false;
      const sideCollisionEscape = sideActor.crashed && t.player().position.z > sideStart.z + 0.5 &&
        Math.abs(t.player().rotation.y) < 0.001 && !t.footprintsOverlap(t.playerFootprint(), t.actorFootprint(sideActor), 0.05);
      // Regression: a crash participant that ends up INSIDE the player's car
      // (no escape gap along its own route) must not re-trigger the collision
      // every frame and freeze the run. The player has no reverse gear, so the
      // engine has to open a gap itself and let the car drive on.
      t.select(index); t.approach(); t.state.paused = false;
      window.game.releaseTraffic(t.state.activeIntersection.situation.id);
      const stuckActor = t.state.actors.find(a => !['pedestrian', 'cyclist'].includes(a.config.type));
      t.state.actors = [stuckActor]; t.state.isAtSituation = false; t.state.resolution = null;
      stuckActor.path = new THREE.LineCurve3(new THREE.Vector3(-1.8, 0, 60), new THREE.Vector3(-1.8, 0, 0));
      stuckActor.length = 60; stuckActor.distance = 60; stuckActor.active = true; stuckActor.waitsForPlayer = false; stuckActor.dependencies = [];
      t.player().position.set(-1.8, 0, 0); t.player().rotation.y = 0;
      stuckActor.mesh.position.copy(t.player().position); stuckActor.mesh.rotation.y = Math.PI;
      stuckActor.mesh.parent.updateMatrixWorld(true);
      const violationsBefore = window.events.length;
      t.state.driveRecovery = 0; t.state.driveFaults.clear();
      window.game.setGas(true);
      // Steer around the wreck the way a player would: no reverse gear exists.
      for (let i = 0; i < 300; i++) {
        if (!t.state.driveRecovery) { window.game.setGas(true); window.game.setSteering(i < 150 ? 1 : -1); }
        t.tick(1 / 60);
      }
      window.game.setGas(false); window.game.setSteering(0);
      const stuckViolations = window.events.slice(violationsBefore).filter(e => e.event === 'violation' && e.type === 'collision').length;
      const collisionUnstuck = stuckActor.crashed && stuckViolations <= 1 &&
        t.player().position.distanceTo(new THREE.Vector3(-1.8, 0, 0)) > 3 &&
        !t.footprintsOverlap(t.playerFootprint(), t.actorFootprint(stuckActor));
      // --- Brake pedal: hard stop while moving, reverse gear from a standstill.
      t.select(0); t.approach(); t.state.paused = false; t.state.isAtSituation = false; t.state.intersections = [];
      t.player().position.set(-1.8, 0, 0); t.player().rotation.y = 0; t.state.speed = 15;
      window.game.setBrake(true); t.tick(0.4); const brakeSpeedAfter = t.state.speed;
      t.tick(0.5); const stopped = t.state.speed <= 0;
      const zBeforeReverse = t.player().position.z; t.tick(1.5);
      const wentBack = t.state.speed < 0 && t.player().position.z < zBeforeReverse - 1;
      window.game.setBrake(false); t.tick(1);
      const brakeWorks = brakeSpeedAfter < 5 && stopped && wentBack && t.state.speed === 0 && t.state.distanceTraveled < 5;
      // --- Straight-road situations: speed limit, prohibited overtaking, zebra.
      function driveUntil(predicate, frames = 1500, steer = 0) {
        for (let i = 0; i < frames && !predicate(); i++) {
          if (!t.state.driveRecovery) { window.game.setGas(true); window.game.setSteering(typeof steer === 'function' ? steer() : steer); }
          t.tick(1 / 60);
        }
        window.game.setGas(false); window.game.setSteering(0);
        return predicate();
      }
      function enterRoadEvent(id) {
        t.select(0); t.approach(); t.state.paused = false;
        if (id && id !== 'busstop') t.roadQueue([id]); else t.state.roadTurn = 1;
        t.state.forceRoadEvent = id === 'busstop' ? 'busstop' : 'crosswalk';
        window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
        const drive = t.drive();
        return drive?.complete ? t.state.roadEvent : null;
      }
      const speedEvent = enterRoadEvent('road_1_16');
      const roadPlaced = !!speedEvent && speedEvent.kind === 'speed' && speedEvent.situation.id === 'road_1_16' && speedEvent.phase === 'approach';
      const roadStopped = roadPlaced && driveUntil(() => t.state.isAtSituation) && speedEvent.phase === 'question' &&
        Math.abs(t.player().position.z - speedEvent.stopZ) < 0.6 &&
        window.events.filter(e => e.event === 'approach_situation').pop().situation.id === 'road_1_16';
      window.game.proceedAfterAnswer(true, 'road_1_16');
      const roadManual = speedEvent.phase === 'manual' && !t.state.isAtSituation;
      const eventsBeforeSpeeding = window.events.length;
      const speedLimited = roadManual && driveUntil(() => t.state.speedLimitKmH === 20 && t.state.speed * 3.6 > 40, 900) &&
        driveUntil(() => window.events.slice(eventsBeforeSpeeding).some(e => e.event === 'violation' && e.type === 'speeding'), 240);
      const roadCleared = speedLimited && driveUntil(() => !t.state.roadEvent, 1200) &&
        window.events.slice(eventsBeforeSpeeding).some(e => e.event === 'situation_cleared' && e.situationId === 'road_1_16') &&
        t.state.speedLimitKmH === null; // 5.22 "end of residential zone" restores the town limit
      const overtakeEvent = enterRoadEvent('road_24_11');
      const overtakeQuestion = !!overtakeEvent && overtakeEvent.scene.overtake === false && driveUntil(() => t.state.isAtSituation);
      window.game.proceedAfterAnswer(false, 'road_24_11');
      const truck = overtakeEvent?.actors[0];
      const truckStart = truck?.mesh.position.z;
      const eventsBeforeOvertake = window.events.length;
      // Move into the oncoming lane like a player would: steer left, then straighten.
      const intoOncoming = () => t.player().position.x < 1.6 ? (t.player().rotation.y < 0.35 ? 1 : 0) : (t.player().rotation.y > 0.03 ? -1 : 0);
      const overtakePenalised = overtakeQuestion && driveUntil(() =>
        window.events.slice(eventsBeforeOvertake).some(e => e.event === 'violation' && e.type === 'overtaking'), 600, intoOncoming) &&
        truck.mesh.position.z > truckStart + 2 && t.player().position.x > 0.85;
      const backToLane = () => t.player().position.z < truck.mesh.position.z + 9 ? (t.player().rotation.y > 0.03 ? -1 : 0) :
        t.player().position.x > -1.6 ? (t.player().rotation.y > -0.35 ? -1 : 0) : (t.player().rotation.y < -0.03 ? 1 : 0);
      const overtakeDone = overtakePenalised && driveUntil(() => !t.state.roadEvent, 1500, backToLane) &&
        window.events.slice(eventsBeforeOvertake).some(e => e.event === 'situation_cleared' && e.situationId === 'road_24_11') &&
        !t.state.intersections.some(it => it.stopZ < t.player().position.z);
      // Signalled manoeuvres: the truck with a left signal really overtakes and
      // returns; the motorcycle really turns left at the next junction.
      const overtakeNpc = enterRoadEvent('road_20_11');
      const npcTruck = overtakeNpc?.actors[0];
      let npcLeft = false, npcRight = false, npcOut = false;
      const npcOvertakes = !!overtakeNpc && driveUntil(() => t.state.isAtSituation) && (() => {
        window.game.proceedAfterAnswer(true, 'road_20_11');
        for (let i = 0; i < 1500 && npcTruck.distance < 110; i++) {
          t.tick(1 / 60);
          const lamps = npcTruck.mesh.userData.blinkerLamps;
          if (npcTruck.distance < 18 && lamps.left.some(l => l.visible)) npcLeft = true;
          if (npcTruck.distance > 58 && npcTruck.distance < 78 && lamps.right.some(l => l.visible)) npcRight = true;
          if (npcTruck.mesh.position.x > 1.5) npcOut = true;
        }
        const lamps = npcTruck.mesh.userData.blinkerLamps;
        return npcLeft && npcRight && npcOut && Math.abs(npcTruck.mesh.position.x + 1.8) < 0.2 &&
          !lamps.left.some(l => l.visible) && !lamps.right.some(l => l.visible);
      })();
      const turnEvent = enterRoadEvent('road_2_11');
      const npcMoto = turnEvent?.actors[0];
      const npcTurns = !!turnEvent && driveUntil(() => t.state.isAtSituation) && (() => {
        window.game.proceedAfterAnswer(true, 'road_2_11');
        // Follow at a safe distance instead of ramming the motorcycle.
        for (let i = 0; i < 4000 && npcMoto.mesh.position.x < 15; i++) {
          const gap = npcMoto.mesh.position.z - t.player().position.z;
          if (!t.state.driveRecovery) window.game.setGas(gap > 16 || npcMoto.mesh.position.x > 2);
          t.tick(1 / 60);
        }
        window.game.setGas(false);
        return npcMoto.mesh.position.x > 15 && Math.abs(npcMoto.mesh.rotation.y - Math.PI / 2) < 0.2 &&
          !npcMoto.mesh.userData.blinkerLamps.left.some(l => l.visible);
      })();
      // Bus bay: the bus pulls into the pocket, dwells, then merges back.
      const stopEvent = enterRoadEvent('busstop');
      const bus = stopEvent?.actors[0];
      let dwelt = false, inBay = false;
      const startedInBay = !!bus && bus.mesh.position.x < -4.5;
      const busStops = startedInBay && !!stopEvent && stopEvent.kind === 'busstop' && (() => {
        for (let i = 0; i < 1500; i++) {
          const gap = bus.mesh.position.z - t.player().position.z;
          if (!t.state.driveRecovery) window.game.setGas(gap > 16); // stay behind the bus
          t.tick(1 / 60);
          if (bus.mesh.position.x < -4.5) { inBay = true; if (bus.speed === 0) dwelt = true; }
          if (dwelt && bus.mesh.position.x > -2.2 && bus.mesh.position.z > stopEvent.bayZ + 15) break;
        }
        window.game.setGas(false);
        return inBay && dwelt && bus.mesh.position.x > -2.2 && bus.speed > 0;
      })();
      const zebraEvent = enterRoadEvent(null);
      const zebraPlaced = !!zebraEvent && zebraEvent.kind === 'crosswalk' && zebraEvent.pedestrian.waitsForPlayer;
      const eventsBeforeZebra = window.events.length;
      const pedestrianReleased = zebraPlaced && driveUntil(() => zebraEvent.phase === 'manual', 900) &&
        driveUntil(() => Math.abs(zebraEvent.pedestrian.mesh.position.x) < 4.4, 300);
      const pedestrianYield = pedestrianReleased && driveUntil(() => !t.state.roadEvent, 600) &&
        window.events.slice(eventsBeforeZebra).some(e => e.event === 'violation' && e.type === 'pedestrian') &&
        !window.events.slice(eventsBeforeZebra).some(e => e.event === 'approach_situation');
      const tramIndex = t.scenarios().findIndex(s => s.actorsConfig.some(a => a.type === 'tram'));
      t.select(tramIndex);
      const tram = t.state.intersections[0].actors.find(a => a.config.type === 'tram');
      const rails = [];
      t.state.intersections[0].seg.traverse(o => { if (o.userData.tramRail) rails.push(o); });
      const continuousRails = rails.length >= 2 && rails.every(rail => rail.userData.railEnd.distanceTo(tram.initialPos) > 90);
      window.game.configure({ soundEnabled: false });
      const muteWorks = !t.audioSnapshot().enabled;
      window.game.configure({ soundEnabled: true });
      t.state.speed = 10; t.state.isAccelerating = true; t.updateAudio(0.1, 8);
      const dynamicAudio = t.audioSnapshot().enabled && t.audioSnapshot().engine > 0;
      t.state.isAccelerating = false;
      t.select(0);
      const ambient = t.state.ambient.length > 0 && t.state.ambient.every(a => Math.abs(a.mesh.position.x) > 5);
      const a = t.state.ambient[0], before = a.mesh.position.z; t.updateActors(1);
      const livingScenery = ambient && a.mesh.position.z !== before && !t.state.actors.includes(a);
      t.select(0); t.state.paused = false;
      t.player().position.set(-1.8, 0, -52); t.player().rotation.y = Math.PI;
      const relativeCamera = t.camera().position.clone().sub(t.player().position);
      const oldSituation = t.state.intersections[0].situation.id;
      const reversed = t.maybeReverseWorld(true);
      const cameraInvariant = t.camera().position.clone().sub(t.player().position).distanceTo(relativeCamera.clone().applyAxisAngle(new THREE.Vector3(0, 1, 0), Math.PI)) < 0.01;
      const reverseGenerated = reversed && Math.cos(t.player().rotation.y) > 0.99 &&
        t.state.intersections.length === 1 && t.state.intersections[0].situation.id !== oldSituation &&
        t.corridorWorldEnds().some(p => p.z > t.player().position.z) && t.playerOnRoad();
      window.game.setGas(true);
      for (let i = 0; i < 1200 && !t.state.isAtSituation; i++) t.tick(1 / 60);
      const reverseSituation = t.state.isAtSituation && t.state.activeIntersection != null;
      t.state.paused = true;

      // Attract mode: the parked player, traffic passing on both sides, no
      // head-on meeting, and the gas pedal ignored.
      const attractRun = () => {
        const parkedAt = t.player().position.clone();
        const yaw = t.player().rotation.y, fwd = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
        window.game.setAttract(true);
        window.game.setGas(true);
        const ids = new Set(), passed = new Set();
        let crash = false, offRoad = false;
        for (let i = 0; i < 60 * 60; i++) {
          t.tick(1 / 60);
          t.state.actors.forEach(a => {
            if (!a.config?.id?.startsWith('attract_')) return;
            ids.add(a.config.id);
            if (a.attractBehind && a.mesh.position.clone().sub(parkedAt).dot(fwd) > 12) passed.add(a.config.id);
            if (!a.done && i % 30 === 0 && Math.abs(a.mesh.position.clone().sub(parkedAt).dot(fwd)) < 60 && !t.surfaceAt(a.mesh.position.x, a.mesh.position.z).some(sf => sf.includes('road'))) offRoad = [a.attractBehind, a.mesh.position.x.toFixed(1), a.mesh.position.z.toFixed(1), a.mesh.position.clone().sub(parkedAt).dot(fwd).toFixed(0)];
          });
          if (t.state.actors.some(a => a.crashed || a.knock)) crash = true;
        }
        const parked = t.player().position.distanceTo(parkedAt) < 0.01 && !t.state.isAccelerating;
        // Nobody queues up: no attract car is standing still on the road at the end.
        const stalled = t.state.actors.filter(a => a.config?.id?.startsWith('attract_') && !a.done && a.speed < 0.1 && a.distance > 5).map(a => [a.attractBehind, a.distance.toFixed(0), a.length.toFixed(0), a.mesh.position.clone().sub(parkedAt).dot(fwd).toFixed(0), a.attractStill]);
        window.game.setAttract(false);
        return parked && ids.size >= 4 && passed.size >= 2 && !crash && !offRoad && stalled.length === 0;
      };
      t.select(0); t.state.paused = false;
      const attractParked = attractRun();
      // The same in a reversed world (the player faces -Z): lanes must follow the car.
      t.select(0); t.state.paused = false;
      t.player().position.set(-1.8, 0, -52); t.player().rotation.y = Math.PI; t.maybeReverseWorld(true);
      t.player().position.x = -1.8; // back into the right-hand lane of the rebased world
      const attractTraffic = attractRun();
      t.state.paused = true;

      // Reveal: door opens on tap, the car drives out and turns; hideReveal
      // returns to the road scene. Thumbnails render for every model.
      window.game.showReveal('coupe', 'teal');
      const revealEvents = () => window.events.filter(e => e.event === 'reveal_shown').length;
      const revealBefore = revealEvents();
      t.tick(1); // still closed
      window.game.openReveal();
      for (let i = 0; i < 60 * 6; i++) t.tick(1 / 60);
      const revealShown = revealEvents() === revealBefore + 1;
      window.game.hideReveal();
      const thumbs = ['hatch', 'sedan', 'coupe', 'wagon', 'suv', 'pickup', 'cyber'].map(id => window.game.thumbnail(id, 'blue'));
      const thumbnails = thumbs.every(u => u.startsWith('data:image/png') && u.length > 2000);
      return { attractParked, attractTraffic, revealShown, thumbnails,
        curbSlide, curbExit, noseExit, wrongAnswerTraffic, noTrafficRestart, rearCollision,
        rebasedCollision, sideCollisionEscape, collisionUnstuck, brakeWorks, roadPlaced, roadStopped, roadManual, speedLimited, roadCleared, overtakeQuestion, overtakePenalised, overtakeDone, npcOvertakes, npcTurns, busStops, zebraPlaced, pedestrianReleased, pedestrianYield, continuousRails, muteWorks, dynamicAudio, livingScenery, cameraInvariant, reverseGenerated, reverseSituation };
    });
    if (process.env.GAME_SHOTS) {
      for (const id of ['road_24_11', 'road_13_11', 'road_9_5', 'road_1_16', null]) {
        await page.evaluate(id => {
          const t = window.__engineTest;
          t.select(0); t.approach(); t.state.paused = false;
          if (id && id !== 'busstop') t.roadQueue([id]); else t.state.roadTurn = 1;
        t.state.forceRoadEvent = id === 'busstop' ? 'busstop' : 'crosswalk';
          window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
          t.drive();
          const ev = t.state.roadEvent;
          const target = id ? ev.stopZ : ev.crosswalkZ - 30;
          for (let i = 0; i < 1500 && !t.state.isAtSituation && t.player().position.z < target; i++) { window.game.setGas(true); t.tick(1 / 60); }
          window.game.setGas(false);
          if (!id) { for (let i = 0; i < 150; i++) t.tick(1 / 60); }
          t.tick(0.5);
        }, id);
        await page.screenshot({ path: path.join(process.env.GAME_SHOTS, `${id || 'crosswalk'}.png`) });
      }
    }
    console.log(JSON.stringify({ interactions }));
    for (const [name, passed] of Object.entries(interactions)) assert.equal(passed, true, name);
    if (process.env.FEATURES_ONLY) {
      assert.deepEqual(errors, []);
      console.log(JSON.stringify({ passed: true, features }, null, 2));
      return;
    }

    const results = await page.evaluate(only => {
      const t = window.__engineTest;
      return t.scenarios().map((scenario, index) => {
        if (only && scenario.id !== only) return { id: scenario.id };
        t.select(index); t.approach();
        window.game.setViewportInsets({ top: 130, bottom: 400 });
        t.tick(3);
        const bounds = t.state.activeIntersection.actors.map(a => a.viewBounds);
        const framed = bounds.every(b => {
          for (const x of [b.min.x, b.max.x]) for (const y of [b.min.y, b.max.y]) for (const z of [b.min.z, b.max.z]) {
            const p = new THREE.Vector3(x, y, z).project(t.camera());
            const screenY = (1 - p.y) * 844 / 2;
            if (Math.abs(p.x) > 1.02 || screenY < 125 || screenY > 449) return false;
          }
          return true;
        });
        const id = t.state.activeIntersection.situation.id;
        const previews = Object.values(t.state.activeIntersection.previews);
        const exitsPrebuilt = previews.length === 4 && previews.every(p =>
          p.parent === t.state.activeIntersection.seg &&
          p.children.some(m => m.geometry?.parameters?.height === 200));
        const before = window.events.filter(e => e.event === 'situation_cleared').length;
        t.state.paused = false;
        window.game.proceedAfterAnswer(false, 'stale-id');
        const staleIgnored = !t.state.resolution;
        window.game.proceedAfterAnswer(false, id);
        window.game.proceedAfterAnswer(false, id);
        const entry = t.player().position.clone();
        t.tick(1);
        const waitsForInput = t.player().position.distanceTo(entry) < 0.001;
        const keptRoad = t.state.activeIntersection.previews[window.PDD_SCENARIO_ROUTES[id].maneuver];
        const keptTrees = keptRoad.children.map(o => o.uuid).join();
        const drive = t.drive();
        if (!drive?.complete) return { id, drive };
        t.tick(50);
        // A stopped player now physically blocks following traffic. Vacate the
        // carriageway to verify that those actors resume instead of phasing through.
        const parked = t.player().position.clone();
        t.player().position.x += 1000;
        // The camera follows the player: a parked crash participant is removed
        // only once it leaves the view, so the view must move with the player.
        for (let frame = 0; frame < 3600; frame++) { t.updateActors(1 / 60); t.updateCamera(1 / 60); }
        t.player().position.copy(parked);
        const after = window.events.filter(e => e.event === 'situation_cleared').length;
        const cleanRoad = [1.8, -1.8].every(x => [30, 55, 85, 120].every(d => {
          const surface = t.surfaceAt(x, t.player().position.z + d);
          return surface.includes('road') && !surface.includes('sidewalk');
        }));
        const sceneryPreserved = t.state.exitRoad === keptRoad && keptRoad.children.map(o => o.uuid).join() === keptTrees;
        const result = { id, framed, exitsPrebuilt, waitsForInput, cleanRoad, sceneryPreserved, staleIgnored, clearedOnce: after === before + 1,
          resolved: !t.state.isResolvingSituation,
          actorsFinished: t.state.actors.every(a => a.done || a.road) /* road-event traffic waits for the player by design */,
          finite: Number.isFinite(t.player().position.x + t.player().position.z + t.camera().position.x),
          roadAhead: !!t.state.exitRoad,
          normalLane: t.state.targetLane === 1 };
        t.state.paused = true;
        if (!result.actorsFinished) throw new Error(JSON.stringify({ id,
          blocked: t.state.actors.filter(a => !a.done && !a.road).map(a => ({ id: a.config.id,
            position: a.mesh.position.toArray(), distance: a.distance, active: a.active,
            cleared: a.cleared, waits: a.waitsForPlayer, dependencies: a.dependencies?.map(b => [b.config.id, b.cleared]) })) }));
        return result;
      });
    }, process.env.SCENARIO || null);
    for (const result of results) {
      if (result.drive) throw new Error(JSON.stringify(result));
      for (const [key, value] of Object.entries(result)) if (key !== 'id') assert.equal(value, true, `${result.id}: ${key}`);
    }

    if (process.env.SCENARIO) {
      console.log(JSON.stringify({ passed: true, scenario: process.env.SCENARIO }));
      return;
    }
    const longRun = await page.evaluate(() => {
      const t = window.__engineTest;
      t.select(0); t.state.paused = false;
      let count = 0;
      for (; count < 35; count++) {
        t.approach();
        window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
        const drive = t.drive();
        if (!drive?.complete) return { failure: drive, count };
        t.tick(50);
      }
      const bounded = t.state.roadSegments.length <= 8;
      window.game.reset();
      t.state.paused = true;
      return { count, bounded, actors: t.state.actors.length, distance: t.state.distanceTraveled,
        // Reset keeps the new visible participants registered as stationary obstacles.
        initialActors: t.state.intersections[0].actors.length,
        resetTrafficWaiting: t.state.actors.every(a => !a.active && a.waitsForPlayer && a.distance === 0),
        resolution: t.state.resolution, firstId: t.state.intersections[0].situation.id };
    });
    assert(longRun.bounded);
    assert.equal(longRun.count, 35);
    assert.equal(longRun.actors, longRun.initialActors);
    assert.equal(longRun.resetTrafficWaiting, true);
    assert.equal(longRun.distance, 0);
    assert.equal(longRun.resolution, null);

    if (process.env.GAME_SHOTS) {
      fs.mkdirSync(process.env.GAME_SHOTS, { recursive: true });
      await page.evaluate(() => {
        const t = window.__engineTest;
        t.select(0); t.state.paused = false;
        t.player().position.set(-1.8, 0, -52); t.player().rotation.y = Math.PI;
        t.maybeReverseWorld(true); t.tick(1);
        t.state.paused = true;
      });
      await page.screenshot({ path: path.join(process.env.GAME_SHOTS, 'reverse-generated.png') });
      await page.evaluate(() => {
        const t = window.__engineTest;
        t.select(0); t.state.paused = false;
        t.player().position.set(-2.3, 0, -25); t.player().rotation.y = -Math.PI / 2;
        t.tick(2); t.state.paused = true;
      });
      await page.screenshot({ path: path.join(process.env.GAME_SHOTS, 'curb-horizon.png') });
      await page.evaluate(() => { window.game.setTheme(false); window.game.setViewportInsets({ top: 95, bottom: 400 }); });
      await page.evaluate(() => { window.__engineTest.approach(); window.__engineTest.tick(2); });
      await page.screenshot({ path: path.join(process.env.GAME_SHOTS, 'crossing-mobile.png') });
      await page.evaluate(() => { window.game.setTheme(true); });
      await page.screenshot({ path: path.join(process.env.GAME_SHOTS, 'crossing-dark.png') });
      await page.evaluate(() => { window.game.setTheme(false); });
      for (const maneuver of ['straight', 'left', 'right', 'uturn']) {
        await page.evaluate(maneuver => {
          const t = window.__engineTest;
          const idx = t.scenarios().findIndex(s => window.PDD_SCENARIO_ROUTES[s.id].maneuver === maneuver);
          t.select(idx); t.approach(); t.tick(2);
          t.state.paused = false;
          window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
          t.drive(120);
          t.tick(0.1); t.state.paused = true;
        }, maneuver);
        await page.screenshot({ path: path.join(process.env.GAME_SHOTS, `maneuver-${maneuver}.png`) });
      }
    }
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ passed: true, scenarios: results.length, laps: longRun.count, laneTests: lanes, features, errors }, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
