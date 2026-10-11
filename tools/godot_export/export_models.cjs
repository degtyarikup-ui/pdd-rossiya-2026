// Exports the WebView game's models to glb for the Godot game:
//   node tools/godot_export/export_models.cjs
// Needs Playwright + Chrome (same as tools/game_tests). Serves the repo root on
// a free port itself. Output: game_godot/models/<group>/<name>.glb + index.json.
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'game_godot/models');
const TYPES = { '.js': 'text/javascript', '.html': 'text/html', '.png': 'image/png', '.json': 'application/json' };

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
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(`http://127.0.0.1:${server.address().port}/tools/godot_export/export.html`);
    const result = await page.evaluate(() => window.exportModels());
    if (errors.length) throw new Error(errors.join('\n'));
    const index = {};
    for (const [name, item] of Object.entries(result)) {
      const file = path.join(OUT, name + '.glb');
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, Buffer.from(item.glb, 'base64'));
      index[name] = { before: item.before, after: item.after, ...(item.meta ? { meta: item.meta } : {}) };
      console.log(name.padEnd(18), `meshes ${item.before.meshes} -> ${item.after.meshes}`, `tris ${item.after.tris}`);
    }
    fs.writeFileSync(path.join(OUT, 'index.json'), JSON.stringify(index, null, 1) + '\n');

    // Scenery: the full game page (its factories are inside game.js).
    const game = await browser.newPage();
    game.on('pageerror', e => errors.push(e.message));
    await game.addInitScript(() => { window.FlutterChannel = { postMessage: m => { if (m.includes('"ready"')) window.__ready = true; } }; });
    await game.route('**/assets/game/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready',
        '  window.__pdd = { createBuilding, createTree, createBush, createFence, createKiosk, createLampPost, season };\n  // Run init on DOM ready');
      await route.fulfill({ response, body });
    });
    await game.goto(`http://127.0.0.1:${server.address().port}/assets/game/index.html`);
    await game.waitForFunction(() => window.__ready, null, { timeout: 120000 });
    for (const src of ['vendor/BufferGeometryUtils.js', 'vendor/GLTFExporter.js', 'exporter.js']) await game.addScriptTag({ path: path.join(__dirname, src) });
    const scenery = await game.evaluate(() => window.exportScenery());
    if (errors.length) throw new Error(errors.join('\n'));
    const SC = path.join(ROOT, 'game_godot/scenery'), TX = path.join(ROOT, 'game_godot/textures/detail');
    fs.rmSync(SC, { recursive: true, force: true }); fs.mkdirSync(TX, { recursive: true });
    const props = {};
    for (const [name, item] of Object.entries(scenery.props)) {
      const file = path.join(SC, name + '.glb');
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, Buffer.from(item.glb, 'base64'));
      const { glb, ...meta } = item; props[name] = meta;
      console.log(name.padEnd(22), 'size', meta.size.map(v => v.toFixed(1)).join(' x '));
    }
    const textures = scenery.textures.map(({ png, ...meta }) => { fs.writeFileSync(path.join(TX, meta.kind + '.png'), Buffer.from(png, 'base64')); return meta; });
    const seasons = await game.evaluate(() => {
      // Colours are integers (0xRRGGBB); intensities are fractions and stay numbers.
      const hex = v => Number.isInteger(v) && v > 1 ? '#' + v.toString(16).padStart(6, '0') : Array.isArray(v) ? v.map(hex) : v;
      const out = {};
      for (const [name, s] of Object.entries(PDD_SEASONS.palettes)) out[name] = Object.fromEntries(Object.entries(s).map(([k, v]) => [k, hex(v)]));
      return out;
    });
    fs.writeFileSync(path.join(SC, 'index.json'), JSON.stringify({ textures, props, seasons }, null, 1) + '\n');
  } finally {
    await browser.close();
    server.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
