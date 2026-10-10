// Real browser regression for the dead end (sign 6.8.x) of tickets 8·4 and 9·14.
//
// The sign promises a street that goes nowhere, so the game must build exactly
// that: a closed street whose end is a turning pad, with nothing beyond it (no
// next junction, no road event, no road to drive off on), a pad wide enough to
// turn round on by hand, and a U-turn button that drives the same loop.
//
//   NODE_PATH=<dir with playwright> node tools/game-deadend-test.cjs
//   GAME_LAB_URL=http://127.0.0.1:8940   use a lab server that is already running
//   DEADEND_SHOTS=output/game-review/dead-end   also save screenshots of each step
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {chromium} = require('playwright');

const ROOT = path.resolve(__dirname, '..');
const SHOTS = process.env.DEADEND_SHOTS ? path.resolve(ROOT, process.env.DEADEND_SHOTS) : null;
const CHROME = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => { const {port} = server.address(); server.close(() => resolve(port)); });
  });
}

async function startLab() {
  if (process.env.GAME_LAB_URL) return {url: process.env.GAME_LAB_URL, stop() {}};
  const port = await freePort();
  const proc = spawn('python3', ['tools/game_lab/server.py'], {cwd: ROOT, env: {...process.env, GAME_LAB_PORT: String(port)}, stdio: 'ignore'});
  const url = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 100; i++) {
    const up = await new Promise(resolve => http.get(url + '/', res => { res.resume(); resolve(true); }).on('error', () => resolve(false)));
    if (up) return {url, stop: () => proc.kill()};
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  proc.kill();
  throw new Error('lab server did not start');
}

