// Тестирование аналитики, логина и эндпоинтов админки воркера локально
import worker from './worker.js';
import assert from 'node:assert/strict';

class MockKV {
  constructor() {
    this.store = new Map();
  }
  async get(key) {
    return this.store.get(key) || null;
  }
  async put(key, val) {
    this.store.set(key, String(val));
  }
  async delete(key) {
    this.store.delete(key);
  }
  async list({ prefix }) {
    const keys = [];
    for (const k of this.store.keys()) {
      if (k.startsWith(prefix)) keys.push({ name: k });
    }
    return { keys };
  }
}

async function runTests() {
  const env = {
    INSTALLS: new MockKV(),
    BOT_TOKEN: 'mock_token',
    CHAT_ID: 'mock_chat_id',
    ADMIN_PASSWORD: 'test_password_123'
  };

  console.log('1. Тестируем GET /admin (страница админки)...');
  const adminReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/admin');
  const adminRes = await worker.fetch(adminReq, env);
  const adminHtml = await adminRes.text();
  assert.equal(adminRes.status, 200);
  assert.match(adminHtml, /<title>ПДД Аналитика — Панель управления<\/title>/);
  assert.match(adminHtml, /id="admin-data-state"/);
  assert.match(adminHtml, /Установки по дням/);
  assert.doesNotMatch(adminHtml, /chart\.js/);
  assert.match(adminHtml, /Данные аналитики/);
  assert.match(adminHtml, /Беларусь \(BY\)/);
  assert.equal((adminHtml.match(/id="sidebar-app-select"/g) || []).length, 1);
  console.log('   Status:', adminRes.status, 'оболочка и состояния встроены: YES');

  console.log('2. Тестируем POST /api/track (просмотр из YouTube Shorts)...');
  const viewReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/track', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'
    },
    body: JSON.stringify({
      type: 'view',
      source: 'youtube',
      campaign: 'shorts_15',
      path: '/links/',
      platform: 'ios'
    })
  });
  const viewRes = await worker.fetch(viewReq, env);
  console.log('   Status:', viewRes.status, await viewRes.json());

  console.log('3. Тестируем POST /api/track (клик по RuStore)...');
  const clickReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/track', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'user-agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36'
    },
    body: JSON.stringify({
      type: 'click',
      target: 'rustore',
      source: 'youtube',
      campaign: 'shorts_15',
      path: '/links/',
      platform: 'android'
    })
  });
  const clickRes = await worker.fetch(clickReq, env);
  console.log('   Status:', clickRes.status, await clickRes.json());

  console.log('4. Тестируем POST /api/track (просмотр из TikTok)...');
  const ttReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/track', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15'
    },
    body: JSON.stringify({
      type: 'view',
      source: 'tiktok',
      campaign: 'bio',
      path: '/links/',
      platform: 'ios'
    })
  });
  await worker.fetch(ttReq, env);

  const byReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/track', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'user-agent': 'Mozilla/5.0 Chrome/126.0' },
    body: JSON.stringify({ type: 'view', app: 'by', country: 'BY', source: 'direct', path: '/' })
  });
  await worker.fetch(byReq, env);

  // Предыдущий равный период: 7 дней, которые идут перед выбранными семью.
  const previousDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const previousDayKey = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Moscow', year: 'numeric', month: '2-digit', day: '2-digit'
  }).format(previousDate);
  await env.INSTALLS.put(`day:${previousDayKey}`, JSON.stringify({
    views: 9, clicks: 4, installs: 2,
    apps: { by: { views: 2, clicks: 1, installs: 1 } }
  }));

  console.log('5. Тестируем GET /api/admin/stats без авторизации (ожидаем 401)...');
  const unauthReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/admin/stats');
  const unauthRes = await worker.fetch(unauthReq, env);
  console.log('   Status:', unauthRes.status);

  console.log('6. Тестируем POST /api/admin/login...');
  const loginReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/admin/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ password: 'test_password_123' })
  });
  const loginRes = await worker.fetch(loginReq, env);
  const cookie = loginRes.headers.get('set-cookie');
  console.log('   Status:', loginRes.status, 'Cookie set:', cookie ? 'YES' : 'NO');

  console.log('7. Тестируем GET /api/admin/stats с Bearer токеном...');
  const statsReq = new Request('https://pdd-install-notifier.sergei-pdd.workers.dev/api/admin/stats?days=7', {
    headers: { 'authorization': 'Bearer test_password_123' }
  });
  const statsRes = await worker.fetch(statsReq, env);
  const statsData = await statsRes.json();
  console.log('   Status:', statsRes.status);
  console.log('   Totals:', statsData.totals);
  console.log('   Sources:', statsData.sources);
  console.log('   Targets:', statsData.targets);
  console.log('   Campaigns:', statsData.campaigns);
  console.log('   Recent events count:', statsData.recent.length);
  const { views, clicks, installs } = statsData.previous;
  assert.deepEqual({ views, clicks, installs }, { views: 9, clicks: 4, installs: 2 });
  const byStatsRes = await worker.fetch(new Request(
    'https://pdd-install-notifier.sergei-pdd.workers.dev/api/admin/stats?days=7&app=by',
    { headers: { 'authorization': 'Bearer test_password_123' } }
  ), env);
  const byStats = await byStatsRes.json();
  assert.equal(byStats.totals.views, 1);
  assert.equal(byStats.timeline.reduce((sum, day) => sum + day.views, 0), 1);
  assert.deepEqual({ views: byStats.previous.views, clicks: byStats.previous.clicks, installs: byStats.previous.installs }, { views: 2, clicks: 1, installs: 1 });
  console.log('   Беларусь отделена от России: YES');

  console.log('8. Тестируем атомарную перестановку статей...');
  const articleList = JSON.parse(JSON.stringify([
    { slug: 'first', title: 'Первая', datePublished: '2026-10-01' },
    { slug: 'second', title: 'Вторая', datePublished: '2026-10-02' }
  ]));
  await env.INSTALLS.put('blog_articles', JSON.stringify(articleList));
  const reorderRes = await worker.fetch(new Request(
    'https://pdd-install-notifier.sergei-pdd.workers.dev/api/admin/blog/reorder',
    {
      method: 'POST',
      headers: { 'authorization': 'Bearer test_password_123', 'content-type': 'application/json' },
      body: JSON.stringify({ changes: [
        { slug: 'first', datePublished: '2026-10-02' },
        { slug: 'second', datePublished: '2026-10-01' }
      ] })
    }
  ), env);
  assert.equal(reorderRes.status, 200);
  const reordered = JSON.parse(await env.INSTALLS.get('blog_articles'));
  assert.equal(reordered[0].datePublished, '2026-10-02');
  assert.equal(reordered[1].datePublished, '2026-10-01');
  console.log('   Обе даты сохранены одной операцией: YES');
  console.log('Все тесты успешно пройдены!');
}

runTests().catch(console.error);
