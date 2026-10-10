// Comparable before/after measurement of road scenes: draw calls, triangles,
// GPU textures/geometries and the median CPU+GPU time of one render.
// "before" serves output/game-textures/roads/baseline-src instead of the live
// engine. Software rendering (SwiftShader) on this computer: compare the two
// columns with each other, not with phone FPS.
const fs = require('node:fs');
const { chromium } = require('playwright');
const SRC = 'output/game-textures/roads/baseline-src/';
const SCENES = ['straight', 'ticket_1_13', 'ticket_16_14', 'ticket_22_13', 'ticket_21_15', 'road_2_16', 'road_15_3'];

async function measure(browser, variant) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  page.on('pageerror', e => console.error(variant, e.message));
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; window.events = []; window.FlutterChannel = { postMessage: m => events.push(JSON.parse(m)) }; });
  await page.route('**/assets/game/game.js', async route => {
    let body = fs.readFileSync(variant === 'before' ? SRC + 'baseline-game.js' : 'assets/game/game.js', 'utf8');
    body = body.replace('  // Run init on DOM ready', `window.bench = { run(fn, args) { return eval('(' + fn + ')')(...args); } }; // Run init on DOM ready`);
    await route.fulfill({ body, contentType: 'application/javascript' });
  });
  if (variant === 'before') await page.route('**/assets/game/index.html', route => route.fulfill({ body: fs.readFileSync(SRC + 'baseline-index.html', 'utf8'), contentType: 'text/html' }));
  await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8943') + '/assets/game/index.html');
  await page.waitForFunction(() => window.bench && events.some(e => e.event === 'ready'), null, { polling: 100 });
  const rows = [];
  for (const id of SCENES) {
    rows.push(await page.evaluate(([f, a]) => bench.run(f, a), [((id) => {
      let s = 9; Math.random = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
      window.game.setSeason('summer');
      resetGame(); state.attract = false; state.paused = true; state.roadSegments = []; state.actors = []; state.intersections = [];
      state.ambient = []; state.occluders = []; state.roadEvent = null; state.exitRoad = currentCorridor = null;
      if (id === 'straight') { const seg = buildStraightSegment(-45, 200, true); state.roadSegments.push(seg); playerCarGroup.position.set(-1.8, 0, 25); }
      else if (id.startsWith('ticket')) { situationBag = [SITUATIONS.find(s => s.id === id)]; buildInitialTrack(); playerCarGroup.position.set(-1.8, 0, state.intersections[0].stopZ); }
      else { const seg = buildStraightSegment(-45, 200, true); state.roadSegments.push(seg); state.exitRoad = currentCorridor = seg;
        const g = new THREE.Group(); scene.add(g); state.roadSegments.push(g); state.roadTurn = 1;
        const ev = state.roadEvent = buildQuestionEvent(g, -45, window.PDD_ROAD_SITUATIONS.find(s => s.id === id)); playerCarGroup.position.set(-1.8, 0, ev.stopZ); }
      for (let i = 0; i < 200; i++) updateCamera(1 / 60);
      const gl = renderer.getContext();
      renderer.render(scene, camera); renderer.render(scene, camera);
      const info = { calls: renderer.info.render.calls, triangles: renderer.info.render.triangles,
        textures: renderer.info.memory.textures, geometries: renderer.info.memory.geometries, programs: renderer.info.programs.length };
      const times = [];
      for (let i = 0; i < 40; i++) { const t = performance.now(); renderer.render(scene, camera); gl.finish(); times.push(performance.now() - t); }
      times.sort((a, b) => a - b);
      return { id, ...info, medianMs: +times[20].toFixed(2) };
    }).toString(), [id]]));
  }
  await page.close();
  return rows;
}

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const result = { environment: 'Chrome headless, SwiftShader (software GL), 390x844, this computer', scenes: SCENES, before: [], after: [] };
    // Alternate the variants to share any machine load evenly.
    for (let round = 0; round < 2; round++) for (const v of ['before', 'after']) {
      const rows = await measure(browser, v);
      if (!round) result[v] = rows; else rows.forEach((r, i) => { result[v][i].medianMs = +((result[v][i].medianMs + r.medianMs) / 2).toFixed(2); });
    }
    fs.writeFileSync('output/game-textures/roads/benchmark.json', JSON.stringify(result, null, 2));
    for (let i = 0; i < SCENES.length; i++) {
      const a = result.before[i], b = result.after[i];
      console.log(`${a.id.padEnd(14)} calls ${a.calls}->${b.calls}  tris ${a.triangles}->${b.triangles}  tex ${a.textures}->${b.textures}  geo ${a.geometries}->${b.geometries}  ms ${a.medianMs}->${b.medianMs}`);
    }
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
