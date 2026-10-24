// The account Durable Object is the authority for profile, progress, purchase
// ledger and deletion/session generation. KV is a retryable read projection.
// Every existing account writer runs inside one globally addressed DO request;
// all local documents commit in one storage transaction after the handler ends.
import { durableRequest } from './durable_request.js';
const ACCOUNT_PREFIXES = ['user:', 'user_progress:', 'user_admin:', 'pay_intent:', 'auth_generation:', 'account_deleted:', 'apple_auth:'];
const scoped = (key, id) => ACCOUNT_PREFIXES.some(prefix => key === prefix + id) || key.startsWith('pay_order:') || key.startsWith('payment_ledger:') || key.startsWith('pay_tx:') || key.startsWith('notified_purch:') || key.startsWith('revoked_session:' + id + ':');
const json = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
const parse = raw => { try { return raw ? JSON.parse(raw) : null; } catch { return null; } };
const noProjection = key => key.startsWith('apple_auth:');
const MAINTENANCE_PAGE = 25;
// After a rollback to the KV-only Worker, KV holds newer writes than this DO.
// Raising ACCOUNT_STATE_EPOCH makes older projected documents re-import from KV
// instead of overwriting it. Private DO-only documents keep their value.
const accountEpoch = env => String(env.ACCOUNT_STATE_EPOCH || '1');
const stale = (env, record) => Boolean(record) && !noProjection(record.key) && String(record.epoch || '1') !== accountEpoch(env);

export function accountStateRequired(env) { return env.ACCOUNT_STATE_REQUIRED === 'true'; }
export async function accountRpc(env, id, path, body) {
  if (!env.ACCOUNTS) {
    if (accountStateRequired(env)) throw new Error('account storage not configured');
    return null; // Isolated pre-migration fixtures only; production requires it.
  }
  const retryableRead = ['/_account/read', '/_account/read-many', '/_directory/find'].includes(path);
  return durableRequest(env.ACCOUNTS, env.ACCOUNTS.idFromName(id), stub => stub.fetch('https://account.internal' + path, {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-account-id': id }, body: JSON.stringify(body || {}),
  }), { retryableRead });
}
export async function accountRead(env, id, key) {
  if (env.__ACCOUNT_ID === id || !env.ACCOUNTS) return env.INSTALLS?.get(key);
  const response = await accountRpc(env, id, '/_account/read', { key });
  if (!response?.ok) throw new Error('account storage unavailable');
  return (await response.json()).value;
}
// Session generation and individual revocation must be checked together, with
// no cache window in which a logged-out or deleted account keeps access.
export async function accountReadMany(env, id, keys) {
  if (env.__ACCOUNT_ID === id || !env.ACCOUNTS) return Promise.all(keys.map(key => env.INSTALLS?.get(key)));
  const response = await accountRpc(env, id, '/_account/read-many', { keys });
  const body = response?.ok ? await response.json() : null;
  if (Array.isArray(body?.values) && body.values.length === keys.length
      && body.values.every(value => value === null || typeof value === 'string')) return body.values;
  // During a deployment, a new Worker may reach an older AccountState. The
  // old HTTP router either returns 404 or treats this private POST as an ignored
  // installation. Fall back only for those explicit legacy responses; malformed
  // data and storage failures must never authorize a session as "not revoked".
  if (response?.status === 404 || (body?.ok === true && body.ignored === true
      && body.reason === 'not-a-store-install')) return Promise.all(keys.map(key => accountRead(env, id, key)));
  throw new Error('account storage unavailable');
}
export async function accountWrite(env, id, key, value, options = {}) {
  if (env.__ACCOUNT_ID === id || !env.ACCOUNTS) return value == null ? env.INSTALLS.delete(key) : env.INSTALLS.put(key, value, options);
  const response = await accountRpc(env, id, '/_account/write', { key, value, options });
  if (!response?.ok) throw new Error('account storage unavailable');
}
export async function paymentOwner(env, orderId, txId) {
  if (env.ACCOUNTS) {
    const response = await accountRpc(env, 'payment-directory', '/_directory/find', { orderId, txId });
    if (!response.ok) throw new Error('payment directory unavailable');
    const owner = (await response.json()).userId;
    if (owner) return owner;
  }
  if (!env.INSTALLS) return null;
  const id = orderId || (txId ? await env.INSTALLS.get('pay_tx:' + txId) : null);
  return parse(id ? await env.INSTALLS.get('pay_order:' + id) : null)?.userId || null;
}
export async function routeAccountRequest(request, env, { sessionAccountId, verifyAdminAuth }) {
  if (env.__ACCOUNT_ID || !env.ACCOUNTS) {
    if (!env.__ACCOUNT_ID && accountStateRequired(env) && !env.ACCOUNTS) return json({ error: 'account storage unavailable' }, 503);
    return null;
  }
  const url = new URL(request.url), path = url.pathname;
  let id = null, callbackOrder = null;
  if (path.startsWith('/api/user/')) id = await sessionAccountId(request, env);
  else if (path.startsWith('/api/admin/users/') && await verifyAdminAuth(request, env)) {
    id = String((request.method === 'GET' ? url.searchParams.get('id') : (await request.clone().json().catch(() => null))?.userId) || '').trim();
  } else if (path === '/api/pay/platega/callback' && request.method === 'POST') {
    // Do not allocate account objects or reveal a payment index to strangers.
    if (!env.PLATEGA_SECRET || request.headers.get('x-secret') !== env.PLATEGA_SECRET || request.headers.get('x-merchantid') !== env.PLATEGA_MERCHANT_ID) return null;
    const body = await request.clone().json().catch(() => null);
    callbackOrder = body?.payload;
    id = await paymentOwner(env, callbackOrder, body?.id);
    if (!id && typeof body?.id === 'string' && body.id.length <= 128) {
      const { readPaymentTransaction } = await import('./payments.js');
      let tx; try { tx = await readPaymentTransaction(env, body.id); }
      catch { return json({ error: 'payment index not ready' }, 503); }
      callbackOrder = typeof tx.payload === 'string' ? tx.payload : null;
      id = await paymentOwner(env, callbackOrder, body.id);
    }
    if (!id) return json({ error: 'payment index not ready' }, 503);
  }
  if (!id) return null;
  if (typeof id !== 'string' || id.length > 220) return json({ error: 'invalid account' }, 400);
  const headers = new Headers(request.headers); headers.set('x-account-id', id);
  headers.delete('x-account-order'); if (callbackOrder) headers.set('x-account-order', callbackOrder);
  // Reads may recover from a reset. A write can already have committed before
  // its response is lost, so never repeat it without a request-id contract.
  const retryableRead = request.method === 'GET' && ['/api/user/status', '/api/user/progress',
    '/api/user/store/status', '/api/user/store/account-token'].includes(path);
  return durableRequest(env.ACCOUNTS, env.ACCOUNTS.idFromName(id),
    stub => stub.fetch(new Request(request, { headers })), { retryableRead });
}

