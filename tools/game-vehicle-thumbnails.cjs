// Render the actual procedural vehicle meshes, not unrelated illustrations.
const { chromium } = require('playwright');
const path = require('node:path');
(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 560, height: 340 }, deviceScaleFactor: 1 });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.PDD_VEHICLES && window.game);
    await page.evaluate(() => window.game.setPaused(true));
    for (const id of ['hatch', 'sedan', 'suv', 'pickup']) {
      await page.evaluate(id => {
        document.body.replaceChildren();
        const scene = new THREE.Scene();
        const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true });
        renderer.setSize(560, 340); renderer.setClearColor(0, 0);
        document.body.style.background = 'transparent'; document.documentElement.style.background = 'transparent';
        document.body.appendChild(renderer.domElement);
        const camera = new THREE.OrthographicCamera(-3.6, 3.6, 2.185, -2.185, 0.1, 100);
        camera.position.set(6, 4.5, 7); camera.lookAt(0, 0.65, 0);
        scene.add(new THREE.AmbientLight(0xffffff, 0.8));
        const light = new THREE.DirectionalLight(0xfffaf2, 0.8); light.position.set(4, 8, 5); scene.add(light);
        scene.add(window.PDD_VEHICLES.create(id)); renderer.render(scene, camera);
        window.thumbnailRenderer?.dispose(); window.thumbnailRenderer = renderer;
      }, id);
      await page.screenshot({ path: path.resolve(`assets/game/vehicle-${id}.png`), omitBackground: true });
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
