export async function privatePushTopic(env, userId) {
  if (!env.SESSION_SECRET || !userId) throw new Error('notification identity unavailable');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.SESSION_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode('push-account-v1:' + userId)));
  return 'pdd_account_' + [...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('');
}
