import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { accountRead, accountRpc } from './account_state.js';
import { fixture, identity, request, seedOrder, session } from './fixture-account.mjs';

const id = 'google_123';
const profileKey = 'user:' + id;
const progressKey = 'user_progress:' + id;
const exhausted = () => new Error('SQLite allocation failed: SQLITE_NOMEM');
const progress = (question, at) => ({ questionProgressAb: { [question]: { correct: true, answeredAt: at } } });
const primary = (states, key) => JSON.parse(states.get(id).data.get('doc:' + key).value);
const pending = (states, prefix) => [...states.get(id).data.keys()].filter(key => key.startsWith(prefix));
const write = (env, key, value) => accountRpc(env, id, '/_account/write', { key, value: JSON.stringify(value) });

async function seeded() {
  const fixtureData = fixture();
  const { env } = fixtureData;
  await env.INSTALLS.put(profileKey, JSON.stringify({
    ...identity(), isPremium: true, premiumSource: 'admin_grant', premiumExpiresAt: '2030-01-01T00:00:00.000Z',
    entitlements: { admin_grant: { expiresAt: '2030-01-01T00:00:00.000Z' } },
  }));
  const token = await session(env);
  assert.equal((await worker.fetch(request('/api/user/progress/sync', { userId: id, progress: progress('q1', 1000) }, token), env)).status, 200);
  await fixtureData.objects.get(id).alarm();
  return { ...fixtureData, token };
}

// Cloudflare removes the currently firing alarm before invoking the handler.
// Clearing it here prevents an old timestamp from hiding missing rescheduling.
async function fireAlarm(fixtureData) {
  await fixtureData.states.get(id).deleteAlarm();
  return fixtureData.objects.get(id).alarm();
}

test('cached account reads do not start a write transaction or inspect background queues', async () => {
  const { env, states, objects, token } = await seeded();
  const storage = states.get(id);
  const originalTransaction = storage.transaction.bind(storage), originalList = storage.list.bind(storage);
  let transactions = 0, backgroundLists = 0, flushes = 0;
  storage.transaction = async fn => { transactions++; return originalTransaction(fn); };
  storage.list = async options => {
    if (['projection:', 'index:', 'effect:'].includes(options?.prefix)) { backgroundLists++; throw exhausted(); }
    return originalList(options);
  };
  objects.get(id).flush = async () => { flushes++; throw exhausted(); };

  const responses = await Promise.all([
    worker.fetch(request('/api/user/progress?userId=' + id, undefined, token), env),
    accountRpc(env, id, '/_account/read', { key: profileKey }),
    accountRpc(env, id, '/_account/read-many', { keys: [profileKey, progressKey] }),
  ]);
  assert.deepEqual(responses.map(response => response.status), [200, 200, 200]);
  assert.equal(transactions, 0, 'already imported reads must not perform an empty commit');
  assert.equal(backgroundLists, 0, 'serving progress must not depend on projection/outbox scans');
  assert.equal(flushes, 0, 'background repair must be a different event');
});

