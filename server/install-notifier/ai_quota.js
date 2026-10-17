import { readSession, tokenHash } from './user_auth.js';
import { accountRead, accountStateRequired } from './account_state.js';
import { applyEntitlements } from './entitlements.js';
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
const limitNumber = (value, fallback) => Number.isSafeInteger(Number(value)) && Number(value) > 0 && Number(value) <= 100000 ? Number(value) : fallback;
export async function aiQuota(request, env, body = {}, reserve = true) {
  const session = await readSession(request, env);
  if (!session && reserve && (body.userMessage || body.messages?.length)) return { response: reply({ error: 'authentication required' }, 401) };
  let installation = body.installationId || body.installId || new URL(request.url).searchParams.get('installationId');
  const legacyAllowed = env.AI_LEGACY_EXPLANATIONS === 'true' && Date.parse(env.AI_LEGACY_UNTIL || '') > Date.now()
    && Boolean(env.SHARED_SECRET) && request.headers.get('x-install-secret') === env.SHARED_SECRET;
  if (!session && !installation && legacyAllowed) installation = (await tokenHash('legacy-ai:' + (request.headers.get('cf-connecting-ip') || 'unknown') + ':' + (request.headers.get('user-agent') || ''))).slice(0, 32);
  if (!session && (typeof installation !== 'string' || !/^[a-f0-9]{32}$/.test(installation))) return { response: reply({ error: 'installation required' }, 400) };
  let premium = false;
  if (session) {
    const raw = await accountRead(env, session.user.id, 'user:' + session.user.id);
    const user = raw ? JSON.parse(raw) : null;
    premium = Boolean(user && applyEntitlements(user).isPremium);
  }
  const limit = session ? premium ? 200 : 10 : 3;
  const id = await tokenHash(session ? 'user:' + session.user.id : 'installation:' + installation);
  const ip = await tokenHash(request.headers.get('cf-connecting-ip') || 'unknown');
  if (!env.AI_QUOTAS) {
    if (accountStateRequired(env)) return { response: reply({ error: 'AI quota storage unavailable' }, 503) };
    // Old unit fixtures without bindings must opt into an isolated allowance.
    if (!env.__AI_TEST_QUOTA) return { response: reply({ error: 'AI quota storage unavailable' }, 503) };
    return { quota: { limit, remaining: limit - (reserve ? 1 : 0), resetsAt: new Date(Date.now() + 86400000).toISOString() } };
  }
  const response = await env.AI_QUOTAS.get(env.AI_QUOTAS.idFromName('ai-budget-v1')).fetch('https://ai-quota/' + (reserve ? 'reserve' : 'status'), {
    method: 'POST', body: JSON.stringify({ id, ip, guest: !session, limit, globalLimit: limitNumber(env.AI_GLOBAL_DAILY_LIMIT, 5000), now: Date.now() }),
  });
  const quota = await response.json();
  return response.ok ? { quota } : { response: reply(quota, response.status) };
}
export class AiQuotaState {
  constructor(state) { this.state = state; }
  async fetch(request) {
    const body = await request.json();
    if (!/^[a-f0-9]{64}$/.test(body.id || '') || !/^[a-f0-9]{64}$/.test(body.ip || '')) return reply({ error: 'invalid quota identity' }, 400);
    const now = Date.now(), day = new Date(now).toISOString().slice(0, 10), minute = Math.floor(now / 60000);
    const reset = Date.parse(day) + 86400000;
    const response = await this.state.storage.transaction(async txn => {
      const accountKey = `${day}:account:${body.id}`, globalKey = `${day}:global`, ipKey = `${day}:guest-ip:${body.ip}`, rateKey = `${day}:minute:${minute}:${body.id}`;
      const used = await txn.get(accountKey) || 0, global = await txn.get(globalKey) || 0;
      const ipUsed = body.guest ? await txn.get(ipKey) || 0 : 0;
      const rate = await txn.get(rateKey) || 0;
      const limit = limitNumber(body.limit, 3), globalLimit = limitNumber(body.globalLimit, 5000);
      const quota = { ok: true, limit, remaining: Math.max(0, limit - used), resetsAt: new Date(reset).toISOString(), requiresSignInForChat: true };
      if (new URL(request.url).pathname !== '/reserve') return reply(quota);
      if (used >= limit || global >= globalLimit || (body.guest && ipUsed >= 10) || rate >= (body.guest ? 3 : 10)) {
        const retryAfterSeconds = rate >= (body.guest ? 3 : 10) ? 60 - Math.floor(now / 1000) % 60 : Math.ceil((reset - now) / 1000);
        const reason = used >= limit ? 'daily_limit' : global >= globalLimit ? 'global_limit' : body.guest && ipUsed >= 10 ? 'ip_limit' : 'rate_limit';
        return reply({ ...quota, ok: false, error: 'ai_quota_exceeded', reason, retryAfterSeconds }, 429);
      }
      await txn.put(accountKey, used + 1); await txn.put(globalKey, global + 1); await txn.put(rateKey, rate + 1);
      if (body.guest) await txn.put(ipKey, ipUsed + 1);
      return reply({ ...quota, remaining: limit - used - 1 });
    });
    if (!await this.state.storage.getAlarm?.()) await this.state.storage.setAlarm?.(reset + 60000);
    return response;
  }
  async alarm() {
    const cutoff = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    const entries = await this.state.storage.list();
    for (const key of entries.keys()) if (key.slice(0, 10) < cutoff) await this.state.storage.delete(key);
    if (entries.size) await this.state.storage.setAlarm?.(Date.parse(new Date().toISOString().slice(0, 10)) + 86400000 + 60000);
  }
}
