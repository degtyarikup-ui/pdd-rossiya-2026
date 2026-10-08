import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { reportIncident, handleClientIncident, errorCode, buildIncidentMessage } from './diagnostics.js';
import { incidentCopy } from './incident_copy.js';
import { TelegramQueue } from './telegram_queue.js';
import { handleAuth, signSession } from './user_auth.js';

class Storage {
  data = new Map(); alarm = null;
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '', limit = Infinity } = {}) { return new Map([...this.data].filter(([key]) => key.startsWith(prefix)).sort().slice(0, limit)); }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  async transaction(fn) { return fn(this); }
}
function setup() {
  const env = { SHARED_SECRET: 'test', SESSION_SECRET: 'test', BOT_TOKEN: 'test', CHAT_ID: 'test', INSTALLS: new Storage() };
  const state = { storage: new Storage() };
  const queue = new TelegramQueue(state, env);
  env.TELEGRAM = { idFromName: value => { assert.equal(value, 'test'); return value; }, get: () => ({ fetch: (url, options) => queue.fetch(new Request(url, options)) }) };
  return { env, state, queue };
}
const event = (overrides = {}) => ({ id: 'a'.repeat(32), ts: Date.now(), category: 'auth', operation: 'auth.provider', code: 'network', provider: 'google', platform: 'android', appVersion: '2.2.0+50', ...overrides });
const request = (body, headers = {}) => new Request('https://test/api/diagnostics', { method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': 'test', ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body) });
const messages = async state => [...(await state.storage.list({ prefix: 'q:' })).values()].map(item => item.text);

test('diagnostics require the app key, validate a whole batch and enforce actual byte limits', async () => {
  const { env, state } = setup();
  const valid = { installId: 'b'.repeat(32), events: [event()] };
  assert.equal((await handleClientIncident(request(valid, { 'x-install-secret': '' }), env)).status, 403);
  assert.equal((await handleClientIncident(request('x'.repeat(16385)), env)).status, 413);
  for (const body of [{ ...valid, installId: 'wrong' }, { ...valid, events: [event(), event({ ts: 0 })] }, { ...valid, events: [event({ category: 'infrastructure' })] }, { ...valid, events: [event({ operation: '<script>' })] }]) {
    assert.equal((await handleClientIncident(request(body), env)).status, 400);
  }
  assert.equal((await messages(state)).length, 0);
  assert.equal((await handleClientIncident(request(valid), env)).status, 200);
  assert.equal((await handleClientIncident(request(valid), env)).status, 200);
  assert.equal((await messages(state)).length, 1);
});

test('messages escape HTML, omit raw secrets and only show verified account identity', async () => {
  const { env, state } = setup();
  const token = await signSession(env, { user: { id: 'google_real' }, expiresAt: Date.now() + 60000, generation: '' });
  const body = { installId: 'b'.repeat(32), events: [event({ userId: 'google_fake', message: 'credential=TOP_SECRET', stack: 'Bearer TOP_SECRET', device: '<phone>' })] };
  await handleClientIncident(request(body, { authorization: 'Bearer ' + token }), env);
  const text = (await messages(state))[0];
  assert.doesNotMatch(text, /TOP_SECRET|google_fake|<phone>|b{32}/);
  assert.match(text, /&lt;phone&gt;/);
  assert.match(text, /Установка:/);
  body.events = [event({ id: 'c'.repeat(32), operation: 'auth.session', userId: 'google_real' })];
  await handleClientIncident(request(body, { authorization: 'Bearer ' + token }), env);
  assert.match((await messages(state))[1], /google_real/);
});

test('durable cooldown survives restarts, counts repeats and limits error storms without blocking purchases', async () => {
  const { env, state } = setup();
  await reportIncident(env, event());
  await reportIncident(env, event({ id: 'c'.repeat(32) }));
  const restarted = new TelegramQueue(state, env);
  env.TELEGRAM.get = () => ({ fetch: (url, options) => restarted.fetch(new Request(url, options)) });
  await reportIncident(env, event({ id: 'd'.repeat(32) }));
  assert.equal((await messages(state)).length, 1);
  const stored = await state.storage.get('errors:state');
  assert.equal(Object.values(stored.groups)[0].repeats, 2);
  Object.values(stored.groups)[0].at -= 600001;
  await state.storage.put('errors:state', stored);
  await reportIncident(env, event({ id: 'e'.repeat(32) }));
  assert.match((await messages(state))[1], /Повторов с прошлого сообщения:<\/b> 2/);
  for (let i = 0; i < 30; i++) await reportIncident(env, event({ id: crypto.randomUUID(), operation: 'test.failure_' + i }));
  assert.equal((await messages(state)).length, 20);
  await restarted.fetch(new Request('https://queue/enqueue', { method: 'POST', body: JSON.stringify({ text: 'Purchase success' }) }));
  assert.equal((await messages(state)).at(-1), 'Purchase success');
  assert.equal((await state.storage.get('errors:state')).overflow, 12);
});

test('auth failures use stable outcomes and request ID, with credentials excluded', async () => {
  const { env, state } = setup();
  let task;
  const r = await handleAuth(new Request('https://test/api/auth/session', { method: 'POST', headers: { 'x-install-secret': 'test' }, body: JSON.stringify({ provider: 'apple', credential: 'TOP_SECRET' }) }), env,
    async () => { throw new DOMException('TOP_SECRET', 'TimeoutError'); }, e => { task = reportIncident(env, e); });
  assert.equal(r.status, 401);
  // onFailure schedules in the worker; this direct hook is asynchronous.
  await task;
  const text = (await messages(state))[0];
  assert.match(text, /provider_timeout/);
  assert.ok(text.includes(r.headers.get('x-auth-diagnostic-id')));
  assert.doesNotMatch(text, /TOP_SECRET/);
});

test('worker catches storage crashes, preserves CORS and never recursively reports diagnostics delivery', async () => {
  const { env, state } = setup();
  env.INSTALLS.get = async () => { throw new Error('KV quota exceeded TOP_SECRET'); };
  const r = await worker.fetch(new Request('https://test/api/pay/status'), env);
  // Use user storage: reading a profile must fail instead of fabricating premium.
  const token = await signSession(env, { user: { id: 'google_real' }, expiresAt: Date.now() + 60000, generation: '' });
  const failed = await worker.fetch(new Request('https://test/api/user/premium', { headers: { authorization: 'Bearer ' + token } }), env);
  assert.equal(failed.status, 500);
  assert.equal(failed.headers.get('Access-Control-Allow-Origin'), '*');
  assert.match((await messages(state))[0], /storage_quota/);
  assert.doesNotMatch((await messages(state))[0], /TOP_SECRET/);
  env.TELEGRAM.get = () => ({ fetch: async () => { throw new Error('Telegram unavailable'); } });
  const unavailable = await worker.fetch(request({ installId: 'b'.repeat(32), events: [event()] }), { ...env, INSTALLS: new Storage() });
  assert.equal(unavailable.status, 503);
  assert.equal(r.status, 200);
});

test('classification never includes raw exception messages', () => {
  assert.equal(errorCode(new Error('KV quota exceeded: TOP_SECRET')), 'storage_quota');
  assert.equal(errorCode(new Error('https://provider/?token=TOP_SECRET')), 'operation_failed');
});

test('rejected authenticated purchase is reported but unauthorized traffic is quiet', async () => {
  const { env, state } = setup();
  const call = token => worker.fetch(new Request('https://test/api/user/purchase', { method: 'POST', headers: { 'x-install-secret': 'test', authorization: 'Bearer ' + token }, body: JSON.stringify({ store: 'googleplay', country: 'ru', productId: 'fake', purchaseToken: 'TOP_SECRET' }) }), env);
  assert.equal((await call('invalid')).status, 401);
  assert.equal((await messages(state)).length, 0);
  const token = await signSession(env, { user: { id: 'google_real' }, expiresAt: Date.now() + 60000, generation: '' });
  assert.equal((await call(token)).status, 422);
  assert.match((await messages(state))[0], /unknown_product/);
  assert.match((await messages(state))[0], /google_real/);
  assert.doesNotMatch((await messages(state))[0], /TOP_SECRET/);
});

test('progress failures show real profile identity, plain explanation and technical details last', async () => {
  const { env, state } = setup();
  await env.INSTALLS.put('user:google_real', JSON.stringify({ id: 'google_real', name: 'Анна <Тест>', email: 'anna@example.org', provider: 'google', platform: 'android', appVersion: '2.1.8+47', device: 'Pixel' }));
  await reportIncident(env, event({ category: 'infrastructure', origin: 'server', operation: 'api.user.progress.sync', code: 'operation_failed', status: 500, userId: 'google_real', platform: null, appVersion: null }));
  const message = (await messages(state))[0];
  assert.match(message, /Не удалось синхронизировать прогресс/);
  assert.match(message, /Локальный прогресс сохраняется на устройстве/);
  assert.match(message, /Точная причина пока не определена/);
  assert.match(message, /Анна &lt;Тест&gt;/);
  assert.match(message, /anna@example.org/);
  assert.match(message, /Вход:<\/b> Google/);
  assert.match(message, /Android · v2.1.8\+47/);
  assert.ok(message.indexOf('Пользователь:') < message.indexOf('Для диагностики:'));
  assert.ok(message.indexOf('Для диагностики:') < message.indexOf('api.user.progress.sync'));
});

test('storage outage retains trusted session context and unverified clients cannot invent a name', async () => {
  const { env, state } = setup();
  env.INSTALLS.get = async () => { throw new Error('unavailable'); };
  await reportIncident(env, event({ userId: 'google_real', user: { id: 'google_real', name: 'Анна', email: 'anna@example.org', provider: 'google' } }));
  assert.match((await messages(state))[0], /Анна/);
  assert.match((await messages(state))[0], /anna@example.org/);
  env.INSTALLS = new Storage();
  await handleClientIncident(request({ installId: 'b'.repeat(32), events: [event({ id: 'd'.repeat(32), operation: 'auth.session', userId: 'google_fake', user: { id: 'google_fake', name: 'FAKE_NAME', email: 'fake@example.org' }, userName: 'FAKE_NAME' })] }), env);
  const message = (await messages(state))[1];
  assert.match(message, /Аккаунт ещё не определён/);
  assert.doesNotMatch(message, /FAKE_NAME|fake@example.org|google_fake/);
});

test('known payment reasons are readable, unknown codes remain honest and message fits Telegram', () => {
  const message = buildIncidentMessage(event({ category: 'purchase', operation: 'api.user.purchase', code: 'purchase_belongs_to_another_account', provider: 'appstore' }));
  assert.match(message, /Эта покупка уже привязана к другому аккаунту/);
  assert.match(message, /App Store/);
  assert.match(buildIncidentMessage(event({ operation: 'constructor', code: '__proto__', provider: '__proto__', platform: 'constructor' })), /Точная причина пока не определена/);
  assert.match(incidentCopy(event({ operation: 'new.unknown', code: 'sdk_error' })).reason, /Точная причина пока не определена/);
  const longest = buildIncidentMessage(event({ category: 'infrastructure', origin: 'server', operation: 'api.user.progress.sync', code: 'storage_rate_limited', userId: '&'.repeat(200), userName: '&'.repeat(120), userEmail: '&'.repeat(160), device: '&'.repeat(100), installation: 'a'.repeat(16), diagnosticId: 'a'.repeat(36), status: 500 }), 1000000, 1000000);
  assert.ok(longest.length < 4096);
  assert.equal(errorCode(new Error('KV PUT failed: 429 Too Many Requests')), 'storage_rate_limited');
});
