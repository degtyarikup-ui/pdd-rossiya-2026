// Notifications screen of the assembled admin with local, isolated campaigns.
// `node test-notifications-ui.mjs --serve` prints a URL to open in a browser;
// without the flag Playwright checks the editor, preview and history.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { generateKeyPairSync } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import { NotificationsState, DEFAULT_NOTIFICATION_CONFIG } from './notifications.js';

class MemoryKV {
  constructor() { this.store = new Map(); this.metadata = new Map(); }
  async get(key, options) {
    const value = this.store.get(key) ?? null;
    if (value === null) return null;
    if (options === 'json' || options?.type === 'json') return JSON.parse(value);
    return options?.type === 'arrayBuffer' ? value : typeof value === 'string' ? value : value;
  }
  async getWithMetadata(key, options) { return { value: await this.get(key, options), metadata: this.metadata.get(key) || null }; }
  async put(key, value, options) {
    this.store.set(key, value instanceof ArrayBuffer ? value : String(value));
    if (options?.metadata) this.metadata.set(key, options.metadata); else this.metadata.delete(key);
  }
  async delete(key) { this.store.delete(key); this.metadata.delete(key); }
  async list({ prefix = '' } = {}) { return { keys: [...this.store.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name })), list_complete: true }; }
}

function notificationsNamespace(env) {
  const data = new Map();
  const storage = {
    get: async k => structuredClone(data.get(k)), put: async (k, v) => data.set(k, structuredClone(v)),
    delete: async k => data.delete(k), setAlarm: async () => {},
    list: async ({ prefix }) => new Map([...data].filter(([k]) => k.startsWith(prefix)).map(([k, v]) => [k, structuredClone(v)])),
  };
  const object = new NotificationsState({ storage }, env);
  return { data, namespace: { idFromName: () => 'admin-notifications', get: () => ({ fetch: (url, init) => object.fetch(new Request(url, init)) }) } };
}

export async function preview() {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const env = { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: crypto.randomUUID(), SESSION_SECRET: crypto.randomUUID(),
    FCM_SERVICE_ACCOUNT: JSON.stringify({ project_id: 'preview', client_email: 'preview@test.invalid', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) }) };
  const { data, namespace } = notificationsNamespace(env);
  env.NOTIFICATIONS = namespace;
  await data.set('config', { ...DEFAULT_NOTIFICATION_CONFIG, pushEnabled: true });
  const now = Date.now(), day = 86400000;
  const seed = [
    { kind: 'push', inAppKind: 'news', title: 'Новые билеты 2026', body: 'Мы обновили все 40 билетов по новым правилам. Загляните в раздел «Билеты».', status: 'accepted', action: 'tickets', createdAt: now - 2 * 3600000 },
    { kind: 'banner', layout: 'image', title: '', body: '', imageUrl: 'https://pdd-drive.ru/assets/icon-192.png', action: 'premium', createdAt: now - day, metrics: [140, 12] },
    { kind: 'popup', title: 'Тест окна', body: 'Проверка на своём аккаунте', target: 'me@example.test', createdAt: now - 3 * day },
  ];
  for (const item of seed) {
    const id = crypto.randomUUID();
    data.set('message:' + id, { id, app: 'ru', platform: 'all', store: 'all', enabled: true, startAt: item.createdAt, expiresAt: item.createdAt + 7 * day,
      layout: 'standard', button: true, buttonText: '', dismissText: '', imageUrl: '', accent: '', emoji: '', actionUrl: '', target: '', inApp: false,
      status: item.kind === 'push' ? 'accepted' : 'published', ...item, metrics: undefined });
    if (item.metrics) await env.INSTALLS.put('notice_metrics:' + id, JSON.stringify({ view: item.metrics[0], click: item.metrics[1] }));
  }
  await env.INSTALLS.put('user_email:me@example.test', 'google_preview');
  await env.INSTALLS.put('user_email:friend@example.test', 'google_friend');
  await env.INSTALLS.put('user:google_friend', JSON.stringify({ id: 'google_friend', email: 'friend@example.test', name: 'Друг' }));
  await env.INSTALLS.put('user:google_preview', JSON.stringify({ id: 'google_preview', email: 'me@example.test', name: 'Админ' }));
  const server = createServer(async (incoming, outgoing) => {
    try {
      const url = new URL(incoming.url, `http://${incoming.headers.host}`), headers = new Headers(incoming.headers);
      if (url.pathname.startsWith('/api/admin/')) headers.set('authorization', `Bearer ${env.ADMIN_PASSWORD}`);
      const chunks = []; for await (const chunk of incoming) chunks.push(chunk);
      const body = chunks.length ? Buffer.concat(chunks) : undefined;
      const response = await worker.fetch(new Request(url, { method: incoming.method, headers, body }), env, { waitUntil(p) { p.catch(() => {}); } });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch (e) { outgoing.writeHead(500); outgoing.end(String(e)); }
  });
  await new Promise(resolve => server.listen(Number(process.env.PORT) || 0, '127.0.0.1', resolve));
  return { url: `http://127.0.0.1:${server.address().port}`, data, async close() { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); } };
}

