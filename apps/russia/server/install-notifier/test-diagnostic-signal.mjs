import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TelegramQueue, sendErrorDigest } from './telegram_queue.js';
import { reportIncident, handleClientIncident, buildIncidentMessage } from './diagnostics.js';
import { diagnosticSignal, trackSignal, buildSignalDigest, SIGNAL_STALE_MS,
  SIGNAL_SPIKE_MIN_INSTALLS, SIGNAL_SPIKE_COOLDOWN_MS } from './diagnostic_signal.js';
import { providerLabel, incidentGuide } from './incident_copy.js';
import { buildErrorCsv } from './telegram_export.js';
import { MemoryKV, MemoryStorage } from './fixture-account.mjs';

const HOUR = 3600000;

function fixture(t) {
  let now = Date.UTC(2026, 10, 10, 9);
  t.mock.method(Date, 'now', () => now);
  const storage = new MemoryStorage(), env = {
    BOT_TOKEN: 'fixture', CHAT_ID: '-100123', TELEGRAM_TOPIC_ERRORS: '7',
    SHARED_SECRET: crypto.randomUUID(), INSTALLS: new MemoryKV(),
  };
  let queue = new TelegramQueue({ storage }, env);
  const delivered = [];
  env.TELEGRAM = { idFromName: value => value, get: () => ({
    fetch: (url, options) => queue.fetch(new Request(url, options)),
  }) };
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.match(String(url), /^https:\/\/api\.telegram\.org\/botfixture\/sendMessage$/);
    delivered.push(JSON.parse(options.body));
    return Response.json({ ok: true });
  });
  let counter = 0;
  const install = n => n.toString(16).padStart(16, '0');
  const incident = (overrides = {}) => ({
    id: crypto.randomUUID(), ts: now, origin: 'client', category: 'auth',
    operation: 'auth.session', code: 'timeout:3x', provider: 'yandex',
    platform: 'android', appVersion: '2.2.14+77', device: 'Xiaomi 2412DPC0AG',
    os: 'Android 16 (SDK 36)', installation: install(++counter), userId: null,
    ...overrides,
  });
  const send = async overrides => assert.equal(await reportIncident(env, incident(overrides)), true);
  const drain = async () => {
    for (let i = 0; i < 100; i++) {
      const deadline = await storage.getAlarm();
      if (deadline == null) return;
      now = Math.max(now, Number(deadline));
      await storage.deleteAlarm();
      await queue.alarm();
    }
    assert.fail('queue did not drain');
  };
  return { storage, env, incident, send, delivered, drain, install,
    get queue() { return queue; }, get now() { return now; },
    advance: ms => { now += ms; }, restart: () => { queue = new TelegramQueue({ storage }, env); } };
}

const client = (operation, code, extra = {}) => ({ origin: 'client', operation, code, ...extra });

test('failures from the 10.11 export are classified by cause, not by where they surfaced', () => {
  const now = Date.UTC(2026, 10, 10, 9);
  const expectFamily = (family, cases) => {
    for (const [operation, code] of cases) {
      assert.deepEqual(diagnosticSignal(client(operation, code, { ts: now }), now), { kind: 'environment', family }, operation + ' ' + code);
    }
  };
  expectFamily('auth_server', [['auth.session', 'timeout:3x'], ['auth.session', 'network:3x'],
    ['telegram.request', 'network'], ['telegram.check', 'timeout']]);
  expectFamily('auth_provider', [['auth.provider', 'timeout'], ['auth.provider', 'network_error'],
    ['auth.provider', 'sign_in_failed'], ['auth.provider', 'sign_in_failed:7'], ['auth.provider', 'apple_unknown'],
    ['auth.provider', 'gms_unavailable:1'], ['yandex.webview', 'page_load_failed:hostLookup'],
    ['google.web_button', 'network']]);
  expectFamily('store', [['iap.products', 'store_unavailable'], ['iap.products', 'timeout'],
    ['iap.products', 'storekit2_products_error'], ['iap.init', 'timeout'], ['iap.products', 'billing_unavailable']]);
  expectFamily('payment', [['web_payment.check', 'network'], ['web_payment.start', 'network']]);
  expectFamily('app', [['flutter.framework', 'network:http'], ['flutter.framework', 'network:socket'],
    ['dart.unhandled', 'network:tls'], ['support.send', 'timeout']]);
});

