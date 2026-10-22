import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { tokenHash } from './user_auth.js';
import { TelegramQueue } from './telegram_queue.js';
import { reportIncident } from './diagnostics.js';
import { incidentGuide } from './incident_copy.js';
import { sanitizeDiagnosticContext, diagnosticNotificationPolicy, serverErrorContext } from './diagnostic_context.js';
import { buildErrorCsv } from './telegram_export.js';

class Storage {
  data = new Map(); alarm = null;
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async list({prefix = '', limit = Infinity} = {}) { return new Map([...this.data].filter(([key]) => key.startsWith(prefix)).sort().slice(0, limit)); }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  async transaction(fn) { return fn(this); }
}
function setup() {
  const env = { BOT_TOKEN: 'test', CHAT_ID: 'test', SHARED_SECRET: crypto.randomUUID(), INSTALLS: new Storage() };
  const storage = new Storage(), queue = new TelegramQueue({storage}, env);
  env.TELEGRAM = {idFromName: s => s, get: () => ({fetch: (url, options) => queue.fetch(new Request(url, options))})};
  return {env, storage};
}
const entries = (storage, prefix) => [...storage.data].filter(([key]) => key.startsWith(prefix)).map(([, value]) => value);
const id = () => crypto.randomUUID().replaceAll('-', '');

test('new client fields survive diagnostics, Telegram and CSV without raw messages or identifiers', async () => {
  const {env, storage} = setup(), installId = id();
  const context = { phase: 'paywall', stage: 'query', attempt: 3, requestedCount: 27, returnedCount: 0,
    missingCount: 27, missingIds: ['ru.pdd.pddapp.sub.week', 'user@example.com'],
    sdkSource: 'app_store', sdkCodeHash: '0123456789abcdef', message: 'TOP_SECRET',
    frames: ['package:pdd_app/data/services/iap_service.dart:320:7', 'https://private.test/token=TOP_SECRET'] };
  const response = await worker.fetch(new Request('https://test/api/diagnostics', {method: 'POST',
    headers: {'x-install-secret': env.SHARED_SECRET, 'content-type':'application/json'},
    body: JSON.stringify({installId, events: [{id: id(), ts: Date.now(), category: 'purchase', operation: 'iap.products', code:'channel-error', platform:'ios', appVersion:'2.2.4+65', os:'iOS 26.5', context}]}),
  }), env);
  assert.equal(response.status, 200);
  const [record] = entries(storage, 'log:');
  assert.match(record.installation, /^[a-f0-9]{16}$/);
  assert.equal(record.os, 'iOS 26.5');
  assert.equal(record.context.attempt, 3);
  assert.deepEqual(record.context.missingIds, ['ru.pdd.pddapp.sub.week']);
  assert.deepEqual(record.context.frames, [context.frames[0]]);
  const csv = buildErrorCsv([record]);
  assert.match(csv, /ID установки \(обезличенный\);ОС;Контекст загрузки/);
  assert.ok(csv.includes(record.installation));
  assert.ok(csv.includes('iOS 26.5;paywall;query;3;27;0;27'));
  assert.match(entries(storage, 'q:')[0].text, /экран оплаты/);
  assert.doesNotMatch(JSON.stringify([...storage.data]), /TOP_SECRET|user@example|private\.test/);
  assert.ok(!JSON.stringify([...storage.data]).includes(installId));
});

test('hourly prefetch grouping never suppresses a foreground or payment failure and retains every incident', async () => {
  const {env, storage} = setup(), realNow = Date.now;
  let now = realNow(); Date.now = () => now;
  const send = (operation, phase) => reportIncident(env, { id: id(), ts: now, origin:'client', category:'purchase', operation, code:'sdk_error', context:{phase,stage:'query'} });
  try {
    await send('iap.products', 'background');
    now += 11*60000;
    await send('iap.products', 'background');
    assert.equal(entries(storage, 'q:').length, 1);
    assert.equal(entries(storage, 'log:').length, 2);
    await send('iap.products', 'paywall');
    assert.equal(entries(storage, 'q:').length, 2);
    await send('premium.verify', 'background');
    now += 11*60000;
    await send('premium.verify', 'background');
    assert.equal(entries(storage, 'q:').length, 4);
    assert.equal(incidentGuide({category:'purchase',operation:'premium.verify',code:'sdk_error',context:{phase:'background'}}).level, 'critical');
    now += 40*60000;
    await send('iap.products', 'background');
    assert.equal(entries(storage, 'q:').length, 5);
    assert.equal(entries(storage, 'log:').length, 6);
    assert.match(entries(storage, 'q:').at(-1).text, /Повторов с прошлого сообщения: 1/);
  } finally { Date.now = realNow; }
});

