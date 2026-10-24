import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { TelegramQueue } from './telegram_queue.js';
import { MemoryStorage } from './fixture-account.mjs';
import { buildErrorCsv } from './telegram_export.js';

const START = Date.UTC(2026, 9, 24, 8, 29, 19);
const occurrences = (text, value) => text.split(value).length - 1;

function fixture(t) {
  let now = START;
  const storage = new MemoryStorage();
  const state = { storage };
  const env = { BOT_TOKEN: 'fixture-token', CHAT_ID: '-100123', TELEGRAM_TOPIC_ERRORS: '7' };
  let queue = new TelegramQueue(state, env);
  const calls = [], delivered = [];
  let respond = () => Response.json({ ok: true });
  t.mock.method(Date, 'now', () => now);
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.match(String(url), /^https:\/\/api\.telegram\.org\/botfixture-token\/sendMessage$/);
    const body = JSON.parse(options.body);
    calls.push(body);
    const response = await respond(body);
    if (response.ok) delivered.push(body);
    return response;
  });
  const incident = (overrides = {}) => ({
    id: crypto.randomUUID(), ts: now, origin: 'server', category: 'infrastructure',
    operation: 'api.user.sync', code: 'operation_failed', status: 500,
    userId: 'google_fixture_account', userName: 'Fixture User', userEmail: 'fixture@example.invalid',
    authProvider: 'google', platform: 'ios', appVersion: '2.2.4+63', device: 'iPhone18,2',
    country: 'LV', os: 'iOS 26.5', diagnosticId: crypto.randomUUID(),
    context: { stage: 'server', errorType: 'Error', frames: ['worker.js:1474:14'] },
    ...overrides,
  });
  const enqueue = async event => {
    // Match reportIncident's stable per-operation fingerprint; account identity
    // intentionally is not part of its existing cross-account cooldown.
    const context = event.context || {};
    const contextKey = [context.phase || '', context.stage || '', context.sdkCodeHash || '', context.frames?.[0] || ''];
    const fingerprint = createHash('sha256').update([
      event.origin, event.category, event.operation, event.code, event.provider,
      event.platform, event.appVersion, ...(contextKey.some(Boolean) ? contextKey : []),
    ].join('|')).digest('hex');
    const response = await queue.fetch(new Request('https://queue/incident', {
      method: 'POST', body: JSON.stringify({ incident: event, fingerprint }),
    }));
    assert.equal(response.status, 200);
    return response.json();
  };
  const fire = async () => {
    // The runtime clears a delivered alarm before invoking the handler.
    await storage.deleteAlarm();
    await queue.alarm();
  };
  const drain = async () => {
    for (let i = 0; i < 100; i++) {
      const deadline = await storage.getAlarm();
      if (deadline === null || deadline === undefined) return;
      now = Math.max(now, Number(deadline));
      await fire();
    }
    assert.fail('Telegram queue did not drain after 100 alarms');
  };
  return {
    storage, calls, delivered, incident, enqueue, fire, drain,
    get queue() { return queue; }, get now() { return now; },
    advance: ms => { now += ms; },
    restart: () => { queue = new TelegramQueue(state, env); },
    response: fn => { respond = fn; },
  };
}

test('one account outage sends the requested headings, one identity block and every diagnostic ID', async t => {
  const f = fixture(t);
  const profile = f.incident();
  const progress = f.incident({ operation: 'api.user.progress.sync',
    context: { stage: 'server', errorType: 'Error', frames: ['worker.js:3418:8'] } });
  const notifications = f.incident({ operation: 'api.notifications',
    context: { stage: 'server', errorType: 'Error', frames: ['notifications.js:82:9'] } });
  for (const event of [profile, progress, notifications]) {
    await f.enqueue(event);
    f.advance(400);
  }
  assert.equal(f.calls.length, 0, 'collection does not call Telegram from the request');
  await f.drain();
  assert.equal(f.delivered.length, 1);
  const text = f.delivered[0].text;
  assert.match(text, /^🟠 <b>Сбой сервера<\/b>\n🟡 <b>Не удалось обновить профиль<\/b>\n🟡 <b>Не удалось синхронизировать прогресс<\/b>/);
  assert.equal(occurrences(text, 'Fixture User'), 1);
  assert.equal(occurrences(text, 'fixture@example.invalid'), 1);
  assert.equal(occurrences(text, 'google_fixture_account'), 1);
  for (const event of [profile, progress, notifications]) {
    assert.ok(text.includes(event.operation), event.operation);
    assert.ok(text.includes(event.diagnosticId), event.diagnosticId);
  }
  assert.equal(f.delivered[0].message_thread_id, 7);
  assert.equal(f.delivered[0].parse_mode, 'HTML');
  assert.ok(text.length <= 4096);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 3, 'aggregation retains each original CSV event');
  assert.ok(records.every(record => record.sent));
  assert.equal(records.filter(record => record.notificationReason === 'coalesced').length, 2);
  const csv = buildErrorCsv(records);
  for (const event of [profile, progress, notifications]) assert.ok(csv.includes(event.diagnosticId));
  assert.doesNotMatch(csv, /нет \(повтор, свёрнуто\)/);
});

