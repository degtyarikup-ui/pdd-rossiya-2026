import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { AccountState, accountRead, paymentOwner } from './account_state.js';
import { PurchaseClaims } from './purchase_claims.js';
import { TrafficState } from './traffic_state.js';
import { createClosedInventory, createClosedTarget, restoreClosedBundle, readClosedObject } from '../../tools/domain_migration/closed_restore.mjs';
import { syntheticBackup, guardedApplicationFixture, identities, SYNTHETIC_USER, DELETED_USER, denyNetwork } from './closed-backup-fixtures.mjs';

async function restoredFixture() {
  const source = await syntheticBackup(), target = createClosedTarget();
  const inventory = await createClosedInventory(source.snapshots, { key: source.backupKey, kvEntries: source.kvEntries });
  await restoreClosedBundle({ inventory, snapshots: source.snapshots, kvEntries: source.kvEntries }, target, { key: source.backupKey });
  return { source, target, ...guardedApplicationFixture(target, source) };
}

test('restored actual AccountState handlers preserve all premium sources and large AB/CD progress against stale KV', async () => denyNetwork(async counts => {
  const { source, target, env, states, request } = await restoredFixture();
  assert.ok([...states.get('active').data.keys()].filter(k => k.startsWith('chunk:')).length > 2);
  await env.INSTALLS.put('user:' + SYNTHETIC_USER, JSON.stringify({ ...source.user, isPremium: false, entitlements: {} }));
  await env.INSTALLS.put('user_progress:' + SYNTHETIC_USER, '{}');
  assert.equal(AccountState.prototype.isPrototypeOf(new AccountState({ storage: states.get('active') }, env)), true);
  const response = await worker.fetch(request('/api/user/status', undefined, source.tokens.active), env);
  assert.equal(response.status, 200);
  const status = await response.json();
  assert.equal(status.isPremium, true);
  assert.equal(status.premiumExpiresAt, source.user.premiumExpiresAt);
  assert.equal(status.premiumSource, source.user.premiumSource);
  assert.deepEqual(JSON.parse(await accountRead(env, SYNTHETIC_USER, 'user:' + SYNTHETIC_USER)), source.user);
  const progress = await worker.fetch(request('/api/user/progress?userId=' + SYNTHETIC_USER, undefined, source.tokens.active), env);
  assert.equal(progress.status, 200);
  assert.deepEqual((await progress.json()).progress, source.progress);
  // Original restored evidence is independent from application rehearsal writes.
  assert.deepEqual(readClosedObject(target, identities.active).entries, source.objects.get('active').data);
  assert.equal(await states.get('active').getAlarm(), null);
  assert.deepEqual(counts, { blocked: 0, providerMocks: 0, outgoing: 0 });
}));

test('restored generations, revoked sessions and deleted-account tombstone cannot resurrect old access', async () => denyNetwork(async counts => {
  const { source, env, request } = await restoredFixture();
  await env.INSTALLS.put('user:' + DELETED_USER, JSON.stringify({ id: DELETED_USER, isPremium: true }));
  await env.INSTALLS.put('auth_generation:' + SYNTHETIC_USER, 'generation-1');
  for (const token of [source.tokens.oldGeneration, source.tokens.revoked, source.tokens.deleted, source.tokens.legacy]) {
    assert.equal((await worker.fetch(request('/api/user/status', undefined, token), env)).status, 401);
  }
  assert.equal(await accountRead(env, DELETED_USER, 'user:' + DELETED_USER), null);
  assert.equal(await env.INSTALLS.get('closed-expired-session'), null);
  assert.equal(await accountRead(env, DELETED_USER, 'user_progress:' + DELETED_USER), null);
  assert.deepEqual(JSON.parse(await accountRead(env, DELETED_USER, 'account_deleted:' + DELETED_USER)), { at: Date.parse('2026-10-18T00:00:00.000Z') });
  assert.deepEqual(counts, { blocked: 0, providerMocks: 0, outgoing: 0 });
}));

test('application rehearsal rejects a wrong epoch and pins the restored epoch against stale KV reimport', async () => denyNetwork(async counts => {
  const { source, target, env, request } = await restoredFixture();
  assert.throws(() => guardedApplicationFixture(target, { ...source, epoch: 'wrong-epoch' }), /epoch/);
  assert.throws(() => { env.ACCOUNT_STATE_EPOCH = 'wrong-epoch'; }, TypeError);
  assert.equal(env.ACCOUNT_STATE_EPOCH, source.epoch);
  const status = await worker.fetch(request('/api/user/status', undefined, source.tokens.active), env);
  assert.equal(status.status, 200);
  assert.equal((await status.json()).isPremium, true);
  assert.deepEqual(counts, { blocked: 0, providerMocks: 0, outgoing: 0 });
}));

