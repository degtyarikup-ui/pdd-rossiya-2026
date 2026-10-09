// Run against scripts/game_lab.sh with NODE_PATH pointing at Playwright.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
    page.setDefaultTimeout(60000);
    const errors = [];
    await page.route('https://fonts.googleapis.com/**', route => route.abort());
    await page.route('https://fonts.gstatic.com/**', route => route.abort());
    page.on('pageerror', e => errors.push(e.message));
    await page.goto((process.env.GAME_LAB_URL || 'http://127.0.0.1:8940') + '/#ticket_1_15', { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => typeof lab !== 'undefined' && current?.id === 'ticket_1_15');
    await page.evaluate(() => lab.run('renderer.setPixelRatio(0.5)'));
    await page.locator('[data-mode="edit"]').click();
    assert.equal(await page.locator('#panel img.ticketImg').getAttribute('src'), await page.evaluate(() => imgOf(current)));
    await page.locator('#panel img.ticketImg').click();
    await page.locator('#zoom').click();
    await page.locator('[data-route="route:0"]').click();
    const initial = await page.evaluate(() => ({ ...selection }));
    await page.locator('#shorten').click();
    assert.ok(Math.abs(await page.evaluate(() => selection.length) - (initial.length - 1)) < 0.001);
    await page.locator('#rotL').click();
    await page.locator('#sl').fill('9');
    await page.locator('#sl').dispatchEvent('change');
    const saved = await page.evaluate(() => ({ ...selection }));
    if (process.env.GAME_LAB_SCREENSHOT) await page.screenshot({ path: process.env.GAME_LAB_SCREENSHOT });
    assert.equal(saved.length, 9);
    assert.ok(Math.abs(saved.rotY - Math.PI / 12) < 0.001);
    // Rebuild from the saved edit format, as the production engine does.
    await page.evaluate(() => open(current.id));
    const reloaded = await page.evaluate(() => lab.describe(lab.find('route:0')));
    for (const key of ['x', 'z', 'rotY', 'length']) assert.equal(reloaded[key], saved[key], key);
    const geometry = await page.evaluate(() => lab.run(`(() => {
      const route = window.__lab.find('route:0'), head = route.children.find(o => o.userData.guideArrow);
      return { tip: head.position.length(), start: route.children[0].userData.routePoints[0] };
    })()`));
    assert.ok(geometry.tip < 9.2);
    assert.ok(Math.hypot(geometry.start[0], geometry.start[2]) < 0.001, 'rotation must pivot at arrow start');
    await page.evaluate(() => { selection = lab.select('route:0'); renderEditPanel(); });
    await page.locator('#resetItem').click();
    assert.equal(await page.evaluate(() => lab.routes()[0].length), initial.length);
    // Multiple alternatives remain independently editable, including road scenes.
    const alternatives = await page.evaluate(() => {
      const item = gameWin.PDD_ROAD_SITUATIONS.find(s => s.scene.trajectories?.length > 1);
      if (item) { open(item.id); return item.id; }
    });
    assert.ok(alternatives);
    const road = await page.evaluate(() => {
      const [first, second] = lab.routes();
      lab.select(first.key); record(lab.update({ length: 7, rotY: 0.5 }));
      open(current.id);
      return { first: lab.describe(lab.find(first.key)), second: lab.describe(lab.find(second.key)), originalSecond: second };
    });
    assert.equal(road.first.length, 7);
    assert.equal(road.first.rotY, 0.5);
    assert.deepEqual(road.second, road.originalSecond);
    assert.deepEqual(errors, []);
    console.log('PASS: ticket image, zoom, arrow length/direction, reset, reload, independent road alternatives');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
