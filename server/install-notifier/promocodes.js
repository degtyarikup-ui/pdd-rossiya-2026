import { accountRpc } from './account_state.js';
import { sanitizeCode, codeRpc, liveUser, readClaimCode } from './referrals.js';
import { extendEntitlement, applyEntitlements } from './entitlements.js';
import { putUserRecord } from './user_store.js';

const json = (data, status = 200, headers = {}) => Response.json(data, { status, headers: { 'Cache-Control': 'no-store', ...headers } });
const fail = (error, status = 400) => json({ error }, status);
const marker = '@promotion';
const rpc = (env, body) => accountRpc(env, 'promotions', '/_promo/catalog', body);

export async function handlePromoClaim(request, env, user, jsonResponse) {
  if (!user?.id) return jsonResponse({ error: 'unauthorized' }, 401);
  const code = await readClaimCode(request);
  if (!code) return jsonResponse({ error: 'invalid_code' }, 400);
  const res = await rpc(env, { operation: 'claim', userId: user.id, code });
  return jsonResponse(await res.json(), res.status, { 'Cache-Control': 'no-store',
    ...(res.headers.has('Retry-After') ? { 'Retry-After': res.headers.get('Retry-After') } : {}) });
}

export async function handlePromoAdmin(request, env) {
  if (request.method === 'GET') {
    const url = new URL(request.url);
    return rpc(env, url.searchParams.has('code')
      ? { operation: 'history', code: url.searchParams.get('code'), cursor: url.searchParams.get('cursor') }
      : { operation: 'list' });
  }
  if (request.method !== 'POST') return fail('method_not_allowed', 405);
  let body;
  try { body = await request.json(); } catch { return fail('invalid_json'); }
  if (!['create', 'update', 'toggle', 'delete'].includes(body?.operation)) return fail('invalid_operation');
  return rpc(env, body);
}

export async function promoAccountStep(request, env) {
  const job = await request.json();
  const user = await liveUser(env);
  if (!user) return fail('account_not_ready', 410);
  if (job.operation === 'check') return json({ createdAt: user.createdAt || null });
  if ((user.createdAt || null) !== job.createdAt) return fail('account_not_ready', 410);
  if (!Number.isInteger(job.days) || job.days < 1 || job.days > 365 || !sanitizeCode(job.code)) return fail('invalid_grant');
  const key = 'promo_receipt:' + user.id + ':' + job.code;
  const receipt = await env.INSTALLS.get(key);
  if (!receipt) {
    extendEntitlement(user, 'promo', job.days);
    await putUserRecord(env, user);
    await env.INSTALLS.put(key, JSON.stringify({ days: job.days }));
  } else {
    applyEntitlements(user);
  }
  return json({ ok: true, kind: 'promotion', daysAdded: receipt ? JSON.parse(receipt).days : job.days,
    isPremium: user.isPremium, premiumExpiresAt: user.premiumExpiresAt, premiumSource: user.premiumSource });
}

async function finish(storage, env, key, job) {
  const res = await accountRpc(env, job.userId, '/_account/promo', job);
  const data = await res.json();
  if (!res.ok && res.status !== 410) return fail('referral_pending', 503);
  await storage.transaction(async txn => {
    await txn.put(key, { ...job, done: true, failed: !res.ok });
    await txn.delete('promo-pending:' + key);
  });
  return json(data, res.status);
}

export async function retryPromos(storage, env) {
  await storage.setAlarm(Date.now() + 60_000);
  const pending = await storage.list({ prefix: 'promo-pending:', limit: 25 });
  for (const key of pending.values()) {
    const job = await storage.get(key);
    if (job && !job.done) await finish(storage, env, key, job);
    else await storage.delete('promo-pending:' + key);
  }
  if (!(await storage.list({ prefix: 'promo-pending:', limit: 1 })).size) await storage.deleteAlarm();
}

