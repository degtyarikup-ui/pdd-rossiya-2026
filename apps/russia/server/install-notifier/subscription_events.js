import { premiumDate } from './premium_message.js';

const escapeHtml = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

function notice(title, user, lines) {
  return [
    '<b>' + title + '</b>',
    ...lines,
    'Пользователь: ' + escapeHtml(user.name || user.id),
    'ID аккаунта: <code>' + escapeHtml(user.id) + '</code>',
  ].join('\n');
}

// This step runs in the same AccountState transaction as the promo receipt.
export function recordPromoNotice(env, user, job) {
  if (!env.BOT_TOKEN || !env.CHAT_ID) return;
  env.__DURABLE_EFFECTS.push({ kind: 'telegram', options: { topic: 'subscriptions' },
    dedupKey: 'promo-activated:' + user.id + ':' + job.code + ':' + (user.createdAt || ''),
    text: notice('🎟 Активирован промокод', user, [
      'Промокод: <code>' + escapeHtml(job.code) + '</code>',
      'Добавлено дней: ' + job.days, 'Premium до ' + premiumDate(user.premiumExpiresAt),
    ]) });
}

// All three entry points (device, store callback and periodic refresh) use
// the same per-receipt history. The journal and delivery share the account commit.
export async function observeSubscription(env, user, verified, sendTelegram) {
  if (!verified.active || !verified.key || verified.reference.refunded) return false;
  const { store, isTest, paid } = verified.reference;
  const key = 'notified_purch:lifecycle:' + verified.key;
  const raw = await env.INSTALLS.get(key);
  const state = raw ? JSON.parse(raw) : {};
  const send = async (title, kind, instant) => {
    if (!env.BOT_TOKEN || !env.CHAT_ID) return;
    const lines = [store === 'googleplay' ? 'Google Play' : 'App Store'];
    if (instant) lines.push('Дата: ' + premiumDate(instant));
    lines.push('Доступ до ' + premiumDate(verified.expiresAt));
    if (isTest) lines.push('Тестовая среда магазина');
    const response = await sendTelegram(env, notice(title, user, lines), key + ':' + kind, { topic: 'subscriptions' });
    if (!response.ok) throw new Error('subscription notification queue unavailable');
  };
  if (verified.freeTrial && !state.trial) {
    await send('🎁 Начался бесплатный пробный период', 'trial', verified.trialStartedAt);
    state.trial = true;
  }
  if (verified.userCanceled && !state.canceled) {
    state.cancellations = (state.cancellations || 0) + 1;
    await send('🔕 Отключено автопродление' + (verified.freeTrial ? ' пробной подписки' : ' подписки'),
      'cancel:' + state.cancellations, verified.canceledAt);
    state.canceled = true;
  } else if (state.canceled && verified.autoRenewEnabled === true) {
    state.canceled = false;
  }
  if ((state.trial || verified.firstChargeAfterTrial) && !state.conversionOrder && !verified.freeTrial && paid === true && !isTest &&
      verified.orderId && !(verified.billingPeriodEndsAt <= Date.now())) {
    state.conversionOrder = verified.orderId;
  }
  const updated = JSON.stringify(state);
  if (updated !== (raw || '{}')) await env.INSTALLS.put(key, updated);
  return Boolean(state.conversionOrder && state.conversionOrder === verified.orderId);
}
