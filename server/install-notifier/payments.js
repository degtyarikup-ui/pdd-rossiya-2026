// Оплата на сайте (СБП через платёжного агрегатора). Пока платёжка не
// подключена, веб-пейвол показывает заглушку «СБП скоро» и записывает
// намерение оплатить: аккаунт, выбранный тариф и почту для чека — этого
// требует банк при согласовании. Покупка периода — разовая, без
// автопродления; срок начисляется через extendEntitlement (источник `web`).

// Тарифы сайта — единственный источник цен на сервере; те же цены и сроки
// на странице /tarify/ лендинга и в веб-пейволе приложения.
export const WEB_TARIFFS = {
  weekly: { days: 7, priceRub: 99, title: '1 неделя' },
  threeMonths: { days: 90, priceRub: 290, title: '3 месяца' },
};

const METHODS = new Set(['sbp']);
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
// Повтор того же выбора в течение этого времени не пишется заново
// (бесплатный KV — 1000 записей в сутки).
const REPEAT_MS = 10 * 60 * 1000;

/** POST /api/user/pay-intent — выбор способа оплаты на сайте (сессия обязательна). */
export async function handlePayIntent(request, env, user, { jsonResponse, sendTelegram, esc }) {
  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
  const email = String(body?.email || '').trim().toLowerCase();
  const tier = body?.tier;
  const method = body?.method;
  if (!EMAIL_RE.test(email)) return jsonResponse({ error: 'invalid email' }, 400);
  if (!WEB_TARIFFS[tier] || !METHODS.has(method)) return jsonResponse({ error: 'invalid tariff' }, 400);
  if (!env.INSTALLS) return jsonResponse({ error: 'storage unavailable' }, 503);

  const key = 'pay_intent:' + user.id;
  const raw = await env.INSTALLS.get(key);
  const previous = raw ? JSON.parse(raw) : null;
  const now = Date.now();
  if (previous && previous.email === email && previous.tier === tier && previous.method === method &&
      now - Date.parse(previous.at) < REPEAT_MS) {
    return jsonResponse({ ok: true, available: false });
  }
  const app = typeof body.app === 'string' ? body.app.slice(0, 4) : 'ru';
  const intent = {
    userId: user.id, name: user.name || '', accountEmail: user.email || '', email, tier, method, app,
    priceRub: WEB_TARIFFS[tier].priceRub, at: new Date(now).toISOString(),
    firstAt: previous?.firstAt || new Date(now).toISOString(), count: (previous?.count || 0) + 1,
  };
  // Сводка в метаданных — список в админке читается одним list() без get.
  await env.INSTALLS.put(key, JSON.stringify(intent), {
    metadata: { email: email.slice(0, 120), tier, method, app, at: intent.at, count: intent.count },
  });

  if (!previous && env.BOT_TOKEN && env.CHAT_ID) {
    const tariff = WEB_TARIFFS[tier];
    const text = [
      '💳 <b>Хотят оплатить на сайте</b> (СБП ещё не подключена)',
      `👤 ${esc(user.name || 'Без имени')} · ${esc(user.email || user.id)}`,
      `📧 Почта для чека: ${esc(email)}`,
      `📦 ${esc(tariff.title)} — ${tariff.priceRub} ₽`,
    ].join('\n');
    try { await sendTelegram(env, text, 'pay_intent:' + user.id); } catch (_) {}
  }
  // available: false — платёжка ещё не подключена, приложение показывает заглушку.
  return jsonResponse({ ok: true, available: false });
}

/** GET /api/admin/pay-intents — кто хотел оплатить на сайте (новые сверху). */
export async function listPayIntents(env) {
  const items = [];
  let cursor;
  do {
    const page = await env.INSTALLS.list({ prefix: 'pay_intent:', cursor });
    for (const key of page.keys) items.push({ userId: key.name.slice('pay_intent:'.length), ...(key.metadata || {}) });
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  items.sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')));
  return items;
}
