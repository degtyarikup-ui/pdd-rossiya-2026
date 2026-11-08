import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TelegramQueue } from './telegram_queue.js';
import { reportIncident, handleClientIncident, buildIncidentMessage } from './diagnostics.js';
import { authTransportIdentity } from './diagnostic_context.js';
import { providerLabel } from './incident_copy.js';
import { buildErrorCsv } from './telegram_export.js';
import { MemoryKV, MemoryStorage } from './fixture-account.mjs';

function fixture(t) {
  let now = Date.UTC(2026, 9, 26, 9);
  t.mock.method(Date, 'now', () => now);
  const fixtureAccess = 'fixture-app';
  const storage = new MemoryStorage(), env = {
    BOT_TOKEN: 'fixture', CHAT_ID: '-100123', TELEGRAM_TOPIC_ERRORS: '7',
    SHARED_SECRET: fixtureAccess, INSTALLS: new MemoryKV(),
  };
  let queue = new TelegramQueue({ storage }, env), respond = () => Response.json({ ok: true });
  const envelopes = [], calls = [], delivered = [];
  env.TELEGRAM = { idFromName: value => value, get: () => ({ fetch: async (url, options) => {
    envelopes.push(JSON.parse(options.body));
    return queue.fetch(new Request(url, options));
  } }) };
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.match(String(url), /^https:\/\/api\.telegram\.org\/botfixture\/sendMessage$/);
    const body = JSON.parse(options.body);
    calls.push(body);
    const response = await respond(body);
    if (response.ok) delivered.push(body);
    return response;
  });
  const incident = (overrides = {}) => ({
    id: crypto.randomUUID(), ts: now, origin: 'client', category: 'auth',
    operation: 'auth.session', code: 'network:1x', provider: 'google',
    platform: 'android', appVersion: '2.2.5+67', device: 'realme RMX2117',
    os: 'Android 12 (SDK 31)', installation: 'a'.repeat(16), userId: null,
    ...overrides,
  });
  const send = async overrides => {
    const event = incident(overrides);
    assert.equal(await reportIncident(env, event), true);
    return envelopes.at(-1).incident;
  };
  const fire = async () => { await storage.deleteAlarm(); await queue.alarm(); };
  const drain = async () => {
    for (let i = 0; i < 100; i++) {
      const deadline = await storage.getAlarm();
      if (deadline == null) return;
      now = Math.max(now, Number(deadline));
      await fire();
    }
    assert.fail('queue did not drain');
  };
  return { storage, env, incident, send, envelopes, calls, delivered, fire, drain,
    get queue() { return queue; },
    advance: ms => { now += ms; }, restart: () => { queue = new TelegramQueue({ storage }, env); },
    response: fn => { respond = fn; },
  };
}

test('known anonymous installation coalesces transport attempts across providers with every original technical detail', async t => {
  const f = fixture(t);
  const events = [
    await f.send({ code: 'network:1x', diagnosticId: crypto.randomUUID() }),
    await f.send({ operation: 'auth.provider', code: 'timeout:3x', provider: 'telegram', diagnosticId: crypto.randomUUID() }),
    await f.send({ code: 'network_error', provider: 'yandex', diagnosticId: crypto.randomUUID(), context: { attempt: 3, stage: 'server' } }),
  ];
  assert.equal(new Set(f.envelopes.map(item => item.fingerprint)).size, 1);
  await f.drain();
  assert.equal(f.delivered.length, 1);
  const text = f.delivered[0].text;
  assert.match(text, /Способы входа: Google · Telegram · Яндекс/);
  assert.doesNotMatch(text, /Вход: Google|Сервер:|Не определён/);
  for (const event of events) for (const detail of [event.operation, event.code, event.diagnosticId]) assert.ok(text.includes(detail), detail);
  assert.match(text, /Этап: server · попытка 3/);
  assert.equal(text.split('Установка:').length - 1, 1);
  assert.ok(text.length <= 4096);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 3);
  assert.ok(records.every(record => record.sent));
  assert.equal(records.filter(record => record.notificationReason === 'coalesced').length, 2);
  assert.ok(buildErrorCsv(records).includes('Telegram'));
});

