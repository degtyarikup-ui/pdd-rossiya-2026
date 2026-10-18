import { SignJWT, importPKCS8, decodeJwt } from 'jose';
import { accountRead, accountWrite, accountRpc } from './account_state.js';
export const APPLE_MANAGE_URL = 'https://account.apple.com/account/manage';
export function appleAuthConfigured(env) { return Boolean(env.APPLE_AUTH_PRIVATE_KEY && env.APPLE_AUTH_KEY_ID && env.APPLE_AUTH_TEAM_ID); }
async function clientSecret(env, clientId) {
  const key = await importPKCS8(env.APPLE_AUTH_PRIVATE_KEY, 'ES256');
  return new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: env.APPLE_AUTH_KEY_ID }).setIssuer(env.APPLE_AUTH_TEAM_ID)
    .setSubject(clientId).setAudience('https://appleid.apple.com').setIssuedAt().setExpirationTime('5m').sign(key);
}
// Called only after the identity token's signature, issuer and audience were
// verified. Never log provider payloads, credentials or authorization codes.
export async function retainAppleAuthorization(env, user, body) {
  if (user.provider !== 'apple' || !body.authorizationCode || !appleAuthConfigured(env)) return;
  if (env.ACCOUNTS && env.__ACCOUNT_ID !== user.id) {
    const response = await accountRpc(env, user.id, '/_account/apple-retain', { user, body });
    if (!response?.ok) throw new Error('Apple authorization unavailable');
    return;
  }
  if (typeof body.authorizationCode !== 'string' || body.authorizationCode.length > 2048) throw new Error('invalid authorization code');
  const identity = decodeJwt(body.credential);
  const clientId = Array.isArray(identity.aud) ? identity.aud[0] : identity.aud;
  if (typeof clientId !== 'string') throw new Error('invalid Apple audience');
  const codeHash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(body.authorizationCode)))].map(b => b.toString(16).padStart(2, '0')).join('');
  const existing = JSON.parse(await accountRead(env, user.id, 'apple_auth:' + user.id) || 'null');
  if (existing?.codeHash === codeHash && existing.clientId === clientId) return;
  const response = await fetch('https://appleid.apple.com/auth/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, signal: AbortSignal.timeout(7000),
    body: new URLSearchParams({ grant_type: 'authorization_code', code: body.authorizationCode, client_id: clientId, client_secret: await clientSecret(env, clientId) }),
  });
  const data = await response.json().catch(() => null);
  if (!response.ok || typeof data?.refresh_token !== 'string' || data.refresh_token.length > 8192) throw new Error('Apple authorization unavailable');
  if (data.id_token) {
    const issued = decodeJwt(data.id_token);
    if ('apple_' + issued.sub !== user.id || issued.aud !== clientId) throw new Error('Apple authorization mismatch');
  }
  // Private DO-only document: never projected to KV/admin/user responses.
  await accountWrite(env, user.id, 'apple_auth:' + user.id, JSON.stringify({ clientId, codeHash, refreshToken: data.refresh_token, savedAt: Date.now() }));
}
// Called by the private account outbox too. Throws to retain the durable job;
// it never logs the token or sends it through a public/KV document.
export async function executeAppleRevocation(env, authorization) {
  if (!appleAuthConfigured(env)) throw new Error('Apple revocation unavailable');
  const response = await fetch('https://appleid.apple.com/auth/revoke', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, signal: AbortSignal.timeout(7000),
    body: new URLSearchParams({ token: authorization.refreshToken, token_type_hint: 'refresh_token', client_id: authorization.clientId, client_secret: await clientSecret(env, authorization.clientId) }),
  });
  if (!response.ok) throw new Error('Apple revocation unavailable');
}
export async function revokeAppleAuthorization(env, userId) {
  const raw = await accountRead(env, userId, 'apple_auth:' + userId);
  const stored = raw ? JSON.parse(raw) : null;
  if (!stored?.refreshToken || !appleAuthConfigured(env)) return { appleRevocation: 'manual_required', appleManageUrl: APPLE_MANAGE_URL };
  try {
    await executeAppleRevocation(env, stored);
    return { appleRevocation: 'revoked' };
  } catch {
    if (env.__DURABLE_EFFECTS) {
      env.__DURABLE_EFFECTS.push({ kind: 'apple-revoke', authorization: { clientId: stored.clientId, refreshToken: stored.refreshToken } });
      return { appleRevocation: 'pending' };
    }
    return { appleRevocation: 'manual_required', appleManageUrl: APPLE_MANAGE_URL };
  } finally { await accountWrite(env, userId, 'apple_auth:' + userId, null); }
}
export async function deleteAccountDocuments(env, userId) {
  const raw = await env.INSTALLS.get('user:' + userId);
  const user = raw ? JSON.parse(raw) : null;
  const apple = user?.provider === 'apple' || userId.startsWith('apple_') ? await revokeAppleAuthorization(env, userId) : {};
  await env.INSTALLS.put('account_deleted:' + userId, JSON.stringify({ at: Date.now() }));
  for (const prefix of ['user:', 'user_progress:', 'user_admin:', 'pay_intent:', 'apple_auth:']) await env.INSTALLS.delete(prefix + userId);
  if (user?.email) await env.INSTALLS.delete('user_email:' + user.email.toLowerCase().trim());
  return apple;
}
