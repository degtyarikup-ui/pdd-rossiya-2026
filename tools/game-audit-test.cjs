// Focused regressions for contacts, model changes, recovery and world rebasing.
// Same GAME_URL, CHROME_PATH and Playwright setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
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
      window.events = [];
      window.FlutterChannel = { postMessage: m => events.push(JSON.parse(m)) };
      // Advance deterministically; no concurrent animation frame mutates fixtures.
      window.requestAnimationFrame = () => 0;
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const source = process.env.GAME_SCRIPT ? fs.readFileSync(process.env.GAME_SCRIPT, 'utf8') : await response.text();
      const body = source.replace('  // Run init on DOM ready', `
        window.audit = {
          state, player: () => playerCarGroup, scene: () => scene,
          playerOnRoad, playerFootprint, actorFootprint, footprintsOverlap,
          integrateDriving, updateActors, updatePlayerMovement, updateResolution,
          startActorFall, handleCollision, maybeReverseWorld, updateLaneViolation,
          finishRoadEvent, updateRoadEvent, placeRoadEvent, disposeSegment,
          audio: () => gameAudio.snapshot(), updateAudio: () => gameAudio.update(0.1, 1),
          fresh() { resetGame(); window.game.setPaused(false); window.game.selectVehicle('hatch'); events.length = 0; },
          actor(type = 'car', x = -1.8, z = 0, yaw = 0) {
            const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
            const p = new THREE.Vector3(x, 0, z), forward = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
            const a = addRoadActor(group, { id: 'audit-' + state.actors.length, type, name: 'Audit', color: '#0574F8' }, p, yaw,
              [p, p.clone().addScaledVector(forward, 20), p.clone().addScaledVector(forward, 60)], 6);
            // Isolated from the random start junction: a T-junction or a
            // roundabout ahead would otherwise reroute these test cars.
            a.rerouted = true;
            return a;
          },
          approach() { playerCarGroup.position.z = state.intersections[0].stopZ; updatePlayerMovement(0); },
          recover() { for (let i = 0; i < 30; i++) {
            if (state.resolution) updateResolution(1/60); else updatePlayerMovement(1/60);
          } }
        };
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.audit);
    const results = await page.evaluate(() => {
      const t = audit, results = {};
      const check = (name, fn) => { t.fresh(); try { results[name] = !!fn(); } catch (e) { results[name] = e.message; } };
      check('futureIntersectionTrafficAlreadyBlocksRoad', () => {
        // The start junction is drawn at random and may have no traffic:
        // redraw until it has some (the check is about that traffic).
        for (let k = 0; k < 40 && !t.state.intersections[0]?.actors.length; k++) t.fresh();
        const next = t.state.intersections[0];
        return next.actors.length > 0 && next.actors.every(a => t.state.actors.some(m =>
          m.mesh === a.mesh && !m.active && m.waitsForPlayer));
      });
      for (const fps of [15, 30, 60, 120]) {
        check('followingStopsAndResumesAt' + fps + 'Fps', () => {
          t.state.actors = []; t.player().position.x = 1000;
          const rear = t.actor('car', -1.8, 0), front = t.actor('tractor', -1.8, 20);
          rear.active = true; rear.maxSpeed = 16; rear.speed = 16;
          let minGap = Infinity;
          const tick = () => {
            t.updateActors(1 / fps);
            minGap = Math.min(minGap, front.mesh.position.z - rear.mesh.position.z - front.halfLength - rear.halfLength);
          };
          for (let i = 0; i < fps * 10; i++) tick();
          const stopped = rear.speed < 0.01 && minGap >= 1.39 && front.distance === 0 && rear.distance > 5;
          const stopPosition = rear.distance;
          front.active = true; front.maxSpeed = 3;
          for (let i = 0; i < fps * 5; i++) tick();
          return stopped && minGap >= 1.39 && rear.distance > stopPosition + 8 &&
            Math.abs(rear.speed - front.speed) < 0.3 && !rear.crashed && !front.crashed;
        });
      }
      check('followingIgnoresAdjacentLane', () => {
        t.state.actors = []; t.player().position.x = 1000;
        const rear = t.actor('car', -1.8, 0); t.actor('car', 1.8, 8);
        rear.active = true; rear.maxSpeed = 12;
        for (let i = 0; i < 120; i++) t.updateActors(1/60);
        return rear.speed === 12 && rear.distance > 17;
      });
      check('followingUsesDifferentParentTransforms', () => {
        t.state.actors = []; t.player().position.x = 1000;
        const rear = t.actor('car', 0, 0, Math.PI / 2), front = t.actor('car', 0, 0);
        front.mesh.parent.position.x = 16; front.mesh.parent.rotation.y = Math.PI / 2;
        rear.active = true; rear.speed = rear.maxSpeed = 12;
        for (let i = 0; i < 600; i++) t.updateActors(1/60);
        const gap = t.actorFootprint(front).p.x - t.actorFootprint(rear).p.x - front.halfLength - rear.halfLength;
        return rear.speed < 0.01 && gap >= 1.39 && rear.distance > 5;
      });
      check('followingQueueDoesNotPushOrJitter', () => {
        t.state.actors = []; t.player().position.x = 1000;
        const queue = [0, 12, 24].map(z => t.actor('car', -1.8, z));
        queue.slice(0, 2).forEach(a => { a.active = true; a.maxSpeed = 12; });
        // Rear-to-front storage must be as safe as front-to-rear storage.
        for (let i = 0; i < 600; i++) t.updateActors(1/60);
        const stopped = queue.every(a => a.speed < 0.01);
        const positions = queue.map(a => a.distance);
        for (let i = 0; i < 120; i++) t.updateActors(1/60);
        const stable = queue.every((a, i) => Math.abs(a.distance - positions[i]) < 0.01);
        queue[2].active = true; queue[2].maxSpeed = 4;
        for (let i = 0; i < 300; i++) t.updateActors(1/60);
        return stopped && stable && queue.every((a, i) => a.distance > positions[i] + 8) &&
          queue.slice(1).every((a, i) => a.mesh.position.z - queue[i].mesh.position.z - a.halfLength - queue[i].halfLength >= 1.39);
      });
      check('followingSurvivesLongFrame', () => {
        t.state.actors = []; t.player().position.x = 1000;
        const rear = t.actor('car', -1.8, 0), front = t.actor('car', -1.8, 10);
        rear.active = true; rear.speed = rear.maxSpeed = 20;
        t.updateActors(1);
        return front.mesh.position.z - rear.mesh.position.z - front.halfLength - rear.halfLength >= 1.39;
      });
      check('followingHandlesLeaderEmergencyStop', () => {
        t.state.actors = []; t.player().position.x = 1000;
        const rear = t.actor('car', -1.8, 0), front = t.actor('car', -1.8, 16);
        rear.active = front.active = true;
        rear.speed = rear.maxSpeed = 16; front.speed = front.maxSpeed = 6;
        for (let i = 0; i < 120; i++) t.updateActors(1/60);
        front.active = false; front.waitsForPlayer = true; front.speed = 0;
        const stoppedAt = front.distance;
        let minimum = Infinity;
        for (let i = 0; i < 600; i++) {
          t.updateActors(1/60);
          minimum = Math.min(minimum, front.mesh.position.z - rear.mesh.position.z - front.halfLength - rear.halfLength);
        }
        return minimum >= 1.39 && rear.speed < 0.01 && front.distance === stoppedAt;
      });
      check('largerVehicleAtCurb', () => {
        t.player().position.x = -3.4;
        const before = t.playerOnRoad();
        game.setPaused(true); game.selectVehicle('pickup');
        return before && t.state.vehicleId === 'pickup' && t.playerOnRoad();
      });
      check('largerVehicleBesideTraffic', () => {
        const a = t.actor();
        a.mesh.position.z = t.playerFootprint().halfLength + a.halfLength + 0.1;
        const before = !t.footprintsOverlap(t.playerFootprint(), t.actorFootprint(a));
        game.setPaused(true); game.selectVehicle('pickup');
        return before && !t.footprintsOverlap(t.playerFootprint(), t.actorFootprint(a)) && t.playerOnRoad();
      });
      check('movingBackwardsCannotSwapVehicle', () => {
        t.state.speed = -4; game.selectVehicle('pickup');
        return t.state.vehicleId === 'hatch' && t.state.speed === -4;
      });
      check('selectionReleasesBrake', () => {
        t.state.isBraking = true; game.setPaused(true); t.state.isBraking = true;
        game.selectVehicle('pickup'); return !t.state.isBraking;
      });
      check('crashedLeaderDoesNotFreezeQueue', () => {
        const a = t.actor('car', -1.8, 0), b = t.actor('car', -1.8, -15);
        b.waitsForPlayer = false; b.dependencies = [a];
        t.handleCollision(a, 'audit'); t.player().position.x = 100;
        t.updateActors(0.1);
        return b.active && b.distance > 0;
      });
      check('fallenLeaderDoesNotFreezeQueue', () => {
        const a = t.actor('pedestrian', -1.8, 0), b = t.actor('car', -1.8, -15);
        b.waitsForPlayer = false; b.dependencies = [a];
        t.startActorFall(a); t.player().position.x = 100;
        t.updateActors(0.1);
        return b.active && b.distance > 0;
      });
      check('reverseImpactAtSpeedCounts', () => {
        const a = t.actor(); a.crashed = true;
        a.mesh.position.z = -(t.playerFootprint().halfLength + a.halfLength + 0.1);
        t.state.speed = -4; t.state.isBraking = true;
        t.integrateDriving(0.1);
        return events.some(e => e.event === 'violation' && e.type === 'collision');
      });
      check('recoveryNotifiesNativeControls', () => {
        const a = t.actor('car', -1.8, 0);
        t.handleCollision(a, 'audit'); t.recover();
        return events.filter(e => e.event === 'maneuver_ready').length === 1;
      });
      check('intersectionRecoveryNotifiesNativeControls', () => {
        t.approach(); game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
        const a = t.actor('car', 10, 0);
        t.handleCollision(a, 'audit'); t.recover();
        return events.filter(e => e.event === 'maneuver_ready').length === 1;
      });
      check('fallDirectionUsesWorldYaw', () => {
        const a = t.actor('pedestrian', 0, 0);
        a.mesh.parent.rotation.y = Math.PI / 2; a.mesh.parent.updateMatrixWorld(true);
        t.state.speed = 10; t.startActorFall(a); t.updateActors(0.5);
        const push = a.mesh.userData.body.getWorldPosition(new THREE.Vector3()).sub(a.mesh.getWorldPosition(new THREE.Vector3()));
        return Math.abs(push.x) < 0.01 && push.z > 0.1;
      });
      check('reverseFallFollowsTravelDirection', () => {
        const a = t.actor('pedestrian', 0, 0);
        t.state.speed = -4; t.startActorFall(a); t.updateActors(0.5);
        return a.mesh.userData.body.position.z < 0;
      });
      check('rebaseClearsNativeOncomingWarning', () => {
        t.player().position.set(-1.8, 0, -52); t.player().rotation.y = Math.PI;
        t.updateLaneViolation(0.1, true); events.length = 0;
        const reversed = t.maybeReverseWorld(true);
        return reversed && events.some(e => e.event === 'lane_changed' && !e.oncoming);
      });
      check('rebaseClearsSpeedLimit', () => {
        t.state.speedLimitKmH = 20; t.state.speedingTime = 0.7;
        t.player().position.set(-1.8, 0, -52); t.player().rotation.y = Math.PI;
        t.maybeReverseWorld(true);
        return !t.state.speedLimitKmH && !t.state.speedingTime;
      });
      check('skippedRoadEventReleasesWaitingActors', () => {
        const ev = t.placeRoadEvent(0);
        // Add a guaranteed stationary participant, independent of shuffled question.
        const a = t.actor('car', -1.8, 50); ev.actors.push(a);
        t.finishRoadEvent(false); t.updateActors(0.1);
        return !a.waitsForPlayer && a.active;
      });
      check('resetClearsSpeedingGrace', () => {
        t.state.speedingTime = 0.79; game.reset(); return !t.state.speedingTime;
      });
      check('impactAtStopLineCannotStrandRecovery', () => {
        const stop = t.state.intersections[0].stopZ;
        t.player().position.z = stop - 0.1;
        const a = t.actor('car', -1.8, stop + 4);
        a.mesh.position.z = t.player().position.z + t.playerFootprint().halfLength + a.halfLength + 0.03;
        t.state.speed = 4; t.state.isAccelerating = true;
        t.updatePlayerMovement(0.1);
        const hit = t.state.driveRecovery > 0;
        t.recover();
        return hit && !t.state.driveRecovery && events.some(e => e.event === 'maneuver_ready');
      });
      check('sirenDistanceUsesWorldCoordinates', () => {
        const a = t.actor('special', -1.8, 0);
        a.config.siren = true; a.active = true; a.mesh.parent.position.z = 120;
        t.player().position.z = 120;
        game.configure({soundEnabled: true}); t.updateAudio();
        const near = t.audio().siren > 0.1;
        t.player().position.z = 0; t.updateAudio();
        return near && t.audio().siren === 0;
      });
      check('reverseEngineSoundTracksSpeed', () => {
        game.configure({soundEnabled: true}); t.updateAudio(); const idle = t.audio().engine;
        t.state.speed = -4; t.updateAudio();
        return t.audio().engine > idle;
      });
      return results;
    });
    console.log(JSON.stringify(results, null, 2));
    assert.deepEqual(errors, []);
    assert.deepEqual(Object.entries(results).filter(([,value]) => value !== true), [], 'audit regressions');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