test('hourly cooldown collapses six-minute retry bursts and exposes repeat/provider counts on next eligible alert', async t => {
  const f = fixture(t);
  await f.send();
  await f.drain();
  const attempts = [
    { provider: 'telegram', code: 'timeout:3x', operation: 'auth.provider' },
    { provider: 'yandex', code: 'network_error' },
    { provider: 'google', code: 'network:3x' },
    { provider: 'telegram', code: 'timeout:1x' },
    { provider: 'google', code: 'timeout:2x' },
    { provider: 'yandex', code: 'network:2x' },
  ];
  for (const event of attempts) { f.advance(6 * 60000); await f.send(event); await f.drain(); }
  assert.equal(f.delivered.length, 1, 'one warning rather than seven messages');
  let records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 7);
  assert.equal(records.filter(record => record.notificationReason === 'grouped').length, 6);
  assert.equal(await f.storage.getAlarm(), null, 'no hourly digest alarm is added');
  f.restart();
  f.advance(24 * 60000 + 1);
  await f.send({ provider: 'apple', code: 'timeout:3x' });
  await f.drain();
  assert.equal(f.delivered.length, 2);
  const text = f.delivered[1].text;
  assert.match(text, /Повторов с прошлого сообщения: 6/);
  assert.match(text, /Способы входа в свёрнутых повторах: Google — 2 · Яндекс — 2 · Telegram — 2/);
  records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 8);
  assert.equal(records.filter(record => record.sent).length, 2);
});

test('auth collection deadline and event delivery dedup survive restart without extending the first three seconds', async t => {
  const f = fixture(t), first = await f.send();
  assert.equal(await reportIncident(f.env, first), true);
  f.advance(2000);
  f.restart();
  await f.send({ provider: 'telegram', code: 'timeout:3x' });
  f.advance(999); await f.fire();
  assert.equal(f.calls.length, 0);
  f.restart(); f.advance(1); await f.fire();
  assert.equal(f.delivered.length, 1);
  assert.equal((await f.queue.readErrorLog(0)).length, 2);
  f.advance(1); await f.send({ code: 'network:2x' }); await f.drain();
  assert.equal(f.delivered.length, 1, 'later arrivals use cooldown rather than modifying a delivered message');
  assert.equal((await f.queue.readErrorLog(0)).length, 3);
});

test('transport scope rejects unrelated identity, provider, credential, billing and malformed-code contexts', async t => {
  const variations = [
    ['missing installation', { installation: null }], ['raw installation', { installation: 'a'.repeat(32) }],
    ['bad installation', { installation: 'not-an-id' }], ['known account', { userId: 'google_account' }],
    ['unknown provider', { provider: 'unknown' }], ['provider prototype', { provider: '__proto__' }],
    ['purchase', { category: 'purchase' }], ['payment context', { payment: {} }],
    ['paywall context', { context: { phase: 'paywall' } }], ['billing source', { context: { sdkSource: 'google_play' } }],
    ['framework failure', { context: { stage: 'framework' } }], ['server source', { origin: 'server' }],
    ['credential rejection', { code: 'credential_rejected' }], ['app key', { code: 'app_key_rejected' }],
    ['SDK configuration', { code: 'sdk_error' }], ['HTTP 403', { status: 403 }],
    ['HTTP injection', { status: '503' }], ['raw network detail', { code: 'network:credential_rejected' }],
    ['bad attempt suffix', { code: 'timeout:3x_extra' }], ['zero attempts', { code: 'timeout:0x' }],
    ['unknown platform', { platform: 'unknown' }], ['missing version', { appVersion: null }],
    ['recovered', { operation: 'auth.recovered' }], ['other operation', { operation: 'startup.auth' }],
  ];
  const f = fixture(t);
  assert.ok(authTransportIdentity(f.incident()));
  for (const [label, override] of variations) assert.equal(authTransportIdentity(f.incident(override)), null, label);
  const original = authTransportIdentity(f.incident());
  for (const override of [{ installation: 'b'.repeat(16) }, { platform: 'ios' }, { appVersion: '2.2.5+66' },
    { device: 'Other phone' }, { os: 'Android 13 (SDK 33)' }, { status: 503 }]) {
    assert.notEqual(authTransportIdentity(f.incident(override)), original);
  }
});

test('other installation and actionable credential/key/purchase failures remain separate during transport cooldown', async t => {
  const f = fixture(t);
  await f.send(); await f.drain();
  await f.send({ installation: 'b'.repeat(16), code: 'network:3x' });
  await f.send({ code: 'credential_rejected', status: 401 });
  await f.send({ code: 'app_key_rejected', status: 403 });
  await f.send({ category: 'purchase', operation: 'premium.verify', code: 'network_error' });
  await f.send({ provider: 'unknown', code: 'timeout:3x' });
  await f.drain();
  assert.equal(f.delivered.length, 6);
  assert.equal((await f.queue.readErrorLog(0)).length, 6);
});

