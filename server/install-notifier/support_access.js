import { readSession } from './user_auth.js';
import { digest, equal, HttpFailure } from './request_security.js';

// An identifier is never an account credential. Guest IDs are cryptographically
// bound to a separate 256-bit secret kept only on the originating client.
export async function supportIdentity(request, env, clientId) {
  if (typeof clientId !== 'string' || clientId.length > 220 || !clientId) throw new HttpFailure(400, 'invalid client id');
  const session = await readSession(request, env);
  if (session) {
    if (session.user.id !== clientId) throw new HttpFailure(403, 'wrong account');
    return { clientId, session };
  }
  const secret = request.headers.get('x-support-secret') || '';
  if (!/^[a-f0-9]{64}$/.test(secret) || !/^guest_v2_[a-f0-9]{64}$/.test(clientId) || !equal(clientId.slice(9), await digest(secret))) throw new HttpFailure(401, 'support authentication required');
  return { clientId, session: null };
}
export function supportImageUrl(imageUrl, clientId) {
  if (!imageUrl) return imageUrl;
  const url = new URL(imageUrl, 'https://support.internal');
  if (url.pathname !== '/api/support/file') return null;
  url.searchParams.set('clientId', clientId);
  return url.pathname + url.search;
}
export async function purgeSupport(env, clientId, deletedAt = Date.now()) {
  if (env.RANKED_RUNS) {
    const key = await digest('ranked-v1:' + clientId);
    const r = await env.RANKED_RUNS.get(env.RANKED_RUNS.idFromName(key)).fetch('https://ranking/delete', { method: 'POST', body: JSON.stringify({ before: deletedAt }) });
    if (!r.ok) throw new Error('ranked game deletion unavailable');
  }
  if (env.SUPPORT) {
    const r = await env.SUPPORT.get(env.SUPPORT.idFromName(clientId)).fetch('https://support.internal/delete', { method: 'POST', body: JSON.stringify({ before: deletedAt }) });
    if (!r.ok) throw new Error('support deletion unavailable');
  }
  if (!env.INSTALLS) return;
  const raw = await env.INSTALLS.get('support:client:' + clientId);
  let client; try { client = JSON.parse(raw); } catch {}
  if (!client || (client.createdAt || 0) <= deletedAt) {
    if (client?.threadId) await env.INSTALLS.delete('support:thread:' + client.threadId);
    await env.INSTALLS.delete('support:client:' + clientId);
  }
  await env.INSTALLS.delete('support:messages:' + clientId);
}