test('restored duplicate actual payment callback retains exact ledger/expiry and unknown/refund states; provider is local mock only', async () => {
  const { source, env, states, request } = await restoredFixture();
  const order = source.orders.confirmed;
  await denyNetwork(async counts => {
    const callback = () => worker.fetch(request('/api/pay/platega/callback', { id: order.txId, payload: order.orderId }, null,
      { 'x-secret': env.PLATEGA_SECRET, 'x-merchantid': env.PLATEGA_MERCHANT_ID }), env);
    const before = JSON.parse(await accountRead(env, SYNTHETIC_USER, 'user:' + SYNTHETIC_USER));
    for (let i = 0; i < 3; i++) assert.equal((await callback()).status, 200);
    const after = JSON.parse(await accountRead(env, SYNTHETIC_USER, 'user:' + SYNTHETIC_USER));
    assert.deepEqual(after.entitlements, before.entitlements);
    assert.deepEqual(after.webPayments, before.webPayments);
    assert.equal(after.premiumExpiresAt, before.premiumExpiresAt);
    assert.deepEqual(JSON.parse(await accountRead(env, SYNTHETIC_USER, 'payment_ledger:' + order.orderId)), source.ledger);
    for (const status of ['pending', 'creation_unknown', 'requires_refund']) {
      const other = source.orders[status];
      assert.deepEqual(JSON.parse(await accountRead(env, other.userId, 'pay_order:' + other.orderId)), other);
      assert.equal(await paymentOwner(env, other.orderId, other.txId), other.userId);
    }
    const blockedCreate = await worker.fetch(request('/api/user/pay-intent',
      { email: source.user.email, tier: 'weekly', method: 'sbp' }, source.tokens.active), env);
    assert.equal(blockedCreate.status, 409);
    assert.equal((await blockedCreate.json()).code, 'payment_creation_unknown');
    assert.equal(counts.providerMocks, 3);
    assert.equal(counts.outgoing, 0);
    assert.equal(counts.blocked, 0);
    assert.ok(states.get('active').data.has('effect:closed-fixture-notification'));
  }, new Map([[order.txId, { status: 'CONFIRMED', payload: order.orderId, paymentDetails: { amount: 99, currency: 'RUB' } }]]));
});

test('restored PurchaseClaims ownership and TrafficState private ranking/outbox survive without replay', async () => denyNetwork(async counts => {
  const { source, states, env } = await restoredFixture();
  const claims = new PurchaseClaims({ storage: states.get('claim') });
  assert.equal((await (await claims.fetch(new Request('https://closed.invalid/claim'))).json()).userId, SYNTHETIC_USER);
  const claim = id => claims.fetch(new Request('https://closed.invalid/claim', { method: 'POST', body: JSON.stringify({ userId: id }) }));
  assert.equal((await claim('google_other')).status, 403);
  assert.equal((await claim(SYNTHETIC_USER)).status, 204);
  const traffic = new TrafficState({ storage: states.get('traffic') }, env);
  const board = await traffic.fetch(new Request('https://closed.invalid/traffic', { method: 'POST',
    body: JSON.stringify({ key: 'game_lb:2026-W43', action: 'read' }) }));
  assert.equal(board.status, 200);
  assert.equal((await board.json())[SYNTHETIC_USER].score, 937);
  assert.deepEqual(await states.get('traffic').get('ranking:' + SYNTHETIC_USER),
    await source.objects.get('traffic').get('ranking:' + SYNTHETIC_USER));
  assert.deepEqual(await states.get('traffic').get('out:closed-event'), await source.objects.get('traffic').get('out:closed-event'));
  assert.equal(await states.get('traffic').getAlarm(), null);
  assert.deepEqual(counts, { blocked: 0, providerMocks: 0, outgoing: 0 });
}));

test('late confirmed payment after restored deletion is quarantined for refund without recreating account or premium', async () => {
  const { source, env, request } = await restoredFixture(), order = source.orders.lateDeleted;
  await denyNetwork(async counts => {
    for (let i = 0; i < 2; i++) {
      const result = await worker.fetch(request('/api/pay/platega/callback', { id: order.txId, payload: order.orderId }, null,
        { 'x-secret': env.PLATEGA_SECRET, 'x-merchantid': env.PLATEGA_MERCHANT_ID }), env);
      assert.equal(result.status, 200);
    }
    assert.equal(await accountRead(env, DELETED_USER, 'user:' + DELETED_USER), null);
    assert.equal(await accountRead(env, DELETED_USER, 'payment_ledger:' + order.orderId), null);
    const retained = JSON.parse(await accountRead(env, DELETED_USER, 'pay_order:' + order.orderId));
    assert.equal(retained.status, 'requires_refund');
    assert.equal(retained.supportReason, 'account_deleted');
    assert.deepEqual(counts, { blocked: 0, providerMocks: 2, outgoing: 0 });
  }, new Map([[order.txId, { status: 'CONFIRMED', payload: order.orderId, paymentDetails: { amount: 99, currency: 'RUB' } }]]));
});
