// Read-only merchant balances. This module never changes payments, payouts or
// the economy ledger. USDT remains its own currency; balances are not revenue.
// Contract: https://docs.platega.io/получение-балансов-33582950e0
const API = 'https://app.platega.io';
const TIMEOUT_MS = 7000;

function reply(body, status = 200) {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
}
function failure(code, error, status = 503) {
  return reply({ ok: false, code, error }, status);
}
function timeout(error) {
  return ['AbortError', 'TimeoutError'].includes(error?.name);
}
function balancesFrom(data) {
  // The published OpenAPI schema is an array, not a data/result envelope.
  if (!Array.isArray(data)) throw new Error('invalid balances');
  const currencies = new Set();
  return data.map(item => {
    if (!item || typeof item !== 'object' || Array.isArray(item)
      || typeof item.currency !== 'string' || !/^[A-Z][A-Z0-9]{2,9}$/.test(item.currency)
      || currencies.has(item.currency) || typeof item.amount !== 'number' || !Number.isFinite(item.amount)) {
      throw new Error('invalid balance');
    }
    currencies.add(item.currency);
    const row = { currency: item.currency, amount: item.amount };
    if (Object.hasOwn(item, 'frozenBalance')) {
      if (item.currency !== 'USDT' || typeof item.frozenBalance !== 'number'
        || !Number.isFinite(item.frozenBalance) || item.frozenBalance < 0) throw new Error('invalid frozen balance');
      row.frozenBalance = item.frozenBalance;
    }
    return row;
  });
}

export async function handlePlategaBalances(env, deps = {}) {
  if (!env?.PLATEGA_MERCHANT_ID || !env?.PLATEGA_SECRET) {
    return reply({ ok: true, configured: false, updatedAt: null, balances: [] });
  }
  let response;
  try {
    response = await (deps.fetch || globalThis.fetch)(new URL('/balance/all', env.PLATEGA_API || API).href, {
      method: 'GET', redirect: 'manual',
      headers: { Accept: 'application/json', 'X-MerchantId': env.PLATEGA_MERCHANT_ID, 'X-Secret': env.PLATEGA_SECRET },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (error) {
    return timeout(error)
      ? failure('platega_timeout', 'Platega не ответила вовремя. Повторите обновление.')
      : failure('platega_unavailable', 'Не удалось связаться с Platega. Повторите обновление.');
  }
  if ([401, 403].includes(response.status)) return failure('platega_auth', 'Platega отклонила доступ. Проверьте API-ключ в настройках сервера.');
  if (response.status === 429) return failure('platega_rate_limited', 'Platega ограничила запросы. Обновите баланс позже.');
  if (!response.ok) return failure('platega_unavailable', 'Баланс Platega временно недоступен. Повторите обновление.');
  let balances;
  try {
    balances = balancesFrom(await response.json());
  } catch (error) {
    return timeout(error)
      ? failure('platega_timeout', 'Platega не ответила вовремя. Повторите обновление.')
      : failure('platega_invalid_response', 'Platega вернула неполные данные. Баланс не обновлён.', 502);
  }
  return reply({ ok: true, configured: true, updatedAt: new Date(deps.now ?? Date.now()).toISOString(), balances });
}
