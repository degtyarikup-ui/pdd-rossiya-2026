import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { accountRead } from './account_state.js';
import { fixture, identity, session, request, MemoryStorage } from './fixture-account.mjs';
import { SupportThread } from './support_thread.js';
import { handleSupportGetMessages, resetSupportPollThrottle } from './support_chat.js';

async function clocked(run, start = Date.now()) {
  const RealDate = Date;
  let now = start;
  globalThis.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [now])); }
    static now() { return now; }
  };
  try { await run(value => { now = value; }, start); }
  finally { globalThis.Date = RealDate; }
}

function countStorage(env) {
  const writes = [];
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  env.INSTALLS.put = async (...args) => { writes.push(args[0]); return put(...args); };
  const get = env.ACCOUNTS.get.bind(env.ACCOUNTS);
  const calls = [];
  env.ACCOUNTS.get = id => ({ fetch: (input, options) => {
    calls.push(typeof input === 'string' ? new URL(input).pathname : new URL(input.url).pathname);
    return get(id).fetch(input, options);
  } });
  return { writes, calls };
}

test('100 changed answers commit immediately with one DO request per sync and batched KV projections', async () => clocked(async (setTime, start) => {
  const { env, restart, objects, states } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify(identity()));
  const token = await session(env), { writes, calls } = countStorage(env);
  const progress = { questionProgressAb: {} };
  for (let i = 0; i < 100; i++) {
    setTime(start + i * 1000);
    progress.questionProgressAb['q' + i] = { answeredAt: Date.now(), correct: i % 2 === 0 };
    const response = await worker.fetch(request('/api/user/progress/sync', {
      userId: 'google_123', progress, appVersion: '2.2.4+90', platform: 'android',
    }, token), env);
    assert.equal(response.status, 200);
    // The acknowledged primary snapshot is complete before any projection runs.
    assert.equal(Object.keys((await response.json()).progress.questionProgressAb).length, i + 1);
    if (await states.get('google_123').getAlarm() <= Date.now()) await objects.get('google_123').alarm();
  }
  assert.equal(writes.filter(key => key === 'user_progress:google_123').length, 1);
  assert.equal(writes.filter(key => key === 'user:google_123').length, 1);
  assert.equal(calls.length, 100);
  restart('google_123');
  const response = await worker.fetch(request('/api/user/progress?userId=google_123', undefined, token), env);
  assert.equal(Object.keys((await response.json()).progress.questionProgressAb).length, 100);
  await objects.get('google_123').alarm();
  assert.equal(Object.keys(JSON.parse(await env.INSTALLS.get('user_progress:google_123')).questionProgressAb).length, 100);
  assert.equal(writes.filter(key => key === 'user_progress:google_123').length, 2);
}));

test('unchanged retries do no KV writes; heartbeat and changed platform/version remain visible', async () => clocked(async (setTime, start) => {
  const { env, objects } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify(identity()));
  const token = await session(env), { writes } = countStorage(env);
  const body = { userId: 'google_123', progress: {}, appVersion: '2.2.4+90', platform: 'android' };
  const sync = async () => {
    const response = await worker.fetch(request('/api/user/progress/sync', body, token), env);
    assert.equal(response.status, 200); return response.json();
  };
  const initial = await sync(); await objects.get('google_123').alarm(); writes.length = 0;
  for (let i = 1; i <= 100; i++) {
    setTime(start + i * 1000);
    assert.equal((await sync()).serverUpdatedAt, initial.serverUpdatedAt);
  }
  assert.equal(writes.length, 0);
  setTime(start + 5 * 60000); await sync(); await objects.get('google_123').alarm();
  assert.deepEqual(writes.sort(), ['user:google_123', 'user_progress:google_123']);
  writes.length = 0; setTime(start + 5 * 60000 + 1000);
  body.platform = 'ios'; body.appVersion = '2.3.0+100'; await sync();
  const user = JSON.parse(await accountRead(env, 'google_123', 'user:google_123'));
  assert.equal(user.platform, 'ios'); assert.equal(user.appVersion, '2.3.0+100');
  assert.equal(user.activity.ios, '1');
  assert.equal(user.versionObservations.ios.version, '2.3.0+100');
  await objects.get('google_123').alarm();
  assert.ok(writes.includes('user:google_123'));
}));

test('Moscow midnight records daily activity immediately inside the heartbeat interval', async () => clocked(async (setTime, start) => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify(identity()));
  const token = await session(env);
  const body = { userId: 'google_123', progress: {}, platform: 'android' };
  await worker.fetch(request('/api/user/progress/sync', body, token), env);
  setTime(start + 2000);
  await worker.fetch(request('/api/user/progress/sync', body, token), env);
  const user = JSON.parse(await accountRead(env, 'google_123', 'user:google_123'));
  assert.equal(user.activity.date, '2026-10-23'); assert.equal(user.activity.android, '3');
}, Date.parse('2026-10-22T20:59:59Z')));

