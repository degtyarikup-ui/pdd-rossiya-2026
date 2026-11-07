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

  // Double claim by friend fails
  const secondClaim = await worker.fetch(request('/api/user/referral/claim', { code }, friendToken), env);
  assert.equal(secondClaim.status, 400);
  const secondData = await secondClaim.json();
  assert.equal(secondData.error, 'already_claimed');
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