test('failures we can fix, payment confirmation and server incidents are never moved to the background', () => {
  const now = Date.UTC(2026, 10, 10, 9);
  for (const [operation, code, extra] of [
    ['auth.provider', 'sign_in_failed:10'], ['auth.provider', 'sign_in_failed:12500'],
    ['auth.provider', 'missing_credential'], ['auth.provider', 'apple_failed'],
    ['auth.session', 'invalid_response'], ['auth.session', 'credential_rejected'], ['auth.session', 'app_key_rejected'],
    ['iap.products', 'products_not_found'], ['iap.products', 'sdk_error'], ['iap.products', 'developer_error'],
    ['iap.buy', 'timeout'], ['iap.restore', 'timeout'], ['iap.payment', 'network'],
    ['flutter.framework', 'invalid_response'], ['dart.unhandled', 'sdk_error'], ['dart.unhandled', 'platform:AndroidAudioError'],
    ['yandex.webview', 'page_load_failed:unknown'], ['yandex.callback', 'network'],
    ['web_payment.open', 'page_not_opened'], ['web_payment.start', 'invalid_response'],
    ['premium.verify', 'network'], ['iap.process', 'timeout'], ['iap.complete', 'network'],
    ['auth.session', 'network:credential_rejected_long'], ['auth.session', 'timeout:3x', { origin: 'server' }],
    ['api.user.sync', 'timeout', { origin: 'server' }],
  ]) {
    assert.equal(diagnosticSignal({ ...client(operation, code, { ts: now }), ...extra }, now), null, operation + ' ' + code);
  }
  // Even a week-old or emulator report about payment confirmation stays visible.
  assert.equal(diagnosticSignal(client('premium.verify', 'network', { ts: now - 5 * 24 * HOUR, device: 'Google sdk_gphone64_arm64' }), now), null);
});

test('a narration playback failure is a quiet, non-urgent alert rather than an unhandled application error', () => {
  const event = { origin: 'client', category: 'app', operation: 'narration.playback', code: 'playback_failed',
    platform: 'android', ts: Date.now(), context: { sdkCodeHash: 'a'.repeat(16) } };
  assert.equal(diagnosticSignal(event), null);
  assert.equal(incidentGuide(event).level, 'low');
  const text = buildIncidentMessage(event);
  assert.match(text, /🟡 <b>Не проигралась озвучка вопроса<\/b>/);
  assert.match(text, /Плеер устройства сообщил об ошибке воспроизведения/);
  assert.match(text, /Код SDK \(отпечаток\): a{16}/);
  assert.match(text, /Opus/);
});

test('late and emulator reports are background regardless of code, real devices are not mistaken for emulators', () => {
  const now = Date.UTC(2026, 10, 10, 9);
  assert.deepEqual(diagnosticSignal(client('iap.products', 'sdk_error', { ts: now - SIGNAL_STALE_MS - 1 }), now), { kind: 'stale' });
  assert.equal(diagnosticSignal(client('iap.products', 'sdk_error', { ts: now - SIGNAL_STALE_MS }), now), null);
  // The trusted reception time decides, not the processing time.
  assert.deepEqual(diagnosticSignal(client('auth.dialog', 'sdk_error', { ts: now - 30 * HOUR, receivedAt: now - HOUR }), now), { kind: 'stale' });
  for (const device of ['Google sdk_gphone64_arm64', 'Google Android SDK built for x86', 'unknown generic_x86_64', 'arm64', 'x86_64']) {
    assert.deepEqual(diagnosticSignal(client('auth.provider', 'sign_in_failed:10', { ts: now, device }), now), { kind: 'test_device' }, device);
  }
  for (const device of ['OnePlus OnePlus8Pro', 'iPhone16,2', 'samsung SM-A165F', 'Google Pixel 8', 'iPad11,6']) {
    assert.equal(diagnosticSignal(client('auth.provider', 'sign_in_failed:10', { ts: now, device }), now), null, device);
  }
});

test('a single connectivity failure is logged for the CSV and digest but sends nothing to the chat', async t => {
  const f = fixture(t);
  await f.send();
  await f.send({ operation: 'auth.provider', code: 'apple_unknown', provider: 'apple', platform: 'iOS' });
  await f.send({ category: 'purchase', operation: 'iap.products', code: 'store_unavailable', provider: 'googleplay' });
  await f.drain();
  assert.equal(f.delivered.length, 0);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 3);
  assert.ok(records.every(record => !record.sent && record.notificationReason === 'environment' && record.level === 'Фон'));
  assert.equal(buildErrorCsv(records).split('связь или устройство человека').length - 1, 3);
});

