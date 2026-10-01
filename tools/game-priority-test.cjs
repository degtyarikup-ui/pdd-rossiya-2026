// Priority at ticket junctions: the source-ticket behaviour is never penalised,
// getting in the way of a participant the player must give way to is.
// Run with the same GAME_URL / NODE_PATH / CHROME_PATH setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
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
      window.__priorityTest = {
        state, player: () => playerCarGroup, actorFootprint, THREE,
        scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed),
        // Follows the task route like a careful driver; speed caps the gas.
        drive(speed = 4, maxFrames = 3000) {
          const r = state.resolution;
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
            window.game.setGas(!r.recovery && state.speed < speed);
            this.tick(1 / 60);
          }
          window.game.setGas(false); window.game.setSteering(0);
          return !state.resolution;
        },
        tick(seconds) {
          for (let i = 0; i < Math.ceil(seconds * 60); i++) {
            updateActors(1 / 60);
            if (state.resolution) updateResolution(1 / 60); else updatePlayerMovement(1 / 60);
            updateRoadEvent(1 / 60);
            updateCamera(1 / 60); checkAndSpawnNext();
          }
        },
        select(id) {
          resetGame();
          state.roadSegments.forEach(disposeSegment);
          state.roadSegments = []; state.intersections = [];
          situationBag = [SITUATIONS.find(s => s.id === id)]; buildInitialTrack();
          playerCarGroup.position.z = state.intersections[0].stopZ;
          updatePlayerMovement(0);
          state.paused = false;
        }
      };
      // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'));
    await page.evaluate(() => window.game.setPaused(true));

    // 1. Every enabled junction: waiting for the participants the ticket says
    // to give way to (until they pass, or stand aside for the player) and then
    // driving the task route costs no violation at all.
    const legal = await page.evaluate(() => {
      const t = window.__priorityTest, s = t.state, bad = [];
      window.game.setSimpleSteering(false);
      for (const sc of t.scenarios()) {
        t.select(sc.id);
        const mark = window.events.length;
        window.game.proceedAfterAnswer(true, sc.id);
        const r = s.resolution;
        for (let waited = 0; waited < 30 && !r.yielding.every(a => a.cleared || a.done || a.held); waited += 0.25) t.tick(0.25);
        const done = t.drive();
        const faults = window.events.slice(mark).filter(e => e.event === 'violation').map(e => e.type);
        if (!done || faults.length) bad.push({ id: sc.id, done, faults });
      }
      return bad;
    });
    assert.deepEqual(legal, [], 'Ticket-correct driving is never penalised');

    // 2. 8_14 (source image: motorcycle on the left, car on the right turning
    // left): the car moves off first and stops at the edge of the player's
    // road; the player passes, then the motorcycle, the car turns last.
    const staged = await page.evaluate(() => {
      const t = window.__priorityTest, s = t.state;
      t.select('ticket_8_14');
      window.game.proceedAfterAnswer(true, 'ticket_8_14');
      const [car, moto] = ['npc_car', 'npc_moto'].map(id => s.resolution.motions.find(a => a.config.id === id));
      t.tick(2);
      const carHeld = car.held && car.distance > 3 && car.speed === 0;
      // Its nose stays clear of the player's lane (x < -2.7).
      const carNose = t.actorFootprint(car).p.x + car.halfLength;
      const motoWaits = moto.distance === 0;
      const passed = t.drive(8);
      let motoFirst = null;
      for (let i = 0; i < 1200 && !(car.cleared && moto.cleared); i++) {
        t.tick(1 / 60);
        if (motoFirst === null && (car.cleared || moto.cleared)) motoFirst = moto.cleared && !car.cleared;
      }
      return { carHeld, carNose, motoWaits, passed, motoFirst };
    });
    assert.ok(staged.carHeld && staged.motoWaits && staged.passed && staged.motoFirst, JSON.stringify(staged));
    assert.ok(staged.carNose < -3.2, 'The waiting car leaves the player\'s lane free: ' + staged.carNose);

    // 3. 13_15: the player may turn left together with the truck (1.2 «не
    // создавать помех»), but cutting into its turn is flagged as not giving
    // way before the contact, not only as a crash.
    const rushed = await page.evaluate(() => {
      const t = window.__priorityTest;
      t.select('ticket_13_15');
      const mark = window.events.length;
      window.game.proceedAfterAnswer(true, 'ticket_13_15');
      t.drive(12);
      return window.events.slice(mark).filter(e => e.event === 'violation').map(e => e.type);
    });
    assert.equal(rushed[0], 'priority', 'Interference is named first: ' + rushed);

    // 4. Simple steering: a crash inside the junction keeps the exit the
    // player chose — the car carries on with the turn instead of running
    // straight past it into a wrong-manoeuvre fault.
    const crash = await page.evaluate(() => {
      const t = window.__priorityTest, s = t.state;
      window.game.setSimpleSteering(true);
      t.select('ticket_2_13');
      const mark = window.events.length;
      window.game.proceedAfterAnswer(true, 'ticket_2_13');
      window.game.changeLane('left');
      // The car slows for the turn now, and walkers are long gone when it
      // gets there: one stops dead on the turn's path, a few metres ahead.
      const walker = s.actors.find(a => a.config.type === 'pedestrian');
      let crashed = false, placed = false;
      for (let f = 0; f < 1800 && s.resolution; f++) {
        const ap = s.autoPath;
        if (!placed && walker && ap && ap.s > 6) {
          const p = ap.path.getPointAt(Math.min(1, (ap.s + 5) / ap.length));
          const local = walker.mesh.parent.worldToLocal(p.clone());
          walker.path = new t.THREE.CatmullRomCurve3([local, local.clone().add(new t.THREE.Vector3(0, 0, 0.01))]);
          walker.length = walker.path.getLength(); walker.distance = 0; walker.maxSpeed = 0; walker.done = false; walker.active = true;
          walker.mesh.position.copy(local);
          placed = true;
        }
        window.game.setGas(!s.resolution.recovery);
        t.tick(1 / 60);
        crashed ||= window.events.slice(mark).some(e => e.type === 'collision');
      }
      window.game.setGas(false);
      window.game.setSimpleSteering(false);
      return { crashed, faults: window.events.slice(mark).filter(e => e.event === 'violation').map(e => e.type),
        finished: !s.resolution, heading: t.player().rotation.y };
    });
    assert.ok(crash.crashed, 'The rushed turn hits the crossing pedestrian: ' + JSON.stringify(crash));
    assert.ok(crash.finished && !crash.faults.includes('wrong_maneuver') && !crash.faults.includes('offroad'),
      'After the crash the chosen left turn is completed: ' + JSON.stringify(crash));

    // 5. Simple steering on every enabled junction: the arrow for the task
    // pulses (never a turn by itself), pressing it once — the U-turn has its
    // own button — and giving way as the ticket says costs no violation.
    const simple = await page.evaluate(() => {
      const t = window.__priorityTest, s = t.state, bad = [];
      window.game.setSimpleSteering(true);
      for (const sc of t.scenarios()) {
        const task = window.PDD_SCENARIO_ROUTES[sc.id].maneuver;
        t.select(sc.id);
        const mark = window.events.length;
        window.game.proceedAfterAnswer(true, sc.id);
        const r = s.resolution;
        for (let w = 0; w < 30 && !r.yielding.every(a => a.cleared || a.done || a.held); w += 0.25) t.tick(0.25);
        t.tick(1 / 60);
        const hint = window.events.slice(mark).filter(e => e.event === 'exit_choice').map(e => e.hint).find(h => h) || null;
        const turnedAlone = r.simpleChoice !== (r.intersection.previews.straight ? 'straight' : null);
        // One press of the hinted button: the arrows, or the U-turn button.
        if (task === 'left') window.game.changeLane('left');
        if (task === 'uturn') window.game.chooseUturn();
        if (task === 'right') window.game.changeLane('right');
        for (let f = 0; f < 2400 && s.resolution; f++) { window.game.setGas(!s.resolution.recovery && s.speed < 9); t.tick(1 / 60); }
        window.game.setGas(false);
        const faults = window.events.slice(mark).filter(e => e.event === 'violation').map(e => e.type);
        const expectedHint = task === 'straight' ? null : task;
        if (s.resolution || faults.length || hint !== expectedHint || turnedAlone) bad.push({ id: sc.id, task, hint, faults, turnedAlone });
      }
      window.game.setSimpleSteering(false);
      return bad;
    });
    assert.deepEqual(simple, [], 'Simple steering follows the hinted arrows cleanly, U-turns included');

    assert.deepEqual(errors, []);
    console.log('PASS: priority follows the tickets; staged 8_14, 13_15 interference, route kept after a crash, simple steering with hints');
  } finally { await browser.close(); }
})();
