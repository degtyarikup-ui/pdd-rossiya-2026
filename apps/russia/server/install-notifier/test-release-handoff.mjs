import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { accountRead } from './account_state.js';
import { claimPurchase, legacyAppleClaimsOpen } from './store_verification.js';
import { fixture, identity, session, request } from './fixture-account.mjs';

test('epoch bump after a KV-only rollback re-imports newer KV profile instead of overwriting it', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify({ ...identity(), isPremium: false }));
  const token = await session(env);
  assert.equal((await worker.fetch(request('/api/user/status', undefined, token), env)).status, 200);
  // Rollback window: the old Worker writes Premium straight into KV.
  const paid = { ...identity(), isPremium: true, premiumSource: 'web', premiumExpiresAt: new Date(Date.now() + 7 * 86400000).toISOString(),
    entitlements: { web: { expiresAt: new Date(Date.now() + 7 * 86400000).toISOString() } } };
  await env.INSTALLS.put('user:google_123', JSON.stringify(paid));
  assert.equal(JSON.parse(await accountRead(env, 'google_123', 'user:google_123')).isPremium, false);
  env.ACCOUNT_STATE_EPOCH = '2';
  assert.equal(JSON.parse(await accountRead(env, 'google_123', 'user:google_123')).isPremium, true);
  const status = await (await worker.fetch(request('/api/user/status', undefined, token), env)).json();
  assert.equal(status.isPremium, true);
  assert.equal(JSON.parse(await env.INSTALLS.get('user:google_123')).isPremium, true);
});

function claims(owner) {
  const stub = { owner, async fetch(url, options) {
    if (!options || options.method !== 'POST') return Response.json({ userId: stub.owner });
    const { userId } = JSON.parse(options.body);
    if (stub.owner && stub.owner !== userId) return new Response(null, { status: 403 });
    stub.owner = userId; return Response.json({ ok: true });
  } };
  return { stub, ns: { idFromName: id => id, get: () => stub } };
}
const legacyApple = { key: 'appstore:1', accountToken: null, reference: { store: 'appstore' } };

test('old iOS builds without appAccountToken keep first-claimant binding only during the transition', async () => {
  const open = claims(null);
  await claimPurchase({ PURCHASE_CLAIMS: open.ns, APPLE_LEGACY_CLAIMS_UNTIL: new Date(Date.now() + 86400000).toISOString() }, 'apple_a', legacyApple);
  assert.equal(open.stub.owner, 'apple_a');
  await assert.rejects(claimPurchase({ PURCHASE_CLAIMS: open.ns, APPLE_LEGACY_CLAIMS_UNTIL: new Date(Date.now() + 86400000).toISOString() }, 'apple_b', legacyApple), /another account/);
  const closed = claims(null);
  await assert.rejects(claimPurchase({ PURCHASE_CLAIMS: closed.ns, APPLE_LEGACY_CLAIMS_UNTIL: '2020-01-01T00:00:00Z' }, 'apple_a', legacyApple), /legacy purchase owner required/);
  await assert.rejects(claimPurchase({ PURCHASE_CLAIMS: closed.ns }, 'apple_a', legacyApple), /legacy purchase owner required/);
  assert.equal(closed.stub.owner, null);
  assert.equal(legacyAppleClaimsOpen({ APPLE_LEGACY_CLAIMS_UNTIL: 'garbage' }), false);
});
