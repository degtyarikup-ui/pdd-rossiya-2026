// Regression: a gas station must not turn the rest of the road into kerb.
// Its lowered-pavement test ignored X and the station's length, so after one
// was built the car hit an invisible kerb on any straight (after a junction or
// a roundabout) and could not move on.
//
//   NODE_PATH=<dir with playwright> node tools/game_tests/game-gas-station-kerb-test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {chromium} = require('playwright');

const ROOT = path.resolve(__dirname, '../..');
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
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.goto(lab.url + '/game/index.html');
    await page.waitForFunction(() => window.__lab?.run('!!playerCarGroup'), null, {timeout: 90000});
    const result = await page.evaluate(() => __lab.run(`(() => {
      renderer.render = () => {};
      let t = 5000; const f = n => { for (let i = 0; i < n; i++) { t += 1000 / 60; animate(t); } };
      __lab.show('ticket_1_13'); processSceneryJobs(1e9); state.paused = false; window.game.setSimpleSteering(true);
      state.forceRoadEvent = 'gasstation'; state.roadTurn = 1;
      window.game.proceedAfterAnswer(true, 'ticket_1_13');
      for (let i = 0; i < 4000 && state.resolution; i++) { window.game.setGas(state.speed < 6); f(1); }
      const ev = state.roadEvent, z0 = playerCarGroup.position.z;
      const station = ev && ev.kind === 'gasstation' ? ev.stationZ : null;
      // The carriageway before, beside and after the station is road; the raised pavement is not.
      const lane = z => roadSupports(new THREE.Vector3(-1.8, 0, z));
      const carriageway = [z0 + 2, station - 10, station, station + 10].every(lane);
      const pavement = !roadSupports(new THREE.Vector3(-5.8, 0, station - 4));
      const start = playerCarGroup.position.clone();
      for (let i = 0; i < 600; i++) { window.game.setGas(true); f(1); }
      return { station, carriageway, pavement, moved: playerCarGroup.position.distanceTo(start) };
    })()`));
    console.log(JSON.stringify(result));
    assert(result.station !== null, 'a gas station is built after the junction');
    assert(result.carriageway, 'the carriageway around the station is road');
    assert(result.pavement, 'the pavement beside the forecourt is not');
    assert(result.moved > 60, 'the car drives on past the station');
    assert.deepEqual(errors, []);
    console.log('PASS: gas station kerb stays on its pavement');
  } finally {
    await browser.close();
    lab.stop();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
