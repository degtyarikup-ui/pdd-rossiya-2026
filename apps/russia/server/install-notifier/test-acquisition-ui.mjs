import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { ANALYTICS_VIEW_HTML, ANALYTICS_CLIENT_JS } from './analytics_ui.js';
import { USERS_VIEW_HTML, USERS_CLIENT_JS } from './users_ui.js';
import { usersSnapshot } from './analytics_data.js';

test('account acquisition renders cohorts, missing evidence, article/campaign details and source labels on mobile', { timeout: 60000 }, async () => {
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 1000 } });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.setContent('<body style="margin:0;background:#F4F5F7;font-family:Arial;padding:16px;box-sizing:border-box">' + ANALYTICS_VIEW_HTML + USERS_VIEW_HTML + '</body>');
    await page.addScriptTag({ content: 'var currentFeature="analytics";function adminEsc(v){return String(v==null?"":v).replace(/[&<>\"]/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;","\\\"":"&quot;"}[c]||"&quot;";});}' });
    await page.addScriptTag({ content: ANALYTICS_CLIENT_JS });
    await page.addScriptTag({ content: USERS_CLIENT_JS });
    const now = Date.parse('2026-10-25T12:00:00Z');
    const common = { provider: 'google', app: 'ru', platform: 'android', createdAt: '2026-10-25T02:00:00Z' };
    const users = [
      { ...common, id: 'one', name: 'Первый', marketingSource: 'google', marketingMedium: 'organic', marketingCampaign: 'article_1', landingPage: '/blog/bilety-pdd/', hasPaidPurchase: true, purchaseEvidenceKnown: true },
      { ...common, id: 'two', name: 'Второй', marketingSource: 'unknown', installStore: 'App Store', hasPaidPurchase: false, purchaseEvidenceKnown: false },
      { ...common, id: 'three', name: 'Третий', marketingSource: 'direct', hasPaidPurchase: false, purchaseEvidenceKnown: true },
      { ...common, id: 'four', name: 'Четвёртый', marketingSource: 'google_play_organic', marketingMedium: 'organic', createdAt: '2026-09-01', hasPaidPurchase: false, purchaseEvidenceKnown: true },
    ];
    const snapshot = usersSnapshot(users, 1, 'ru', date => date.toISOString().slice(0, 10), now);
    await page.evaluate(data => { window.__anData = data; anRenderAcquisition(data); }, { users: snapshot });
    assert.equal(await page.locator('#an-acquisition-table tbody tr').count(), 3);
    assert.match(await page.locator('#an-acquisition-table').innerText(), /Google.*1.*1.*100%/s);
    assert.match(await page.locator('#an-acquisition-table').innerText(), /Источник не определён.*≥ 0%.*данные неполные/s);
    assert.match(await page.locator('#an-acquisition-coverage').innerText(), /недостаточно данных о старых покупках/);
    await page.locator('[data-acquisition="allTime"]').click();
    assert.equal(await page.locator('#an-acquisition-table tbody tr').count(), 4);
    assert.match(await page.locator('#an-acquisition-table').innerText(), /Google Play · органика/);
    await page.locator('#an-acquisition details.an-day-details').nth(0).locator('summary').click();
    assert.match(await page.locator('#an-acquisition-campaigns').innerText(), /article_1/);
    await page.locator('#an-acquisition details.an-day-details').nth(1).locator('summary').click();
    assert.match(await page.locator('#an-acquisition-articles').innerText(), /\/blog\/bilety-pdd\//);
    await page.evaluate(users => { currentFeature = 'users'; document.getElementById('users-view').style.display='block'; uvState.users = users; uvRenderList(); }, users);
    for (const width of [1200, 390, 320]) {
      await page.setViewportSize({ width, height: 1000 });
      assert.equal(await page.locator('#uv-list button[data-user="one"]').getByText('Google', { exact: true }).isVisible(), true);
      const metrics = await page.locator('#an-acquisition').evaluate(element => ({ width: element.clientWidth, scroll: element.scrollWidth }));
      assert.ok(metrics.scroll <= metrics.width, 'acquisition card fits ' + width);
      if (process.env.ACQUISITION_UI_SCREENSHOTS) {
        await mkdir(new URL('../../output/acquisition-ui/', import.meta.url), { recursive: true });
        await page.locator('#an-acquisition').screenshot({ path: fileURLToPath(new URL('../../output/acquisition-ui/' + width + '.png', import.meta.url)) });
      }
      await page.locator('#an-acquisition .an-help > summary').click();
      const help = await page.locator('#an-acquisition .an-help > div').boundingBox();
      assert.ok(help.x >= 0 && help.x + help.width <= width, 'help fits ' + width);
      await page.keyboard.press('Escape');
    }
    await page.locator('#uv-search').fill('google');
    await page.waitForFunction(() => uvState.query === 'google');
    assert.equal(await page.locator('#uv-list button[data-user]').count(), 2);
    await page.evaluate(user => { document.getElementById('uv-detail-screen').innerHTML = uvInfoCard(user); }, users[0]);
    assert.match(await page.locator('#uv-detail-screen').textContent(), /Источник привлеченияGoogle/);
    assert.match(await page.locator('#uv-detail-screen').textContent(), /Первая страница\/blog\/bilety-pdd\//);
    await page.evaluate(() => anRenderAcquisition({}));
    assert.match(await page.locator('#an-acquisition-table').innerText(), /недоступны/);
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
});
