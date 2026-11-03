// Run against the local editor. Exercise real Chromium touch sequences without saving a scene.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({channel: 'chrome'});
  try {
    const page = await browser.newPage({hasTouch: true, viewport: {width: 1280, height: 840}});
    const errors = [], writes = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/**', route => {
      const request = route.request();
      if (request.method() !== 'GET' && !request.url().includes('/api/preview/')) {
        writes.push(request.url());
        return route.abort();
      }
      return route.continue();
    });
    await page.goto('http://127.0.0.1:8950/?scene=ticket_3_16');
    await page.waitForFunction(() => typeof App !== 'undefined' && App.S?.layout);
    const client = await page.context().newCDPSession(page);
    const send = (type, ...touchPoints) => client.send('Input.dispatchTouchEvent', {type, touchPoints});
    const a = {x: 450, y: 245, id: 0}, b = {x: 535, y: 245, id: 1};
    const view = () => page.evaluate(() => Scene3D.getView());
    const scene = () => page.evaluate(() => JSON.stringify(App.S));
    const pinch = async () => {
      await send('touchStart', a);
      await send('touchStart', a, b);
      await send('touchMove', a, {...b, x: 620, y: 262});
      await send('touchEnd', a);
      await send('touchMove', {...a, x: 475});
      await send('touchEnd');
    };
    for (const mode of ['plan', '3d']) {
      await page.evaluate(mode => { Tools.set('road'); Scene3D.setMode(mode); Scene3D.fit(); }, mode);
      const original = await scene(), before = await view();
      await pinch();
      const after = await view();
      assert(mode === 'plan' ? after.pxPerM > before.pxPerM : after.orbitDist < before.orbitDist);
      assert(Math.hypot(after.x - before.x, after.z - before.z) > 1);
      assert.equal(await scene(), original);
      assert.equal(await page.locator('.drawing-actions').count(), 0, 'pinching did not start a road');
    }
    await page.evaluate(() => { Tools.set('prop'); Scene3D.setMode('plan'); Scene3D.fit(); });
    const count = await page.evaluate(() => App.S.decor.length);
    await pinch();
    assert.equal(await page.evaluate(() => App.S.decor.length), count);
    await send('touchStart', a);
    await send('touchEnd');
    assert.equal(await page.evaluate(() => App.S.decor.length), count + 1, 'one tap places an object');

    await page.evaluate(() => Tools.set('select'));
    const point = await page.evaluate(() => {
      const box = document.querySelector('#view canvas').getBoundingClientRect();
      const at = Scene3D.screenOf(...App.S.decor.at(-1).pos);
      return {x: box.left + at.x, y: box.top + at.y, id: 0};
    });
    const moved = {...point, x: point.x + 35, y: point.y + 21}, beforeDrag = await scene();
    await send('touchStart', point);
    await send('touchMove', moved);
    assert.notEqual(await scene(), beforeDrag, 'single-finger drag previews live');
    await send('touchStart', moved, b);
    await send('touchEnd');
    assert.equal(await scene(), beforeDrag, 'a second finger rolls back a live drag');
    await send('touchStart', point);
    await send('touchMove', moved);
    await send('touchEnd');
    assert.notEqual(await scene(), beforeDrag, 'lifting one finger commits the drag');
    assert.deepEqual(writes, []);
    assert.deepEqual(errors, []);
    console.log('PASS touch camera in 2D and 3D, placement, drag and cancellation');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
