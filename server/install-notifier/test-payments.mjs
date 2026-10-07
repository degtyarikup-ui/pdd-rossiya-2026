// Оплата на сайте через Platega: создание платежа, уведомление, проверка
// после возврата, повторы, чужие и поддельные уведомления, возврат денег.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { handleAuth } from './user_auth.js';

class KV {
  data = new Map();
  meta = new Map();
  async get(k) { return this.data.get(k) ?? null; }
  async put(k, v, o) { this.data.set(k, String(v)); if (o?.metadata) this.meta.set(k, o.metadata); }
  async delete(k) { this.data.delete(k); this.meta.delete(k); }
  async list({ prefix }) {
    return { keys: [...this.data.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name, metadata: this.meta.get(name) })), list_complete: true };
  }
}

// Подменяем Platega: создание платежа и чтение статуса.
function fakePlatega() {
  const txs = new Map();
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    if (!u.startsWith('https://app.platega.io/')) return original(url, init);
    calls.push({ url: u, init });
    assert.equal(init.headers['X-MerchantId'], 'merchant-1');
    assert.equal(init.headers['X-Secret'], 'secret-1');
    if (u.endsWith('/transaction/process')) {
      const body = JSON.parse(init.body);
      const id = crypto.randomUUID();
      txs.set(id, { id, status: 'PENDING', paymentDetails: body.paymentDetails, payload: body.payload, body });
      return Response.json({ transactionId: id, url: 'https://pay.platega.io/' + id, status: 'PENDING' });
    }
    const id = u.split('/transaction/')[1];
    const tx = txs.get(id);
    return tx ? Response.json(tx) : new Response('{}', { status: 404 });
  };
  return { txs, calls, restore: () => { globalThis.fetch = original; } };
}

const baseEnv = () => ({ INSTALLS: new KV(), SHARED_SECRET: 'test-key', SESSION_SECRET: 'session-test-secret',
  ADMIN_PASSWORD: 'pw', PLATEGA_MERCHANT_ID: 'merchant-1', PLATEGA_SECRET: 'secret-1' });
const req = (path, body, token, headers = {}) => new Request('https://app.test' + path, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { 'content-type': 'application/json', 'x-install-secret': 'test-key', ...(token ? { authorization: 'Bearer ' + token } : {}), ...headers },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});
async function login(env, id = 'google_1') {
  const r = await handleAuth(req('/api/auth/session', {}), env,
    async () => ({ id, name: 'Анна', email: 'anna@example.com', provider: 'google', createdAt: new Date().toISOString() }));
  return (await r.json()).token;
}
const callback = (env, body, secret = 'secret-1') => worker.fetch(req('/api/pay/platega/callback', body, null,
  { 'X-MerchantId': 'merchant-1', 'X-Secret': secret }), env);
const user = env => JSON.parse(env.INSTALLS.data.get('user:google_1') || 'null');

test('без ключей Platega оплата выключена — только заглушка', async () => {
  const env = baseEnv(); delete env.PLATEGA_SECRET;
  const token = await login(env);
  assert.deepEqual(await (await worker.fetch(req('/api/pay/status'), env)).json(), { ok: true, available: false, methods: ['sbp'] });
  const r = await (await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'weekly', method: 'sbp' }, token), env)).json();
  assert.deepEqual(r, { ok: true, available: false });
  assert.equal((await callback(env, { id: 'x', status: 'CONFIRMED' })).status, 503);
});

