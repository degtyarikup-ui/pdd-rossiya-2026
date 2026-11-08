// The real shortcuts and Save button, with scene writes intercepted before they reach disk.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1400,height:900}});
    const writes = [], errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/**', route => {
      const path = new URL(route.request().url()).pathname;
      if (route.request().method() === 'GET' || path.startsWith('/api/preview/')) return route.continue();
      if (path.startsWith('/api/scene/')) {
        writes.push(route.request().postDataJSON());
        return route.fulfill({json:{findings:[]}});
      }
      if (path.startsWith('/api/thumb/')) return route.fulfill({json:{}});
      return route.abort();
    });
    await page.goto('http://127.0.0.1:8950/?scene=ticket_3_16');
    await page.waitForFunction(() => typeof App !== 'undefined' && App.S?.actors.length);
    await page.evaluate(async () => {
      if (App.state.dirty) await App.save();
      App.select({t:'actor',id:App.S.actors[0].id});
    });
    writes.length = 0;
    assert(await page.locator('[data-text="name"]').isVisible(), 'actor name is directly editable');
    const name = page.locator('[data-text="name"]'), save = page.locator('#save');
    await name.fill('Имя с клавиатуры');
    assert(await save.isEnabled(), 'a typed draft enables Save on a clean scene');
    await name.dispatchEvent('compositionstart');
    await name.press('Control+s');
    assert.equal(writes.length,0, 'a shortcut cannot commit an active composition');
    await name.dispatchEvent('compositionend');
    await Promise.all([page.waitForRequest(r => r.method() === 'POST' && r.url().includes('/api/scene/')), name.press('Control+s')]);
    await page.waitForFunction(() => !App.isSaving);
    assert.equal(writes.at(-1).actors[0].name,'Имя с клавиатуры');
    assert(await name.evaluate(el => document.activeElement === el));

    await name.fill('Имя по кнопке');
    await save.click();
    await page.waitForFunction(() => !App.isSaving);
    assert.equal(writes.at(-1).actors[0].name,'Имя по кнопке');
    assert.equal(writes.length,2);

    await page.evaluate(() => {
      App.select({t:'sign',id:App.S.signs[0].id});
      App.edit(() => { App.S.signs[0].code = '3.24'; delete App.S.signs[0].number; }, {rebuild:false});
    });
    const number = page.locator('[data-text="signNumber"]');
    await number.fill('не число');
    await number.press('Control+s');
    await save.click();
    assert.equal(writes.length,2,'invalid input cannot save a different, older change');
    assert.equal(await page.evaluate(() => App.state.dirty),true);
    assert.deepEqual(errors,[]);
    console.log('Inspector save PASS: shortcut and button commit the focused field, IME and invalid values retain the draft');
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode=1;});
