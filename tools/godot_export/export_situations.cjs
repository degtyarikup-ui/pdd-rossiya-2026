// Exports every reviewed situation scene of the WebView game for Godot:
//   node tools/godot_export/export_situations.cjs [id ...]
// -> game_godot/situations/<id>/{scene.glb, light_<n>.glb, actor_<n>.glb, scene.json}
// The scene is built by game.js itself (same code the player sees), see
// docs/game/godot-migration.md, stage 2.
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'game_godot/situations');
const TYPES = { '.js': 'text/javascript', '.html': 'text/html', '.png': 'image/png', '.json': 'application/json', '.webp': 'image/webp' };
const only = process.argv.slice(2);

(async () => {
  const server = http.createServer((req, res) => {
    const file = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  }).listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  const errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.FlutterChannel = { postMessage: m => { if (m.includes('"ready"')) window.__ready = true; } }; });
    await page.route('**/assets/game/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
  // Roadside props are not baked into the scene: Godot draws them with its
  // own instanced copies (scenery/*.glb). Tag what the factories return.
  {
    const tag = (fn, kind) => (...args) => { const o = fn(...args); o.userData.godotProp = { kind, args }; return o; };
    createBuilding = tag(createBuilding, 'building'); createTree = tag(createTree, 'tree');
    createBush = tag(createBush, 'bush'); createFence = tag(createFence, 'fence');
    createKiosk = tag(createKiosk, 'kiosk'); createLampPost = tag(createLampPost, 'lamp');
    createParkedCar = tag(createParkedCar, 'parked');
    // The far background is merged per row by bakeGroups: keep the tagged
    // props as they are instead (Godot instances them).
    bakeGroups = groups => groups;
  }
  window.__eng = {
    state, routeSpec, ensureTraffic, maneuverPoints, curve, player: () => playerCarGroup, roadSupports, refreshRoadBounds,
    // The question view the game settles on at this junction (updateCamera).
    questionCamera(it) {
      state.isAtSituation = true; state.activeIntersection = it;
      for (let i = 0; i < 400; i++) updateCamera(1 / 60);
      const out = { look: cameraLook.clone(), size: cameraViewSize, position: camera.position.clone() };
      state.isAtSituation = false;
      return out;
    },
    scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed && !isRegulatorSituation(s)),
    drain() { while (processSceneryJobs(1000).pending) {} },
    // Vertices of the scene by top-level child (to find what makes it heavy).
    weight(root) {
      const out = {};
      let kids = root.children.length === 1 ? root.children[0].children : root.children;
      if (window.__deep) { let big = null, bn = 0; kids.forEach(c => { let n = 0; c.traverse(m => { if (m.isMesh) n += m.geometry.attributes.position?.count || 0; }); if (n > bn) { bn = n; big = c; } }); kids = big.children; }
      kids.forEach(c => { let n = 0; c.traverse(m => { if (m.userData.godotProp) return; if (m.isMesh && m.visible !== false) n += (m.geometry.attributes.position?.count || 0) * (m.isInstancedMesh ? m.count : 1); });
        const k = c.userData.godotProp ? 'prop:' + c.userData.godotProp.kind : (c.name || c.type) + ':' + Object.keys(c.userData).slice(0, 3).join(',') + (c.isMesh ? ':' + (c.geometry.type) : '') + ':' + c.children.length; out[k] = (out[k] || 0) + n; });
      return Object.entries(out).sort((a, b) => b[1] - a[1]).slice(0, 25);
    },
    select(index) {
      resetGame();
      state.roadSegments.forEach(disposeSegment);
      state.roadSegments = []; state.intersections = [];
      situationIndex = index; situationBag = [this.scenarios()[index]]; buildInitialTrack();
    },
    approach() {
      if (!state.intersections.length) { playerCarGroup.position.z = nextSegmentZ - 100; checkAndSpawnNext(); }
      playerCarGroup.position.z = state.intersections[0].stopZ;
      playerCarGroup.rotation.y = 0;
      updatePlayerMovement(0);
    },
  };
  // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/assets/game/index.html`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 120000 });
    await page.evaluate(d => { window.game.setPaused(true); window.__deep = d; }, process.env.WEIGHT === '2');
    for (const src of ['vendor/BufferGeometryUtils.js', 'vendor/GLTFExporter.js', 'exporter.js', 'situations.js']) await page.addScriptTag({ path: path.join(__dirname, src) });
    const ids = await page.evaluate(() => window.situationIds());
    const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, 'game_godot/scenery/index.json'), 'utf8')).props;
    const index = [], failed = [];
    for (let i = 0; i < ids.length; i++) {
      if (only.length && !only.includes(ids[i])) continue;
      let item;
      try { item = await page.evaluate(([i, c]) => window.exportSituation(i, c), [i, catalog]); }
      catch (e) { console.log(ids[i], 'FAILED', e.message.split('\n')[0]); failed.push(ids[i]); continue; }
      if (item.error) { console.log(ids[i], 'SKIP', item.error); continue; }
      const dir = path.join(OUT, ids[i]);
      fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'scene.glb'), Buffer.from(item.glb, 'base64'));
      fs.writeFileSync(path.join(dir, 'road.png'), Buffer.from(item.mask, 'base64'));
      item.json.lights = item.lights.map((l, n) => { fs.writeFileSync(path.join(dir, `light_${n}.glb`), Buffer.from(l.glb, 'base64')); const { glb, ...rest } = l; return rest; });
      item.json.actors = item.actors.map((a, n) => { fs.writeFileSync(path.join(dir, `actor_${n}.glb`), Buffer.from(a.glb, 'base64')); const { glb, ...rest } = a; return rest; });
      fs.writeFileSync(path.join(dir, 'scene.json'), JSON.stringify(item.json, null, 1) + '\n');
      index.push(ids[i]);
      console.log(ids[i].padEnd(16), `actors ${item.actors.length}`, `lights ${item.lights.length}`, `props ${item.json.props.length}`);
      if (process.env.WEIGHT) console.log(item.weight);
    }
    if (!only.length) fs.writeFileSync(path.join(OUT, 'index.json'), JSON.stringify(index, null, 1) + '\n');
    console.log(`done: ${index.length} exported, ${failed.length} failed`, failed.join(' '));
    if (errors.length) console.error('page errors:\n' + errors.join('\n'));
  } finally {
    await browser.close();
    server.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
