import { accountRpc } from './account_state.js';

export const WEB_TARIFFS = {
  weekly: { days: 7, priceRub: 99, title: '1 неделя' },
  threeMonths: { days: 90, priceRub: 290, title: '3 месяца' },
};

const STANDARD_QUARTER = 370;
const MODES = ['legacy', 'standard', 'promotion'];
const STORES = ['appstore', 'googleplay'];
const defaults = {
  revision: 0, sbpMode: 'legacy', draftPriceRub: 290, promotionPriceRub: 290,
  storeTrials: { appstore: false, googleplay: false },
  nativeQuarter: { appstore: 'legacy', googleplay: 'legacy' },
};

function catalog(settings) {
  const priceRub = { legacy: WEB_TARIFFS.threeMonths.priceRub, standard: STANDARD_QUARTER,
    promotion: settings.promotionPriceRub }[settings.sbpMode];
  return { version: 1, tariffs: { weekly: WEB_TARIFFS.weekly,
    threeMonths: { ...WEB_TARIFFS.threeMonths, priceRub } },
    nativeQuarter: settings.nativeQuarter, storeTrials: settings.storeTrials };
}

const json = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
const invalid = () => json({ error: 'invalid_offer' }, 400);

// A single, separately addressed instance of the existing AccountState class serializes
// both price reads and writes. No KV propagation delay and no rollout migration.
export async function offersState(storage, body) {
  const current = await storage.get('premium-offers') || defaults;
  if (body?.operation === 'read') return json({ settings: current, catalog: catalog(current) });
  if (body?.revision !== current.revision) return json({ error: 'offers_changed' }, 409);
  const next = { ...current, revision: current.revision + 1 };
  switch (body.operation) {
    case 'save_promotion':
      if (!Number.isSafeInteger(body.priceRub) || body.priceRub <= 0 || body.priceRub >= STANDARD_QUARTER) return invalid();
      next.draftPriceRub = body.priceRub;
      break;
    case 'activate_sbp':
      if (!MODES.includes(body.mode)) return invalid();
      next.sbpMode = body.mode;
      if (body.mode === 'promotion') next.promotionPriceRub = current.draftPriceRub;
      break;
    case 'set_store':
      if (!STORES.includes(body.store) || !MODES.includes(body.mode) || typeof body.trial !== 'boolean') return invalid();
      next.storeTrials = { ...current.storeTrials, [body.store]: body.trial };
      next.nativeQuarter = { ...current.nativeQuarter, [body.store]: body.mode };
      break;
    default:
      return invalid();
  }
  await storage.put('premium-offers', next);
  return json({ settings: next, catalog: catalog(next) });
}

const rpc = (env, body) => accountRpc(env, 'premium-offers', '/_offers/catalog', body);

export async function readCatalog(env) {
  const result = await rpc(env, { operation: 'read' });
  if (!result?.ok) throw new Error('catalog_unavailable');
  const data = await result.json();
  if (data.catalog?.version !== 1) throw new Error('catalog_unavailable');
  return data.catalog;
}

export async function adminOffers(request, env) {
  if (request.method === 'GET') return await rpc(env, { operation: 'read' }) || json({ error: 'catalog_unavailable' }, 503);
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  let body;
  try { body = await request.json(); } catch { return invalid(); }
  if (!['save_promotion', 'activate_sbp', 'set_store'].includes(body?.operation)) return invalid();
  return await rpc(env, body) || json({ error: 'catalog_unavailable' }, 503);
}

// Old binaries displayed a fixed amount before they called the Worker. They never
// consume the rotating catalog, even after an operator activates a new price.
export async function quotedWebTariff(env, body, jsonResponse) {
  if (!Object.hasOwn(body, 'catalogVersion') && !Object.hasOwn(body, 'expectedPriceRub')) {
    return { tariff: WEB_TARIFFS[body.tier] };
  }
  if (body.catalogVersion !== 1 || !Number.isSafeInteger(body.expectedPriceRub)) {
    return { error: jsonResponse({ error: 'invalid_quote' }, 400) };
  }
  let current;
  try { current = await readCatalog(env); }
  catch { return { error: jsonResponse({ error: 'catalog_unavailable' }, 503) }; }
  const tariff = current.tariffs[body.tier];
  if (tariff.priceRub !== body.expectedPriceRub) {
    return { error: jsonResponse({ error: 'price_changed', code: 'price_changed', catalog: current }, 409) };
  }
  return { tariff };
}