export class AccountState {
  constructor(state, env) { this.state = state; this.env = env; this.tail = Promise.resolve(); }
  // Keep only completion in the long-lived queue, never the last profile or
  // progress Response. The caller still receives the original result/error.
  serial(fn) { const result = this.tail.then(fn); this.tail = result.then(() => {}, () => {}); return result; }
  fetch(request) { return this.serial(() => this.handle(request)); }
  alarm() { return this.serial(async () => { await this.expireRecords(); await this.flush(); }); }
  async scheduleExpiry(at) {
    const current = await this.state.storage.getAlarm?.();
    if (!current || current <= Date.now() || at < current) await this.state.storage.setAlarm(at);
  }
  async expireRecords() {
    let next = Infinity;
    let start;
    for (;;) {
      const records = await this.state.storage.list({ prefix: 'doc:', limit: MAINTENANCE_PAGE, ...(start ? { start } : {}) });
      for (const record of records.values()) if (record.expiresAt && !stale(this.env, record)) {
        if (record.expiresAt <= Date.now()) {
          await this.state.storage.transaction(async txn => {
            await this.persistRecord(txn, { key: record.key, value: null, options: {} });
            if (!noProjection(record.key)) await txn.put('projection:' + record.key, { key: record.key });
          });
        } else next = Math.min(next, record.expiresAt);
      }
      if (records.size < MAINTENANCE_PAGE) break;
      start = [...records.keys()].at(-1) + '\u0000';
    }
    if (Number.isFinite(next)) await this.scheduleExpiry(next);
  }
  async loadRecord(key) {
    const record = await this.state.storage.get('doc:' + key);
    if (!record?.chunks) return record;
    const parts = []; let size = 0;
    for (let i = 0; i < record.chunks; i++) {
      const encoded = await this.state.storage.get('chunk:' + key + ':' + i);
      if (typeof encoded !== 'string') throw new Error('account document incomplete');
      const bytes = Uint8Array.from(atob(encoded), char => char.charCodeAt(0)); parts.push(bytes); size += bytes.length;
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    return { key, value: new TextDecoder().decode(bytes), options: record.options || {}, expiresAt: record.expiresAt, epoch: record.epoch };
  }
  async persistRecord(txn, record) {
    record = { ...record, epoch: accountEpoch(this.env) };
    const previous = await txn.get('doc:' + record.key);
    const bytes = record.value == null ? null : new TextEncoder().encode(record.value);
    let chunks = 0;
    if (bytes && bytes.length > 60000) {
      chunks = Math.ceil(bytes.length / 49152);
      for (let i = 0; i < chunks; i++) {
        const part = bytes.subarray(i * 49152, (i + 1) * 49152);
        await txn.put('chunk:' + record.key + ':' + i, btoa(String.fromCharCode(...part)));
      }
      await txn.put('doc:' + record.key, { key: record.key, chunks, options: record.options, expiresAt: record.expiresAt, epoch: record.epoch });
    } else await txn.put('doc:' + record.key, record);
    for (let i = chunks; i < (previous?.chunks || 0); i++) await txn.delete('chunk:' + record.key + ':' + i);
  }
  async flush() {
    const indexes = await this.state.storage.list({ prefix: 'index:', limit: MAINTENANCE_PAGE });
    for (const [key, order] of indexes) {
      try {
        const response = await accountRpc(this.env, 'payment-directory', '/_directory/register', order);
        if (!response?.ok) throw new Error('payment directory unavailable');
        await this.state.storage.delete(key);
      } catch { await this.state.storage.setAlarm(Date.now() + 65000); return; }
    }
    if (indexes.size === MAINTENANCE_PAGE) await this.scheduleExpiry(Date.now() + 65000);
    const outbox = await this.state.storage.list({ prefix: 'effect:', limit: 25 });
    let retryEffects = false;
    for (const [key, effect] of outbox) {
      try {
        const { executeAccountEffect } = await import('./worker.js');
        await executeAccountEffect(effect, this.env);
        await this.state.storage.delete(key);
      } catch { retryEffects = true; }
    }
    if (retryEffects || outbox.size === 25) await this.scheduleExpiry(Date.now() + 65000);
    const pending = await this.state.storage.list({ prefix: 'projection:', limit: MAINTENANCE_PAGE });
    for (const [key, pendingRecord] of pending) {
      try {
        const record = await this.loadRecord(pendingRecord.key);
        if (!record || stale(this.env, record)) { await this.state.storage.delete(key); continue; }
        if (record.value == null) await this.env.INSTALLS.delete(record.key);
        else await this.env.INSTALLS.put(record.key, record.value, record.options);
        await this.state.storage.delete(key);
      } catch { await this.state.storage.setAlarm(Date.now() + 65000); return; }
    }
    if (pending.size === MAINTENANCE_PAGE) await this.scheduleExpiry(Date.now() + 65000);
  }
  async handle(request) {
    const path = new URL(request.url).pathname;
    if (path.startsWith('/_directory/')) return this.directory(request, path);
    const id = request.headers.get('x-account-id');
    if (!id || id.length > 220) return json({ error: 'invalid account' }, 400);
    const owner = await this.state.storage.get('account-id');
    if (owner && owner !== id) return json({ error: 'wrong account' }, 403);
    if (!owner) await this.state.storage.put('account-id', id);
    const writes = new Map(), effects = [], durableEffects = [];
    const get = async (key, options) => {
      if (!scoped(key, id)) return this.env.INSTALLS.get(key, options);
      let record = writes.get(key) || await this.loadRecord(key);
      if (!writes.has(key) && stale(this.env, record)) record = null;
      if (!record) {
        let value = null;
        if (!noProjection(key)) value = await this.env.INSTALLS.get(key);
        record = { key, value, options: {} };
        await this.state.storage.transaction(txn => this.persistRecord(txn, record));
      }
      if (record.expiresAt && record.expiresAt <= Date.now()) return null;
      return options === 'json' || options?.type === 'json' ? parse(record.value) : record.value;
    };
    const put = async (key, value, options = {}) => {
      if (!scoped(key, id)) return this.env.INSTALLS.put(key, value, options);
      const expiresAt = options.expiration ? options.expiration * 1000 : options.expirationTtl ? Date.now() + options.expirationTtl * 1000 : undefined;
      writes.set(key, { key, value: String(value), options, expiresAt });
    };
    const del = async key => {
      if (!scoped(key, id)) return this.env.INSTALLS.delete(key);
      writes.set(key, { key, value: null, options: {} });
    };
    const installs = new Proxy(this.env.INSTALLS, { get: (target, key) => key === 'get' ? get : key === 'put' ? put : key === 'delete' ? del : typeof target[key] === 'function' ? target[key].bind(target) : target[key] });
    const commit = async () => {
      // Persist recovery before the primary commit. A process death immediately
      // after commit must not strand a quiet account's outbox without an alarm.
      // A failed transaction can leave a harmless no-op alarm behind.
      if (writes.size || durableEffects.length) await this.scheduleExpiry(Date.now() + 65000);
      await this.state.storage.transaction(async txn => {
        for (const record of writes.values()) {
          await this.persistRecord(txn, record);
          if (!noProjection(record.key)) await txn.put('projection:' + record.key, { key: record.key });
          if (record.key.startsWith('pay_order:') && record.value) await txn.put('index:' + record.key, parse(record.value));
        }
        for (const effect of durableEffects) await txn.put('effect:' + crypto.randomUUID(), effect);
      });
      durableEffects.length = 0;
      for (const record of writes.values()) if (record.expiresAt) await this.scheduleExpiry(record.expiresAt);
      writes.clear();
    };
    const checkpoint = async () => {
      await commit(); await this.flush();
      if ((await this.state.storage.list({ prefix: 'index:', limit: 1 })).size) throw new Error('payment directory unavailable');
    };
    const env = { ...this.env, INSTALLS: installs, __ACCOUNT_ID: id, __AFTER_ACCOUNT_COMMIT: effects, __DURABLE_EFFECTS: durableEffects, __ACCOUNT_CHECKPOINT: checkpoint };
    let response;
    if (path === '/_account/read-many') {
      const { keys } = await request.json();
      if (!Array.isArray(keys) || !keys.length || keys.length > 8
          || keys.some(key => typeof key !== 'string' || !scoped(key, id))) return json({ error: 'invalid keys' }, 400);
      response = json({ values: await Promise.all(keys.map(key => get(key))) });
    } else if (path === '/_account/read' || path === '/_account/write') {
      const body = await request.json();
      if (!scoped(body.key || '', id)) return json({ error: 'invalid key' }, 400);
      if (path.endsWith('/write')) { if (body.value == null) await del(body.key); else await put(body.key, body.value, body.options || {}); }
      response = json({ ok: true, value: await get(body.key) });
    } else if (path === '/_account/apple-retain') {
      const { user, body } = await request.json();
      if (user?.id !== id) return json({ error: 'wrong account' }, 403);
      const { retainAppleAuthorization } = await import('./apple_account.js');
      await retainAppleAuthorization(env, user, body);
      response = json({ ok: true });
    } else if (path === '/_account/metadata') {
      const user = parse(await get('user:' + id));
      if (user) {
        const { userSummary } = await import('./user_store.js');
        await put('user:' + id, JSON.stringify(user), { metadata: userSummary(user) });
      }
      response = json({ ok: true });
    } else {
      const handlers = await import('./worker.js');
      response = path === '/_account/reconcile' || path === '/_account/refresh' || path === '/_account/iap-event'
        ? await handlers.handleAccountMaintenance(path, request, env)
        : await handlers.handleAccountHttp(request, env);
    }
    if (response.status < 500) {
      await commit();
      // The durable index outbox also retries failures after a restart.
      for (const effect of effects) { try { await effect(); } catch { console.error('Committed account effect deferred'); } }
      await this.flush();
      if ((await this.state.storage.list({ prefix: 'projection:', limit: 1 })).size) await this.state.storage.setAlarm(Date.now() + 65000);
    }
    return response;
  }
  async directory(request, path) {
    const body = await request.json();
    if (path === '/_directory/register') {
      if (!body.orderId || !body.userId) return json({ error: 'invalid order' }, 400);
      await this.state.storage.transaction(async txn => {
        const old = await txn.get('order:' + body.orderId);
        if (old && old.userId !== body.userId) throw new Error('payment ownership conflict');
        await txn.put('order:' + body.orderId, { userId: body.userId, orderId: body.orderId, status: body.status, createdAt: body.createdAt });
        if (body.txId) await txn.put('tx:' + body.txId, body.userId);
      });
      return json({ ok: true });
    }
    if (path === '/_directory/find') {
      const order = body.orderId ? await this.state.storage.get('order:' + body.orderId) : null;
      return json({ userId: order?.userId || (body.txId ? await this.state.storage.get('tx:' + body.txId) : null) || null });
    }
    return json({ error: 'not found' }, 404);
  }
}
