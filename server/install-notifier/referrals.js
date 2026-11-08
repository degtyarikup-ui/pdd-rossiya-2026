import { applyEntitlements, extendEntitlement } from './entitlements.js';
import { putUserRecord } from './user_store.js';
import { accountRpc } from './account_state.js';

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const FRIEND_DAYS = 2;
const INVITER_DAYS = 2;
const WINDOW_MS = 15 * 60_000;
const MAX_ATTEMPTS = 8;
const noStore = { 'Cache-Control': 'no-store' };
const reply = (body, status = 200, headers = {}) => Response.json(body, { status, headers: { ...noStore, ...headers } });
const fail = (error, status) => reply({ error }, status);

export function sanitizeCode(value) {
  if (typeof value !== 'string' || value.length > 64) return null;
  const code = value.trim();
  return /^[A-Za-z0-9]{3,32}$/.test(code) ? code.toUpperCase() : null;
}

function generateCode() {
  return Array.from(crypto.getRandomValues(new Uint8Array(10)), byte => ALPHABET[byte & 31]).join('');
}

export async function liveUser(env) {
  const id = env.__ACCOUNT_ID;
  const raw = await env.INSTALLS.get('user:' + id);
  const user = raw && JSON.parse(raw);
  if (user?.id !== id) return null;
  const deletion = JSON.parse(await env.INSTALLS.get('account_deleted:' + id) || 'null');
  return deletion && !(Date.parse(user.createdAt) > deletion.at) ? null : user;
}

export async function codeRpc(env, code, operation, owner) {
  const res = await accountRpc(env, 'referral-code:' + code, '/_referral/code', { code, operation, owner });
  if (!res?.ok) throw new Error('referral directory unavailable');
  return (await res.json()).owner;
}

// One strongly consistent slot per code. Existing KV codes are read only for
// compatibility; a reward also checks the code on its owner's current profile.
export async function referralDirectory(storage, env, { code, operation, owner }) {
  if (sanitizeCode(code) !== code) return fail('invalid_code', 400);
  let current = await storage.get('referral-owner');
  if (!current) {
    current = await env.INSTALLS.get('ref_code:' + code);
    if (operation === 'register' && (!current || current === owner)) {
      current = owner;
      await storage.put('referral-owner', owner);
    }
  }
  return reply({ owner: current || null });
}

export async function handleGetReferral(env, authenticatedUser, jsonResponse) {
  if (!authenticatedUser?.id) return jsonResponse({ error: 'unauthorized' }, 401, noStore);
  if (env.__ACCOUNT_ID !== authenticatedUser.id) return jsonResponse({ error: 'referral_unavailable' }, 503, noStore);
  const user = await liveUser(env);
  if (!user) return jsonResponse({ error: 'account_not_ready' }, 404, noStore);
  let code = user.referralCode;
  if (!sanitizeCode(code) || await codeRpc(env, code, 'register', user.id) !== user.id) {
    code = null;
    for (let attempt = 0; attempt < 5 && !code; attempt++) {
      const candidate = generateCode();
      if (await codeRpc(env, candidate, 'register', user.id) === user.id) code = candidate;
    }
    if (!code) return jsonResponse({ error: 'referral_unavailable' }, 503, noStore);
    user.referralCode = code;
    await putUserRecord(env, user);
  }
  return jsonResponse({
    ok: true,
    code,
    link: 'https://pdd-drive.app/app/?ref=' + code,
    invitedCount: user.referralCount || 0,
    rewardDays: user.referralDaysEarned || 0,
    hasUsedReferral: Boolean(user.referredBy || await env.INSTALLS.get('referral_used:' + user.id)),
    referralCodeUsed: user.referralCodeUsed || null,
    friendBonusDays: FRIEND_DAYS,
    inviterBonusDays: INVITER_DAYS,
  }, 200, noStore);
}

export async function readClaimCode(request) {
  const reader = request.body?.getReader();
  if (!reader) return null;
  let size = 0, json = '';
  const decoder = new TextDecoder();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1024) { void reader.cancel().catch(() => {}); return null; }
      json += decoder.decode(value, { stream: true });
    }
    return sanitizeCode(JSON.parse(json + decoder.decode())?.code);
  } catch { return null; }
  finally { reader.releaseLock(); }
}

