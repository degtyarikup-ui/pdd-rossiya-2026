// API раздела «Экономика»: доходы, расходы, фонд развития, доли партнеров,
// точка безубыточности, юнит-экономика и реестр чеков.
// Хранилище настроек и кастомных записей: KV env.INSTALLS (economy_config).

export const DEFAULT_ECONOMY_CONFIG = {
  usdRate: 95.0,             // Курс USD/RUB
  cloudflareMonthlyUsd: 5.0,  // Подписка Cloudflare в $
  domainMonthlyRub: 67.0,     // Домен pdd-drive.ru (800 ₽ в год = ~67 ₽ / мес)
  reinvestPercent: 15.0,      // % реинвестиций в развитие (15% от операционной прибыли)
  nikitaSharePercent: 6.7,    // Доля Никиты (6.7% от распределяемой прибыли)
  sergeySharePercent: 93.3,   // Доля Сергея (93.3% от распределяемой прибыли)
  targetMonthlyProfit: 50000, // Целевая прибыль по умолчанию (50 000 ₽)
  excludeTestOrders: true,    // Исключать тестовые заказы (включая 99 ₽ СБП от разработчика)
  extraExpenses: [],
  manualRevenues: [],         // Фактические подтвержденные выплаты от сторов (Apple, Google, RuStore)
};

const KV_ECONOMY_CONFIG_KEY = 'economy_config';

function reply(data, status = 200, extraHeaders = {}) {
  return Response.json(data, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
      ...extraHeaders,
    },
  });
}

export function isTestOrder(ord) {
  if (!ord) return false;
  if (ord.isTest === true || ord.test === true) return true;
  const email = String(ord.email || ord.accountEmail || '').toLowerCase();
  const name = String(ord.name || '').toLowerCase();
  const userId = String(ord.userId || '').toLowerCase();
  if (email.includes('mojomaker') || email.includes('sergei') || name.includes('сергей') || userId.includes('test') || userId === 'admin') {
    return true;
  }
  // Тестовая покупка за 99 ₽ в СБП от создателя
  if (ord.amount === 99 && (ord.method === 2 || ord.method === 'sbp' || String(ord.tier).toLowerCase().includes('week'))) {
    return true;
  }
  return false;
}

export async function getEconomyConfig(env) {
  if (!env || !env.INSTALLS) return { ...DEFAULT_ECONOMY_CONFIG };
  try {
    const raw = await env.INSTALLS.get(KV_ECONOMY_CONFIG_KEY);
    if (!raw) return { ...DEFAULT_ECONOMY_CONFIG };
    const parsed = JSON.parse(raw);
    return {
      ...DEFAULT_ECONOMY_CONFIG,
      ...parsed,
      sergeySharePercent: Math.max(0, 100 - (Number(parsed.nikitaSharePercent) || DEFAULT_ECONOMY_CONFIG.nikitaSharePercent)),
    };
  } catch (err) {
    console.error('getEconomyConfig error:', err);
    return { ...DEFAULT_ECONOMY_CONFIG };
  }
}

export async function saveEconomyConfig(env, updates) {
  if (!env || !env.INSTALLS) return false;
  const current = await getEconomyConfig(env);
  const next = {
    ...current,
    ...updates,
  };
  if (typeof updates.nikitaSharePercent === 'number') {
    next.nikitaSharePercent = Math.min(100, Math.max(0, updates.nikitaSharePercent));
    next.sergeySharePercent = Number((100 - next.nikitaSharePercent).toFixed(2));
  }
  if (typeof updates.reinvestPercent === 'number') {
    next.reinvestPercent = Math.min(100, Math.max(0, updates.reinvestPercent));
  }
  if (typeof updates.usdRate === 'number' && updates.usdRate > 0) {
    next.usdRate = updates.usdRate;
  }
  if (typeof updates.cloudflareMonthlyUsd === 'number' && updates.cloudflareMonthlyUsd >= 0) {
    next.cloudflareMonthlyUsd = updates.cloudflareMonthlyUsd;
  }
  if (typeof updates.domainMonthlyRub === 'number' && updates.domainMonthlyRub >= 0) {
    next.domainMonthlyRub = updates.domainMonthlyRub;
  }
  if (typeof updates.excludeTestOrders === 'boolean') {
    next.excludeTestOrders = updates.excludeTestOrders;
  }
  if (Array.isArray(updates.extraExpenses)) {
    next.extraExpenses = updates.extraExpenses;
  }
  if (Array.isArray(updates.manualRevenues)) {
    next.manualRevenues = updates.manualRevenues;
  }
  await env.INSTALLS.put(KV_ECONOMY_CONFIG_KEY, JSON.stringify(next));
  return next;
}