(async () => {
  const lab = await startLab();
  const browser = await chromium.launch({headless: true, executablePath: CHROME, args: ['--use-angle=swiftshader']});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}});
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    // The production frame loop is driven by hand; drawing is irrelevant to the
    // physics, so it is switched off except for the optional screenshots.
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.goto(lab.url + '/game/index.html');
    await page.waitForFunction(() => window.__lab?.run('!!playerCarGroup'), null, {timeout: 90000});
    const run = code => page.evaluate(c => __lab.run(c), code);
    await run(`
      window.__events = [];
      window.FlutterChannel = { postMessage: m => { const e = JSON.parse(m); if (e.event === 'violation') e.pose = window.__T.pose(); window.__events.push(e); } };
      window.__draw = renderer.render.bind(renderer); renderer.render = () => {};
      window.__T = { t: 5000,
        frames(n, fps = 60) { for (let i = 0; i < n; i++) { this.t += 1000 / fps; animate(this.t); } },
        draw() { window.__draw(scene, camera); },
        pose() {
          const c = currentCorridor, p = c.worldToLocal(playerCarGroup.position.clone());
          const h = c.worldToLocal(playerCarGroup.position.clone().add(new THREE.Vector3(Math.sin(playerCarGroup.rotation.y), 0, Math.cos(playerCarGroup.rotation.y))));
          return { x: +p.x.toFixed(2), z: +p.z.toFixed(2), head: +Math.atan2(h.x - p.x, h.z - p.z).toFixed(2) };
        },
        snap() {
          return Object.assign(this.pose(), { speed: +state.speed.toFixed(2), auto: !!state.autoPath, ahead: !!deadEndAhead(), onRoad: playerOnRoad(),
            intersections: state.intersections.length, event: state.roadEvent?.kind || null, segments: state.roadSegments.length, button: deadEndTurnOffered() });
        },
        // Turn right into the dead end of a scenario by the arrow, as the app does.
        enter(id) {
          __lab.show(id); processSceneryJobs(1e9); state.paused = false; window.game.setSimpleSteering(true);
          window.game.proceedAfterAnswer(true, id); window.game.changeLane('right');
          for (let i = 0; i < 3000 && (state.resolution || !currentCorridor?.userData.deadEnd); i++) { window.game.setGas(state.speed < 5); this.frames(1); }
          window.game.setGas(false); window.__events.length = 0;
        },
        // Drive on at walking pace until the car is at this distance into the street.
        driveTo(z, fps = 60) {
          for (let i = 0; i < 4000; i++) {
            const s = this.pose(); if (s.z >= z) return s;
            window.game.setGas(state.speed < 4.5); this.frames(3, fps);
          }
          return this.pose();
        } };
    `);
    const snap = () => run('__T.snap()');
    const events = type => page.evaluate(t => window.__events.filter(e => e.event === t), type);
    let shot = 0;
    const capture = async name => {
      if (!SHOTS) return;
      fs.mkdirSync(SHOTS, {recursive: true});
      await run('__T.draw()');
      await page.screenshot({path: path.join(SHOTS, String(++shot).padStart(2, '0') + '-' + name + '.png')});
    };

    // 1. What is built: the street, the pad, the garages, and little else than that.
    for (const id of ['ticket_8_4', 'ticket_9_14']) {
      const built = await run(`(() => {
        __lab.show(${JSON.stringify(id)}); processSceneryJobs(1e9);
        const road = state.intersections[0].previews.right, info = road.userData.deadEnd;
        let meshes = 0, triangles = 0, garages = 0, houses = 0;
        road.traverse(o => {
          if (o.userData.garageRow) garages++;
          if (o.userData.cameraOccluder) houses++;
          if (o.isMesh && o.visible) { meshes++; const g = o.geometry; triangles += (g.index ? g.index.count : g.attributes.position.count) / 3; }
        });
        const left = state.intersections[0].previews.left;
        return { info, garages, houses, meshes, triangles: Math.round(triangles), leftIsDead: !!left.userData.deadEnd };
      })()`);
      console.log(id, JSON.stringify(built));
      assert.equal(built.info.length, 66, id + ': length of the dead end');
      assert(built.info.radius >= 10, id + ': the turning pad is at least 20 m across');
      assert.equal(built.garages, 1, id + ': the street is closed by a row of garages');
      assert(built.houses >= 8, id + ': homes along the street and round the pad');
      assert(built.meshes <= 170 && built.triangles <= 40000, id + ': draw call and triangle budget (' + built.meshes + ' meshes, ' + built.triangles + ' triangles)');
      assert.equal(built.leftIsDead, false, id + ': only the street the sign shows is closed');
    }

    // 2. The scenery is streamed in small steps and does not stall the frame.
    const streamed = await run(`(() => {
      __lab.show('ticket_8_4'); state.paused = false; streamScenery = true;
      const t0 = performance.now(), road = buildDeadEndSegment(), sync = performance.now() - t0;
      const queued = sceneryJobs.filter(j => j.owner === road).length;
      let worst = 0, steps = 0;
      while (sceneryJobs.some(j => j.owner === road)) { const a = performance.now(); processSceneryJobs(0.001); worst = Math.max(worst, performance.now() - a); steps++; if (steps > 200) break; }
      const lamps = [];
      road.children.forEach(o => { if (o.userData.streetLamp) lamps.push([+o.position.x.toFixed(2), +o.position.z.toFixed(2), +o.rotation.y.toFixed(2)]); });
      disposeSegment(road);
      state.paused = true;
      const eager = buildDeadEndSegment(), eagerLamps = [];
      eager.children.forEach(o => { if (o.userData.streetLamp) eagerLamps.push([+o.position.x.toFixed(2), +o.position.z.toFixed(2), +o.rotation.y.toFixed(2)]); });
      const eagerJobs = sceneryJobs.filter(j => j.owner === eager).length;
      disposeSegment(eager);
      state.paused = false;
      return { sync: +sync.toFixed(1), queued, steps, worst: +worst.toFixed(1), lamps, eagerLamps, eagerJobs };
    })()`);
    console.log('streaming', JSON.stringify({...streamed, lamps: streamed.lamps.length, eagerLamps: streamed.eagerLamps.length}));
    assert(streamed.sync < 30, 'surfaces are laid in under 30 ms, the scenery follows in steps (' + streamed.sync + ' ms)');
    assert(streamed.queued > 0 && streamed.eagerJobs === 0, 'streamed while the game runs, built at once while it is paused');
    assert(streamed.steps >= 5 && streamed.worst < 80, 'no single scenery step stalls a frame (' + streamed.worst + ' ms)');
    assert.equal(streamed.lamps.length, 4, 'four lamps, in the street and at the pad');
    // The same lamps, mirrored the same way, whether the road was built eagerly or streamed.
    const key = l => l.map(String).join(',');
    assert.deepEqual(streamed.lamps.map(key).sort(), streamed.eagerLamps.map(key).sort(), 'eager and streamed builds place the lamps alike');

    // 3. The street ends: no junction, no road event, no road beyond the garages.
    await run('__T.enter("ticket_8_4")');
    await capture('entered');
    let s = await snap();
    assert(s.ahead && s.intersections === 0 && s.event === null, 'in the dead end, nothing is built beyond: ' + JSON.stringify(s));
    await run('__T.driveTo(10)');
    assert.equal((await snap()).button, false, 'no U-turn button in the first metres of the street');
    await run('window.game.chooseUturn()');
    assert.equal((await snap()).auto, false, 'the U-turn button is refused there');
    await run('__T.driveTo(34); window.game.setGas(false); __T.frames(120)');
    s = await snap();
    assert(s.segments <= 2 && s.intersections === 0 && s.event === null, 'still nothing built ahead of the car: ' + JSON.stringify(s));
    const beyond = await run(`(() => {
      const road = currentCorridor, info = road.userData.deadEnd; let n = 0, supported = 0;
      for (let z = info.centerZ + info.radius + 0.6; z <= info.length + 60; z += 1.5) for (let x = -50; x <= 50; x += 1.5) {
        n++; if (roadSupports(road.localToWorld(new THREE.Vector3(x, 0, z)))) supported++;
      }
      return { n, supported };
    })()`);
    assert(beyond.n > 3000 && beyond.supported === 0, 'no road at all beyond the end of the pad: ' + JSON.stringify(beyond));
    // Full gas at the garages from the middle of the pad: the car stops short of them.
    await run(`(() => { const road = currentCorridor, info = road.userData.deadEnd;
      state.autoPath = null; state.speed = 0; playerCarGroup.rotation.y = 0;
      playerCarGroup.position.copy(road.localToWorld(new THREE.Vector3(-3, 0, info.centerZ + 2))); __T.frames(2); })()`);
    let farthest = 0, offRoad = 0;
    for (let i = 0; i < 100; i++) {
      s = await run('window.game.setGas(true); __T.frames(12); __T.snap()');
      farthest = Math.max(farthest, s.z); if (!s.onRoad) offRoad++;
    }
    await capture('against-the-end');
    const info = await run('currentCorridor.userData.deadEnd');
    assert(farthest <= info.centerZ + info.radius, 'the car stops at the end of the pad, never beyond it (z ' + farthest + ')');
    assert.equal(offRoad, 0, 'the car never leaves the road surface');
    assert((await events('violation')).length > 0 && (await events('violation')).every(e => e.type === 'offroad'), 'driving at the kerb is a kerb fault');

    // 4. The U-turn button: offered from the street short of the pad, one smooth loop, out into the other lane.
    for (const fps of [60, 30]) {
      await run('__T.enter("ticket_8_4")');
      await run(`__T.driveTo(${info.turnFromZ + 1}, ${fps}); __T.frames(2, ${fps})`);
      s = await snap();
      assert(s.button, 'the U-turn button is offered at the street short of the pad: ' + JSON.stringify(s));
      const offered = (await events('exit_choice')).filter(e => e.uturn === true && e.hint === 'uturn');
      assert(offered.length >= 1, 'the controls are told to show it (and to pulse it)');
      await run('window.game.chooseUturn()');
      assert((await snap()).auto, 'the button starts the loop');
      assert.equal((await snap()).button, false, 'the button hides while the turn is under way');
      let off = 0, steps = 0, flippedInLoop = false;
      for (; steps < 800; steps++) {
        s = await run(`window.game.setGas(state.speed < 5); __T.frames(6, ${fps}); __T.snap()`);
        if (!s.onRoad) off++;
        if (!s.auto) break;
        if (!s.ahead) flippedInLoop = true;
      }
      await capture('turned-round-' + fps);
      assert(!s.auto && steps < 800, 'the loop ends by itself');
      assert.equal(flippedInLoop, false, 'the world is not turned round under the car while the loop is under way');
      assert.equal(off, 0, 'the whole loop is on the road');
      assert.deepEqual((await events('violation')), [], 'a clean U-turn: no faults at ' + fps + ' fps');
      s = await run(`window.game.setGas(state.speed < 5); __T.frames(6, ${fps}); __T.snap()`);
      assert(!s.ahead && s.intersections === 1, 'the world has turned round and the next junction stands at the mouth: ' + JSON.stringify(s));
      assert(Math.abs(Math.abs(s.head) - Math.PI) < 0.15 && Math.abs(s.x - 1.8) < 0.45, 'heading out of the street, in its other lane: ' + JSON.stringify(s));
      // And on to the junction, no fault on the way.
      let arrived = null;
      for (let i = 0; i < 600 && !arrived; i++) {
        await run(`window.game.setGas(state.speed < 6); __T.frames(8, ${fps})`);
        arrived = (await events('approach_situation'))[0];
      }
      assert(arrived, 'the car drives out to the new junction');
      assert.deepEqual((await events('violation')), [], 'no fault on the way out');
    }

    // 5. By hand: one held arrow turns the car round anywhere on the pad.
    for (const startZ of [32, 36, 40, 44]) {
      await run('__T.enter("ticket_8_4")');
      await run(`__T.driveTo(${startZ}); window.game.setSteering(1)`);
      let done = false;
      for (let i = 0; i < 300 && !done; i++) {
        s = await run('window.game.setGas(state.speed < 4.5); __T.frames(4); __T.snap()');
        done = Math.abs(s.head) > 2.9;
      }
      await run('window.game.setSteering(0)');
      assert(done, 'turned round by hand from z ' + startZ);
      for (let i = 0; i < 40; i++) s = await run('window.game.setGas(state.speed < 5); __T.frames(6); __T.snap()');
      assert(s.onRoad && Math.abs(s.x - 1.8) < 0.5 && Math.abs(Math.abs(s.head) - Math.PI) < 0.2, 'back in the street in the right lane after a manual U-turn from z ' + startZ + ': ' + JSON.stringify(s));
      assert.deepEqual((await events('violation')), [], 'no fault in a manual U-turn from z ' + startZ);
    }

    // 6. Turning back towards the garages never opens a road behind them.
    await run('__T.enter("ticket_8_4")');
    await run(`__T.driveTo(${info.turnFromZ + 1}); window.game.chooseUturn()`);
    for (let i = 0; i < 800 && (await snap()).auto; i++) await run('window.game.setGas(state.speed < 5); __T.frames(6)');
    await run('__T.frames(30)');
    s = await snap();
    assert(!s.ahead && s.intersections === 1, 'out of the dead end: ' + JSON.stringify(s));
    // The player turns round again (as they might at the junction) and heads for the closed end.
    await run(`(() => { state.speed = 0; state.autoPath = null; playerCarGroup.rotation.y = Math.PI; __T.frames(30); })()`);
    s = await snap();
    assert(s.ahead && s.intersections === 0 && s.segments === 1, 'heading for the closed end again: no junction is built there: ' + JSON.stringify(s));
    await run('window.game.setGas(true); __T.frames(600)');
    s = await snap();
    assert(s.ahead && s.intersections === 0 && s.event === null && s.segments <= 2, 'driving back in builds nothing beyond the end either: ' + JSON.stringify(s));

    assert.deepEqual(errors, [], 'no page errors');
    console.log('PASS: dead end of tickets 8·4 and 9·14 — closed street, turning pad, U-turn button, manual turns, streaming');
  } finally {
    await browser.close();
    lab.stop();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
