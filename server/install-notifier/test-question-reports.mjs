import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { sendTelegram } from './worker.js';
import { signSession, revokeUserSessions } from './user_auth.js';
import { TelegramQueue } from './telegram_queue.js';

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
  const env = { INSTALLS: new Storage(), BOT_TOKEN: 'test', CHAT_ID: 'test', SHARED_SECRET: 'test', SESSION_SECRET: 'test', TELEGRAM_TOPIC_ERRORS: '7', TELEGRAM_TOPIC_PURCHASES: '8', TELEGRAM_TOPIC_REGISTRATIONS: '9' };
  const state = { storage: new Storage() }, queue = new TelegramQueue(state, env);
  env.TELEGRAM = { idFromName: name => name, get: () => ({ fetch: (url, options) => queue.fetch(new Request(url, options)) }) };
  return { env, state };
}
const request = (body, token, path = '/') => new Request('https://test' + path, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { 'content-type': 'application/json', 'x-install-secret': 'test', ...(token ? { authorization: 'Bearer ' + token } : {}) },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});
const session = (env, user, expiresAt = Date.now() + 60000) => signSession(env, { user, expiresAt, generation: '' });
const queued = async state => [...(await state.storage.list({ prefix: 'q:' })).values()];

test('complaints use their own topic and server profile, ignoring forged identity', async () => {
  const { env, state } = setup();
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ errors: 7, purchases: 8, registrations: 9, reports: 42 }));
  const user = { id: 'google_real', name: 'Old name', email: 'old@example.com' };
  await env.INSTALLS.put('user:' + user.id, JSON.stringify({ ...user, name: '<Иван & Анна>', email: 'real@example.com' }));
  const token = await session(env, user);
  const response = await worker.fetch(request({ kind: 'report', message: '<Опечатка>', question_id: 'ru_ab_21_4', ticket: 21, userId: 'victim', user: { name: 'Подмена', email: 'victim@example.com' }, email: 'victim@example.com' }, token), env);
  assert.equal(response.status, 200);
  const [item] = await queued(state);
  assert.equal(item.threadId, 42);
  assert.match(item.text, /&lt;Иван &amp; Анна&gt;/);
  assert.match(item.text, /real@example.com/);
  assert.match(item.text, /google_real/);
  assert.match(item.text, /&lt;Опечатка&gt;/);
  assert.match(item.text, /ru_ab_21_4/);
  assert.doesNotMatch(item.text, /victim|Подмена|Old name|old@example/);
});

test('guests, old clients, invalid, expired and revoked sessions can report without claiming an account', async () => {
  const { env, state } = setup();
  const user = { id: 'google_real', name: 'Private name', email: 'private@example.com' };
  const expired = await session(env, user, Date.now() - 1), revoked = await session(env, user);
  await revokeUserSessions(env, user.id);
  for (const token of [undefined, 'forged', expired, revoked]) {
    const response = await worker.fetch(request({ kind: 'report', message: 'Ошибка', name: user.name, email: user.email, user_id: user.id }, token), env);
    assert.equal(response.status, 200);
  }
  for (const item of await queued(state)) {
    assert.match(item.text, /Гость \(без подтверждённого входа\)/);
    assert.doesNotMatch(item.text, /Private name|private@example.com|google_real/);
  }
});

test('game complaints log verified email, device, OS, scene and question text', async () => {
  const { env, state } = setup();
  const user = { id: 'google_driver', name: 'Водитель', email: 'driver@example.com' };
  const token = await session(env, user);
  const response = await worker.fetch(request({
    kind: 'report', mode: 'city', question_id: 'ticket_8_15', ticket: 8,
    question_text: 'Кому уступить дорогу?', message: 'Машина едет неверно',
    device: 'Google Pixel 9', os: 'Android 16 (SDK 36)', version: '2.3.0+59',
    platform: 'android', email: 'forged@example.com',
  }, token), env);
  assert.equal(response.status, 200);
  const [item] = await queued(state);
  for (const field of ['driver@example.com', 'Google Pixel 9', 'Android 16', 'ticket_8_15', 'билет 8', 'city', 'Кому уступить дорогу?', '2.3.0+59']) {
    assert.ok(item.text.includes(field), field);
  }
  assert.doesNotMatch(item.text, /forged@example.com/);
});

test('verified session identity survives a missing profile or profile lookup failure', async () => {
  for (const failLookup of [false, true]) {
    const { env, state } = setup(), user = { id: 'apple_real', name: 'Иван', email: '' };
    const token = await session(env, user);
    if (failLookup) {
      const original = env.INSTALLS.get.bind(env.INSTALLS);
      env.INSTALLS.get = key => key.startsWith('user:') ? Promise.reject(new Error('unavailable')) : original(key);
    }
    assert.equal((await worker.fetch(request({ kind: 'report', message: 'Ошибка' }, token), env)).status, 200);
    const [item] = await queued(state);
    assert.match(item.text, /Иван/);
    assert.match(item.text, /Email:<\/b> —/);
    assert.doesNotMatch(item.text, /Гость/);
  }
});