test('a singleton is delivered after the bounded three-second collection window', async t => {
  const f = fixture(t), event = f.incident();
  await f.enqueue(event);
  f.advance(2999);
  await f.fire();
  assert.equal(f.calls.length, 0);
  f.advance(1);
  await f.fire();
  assert.equal(f.delivered.length, 1);
  assert.ok(f.delivered[0].text.includes(event.diagnosticId));
  await f.drain();
  assert.equal(f.delivered.length, 1);
});

test('restart preserves the batch and later arrivals do not extend its first deadline', async t => {
  const f = fixture(t), first = f.incident();
  await f.enqueue(first);
  f.advance(2000);
  f.restart();
  const second = f.incident({ operation: 'api.user.progress.sync' });
  await f.enqueue(second);
  f.advance(999);
  await f.fire();
  assert.equal(f.calls.length, 0);
  f.restart();
  f.advance(1);
  await f.fire();
  assert.equal(f.delivered.length, 1);
  assert.ok(f.delivered[0].text.includes(first.diagnosticId));
  assert.ok(f.delivered[0].text.includes(second.diagnosticId));
  assert.equal((await f.queue.readErrorLog(0)).length, 2);
});

test('duplicate incident delivery stays idempotent and real repeats keep the existing hourly cooldown', async t => {
  const f = fixture(t), first = f.incident();
  await f.enqueue(first);
  assert.equal((await f.enqueue(first)).duplicate, true);
  const repeat = f.incident();
  assert.equal((await f.enqueue(repeat)).suppressed, true);
  await f.enqueue(f.incident({ operation: 'api.user.progress.sync' }));
  await f.drain();
  assert.equal(f.delivered.length, 1);
  assert.equal(occurrences(f.delivered[0].text, '<b>Не удалось обновить профиль</b>'), 1);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 3, 'one duplicate delivery adds no duplicate CSV row');
  assert.equal(records.find(record => record.id === repeat.id).notificationReason, 'grouped');
  assert.equal(records.find(record => record.id === repeat.id).sent, false);
  f.advance(3600001);
  await f.enqueue(f.incident());
  await f.drain();
  assert.equal(f.delivered.length, 2);
  assert.match(f.delivered[1].text, /Повторов с прошлого сообщения: 1/);
});

test('unrelated identities, causes and client contexts are delivered separately', async t => {
  const cases = [
    ['different account', { userId: 'apple_other_account' }],
    ['unknown account', { userId: null }],
    ['different code', { code: 'durable_overloaded' }],
    ['different HTTP status', { status: 503 }],
    ['different platform', { platform: 'android' }],
    ['different version', { appVersion: '2.2.5+66' }],
    ['different device', { device: 'Pixel' }],
    ['different country', { country: 'RU' }],
    ['different OS', { os: 'iOS 26.4' }],
    ['different provider', { authProvider: 'apple' }],
    ['different stage', { context: { stage: 'framework', errorType: 'Error' } }],
    ['different exception', { context: { stage: 'server', errorType: 'TypeError' } }],
    ['different retryability', { context: { stage: 'server', errorType: 'Error', retryable: true } }],
    ['different overload flag', { context: { stage: 'server', errorType: 'Error', overloaded: true } }],
    ['authentication', { category: 'auth', operation: 'auth.session' }],
    ['purchase', { category: 'purchase', operation: 'api.user.purchase' }],
    ['client event', { origin: 'client' }],
    ['non-server failure', { status: 400 }],
    ['unrelated route', { operation: 'cron.maintenance' }],
  ];
  for (const [label, overrides] of cases) await t.test(label, async child => {
    const f = fixture(child);
    const first = f.incident(), second = f.incident({ operation: 'api.user.progress.sync', ...overrides });
    await f.enqueue(first);
    await f.enqueue(second);
    await f.drain();
    assert.equal(f.delivered.length, 2);
    assert.equal(f.delivered.filter(body => body.text.includes(first.diagnosticId)).length, 1);
    assert.equal(f.delivered.filter(body => body.text.includes(second.diagnosticId)).length, 1);
    assert.ok(f.delivered.every(body => !(body.text.includes(first.diagnosticId) && body.text.includes(second.diagnosticId))));
    assert.equal((await f.queue.readErrorLog(0)).length, 2);
  });
});