test('progress success is returned after primary commit without a failing projection scan; Premium and ledger survive restart', async () => {
  const data = await seeded();
  const { env, states, objects, restart, token } = data;
  const ledgerKey = 'payment_ledger:fixture-credited';
  const ledger = { orderId: 'fixture-credited', userId: id, status: 'confirmed', days: 7 };
  assert.equal((await write(env, ledgerKey, ledger)).status, 200);
  await fireAlarm(data);
  const oldProjection = await env.INSTALLS.get(progressKey);
  const paidBefore = primary(states, profileKey);
  const storage = states.get(id), originalList = storage.list.bind(storage);
  let badScans = 0, flushes = 0;
  storage.list = async options => {
    if (options?.prefix === 'projection:') { badScans++; throw exhausted(); }
    return originalList(options);
  };
  objects.get(id).flush = async () => { flushes++; throw exhausted(); };

  const response = await worker.fetch(request('/api/user/progress/sync', { userId: id, progress: progress('q2', 2000) }, token), env);
  assert.equal(response.status, 200);
  assert.equal(badScans, 0);
  assert.equal(flushes, 0);
  assert.deepEqual(primary(states, profileKey), paidBefore);
  assert.deepEqual(primary(states, ledgerKey), ledger);
  assert.ok(primary(states, progressKey).questionProgressAb.q1);
  assert.ok(primary(states, progressKey).questionProgressAb.q2);
  assert.equal(await env.INSTALLS.get(progressKey), oldProjection, 'the primary and eventual projection are distinct');
  assert.ok(pending(states, 'projection:').includes('projection:' + progressKey));
  assert.ok(await storage.getAlarm(), 'recovery is durable before success reaches the client');

  restart(id);
  const recovered = await worker.fetch(request('/api/user/progress?userId=' + id, undefined, token), env);
  assert.equal(recovered.status, 200);
  assert.ok((await recovered.json()).progress.questionProgressAb.q2);
  assert.deepEqual(JSON.parse(await accountRead(env, id, profileKey)), paidBefore);
  assert.deepEqual(JSON.parse(await accountRead(env, id, ledgerKey)), ledger);
  storage.list = originalList;
  await fireAlarm(data);
  assert.ok(JSON.parse(await env.INSTALLS.get(progressKey)).questionProgressAb.q2);
  assert.equal(pending(states, 'projection:').length, 0);
});

test('a recovery-alarm failure or primary transaction failure never acknowledges an uncommitted progress write', async () => {
  for (const fault of ['alarm', 'transaction']) {
    const data = await seeded();
    const { env, states, token } = data;
    const storage = states.get(id);
    const before = structuredClone(storage.data.get('doc:' + progressKey));
    const paidBefore = structuredClone(storage.data.get('doc:' + profileKey));
    await storage.deleteAlarm();
    if (fault === 'alarm') storage.setAlarm = async () => { throw exhausted(); };
    else storage.failCommit = true;

    const response = await worker.fetch(request('/api/user/progress/sync', { userId: id, progress: progress('q2', 2000) }, token), env);
    assert.ok(response.status >= 500, fault);
    assert.deepEqual(storage.data.get('doc:' + progressKey), before, fault + ': primary progress is unchanged');
    assert.deepEqual(storage.data.get('doc:' + profileKey), paidBefore, fault + ': Premium is unchanged');
    assert.equal(pending(states, 'projection:').length, 0, fault + ': failed commit does not publish projection work');
  }
});

test('background storage failures exceeding the platform alarm retry cap remain scheduled and recover credited Premium exactly once', async () => {
  const data = await seeded();
  const { env, states, objects, restart } = data;
  env.BOT_TOKEN = 'fixture-bot'; env.CHAT_ID = 'fixture-chat';
  let queueAvailable = false;
  const notifications = [];
  env.TELEGRAM = { idFromName: value => value, get: () => ({ fetch: async (_url, options) => {
    notifications.push(JSON.parse(options.body));
    return Response.json({ ok: queueAvailable }, { status: queueAvailable ? 200 : 503 });
  } }) };
  env.STATS = { idFromName: value => value, get: () => ({ fetch: async () => Response.json({ ok: true }) }) };
  const order = await seedOrder(env);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ status: 'CONFIRMED', paymentDetails: { amount: 99, currency: 'RUB' } });
  try {
    const callback = () => worker.fetch(request('/api/pay/platega/callback', { id: order.txId, payload: order.orderId }, null,
      { 'x-secret': env.PLATEGA_SECRET, 'x-merchantid': env.PLATEGA_MERCHANT_ID }), env);
    assert.equal((await callback()).status, 200);
    const paid = primary(states, profileKey);
    assert.ok(paid.webPayments[order.orderId]);
    assert.ok(primary(states, 'payment_ledger:' + order.orderId));
    assert.ok(pending(states, 'effect:').length > 0);
    assert.equal(notifications.length, 0, 'Telegram must not run in the user request');

    const storage = states.get(id), originalList = storage.list.bind(storage);
    storage.list = async options => { if (options?.prefix === 'doc:') throw exhausted(); return originalList(options); };
    for (let attempt = 0; attempt < 8; attempt++) {
      await fireAlarm(data).catch(() => {});
      assert.ok(await storage.getAlarm(), 'failed maintenance must schedule a fresh alarm, attempt ' + attempt);
      assert.ok(pending(states, 'effect:').length > 0);
      assert.deepEqual(primary(states, profileKey), paid);
    }
    storage.list = originalList;
    await fireAlarm(data);
    assert.equal(notifications.length, 1, 'the queue outage is exercised by a real background delivery');
    assert.ok(pending(states, 'effect:').length > 0, 'a failed downstream delivery stays durable');
    assert.ok(await storage.getAlarm(), 'downstream outage schedules another event');
    restart(id);
    assert.deepEqual(JSON.parse(await accountRead(env, id, profileKey)), paid);
    queueAvailable = true;
    await fireAlarm(data);
    assert.equal(pending(states, 'effect:').length, 0);
    assert.equal(pending(states, 'projection:').length, 0);
    assert.deepEqual(JSON.parse(await env.INSTALLS.get(profileKey)), paid);
    assert.ok(await env.INSTALLS.get('payment_ledger:' + order.orderId));
    assert.ok(JSON.parse(await env.INSTALLS.get(progressKey)).questionProgressAb.q1);
    assert.equal((await callback()).status, 200);
    assert.deepEqual(primary(states, profileKey), paid, 'duplicate verified callback must not extend entitlement twice');
    assert.equal(notifications.length, 2);
    assert.ok(notifications.every(item => item.dedupKey === 'pay_paid:' + order.orderId));
  } finally { globalThis.fetch = originalFetch; }
});