test('old clients get grouping without inferred foreground or missing diagnostic values', async () => {
  const {env, storage} = setup();
  await reportIncident(env, {id:id(), origin:'client', operation:'iap.products', category:'purchase', code:'sdk_error'});
  const record = entries(storage, 'log:')[0];
  const legacyFingerprint = await tokenHash([record.origin, record.category, record.operation, record.code, record.provider, record.platform, record.appVersion].join('|'));
  assert.ok((await storage.get('errors:state')).groups[legacyFingerprint], 'old notification groups retain the same storage key');
  assert.deepEqual(record.context, {});
  assert.equal(record.os, '');
  assert.equal(record.installation, '');
  assert.equal(diagnosticNotificationPolicy(record).windowMs, 3600000);
  assert.equal(diagnosticNotificationPolicy({...record,context:{phase:'paywall'}}).windowMs, 600000);
});

test('recovered sign-in stays in CSV as informational, not as a false duplicate or Telegram alarm', async () => {
  const {env, storage} = setup();
  await reportIncident(env, {id:id(), origin:'client', operation:'auth.recovered', category:'auth', code:'fallback_ok:2x'});
  assert.equal(entries(storage, 'q:').length, 0);
  const [record] = entries(storage, 'log:');
  assert.equal(record.notificationReason, 'info_only');
  assert.match(buildErrorCsv([record]), /нет \(для сведения\)/);
  assert.equal(incidentGuide({operation:'startup.premium',code:'timeout',category:'app'}).level, 'low');
  assert.equal(incidentGuide({operation:'iap.products',code:'sdk_error',category:'purchase',context:{phase:'background'}}).level, 'low');
  assert.equal(incidentGuide({operation:'iap.products',code:'sdk_error',category:'purchase',context:{phase:'purchase'}}).level, 'high');
  assert.equal(incidentGuide({operation:'flutter.framework',code:'exception_StateError',category:'app'}).level, 'high');
});

test('server error context contains type and module location without private URLs, paths or exception text', () => {
  const error = new TypeError('TOP_SECRET user@example.com');
  error.stack = 'TypeError: TOP_SECRET\n at query (/Users/private/project/worker.js:123:8)\n at token (https://private.test/path?TOP_SECRET)';
  assert.deepEqual(serverErrorContext(error), {stage:'server',errorType:'TypeError',frames:['worker.js:123:8']});
  error.retryable = true; error.overloaded = false;
  assert.deepEqual(serverErrorContext(error), {stage:'server',errorType:'TypeError',frames:['worker.js:123:8'],retryable:true,overloaded:false});
  const context = sanitizeDiagnosticContext({phase:'TOP_SECRET',stage:'bad',errorType:'TOP_SECRET',attempt:-1,returnedCount:1e20,frames:['https://a.test/private'],missingIds:['TOP_SECRET']});
  assert.deepEqual(context, {frames:[], missingIds:[]});
  assert.doesNotMatch(JSON.stringify(context), /TOP_SECRET|private/);
  assert.deepEqual(sanitizeDiagnosticContext({ retryable: 'TOP_SECRET', overloaded: {} }), {});
});

test('support context accepts only fixed stages and integer error statuses, excluding private properties', () => {
  for (const supportStage of ['list', 'seed']) for (const upstreamStatus of [400, 503, 599]) {
    const context = sanitizeDiagnosticContext({ supportStage, upstreamStatus, message: 'TOP_SECRET',
      url: 'https://private.test/?token=TOP_SECRET', body: 'TOP_SECRET', userId: 'private-user', request: {} });
    assert.deepEqual(context, { supportStage, upstreamStatus });
    const error = Object.assign(new Error('TOP_SECRET'), { supportStage, upstreamStatus,
      body: 'TOP_SECRET', url: 'https://private.test', userId: 'private-user', retryable: false });
    error.stack = 'Error: TOP_SECRET\n at read (https://private.test/?token=TOP_SECRET)';
    assert.deepEqual(serverErrorContext(error), { stage: 'server', errorType: 'Error',
      supportStage, retryable: false, upstreamStatus, frames: [] });
    assert.doesNotMatch(JSON.stringify(context), /TOP_SECRET|private/);
  }
  for (const supportStage of ['append', 'list?token=TOP_SECRET', 1, {}, null]) {
    assert.deepEqual(sanitizeDiagnosticContext({ supportStage }), {});
  }
  for (const upstreamStatus of [0, 200, 399, 600, 1000, 503.1, '503', NaN, Infinity, null]) {
    assert.deepEqual(sanitizeDiagnosticContext({ upstreamStatus }), {});
  }
});