export async function handleClaimReferral(request, env, authenticatedUser, jsonResponse) {
  if (!authenticatedUser?.id) return jsonResponse({ error: 'unauthorized' }, 401, noStore);
  if (!env.ACCOUNTS || env.__ACCOUNT_ID) return jsonResponse({ error: 'referral_unavailable' }, 503, noStore);
  const code = await readClaimCode(request);
  if (!code) return jsonResponse({ error: 'invalid_code' }, 400, noStore);
  const friendId = authenticatedUser.id;
  const res = await accountRpc(env, 'referral-claim:' + friendId, '/_referral/claim', { code, friendId });
  const retryAfter = res.headers.get('Retry-After');
  return jsonResponse(await res.json(), res.status, {
    ...noStore, ...(retryAfter ? { 'Retry-After': retryAfter } : {}),
  });
}

const premiumStatus = user => ({
  isPremium: Boolean(user.isPremium),
  premiumExpiresAt: user.premiumExpiresAt || null,
  premiumSource: user.premiumSource || null,
});
const success = (user, inviterDaysAdded = INVITER_DAYS) => reply({
  ok: true, kind: 'referral', daysAdded: FRIEND_DAYS, inviterDaysAdded, ...premiumStatus(user),
});

const normalizedEmail = email => typeof email === 'string' ? email.trim().toLowerCase() : '';

export async function referralAccountStep(path, request, env) {
  const job = await request.json();
  const user = await liveUser(env);
  if (path === '/_account/referral-check') {
    if (!user) return fail('account_not_ready', 404);
    if (user.referredBy || await env.INSTALLS.get('referral_used:' + user.id)) return fail('already_claimed', 400);
    const created = Date.parse(user.createdAt);
    if (!Number.isFinite(created) || created > Date.now() ||
        Date.now() - created > 7 * 86400000 ||
        await env.INSTALLS.get('account_deleted:' + user.id)) return fail('referral_ineligible', 400);
    if (user.referralCode === job.code) return fail('cannot_refer_self', 400);
    return reply({ createdAt: user.createdAt, email: normalizedEmail(user.email) });
  }
  if (path === '/_account/referral-inviter') {
    if (!user || user.referralCode !== job.code) return fail('code_not_found', 404);
    if (job.email && job.email === normalizedEmail(user.email)) return fail('cannot_refer_self', 400);
    if (!(Date.parse(user.createdAt) < Date.parse(job.createdAt))) return fail('referral_ineligible', 400);
    return reply({ inviterCreatedAt: user.createdAt });
  }
  if (path === '/_account/referral-reward') {
    const receipt = 'referral_receipt:' + env.__ACCOUNT_ID + ':' + job.id;
    if (await env.INSTALLS.get(receipt)) return reply({ ok: true });
    if (!user || user.referralCode !== job.code ||
        (job.inviterCreatedAt && user.createdAt !== job.inviterCreatedAt)) return fail('code_not_found', 404);
    // Before receipts existed, the inviter could already have been credited
    // even if the friend's profile write failed.
    if (Array.isArray(user.referrals) && user.referrals.some(entry => entry?.id === job.friendId)) {
      await env.INSTALLS.put(receipt, '1');
      return reply({ ok: true });
    }
    extendEntitlement(user, 'referral', INVITER_DAYS);
    user.referralCount = (user.referralCount || 0) + 1;
    user.referralDaysEarned = (user.referralDaysEarned || 0) + INVITER_DAYS;
    await putUserRecord(env, user);
    await env.INSTALLS.put(receipt, '1');
    return reply({ ok: true });
  }
  const usedKey = 'referral_used:' + env.__ACCOUNT_ID;
  const used = await env.INSTALLS.get(usedKey);
  if (!user || (user.createdAt || null) !== job.createdAt) {
    return fail(used === job.id ? 'referral_friend_deleted' : 'account_not_ready', 410);
  }
  if (user.referredBy) {
    if (user.referralCodeUsed !== job.code || user.referredBy !== job.inviterId) return fail('already_claimed', 400);
    return success(applyEntitlements(user));
  }
  if (used) return fail('already_claimed', 400);
  if (await env.INSTALLS.get('account_deleted:' + user.id)) return fail('account_not_ready', 410);
  extendEntitlement(user, 'referral', FRIEND_DAYS);
  user.referredBy = job.inviterId;
  user.referralCodeUsed = job.code;
  user.referralClaimedAt = new Date().toISOString();
  await putUserRecord(env, user);
  await env.INSTALLS.put(usedKey, job.id);
  return success(user);
}

