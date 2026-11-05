import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { SecurityState, SupportThread } from './worker.js';
import { signSession } from './user_auth.js';
import { digest } from './request_security.js';
class KV {
  data = new Map();
  async get(k, opts) { const value = this.data.get(k) ?? null; return opts?.type === 'json' && value !== null ? JSON.parse(value) : value; }
  async put(k, v) { this.data.set(k, String(v)); }
  async delete(k) { this.data.delete(k); }
  async list({ prefix = '' } = {}) { return { keys: [...this.data.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name })), list_complete: true }; }
}
function state() {
  const data = new Map(); let alarm = null;
  const storage = { get: async k => data.get(k), put: async (k, v) => { if (typeof k === 'object') for (const [a,b] of Object.entries(k)) data.set(a,b); else data.set(k,v); }, delete: async k => data.delete(k),
    setAlarm: async v => { alarm = v; }, getAlarm: async () => alarm, list: async () => data };
  storage.transaction = fn => fn(storage); return { storage };
}
function env() {
  const e = { INSTALLS: new KV(), ADMIN_PASSWORD: crypto.randomUUID(), SESSION_SECRET: crypto.randomUUID(), SHARED_SECRET: crypto.randomUUID() };
  const ns = Class => {
    const objects = new Map();
    return { idFromName: k => k, get: k => {
      if (!objects.has(k)) {
        const obj = new Class(state(), e);
        objects.set(k, { fetch: (input, opts) => obj.fetch(input instanceof Request ? input : new Request(input, opts)) });
      }
      return objects.get(k);
    } };
  };
  e.SUPPORT = ns(SupportThread); e.SECURITY = ns(SecurityState); return e;
}
function req(path, body, headers = {}) {
  return new Request('https://fixture.test' + path, { method: body === undefined ? 'GET' : 'POST', headers: { 'content-type': 'application/json', ...headers }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
}
async function session(e, id = 'google_fixture') {
  const token = await signSession(e, { user: { id, name: 'Fixture', provider: 'google' }, expiresAt: Date.now() + 3600000, generation: '' });
  return { authorization: 'Bearer ' + token };
}
async function seed(e, id, text = 'private', imageUrl) {
  await e.SUPPORT.get(id).fetch('https://support/append', { method: 'POST', body: JSON.stringify({ id: crypto.randomUUID(), ts: Date.now(), text, sender: 'user', ...(imageUrl ? { imageUrl } : {}) }) });
}
test('account support rejects anonymous, cross-account and app-key-only reads and writes', async () => {
  const e = env(); await seed(e, 'google_fixture');
  const other = await session(e, 'google_other'), own = await session(e);
  for (const headers of [{}, { 'x-install-secret': e.SHARED_SECRET }, other]) {
    const status = headers === other ? 403 : 401;
    assert.equal((await worker.fetch(req('/api/support/messages?clientId=google_fixture', undefined, headers), e)).status, status);
    assert.equal((await worker.fetch(req('/api/support/send', { clientId: 'google_fixture', text: 'impersonation' }, headers), e)).status, status);
  }
  const r = await worker.fetch(req('/api/support/messages?clientId=google_fixture', undefined, own), e);
  assert.equal(r.status, 200); assert.equal((await r.json()).messages[0].text, 'private');
});
test('guest support needs a separate secret and signed-out accounts cannot be treated as guests', async () => {
  const e = env(), secret = 'a'.repeat(64), id = 'guest_v2_' + await digest(secret);
  const r = await worker.fetch(req('/api/support/send', { clientId: id, text: 'guest' }, { 'x-support-secret': secret }), e);
  assert.equal(r.status, 200);
  assert.equal((await worker.fetch(req('/api/support/messages?clientId=' + id), e)).status, 401);
  assert.equal((await worker.fetch(req('/api/support/messages?clientId=' + id, undefined, { 'x-support-secret': secret }), e)).status, 200);
});
test('unsigned webhook has no state changes; verified Telegram reply still works', async () => {
  const e = env(); e.CHAT_ID = '-1000123456';
  await e.INSTALLS.put('support:thread:12', 'google_fixture');
  const update = { message: { message_id: 44, chat: { id: e.CHAT_ID }, message_thread_id: 12, from: { is_bot: false }, text: 'reply' } };
  assert.equal((await worker.fetch(req('/api/telegram/webhook', update, { 'x-telegram-bot-api-secret-token': 'invalid' }), e)).status, 401);
  assert.equal(await e.INSTALLS.get('tg:webhook_active'), null);
  const { telegramWebhookSecret } = await import('./telegram_auth.js');
  assert.equal((await worker.fetch(req('/api/telegram/webhook', update, { 'x-telegram-bot-api-secret-token': await telegramWebhookSecret(e) }), e)).status, 200);
});
test('every Telegram administrative API denies the public app key', async () => {
  const e = env();
  for (const [path, body] of [['/api/admin/telegram/topics'], ['/api/admin/telegram/setup-topics', {}], ['/api/admin/support/webhook-info'], ['/api/admin/support/setup-webhook', {}]]) {
    assert.equal((await worker.fetch(req(path, body, { 'x-install-secret': e.SHARED_SECRET }), e)).status, 401);
  }
});
test('one atomic attempt budget covers form and Bearer, including concurrent guesses', async () => {
  const e = env(), headers = { 'cf-connecting-ip': '192.0.2.1' };
  const results = await Promise.all(Array.from({ length: 16 }, (_, i) => worker.fetch(i % 2 ? req('/api/admin/session', undefined, { ...headers, authorization: 'Bearer invalid' }) : req('/api/admin/login', { password: 'invalid' }, headers), e)));
  assert.equal(results.filter(r => r.status === 401).length, 8);
  assert.equal(results.filter(r => r.status === 429).length, 8);
  assert.equal((await worker.fetch(req('/api/admin/session', undefined, { ...headers, authorization: 'Bearer ' + e.ADMIN_PASSWORD }), e)).status, 429);
});
test('admin password rotation invalidates old cookies and mutations need a CSRF token', async () => {
  const e = env(), login = await worker.fetch(req('/api/admin/login', { password: e.ADMIN_PASSWORD }), e);
  const cookie = login.headers.get('set-cookie').split(';')[0], csrf = (await login.json()).csrfToken;
  assert.equal((await worker.fetch(req('/api/admin/ai/legacy', { open: false }, { cookie }), e)).status, 403);
  assert.equal((await worker.fetch(req('/api/admin/ai/legacy', { open: false }, { cookie, 'x-admin-csrf': csrf, origin: 'https://attacker.test' }), e)).status, 403);
  assert.equal((await worker.fetch(req('/api/admin/ai/legacy', { open: false }, { cookie, 'x-admin-csrf': csrf, origin: 'https://fixture.test' }), e)).status, 200);
  assert.equal((await worker.fetch(req('/?report=daily&send=true', undefined, { cookie }), e)).status, 405);
  e.ADMIN_PASSWORD = crypto.randomUUID();
  assert.equal((await worker.fetch(req('/api/admin/session', undefined, { cookie }), e)).status, 401);
});
test('support files require the owning thread before Telegram and are never publicly cached', async t => {
  const e = env(); e.BOT_TOKEN = crypto.randomUUID();
  await seed(e, 'google_fixture', 'image', '/api/support/file?fileId=file-a');
  const auth = await session(e), calls = [];
  t.mock.method(globalThis, 'fetch', async url => {
    calls.push(url);
    return String(url).includes('/getFile?') ? Response.json({ ok: true, result: { file_path: 'photos/fixture.jpg' } }) : new Response('image', { headers: { 'content-type': 'image/jpeg' } });
  });
  assert.equal((await worker.fetch(req('/api/support/file?clientId=google_fixture&fileId=file-a'), e)).status, 401);
  assert.equal((await worker.fetch(req('/api/support/file?clientId=google_fixture&fileId=other', undefined, auth), e)).status, 404);
  assert.equal(calls.length, 0);
  const r = await worker.fetch(req('/api/support/file?clientId=google_fixture&fileId=file-a', undefined, auth), e);
  assert.equal(r.status, 200); assert.equal(r.headers.get('cache-control'), 'private, no-store');
});
test('account deletion purges support and prevents legacy seeding from resurrecting it', async () => {
  const e = env(); await seed(e, 'google_fixture');
  const r = await worker.fetch(req('/api/user/delete', { userId: 'google_fixture' }, { ...await session(e), 'x-install-secret': e.SHARED_SECRET }), e);
  assert.equal(r.status, 200);
  const stub = e.SUPPORT.get('google_fixture');
  await stub.fetch('https://support/seed', { method: 'POST', body: JSON.stringify([{ id: 'old', ts: 1, text: 'old' }]) });
  assert.deepEqual((await (await stub.fetch('https://support/list')).json()).messages, []);
});
test('anonymous lead budget cannot be reset by changing email and bodies are bounded', async () => {
  const e = env();
  for (let i = 0; i < 5; i++) assert.equal((await worker.fetch(req('/api/pay/lead', { email: 'fixture' + i + '@example.invalid', tier: 'weekly' }), e)).status, 200);
  assert.equal((await worker.fetch(req('/api/pay/lead', { email: 'other@example.invalid', tier: 'weekly' }), e)).status, 429);
  const large = await worker.fetch(req('/api/pay/lead', { padding: 'x'.repeat(9000) }), e);
  assert.equal(large.status, 413);
});
test('support retention and admin idle/absolute expiry use server time', async t => {
  const e = env(), now = Date.now();
  const login = await worker.fetch(req('/api/admin/login', { password: e.ADMIN_PASSWORD }), e);
  const cookie = login.headers.get('set-cookie').split(';')[0];
  await seed(e, 'google_fixture');
  t.mock.method(Date, 'now', () => now + 13 * 3600000);
  assert.equal((await worker.fetch(req('/api/admin/session', undefined, { cookie }), e)).status, 401);
  t.mock.method(Date, 'now', () => now + 91 * 86400000);
  const r = await e.SUPPORT.get('google_fixture').fetch('https://support/list');
  assert.deepEqual((await r.json()).messages, []);
});
