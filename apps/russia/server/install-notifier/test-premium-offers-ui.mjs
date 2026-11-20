import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import worker from './worker.js';
import { fixture, request } from './fixture-account.mjs';

test('admin stages a discount, activates a rate and sees stale edits across tabs', { timeout: 45000 }, async () => {
  const { env } = fixture();
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', err => errors.push(err.message));
    const origin = 'https://fixture.invalid';
    await page.route('**/*', async route => {
      const req = route.request();
      if (new URL(req.url()).origin !== origin) return route.abort();
      const response = await worker.fetch(new Request(req.url(), {
        method: req.method(), headers: { ...req.headers(), authorization: 'Bearer fixture-admin' },
        ...(req.postData() ? { body: req.postData() } : {}),
      }), env, {waitUntil: p => p.catch(() => {})});
      await route.fulfill({status: response.status, headers: Object.fromEntries(response.headers), body: await response.text()});
    });
    await page.goto(origin + '/admin#offers');
    const panel = page.locator('#offers-view');
    const current = panel.locator('#offers-sbp-current');
    await current.filter({hasText:'290 ₽'}).waitFor();
    assert.equal(await panel.evaluate(el => el.scrollWidth <= el.clientWidth), true);
    const trialCheck = panel.getByRole('button', { name:'Проверить пробный период СБП' });
    const trialStatus = panel.locator('#offers-sbp-trial-status');
    const probe = '**/api/admin/premium-offers/sbp-trial';
    for (const [trialSupported, maxTrialPeriodDays, minTrialAmount, message] of [
      [false,0,0,'не разрешает'],
      [true,30,1.25,'1,25 ₽'],
      [true,2,0,'2 дн.'],
      [true,3,0,'разрешает 3 дня за 0 ₽'],
    ]) {
      await page.route(probe, route => route.fulfill({json:{trialSupported,maxTrialPeriodDays,minTrialAmount}}), {times:1});
      await trialCheck.click();
      await trialStatus.filter({hasText:message}).waitFor();
    }
    await page.route(probe, route => route.fulfill({status:503,json:{error:'sbp_trial_unavailable'}}), {times:1});
    await trialCheck.click();
    await trialStatus.filter({hasText:'Не удалось проверить'}).waitFor();
    await page.route(probe, route => route.fulfill({status:503,json:{error:'sbp_trial_unavailable',reason:'provider_http',providerStatus:403}}), {times:1});
    await trialCheck.click();
    await trialStatus.filter({hasText:'Platega вернула HTTP 403.'}).waitFor();
    await panel.locator('#offers-discount input').fill('240');
    await panel.getByRole('button', {name:'Сохранить черновик'}).click();
    await panel.locator('#offers-state').filter({hasText:'Сохранено'}).waitFor();
    assert.ok((await current.textContent()).includes('290 ₽'));
    const activate = async mode => {
      await panel.locator('#offers-sbp select').selectOption(mode);
      await panel.getByRole('button', {name:'Применить цену СБП'}).click();
    };
    await activate('standard');
    await current.filter({hasText:'370 ₽'}).waitFor();
    await activate('promotion');
    await current.filter({hasText:'240 ₽ по акции'}).waitFor();
    const store = panel.locator('[data-store="appstore"]');
    await store.locator('select').selectOption('standard');
    await store.locator('input').check();
    await store.getByRole('button').click();
    await panel.locator('#offers-state').filter({hasText:'Сохранено'}).waitFor();
    const url = '/api/admin/premium-offers';
    const settings = (await (await worker.fetch(request(url,undefined,'fixture-admin'),env)).json()).settings;
    assert.deepEqual(settings.storeTrials, {appstore:true, googleplay:false});
    const modified = await worker.fetch(request(url, {operation:'activate_sbp', revision:settings.revision, mode:'legacy'}, 'fixture-admin'), env);
    assert.equal(modified.status, 200);
    await activate('standard');
    await panel.locator('#offers-state').filter({hasText:'другой вкладке'}).waitFor();
    assert.ok(await panel.locator('#offers-sbp select').isDisabled());
    await panel.getByRole('button',{name:'Обновить'}).click();
    await current.filter({hasText:'290 ₽'}).waitFor();
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
});

