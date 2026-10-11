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
  } finally {
    await browser.close();
    server.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