test('actionable failures still arrive immediately while connectivity noise stays silent', async t => {
  const f = fixture(t);
  await f.send();
  await f.send({ code: 'credential_rejected', status: 401 });
  await f.send({ code: 'app_key_rejected', status: 403 });
  await f.send({ operation: 'auth.provider', code: 'sign_in_failed:10', provider: 'google' });
  await f.send({ category: 'purchase', operation: 'iap.products', code: 'products_not_found', provider: 'googleplay' });
  await f.send({ category: 'purchase', operation: 'premium.verify', code: 'network_error' });
  await f.send({ category: 'app', operation: 'dart.unhandled', code: 'sdk_error', provider: null });
  await f.drain();
  assert.equal(f.delivered.length, 6);
  assert.ok(f.delivered.every(message => message.message_thread_id === 7));
  assert.equal((await f.queue.readErrorLog(0)).filter(record => record.sent).length, 6);
});

test('one alert when many installations fail within an hour, with a cooldown and no repeat for one person', async t => {
  const f = fixture(t);
  // One person retrying does not look like an outage.
  for (let i = 0; i < 12; i++) await f.send({ installation: f.install(999) });
  await f.drain();
  assert.equal(f.delivered.length, 0);
  for (let i = 1; i < SIGNAL_SPIKE_MIN_INSTALLS - 1; i++) { f.advance(60000); await f.send(); }
  await f.drain();
  assert.equal(f.delivered.length, 0, 'below the threshold');
  f.advance(60000);
  await f.send({ operation: 'telegram.request', code: 'network', provider: 'telegram', platform: 'iOS', appVersion: '2.2.11+74' });
  await f.drain();
  assert.equal(f.delivered.length, 1);
  const text = f.delivered[0].text;
  assert.match(text, /Всплеск: приложение не достаёт до нашего сервера при входе/);
  assert.match(text, new RegExp(`За последний час — ${SIGNAL_SPIKE_MIN_INSTALLS} разных установок \\(обычно меньше одной в час\\), событий: 17`));
  assert.match(text, /<code>auth\.session · timeout<\/code> — 16/);
  assert.match(text, /<code>telegram\.request · network<\/code> — 1/);
  assert.match(text, /Платформы: Android — 16 · iOS — 1/);
  assert.match(text, /\/export_day/);
  assert.equal(f.delivered[0].message_thread_id, 7);
  assert.ok(text.length <= 4096);
  // More failures inside the cooldown stay silent, also after a restart.
  f.restart();
  for (let i = 0; i < 10; i++) { f.advance(5 * 60000); await f.send(); }
  await f.drain();
  assert.equal(f.delivered.length, 1);
  f.advance(SIGNAL_SPIKE_COOLDOWN_MS);
  for (let i = 0; i < SIGNAL_SPIKE_MIN_INSTALLS; i++) await f.send();
  await f.drain();
  assert.equal(f.delivered.length, 2, 'a continuing outage is reported again after the cooldown');
  const records = await f.queue.readErrorLog(0);
  assert.ok(records.every(record => !record.sent && record.notificationReason === 'environment'));
});

test('different kinds of background failures do not add up to a false spike', async t => {
  const f = fixture(t);
  for (let i = 0; i < 4; i++) await f.send();
  for (let i = 0; i < 4; i++) await f.send({ operation: 'auth.provider', code: 'apple_unknown', provider: 'apple' });
  for (let i = 0; i < 4; i++) await f.send({ category: 'purchase', operation: 'iap.products', code: 'timeout' });
  for (let i = 0; i < 4; i++) await f.send({ category: 'app', operation: 'flutter.framework', code: 'network:http' });
  // Late reports describe the past and never count towards a current spike.
  for (let i = 0; i < 10; i++) await f.send({ ts: f.now - SIGNAL_STALE_MS - 60000 });
  await f.drain();
  assert.equal(f.delivered.length, 0);
});

test('the spike threshold follows the usual background level as the audience grows', () => {
  const start = Date.UTC(2026, 10, 10, 0);
  let state = null, spikes = 0, id = 0;
  const event = () => ({ operation: 'auth.session', code: 'timeout:3x', platform: 'android',
    appVersion: '2.2.14+77', installation: (++id).toString(16).padStart(16, '0') });
  // A day with five affected installations every hour: ordinary background.
  for (let hour = 0; hour < 24; hour++) {
    for (let i = 0; i < 5; i++) {
      const result = trackSignal(state, event(), start + hour * HOUR + i * 60000);
      state = result.state;
      if (result.spike) spikes++;
    }
  }
  assert.equal(spikes, 0);
  // The next hour now needs four times the usual level: 20 installations.
  const at = start + 24 * HOUR + 30 * 60000;
  for (let i = 0; i < 19; i++) {
    const result = trackSignal(state, event(), at + i * 1000);
    state = result.state;
    assert.equal(result.spike, null, 'installation ' + (i + 1));
  }
  const result = trackSignal(state, event(), at + 20000);
  assert.equal(result.spike?.installs, 20);
  assert.equal(Math.round(result.spike.usual), 5);
  assert.ok(Object.keys(result.state.hours).length <= 26, 'hour buckets are pruned');
  assert.ok(JSON.stringify(result.state).length < 20000, 'state stays far below the Durable Object value limit');
});

