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
  return json({ ok: true, kind: 'promotion', daysAdded: receipt ? JSON.parse(receipt).days : job.days, alreadyApplied: Boolean(receipt),
    isPremium: user.isPremium, premiumExpiresAt: user.premiumExpiresAt, premiumSource: user.premiumSource });
}

async function finish(storage, env, key, job, serial) {
  const res = await accountRpc(env, job.userId, '/_account/promo', job);
  const data = await res.json();
  if (!res.ok && res.status !== 410) return fail('referral_pending', 503);
  await serial(() => storage.transaction(async txn => {
    const current = await txn.get(key);
    // A later replay (including after deletion) must not rewrite grant history.
    if (!current?.done) await txn.put(key, { ...job, done: true, failed: !res.ok });
    await txn.delete('promo-pending:' + key);
  }));
  return json(data, res.status);
}

// Select a fair batch under the catalog lock; run account calls outside it.
export async function retryPromos(storage, env, serial) {
  await storage.setAlarm(Date.now() + 60_000);
  const cursor = await storage.get('promo-retry-cursor');
  let pending = await storage.list({ prefix: 'promo-pending:', ...(cursor ? { start: cursor + '\0' } : {}), limit: 25 });
  if (!pending.size) pending = await storage.list({ prefix: 'promo-pending:', limit: 25 });
  if (pending.size) await storage.put('promo-retry-cursor', [...pending.keys()].at(-1));
  return async () => {
    await Promise.allSettled([...pending.values()].map(async key => {
      const job = await storage.get(key);
      if (job && !job.done) await finish(storage, env, key, job, serial);
      else await serial(() => storage.delete('promo-pending:' + key));
    }));
    await serial(async () => {
      if (!(await storage.list({ prefix: 'promo-pending:', limit: 1 })).size) {
        await storage.delete('promo-retry-cursor');
        await storage.deleteAlarm();
      }
    });
  };
}

async function archives(storage) {
  const result = [];
  let start;
  while (true) {
    const page = await storage.list({ prefix: 'promo-archive:', ...(start ? { start } : {}), limit: 500 });
    result.push(...page.values());
    if (page.size < 500) return result;
    start = [...page.keys()].at(-1) + '\0';
  }
}