test('оплата: платёж, уведомление, срок один раз, повтор не добавляет', async () => {
  const fake = fakePlatega();
  try {
    const env = baseEnv();
    const token = await login(env);
    assert.equal((await (await worker.fetch(req('/api/pay/status'), env)).json()).available, true);
    const start = await (await worker.fetch(req('/api/user/pay-intent', { email: 'Anna@Example.com', tier: 'threeMonths', method: 'sbp' }, token), env)).json();
    assert.equal(start.available, true);
    assert.match(start.url, /^https:\/\/pay\.platega\.io\//);
    const [tx] = fake.txs.values();
    assert.equal(tx.paymentDetails.amount, 290);
    assert.equal(tx.body.paymentMethod, 2);
    assert.equal(tx.body.return, `https://pdd-drive.ru/app/?pay=done&order=${start.order}`);
    assert.equal(tx.payload, start.order);

    // Повторное нажатие в течение 10 минут — та же форма оплаты, без нового платежа.
    const again = await (await worker.fetch(req('/api/user/pay-intent', { email: 'anna@example.com', tier: 'threeMonths', method: 'sbp' }, token), env)).json();
    assert.equal(again.url, start.url);
    assert.equal(fake.txs.size, 1);

    // Пока не оплачено — премиума нет.
    const pending = await (await worker.fetch(req('/api/user/pay-check', { order: start.order }, token), env)).json();
    assert.equal(pending.status, 'pending');
    assert.ok(!user(env)?.isPremium);

    // Поддельное уведомление: неверный секрет.
    assert.equal((await callback(env, { id: tx.id, status: 'CONFIRMED', payload: start.order }, 'wrong')).status, 401);
    // Уведомление «оплачено», но Platega говорит PENDING — доступ не выдаётся.
    assert.equal((await callback(env, { id: tx.id, status: 'CONFIRMED', payload: start.order })).status, 200);
    assert.ok(!user(env)?.isPremium);

    tx.status = 'CONFIRMED';
    assert.equal((await callback(env, { id: tx.id, status: 'CONFIRMED', payload: start.order })).status, 200);
    const paid = user(env);
    assert.equal(paid.isPremium, true);
    assert.equal(paid.premiumSource, 'web');
    const end = Date.parse(paid.premiumExpiresAt);
    assert.ok(Math.abs(end - (Date.now() + 90 * 86400000)) < 60000);

    // Повторное уведомление и проверка после возврата не продлевают ещё раз.
    await callback(env, { id: tx.id, status: 'CONFIRMED', payload: start.order });
    const check = await (await worker.fetch(req('/api/user/pay-check', { order: start.order }, token), env)).json();
    assert.equal(check.status, 'confirmed');
    assert.equal(user(env).premiumExpiresAt, paid.premiumExpiresAt);

    // Новая покупка после оплаты — новый платёж, а не старая ссылка.
    const next = await (await worker.fetch(req('/api/user/pay-intent', { email: 'anna@example.com', tier: 'threeMonths', method: 'sbp' }, token), env)).json();
    assert.notEqual(next.order, start.order);
    assert.equal(fake.txs.size, 2);

    // Статус в приложении — по аккаунту.
    const status = await (await worker.fetch(req('/api/user/status', undefined, token), env)).json();
    assert.equal(status.isPremium, true);
    assert.equal(status.premiumSource, 'web');

    // Возврат денег снимает начисленный срок.
    tx.status = 'CHARGEBACKED';
    await callback(env, { id: tx.id, status: 'CHARGEBACKED', payload: start.order });
    assert.equal(user(env).isPremium, false);
  } finally { fake.restore(); }
});

test('чужой заказ не проверить, сумма не совпала — доступа нет', async () => {
  const fake = fakePlatega();
  try {
    const env = baseEnv();
    const token = await login(env);
    const other = await login(env, 'google_2');
    const start = await (await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'weekly', method: 'sbp' }, token), env)).json();
    assert.equal((await worker.fetch(req('/api/user/pay-check', { order: start.order }, other), env)).status, 404);
    const [tx] = fake.txs.values();
    tx.status = 'CONFIRMED';
    tx.paymentDetails = { amount: 1, currency: 'RUB' };
    await callback(env, { id: tx.id, status: 'CONFIRMED', payload: start.order });
    assert.ok(!user(env)?.isPremium);
    assert.equal(JSON.parse(env.INSTALLS.data.get('pay_order:' + start.order)).status, 'mismatch');
    // Неизвестный платёж подтверждается без действий, чтобы Platega не повторяла.
    const unknown = await callback(env, { id: crypto.randomUUID(), status: 'CONFIRMED' });
    assert.deepEqual(await unknown.json(), { ok: true, ignored: true });
  } finally { fake.restore(); }
});

test('оплата на сайте добавляется после действующего срока стора', async () => {
  const fake = fakePlatega();
  try {
    const env = baseEnv();
    const token = await login(env);
    const storeEnd = new Date(Date.now() + 5 * 86400000).toISOString();
    env.INSTALLS.data.set('user:google_1', JSON.stringify({ id: 'google_1', isPremium: true, premiumSource: 'appstore', premiumExpiresAt: storeEnd }));
    const start = await (await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'weekly', method: 'sbp' }, token), env)).json();
    const [tx] = fake.txs.values();
    tx.status = 'CONFIRMED';
    await worker.fetch(req('/api/user/pay-check', { order: start.order }, token), env);
    const u = user(env);
    assert.equal(u.entitlements.appstore.expiresAt, storeEnd);
    assert.equal(u.entitlements.web.expiresAt, new Date(Date.parse(storeEnd) + 7 * 86400000).toISOString());
    assert.equal(u.premiumSource, 'web');
  } finally { fake.restore(); }
});

test('страница тарифов: почта без входа, проверка ввода, ловушка для ботов, без повторов', async () => {
  const env = baseEnv(); delete env.PLATEGA_SECRET;
  const lead = body => worker.fetch(new Request('https://app.test/api/pay/lead', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }), env);
  assert.equal((await lead({ email: 'нет', tier: 'weekly' })).status, 400);
  assert.equal((await lead({ email: 'a@b.ru', tier: 'year' })).status, 400);
  assert.deepEqual(await (await lead({ email: 'a@b.ru', tier: 'weekly', website: 'spam' })).json(), { ok: true, available: false });
  assert.equal(env.INSTALLS.data.has('pay_lead:a@b.ru'), false);
  assert.deepEqual(await (await lead({ email: 'A@B.ru', tier: 'threeMonths' })).json(), { ok: true, available: false });
  await lead({ email: 'a@b.ru', tier: 'threeMonths' });
  assert.equal(JSON.parse(env.INSTALLS.data.get('pay_lead:a@b.ru')).count, 1);
  const list = await (await worker.fetch(req('/api/admin/pay-intents', undefined, 'pw'), env)).json();
  assert.equal(list.intents.find(i => i.source === 'tarify').email, 'a@b.ru');
});
