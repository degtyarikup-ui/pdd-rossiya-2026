import { SignJWT, importPKCS8 } from 'jose';

export const STORE_NAMES = { apple: 'App Store', google: 'Google Play', rustore: 'RuStore' };
export const REPLY_LIMITS = { apple: 3000, google: 350, rustore: 500 };
export class StoreError extends Error {
  constructor(status, code = 'store_request_failed') { super(code); this.status = status; }
}
async function jsonFetch(url, options = {}) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(20000) });
  if (!response.ok) { await response.body?.cancel(); throw new StoreError(response.status); }
  return response.json();
}
export class ReviewStores {
  constructor(env) { this.config = JSON.parse(env.STORE_REVIEW_CREDENTIALS || '{}'); this.tokens = {}; }
  async auth(store) {
    if (this.tokens[store]?.expires > Date.now()) return this.tokens[store].value;
    const c = this.config[store];
    if (!c) throw new StoreError(503, 'store_not_configured');
    let value;
    if (store === 'apple') {
      value = await new SignJWT({}).setProtectedHeader({ alg: 'ES256', kid: c.keyId, typ: 'JWT' })
        .setIssuer(c.issuerId).setAudience('appstoreconnect-v1').setIssuedAt().setExpirationTime('10m')
        .sign(await importPKCS8(c.privateKey, 'ES256'));
    } else if (store === 'google') {
      const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
        .setProtectedHeader({ alg: 'RS256', typ: 'JWT' }).setIssuer(c.client_email)
        .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('10m')
        .sign(await importPKCS8(c.private_key, 'RS256'));
      const result = await jsonFetch('https://oauth2.googleapis.com/token', { method: 'POST',
        body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }) });
      value = result.access_token;
    } else {
      const timestamp = new Date().toISOString();
      const key = await importPKCS8(c.privateKey, 'RS512');
      const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(c.keyId + timestamp));
      const signature64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
      const result = await jsonFetch((c.base || 'https://public-api-m.rustore.ru') + '/public/auth/', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ keyId: c.keyId, timestamp, signature: signature64 }) });
      value = result.body?.jwe;
    }
    if (!value) throw new StoreError(502, 'store_auth_failed');
    this.tokens[store] = { value, expires: Date.now() + 8 * 60000 };
    return value;
  }
  async call(store, path, method = 'GET', body) {
    const c = this.config[store];
    const token = await this.auth(store);
    const base = store === 'apple' ? 'https://api.appstoreconnect.apple.com' : store === 'google'
      ? `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${c.package}`
      : (c.base || 'https://public-api-m.rustore.ru');
    const result = await jsonFetch(base + path, { method, headers: {
      ...(store === 'rustore' ? { 'Public-Token': token } : { Authorization: 'Bearer ' + token }),
      'content-type': 'application/json',
    }, ...(body ? { body: JSON.stringify(body) } : {}) });
    if (store === 'rustore' && !['OK', 0, '0'].includes(result.code)) throw new StoreError(502, 'rustore_request_failed');
    return result;
  }
  normalize(store, data, included = []) {
    if (store === 'apple') {
      const a = data.attributes;
      const id = data.relationships?.response?.data?.id;
      const response = included.find(x => x.id === id)?.attributes;
      return { store, id: data.id, author: a.reviewerNickname, rating: a.rating,
        text: [a.title, a.body].filter(Boolean).join('\n'), date: a.createdDate, territory: a.territory,
        response: response?.responseBody || '', responseStatus: response?.state || '', responseId: id || null };
    }
    if (store === 'google') {
      const user = data.comments?.find(c => c.userComment)?.userComment || {};
      const response = data.comments?.find(c => c.developerComment)?.developerComment;
      return { store, id: data.reviewId, author: data.authorName, rating: user.starRating,
        text: user.originalText || user.text || '', date: new Date(Number(user.lastModified?.seconds || 0) * 1000).toISOString(),
        version: user.appVersionName || '', response: response?.text || '', responseStatus: response ? 'PUBLISHED' : '' };
    }
    return { store, id: String(data.commentId), author: data.userName, rating: data.appRating,
      text: data.commentText || '', date: data.updatedAtIso || data.commentDateIso || data.updatedAt || data.commentDate,
      version: data.appVersionName || '', response: data.devResponses?.at(-1)?.text || '', responseStatus: '' };
  }
  async *list(store) {
    const responses = store === 'rustore' ? await this.rustoreResponses() : new Map();
    let next = store === 'apple' ? `/v1/apps/${this.config.apple.appId}/customerReviews?limit=200&sort=-createdDate&include=response`
      : store === 'google' ? '/reviews?maxResults=100' : '';
    for (let page = 0; page < 50; page++) {
      if (store === 'rustore') next = `/public/v1/application/${this.config.rustore.package}/comment?page=${page}&size=100`;
      const result = await this.call(store, next);
      const rows = store === 'apple' ? result.data : store === 'google' ? result.reviews || [] : result.body;
      if (!Array.isArray(rows)) throw new StoreError(502, 'invalid_reviews');
      for (const row of rows) {
        const review = this.normalize(store, row, result.included);
        const response = responses.get(review.id);
        yield response ? { ...review, response: response.text, responseStatus: response.status, responseId: String(response.id) } : review;
      }
      if (store === 'apple') {
        if (!result.links?.next) return;
        const url = new URL(result.links.next);
        if (url.origin !== 'https://api.appstoreconnect.apple.com') throw new StoreError(502, 'invalid_pagination');
        next = url.pathname + url.search;
      } else if (store === 'google') {
        const token = result.tokenPagination?.nextPageToken;
        if (!token) return;
        next = '/reviews?maxResults=100&token=' + encodeURIComponent(token);
      } else if (rows.length < 100) return;
    }
    throw new StoreError(502, 'review_page_limit');
  }
  async rustoreResponses() {
    const map = new Map();
    for (let page = 0; page < 50; page++) {
      const r = await this.call('rustore', `/public/v1/application/${this.config.rustore.package}/feedback?page=${page}&size=100`);
      if (!Array.isArray(r.body)) throw new StoreError(502, 'invalid_review_responses');
      for (const response of r.body) if (response.status !== 'DELETED' && !map.has(String(response.commentId))) map.set(String(response.commentId), response);
      if (r.body.length < 100) return map;
    }
    throw new StoreError(502, 'response_page_limit');
  }
  async get(review) {
    const { store, id } = review;
    if (store === 'apple') {
      const r = await this.call(store, `/v1/customerReviews/${encodeURIComponent(id)}?include=response`);
      return this.normalize(store, r.data, r.included);
    }
    if (store === 'google') return this.normalize(store, await this.call(store, '/reviews/' + encodeURIComponent(id)));
    const r = await this.call(store, `/public/v1/application/${this.config.rustore.package}/comment?id=${encodeURIComponent(id)}`);
    if (!Array.isArray(r.body) || !r.body.length) throw new StoreError(404);
    const current = this.normalize(store, r.body[0]);
    const response = (await this.rustoreResponses()).get(current.id);
    return response ? { ...current, response: response.text, responseStatus: response.status, responseId: String(response.id) } : current;
  }
  async publish(review, text) {
    const { store, id } = review;
    if (store === 'apple') return this.call(store, '/v1/customerReviewResponses', 'POST', { data: {
      type: 'customerReviewResponses', attributes: { responseBody: text },
      relationships: { review: { data: { type: 'customerReviews', id } } },
    } });
    if (store === 'google') return this.call(store, `/reviews/${encodeURIComponent(id)}:reply`, 'POST', { replyText: text });
    return this.call(store, `/public/v1/application/${this.config.rustore.package}/feedback${review.responseId ? '/' + encodeURIComponent(review.responseId) : '?commentId=' + encodeURIComponent(id)}`, 'POST', { message: text });
  }
  async replyStatus(review, result) {
    if (review.store === 'google') return { responseStatus: 'PUBLISHED' };
    if (review.store === 'apple') return { responseStatus: result.data?.attributes?.state || 'PENDING_PUBLISH' };
    const id = result.body?.id;
    return { responseStatus: 'MODERATION', responseId: id ? String(id) : null };
  }
  async status(review) {
    if (review.store !== 'rustore' || !review.responseId) return null;
    const r = await this.call('rustore', `/public/v1/application/${this.config.rustore.package}/feedback/${review.responseId}`);
    const body = Array.isArray(r.body) ? r.body[0] : r.body;
    return body ? { response: body.text || review.response, responseStatus: body.status } : null;
  }
}
