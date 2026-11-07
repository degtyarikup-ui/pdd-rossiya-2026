import { extendEntitlement } from './entitlements.js';
import { putUserRecord, userSummary } from './user_store.js';
import { accountRead, accountWrite } from './account_state.js';

const CODE_CHARS = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const CODE_LEN = 6;

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

  if (user.referredBy) {
    return jsonResponse({ error: 'already_claimed' }, 400);
  }

  let inviterRaw = await accountRead(env, inviterId, 'user:' + inviterId);
  let inviter = inviterRaw ? JSON.parse(inviterRaw) : null;
  if (!inviter) {
    return jsonResponse({ error: 'inviter_not_found' }, 404);
  }

  const now = Date.now();
  // 1. Friend gets 1 day of Premium
  extendEntitlement(user, 'referral', 1, now);
  user.referredBy = inviterId;
  user.referralCodeUsed = cleanCode;
  user.referralClaimedAt = new Date(now).toISOString();
  await putUserRecord(env, user);

  // 2. Inviter gets 2 days of Premium
  extendEntitlement(inviter, 'referral', 2, now);
  inviter.referralCount = (inviter.referralCount || 0) + 1;
  inviter.referralDaysEarned = (inviter.referralDaysEarned || 0) + 2;
  const referrals = Array.isArray(inviter.referrals) ? inviter.referrals : [];
  referrals.push({
    id: user.id,
    name: user.name || null,
    at: new Date(now).toISOString(),
  });
  inviter.referrals = referrals.slice(-50);
  await accountWrite(env, inviterId, 'user:' + inviterId, JSON.stringify(inviter), { metadata: userSummary(inviter) });

  if (sendTelegram && env.BOT_TOKEN && env.CHAT_ID) {
    try {
      const msg = `🎁 <b>Реферальное приглашение</b>\n` +
        `• Пригласил: <b>${inviter.name || inviter.id}</b> (+2 дня Premium)\n` +
        `• Друг: <b>${user.name || user.id}</b> (+1 день Premium)\n` +
        `• Код: <code>${cleanCode}</code>`;
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
