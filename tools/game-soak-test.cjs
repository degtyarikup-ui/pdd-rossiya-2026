// Soak test: long unattended runs through the real game loop.
//
// A driver plays like the app does — answers every question (mostly right,
// sometimes wrong: traffic is released first, the run goes on after the
// "explanation"), follows the hinted arrows in simple steering, gives way for
// a few seconds after an answer, now and then pauses or opens the garage in
// the middle of a run. Meanwhile it watches for engine exceptions and console
// errors, non-finite positions, a car that makes no progress for long, a car
// off the road for long, and growth of objects and GPU memory over time.
//
// Run with NODE_PATH pointing at Playwright and a local server on :8938:
//   SOAK_MINUTES=12 SOAK_SEEDS=1,2,3 node tools/game-soak-test.cjs
// SOAK_FREE=1 drives in free steering (the arrows as a wheel) instead.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  const minutes = Number(process.env.SOAK_MINUTES || 8);
  const seeds = (process.env.SOAK_SEEDS || '1').split(',').map(Number);
  const free = !!process.env.SOAK_FREE;
  const report = [];
  try {
    for (const seed of seeds) {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
      const errors = [], consoleErrors = [];
      page.on('pageerror', e => errors.push(e.message + ' @ ' + (e.stack || '').split('\n').slice(1, 3).join(' | ')));
      page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 200)); });
      await page.addInitScript(seed => {
        window.events = [];
        window.FlutterChannel = { postMessage: m => window.events.push(JSON.parse(m)) };
        window.requestAnimationFrame = () => 0;
        // Deterministic randomness for the whole engine.
        let s = seed * 2654435761 % 2147483647 || 1;
        Math.random = () => (s = s * 16807 % 2147483647) / 2147483647;
      }, seed);
      await page.route('**/game.js', async route => {
        // The local static server now and then resets a connection: retry.
        let response;
        for (let attempt = 0; ; attempt++) {
          try { response = await route.fetch(); break; } catch (e) { if (attempt >= 4) throw e; await new Promise(r => setTimeout(r, 500)); }
        }
        const body = (await response.text()).replace('  // Run init on DOM ready', `
        // Every collision with its circumstances: who hit whom.
        const __collisions = [];
        const __handleCollision = handleCollision;
        handleCollision = (actor, key) => {
          const p = playerCarGroup.position, yaw = playerCarGroup.rotation.y;
          const a = actor.mesh.getWorldPosition(new THREE.Vector3());
          const fwd = Math.sin(yaw) * (a.x - p.x) + Math.cos(yaw) * (a.z - p.z);
          __collisions.push({ t: +(window.__drive?.t || 0).toFixed(2), type: actor.config.type, id: actor.config.id, playerSpeed: +state.speed.toFixed(2),
            px: +p.x.toFixed(2), pz: +p.z.toFixed(2), pyaw: +yaw.toFixed(2), ax: +a.x.toFixed(2), az: +a.z.toFixed(2),
            ayaw: +actor.mesh.rotation.y.toFixed(2), choice: state.resolution?.simpleChoice, path: !!state.autoPath,
            held: !!actor.held, active: !!actor.active, waits: !!actor.waitsForPlayer,
            actorSpeed: +(actor.speed || 0).toFixed(2), ahead: +fwd.toFixed(1), crashed: !!actor.crashed,
            where: state.resolution ? 'junction ' + state.resolution.intersection.situation.id + ' ' + state.resolution.phase
              : state.roadEvent ? 'road ' + state.roadEvent.kind + '/' + state.roadEvent.phase : 'road' });
          return __handleCollision(actor, key);
        };
        window.__soak = {
          collisions: __collisions,
          state, THREE, get player() { return playerCarGroup; },
          playerOnRoad: () => playerOnRoad(),
          // One frame of the real loop (animate() without requestAnimationFrame).
          step(dt, time) {
            if (reveal) { updateReveal(dt); return; }
            if (state.paused) return;
            updateAttract(dt);
            updateActors(dt);
            if (state.resolution) updateResolution(dt);
            else updatePlayerMovement(dt);
            updateRoadEvent(dt);
            updateWeather(dt);
            updateBlinkers(dt);
            updateMistakeHighlight(dt);
            gameAudio?.update(dt, time);
            state.roadSegments.forEach(seg => seg.traverse(obj => {
              if (obj.userData.beacons) obj.userData.beacons.forEach((lamp, i) => { lamp.visible = Math.floor(time * 1000 / 180 + i) % 2 === 0; });
            }));
            terrainMesh.position.z = playerCarGroup.position.z + 500;
            updateCamera(dt);
            checkAndSpawnNext();
          },
          render() { renderer.render(scene, camera); },
          shot() { renderer.render(scene, camera); return renderer.domElement.toDataURL('image/png'); },
          info() {
            let objects = 0; scene.traverse(() => objects++);
            return { geometries: renderer.info.memory.geometries, textures: renderer.info.memory.textures, signCache: signTextureCache.size,
              objects, segments: state.roadSegments.length, actors: state.actors.length,
              ambient: state.ambient.length, props: state.props.length, crews: (state.crews || []).length,
              blockers: (state.blockers || []).length, trail: (state.trail || []).length,
              paused: state.paused, atSituation: state.isAtSituation, reveal: reveal ? reveal.phase : null,
              res: state.resolution ? state.resolution.phase + '/' + state.resolution.intersection.situation.id : null,
              ev: state.roadEvent ? state.roadEvent.kind + '/' + state.roadEvent.phase : null,
              active: state.activeIntersection ? state.activeIntersection.situation.id : null,
              speed: +state.speed.toFixed(2), z: +playerCarGroup.position.z.toFixed(1),
              x: +playerCarGroup.position.x.toFixed(2), yaw: +playerCarGroup.rotation.y.toFixed(2),
              steer: state.steering, center: state.resolution ? +(playerCarGroup.position.z - state.resolution.intersection.centerZ).toFixed(1) : null,
              geometry: state.resolution ? state.resolution.intersection.situation.geometry || '' : null,
              maneuver: state.resolution ? state.resolution.spec.maneuver : null };
          },
        };
        // Run init on DOM ready`);
        await route.fulfill({ response, body });
      });
      for (let attempt = 0; ; attempt++) {
        try { await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/'); break; }
        catch (e) { if (attempt >= 4) throw e; await new Promise(r => setTimeout(r, 1000)); }
      }
      await page.waitForFunction(() => window.events.some(e => e.event === 'ready'));
      // Start a run the way the app does.
      await page.evaluate(free => {
        window.game.configure({ labels: {} });
        window.game.setAttract(false);
        window.game.setSimpleSteering(!free);
        window.game.setViewportInsets({ top: 110, bottom: 260 });
        window.game.setPaused(false);
      }, free);

      const frames = Math.round(minutes * 60 * 60);
      const chunk = 60 * 20; // 20 s per evaluate
      const result = { seed, free, answered: 0, wrong: 0, stuck: [], offroad: [], nonFinite: null, resets: 0,
        violations: {}, info: [], distance: 0, exits: 0, refused: 0 };
      if (process.env.SOAK_SHOTS_AT) await page.evaluate(at => { window.__shotAt = at; }, process.env.SOAK_SHOTS_AT.split(',').map(Number));
      await page.evaluate(free => {
        window.__drive = { t: 0, pending: [], mark: 0, lastProgress: { t: 0, d: 0 }, offSince: null, free,
          pressedFor: null, answerAt: null, nextPauseAt: 150 + Math.random() * 120, pauseUntil: null,
          lobbyUntil: null, stuck: [], offroad: [], resets: 0, answered: 0, wrong: 0, violations: {}, refused: 0,
          rnd: Math.random };
      }, free);
      for (let done = 0; done < frames; done += chunk) {
        const out = await page.evaluate(n => {
          const S = window.__soak, D = window.__drive, s = S.state, dt = 1 / 60;
          for (let f = 0; f < n; f++) {
            D.t += dt;
            // Events from the engine, as the app would see them.
            while (D.mark < window.events.length) {
              const e = window.events[D.mark++];
              if (e.event === 'approach_situation') D.pending.push({ id: e.situation.id, at: D.t + 1.5 + D.rnd() * 2, correct: D.rnd() < 0.75 });
              else if (e.event === 'violation') {
                D.violations[e.type] = (D.violations[e.type] || 0) + 1;
                (D.vlog ||= []).push([+D.t.toFixed(1), e.type, +S.player.position.x.toFixed(2), +S.player.position.z.toFixed(1), s.resolution ? s.resolution.intersection.situation.id : s.roadEvent?.kind]);
              }
              else if (e.event === 'maneuver_reset') D.resets++;
              else if (e.event === 'input_refused') D.refused++;
              if (e.event === 'exit_choice' || e.event === 'situation_cleared' || e.event === 'approach_situation') {
                (D.vlog ||= []).push([+D.t.toFixed(1), e.event, +S.player.position.x.toFixed(2), +S.player.position.z.toFixed(1),
                  e.event === 'exit_choice' ? e.choice + '/' + e.hint + '/' + e.uturn : e.situationId || e.situation?.id, s.resolution ? s.resolution.spec.maneuver : null]);
              }
              if (e.event === 'exit_choice' && e.hint && !D.free) {
                const r = s.resolution;
                if (r && D.pressedFor !== r) {
                  D.pressedFor = r;
                  if (e.hint === 'uturn') window.game.chooseUturn(); else window.game.changeLane(e.hint);
                }
              }
            }
            // Answers: right ones go on at once, wrong ones release the
            // traffic first and go on after the "explanation".
            for (const p of D.pending) {
              if (p.done || D.t < p.at) continue;
              if (p.correct) { window.game.proceedAfterAnswer(true, p.id); p.done = true; D.answered++; }
              else if (!p.released) { window.game.releaseTraffic(p.id); p.released = true; p.at = D.t + 2.5; }
              else { window.game.proceedAfterAnswer(false, p.id); p.done = true; D.answered++; D.wrong++; }
            }
            D.pending = D.pending.filter(p => !p.done);
            // Now and then: a pause, or the garage opened mid-run.
            if (D.t > D.nextPauseAt && !D.pauseUntil && !D.lobbyUntil) {
              if (D.rnd() < 0.5) { window.game.setPaused(true); D.pauseUntil = D.t + 3; }
              else { window.game.setPaused(true); window.game.showLobby('hatch', 'red'); D.lobbyUntil = D.t + 4; }
              D.nextPauseAt = D.t + 150 + D.rnd() * 150;
            }
            if (D.pauseUntil && D.t > D.pauseUntil) { window.game.setPaused(false); D.pauseUntil = null; }
            if (D.lobbyUntil && D.t > D.lobbyUntil) { window.game.hideLobby(); window.game.setPaused(false); D.lobbyUntil = null; }
            // Driving: gas, giving way a few seconds after an answer.
            const r = s.resolution;
            const wait = r && r.phase === 'manual' && r.elapsed < 3 && r.yielding.some(a => !a.cleared && !a.done);
            window.game.setGas(!s.paused && !wait);
            if (D.free && !s.paused) {
              // Free steering: follow the planned route at a junction, else
              // keep to the lane centre; the arrows are a wheel.
              const p = S.player.position, yaw = S.player.rotation.y;
              let target;
              if (r && r.path) {
                let best = 0, bd = Infinity;
                for (let u = 0; u <= 1; u += 0.01) { const d = r.path.getPointAt(u).distanceTo(p); if (d < bd) { bd = d; best = u; } }
                target = best > 0.95 ? r.path.getPointAt(1).addScaledVector(r.path.getTangentAt(1), 15) : r.path.getPointAt(Math.min(1, best + 3 / r.length));
              } else {
                const back = Math.cos(yaw) < 0 ? -1 : 1;
                target = new S.THREE.Vector3(back > 0 ? -1.8 : 1.8, 0, p.z + back * 10);
              }
              const heading = Math.atan2(target.x - p.x, target.z - p.z);
              const err = Math.atan2(Math.sin(heading - yaw), Math.cos(heading - yaw));
              window.game.setSteering(Math.max(-1, Math.min(1, err * 3)));
            }
            S.step(dt, D.t);
            if (f % 60 === 0) S.render();
            if (window.__shotAt && D.t >= window.__shotAt[0] && D.t < window.__shotAt[1] && f % 15 === 0) {
              (window.__shots ||= []).push([+D.t.toFixed(2), S.shot()]);
            }
            // Watch.
            const p = S.player.position;
            if (![p.x, p.z, s.speed, S.player.rotation.y].every(Number.isFinite)) return { nonFinite: [p.x, p.z, s.speed] };
            if (s.paused || s.isAtSituation) { D.lastProgress = { t: D.t, d: s.distanceTraveled }; }
            else if (s.distanceTraveled > D.lastProgress.d + 5) D.lastProgress = { t: D.t, d: s.distanceTraveled };
            else if (D.t - D.lastProgress.t > 45) {
              D.stuck.push({ t: Math.round(D.t), x: +p.x.toFixed(1), z: +p.z.toFixed(1), yaw: +S.player.rotation.y.toFixed(2),
                speed: +s.speed.toFixed(2), res: r ? r.phase + '/' + r.intersection.situation.id + '/' + r.simpleChoice : null,
                ev: s.roadEvent ? s.roadEvent.kind + '/' + s.roadEvent.phase : null, onRoad: S.playerOnRoad() });
              D.lastProgress = { t: D.t, d: s.distanceTraveled };
            }
            if (!s.paused && !S.playerOnRoad()) {
              D.offSince ??= D.t;
              if (D.t - D.offSince > 10) {
                D.offroad.push({ t: Math.round(D.t), x: +p.x.toFixed(1), z: +p.z.toFixed(1), res: r ? r.intersection.situation.id : null });
                D.offSince = D.t;
              }
            } else D.offSince = null;
          }
          return { info: { ...S.info(), pending: D.pending.length, pauseUntil: D.pauseUntil, lobbyUntil: D.lobbyUntil }, t: Math.round(D.t), distance: Math.round(s.distanceTraveled) };
        }, Math.min(chunk, frames - done));
        if (out.nonFinite) { result.nonFinite = out.nonFinite; break; }
        result.info.push({ t: out.t, ...out.info });
        result.distance = out.distance;
      }
      if (process.env.SOAK_SHOTS_AT) {
        const shots = await page.evaluate(() => window.__shots || []);
        shots.forEach(([t, url], i) => require('node:fs').writeFileSync(process.env.SOAK_SHOT + '_' + seed + '_' + String(i).padStart(2, '0') + '_' + t + '.png', Buffer.from(url.split(',')[1], 'base64')));
      }
      if (process.env.SOAK_SHOT) require('node:fs').writeFileSync(process.env.SOAK_SHOT + '_' + seed + '.png', Buffer.from((await page.evaluate(() => window.__soak.shot())).split(',')[1], 'base64'));
      Object.assign(result, await page.evaluate(() => {
        const D = window.__drive;
        return { answered: D.answered, wrong: D.wrong, stuck: D.stuck, offroad: D.offroad, resets: D.resets, violations: D.violations, refused: D.refused,
          collisions: window.__soak.collisions, vlog: D.vlog || [] };
      }));
      result.errors = errors.slice(0, 10);
      result.consoleErrors = [...new Set(consoleErrors)].slice(0, 10);
      report.push(result);
      await page.close();
    }
  } finally {
    await browser.close();
  }
  for (const r of report) {
    const first = r.info[0] || {}, last = r.info[r.info.length - 1] || {};
    console.log(JSON.stringify({ seed: r.seed, free: r.free, answered: r.answered, wrong: r.wrong, distanceM: r.distance,
      resets: r.resets, refused: r.refused, violations: r.violations, stuck: r.stuck, offroad: r.offroad.slice(0, 6),
      nonFinite: r.nonFinite, errors: r.errors, consoleErrors: r.consoleErrors,
      growth: { geometries: [first.geometries, last.geometries], textures: [first.textures, last.textures],
        objects: [first.objects, last.objects], segments: [first.segments, last.segments], actors: [first.actors, last.actors],
        ambient: [first.ambient, last.ambient], props: [first.props, last.props], blockers: [first.blockers, last.blockers] } }));
    if (process.env.SOAK_VLOG) r.vlog.forEach(v => console.log('  violation', JSON.stringify(v)));
    if (process.env.SOAK_COLLISIONS) r.collisions.forEach(c => console.log('  collision', JSON.stringify(c)));
    if (process.env.SOAK_TRACE) r.info.forEach(i => console.log('  trace', JSON.stringify(i)));
    if (process.env.SOAK_SERIES) console.log('  series', JSON.stringify(r.info.filter((_, i) => i % 6 === 5).map(i => [i.t, i.geometries, i.textures, i.signCache, i.objects, i.segments, i.actors, i.ambient])));
  }
  if (process.env.SOAK_ASSERT) {
    for (const r of report) {
      assert.deepEqual(r.errors, [], 'engine errors');
      assert.equal(r.nonFinite, null, 'non-finite state');
      assert.deepEqual(r.stuck, [], 'stuck');
    }
    console.log('PASS: soak');
  }
})().catch(error => { console.error(error); process.exit(1); });