export async function promoCatalog(storage, env, body) {
  await storage.put('promo-catalog', true);
  const catalog = await storage.get('catalog') || {};
  if (body.operation === 'list') return json({ codes: Object.values(catalog) });
  const code = sanitizeCode(body.code);
  if (!code) return fail('invalid_code');
  if (body.operation === 'history') {
    if (!catalog[code]) return fail('not_found', 404);
    const prefix = 'promo-claim:' + code + ':';
    if (body.cursor && (typeof body.cursor !== 'string' || !body.cursor.startsWith(prefix) || body.cursor.length > 300)) return fail('invalid_cursor');
    const rows = await storage.list({ prefix, ...(body.cursor ? { start: body.cursor } : {}), limit: 51 });
    const entries = [...rows];
    return json({ claims: entries.slice(0, 50).map(([, job]) => ({ userId: job.userId,
      days: job.days, claimedAt: job.claimedAt || null, status: job.failed ? 'failed' : job.done ? 'done' : 'pending' })),
      cursor: entries.length > 50 ? entries[50][0] : null });
  }
  if (['update', 'toggle', 'delete'].includes(body.operation)) {
    const current = catalog[code];
    if (!current || current.deletedAt) return fail('not_found', 404);
    if ((body.operation !== 'toggle' || body.revision !== undefined) && body.revision !== (current.revision || 1)) return fail('campaign_changed', 409);
    if (body.operation === 'delete' || body.operation === 'toggle') {
      if (body.operation === 'toggle' && typeof body.enabled !== 'boolean') return fail('invalid_campaign');
      current.enabled = body.operation === 'delete' ? false : body.enabled;
      if (body.operation === 'delete') current.deletedAt = new Date().toISOString();
      current.revision = (current.revision || 1) + 1;
      current.updatedAt = new Date().toISOString();
      await storage.put('catalog', catalog);
      return json({ ok: true, campaign: current });
    }
  }
  if (body.operation === 'create' || body.operation === 'update') {
    const { days, maxUses } = body;
    const startsAt = Date.parse(body.startsAt), expiresAt = Date.parse(body.expiresAt);
    if (!Number.isInteger(days) || days < 1 || days > 365 ||
        !Number.isInteger(maxUses) || maxUses < 1 || maxUses > 100000 ||
        !Number.isFinite(startsAt) || !Number.isFinite(expiresAt) || expiresAt <= startsAt ||
        (body.operation === 'create' && expiresAt <= Date.now())) return fail('invalid_campaign');
    if (body.title !== undefined && (typeof body.title !== 'string' || body.title.length > 100)) return fail('invalid_campaign');
    if (body.notes !== undefined && (typeof body.notes !== 'string' || body.notes.length > 1000)) return fail('invalid_campaign');
    if (body.operation === 'update') {
      if (maxUses < catalog[code].uses) return fail('limit_below_uses');
      catalog[code] = { ...catalog[code], days, maxUses, title: (body.title || '').trim(), notes: (body.notes || '').trim(),
        startsAt: new Date(startsAt).toISOString(), expiresAt: new Date(expiresAt).toISOString(),
        revision: (catalog[code].revision || 1) + 1, updatedAt: new Date().toISOString() };
      await storage.put('catalog', catalog);
      return json({ ok: true, campaign: catalog[code] });
    }
    if (catalog[code]) return fail('code_exists', 409);
    if (Object.keys(catalog).length >= 500) return fail('catalog_full', 409);
    const owner = await codeRpc(env, code, 'register', marker);
    if (owner !== marker) return fail('code_exists', 409);
    catalog[code] = { code, days, maxUses, startsAt: new Date(startsAt).toISOString(),
      expiresAt: new Date(expiresAt).toISOString(), enabled: true, uses: 0, revision: 1,
      title: (body.title || '').trim(), notes: (body.notes || '').trim(), createdAt: new Date().toISOString() };
    await storage.put('catalog', catalog);
    return json({ ok: true, campaign: catalog[code] });
  }
  if (body.operation !== 'claim' || typeof body.userId !== 'string') return fail('invalid_operation');
  const key = 'promo-claim:' + code + ':' + body.userId;
  const previous = await storage.get(key);
  if (previous) {
    if (previous.failed) return fail('promo_already_used');
    return finish(storage, env, key, previous);
  }
  const now = Date.now();
  const rateKey = 'promo-attempts:' + body.userId;
  const attempts = (await storage.get(rateKey) || []).filter(at => at > now - 900000);
  if (attempts.length >= 8) return json({ error: 'rate_limited' }, 429, { 'Retry-After': String(Math.ceil((attempts[0] + 900000 - now) / 1000)) });
  await storage.put(rateKey, [...attempts, now]);
  const owner = await codeRpc(env, code, 'lookup');
  if (!owner) return fail('code_not_found', 404);
  if (owner !== marker) {
    return accountRpc(env, 'referral-claim:' + body.userId, '/_referral/claim', { code, friendId: body.userId });
  }
  const campaign = catalog[code];
  if (!campaign) return fail('code_not_found', 404);
  if (campaign.deletedAt || !campaign.enabled) return fail('promo_inactive');
  if (now < Date.parse(campaign.startsAt)) return fail('promo_not_started');
  if (now >= Date.parse(campaign.expiresAt)) return fail('promo_expired');
  if (campaign.uses >= campaign.maxUses) return fail('promo_exhausted');
  const check = await accountRpc(env, body.userId, '/_account/promo', { operation: 'check' });
  if (!check.ok) return check;
  const { createdAt } = await check.json();
  const job = { code, userId: body.userId, createdAt, days: campaign.days, claimedAt: new Date(now).toISOString() };
  await storage.setAlarm(now + 60_000);
  await storage.transaction(async txn => {
    campaign.uses++;
    await txn.put('catalog', catalog);
    await txn.put(key, job);
    await txn.put('promo-pending:' + key, key);
  });
  return finish(storage, env, key, job);
}