if (process.argv.includes('--serve')) {
  const app = await preview(); console.log(app.url + '/admin#notifications');
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await app.close(); process.exit(0); });
} else test('notifications editor previews every channel and sends a test before everyone', { timeout: 90000 }, async t => {
  let chromium;
  try { ({ chromium } = createRequire(import.meta.url)('playwright')); } catch { t.skip('Playwright не найден (NODE_PATH)'); return; }
  const app = await preview();
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto(app.url + '/admin');
    await page.click('[data-feature="notifications"]');
    await page.waitForSelector('#nt-history .nf-msg');
    assert.equal(await page.locator('#nt-history .nf-msg').count(), 3);
    // Picture only: the window shows the picture, the list shows an entry.
    await page.check('input[name="nt-place"][value="popup"]', { force: true });
    await page.fill('#nt-title', 'Новая версия');
    assert.match(await page.textContent('#nt-screen'), /Новая версия/);
    // A push: title is limited for lock screens and previewed per platform.
    await page.check('#nt-push', { force: true });
    assert.equal(await page.getAttribute('#nt-title', 'maxlength'), '50');
    assert.match(await page.textContent('#nt-screen'), /Раскрыто.*Новая версия/);
    // iPhone picture: a thumbnail on the lock screen, above the text when expanded.
    page.once('dialog', dialog => dialog.accept('https://pdd-drive.ru/assets/icon-192.png'));
    await page.click('#nt-drop [data-img="url"]');
    assert.equal(await page.locator('#nt-screen .in .th').count(), 1);
    assert.equal(await page.locator('#nt-screen .in.big .pic').count(), 1);
    await page.click('#nt-os [data-os="android"]');
    const image = page.locator('#nt-screen .nf-android-image');
    assert.equal(await image.count(), 1);
    assert.equal(await image.evaluate(el => getComputedStyle(el).aspectRatio), '2 / 1');
    assert.match(await image.evaluate(el => getComputedStyle(el).backgroundImage), /icon-192\.png/);
    assert.match(await page.textContent('#nt-screen'), /ПДД Россия 2026/);
    assert.equal(await page.isDisabled('input[name="nt-platform"][value="web"]'), true);
    // Platforms are picked independently; a push never goes to the web.
    assert.equal(await page.isChecked('input[name="nt-platform"][value="web"]'), false);
    await page.uncheck('input[name="nt-platform"][value="ios"]', { force: true });
    assert.deepEqual(await page.evaluate(() => [...document.querySelectorAll('input[name="nt-platform"]:checked')].map(x => x.value)), ['android']);
    await page.check('input[name="nt-platform"][value="ios"]', { force: true });
    // A test goes to my account without confirmation.
    await page.click('#nt-test');
    await page.fill('#nt-target', 'me@example.test');
    await page.click('#nt-me-save');
    await page.waitForFunction(() => document.querySelectorAll('#nt-history .nf-msg').length === 4);
    const test = [...app.data.values()].find(m => m?.target === 'me@example.test' && m.kind === 'push');
    // Several test accounts: each ticked one gets its own copy.
    await page.click('#nt-me');
    await page.fill('#nt-target', 'friend@example.test');
    await page.click('#nt-me-save');
    assert.equal(await page.textContent('#nt-test'), 'Отправить на 2');
    await page.click('#nt-test');
    await page.waitForFunction(() => document.querySelectorAll('#nt-history .nf-msg').length === 6);
    await page.uncheck('#nt-recips input[data-rc="1"]', { force: true });
    assert.equal(await page.textContent('#nt-test'), 'Отправить себе');
    assert.equal(test.inAppKind, 'popup');
    assert.match(test.targetTopic, /^pdd_account_[a-f0-9]{64}$/);
    // Everyone: confirmation first.
    await page.click('#nt-publish');
    assert.equal(await page.isVisible('#nt-confirm'), true);
    await page.click('#nt-confirm-send');
    await page.waitForFunction(() => document.querySelectorAll('#nt-history .nf-msg').length === 7);
    // Permanent means inbox-only, and copying preserves the chosen lifetime.
    await page.check('input[name="nt-place"][value="popup"]', { force: true });
    await page.check('input[name="nt-days"][value="forever"]', { force: true });
    assert.equal(await page.isChecked('input[name="nt-place"][value="news"]'), true);
    assert.equal(await page.isDisabled('input[name="nt-place"][value="popup"]'), true);
    assert.equal(await page.isDisabled('input[name="nt-place"][value="banner"]'), true);
    assert.equal(await page.isDisabled('#nt-push'), true);
    assert.equal(await page.isVisible('#nt-tabs [data-tab="home"]'), false);
    assert.match(await page.textContent('#nt-lifetime-note'), /Только в списке/);
    await page.fill('#nt-title', 'История обновлений');
    await page.click('#nt-publish');
    assert.match(await page.textContent('#nt-confirm-tags'), /Постоянно/);
    await page.click('#nt-confirm-send');
    await page.waitForFunction(() => document.querySelectorAll('#nt-history .nf-msg').length === 8);
    const permanent = [...app.data.values()].find(m => m?.persistent);
    assert.equal(permanent.kind, 'news');
    assert.ok(permanent.expiresAt > Date.now() + 365 * 86400000);
    await page.click('[data-nt-copy="' + permanent.id + '"]');
    assert.equal(await page.isChecked('input[name="nt-days"][value="forever"]'), true);
    await page.check('input[name="nt-days"][value="1"]', { force: true });
    assert.equal(await page.isDisabled('input[name="nt-place"][value="popup"]'), false);
    assert.equal(await page.isDisabled('#nt-push'), false);
    assert.match(await page.textContent('#nt-lifetime-note'), /исчезнет и из списка/);
    await page.click('[data-nt-toggle="' + permanent.id + '"]');
    await page.waitForFunction(id => document.querySelector('[data-nt-toggle="'+id+'"]').dataset.enabled === 'true', permanent.id);
    assert.equal(app.data.get('message:' + permanent.id).enabled, false);
    for (const width of [390, 820]) {
      await page.setViewportSize({ width, height: 900 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'no horizontal scroll at ' + width);
    }
    assert.deepEqual(errors, []);
  } finally { await browser.close(); await app.close(); }
});

