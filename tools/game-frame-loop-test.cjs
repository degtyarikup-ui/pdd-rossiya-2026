// Regression coverage for the production animate() loop and host pause API.
// Run with NODE_PATH pointing at Playwright and GAME_URL at a local repo server.
// Only the HTTP response gets instrumentation; no debug API ships in the app.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium, webkit } = require('playwright');

(async () => {
  const browser = await (process.env.GAME_BROWSER === 'webkit' ? webkit.launch({ headless: true }) : chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] }));
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0;
      window.events = [];
      window.FlutterChannel = { postMessage: message => events.push(JSON.parse(message)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const source = process.env.GAME_SCRIPT ? fs.readFileSync(process.env.GAME_SCRIPT, 'utf8') : await response.text();
      assert(source.includes('  // Run init on DOM ready'), 'engine instrumentation anchor');
      // Frame timing/bridge checks do not need GPU output, including init's
      // first render; all production animation and simulation still run.
      const body = source.replaceAll('renderer.render(scene, camera);', '')
        .replace('  // Run init on DOM ready', `
        window.frameTest = {
          state,
          time: 0,
          get lastTime() { return lastTime; },
          question({ weak = false, struggling = false } = {}) {
            resetGame();
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.intersections = [];
            const situation = SITUATIONS.find(s => s.id === 'ticket_3_13');
            situationBag = [situation]; buildInitialTrack();
            state.weak = weak; quality.struggling = struggling;
            state.nativeControls = false;
            window.game.setPaused(false);
            const it = state.intersections[0];
            playerCarGroup.position.set(it.situation.playerStartX ?? -1.8, 0, it.stopZ);
            playerCarGroup.rotation.y = 0;
            updatePlayerMovement(0);
            // Drawing is irrelevant to the timing/bridge contract. Keep all
            // production frame, physics, scenery and camera logic running.
            renderer.render = () => {};
            events.length = 0;
            return it.situation.id;
          },
          frame(seconds) { this.time += seconds * 1000; animate(this.time); },
          frames(count, fps = 60) { for (let i = 0; i < count; i++) this.frame(1 / fps); },
          deadEnd() {
            const road = buildDeadEndSegment();
            const houses = road.children.filter(o => o.userData.cameraOccluder);
            const result = { deadEnd: road.userData.deadEnd,
              length: road.userData.roadEnds[1].z, houses: houses.length,
              decorated: houses.every(o => o.userData.sceneryObject && o.children.length > 0) };
            disposeSegment(road);
            return result;
          }
        };
        situationBag = [SITUATIONS.find(s => s.id === 'ticket_3_13')];
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => events.some(e => e.event === 'engine_error') ||
      window.frameTest && events.some(e => e.event === 'ready'), null, { polling: 100, timeout: 90000 });
    assert.deepEqual(errors, [], 'engine initializes without exceptions');

    const timing = await page.evaluate(() => {
      const t = frameTest, results = [];
      for (const fps of [60, 120]) {
        for (const profile of [{ weak: true }, { struggling: true }]) {
          const id = t.question(profile);
          window.game.setPaused(true);
          window.game.proceedAfterAnswer(true, id);
          const queued = !!t.state.pendingAnswer && !t.state.resolution;
          t.frames(fps, fps);
          window.game.setPaused(false);
          const resumed = !t.state.pendingAnswer && !!t.state.resolution;
          t.frame(1 / fps);
          const seededClock = Number.isFinite(t.lastTime);
          t.frames(fps, fps);
          const elapsed = t.state.resolution?.elapsed ?? 0;
          window.game.setPaused(true);
          t.time += 3600 * 1000; // backgrounded with no animation frames
          window.game.setPaused(false); t.frame(1 / fps);
          const backgroundGapIgnored = Math.abs(t.state.resolution.elapsed - elapsed) < 1e-9;
          const startDistance = t.state.distanceTraveled;
          window.game.releaseTraffic(id);
          for (let f = 0; f < fps * 40 && t.state.resolution; f++) {
            window.game.setGas(t.state.speed < 4);
            t.frame(1 / fps);
          }
          window.game.setGas(false);
          results.push({ id, fps, profile, queued, resumed, seededClock, elapsed, backgroundGapIgnored,
            moved: t.state.distanceTraveled - startDistance,
            remaining: t.state.resolution && { elapsed: t.state.resolution.elapsed,
              recovery: t.state.resolution.recovery, faults: [...t.state.resolution.faults] },
            finished: !t.state.isAtSituation && !t.state.resolution,
            cleared: events.filter(e => e.event === 'situation_cleared' && e.situationId === id).length });
        }
      }
      return results;
    });
    for (const result of timing) {
      const label = JSON.stringify(result);
      assert(result.queued && result.resumed, 'paused answer survives resume: ' + label);
      assert(result.seededClock, 'first resumed frame establishes the clock: ' + label);
      assert(result.elapsed > 0.8, 'standing resolution advances after resume: ' + label);
      assert(result.backgroundGapIgnored, 'background wall time does not advance the maneuver: ' + label);
      assert(result.moved > 30 && result.finished, 'gas completes the resumed maneuver: ' + label);
      assert.equal(result.cleared, 1, 'Flutter receives exactly one matching situation_cleared: ' + label);
    }

    const recovery = await page.evaluate(() => {
      const t = frameTest;
      t.question({ weak: true });
      t.state.driveRecovery = 0.38;
      t.state.driveFaults.add('offroad');
      window.game.setPaused(true); window.game.setPaused(false);
      t.frames(60);
      const completed = t.state.driveRecovery === 0 && t.state.driveFaults.size === 0;
      t.frames(60);
      return { completed, ready: events.filter(e => e.event === 'maneuver_ready').length };
    });
    assert.deepEqual(recovery, { completed: true, ready: 1 }, 'crash recovery finishes while the next question is displayed');

    const deadEnd = await page.evaluate(() => frameTest.deadEnd());
    assert.deepEqual(deadEnd, { deadEnd: true, length: 38, houses: 3, decorated: true },
      'a randomly offered dead-end exit builds without a missing scenery factory');

    const visibility = await page.evaluate(() => {
      const t = frameTest;
      const visible = hidden => {
        Object.defineProperty(document, 'hidden', { configurable: true, value: hidden });
        document.dispatchEvent(new Event('visibilitychange'));
      };
      const id = t.question({ weak: true });
      window.game.configure({ soundEnabled: false });
      window.game.proceedAfterAnswer(true, id);
      window.game.setPaused(true); window.game.setPaused(false);
      // WKWebView may send its stale hidden event after Flutter has resumed.
      visible(true); t.frames(60);
      const lateHiddenIgnored = !t.state.paused && t.state.resolution.elapsed > 0.8;
      window.game.setPaused(true); visible(false); t.frames(60);
      const hostPauseKept = t.state.paused;
      visible(true); window.game.setPaused(false); t.frames(60);
      const hiddenPropertyIgnoredOnResume = !t.state.paused;
      // The standalone scene has no Flutter lifecycle observer.
      t.state.nativeControls = false;
      visible(true); const standaloneHiddenPaused = t.state.paused;
      visible(false); const standaloneVisibleResumed = !t.state.paused;
      return { lateHiddenIgnored, hostPauseKept, hiddenPropertyIgnoredOnResume,
        standaloneHiddenPaused, standaloneVisibleResumed };
    });
    assert.deepEqual(visibility, { lateHiddenIgnored: true, hostPauseKept: true,
      hiddenPropertyIgnoredOnResume: true, standaloneHiddenPaused: true, standaloneVisibleResumed: true });
    assert.deepEqual(errors, [], 'no engine exceptions');
    console.log(JSON.stringify({ timing, recovery, deadEnd, visibility }, null, 2));
    console.log('PASS: production frame loop, paused answer, weak/adaptive profiles, recovery, dead-end scene, host lifecycle and Flutter clear event');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