test('new batches and ordinary messages cannot shorten a Telegram 429 hold, including after restart', async t => {
  const f = fixture(t);
  await f.enqueue(f.incident());
  await f.enqueue(f.incident({ operation: 'api.user.progress.sync' }));
  f.response(() => Response.json({ ok: false, parameters: { retry_after: 120 } }, { status: 429 }));
  f.advance(3000);
  await f.fire();
  assert.equal(f.calls.length, 1);
  assert.equal(f.delivered.length, 0);
  const retryAt = await f.storage.getAlarm();
  assert.ok(retryAt >= f.now + 120000);
  f.advance(100);
  await f.enqueue(f.incident({ operation: 'api.notifications' }));
  await f.queue.enqueue({ text: 'Fixture purchase notification' });
  f.restart();
  f.response(() => Response.json({ ok: true }));
  await f.fire();
  assert.equal(f.calls.length, 1, 'an early alarm must not bypass the persisted rate limit');
  assert.ok((await f.storage.getAlarm()) >= retryAt);
  f.advance(4000);
  await f.fire();
  assert.equal(f.calls.length, 1, 'new collection deadline must not bypass retry_after');
  await f.drain();
  assert.equal(f.delivered.length, 3);
  assert.equal(f.delivered.filter(body => body.text === 'Fixture purchase notification').length, 1);
  assert.equal(f.delivered.filter(body => body.text.includes('api.user.sync')).length, 1);
  assert.equal(f.delivered.filter(body => body.text.includes('api.notifications')).length, 1);
  assert.equal(new Set(f.delivered.map(body => body.text)).size, 3);
});

test('ordinary queue messages remain compatible and are never absorbed into an incident batch', async t => {
  const f = fixture(t);
  await f.queue.enqueue({ text: 'Fixture ordinary message', threadId: 11 });
  f.restart();
  const event = f.incident();
  await f.enqueue(event);
  await f.drain();
  assert.equal(f.delivered.length, 2);
  assert.equal(f.delivered[0].text, 'Fixture ordinary message');
  assert.equal(f.delivered[0].message_thread_id, 11);
  assert.ok(f.delivered[1].text.includes(event.diagnosticId));
  assert.doesNotMatch(f.delivered[1].text, /Fixture ordinary message/);
});

test('bounded batches split without dropping any diagnostic ID, including long escaped metadata', async t => {
  const f = fixture(t), events = [];
  for (let i = 0; i < 12; i++) {
    const event = f.incident({ userId: '<&'.repeat(100), userName: '<b>&</b>'.repeat(15),
      userEmail: '<&'.repeat(80), device: '<&'.repeat(50), operation: 'api.user.progress.sync',
      context: { stage: 'server', errorType: 'Error', supportStage: 'list', upstreamStatus: 503,
        frames: ['worker.js:' + (1000 + i) + ':10'] } });
    events.push(event);
    await f.enqueue(event);
  }
  await f.drain();
  assert.ok(f.delivered.length > 1, 'a full batch must split rather than lose later operations');
  for (const body of f.delivered) {
    assert.ok(body.text.length <= 4096);
    assert.doesNotMatch(body.text, /<(?!\/?(?:b|code)>)/);
    assert.equal(occurrences(body.text, '<b>'), occurrences(body.text, '</b>'));
    assert.equal(occurrences(body.text, '<code>'), occurrences(body.text, '</code>'));
  }
  for (const event of events) assert.equal(f.delivered.filter(body => body.text.includes(event.diagnosticId)).length, 1);
  assert.equal((await f.queue.readErrorLog(0)).length, events.length);
});

test('coalesced operations consume one burst-limit slot and later unrelated incidents remain limited', async t => {
  const f = fixture(t);
  for (let i = 0; i < 20; i++) await f.enqueue(f.incident({ code: 'fault_' + i }));
  const merged = f.incident({ code: 'fault_0', operation: 'api.user.progress.sync' });
  assert.equal((await f.enqueue(merged)).suppressed, false);
  const overflow = f.incident({ code: 'fault_21' });
  assert.equal((await f.enqueue(overflow)).suppressed, true);
  await f.drain();
  assert.equal(f.delivered.length, 20);
  assert.equal(f.delivered.filter(body => body.text.includes(merged.diagnosticId)).length, 1);
  const records = await f.queue.readErrorLog(0);
  assert.equal(records.length, 22);
  assert.equal(records.find(record => record.id === overflow.id).notificationReason, 'burst_limit');
});

test('delivery failure closes collection so later arrivals cannot mutate a potentially delivered message', async t => {
  const f = fixture(t), first = f.incident();
  await f.enqueue(first);
  f.response(() => { throw new Error('lost Telegram response'); });
  f.advance(3000);
  await f.fire();
  const second = f.incident({ operation: 'api.user.progress.sync' });
  await f.enqueue(second);
  f.restart();
  f.response(() => Response.json({ ok: true }));
  await f.drain();
  assert.equal(f.delivered.length, 2);
  assert.equal(f.calls[0].text, f.delivered[0].text);
  assert.ok(!f.delivered[0].text.includes(second.diagnosticId));
  assert.ok(f.delivered[1].text.includes(second.diagnosticId));
});

test('topic fallback retains the entire collected incident message', async t => {
  const f = fixture(t), first = f.incident(), second = f.incident({ operation: 'api.user.progress.sync' });
  await f.enqueue(first);
  await f.enqueue(second);
  f.response(() => Response.json({ ok: false, description: 'message thread not found' }, { status: 400 }));
  f.advance(3000);
  await f.fire();
  f.restart();
  f.response(() => Response.json({ ok: true }));
  await f.drain();
  assert.equal(f.delivered.length, 1);
  assert.equal(f.delivered[0].message_thread_id, undefined);
  for (const event of [first, second]) assert.ok(f.delivered[0].text.includes(event.diagnosticId));
});