export async function computeEconomyStats(env, period = 'month', deps = {}) {
  const config = await getEconomyConfig(env);
  const { listUserSummaries } = deps;

  const now = Date.now();
  const nowDate = new Date(now);
  const currentMonthStart = new Date(Date.UTC(nowDate.getUTCFullYear(), nowDate.getUTCMonth(), 1)).getTime();
  const thirtyDaysStart = now - 30 * 86400000;

  let periodStart = 0;
  if (period === 'month') {
    periodStart = currentMonthStart;
  } else if (period === '30d') {
    periodStart = thirtyDaysStart;
  } else {
    periodStart = 0; // all time
  }

  // 1. ИИ Затраты (Gemini)
  let aiCostUsd = 0.18; // Базовое значение из Google AI Studio
  let aiTotalRequests = 0;
  let aiPromptTokens = 0;
  let aiCandidateTokens = 0;
  if (env && env.INSTALLS) {
    try {
      const rawCost = await env.INSTALLS.get('ai_stats_cost_usd');
      if (rawCost !== null) aiCostUsd = parseFloat(rawCost);
      aiTotalRequests = parseInt(await env.INSTALLS.get('ai_stats_total_req') || '0', 10);
      aiPromptTokens = parseInt(await env.INSTALLS.get('ai_stats_prompt_tokens') || '0', 10);
      aiCandidateTokens = parseInt(await env.INSTALLS.get('ai_stats_candidate_tokens') || '0', 10);
    } catch (_) {}
  }
  const aiCostRub = Number((aiCostUsd * config.usdRate).toFixed(2));

  // 2. Расходы на Cloudflare ($5) и Домен
  const cloudflareMonthlyRub = Number((config.cloudflareMonthlyUsd * config.usdRate).toFixed(2));
  const domainMonthlyRub = Number(config.domainMonthlyRub || 67.0);

  // 3. Кастомные расходы из настроек
  const extraExpenses = Array.isArray(config.extraExpenses) ? config.extraExpenses : [];
  let extraExpensesRub = 0;
  for (const exp of extraExpenses) {
    const expDate = exp.createdAt ? new Date(exp.createdAt).getTime() : now;
    if (exp.monthly || expDate >= periodStart) {
      extraExpensesRub += Number(exp.amountRub) || 0;
    }
  }

  const totalExpensesRub = Number((cloudflareMonthlyRub + domainMonthlyRub + aiCostRub + extraExpensesRub).toFixed(2));

  // 4. Доходы и Чеки (Receipts)
  const receipts = [];
  let webConfirmedOrdersCount = 0;
  let webRevenueRub = 0;

  if (env && env.INSTALLS) {
    try {
      const orderKeys = await env.INSTALLS.list({ prefix: 'pay_order:', limit: 500 });
      for (const k of orderKeys.keys || []) {
        try {
          const rawOrder = await env.INSTALLS.get(k.name);
          if (!rawOrder) continue;
          const ord = JSON.parse(rawOrder);
          if (ord && (ord.status === 'confirmed' || ord.confirmedAt)) {
            const ordTime = Date.parse(ord.confirmedAt || ord.createdAt || 0);
            const isTest = isTestOrder(ord);
            const amt = Number(ord.amount) || (ord.tier === 'threeMonths' ? 290 : 99);

            receipts.push({
              id: ord.orderId || ord.txId,
              date: ord.confirmedAt || ord.createdAt || new Date().toISOString(),
              customer: ord.name || ord.accountEmail || ord.email || ord.userId || 'Пользователь',
              email: ord.email || ord.accountEmail || '',
              store: 'СБП (Platega)',
              storeKey: 'web',
              tier: ord.tier === 'threeMonths' ? '3 месяца' : '1 неделя',
              amountRub: amt,
              txId: ord.txId || ord.orderId || '—',
              isTest,
              status: ord.status || 'confirmed',
            });

            // Тестовые заказы исключаем из выручки, если включен фильтр excludeTestOrders
            if (ordTime >= periodStart) {
              if (!isTest || !config.excludeTestOrders) {
                webRevenueRub += amt;
                webConfirmedOrdersCount++;
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // 5. Пользователи
  let totalUsersCount = 0;
  let activePayingCount = webConfirmedOrdersCount;
  const storeCounts = {
    web: webConfirmedOrdersCount,
    appstore: 0,
    googleplay: 0,
    rustore: 0,
    admin_grant: 0,
  };

  let appstoreRevenueRub = 0;
  let gplayRevenueRub = 0;
  let rustoreRevenueRub = 0;
  let manualRevenuesRub = 0;

  if (typeof listUserSummaries === 'function') {
    try {
      const users = await listUserSummaries(env);
      totalUsersCount = users.length;
      for (const u of users) {
        if (u.isPremium) {
          const src = (u.premiumSource || '').toLowerCase();
          if (storeCounts[src] !== undefined) {
            storeCounts[src]++;
          }
          if (src && src !== 'admin_grant' && src !== 'web') {
            activePayingCount++;

            // Получаем полную запись пользователя для чека и продукта
            let fullUser = null;
            if (env && env.INSTALLS && typeof env.INSTALLS.get === 'function') {
              try {
                const raw = await env.INSTALLS.get('user:' + u.id);
                if (raw) fullUser = JSON.parse(raw);
              } catch (_) {}
            }

            const vp = fullUser?.verifiedPurchase || {};
            const prod = String(vp.productId || '').toLowerCase();
            const purchaseTime = u.storeVerifiedAt
              ? Number(u.storeVerifiedAt)
              : Date.parse(u.purchasedAt || u.createdAt || 0);
            const purchaseDate = new Date(purchaseTime).toISOString();
            const expiryTime = Date.parse(u.premiumExpiresAt || 0);
            const diffDays = (expiryTime && purchaseTime && expiryTime > purchaseTime)
              ? Math.round((expiryTime - purchaseTime) / 86400000)
              : 0;

            const is3m = prod.includes('3month') || diffDays >= 60;
            const amt = is3m ? 290 : 99;
            const tierTitle = is3m ? '3 месяца' : '1 неделя';
            const txId = vp.transactionId || u.id;

            const storeName = src === 'appstore' ? 'App Store' : src === 'googleplay' ? 'Google Play' : src === 'rustore' ? 'RuStore' : 'Стор';

            receipts.push({
              id: txId,
              date: purchaseDate,
              customer: u.name || u.email || ('Пользователь ' + storeName),
              email: u.email || '',
              store: storeName,
              storeKey: src,
              tier: tierTitle,
              amountRub: amt,
              txId: txId,
              isTest: false,
              status: 'confirmed',
            });

            if (purchaseTime >= periodStart) {
              if (src === 'appstore') appstoreRevenueRub += amt;
              else if (src === 'googleplay') gplayRevenueRub += amt;
              else if (src === 'rustore') rustoreRevenueRub += amt;
            }
          }
        }
      }
    } catch (e) {
      console.error('listUserSummaries error in economy:', e);
    }
  }

  // Ручные фактические выплаты от сторов (Apple, Google, RuStore)
  const manualRevenues = Array.isArray(config.manualRevenues) ? config.manualRevenues : [];

  for (const mr of manualRevenues) {
    const mrDate = mr.date ? new Date(mr.date).getTime() : now;
    const amt = Number(mr.amountRub) || 0;
    receipts.push({
      id: mr.id,
      date: mr.date || mr.createdAt || new Date().toISOString(),
      customer: mr.title || 'Выплата магазина',
      email: '',
      store: mr.store === 'appstore' ? 'App Store' : mr.store === 'googleplay' ? 'Google Play' : mr.store === 'rustore' ? 'RuStore' : 'Выплата',
      storeKey: mr.store || 'other',
      tier: 'Выплата стора',
      amountRub: amt,
      txId: mr.id,
      isTest: false,
      status: 'confirmed',
    });

    if (mrDate >= periodStart) {
      manualRevenuesRub += amt;
      if (mr.store === 'appstore') appstoreRevenueRub += amt;
      else if (mr.store === 'googleplay') gplayRevenueRub += amt;
      else if (mr.store === 'rustore') rustoreRevenueRub += amt;
    }
  }

  // Сортировка чеков: новые сверху
  receipts.sort((a, b) => Date.parse(b.date || 0) - Date.parse(a.date || 0));

  const grossRevenueRub = Number((webRevenueRub + appstoreRevenueRub + gplayRevenueRub + rustoreRevenueRub).toFixed(2));

  // 6. Операционная прибыль и Реинвестиции
  const operatingProfitRub = Number((grossRevenueRub - totalExpensesRub).toFixed(2));

  // Фонд развития (15% от операционной прибыли, если она положительная)
  const reinvestPercent = Number(config.reinvestPercent) || 15.0;
  const reinvestRub = operatingProfitRub > 0
    ? Number(((operatingProfitRub * reinvestPercent) / 100).toFixed(2))
    : 0;

  // Чистая распределяемая прибыль = Операционная прибыль - Реинвестиции
  const distributableNetProfitRub = operatingProfitRub > 0
    ? Number((operatingProfitRub - reinvestRub).toFixed(2))
    : operatingProfitRub;

  // 7. Доли основателей (Никита 6.7%, Сергей 93.3% от чистой распределяемой прибыли)
  const nikitaSharePercent = Number(config.nikitaSharePercent) || 6.7;
  const sergeySharePercent = Number((100 - nikitaSharePercent).toFixed(2));

  const sergeyPayoutRub = distributableNetProfitRub > 0
    ? Number(((distributableNetProfitRub * sergeySharePercent) / 100).toFixed(2))
    : 0;
  const nikitaPayoutRub = distributableNetProfitRub > 0
    ? Number(((distributableNetProfitRub * nikitaSharePercent) / 100).toFixed(2))
    : 0;

  // Рентабельность (Margin)
  const marginPercent = grossRevenueRub > 0
    ? Number(((distributableNetProfitRub / grossRevenueRub) * 100).toFixed(1))
    : 0;

  // 8. Точка безубыточности (Break-Even)
  const weeklySubsToBreakEven = Math.max(1, Math.ceil(totalExpensesRub / 99));
  const threeMonthSubsToBreakEven = Math.max(1, Math.ceil(totalExpensesRub / 290));
  const coveragePercent = totalExpensesRub > 0
    ? Math.round((grossRevenueRub / totalExpensesRub) * 100)
    : 100;

  // 9. Юнит-экономика
  const payingConversionRate = totalUsersCount > 0
    ? Number(((activePayingCount / totalUsersCount) * 100).toFixed(2))
    : 0;
  const arppu = activePayingCount > 0
    ? Number((grossRevenueRub / activePayingCount).toFixed(0))
    : 0;
  const arpu = totalUsersCount > 0
    ? Number((grossRevenueRub / totalUsersCount).toFixed(2))
    : 0;

  return {
    period,
    updatedAt: new Date(now).toISOString(),
    config: {
      usdRate: config.usdRate,
      cloudflareMonthlyUsd: config.cloudflareMonthlyUsd,
      domainMonthlyRub,
      reinvestPercent,
      nikitaSharePercent,
      sergeySharePercent,
      targetMonthlyProfit: config.targetMonthlyProfit,
      excludeTestOrders: config.excludeTestOrders,
      extraExpenses,
      manualRevenues,
    },
    revenue: {
      grossRub: grossRevenueRub,
      webRub: Number(webRevenueRub.toFixed(2)),
      appstoreRub: Number(appstoreRevenueRub.toFixed(2)),
      gplayRub: Number(gplayRevenueRub.toFixed(2)),
      rustoreRub: Number(rustoreRevenueRub.toFixed(2)),
      manualRub: Number(manualRevenuesRub.toFixed(2)),
      ordersCount: webConfirmedOrdersCount,
      activePayingCount,
      storeCounts,
    },
    receipts,
    expenses: {
      totalRub: totalExpensesRub,
      cloudflare: {
        usd: config.cloudflareMonthlyUsd,
        rub: cloudflareMonthlyRub,
      },
      domain: {
        rub: domainMonthlyRub,
      },
      ai: {
        usd: Number(aiCostUsd.toFixed(4)),
        rub: aiCostRub,
        totalRequests: aiTotalRequests,
        promptTokens: aiPromptTokens,
        candidateTokens: aiCandidateTokens,
      },
      extraExpensesRub,
      extraList: extraExpenses,
    },
    profit: {
      operatingRub: operatingProfitRub,
      reinvestPercent,
      reinvestRub,
      distributableNetRub: distributableNetProfitRub,
      marginPercent,
    },
    partners: {
      sergey: {
        name: 'Сергей',
        role: 'Основатель / Разработка',
        percent: sergeySharePercent,
        payoutRub: sergeyPayoutRub,
      },
      nikita: {
        name: 'Никита',
        role: 'Партнёр / Развитие',
        percent: nikitaSharePercent,
        payoutRub: nikitaPayoutRub,
      },
    },
    breakEven: {
      targetRub: totalExpensesRub,
      weeklySubsNeeded: weeklySubsToBreakEven,
      threeMonthSubsNeeded: threeMonthSubsToBreakEven,
      coveragePercent,
      isProfitable: grossRevenueRub >= totalExpensesRub,
    },
    unitEconomics: {
      totalUsersCount,
      activePayingCount,
      payingConversionRate,
      arppu,
      arpu,
    },
  };
}

/**
 * Маршрутизатор /api/admin/economy*
 */
export async function handleEconomyAdmin(request, env, url, deps = {}) {
  const path = url.pathname;
  const method = request.method;

  if (path === '/api/admin/economy/stats' && method === 'GET') {
    const period = url.searchParams.get('period') || 'month';
    const stats = await computeEconomyStats(env, period, deps);
    return reply({ ok: true, ...stats });
  }

  if (path === '/api/admin/economy/settings' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }
    const updated = await saveEconomyConfig(env, body);
    return reply({ ok: true, config: updated });
  }

  if (path === '/api/admin/economy/expenses/add' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }
    const title = String(body.title || '').trim();
    const amountRub = Number(body.amountRub);
    if (!title) return reply({ error: 'Укажите название расхода' }, 400);
    if (!Number.isFinite(amountRub) || amountRub <= 0) return reply({ error: 'Укажите корректную сумму расхода' }, 400);

    const config = await getEconomyConfig(env);
    const item = {
      id: crypto.randomUUID(),
      title,
      amountRub,
      monthly: Boolean(body.monthly),
      createdAt: new Date().toISOString(),
    };
    const nextList = [item, ...(config.extraExpenses || [])];
    await saveEconomyConfig(env, { extraExpenses: nextList });
    return reply({ ok: true, expense: item });
  }

  if (path === '/api/admin/economy/expenses/delete' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }
    const id = String(body.id || '');
    if (!id) return reply({ error: 'Не указан ID' }, 400);

    const config = await getEconomyConfig(env);
    const nextList = (config.extraExpenses || []).filter(e => e.id !== id);
    await saveEconomyConfig(env, { extraExpenses: nextList });
    return reply({ ok: true, id });
  }

  if (path === '/api/admin/economy/revenues/add' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }
    const title = String(body.title || '').trim();
    const amountRub = Number(body.amountRub);
    const store = String(body.store || 'other');
    if (!title) return reply({ error: 'Укажите описание поступления' }, 400);
    if (!Number.isFinite(amountRub) || amountRub <= 0) return reply({ error: 'Укажите корректную сумму' }, 400);

    const config = await getEconomyConfig(env);
    const item = {
      id: crypto.randomUUID(),
      title,
      amountRub,
      store,
      date: body.date || new Date().toISOString(),
      createdAt: new Date().toISOString(),
    };
    const nextList = [item, ...(config.manualRevenues || [])];
    await saveEconomyConfig(env, { manualRevenues: nextList });
    return reply({ ok: true, revenue: item });
  }

  if (path === '/api/admin/economy/revenues/delete' && method === 'POST') {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return reply({ error: 'Некорректный JSON' }, 400);
    }
    const id = String(body.id || '');
    if (!id) return reply({ error: 'Не указан ID' }, 400);

    const config = await getEconomyConfig(env);
    const nextList = (config.manualRevenues || []).filter(r => r.id !== id);
    await saveEconomyConfig(env, { manualRevenues: nextList });
    return reply({ ok: true, id });
  }

  return reply({ error: 'not found' }, 404);
}
