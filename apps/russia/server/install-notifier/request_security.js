// Shared HTTP bounds and an atomic abuse budget. No IPs or credentials are logged.
export class HttpFailure extends Error {
  constructor(status, error, headers = {}) { super(error); this.status = status; this.headers = headers; }
  response() { return Response.json({ error: this.message }, { status: this.status, headers: { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', ...this.headers } }); }
}
export async function boundedJson(request, maxBytes = 65536) {
  if (Number(request.headers.get('content-length')) > maxBytes) throw new HttpFailure(413, 'request too large');
  const reader = request.body?.getReader();
  if (!reader) throw new HttpFailure(400, 'invalid json');
  const parts = []; let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maxBytes) { await reader.cancel(); throw new HttpFailure(413, 'request too large'); }
    parts.push(value);
  }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.length; }
  try {
    const body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body;
  } catch { throw new HttpFailure(400, 'invalid json'); }
}
export async function digest(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(b => b.toString(16).padStart(2, '0')).join('');
}
export function equal(a, b) {
  const x = new TextEncoder().encode(String(a || '')), y = new TextEncoder().encode(String(b || ''));
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] || 0) ^ (y[i] || 0);
  return diff === 0 && x.length > 0;
}
const fixtures = new WeakMap();
async function securityCall(env, body) {
  if (env.SECURITY) {
    const response = await env.SECURITY.get(env.SECURITY.idFromName('request-security-v1')).fetch('https://security.internal/check', { method: 'POST', body: JSON.stringify(body) });
    if (response.status === 429) throw new HttpFailure(429, 'too many attempts', { 'Retry-After': response.headers.get('retry-after') || '60' });
    if (!response.ok) throw new HttpFailure(503, 'security service unavailable');
    return response.json();
  }
  // Production must never use an isolate-local limiter. Only old isolated test
  // environments (without the required AccountState flag) use this fixture.
  if (env.ACCOUNT_STATE_REQUIRED === 'true') throw new HttpFailure(503, 'security service unavailable');
  if (!fixtures.has(env)) {
    const data = new Map();
    const storage = { get: async k => data.get(k), put: async (k, v) => data.set(k, v), delete: async k => data.delete(k), setAlarm: async () => {} };
    storage.transaction = fn => fn(storage);
    fixtures.set(env, new SecurityState({ storage }, env));
  }
  const response = await fixtures.get(env).fetch(new Request('https://security.internal/check', { method: 'POST', body: JSON.stringify(body) }));
  if (response.status === 429) throw new HttpFailure(429, 'too many attempts', { 'Retry-After': response.headers.get('retry-after') || '60' });
  return response.json();
}
export async function abuseBudget(request, env, scope, { limit = 10, windowMs = 600000, globalLimit = 300, identity } = {}) {
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  const key = await digest((env.SESSION_SECRET || '') + ':' + scope + ':' + (identity || ip));
  await securityCall(env, { op: 'budget', scope, key, limit, globalLimit, windowMs });
}
export async function checkAdminCredential(request, env, credential) {
  const key = await digest((env.SESSION_SECRET || '') + ':admin:' + (request.headers.get('cf-connecting-ip') || 'unknown'));
  return (await securityCall(env, { op: 'admin', key, credential })).ok === true;
}
export class SecurityState {
  constructor(state, env) { this.state = state; this.env = env; this.queue = Promise.resolve(); }
  fetch(request) {
    const next = this.queue.then(() => this.check(request));
    this.queue = next.catch(() => {}); return next;
  }
  async check(request) {
    const body = await boundedJson(request, 8192), now = Date.now();
    if (!/^[a-f0-9]{64}$/.test(body.key || '')) return new Response(null, { status: 400 });
    const admin = body.op === 'admin';
    if (!admin && (body.op !== 'budget' || !/^[a-z-]{1,32}$/.test(body.scope || ''))) return new Response(null, { status: 400 });
    const windowMs = admin ? 900000 : Math.max(1000, Math.min(Number(body.windowMs) || 600000, 86400000));
    const limit = admin ? 8 : Math.max(1, Math.min(Number(body.limit) || 10, 10000));
    const globalLimit = admin ? 500 : Math.max(limit, Math.min(Number(body.globalLimit) || 300, 100000));
    const scope = admin ? 'admin' : body.scope, bucket = Math.floor(now / windowMs);
    const expiresAt = (bucket + 1) * windowMs;
    const keys = [scope + ':' + bucket + ':' + body.key, scope + ':' + bucket + ':global'];
    const alarm = await this.state.storage.getAlarm?.();
    if (!alarm || alarm > expiresAt) await this.state.storage.setAlarm(expiresAt);
    return this.state.storage.transaction(async txn => {
      const local = await txn.get(keys[0]), global = await txn.get(keys[1]);
      if ((local?.count || 0) >= limit || (global?.count || 0) >= globalLimit) return Response.json({ error: 'too many attempts' }, { status: 429, headers: { 'Retry-After': String(Math.max(1, Math.ceil((expiresAt - now) / 1000))) } });
      if (admin && this.env.ADMIN_PASSWORD && equal(body.credential, this.env.ADMIN_PASSWORD)) {
        await txn.delete(keys[0]); return Response.json({ ok: true });
      }
      for (const [key, record] of [[keys[0], local], [keys[1], global]]) await txn.put(key, { count: (record?.count || 0) + 1, expiresAt });
      return Response.json({ ok: !admin });
    });
  }
  alarm() {
    const next = this.queue.then(() => this.prune());
    this.queue = next.catch(() => {}); return next;
  }
  async prune() {
    const records = await this.state.storage.list(), now = Date.now(); let next = Infinity;
    for (const [key, value] of records) {
      if (value.expiresAt <= now) await this.state.storage.delete(key);
      else next = Math.min(next, value.expiresAt);
    }
    if (Number.isFinite(next)) await this.state.storage.setAlarm(next);
  }
}
