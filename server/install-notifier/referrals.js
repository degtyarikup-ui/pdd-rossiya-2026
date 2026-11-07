import { extendEntitlement } from './entitlements.js';
import { putUserRecord } from './user_store.js';
import { accountRpc } from './account_state.js';

const CODE_CHARS = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const CODE_LEN = 6;

function esc(s) {
  return String(s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

export function generateReferralCode() {
  const bytes = new Uint8Array(CODE_LEN);
  crypto.getRandomValues(bytes);
  let code = '';
  for (let i = 0; i < CODE_LEN; i++) {
    code += CODE_CHARS[bytes[i] % CODE_CHARS.length];
  }
  return code;
}

export function sanitizeCode(code) {
  return String(code || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export async function getOrCreateReferralCode(env, user) {
  if (user.referralCode) {
    const existing = await env.INSTALLS.get('ref_code:' + user.referralCode);
    if (!existing) {
      await env.INSTALLS.put('ref_code:' + user.referralCode, user.id);
    }
    return user.referralCode;
  }
  let code = null;
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = generateReferralCode();
    const existing = await env.INSTALLS.get('ref_code:' + candidate);
    if (!existing) {
      code = candidate;
      break;
    }
  }
  if (!code) {
    code = ('REF' + user.id.replace(/[^A-Za-z0-9]/g, '')).slice(0, 8).toUpperCase();
  }
  user.referralCode = code;
  await env.INSTALLS.put('ref_code:' + code, user.id);
  await putUserRecord(env, user);
  return code;
}

export async function handleGetReferral(request, env, authenticatedUser, { jsonResponse }) {
  if (!authenticatedUser?.id) return jsonResponse({ error: 'unauthorized' }, 401);
  let raw = await env.INSTALLS.get('user:' + authenticatedUser.id);
  let user = raw ? JSON.parse(raw) : null;
  if (!user) {
    user = {
      id: authenticatedUser.id,
      name: authenticatedUser.name || 'Пользователь',
      email: authenticatedUser.email || null,
      provider: authenticatedUser.provider || 'guest',
      createdAt: new Date().toISOString(),
    };
  }
  const code = await getOrCreateReferralCode(env, user);
  return jsonResponse({
    ok: true,
    code,
    link: 'https://pdd-drive.app/app/?ref=' + code,
    invitedCount: user.referralCount || 0,
    rewardDays: user.referralDaysEarned || 0,
    hasUsedReferral: Boolean(user.referredBy),
    referredBy: user.referredBy || null,
    referralCodeUsed: user.referralCodeUsed || null,
    friendBonusDays: 1,
    inviterBonusDays: 2,
  });
}

export async function rewardInviter(env, inviterId, { friendId, friendName, days = 2, now = Date.now() }) {
  if (env.ACCOUNTS) {
    const response = await accountRpc(env, inviterId, '/_account/referral-reward', {
      friendId,
      friendName,
      days,
      now,
    });
    if (!response?.ok) {
      const err = await response.json().catch(() => ({}));
      throw new Error(err.error || 'failed to reward inviter');
    }
    const data = await response.json();
    return data.inviter;
  }
  let raw = await env.INSTALLS.get('user:' + inviterId);
  if (!raw) throw new Error('inviter_not_found');
  let inviter = JSON.parse(raw);
  const deletion = JSON.parse(await env.INSTALLS.get('account_deleted:' + inviter.id) || 'null');
  if (deletion && Date.parse(inviter.createdAt || '') <= deletion.at) throw new Error('inviter_not_found');
  extendEntitlement(inviter, 'referral', days, now);
  inviter.referralCount = (inviter.referralCount || 0) + 1;
  inviter.referralDaysEarned = (inviter.referralDaysEarned || 0) + days;
  const referrals = Array.isArray(inviter.referrals) ? inviter.referrals : [];
  referrals.push({
    id: friendId,
    name: friendName || null,
    at: new Date(now).toISOString(),
  });
  inviter.referrals = referrals.slice(-50);
  await putUserRecord(env, inviter);
  return inviter;
}

export async function handleClaimReferral(request, env, authenticatedUser, { jsonResponse, sendTelegram }) {
  if (!authenticatedUser?.id) return jsonResponse({ error: 'unauthorized' }, 401);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid json' }, 400);
  }
  const cleanCode = sanitizeCode(body?.code);
  if (!cleanCode || cleanCode.length < 3 || cleanCode.length > 32) {
    return jsonResponse({ error: 'invalid_code' }, 400);
  }

  const inviterId = await env.INSTALLS.get('ref_code:' + cleanCode);
  if (!inviterId) {
    return jsonResponse({ error: 'code_not_found' }, 404);
  }

  if (inviterId === authenticatedUser.id) {
    return jsonResponse({ error: 'cannot_refer_self' }, 400);
  }

  let raw = await env.INSTALLS.get('user:' + authenticatedUser.id);
  let user = raw ? JSON.parse(raw) : null;
  if (!user) {
    user = {
      id: authenticatedUser.id,
      name: authenticatedUser.name || 'Пользователь',
      email: authenticatedUser.email || null,
      provider: authenticatedUser.provider || 'guest',
      createdAt: new Date().toISOString(),
    };
  }

  if (user.referralCode === cleanCode) {
    return jsonResponse({ error: 'cannot_refer_self' }, 400);
  }

  if (user.referredBy) {
    return jsonResponse({ error: 'already_claimed' }, 400);
  }

  const now = Date.now();
  let inviter;
  try {
    inviter = await rewardInviter(env, inviterId, {
      friendId: user.id,
      friendName: user.name,
      days: 2,
      now,
    });
  } catch (e) {
    if (e.message.includes('not found') || e.message.includes('deleted')) {
      return jsonResponse({ error: 'inviter_not_found' }, 404);
    }
    return jsonResponse({ error: 'failed_to_reward_inviter' }, 500);
  }

  // 1. Friend gets 1 day of Premium
  extendEntitlement(user, 'referral', 1, now);
  user.referredBy = inviterId;
  user.referralCodeUsed = cleanCode;
  user.referralClaimedAt = new Date(now).toISOString();
  await putUserRecord(env, user);

  if (sendTelegram && env.BOT_TOKEN && env.CHAT_ID) {
    try {
      const inviterLabel = esc(inviter.name || inviter.id);
      const friendLabel = esc(user.name || user.id);
      const msg = `🎁 <b>Реферальное приглашение</b>\n` +
        `• Пригласил: <b>${inviterLabel}</b> (+2 дня Premium)\n` +
        `• Друг: <b>${friendLabel}</b> (+1 день Premium)\n` +
        `• Код: <code>${esc(cleanCode)}</code>`;
      await sendTelegram(env, msg, 'referral:' + crypto.randomUUID(), { topic: 'purchases' });
    } catch (_) {}
  }

  return jsonResponse({
    ok: true,
    daysAdded: 1,
    inviterDaysAdded: 2,
    isPremium: user.isPremium,
    premiumExpiresAt: user.premiumExpiresAt,
    premiumSource: user.premiumSource,
  });
}
