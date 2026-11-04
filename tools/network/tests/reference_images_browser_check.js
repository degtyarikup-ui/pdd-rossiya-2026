// Read-only browser check. EDITOR_URL can point at an isolated editor server.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors = [], writes = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/**', route => {
      if (route.request().method() !== 'GET') {
        writes.push(route.request().url());
        return route.abort();
      }
      return route.continue();
    });
    await page.goto((process.env.EDITOR_URL || 'http://127.0.0.1:8950') + '/?scene=ticket_4_9');
    await page.waitForFunction(() => typeof App !== 'undefined' && App.state.id === 'ticket_4_9' && document.querySelector('#loading').hidden);
    const baseline = await page.evaluate(() => JSON.stringify(App.S));
    await page.click('#reference-toggle');
    await page.waitForFunction(() => {
      const img = document.querySelector('#refpic [data-photo]');
      return img?.complete && img.naturalWidth > 100;
    });
    assert.match(await page.locator('#refpic [data-photo]').getAttribute('src'), /\/ab\/verified_ab_4_9\.webp$/);
    await page.click('#refpic [data-big]');
    await page.waitForFunction(() => document.querySelector('#lightbox img')?.naturalWidth > 100);
    await page.click('#lightbox [data-close]');
    const output = path.resolve(__dirname, '../../../output/reference-4-9.png');
    fs.mkdirSync(path.dirname(output), {recursive:true});
    await page.screenshot({path:output});

    // The panel remains useful for questions without illustrations.
    await page.evaluate(() => {
      window.__source = App.state.source;
      App.state.source = {...App.state.source, image:null, imageUrl:null};
      Framing.refresh();
    });
    assert.equal(await page.locator('#refpic img').count(), 0);
    assert.equal(await page.locator('#refpic [data-big]').count(), 0);
    await page.click('#refpic [data-question]');
    assert(await page.locator('#refpic .qtext').isVisible());
    assert(!(await page.locator('#refpic').textContent()).includes('Фото текущего вопроса'));

    // A genuinely unavailable asset must never leave the browser's broken-image label.
    await page.evaluate(() => {
      App.state.source = {...window.__source, image:'missing_reference_fixture', imageUrl:'/asset/source/ab/missing_reference_fixture.webp'};
      Framing.refresh();
    });
    await page.waitForFunction(() => !document.querySelector('#refpic img'));
    assert.equal(await page.locator('#refpic [data-big]').count(), 0);
    assert(await page.locator('#refpic .qtext').isVisible());
    await page.evaluate(() => Framing.openPhoto());
    await page.waitForFunction(() => document.querySelector('#lightbox').hidden);

    // Legacy payloads without imageUrl retain category-specific named images.
    await page.evaluate(() => {
      App.state.source = {...window.__source, category:'cd', image:'verified_cd_4_9'};
      delete App.state.source.imageUrl;
      Framing.refresh();
    });
    await page.waitForFunction(() => document.querySelector('#refpic [data-photo]')?.naturalWidth > 100);
    assert.match(await page.locator('#refpic [data-photo]').getAttribute('src'), /\/cd\/verified_cd_4_9\.webp$/);
    assert.equal(await page.evaluate(() => JSON.stringify(App.S)), baseline);
    assert.deepEqual(errors, []);
    assert.deepEqual(writes, []);
    console.log('Reference panel: verified 4·9 + enlargement, no image, failed image, category fallback, unchanged scene PASS');
    console.log(output);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