test('Platega creation is blocked until the durable payment directory accepts the reservation', async () => {
  const { env, states, token } = await seeded();
  const get = env.ACCOUNTS.get.bind(env.ACCOUNTS);
  env.ACCOUNTS.get = name => name === 'payment-directory' ? { fetch: async () => Response.json({ error: 'fixture directory unavailable' }, { status: 503 }) } : get(name);
  const originalFetch = globalThis.fetch;
  let creates = 0;
  globalThis.fetch = async () => { creates++; return Response.json({ transactionId: 'fixture-tx', redirect: 'https://pay.example.invalid/fixture' }); };
  try {
    const response = await worker.fetch(request('/api/user/pay-intent', { email: 'receipt@example.invalid', tier: 'weekly', method: 'sbp' }, token), env);
    assert.equal(response.status, 503);
    assert.equal(creates, 0, 'no external create may occur with an unregistered owner');
    const reservations = [...states.get(id).data.entries()].filter(([key]) => key.startsWith('doc:pay_order:'));
    assert.equal(reservations.length, 1);
    const reserved = JSON.parse(reservations[0][1].value);
    assert.equal(reserved.status, 'creating');
    assert.equal(reserved.txId, null);
    assert.ok(pending(states, 'index:').length > 0);
    assert.ok(await states.get(id).getAlarm());
    assert.equal((await worker.fetch(request('/api/user/pay-intent', { email: 'receipt@example.invalid', tier: 'weekly', method: 'sbp' }, token), env)).status, 503);
    assert.equal(creates, 0, 'repeating the user request cannot bypass the uncertain reservation');
    assert.equal([...states.get(id).data.keys()].filter(key => key.startsWith('doc:pay_order:')).length, 1);
  } finally { globalThis.fetch = originalFetch; }
});