export async function promoCatalog(storage, env, body, serial) {
  await storage.put('promo-catalog', true);
  const catalog = await storage.get('catalog') || {};
  const deleted = Object.values(catalog).filter(c => c.deletedAt);
  if (deleted.length) {
    await storage.transaction(async txn => {
      for (const campaign of deleted) {
        await txn.put('promo-archive:' + campaign.code, campaign);
        delete catalog[campaign.code];
      }
      await txn.put('catalog', catalog);
    });
  }
  if (body.operation === 'list') return json({ codes: [...Object.values(catalog), ...await archives(storage)] });
  const code = sanitizeCode(body.code);
  if (!code) return fail('invalid_code');
  if (body.operation === 'history') {
    if (!catalog[code] && !await storage.get('promo-archive:' + code)) return fail('not_found', 404);
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
      await storage.transaction(async txn => {
        if (current.deletedAt) {
          await txn.put('promo-archive:' + code, current);
          delete catalog[code];
        }
        await txn.put('catalog', catalog);
      });
      return json({ ok: true, campaign: current });
    }
  }
  if (body.operation === 'create' || body.operation === 'update') {
    const { days } = body;
    const optional = value => value === undefined || value === null || value === '';
    const maxUses = optional(body.maxUses) ? null : body.maxUses;
    const startsAt = optional(body.startsAt) ? null : Date.parse(body.startsAt);
    const expiresAt = optional(body.expiresAt) ? null : Date.parse(body.expiresAt);
    const startIso = startsAt === null ? null : Number.isFinite(startsAt) ? new Date(startsAt).toISOString() : null;
    const endIso = expiresAt === null ? null : Number.isFinite(expiresAt) ? new Date(expiresAt).toISOString() : null;
    if (!Number.isInteger(days) || days < 1 || days > 365 ||
        (maxUses !== null && (!Number.isInteger(maxUses) || maxUses < 1 || maxUses > 100000)) ||
        (startsAt !== null && !Number.isFinite(startsAt)) || (expiresAt !== null && !Number.isFinite(expiresAt)) ||
        (startsAt !== null && expiresAt !== null && expiresAt <= startsAt) ||
        (body.operation === 'create' && expiresAt !== null && expiresAt <= Date.now())) return fail('invalid_campaign');
    if (body.title !== undefined && (typeof body.title !== 'string' || body.title.length > 100)) return fail('invalid_campaign');
    if (body.notes !== undefined && (typeof body.notes !== 'string' || body.notes.length > 1000)) return fail('invalid_campaign');
    if (body.operation === 'update') {
      if (maxUses !== null && maxUses < catalog[code].uses) return fail('limit_below_uses');
      catalog[code] = { ...catalog[code], days, maxUses, title: (body.title || '').trim(), notes: (body.notes || '').trim(),
        startsAt: startIso, expiresAt: endIso,
        revision: (catalog[code].revision || 1) + 1, updatedAt: new Date().toISOString() };
      await storage.put('catalog', catalog);
      return json({ ok: true, campaign: catalog[code] });
    }
    if (catalog[code] || await storage.get('promo-archive:' + code)) return fail('code_exists', 409);
    if (Object.keys(catalog).length >= 500) return fail('catalog_full', 409);
    const owner = await codeRpc(env, code, 'register', marker);
    if (owner !== marker) return fail('code_exists', 409);
    catalog[code] = { code, days, maxUses, startsAt: startIso,
      expiresAt: endIso, enabled: true, uses: 0, revision: 1,
      title: (body.title || '').trim(), notes: (body.notes || '').trim(), createdAt: new Date().toISOString() };
    await storage.put('catalog', catalog);
    return json({ ok: true, campaign: catalog[code] });
  }
  if (!['claim', 'reserve'].includes(body.operation) || typeof body.userId !== 'string') return fail('invalid_operation');
  const key = 'promo-claim:' + code + ':' + body.userId;
  const previous = await storage.get(key);
  if (previous) {
    if (previous.failed) return fail('promo_already_used');
    return () => finish(storage, env, key, previous, serial);
  }
  const now = Date.now();
  if (body.operation === 'claim') {
    const rateKey = 'promo-attempts:' + body.userId;
    const attempts = (await storage.get(rateKey) || []).filter(at => at > now - 900000);
    if (attempts.length >= 8) return json({ error: 'rate_limited' }, 429, { 'Retry-After': String(Math.ceil((attempts[0] + 900000 - now) / 1000)) });
    await storage.put(rateKey, [...attempts, now]);
    const owner = await codeRpc(env, code, 'lookup');
    if (!owner) return fail('code_not_found', 404);
    if (owner !== marker) {
      return () => accountRpc(env, 'referral-claim:' + body.userId, '/_referral/claim', { code, friendId: body.userId });
    }
    return async () => {
      const check = await accountRpc(env, body.userId, '/_account/promo', { operation: 'check' });
      if (!check.ok) return check;
      const { createdAt } = await check.json();
      return rpc(env, { operation: 'reserve', userId: body.userId, code, createdAt });
    };
  }
  const campaign = catalog[code];
  if (!campaign) return await storage.get('promo-archive:' + code) ? fail('promo_inactive') : fail('code_not_found', 404);
  if (campaign.deletedAt || !campaign.enabled) return fail('promo_inactive');
  if (campaign.startsAt != null && now < Date.parse(campaign.startsAt)) return fail('promo_not_started');
  if (campaign.expiresAt != null && now >= Date.parse(campaign.expiresAt)) return fail('promo_expired');
  if (campaign.maxUses != null && campaign.uses >= campaign.maxUses) return fail('promo_exhausted');
  const { createdAt } = body;
  const job = { code, userId: body.userId, createdAt, days: campaign.days, claimedAt: new Date(now).toISOString() };
  await storage.setAlarm(now + 60_000);
  await storage.transaction(async txn => {
    campaign.uses++;
    await txn.put('catalog', catalog);
    await txn.put(key, job);
    await txn.put('promo-pending:' + key, key);
  });
  return () => finish(storage, env, key, job, serial);
}
