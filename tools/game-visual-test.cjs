// Procedural model atlas + triangle/draw-call budget. Uses the same local server
// and Playwright/Chrome setup as game-engine-test.cjs; no debug API ships.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 640 } });
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const source = process.env.GAME_SCRIPT ? fs.readFileSync(process.env.GAME_SCRIPT, 'utf8') : await response.text();
      const body = source.replace('  // Run init on DOM ready', `
        window.modelTest = {createPedestrian, createCyclist};
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.modelTest);
    const output = process.env.GAME_SHOTS || 'build/game_ui'; fs.mkdirSync(output, { recursive: true });
    for (const type of ['Pedestrian', 'Cyclist']) {
      const metrics = await page.evaluate(type => {
        document.body.replaceChildren();
        const canvas = document.createElement('canvas'); document.body.append(canvas);
        const renderer = new THREE.WebGLRenderer({canvas, antialias: true, preserveDrawingBuffer: true});
        renderer.setSize(1200, 640); renderer.setScissorTest(true);
        const result = [], signatures = new Set();
        for (let variant = 0; variant < 12; variant++) {
          const scene = new THREE.Scene(); scene.background = new THREE.Color(0xE7EFEC);
          scene.add(new THREE.HemisphereLight(0xFFFFFF, 0x798279, 1.1));
          const light = new THREE.DirectionalLight(0xFFFFFF, 0.8); light.position.set(-3, 6, 5); scene.add(light);
          const model = modelTest['create' + type](type === 'Pedestrian' ? 0x458CB0 : 0xDA8650, variant);
          model.rotation.y = -0.45; scene.add(model);
          let meshes = 0, triangles = 0, textures = 0;
          const shape = [];
          model.traverse(o => { if (!o.isMesh) return; meshes++;
            triangles += (o.geometry.index?.count || o.geometry.attributes.position.count) / 3;
            textures += o.material.map ? 1 : 0;
            shape.push(o.geometry.attributes.color?.array.join(), o.material.color.getHex(), ...o.position.toArray());
          });
          signatures.add(JSON.stringify([shape, model.scale.toArray()]));
          result.push({meshes, triangles, textures});
          const camera = new THREE.PerspectiveCamera(34, 200 / 320, 0.1, 30);
          camera.position.set(2.6, 2.25, 3.6);
          if (type === 'Cyclist') camera.position.multiplyScalar(1.4);
          camera.lookAt(0, 0.78, 0);
          renderer.setViewport((variant % 6) * 200, variant < 6 ? 320 : 0, 200, 320);
          renderer.setScissor((variant % 6) * 200, variant < 6 ? 320 : 0, 200, 320);
          renderer.render(scene, camera);
          const geometries = new Set(), materials = new Set();
          model.traverse(o => { if (o.isMesh) { geometries.add(o.geometry); materials.add(o.material); } });
          geometries.forEach(g => g.dispose()); materials.forEach(m => m.dispose());
        }
        renderer.dispose();
        return { type, unique: signatures.size, variants: result };
      }, type);
      console.log(JSON.stringify(metrics));
      if (!process.env.GAME_SCRIPT) {
        assert.equal(metrics.unique, 12, type + ': distinct appearances');
        assert(metrics.variants.every(v => v.meshes <= 5 && v.triangles <= 600 && v.textures === 0), type + ': geometry budget');
      }
      await page.screenshot({path: output + '/' + type.toLowerCase() + '-variants.png'});
    }
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