if (!process.argv.includes('--serve')) test('notification history shows deadlines and updates expiry locally', { timeout: 30000 }, async t => {
  let chromium;
  try { ({ chromium } = createRequire(import.meta.url)('playwright')); } catch { t.skip('Playwright не найден (NODE_PATH)'); return; }
  const app = await preview();
  const now = Date.now(), messages = [...app.data.values()].filter(m => m?.id);
  const temporary = messages.find(m => m.kind === 'popup');
  temporary.expiresAt = now + 65000;
  const permanent = messages.find(m => m.kind === 'banner');
  Object.assign(permanent, { kind: 'news', persistent: true, expiresAt: 253402300799999 });
  const scheduled = messages.find(m => m.kind === 'push');
  Object.assign(scheduled, { kind: 'news', startAt: now + 3600000, expiresAt: now + 7200000, status: 'scheduled' });
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  try {
    const page = await browser.newPage({ viewport: { width: 1268, height: 1000 } });
    await page.clock.install({ time: new Date(now) });
    let reads = 0;
    page.on('request', request => { if (new URL(request.url()).pathname === '/api/admin/notifications' && request.method() === 'GET') reads++; });
    await page.goto(app.url + '/admin');
    await page.click('[data-feature="notifications"]');
    const row = page.locator('[data-nt-message="'+temporary.id+'"]');
    await row.waitFor();
    assert.match(await row.textContent(), /Исчезнет:.*МСК.*Осталось: [12] мин/);
    assert.equal(await row.locator('time').getAttribute('datetime'), new Date(temporary.expiresAt).toISOString());
    assert.match(await page.locator('[data-nt-message="'+permanent.id+'"] [data-nt-lifetime]').textContent(), /Без срока/);
    assert.match(await page.locator('[data-nt-message="'+scheduled.id+'"] [data-nt-lifetime]').textContent(), /Исчезнет:.*Осталось:/);
    await page.clock.fastForward(61000);
    assert.match(await row.locator('[data-nt-lifetime]').textContent(), /Осталось: [1-9] с/);
    const requestsBefore = reads;
    await page.clock.fastForward(5000);
    assert.match(await row.locator('[data-nt-lifetime]').textContent(), /Исчезло из приложения:/);
    assert.match(await row.locator('[data-nt-status]').textContent(), /Срок истёк/);
    assert.equal(await row.locator('[data-nt-toggle]').count(), 0);
    assert.equal(reads, requestsBefore, 'the countdown never polls the server');
    if (process.env.NOTIFICATIONS_UI_SCREENSHOTS) {
      await page.locator('#nt-history').screenshot({ path: fileURLToPath(new URL('../../../output/notification-history-countdown.png', import.meta.url)) });
    }
    for (const width of [390, 820]) {
      await page.setViewportSize({ width, height: 900 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'countdown fits at ' + width);
    }
  } finally { await browser.close(); await app.close(); }
});
