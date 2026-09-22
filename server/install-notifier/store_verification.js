import { SignJWT, importPKCS8, decodeJwt } from 'jose';
import { tokenHash } from './user_auth.js';

const packages = { ru: 'ru.pdd.pdd_app', by: 'by.pdd.pdd_app', rs: 'rs.pdd.pdd_app' };
const defaultProducts = {
  googleplay: ['ru.pdd.pddapp.premium.week', 'ru.pdd.pddapp.premium.3months'],
  appstore: ['u.pdd.pddApp.premium.week', 'ru.pdd.pddApp.sub.3months'],
};
const activeStates = new Set(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED']);
export class StoreError extends Error {
  constructor(code, status = 503) { super(code); this.status = status; }
}
async function fetchJson(url, options = {}) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(10000) });
  if (!response.ok) throw new StoreError('store verification unavailable', response.status === 404 || response.status === 410 ? 422 : 503);
  return response.json();
}
let googleAccess;
async function googleAccessToken(env) {
  if (!env.GOOGLE_PLAY_SERVICE_ACCOUNT) throw new StoreError('store verification not configured');
  const account = JSON.parse(env.GOOGLE_PLAY_SERVICE_ACCOUNT);
  if (googleAccess?.email === account.client_email && googleAccess.expires > Date.now()) return googleAccess.token;
  const key = await importPKCS8(account.private_key, 'RS256');
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(account.client_email)
    .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);
  const data = await fetchJson('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!data.access_token) throw new StoreError('store verification unavailable');
  googleAccess = { email: account.client_email, token: data.access_token, expires: Date.now() + Math.min(Number(data.expires_in) || 300, 3300) * 1000 };
  return data.access_token;
}

export function googleEntitlement(data, productId, now = Date.now()) {
  const item = data.lineItems?.filter(i => i.productId === productId)
    .sort((a, b) => Date.parse(b.expiryTime) - Date.parse(a.expiryTime))[0];
  if (!item || !Number.isFinite(Date.parse(item.expiryTime))) throw new StoreError('wrong product', 422);
  const active = activeStates.has(data.subscriptionState) && Date.parse(item.expiryTime) > now;
  return { active, expiresAt: new Date(item.expiryTime).toISOString(), orderId: data.latestOrderId || null };
}

export async function verifyStorePurchase(body, env, userId) {
  const { store, productId, country } = body || {};
  if (!packages[country] || !defaultProducts[store]) throw new StoreError('invalid store', 400);
  const products = env[store === 'googleplay' ? 'GOOGLE_PLAY_PRODUCT_IDS' : 'APPLE_PRODUCT_IDS'];
  const allowed = products ? String(products).split(',').map(s => s.trim()) : defaultProducts[store];
  if (!allowed.includes(productId)) throw new StoreError('unknown product', 422);
  if (store === 'googleplay') {
    const token = body.purchaseToken;
    if (typeof token !== 'string' || !token || token.length > 8192) throw new StoreError('missing purchase token', 400);
    const access = await googleAccessToken(env);
    const data = await fetchJson(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packages[country]}/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`, {
      headers: { Authorization: `Bearer ${access}` },
    });
    const account = data.externalAccountIdentifiers?.obfuscatedExternalAccountId;
    if (account && account !== await tokenHash(userId)) throw new StoreError('purchase belongs to another account', 403);
    return { ...googleEntitlement(data, productId), key: `googleplay:${country}:${await tokenHash(token)}`,
      reference: { store, country, productId, purchaseToken: token } };
  }
  if (!env.APPLE_IAP_PRIVATE_KEY || !env.APPLE_IAP_KEY_ID || !env.APPLE_IAP_ISSUER_ID) throw new StoreError('store verification not configured');
  const transactionId = body.transactionId;
  if (typeof transactionId !== 'string' || !/^\d{1,40}$/.test(transactionId)) throw new StoreError('invalid transaction', 400);
  const bundleId = env.APPLE_IAP_BUNDLE_ID || 'ru.pdd.pddApp';
  const key = await importPKCS8(env.APPLE_IAP_PRIVATE_KEY, 'ES256');
  const token = await new SignJWT({ bid: bundleId }).setProtectedHeader({ alg: 'ES256', kid: env.APPLE_IAP_KEY_ID, typ: 'JWT' })
    .setIssuer(env.APPLE_IAP_ISSUER_ID).setAudience('appstoreconnect-v1').setIssuedAt().setExpirationTime('5m').sign(key);
  // Sandbox is opt-in on the server; a client cannot select it in production.
  const sandbox = env.APPLE_IAP_ENVIRONMENT === 'sandbox';
  const host = sandbox ? 'api.storekit-sandbox.apple.com' : 'api.storekit.apple.com';
  const response = await fetchJson(`https://${host}/inApps/v1/transactions/${transactionId}`, { headers: { Authorization: `Bearer ${token}` } });
  // This JWS comes directly from Apple's authenticated HTTPS API, never the client.
  const data = decodeJwt(response.signedTransactionInfo);
  if (data.bundleId !== bundleId || data.productId !== productId || String(data.transactionId) !== transactionId ||
      data.environment !== (sandbox ? 'Sandbox' : 'Production') || !Number.isFinite(data.expiresDate)) throw new StoreError('wrong transaction', 422);
  return { active: !data.revocationDate && data.expiresDate > Date.now(), expiresAt: new Date(data.expiresDate).toISOString(),
    orderId: transactionId, key: `appstore:${data.originalTransactionId}`,
    reference: { store, country, productId, transactionId } };
}

export async function claimPurchase(env, userId, verified) {
  if (!env.PURCHASE_CLAIMS) throw new StoreError('purchase ownership not configured');
  const stub = env.PURCHASE_CLAIMS.get(env.PURCHASE_CLAIMS.idFromName(verified.key));
  const response = await stub.fetch('https://purchase-claims/claim', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ userId }),
  });
  if (response.status === 403) throw new StoreError('purchase belongs to another account', 403);
  if (!response.ok) throw new StoreError('purchase ownership unavailable');
}

export async function refreshStoreEntitlement(env, user) {
  if (!user?.verifiedPurchase || Date.now() - (user.storeVerifiedAt || 0) < 300000) return user;
  try {
    const verified = await verifyStorePurchase(user.verifiedPurchase, env, user.id);
    // Preserve an independent administrative grant.
    if (user.premiumSource !== user.verifiedPurchase.store) return user;
    user.isPremium = verified.active;
    user.premiumExpiresAt = verified.expiresAt;
    user.storeVerifiedAt = Date.now();
    await env.INSTALLS.put('user:' + user.id, JSON.stringify(user));
  } catch (error) {
    // A network/configuration failure never creates or extends an entitlement.
    if (error instanceof StoreError && error.status === 422) {
      user.isPremium = false;
      user.storeVerifiedAt = Date.now();
      await env.INSTALLS.put('user:' + user.id, JSON.stringify(user));
    }
  }
  return user;
}