test('topic setup reuses existing IDs and creates only the complaint topic once', async () => {
  const { env, state } = setup(), original = globalThis.fetch, calls = [];
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ support: 100 }));
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  let writes = 0;
  env.INSTALLS.put = async (key, value) => { if (key === 'telegram_topics') writes++; return put(key, value); };
  globalThis.fetch = async (url, options) => {
    calls.push(JSON.parse(options.body));
    assert.match(url, /createForumTopic$/);
    return Response.json({ ok: true, result: { message_thread_id: 42 } });
  };
  try {
    for (let i = 0; i < 2; i++) {
      const response = await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env);
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).topics, { errors: 7, purchases: 8, registrations: 9, reports: 42 });
    }
    assert.equal(calls.length, 1);
    assert.equal(writes, 1, 'one KV write for setup, none for an unchanged retry');
    assert.equal(calls[0].name, '🚩 Жалобы на вопросы');
    assert.equal(JSON.parse(await env.INSTALLS.get('telegram_topics')).support, 100);
    assert.equal((await queued(state)).length, 1, 'only the new topic gets an announcement');
    const response = await worker.fetch(request(undefined, null, '/api/admin/telegram/topics'), env);
    assert.equal((await response.json()).topics.reports, 42);
  } finally { globalThis.fetch = original; }
});

test('topic setup rejects unauthorized requests and invalid IDs without creating topics', async () => {
  const { env } = setup();
  const unauthorized = new Request('https://test/api/admin/telegram/setup-topics', { method: 'POST', body: '{}' });
  assert.equal((await worker.fetch(unauthorized, env)).status, 401);
  for (const reports of [0, -1, 1.5, 'oops', null, true, [], {}]) {
    const response = await worker.fetch(request({ reports }, null, '/api/admin/telegram/setup-topics'), env);
    assert.equal(response.status, 400, JSON.stringify(reports));
  }
  assert.equal((await worker.fetch(request({ errors: 99 }, null, '/api/admin/telegram/setup-topics'), env)).status, 409);
});

test('concurrent setup requests create one complaint topic through the durable queue', async () => {
  const { env } = setup(), original = globalThis.fetch;
  let creates = 0;
  globalThis.fetch = async () => Response.json({ ok: true, result: { message_thread_id: 41 + ++creates } });
  try {
    const responses = await Promise.all([1, 2].map(() => worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)));
    assert.equal(creates, 1);
    for (const response of responses) assert.equal((await response.json()).topics.reports, 42);
  } finally { globalThis.fetch = original; }
});

test('partial topic creation saves IDs so the next attempt resumes without duplicates', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM_TOPIC_ERRORS; delete env.TELEGRAM_TOPIC_PURCHASES; delete env.TELEGRAM_TOPIC_REGISTRATIONS;
  let calls = 0;
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  let writes = 0;
  env.INSTALLS.put = async (key, value) => { if (key === 'telegram_topics') writes++; return put(key, value); };
  globalThis.fetch = async () => {
    calls++;
    return calls === 2 ? Response.json({ ok: false }, { status: 502 }) : Response.json({ ok: true, result: { message_thread_id: calls + 10 } });
  };
  try {
    assert.equal((await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)).status, 502);
    assert.equal(writes, 1);
    assert.equal(JSON.parse(await env.INSTALLS.get('telegram_topics')).errors, 11);
    assert.equal((await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)).status, 200);
    assert.equal(writes, 2);
    assert.equal(calls, 5);
    assert.equal(JSON.parse(await env.INSTALLS.get('telegram_topics')).errors, 11);
  } finally { globalThis.fetch = original; }
});

test('direct Telegram fallback also resolves the saved complaint topic', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM;
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ reports: 42 }));
  globalThis.fetch = async (_, options) => {
    assert.equal(JSON.parse(options.body).message_thread_id, 42);
    return Response.json({ ok: true });
  };
  try { assert.equal((await sendTelegram(env, 'Test', null, { topic: 'reports' })).status, 200); }
  finally { globalThis.fetch = original; }
});

test('an immediate partial-setup retry preserves newly created IDs despite the KV per-key limit', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM_TOPIC_ERRORS; delete env.TELEGRAM_TOPIC_PURCHASES; delete env.TELEGRAM_TOPIC_REGISTRATIONS;
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  let lastWrite = 0, limited = 0, creates = 0;
  env.INSTALLS.put = async (key, value) => {
    if (key === 'telegram_topics') {
      if (Date.now() - lastWrite < 1000) { limited++; throw new Error('KV PUT failed: 429 Too Many Requests'); }
      lastWrite = Date.now();
    }
    return put(key, value);
  };
  globalThis.fetch = async () => {
    creates++;
    return creates === 2 ? Response.json({ ok: false }, { status: 502 }) : Response.json({ ok: true, result: { message_thread_id: creates + 10 } });
  };
  try {
    assert.equal((await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)).status, 502);
    const response = await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env);
    assert.equal(response.status, 200);
    assert.equal(limited, 1);
    assert.equal(creates, 5, 'no duplicate topics after the KV retry');
    assert.deepEqual(JSON.parse(await env.INSTALLS.get('telegram_topics')), { errors: 11, purchases: 13, registrations: 14, reports: 15 });
  } finally { globalThis.fetch = original; }
});
