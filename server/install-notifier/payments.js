// Оплата премиума на сайте: СБП через агрегатора Platega (docs.platega.io).
// Покупка периода — разовая, без автопродления; срок начисляется через
// extendEntitlement (источник `web`) и работает на всех платформах, где
// человек вошёл тем же аккаунтом.
//
// Пока у воркера нет секретов PLATEGA_MERCHANT_ID и PLATEGA_SECRET, оплата
// выключена: веб-пейвол показывает заглушку «СБП скоро» и только
// записывает намерение оплатить (аккаунт, тариф, почта для чека) — этого
// требует банк при согласовании. С секретами тот же запрос создаёт платёж
// и возвращает ссылку на платёжную форму; приложение менять не нужно.
//
// Доступ выдаётся только по статусу, полученному у Platega напрямую
// (GET /transaction/{id}), — не по телу уведомления и не по возврату
// клиента на сайт. Повторное подтверждение того же заказа ничего не
// добавляет: заказ отмечается в user.webPayments.

import { putUserRecord } from './user_store.js';
import { entitlementsOf, extendEntitlement, setEntitlement } from './entitlements.js';

// Тарифы сайта — единственный источник цен на сервере; те же цены и сроки
// на странице /tarify/ лендинга и в веб-пейволе приложения.
export const WEB_TARIFFS = {
  weekly: { days: 7, priceRub: 99, title: '1 неделя' },
  threeMonths: { days: 90, priceRub: 290, title: '3 месяца' },
};

const PLATEGA_API = 'https://app.platega.io';
const PLATEGA_METHODS = { sbp: 2 }; // 2 — СБП (QR и оплата из приложения банка)
// Куда Platega возвращает человека после оплаты: веб-версия приложения РФ.
// Адрес фиксирован на сервере — клиент не может подставить свой.
export const PAY_RETURN_URL = 'https://pdd-drive.ru/app/';

const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const ORDER_RE = /^[0-9a-f-]{36}$/;
// Повтор того же выбора в течение этого времени не пишется заново, а
// неоплаченный платёж переиспользуется (форма Platega живёт 15 минут).
const REPEAT_MS = 10 * 60 * 1000;
const DAY_MS = 86400000;

export class PaymentError extends Error {
  constructor(code, status = 503) { super(code); this.status = status; }
}

export function webPaymentsLive(env) {
  return Boolean(env.PLATEGA_MERCHANT_ID && env.PLATEGA_SECRET);
}

function safeEquals(a, b) {
  const x = new TextEncoder().encode(String(a || '')), y = new TextEncoder().encode(String(b || ''));
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] || 0) ^ (y[i] || 0);
  return diff === 0 && x.length > 0;
}

async function platega(env, path, body) {
  let response;
  try {
    response = await fetch((env.PLATEGA_API || PLATEGA_API) + path, {
      method: body ? 'POST' : 'GET',
      headers: { 'content-type': 'application/json', 'X-MerchantId': env.PLATEGA_MERCHANT_ID, 'X-Secret': env.PLATEGA_SECRET },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(15000),
    });
  } catch (_) { throw new PaymentError('payment provider unavailable'); }
  let data = null;
  try { data = await response.json(); } catch (_) {}
  if (response.status === 404) throw new PaymentError('transaction not found', 404);
  if (!response.ok || !data || typeof data !== 'object') throw new PaymentError('payment provider error');
  return data;
}

async function readJson(env, key) {
  const raw = await env.INSTALLS.get(key);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch (_) { return null; }
}

/**
 * POST /api/user/pay-intent — выбор оплаты на сайте (сессия обязательна).
 * Всегда записывает выбор; при подключённой платёжке ещё и создаёт платёж:
 * { ok, available: true, url, order } — иначе { ok, available: false }.
 */
