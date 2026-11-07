import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { fixture, identity, session, request } from './fixture-account.mjs';
import { accountRead } from './account_state.js';

test('referrals: GET /api/user/referral requires authentication', async () => {
  const { env } = fixture();
  const res = await worker.fetch(request('/api/user/referral', undefined, null), env);
  assert.equal(res.status, 401);
});

test('referrals: GET /api/user/referral returns user referral code and link', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_123', JSON.stringify(identity('google_123')));
  const token = await session(env, 'google_123');

  const res = await worker.fetch(request('/api/user/referral', undefined, token), env);
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.ok, true);
  assert.ok(data.code && data.code.length >= 6);
  assert.equal(data.link, 'https://pdd-drive.app/app/?ref=' + data.code);
  assert.equal(data.invitedCount, 0);
  assert.equal(data.rewardDays, 0);
  assert.equal(data.friendBonusDays, 1);
  assert.equal(data.inviterBonusDays, 2);

  // Calling again returns the exact same code
  const res2 = await worker.fetch(request('/api/user/referral', undefined, token), env);
  const data2 = await res2.json();
  assert.equal(data2.code, data.code);
});

test('referrals: POST /api/user/referral/claim rejects invalid input and self-referral', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_inviter', JSON.stringify(identity('google_inviter')));
  const token = await session(env, 'google_inviter');

  const refRes = await worker.fetch(request('/api/user/referral', undefined, token), env);
  const { code } = await refRes.json();

  // Self referral
  const selfRes = await worker.fetch(request('/api/user/referral/claim', { code }, token), env);
  assert.equal(selfRes.status, 400);
  const selfData = await selfRes.json();
  assert.equal(selfData.error, 'cannot_refer_self');

  // Invalid code
  const badRes = await worker.fetch(request('/api/user/referral/claim', { code: 'NONEXIST' }, token), env);
  assert.equal(badRes.status, 404);
  const badData = await badRes.json();
  assert.equal(badData.error, 'code_not_found');

  // Empty code
  const emptyRes = await worker.fetch(request('/api/user/referral/claim', { code: '' }, token), env);
  assert.equal(emptyRes.status, 400);
  const emptyData = await emptyRes.json();
  assert.equal(emptyData.error, 'invalid_code');
});

test('referrals: POST /api/user/referral/claim grants 1 day to friend and 2 days to inviter', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_inviter', JSON.stringify(identity('google_inviter')));
  await env.INSTALLS.put('user:google_friend', JSON.stringify(identity('google_friend')));

  const inviterToken = await session(env, 'google_inviter');
  const friendToken = await session(env, 'google_friend');

  const refRes = await worker.fetch(request('/api/user/referral', undefined, inviterToken), env);
  const { code } = await refRes.json();

  const now = Date.now();
  const claimRes = await worker.fetch(request('/api/user/referral/claim', { code }, friendToken), env);
  assert.equal(claimRes.status, 200);
  const claimData = await claimRes.json();
  assert.equal(claimData.ok, true);
  assert.equal(claimData.daysAdded, 1);
  assert.equal(claimData.isPremium, true);
  assert.equal(claimData.premiumSource, 'referral');

  const friendExpiry = Date.parse(claimData.premiumExpiresAt);
  // ~1 day (+- 5 seconds)
  assert.ok(Math.abs(friendExpiry - (now + 86400000)) < 5000);

  // Check inviter has +2 days
  const inviterRaw = await accountRead(env, 'google_inviter', 'user:google_inviter');
  const inviter = JSON.parse(inviterRaw);
  assert.equal(inviter.isPremium, true);
  assert.equal(inviter.premiumSource, 'referral');
  assert.equal(inviter.referralCount, 1);
  assert.equal(inviter.referralDaysEarned, 2);
  const inviterExpiry = Date.parse(inviter.premiumExpiresAt);
  // ~2 days (+- 5 seconds)
  assert.ok(Math.abs(inviterExpiry - (now + 2 * 86400000)) < 5000);

  // A lost response can be retried without moving either expiry.
  const secondClaim = await worker.fetch(request('/api/user/referral/claim', { code }, friendToken), env);
  assert.equal(secondClaim.status, 200);
  assert.equal((await secondClaim.json()).premiumExpiresAt, claimData.premiumExpiresAt);
  assert.equal(JSON.parse(await accountRead(env, 'google_inviter', 'user:google_inviter')).referralCount, 1);
});