test('public tariffs follow the catalog, reconfirm changed leads and recover failed loads', {timeout:45000}, async () => {
  const { chromium } = createRequire(import.meta.url)('playwright');
  const root = new URL('../../web_landing/ru/', import.meta.url);
  const [html, js] = await Promise.all(['tarify/index.html','assets/tariffs.js'].map(path => readFile(new URL(path, root),'utf8')));
  const origin = 'https://fixture.invalid';
  const browser = await chromium.launch({headless:true, executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  try {
    const page = await browser.newPage();
    let amount = 370, live = false, unavailable = false, legacy = false;
    const leads = [], errors = [];
    page.on('pageerror', e => errors.push(e.message));
    const catalog = () => ({version:1,tariffs:{weekly:{priceRub:99,days:7},threeMonths:{priceRub:amount,days:90}}});
    await page.route('**/*', async route => {
      const req = route.request(), u = new URL(req.url());
      if (u.pathname === '/tarify/') return route.fulfill({contentType:'text/html',body:html});
      if (u.pathname === '/assets/tariffs.js') return route.fulfill({contentType:'text/javascript',body:js});
      if (u.pathname.startsWith('/api/pay/')) {
        const headers = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Access-Control-Allow-Headers':'content-type'};
        if (req.method() === 'OPTIONS') return route.fulfill({status:204,headers});
        if (u.pathname.endsWith('/status')) return route.fulfill({json:{available:live},headers});
        if (u.pathname.endsWith('/catalog')) {
          if (unavailable) return route.fulfill({status:503,headers});
          return route.fulfill(legacy ? {body:'pdd-install-notifier: ok',headers} : {json:catalog(),headers});
        }
        const quote = req.postDataJSON();
        leads.push(quote);
        assert.equal(quote.catalogVersion, 1);
        return route.fulfill(quote.expectedPriceRub === amount
          ? {json:{ok:true,available:live},headers}
          : {status:409,json:{code:'price_changed', catalog:catalog()},headers});
      }
      if (u.pathname === '/app/') return route.fulfill({contentType:'text/html',body:'checkout'});
      return route.fulfill({status:200,body:''});
    });
    const url = origin + '/tarify/';
    await page.goto(url);
    const buy = page.locator('[data-tier="threeMonths"]');
    await buy.filter({hasText:'370 ₽'}).waitFor();
    assert.equal(JSON.parse(await page.locator('#tariff-schema').textContent()).mainEntity.offers[1].price, '370');
    assert.ok((await page.locator('.plan.hit .plan-note').textContent()).includes('123 ₽'));
    await buy.click();
    await page.locator('#pay-title').filter({hasText:'370 ₽'}).waitFor();
    await page.locator('#pay-email').fill('a@example.invalid');
    amount = 240;
    await page.getByRole('button',{name:'Сообщить о запуске'}).click();
    await page.locator('#pay-title').filter({hasText:'240 ₽'}).waitFor();
    assert.equal(leads.length, 1);
    assert.ok(await page.locator('#pay-error').isVisible());
    await page.getByRole('button',{name:'Сообщить о запуске'}).click();
    await page.locator('#pay-done').waitFor();
    assert.deepEqual(leads.map(p => p.expectedPriceRub), [370,240]);
    unavailable = true;
    await page.reload();
    await page.locator('#tariff-retry').waitFor();
    assert.equal(await buy.isDisabled(), true);
    assert.equal(JSON.parse(await page.locator('#tariff-schema').textContent()).mainEntity.offers, undefined);
    unavailable = false;
    legacy = true;
    live = true;
    await page.locator('#tariff-retry').click();
    await buy.filter({hasText:'290 ₽'}).waitFor();
    await buy.click();
    await page.waitForURL(origin + '/app/?checkout=sbp&tier=threeMonths');
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
});