export async function handlePayIntent(request, env, user, { jsonResponse, sendTelegram, esc }) {
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
  const email = String(body?.email || '').trim().toLowerCase();
  const tier = body?.tier;
  const method = body?.method;
  if (!EMAIL_RE.test(email)) return jsonResponse({ error: 'invalid email' }, 400);
  if (!WEB_TARIFFS[tier] || !PLATEGA_METHODS[method]) return jsonResponse({ error: 'invalid tariff' }, 400);
  if (!env.INSTALLS) return jsonResponse({ error: 'storage unavailable' }, 503);

  const live = webPaymentsLive(env);
  const key = 'pay_intent:' + user.id;
  const previous = await readJson(env, key);
  const now = Date.now();
  const repeat = previous && previous.email === email && previous.tier === tier && previous.method === method &&
    now - Date.parse(previous.at) < REPEAT_MS;
  if (repeat && !live) return jsonResponse({ ok: true, available: false });
  if (repeat && previous.lastOrder?.url && previous.lastOrder.tier === tier) {
    // Только неоплаченный заказ: после оплаты новая покупка — новый платёж.
    const last = await readJson(env, 'pay_order:' + previous.lastOrder.orderId);
    if (last?.status === 'pending' && last.userId === user.id) {
      return jsonResponse({ ok: true, available: true, url: last.url, order: last.orderId });
    }
  }

  const tariff = WEB_TARIFFS[tier];
  const app = typeof body.app === 'string' ? body.app.slice(0, 4) : 'ru';
  const intent = {
    userId: user.id, name: user.name || '', accountEmail: user.email || '', email, tier, method, app,
    priceRub: tariff.priceRub, at: new Date(now).toISOString(),
    firstAt: previous?.firstAt || new Date(now).toISOString(), count: (previous?.count || 0) + 1,
  };

  let order = null;
  if (live) {
    const orderId = crypto.randomUUID();
    let tx;
    try {
      tx = await platega(env, '/transaction/process', {
        paymentMethod: PLATEGA_METHODS[method],
        paymentDetails: { amount: tariff.priceRub, currency: 'RUB' },
        description: `Премиум «ПДД Россия 2026» — ${tariff.title}`,
        return: `${PAY_RETURN_URL}?pay=done&order=${orderId}`,
        failedUrl: `${PAY_RETURN_URL}?pay=failed&order=${orderId}`,
        payload: orderId,
        metadata: { userId: user.id },
      });
    } catch (error) {
      return jsonResponse({ error: error.message }, error instanceof PaymentError ? error.status : 503);
    }
    const url = tx.url || tx.redirect;
    if (typeof tx.transactionId !== 'string' || typeof url !== 'string' || !url.startsWith('https://')) {
      return jsonResponse({ error: 'payment provider error' }, 503);
    }
    order = {
      orderId, txId: tx.transactionId, userId: user.id, name: user.name || '', accountEmail: user.email || '',
      provider: user.provider || null, email, tier, days: tariff.days, amount: tariff.priceRub, currency: 'RUB',
      method, app, status: 'pending', url, createdAt: new Date(now).toISOString(),
    };
    await env.INSTALLS.put('pay_order:' + orderId, JSON.stringify(order));
    await env.INSTALLS.put('pay_tx:' + tx.transactionId, orderId);
    intent.lastOrder = { orderId, url, tier };
  }

  // Сводка в метаданных — список в админке читается одним list() без get.
  await env.INSTALLS.put(key, JSON.stringify(intent), {
    metadata: { email: email.slice(0, 120), tier, method, app, at: intent.at, count: intent.count, live },
  });

  if (!live && !previous && env.BOT_TOKEN && env.CHAT_ID) {
    const text = [
      '💳 <b>Хотят оплатить на сайте</b> (СБП ещё не подключена)',
      `👤 ${esc(user.name || 'Без имени')} · ${esc(user.email || user.id)}`,
      `📧 Почта для чека: ${esc(email)}`,
      `📦 ${esc(tariff.title)} — ${tariff.priceRub} ₽`,
    ].join('\n');
    try { await sendTelegram(env, text, 'pay_intent:' + user.id); } catch (_) {}
  }
  return jsonResponse(order
    ? { ok: true, available: true, url: order.url, order: order.orderId }
    : { ok: true, available: false });
}

/**
 * Применяет статус заказа, полученный у Platega. Возвращает заказ.
 * CONFIRMED — начисляет срок один раз, CHARGEBACKED — снимает начисленное.
 */