test('referrals: multiple friends stack +2 days each on inviter', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_inviter', JSON.stringify(identity('google_inviter')));
  const inviterToken = await session(env, 'google_inviter');

  const refRes = await worker.fetch(request('/api/user/referral', undefined, inviterToken), env);
  const { code } = await refRes.json();

  const now = Date.now();
  // Friend 1 joins
  await env.INSTALLS.put('user:friend_1', JSON.stringify(identity('friend_1')));
  const f1Token = await session(env, 'friend_1');
  const c1 = await worker.fetch(request('/api/user/referral/claim', { code }, f1Token), env);
  assert.equal(c1.status, 200);

  // Friend 2 joins
  await env.INSTALLS.put('user:friend_2', JSON.stringify(identity('friend_2')));
  const f2Token = await session(env, 'friend_2');
  const c2 = await worker.fetch(request('/api/user/referral/claim', { code }, f2Token), env);
  assert.equal(c2.status, 200);

  // Inviter should have 2 friends and 4 days of premium
  const inviterRaw = await accountRead(env, 'google_inviter', 'user:google_inviter');
  const inviter = JSON.parse(inviterRaw);
  assert.equal(inviter.referralCount, 2);
  assert.equal(inviter.referralDaysEarned, 4);
  const inviterExpiry = Date.parse(inviter.premiumExpiresAt);
  // ~4 days (+- 5 seconds)
  assert.ok(Math.abs(inviterExpiry - (now + 4 * 86400000)) < 5000);
});

test('referrals: concurrent claims by multiple friends do not race or lose inviter days', async () => {
  const { env } = fixture();
  await env.INSTALLS.put('user:google_inviter', JSON.stringify(identity('google_inviter')));
  const inviterToken = await session(env, 'google_inviter');

  const refRes = await worker.fetch(request('/api/user/referral', undefined, inviterToken), env);
  const { code } = await refRes.json();

  const now = Date.now();
  await env.INSTALLS.put('user:concurrent_1', JSON.stringify({ ...identity('concurrent_1'), name: 'Friend <One>&Co' }));
  await env.INSTALLS.put('user:concurrent_2', JSON.stringify({ ...identity('concurrent_2'), name: 'Friend <Two>' }));
  const f1Token = await session(env, 'concurrent_1');
  const f2Token = await session(env, 'concurrent_2');

  const [res1, res2] = await Promise.all([
    worker.fetch(request('/api/user/referral/claim', { code }, f1Token), env),
    worker.fetch(request('/api/user/referral/claim', { code }, f2Token), env),
  ]);

  assert.equal(res1.status, 200);
  assert.equal(res2.status, 200);

  const inviterRaw = await accountRead(env, 'google_inviter', 'user:google_inviter');
  const inviter = JSON.parse(inviterRaw);
  assert.equal(inviter.referralCount, 2);
  assert.equal(inviter.referralDaysEarned, 4);
  const inviterExpiry = Date.parse(inviter.premiumExpiresAt);
  assert.ok(Math.abs(inviterExpiry - (now + 4 * 86400000)) < 5000);
});

async function setupPair() {
  const setup = fixture();
  const { env } = setup;
  for (const id of ['google_inviter', 'google_friend', 'google_other']) {
    await env.INSTALLS.put('user:' + id, JSON.stringify(identity(id)));
  }
  const inviterToken = await session(env, 'google_inviter');
  const friendToken = await session(env, 'google_friend');
  const otherToken = await session(env, 'google_other');
  const info = token => worker.fetch(request('/api/user/referral', undefined, token), env).then(res => res.json());
  const claim = (code, token = friendToken) =>
    worker.fetch(request('/api/user/referral/claim', { code }, token), env);
  const read = async id => JSON.parse(await accountRead(env, id, 'user:' + id));
  return { ...setup, inviterToken, friendToken, otherToken, info, claim, read };
}