test('single routed request still checks revocation, deletion and foreign account access immediately', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify(identity()));
  const token = await session(env);
  const { calls } = countStorage(env);
  assert.equal((await worker.fetch(request('/api/user/status', undefined, token), env)).status, 200);
  assert.equal(calls.length, 1);
  assert.equal((await worker.fetch(request('/api/user/progress?userId=google_other', undefined, token), env)).status, 403);
  const forged = token.slice(0, -1) + (token.endsWith('a') ? 'b' : 'a');
  assert.equal((await worker.fetch(request('/api/user/status', undefined, forged), env)).status, 401);
  await worker.fetch(request('/api/auth/logout', {}, token), env);
  assert.equal((await worker.fetch(request('/api/user/status', undefined, token), env)).status, 401);
  const next = await session(env);
  assert.equal((await worker.fetch(request('/api/user/delete', { userId: 'google_123' }, next), env)).status, 200);
  assert.equal((await worker.fetch(request('/api/user/status', undefined, next), env)).status, 401);
});

test('idle support polls migrate KV once and never reseed on an empty incremental response', async () => {
  for (const legacy of [[], [{ id: 'old', ts: 1000, sender: 'user', text: 'test' }]]) {
    const state = { storage: new MemoryStorage() };
    const thread = new SupportThread(state);
    let reads = 0, invocations = 0;
    const env = { INSTALLS: { get: async () => { reads++; return legacy; } },
      SUPPORT: { idFromName: id => id, get: () => ({ fetch: (url, options) => {
        invocations++; return thread.fetch(new Request(url, options));
      } }) } };
    const poll = () => handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=test&since=1000'), env);
    assert.equal((await poll()).status, 200);
    assert.equal(reads, 1);
    invocations = 0;
    for (let i = 0; i < 100; i++) assert.deepEqual((await (await poll()).json()).messages, []);
    assert.equal(invocations, 100); assert.equal(reads, 1);
    // A new Telegram reply appears on the very next poll, without cache delay.
    await thread.fetch(new Request('https://support/append', { method: 'POST', body: JSON.stringify({ id: 'reply', ts: 2000, text: 'reply' }) }));
    assert.equal((await (await poll()).json()).messages[0].id, 'reply');
  }
});

test('idle support polls read the active webhook flag once per minute, never cache replies', async () => clocked(async (setTime, start) => {
  resetSupportPollThrottle();
  const state = { storage: new MemoryStorage() }, thread = new SupportThread(state);
  await thread.fetch(new Request('https://support/append', { method: 'POST', body: JSON.stringify({ id: 'first', ts: start, text: 'hi' }) }));
  let reads = 0;
  const env = { BOT_TOKEN: 'fixture', CHAT_ID: 'fixture', INSTALLS: {
    get: async key => { assert.equal(key, 'tg:webhook_active'); reads++; return '1'; },
  }, SUPPORT: { idFromName: id => id, get: () => ({ fetch: (url, options) => thread.fetch(new Request(url, options)) }) } };
  const poll = () => handleSupportGetMessages(new Request('https://test/api/support/messages?clientId=test'), env);
  for (let i = 0; i < 100; i++) assert.equal((await poll()).status, 200);
  assert.equal(reads, 1);
  await thread.fetch(new Request('https://support/append', { method: 'POST', body: JSON.stringify({ id: 'reply', ts: start + 1, text: 'reply' }) }));
  assert.equal((await (await poll()).json()).messages.at(-1).id, 'reply');
  setTime(start + 60000); await poll(); assert.equal(reads, 2);
  resetSupportPollThrottle();
}));

test('profile sync defers email index repair and does not rewrite an unchanged mapping', async () => {
  const { env, objects } = fixture(), token = await session(env), { writes } = countStorage(env);
  const sync = () => worker.fetch(request('/api/user/sync', { id: 'google_123' }, token), env);
  assert.equal((await sync()).status, 200);
  const emailKey = 'user_email:fixture@example.invalid';
  assert.equal(writes.filter(key => key === emailKey).length, 0);
  await objects.get('google_123').alarm();
  assert.equal(writes.filter(key => key === emailKey).length, 1);
  assert.equal((await sync()).status, 200);
  await objects.get('google_123').alarm();
  assert.equal(writes.filter(key => key === emailKey).length, 1);
  await env.INSTALLS.delete(emailKey);
  assert.equal((await sync()).status, 200);
  await objects.get('google_123').alarm();
  assert.equal(await env.INSTALLS.get(emailKey), 'google_123');
});