export async function settleOrder(env, order, deps) {
  // Оплаченный заказ ещё может вернуться возвратом (CHARGEBACKED).
  if (order.status === 'chargebacked' || order.status === 'mismatch') return order;
  const tx = await platega(env, '/transaction/' + encodeURIComponent(order.txId));
  const status = String(tx.status || '').toUpperCase();
  const details = typeof tx.paymentDetails === 'object' && tx.paymentDetails ? tx.paymentDetails : null;

  if (status === 'CONFIRMED' && order.status !== 'confirmed') {
    if (!details || Number(details.amount) !== order.amount || String(details.currency).toUpperCase() !== order.currency) {
      order.status = 'mismatch';
      await env.INSTALLS.put('pay_order:' + order.orderId, JSON.stringify(order));
      await notify(env, deps, `⚠️ <b>Оплата на сайте: сумма не совпала</b>\nЗаказ ${deps.esc(order.orderId)} · ожидали ${order.amount} ₽`, 'pay_mismatch:' + order.orderId);
      return order;
    }
    const user = await loadUser(env, order);
    user.webPayments = user.webPayments || {};
    if (!user.webPayments[order.orderId]) {
      extendEntitlement(user, 'web', order.days);
      user.webPayments[order.orderId] = { tier: order.tier, days: order.days, amount: order.amount, txId: order.txId, at: new Date().toISOString() };
      user.purchasedAt = new Date().toISOString();
      await putUserRecord(env, user);
    }
    order.status = 'confirmed';
    order.confirmedAt = new Date().toISOString();
    await env.INSTALLS.put('pay_order:' + order.orderId, JSON.stringify(order));
    const tariff = WEB_TARIFFS[order.tier];
    await notify(env, deps, [
      '💰 <b>Оплата на сайте</b> (СБП)',
      `👤 ${deps.esc(order.name || 'Без имени')} · ${deps.esc(order.accountEmail || order.userId)}`,
      `📦 ${deps.esc(tariff?.title || order.tier)} — ${order.amount} ₽ · до ${deps.esc((user.entitlements?.web?.expiresAt || '').slice(0, 10))}`,
      `📧 Чек: ${deps.esc(order.email)}`,
    ].join('\n'), 'pay_paid:' + order.orderId);
    try {
      await deps.trackStats?.(env, null, { id: 'pay_paid:' + order.orderId, kind: 'analytics', event: { type: 'purchase', app: order.app || 'ru', platform: 'web' } });
    } catch (_) {}
  } else if (status === 'CHARGEBACKED' && order.status === 'confirmed') {
    const user = await loadUser(env, order);
    const paid = user.webPayments?.[order.orderId];
    if (paid && !paid.reversed) {
      const web = entitlementsOf(user).web;
      if (web?.expiresAt) setEntitlement(user, 'web', new Date(Date.parse(web.expiresAt) - paid.days * DAY_MS).toISOString());
      paid.reversed = new Date().toISOString();
      await putUserRecord(env, user);
    }
    order.status = 'chargebacked';
    await env.INSTALLS.put('pay_order:' + order.orderId, JSON.stringify(order));
    await notify(env, deps, `↩️ <b>Возврат платежа на сайте</b>\n${deps.esc(order.accountEmail || order.userId)} · ${order.amount} ₽ — срок снят`, 'pay_chargeback:' + order.orderId);
  } else if (status === 'CANCELED' && order.status === 'pending') {
    order.status = 'canceled';
    await env.INSTALLS.put('pay_order:' + order.orderId, JSON.stringify(order));
  }
  return order;
}

async function loadUser(env, order) {
  return await readJson(env, 'user:' + order.userId) || {
    id: order.userId, name: order.name || 'Пользователь', email: order.accountEmail || null,
    provider: order.provider || 'guest', country: 'RU', app: order.app || 'ru', createdAt: new Date().toISOString(),
  };
}

async function notify(env, deps, text, dedupKey) {
  if (!env.BOT_TOKEN || !env.CHAT_ID) return;
  try { await deps.sendTelegram(env, text, dedupKey); } catch (_) {}
}

/**
 * POST /api/pay/platega/callback — уведомление Platega о смене статуса.
 * Проверяется по заголовкам X-MerchantId/X-Secret; сам статус всё равно
 * перечитывается у Platega. 200 — уведомление принято (иначе Platega
 * повторит его ещё 3 раза через 5 минут).
 */