test('unavailable KV and Telegram do not block an imported account creating Platega payment after durable directory registration', async () => {
  const data = await seeded();
  const { env, states, token } = data;
  // A first legacy import still needs its KV source. This case intentionally
  // covers a migrated account whose reads already have authoritative records.
  await accountRead(env, id, 'pay_intent:' + id);
  const originalGet = env.INSTALLS.get.bind(env.INSTALLS);
  env.INSTALLS.get = async () => { throw new Error('fixture KV reads unavailable'); };
  env.INSTALLS.failPuts = true;
  env.BOT_TOKEN = 'fixture-bot'; env.CHAT_ID = 'fixture-chat';
  let telegramCalls = 0;
  env.TELEGRAM = { idFromName: value => value, get: () => ({ fetch: async () => {
    telegramCalls++; return Response.json({ ok: false }, { status: 503 });
  } }) };
  const originalFetch = globalThis.fetch;
  let creates = 0, orderId;
  globalThis.fetch = async (url, options) => {
    assert.ok(String(url).endsWith('/transaction/process'));
    creates++; orderId = JSON.parse(options.body).payload;
    const directory = states.get('payment-directory');
    assert.equal(directory.data.get('order:' + orderId).userId, id, 'payment ownership is durable before external side effect');
    return Response.json({ transactionId: 'fixture-tx', redirect: 'https://pay.example.invalid/fixture' });
  };
  try {
    const response = await worker.fetch(request('/api/user/pay-intent', { email: 'receipt@example.invalid', tier: 'weekly', method: 'sbp' }, token), env);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).order, orderId);
    assert.equal(creates, 1);
    assert.equal(telegramCalls, 0);
    assert.equal(primary(states, 'pay_order:' + orderId).status, 'pending');
    assert.equal(states.get(id).data.get('doc:pay_tx:fixture-tx').value, orderId);
    assert.ok(pending(states, 'projection:').length > 0);
    env.INSTALLS.get = originalGet;
    env.INSTALLS.failPuts = false;
    await fireAlarm(data);
    assert.equal(JSON.parse(await env.INSTALLS.get('pay_order:' + orderId)).status, 'pending');
  } finally { globalThis.fetch = originalFetch; env.INSTALLS.get = originalGet; }
});

test('an alarm draining an older projection cannot clear a concurrent newer progress write', async () => {
  const data = await seeded();
  const { env, states } = data;
  assert.equal((await write(env, progressKey, progress('q2', 2000))).status, 200);
  const originalPut = env.INSTALLS.put.bind(env.INSTALLS);
  let enter, release;
  const reached = new Promise(resolve => { enter = resolve; });
  const held = new Promise(resolve => { release = resolve; });
  let first = true;
  env.INSTALLS.put = async (key, value, options) => {
    if (key === progressKey && first) { first = false; enter(); await held; }
    return originalPut(key, value, options);
  };
  const draining = fireAlarm(data);
  await reached;
  let completed = false;
  const writing = write(env, progressKey, progress('q3', 3000)).then(response => { completed = true; return response; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(completed, false, 'alarm and account writes must share one serialization queue');
  release();
  await draining;
  assert.equal((await writing).status, 200);
  assert.ok(primary(states, progressKey).questionProgressAb.q3);
  assert.ok(pending(states, 'projection:').includes('projection:' + progressKey));
  await fireAlarm(data);
  assert.ok(JSON.parse(await env.INSTALLS.get(progressKey)).questionProgressAb.q3);
  assert.equal(pending(states, 'projection:').length, 0);
});

function trafficFixture(env) {
  const calls = [];
  env.TRAFFIC = { idFromName: value => value, get: () => ({ fetch: async (_url, options) => {
    calls.push(JSON.parse(options.body)); return Response.json({ ok: true });
  } }) };
  return calls;
}

test('an imported profile sync commits with KV reads and writes unavailable and repairs its email index later', async () => {
  const data = await seeded();
  const { env, states, token } = data;
  const traffic = trafficFixture(env);
  await accountRead(env, id, 'account_deleted:' + id);
  const userBefore = primary(states, profileKey), progressBefore = primary(states, progressKey);
  const emailKey = 'user_email:' + userBefore.email.toLowerCase().trim();
  const originalGet = env.INSTALLS.get.bind(env.INSTALLS), originalPut = env.INSTALLS.put.bind(env.INSTALLS);
  let kvCalls = 0;
  env.INSTALLS.get = async () => { kvCalls++; throw new Error('fixture KV reads unavailable'); };
  env.INSTALLS.put = async () => { kvCalls++; throw new Error('fixture KV writes unavailable'); };
  try {
    const response = await worker.fetch(request('/api/user/sync', { id, appVersion: 'fixture-next' }, token), env);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).isPremium, true);
    assert.equal(kvCalls, 0, 'authoritative profile sync must not wait for the secondary email index');
    assert.equal(traffic.length, 0, 'registration effects stay outside the request event');
    const saved = primary(states, profileKey);
    assert.equal(saved.premiumExpiresAt, userBefore.premiumExpiresAt);
    assert.deepEqual(saved.entitlements, userBefore.entitlements);
    assert.deepEqual(primary(states, progressKey), progressBefore);
    assert.deepEqual(states.get(id).data.get('projection:' + emailKey), {
      key: emailKey, value: id, projectionOnly: true, ownerId: id, epoch: '1',
    });
  } finally { env.INSTALLS.get = originalGet; env.INSTALLS.put = originalPut; }
  await fireAlarm(data);
  assert.equal(await env.INSTALLS.get(emailKey), id);
  assert.equal(pending(states, 'projection:').length, 0);
  assert.ok(traffic.some(call => call.key === 'counter:registered_users' && call.action === 'install'));
});