test('referrals: only one code can win simultaneous claims by the same friend', async () => {
  const { inviterToken, otherToken, info, claim, read } = await setupPair();
  const [first, second] = await Promise.all([info(inviterToken), info(otherToken)]);
  const statuses = await Promise.all([claim(first.code), claim(second.code)]);
  assert.deepEqual(statuses.map(res => res.status).sort(), [200, 400]);
  const inviters = await Promise.all(['google_inviter', 'google_other'].map(read));
  assert.equal(inviters.reduce((sum, user) => sum + (user.referralDaysEarned || 0), 0), 2);
});

test('referrals: the alarm recovers after inviter credit commits but its response is lost', async () => {
  const { env, states, objects, restart, inviterToken, info, claim, read } = await setupPair();
  const { code } = await info(inviterToken);
  const original = env.ACCOUNTS;
  env.ACCOUNTS = { ...original, get(id) {
    const stub = original.get(id);
    return { async fetch(url, options) {
      const res = await stub.fetch(url, options);
      if (id === 'google_inviter' && String(url).endsWith('/_account/referral-reward')) {
        throw new Error('response lost after inviter commit');
      }
      return res;
    } };
  } };
  assert.equal((await claim(code)).status, 500);
  assert.equal((await read('google_inviter')).referralDaysEarned, 2);
  assert.equal((await read('google_friend')).referredBy, undefined);
  env.ACCOUNTS = original;
  const coordinator = 'referral-claim:google_friend';
  assert.ok(states.get(coordinator).alarm);
  restart(coordinator);
  // Reinstantiate via an unrelated private directory read, then deliver the alarm.
  await original.get(coordinator).fetch('https://account.internal/_directory/find', {
    method: 'POST', body: '{}',
  });
  await objects.get(coordinator).alarm();
  assert.equal((await read('google_friend')).referralCodeUsed, code);
  assert.equal((await read('google_inviter')).referralDaysEarned, 2);
  assert.equal((await claim(code)).status, 200);
  assert.equal(states.get(coordinator).alarm, null);
});

test('referrals: public input is bounded and guesses are rate limited', async () => {
  const { env, friendToken, claim } = await setupPair();
  assert.equal((await claim(['ABC'])).status, 400);
  assert.equal((await claim('ABC-DEF')).status, 400);
  assert.equal((await worker.fetch(request('/api/user/referral/claim', {
    code: 'VALID1', padding: 'x'.repeat(2000),
  }, friendToken), env)).status, 400);
  for (let i = 0; i < 8; i++) assert.equal((await claim('MISS' + i)).status, 404);
  const limited = await claim('MISS8');
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.headers.get('Retry-After')) > 0);
});

test('referrals: rejects a stale index and accepts a valid legacy code', async () => {
  const { env, inviterToken, info, claim, read } = await setupPair();
  await env.INSTALLS.put('ref_code:STALE1', 'google_inviter');
  assert.equal((await claim('STALE1')).status, 404);
  assert.equal((await read('google_inviter')).referralCount, undefined);
  await env.INSTALLS.put('user:google_other', JSON.stringify({
    ...identity('google_other'), referralCode: 'OLD123',
  }));
  await env.INSTALLS.put('ref_code:OLD123', 'google_other');
  assert.equal((await claim('  old123  ')).status, 200);
  assert.equal((await info(inviterToken)).invitedCount, 0);
});

test('referrals: a recreated account cannot collect a second friend bonus', async () => {
  const { env, inviterToken, friendToken, otherToken, info, claim, read } = await setupPair();
  const { code } = await info(inviterToken);
  const other = await info(otherToken);
  assert.equal((await claim(code)).status, 200);
  assert.equal((await worker.fetch(request('/api/user/delete', { userId: 'google_friend' }, friendToken), env)).status, 200);
  const generation = await accountRead(env, 'google_friend', 'auth_generation:google_friend');
  const { accountWrite } = await import('./account_state.js');
  const { signSession } = await import('./user_auth.js');
  const recreated = { ...identity('google_friend'), createdAt: new Date(Date.now() + 1000).toISOString() };
  await accountWrite(env, 'google_friend', 'user:google_friend', JSON.stringify(recreated));
  const token = await signSession(env, { user: recreated, generation, expiresAt: Date.now() + 3600000 });
  assert.equal((await claim(other.code, token)).status, 400);
  assert.equal((await info(token)).hasUsedReferral, true);
  assert.equal((await read('google_other')).referralCount, undefined);
});