// Jobs reserved by the previous release may already have paid the inviter.
async function completeLegacyClaim(storage, env, job) {
  const reward = await accountRpc(env, job.inviterId, '/_account/referral-reward', job);
  if (reward.status === 404 && (await reward.json()).error === 'code_not_found') {
    await storage.delete('referral-job');
    await storage.deleteAlarm();
    return fail('code_not_found', 404);
  }
  if (!reward.ok || (await reward.json()).ok !== true) return fail('referral_pending', 503);
  const friend = await accountRpc(env, job.friendId, '/_account/referral-complete', job);
  const data = await friend.json();
  if ((!friend.ok || data.ok !== true) && !(
    (friend.status === 410 && ['account_not_ready', 'referral_friend_deleted'].includes(data.error)) ||
    (friend.status === 400 && data.error === 'already_claimed')
  )) return fail('referral_pending', 503);

  // Both sides are idempotent if the process stops before this write. Keep
  // the one-claim limit even if the provider account is deleted and recreated.
  await storage.put('referral-job', { code: job.code, done: true, createdAt: job.createdAt });
  await storage.deleteAlarm();
  return reply(data, friend.status);
}

async function completeClaim(storage, env, job) {
  if (!job.inviterCreatedAt) return completeLegacyClaim(storage, env, job);

  const friend = await accountRpc(env, job.friendId, '/_account/referral-complete', job);
  const data = await friend.json();
  const committed = friend.ok && data.ok === true;
  const deletedAfterCommit = friend.status === 410 && data.error === 'referral_friend_deleted';
  if (!committed && !deletedAfterCommit && !(
    (friend.status === 410 && data.error === 'account_not_ready') ||
    (friend.status === 400 && data.error === 'already_claimed')
  )) return fail('referral_pending', 503);

  let inviterDaysAdded = 0;
  if (committed || deletedAfterCommit) {
    const reward = await accountRpc(env, job.inviterId, '/_account/referral-reward', job);
    const rewardData = await reward.json();
    if (reward.ok && rewardData.ok === true) inviterDaysAdded = INVITER_DAYS;
    else if (reward.status !== 404 || rewardData.error !== 'code_not_found') return fail('referral_pending', 503);
  }

  await storage.put('referral-job', { code: job.code, done: true, createdAt: job.createdAt, inviterDaysAdded });
  await storage.deleteAlarm();
  return committed ? reply({ ...data, inviterDaysAdded }) : reply(data, friend.status);
}

export async function referralClaim(storage, env, { code, friendId }) {
  const previous = await storage.get('referral-job');
  if (previous) {
    if (previous.code !== code) return fail(previous.done ? 'already_claimed' : 'referral_pending', previous.done ? 400 : 409);
    if (!previous.done) return completeClaim(storage, env, previous);
    const status = await accountRpc(env, friendId, '/_account/read', { key: 'user:' + friendId });
    if (!status.ok) return fail('referral_unavailable', 503);
    const raw = (await status.json()).value;
    const user = raw && JSON.parse(raw);
    return user?.referralCodeUsed === code && (user.createdAt || null) === previous.createdAt
      ? success(applyEntitlements(user), previous.inviterDaysAdded)
      : fail('already_claimed', 400);
  }

  const now = Date.now();
  const attempts = (await storage.get('referral-attempts') || []).filter(at => at > now - WINDOW_MS);
  if (attempts.length >= MAX_ATTEMPTS) {
    return reply({ error: 'rate_limited' }, 429, { 'Retry-After': String(Math.ceil((attempts[0] + WINDOW_MS - now) / 1000)) });
  }
  await storage.put('referral-attempts', [...attempts, now]);
  const friend = await accountRpc(env, friendId, '/_account/referral-check', { code });
  if (!friend.ok) return friend;
  const inviterId = await codeRpc(env, code, 'lookup');
  if (!inviterId) return fail('code_not_found', 404);
  if (inviterId === friendId) return fail('cannot_refer_self', 400);
  const { createdAt, email } = await friend.json();
  const inviter = await accountRpc(env, inviterId, '/_account/referral-inviter', { code, createdAt, email });
  if (!inviter.ok) return inviter;
  const { inviterCreatedAt } = await inviter.json();
  if (!inviterCreatedAt) return fail('referral_unavailable', 503);
  const job = { id: crypto.randomUUID(), code, inviterId, friendId, createdAt, inviterCreatedAt };
  await storage.setAlarm(now + 60_000);
  await storage.put('referral-job', job);
  return completeClaim(storage, env, job);
}

export async function retryReferralClaim(storage, env, job) {
  const delay = Math.min(60_000 * 2 ** (job.retries || 0), 3_600_000);
  await storage.setAlarm(Date.now() + delay);
  job.retries = (job.retries || 0) + 1;
  await storage.put('referral-job', job);
  await completeClaim(storage, env, job);
}