export async function handlePlategaCallback(request, env, deps) {
  const { jsonResponse } = deps;
  if (!webPaymentsLive(env) || !env.INSTALLS) return jsonResponse({ error: 'payments disabled' }, 503);
  if (!safeEquals(request.headers.get('x-merchantid'), env.PLATEGA_MERCHANT_ID) ||
      !safeEquals(request.headers.get('x-secret'), env.PLATEGA_SECRET)) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
  const txId = typeof body?.id === 'string' ? body.id : '';
  const orderId = (typeof body?.payload === 'string' && ORDER_RE.test(body.payload) ? body.payload : null) ||
    (txId ? await env.INSTALLS.get('pay_tx:' + txId) : null);
  const order = orderId ? await readJson(env, 'pay_order:' + orderId) : null;
  // Чужой или неизвестный платёж подтверждаем, чтобы Platega не повторяла.
  if (!order || (txId && order.txId !== txId)) return jsonResponse({ ok: true, ignored: true });
  try {
    await settleOrder(env, order, deps);
  } catch (error) {
    return jsonResponse({ error: error.message }, error instanceof PaymentError && error.status < 500 ? 200 : 503);
  }
  return jsonResponse({ ok: true });
}

/**
 * POST /api/user/pay-check {order} — возврат с платёжной формы: если
 * уведомление ещё не пришло, статус перечитывается у Platega.
 */
export async function handlePayCheck(request, env, user, deps) {
  const { jsonResponse } = deps;
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
  const orderId = String(body?.order || '');
  if (!ORDER_RE.test(orderId)) return jsonResponse({ error: 'invalid order' }, 400);
  const order = env.INSTALLS ? await readJson(env, 'pay_order:' + orderId) : null;
  if (!order || order.userId !== user.id) return jsonResponse({ error: 'order not found' }, 404);
  if (order.status === 'pending' && webPaymentsLive(env)) {
    try { await settleOrder(env, order, deps); } catch (_) {}
  }
  return jsonResponse({ ok: true, status: order.status });
}

/**
 * POST /api/pay/lead {email, tier} — выбор тарифа на странице /tarify/
 * лендинга (без входа в аккаунт): заглушка «оплата скоро» и почта для
 * письма о запуске. Одна запись на почту; повтор в течение 10 минут не
 * пишется (бесплатный KV — 1000 записей в сутки).
 */
export async function handlePayLead(request, env, { jsonResponse, sendTelegram, esc }) {
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
  const email = String(body?.email || '').trim().toLowerCase();
  const tier = body?.tier;
  // Скрытое поле-ловушка: его заполняют только боты.
  if (body?.website) return jsonResponse({ ok: true, available: webPaymentsLive(env) });
  if (!EMAIL_RE.test(email)) return jsonResponse({ error: 'invalid email' }, 400);
  if (!WEB_TARIFFS[tier]) return jsonResponse({ error: 'invalid tariff' }, 400);
  if (!env.INSTALLS) return jsonResponse({ error: 'storage unavailable' }, 503);
  const key = 'pay_lead:' + email.slice(0, 200);
  const previous = await readJson(env, key);
  const now = Date.now();
  if (!(previous && previous.tier === tier && now - Date.parse(previous.at) < REPEAT_MS)) {
    const lead = { email, tier, source: 'tarify', priceRub: WEB_TARIFFS[tier].priceRub, at: new Date(now).toISOString(),
      firstAt: previous?.firstAt || new Date(now).toISOString(), count: (previous?.count || 0) + 1,
      ipCountry: request.headers.get('cf-ipcountry') || null };
    await env.INSTALLS.put(key, JSON.stringify(lead), {
      metadata: { email: email.slice(0, 120), tier, method: 'sbp', source: 'tarify', at: lead.at, count: lead.count },
    });
    if (!previous && env.BOT_TOKEN && env.CHAT_ID) {
      const tariff = WEB_TARIFFS[tier];
      try {
        await sendTelegram(env, [
          '💳 <b>Хотят оплатить</b> (страница тарифов, СБП ещё не подключена)',
          `📧 ${esc(email)}`,
          `📦 ${esc(tariff.title)} — ${tariff.priceRub} ₽`,
        ].join('\n'), key);
      } catch (_) {}
    }
  }
  return jsonResponse({ ok: true, available: webPaymentsLive(env) });
}

/** GET /api/admin/pay-intents — кто выбирал оплату: в веб-версии и на странице тарифов (новые сверху). */
export async function listPayIntents(env) {
  const items = [];
  let cursor;
  do {
    const page = await env.INSTALLS.list({ prefix: 'pay_intent:', cursor });
    for (const key of page.keys) items.push({ userId: key.name.slice('pay_intent:'.length), ...(key.metadata || {}) });
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  do {
    const page = await env.INSTALLS.list({ prefix: 'pay_lead:', cursor });
    for (const key of page.keys) items.push({ userId: null, source: 'tarify', ...(key.metadata || {}) });
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  items.sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')));
  return items;
}
