// Regression: a WebView may finish loading while its native bounds are 0x0.
// Run against the same local server / NODE_PATH as game-engine-test.cjs.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/startup-host', route => route.fulfill({
      contentType: 'text/html', body: '<body style="margin:0"><iframe style="width:0;height:0;border:0" src="/assets/game/"></iframe></body>',
    }));
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
        window.startupSnapshot = () => {
          renderer.render(scene, camera);
          const gl = renderer.getContext();
          const pixels = new Uint8Array(gl.drawingBufferWidth * gl.drawingBufferHeight * 4);
          gl.readPixels(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
          const colors = new Set();
          for (let i = 0; i < pixels.length; i += 64) colors.add(pixels.slice(i, i + 3).join(','));
          return { finite: [...camera.position.toArray(), ...cameraLook.toArray(),
            ...camera.projectionMatrix.elements].every(Number.isFinite), colors: colors.size };
        };
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/startup-host');
    const frame = page.frames().find(f => f.parentFrame());
    await frame.waitForFunction(() => window.startupSnapshot);
    await page.waitForTimeout(300);
    await frame.evaluate(() => {
      game.configure({ labels: { player: 'TEST' } });
      game.setPaused(false); game.selectVehicle('pickup'); game.setTheme(false);
      game.setViewportInsets({ top: 150, bottom: 100 });
    });
    assert.equal((await frame.evaluate(() => startupSnapshot())).finite, true, 'zero-size startup must not corrupt the camera');
    await page.locator('iframe').evaluate(f => { f.style.width = '390px'; f.style.height = '844px'; });
    await page.waitForTimeout(800);
    let shot = await frame.evaluate(() => startupSnapshot());
    assert.equal(shot.finite, true);
    assert.ok(shot.colors > 30, `scene must render, not just the background (${shot.colors} colors)`);
    // Resizing while paused and then resuming must also keep a valid camera.
    await frame.evaluate(() => game.setPaused(true));
    await page.locator('iframe').evaluate(f => { f.style.width = '0'; f.style.height = '0'; });
    await page.waitForTimeout(100);
    await page.locator('iframe').evaluate(f => { f.style.width = '390px'; f.style.height = '844px'; });
    await frame.evaluate(() => game.setPaused(false));
    await page.waitForTimeout(300);
    shot = await frame.evaluate(() => startupSnapshot());
    assert.equal(shot.finite, true); assert.ok(shot.colors > 30);
    assert.deepEqual(errors, []);
    await page.screenshot({ path: process.env.STARTUP_SHOT || '/tmp/pdd-startup-fixed.png' });
    console.log('PASS: zero-size native startup, saved vehicle, actual scene pixels, resize/resume');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