test('deletion before the first email projection drains coalesces pending registration into deletion without an orphan index', async () => {
  const data = await seeded();
  const { env, states, token } = data;
  trafficFixture(env);
  const emailKey = 'user_email:' + identity().email;
  assert.equal((await worker.fetch(request('/api/user/sync', { id }, token), env)).status, 200);
  assert.equal(states.get(id).data.get('projection:' + emailKey).value, id);
  assert.equal(await env.INSTALLS.get(emailKey), null);

  assert.equal((await worker.fetch(request('/api/user/delete', { userId: id }, token), env)).status, 200);
  const deletion = states.get(id).data.get('projection:' + emailKey);
  assert.equal(deletion.projectionOnly, true);
  assert.equal(deletion.value, null);
  assert.equal(deletion.ownerId, id);
  assert.equal(await accountRead(env, id, profileKey), null);
  assert.equal((await worker.fetch(request('/api/user/status', undefined, token), env)).status, 401);

  const originalPut = env.INSTALLS.put.bind(env.INSTALLS);
  let emailPuts = 0;
  env.INSTALLS.put = async (key, value, options) => { if (key === emailKey) emailPuts++; return originalPut(key, value, options); };
  await fireAlarm(data);
  assert.equal(emailPuts, 0, 'the superseded registration index must never be published');
  assert.equal(await env.INSTALLS.get(emailKey), null);
  assert.equal(pending(states, 'projection:').length, 0);
});

test('an email-index deletion removes its own mapping and preserves a mapping now owned by a different account', async () => {
  for (const owner of [id, 'yandex_foreign-account']) {
    const data = await seeded();
    const { env, states, token } = data;
    trafficFixture(env);
    const emailKey = 'user_email:' + identity().email;
    await env.INSTALLS.put(emailKey, owner);
    assert.equal((await worker.fetch(request('/api/user/delete', { userId: id }, token), env)).status, 200);
    assert.equal(await env.INSTALLS.get(emailKey), owner, 'email deletion is deferred until the background event');
    assert.equal(states.get(id).data.get('projection:' + emailKey).ownerId, id);
    await fireAlarm(data);
    assert.equal(await env.INSTALLS.get(emailKey), owner === id ? null : owner);
    assert.equal(pending(states, 'projection:').length, 0);
  }
});

test('a failed profile transaction cannot publish a detached email-index job or change Premium/progress', async () => {
  const data = await seeded();
  const { env, states, token } = data;
  trafficFixture(env);
  await accountRead(env, id, 'account_deleted:' + id);
  const emailKey = 'user_email:' + identity().email;
  const storage = states.get(id);
  const profileBefore = structuredClone(storage.data.get('doc:' + profileKey));
  const progressBefore = structuredClone(storage.data.get('doc:' + progressKey));
  storage.failCommit = true;
  const response = await worker.fetch(request('/api/user/sync', { id }, token), env);
  assert.ok(response.status >= 500);
  assert.deepEqual(storage.data.get('doc:' + profileKey), profileBefore);
  assert.deepEqual(storage.data.get('doc:' + progressKey), progressBefore);
  assert.equal(storage.data.has('projection:' + emailKey), false);
  assert.equal(pending(states, 'effect:').length, 0);
  assert.equal(await env.INSTALLS.get(emailKey), null);
  await fireAlarm(data);
  assert.equal(await env.INSTALLS.get(emailKey), null, 'a harmless recovery alarm cannot publish an aborted transaction');
});