test('auth.recovered stays log-only and does not reset or consume transport warning state', async t => {
  const f = fixture(t);
  await f.send(); await f.drain();
  await f.send({ operation: 'auth.recovered', code: 'fallback_ok:2x' });
  await f.send({ code: 'timeout:3x' }); await f.drain();
  assert.equal(f.delivered.length, 1);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 3);
  assert.equal(records.find(record => record.operation === 'auth.recovered').notificationReason, 'info_only');
  assert.equal(records.find(record => record.code === 'timeout:3x').notificationReason, 'grouped');
});

test('maximum auth batch keeps eight details and preserves overflow attempts in CSV and future repeat summary', async t => {
  const f = fixture(t);
  const events = [];
  for (let i = 0; i < 10; i++) events.push(await f.send({ code: 'network:' + (i + 1) + 'x',
    provider: i % 2 ? 'telegram' : 'google', diagnosticId: crypto.randomUUID() }));
  await f.drain();
  assert.equal(f.delivered.length, 1);
  assert.ok(f.delivered[0].text.length <= 4096);
  for (const event of events.slice(0, 8)) assert.ok(f.delivered[0].text.includes(event.diagnosticId));
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 10);
  assert.equal(records.filter(record => record.sent).length, 8);
  f.advance(3600001); await f.send(); await f.drain();
  assert.match(f.delivered[1].text, /Повторов с прошлого сообщения: 2/);
  assert.match(f.delivered[1].text, /Google — 1 · Telegram — 1/);
});

test('a new transport repeat cannot mutate an attempted batch or shorten Telegram retry_after after restart', async t => {
  const f = fixture(t);
  await f.send(); await f.send({ provider: 'telegram', code: 'timeout:3x' });
  f.response(() => Response.json({ ok: false, parameters: { retry_after: 60 } }, { status: 429 }));
  f.advance(3000); await f.fire();
  const firstText = f.calls[0].text;
  f.restart(); f.advance(1000); await f.send({ provider: 'yandex', code: 'network_error' });
  f.response(() => Response.json({ ok: true }));
  await f.fire();
  assert.equal(f.calls.length, 1);
  await f.drain();
  assert.equal(f.delivered.length, 1);
  assert.equal(f.delivered[0].text, firstText);
  assert.equal((await f.queue.readErrorLog(0)).length, 3);
});

test('client endpoint fingerprints no private identifiers and rejects unverified names and raw SDK details', async t => {
  const f = fixture(t), rawInstallation = 'c'.repeat(32);
  const body = { installId: rawInstallation, events: [{ id: 'd'.repeat(32), ts: Date.now(), category: 'auth',
    operation: 'auth.session', code: 'network:3x', provider: 'telegram', platform: 'android', appVersion: '2.2.5+67',
    device: '<realme>&', userId: 'google_forged', user: { name: 'PRIVATE_NAME', email: 'private@example.invalid' },
    context: { message: 'PRIVATE_TOKEN', url: 'https://private.invalid', sdkSource: 'PRIVATE_SOURCE' } }] };
  const response = await handleClientIncident(new Request('https://fixture.invalid/api/diagnostics', {
    method: 'POST', headers: { 'x-install-secret': 'fixture-app' }, body: JSON.stringify(body),
  }), f.env);
  assert.equal(response.status, 200);
  await f.drain();
  assert.equal(f.delivered.length, 1);
  assert.match(f.envelopes[0].fingerprint, /^[a-f0-9]{64}$/);
  const state = JSON.stringify([...f.storage.data]);
  assert.doesNotMatch(state, /PRIVATE_|private@example|private\.invalid|google_forged/);
  assert.ok(!state.includes(rawInstallation));
  assert.match(f.delivered[0].text, /&lt;realme&gt;&amp;/);
  assert.match(f.delivered[0].text, /Способы входа: Telegram/);
});

test('Telegram provider is named correctly in ordinary auth, CSV and prototype-safe labels', () => {
  assert.equal(providerLabel('telegram'), 'Telegram');
  assert.equal(providerLabel('__proto__'), 'Не определён');
  assert.match(buildIncidentMessage({ category: 'auth', operation: 'auth.provider', code: 'sdk_error',
    provider: 'telegram', ts: Date.now() }), /🔑 Вход: Telegram/);
});