test('daily digest summarises what stayed out of the chat once per day', async t => {
  const f = fixture(t);
  assert.deepEqual(await sendErrorDigest(f.env), { ok: true, empty: true });
  await f.send(); await f.send(); await f.send({ installation: f.install(1) });
  await f.send({ operation: 'auth.provider', code: 'apple_unknown', provider: 'apple' });
  await f.send({ category: 'purchase', operation: 'web_payment.check', code: 'network', provider: 'platega' });
  await f.send({ category: 'app', operation: 'flutter.framework', code: 'network:http', device: 'Google sdk_gphone64_arm64' });
  await f.send({ category: 'purchase', operation: 'iap.products', code: 'sdk_error', ts: f.now - 5 * 24 * HOUR });
  await f.send({ code: 'credential_rejected', status: 401 });
  f.advance(HOUR);
  assert.equal((await sendErrorDigest(f.env)).queued, true);
  assert.equal((await sendErrorDigest(f.env)).duplicate, true, 'one digest per day');
  await f.drain();
  assert.equal(f.delivered.length, 2);
  const digest = f.delivered.find(message => /Фоновые сбои за сутки/.test(message.text));
  assert.equal(digest.message_thread_id, 7);
  assert.match(digest.text, /Фоновые сбои за сутки — 7/);
  assert.match(digest.text, /Затронуто установок: 6\./);
  assert.match(digest.text, /Не достали до нашего сервера при входе — 3 \(установок: 2\)/);
  assert.match(digest.text, /Окно входа Google \/ Apple \/ Яндекс не завершилось — 1 \(установок: 1\)/);
  assert.match(digest.text, /Нет связи при оплате через СБП — 1/);
  assert.match(digest.text, /Пришли с опозданием больше суток — 1/);
  assert.match(digest.text, /Эмуляторы и тестовые устройства — 1/);
  assert.match(digest.text, /<code>auth\.session · timeout<\/code> — 3/);
  assert.doesNotMatch(digest.text, /credential_rejected/, 'sent incidents are not repeated in the digest');
  // Records older than a day belong to the previous digest.
  assert.equal(buildSignalDigest((await f.queue.readErrorLog(0)).map(record => ({ ...record, sent: true }))), null);
});

test('client endpoint keeps private fields out of storage and escapes device names', async t => {
  const f = fixture(t), rawInstallation = 'c'.repeat(32);
  const body = { installId: rawInstallation, events: [{ id: 'd'.repeat(32), ts: Date.now(), category: 'auth',
    operation: 'auth.session', code: 'invalid_response', provider: 'telegram', platform: 'android', appVersion: '2.2.5+67',
    device: '<realme>&', userId: 'google_forged', user: { name: 'PRIVATE_NAME', email: 'private@example.invalid' },
    context: { message: 'PRIVATE_TOKEN', url: 'https://private.invalid', sdkSource: 'PRIVATE_SOURCE' } },
  { id: 'e'.repeat(32), ts: Date.now(), category: 'auth', operation: 'auth.session', code: 'network:3x',
    provider: 'telegram', platform: 'android', appVersion: '2.2.5+67', device: 'PRIVATE_DEVICE_NOTE',
    userId: 'google_forged', context: { message: 'PRIVATE_TOKEN' } }] };
  const response = await handleClientIncident(new Request('https://fixture.invalid/api/diagnostics', {
    method: 'POST', headers: { 'x-install-secret': f.env.SHARED_SECRET }, body: JSON.stringify(body),
  }), f.env);
  assert.equal(response.status, 200);
  await f.drain();
  assert.equal(f.delivered.length, 1);
  const state = JSON.stringify([...f.storage.data]);
  assert.doesNotMatch(state, /PRIVATE_(NAME|TOKEN|SOURCE)|private@example|private\.invalid|google_forged/);
  assert.ok(!state.includes(rawInstallation));
  assert.match(f.delivered[0].text, /&lt;realme&gt;&amp;/);
  assert.match(f.delivered[0].text, /🔑 Вход: Telegram/);
  assert.doesNotMatch(JSON.stringify(await f.storage.get('signals:auth_server')), /PRIVATE|google_forged/);
});

test('Telegram provider is named correctly in ordinary auth and prototype-safe labels', () => {
  assert.equal(providerLabel('telegram'), 'Telegram');
  assert.equal(providerLabel('__proto__'), 'Не определён');
  assert.match(buildIncidentMessage({ category: 'auth', operation: 'auth.provider', code: 'sdk_error',
    provider: 'telegram', ts: Date.now() }), /🔑 Вход: Telegram/);
});
