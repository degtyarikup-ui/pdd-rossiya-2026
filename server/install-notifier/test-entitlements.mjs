// Премиум из нескольких источников (стор, сайт, админка) и заглушка оплаты на сайте.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { handleAuth } from './user_auth.js';
import { applyEntitlements, entitlementsOf, extendEntitlement, setEntitlement, clearEntitlements } from './entitlements.js';
import { storeEntitlementExpiry } from './store_verification.js';

const DAY = 86400000;
const NOW = Date.parse('2026-10-07T12:00:00Z');
const iso = ms => new Date(ms).toISOString();

class KV {
  data = new Map();
  meta = new Map();
  async get(k) { return this.data.get(k) ?? null; }
  async put(k, v, o) { this.data.set(k, String(v)); if (o?.metadata) this.meta.set(k, o.metadata); }
  async delete(k) { this.data.delete(k); this.meta.delete(k); }
  async list({ prefix }) {
    const keys = [...this.data.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name, metadata: this.meta.get(name) }));
    return { keys, list_complete: true };
  }
}

test('итог — самый дальний действующий срок, покупка не укорачивает доступ', () => {
  const user = { id: 'u' };
  setEntitlement(user, 'web', iso(NOW + 90 * DAY), NOW);
  assert.equal(user.premiumSource, 'web');
  // Неделя в App Store короче оплаченного на сайте — итог не меняется.
  setEntitlement(user, 'appstore', iso(NOW + 7 * DAY), NOW);
  assert.equal(user.isPremium, true);
  assert.equal(user.premiumSource, 'web');
  assert.equal(user.premiumExpiresAt, iso(NOW + 90 * DAY));
  // Срок сайта прошёл — действует стор.
  assert.equal(applyEntitlements(user, NOW + 30 * DAY).premiumSource, 'web');
  setEntitlement(user, 'appstore', iso(NOW + 200 * DAY), NOW);
  assert.equal(user.premiumSource, 'appstore');
  // Бессрочная выдача перекрывает всё.
  setEntitlement(user, 'admin_grant', null, NOW);
  assert.equal(user.premiumSource, 'admin_grant');
  assert.equal(user.premiumExpiresAt, null);
});

test('без действующих сроков премиума нет, история источника остаётся', () => {
  const user = { id: 'u' };
  setEntitlement(user, 'googleplay', iso(NOW + DAY), NOW);
  applyEntitlements(user, NOW + 2 * DAY);
  assert.equal(user.isPremium, false);
  assert.equal(user.premiumSource, 'googleplay');
  clearEntitlements(user);
  assert.equal(user.isPremium, false);
  assert.deepEqual(entitlementsOf(user), {});
});

test('старые записи читаются как единственный источник', () => {
  const legacy = { isPremium: true, premiumSource: 'appstore', premiumExpiresAt: iso(NOW + 5 * DAY) };
  assert.deepEqual(entitlementsOf(legacy), { appstore: { expiresAt: iso(NOW + 5 * DAY) } });
  extendEntitlement(legacy, 'web', 90, NOW);
  // Оплата на сайте начинается после действующего срока стора.
  assert.equal(legacy.entitlements.web.expiresAt, iso(NOW + 95 * DAY));
  assert.equal(legacy.entitlements.appstore.expiresAt, iso(NOW + 5 * DAY));
  assert.equal(legacy.premiumSource, 'web');
});

test('отозванная покупка стора не даёт доступа с будущей датой', () => {
  assert.equal(storeEntitlementExpiry({ active: false, expiresAt: iso(NOW + 30 * DAY) }, NOW), iso(NOW));
  assert.equal(storeEntitlementExpiry({ active: true, expiresAt: iso(NOW + 30 * DAY) }, NOW), iso(NOW + 30 * DAY));
});

test('выдача из админки не снимает стор, отзыв снимает всё', async () => {
  const env = { INSTALLS: new KV(), ADMIN_PASSWORD: 'pw' };
  const storeEnd = iso(Date.now() + 100 * DAY);
  env.INSTALLS.data.set('user:u1', JSON.stringify({ id: 'u1', isPremium: true, premiumSource: 'appstore', premiumExpiresAt: storeEnd }));
  const call = (path, body) => worker.fetch(new Request('https://w.test' + path, {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer pw' }, body: JSON.stringify(body),
  }), env);
  assert.equal((await call('/api/admin/users/grant-premium', { userId: 'u1', days: 7, mode: 'set', notify: false })).status, 200);
  let user = JSON.parse(env.INSTALLS.data.get('user:u1'));
  assert.equal(user.premiumSource, 'appstore');
  assert.equal(user.premiumExpiresAt, storeEnd);
  assert.ok(user.entitlements.admin_grant);
  assert.equal((await call('/api/admin/users/revoke-premium', { userId: 'u1' })).status, 200);
  user = JSON.parse(env.INSTALLS.data.get('user:u1'));
  assert.equal(user.isPremium, false);
  assert.deepEqual(user.entitlements, {});
});

test('выбор оплаты на сайте: только с сессией, проверка почты и тарифа, без повторов', async () => {
  const env = { INSTALLS: new KV(), SHARED_SECRET: 'test-key', SESSION_SECRET: 'session-test-secret', ADMIN_PASSWORD: 'pw' };
  const req = (path, body, token, extra = {}) => new Request('https://app.test' + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'content-type': 'application/json', 'x-install-secret': 'test-key', ...(token ? { authorization: 'Bearer ' + token } : {}), ...extra },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const session = await (await handleAuth(req('/api/auth/session', {}), env,
    async () => ({ id: 'google_1', name: 'Анна', email: 'anna@example.com', provider: 'google', createdAt: new Date().toISOString() }))).json();
  const intent = { email: 'Anna@Example.com', tier: 'threeMonths', method: 'sbp', app: 'ru' };

  assert.equal((await worker.fetch(req('/api/user/pay-intent', intent), env)).status, 401);
  assert.equal((await worker.fetch(req('/api/user/pay-intent', { ...intent, email: 'нет' }, session.token), env)).status, 400);
  assert.equal((await worker.fetch(req('/api/user/pay-intent', { ...intent, tier: 'year' }, session.token), env)).status, 400);

  const ok = await worker.fetch(req('/api/user/pay-intent', intent, session.token), env);
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { ok: true, available: false });
  const saved = JSON.parse(env.INSTALLS.data.get('pay_intent:google_1'));
  assert.equal(saved.email, 'anna@example.com');
  assert.equal(saved.priceRub, 290);
  assert.equal(saved.count, 1);
  // Повтор того же выбора сразу же не пишется.
  await worker.fetch(req('/api/user/pay-intent', intent, session.token), env);
  assert.equal(JSON.parse(env.INSTALLS.data.get('pay_intent:google_1')).count, 1);
  // Выбор оплаты не выдаёт премиум.
  const user = env.INSTALLS.data.get('user:google_1');
  assert.ok(!user || JSON.parse(user).isPremium !== true);

  assert.equal((await worker.fetch(req('/api/admin/pay-intents'), env)).status, 401);
  const list = await (await worker.fetch(req('/api/admin/pay-intents', undefined, 'pw'), env)).json();
  assert.equal(list.intents.length, 1);
  assert.equal(list.intents[0].userId, 'google_1');
  assert.equal(list.intents[0].tier, 'threeMonths');
});
