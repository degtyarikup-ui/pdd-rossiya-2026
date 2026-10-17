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
function fakePlatega({ create, status } = {}) {
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
      if (create) return create(url, init);
      const body = JSON.parse(init.body);
      const id = crypto.randomUUID();
      txs.set(id, { id, status: 'PENDING', paymentDetails: body.paymentDetails, payload: body.payload, body });
      return Response.json({ transactionId: id, url: 'https://pay.platega.io/' + id, status: 'PENDING' });
    }
    if (status) return status(url, init);
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
function captureIncidents(env) {
  const incidents = [];
  env.BOT_TOKEN = 'bot-test'; env.CHAT_ID = 'chat-test';
  env.TELEGRAM = { idFromName: value => value, get: () => ({ fetch: async (url, init) => {
    if (String(url).endsWith('/incident')) incidents.push(JSON.parse(init.body).incident);
    return Response.json({ ok: true });
  } }) };
  return incidents;
}

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
    tx.paymentDetails = { amount: 313.2, currency: 'RUB' }; // 290 ₽ + 8% комиссии покупателя
    assert.equal((await callback(env, { id: tx.id, status: 'CONFIRMED', payload: start.order })).status, 200);
    const paid = user(env);
    assert.equal(paid.isPremium, true);
    assert.equal(paid.premiumSource, 'web');
    const end = Date.parse(paid.premiumExpiresAt);
    assert.ok(Math.abs(end - (Date.now() + 90 * 86400000)) < 60000);

    // Синхронизация профиля приложением не стирает отметку об оплате.
    await worker.fetch(req('/api/user/sync', { id: 'google_1', name: 'Анна', email: 'anna@example.com', provider: 'google' }, token), env);
    assert.ok(user(env).webPayments[start.order]);

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
    assert.equal(unknown.status, 503);
    assert.deepEqual(await unknown.json(), { error: 'payment order not ready' });
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

test('Android: после оплаты возврат на страницу «вернитесь в приложение», веб — как раньше', async () => {
  const fake = fakePlatega();
  try {
    const env = baseEnv();
    const token = await login(env);
    const android = await (await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'weekly', method: 'sbp', client: 'android' }, token), env)).json();
    const [txA] = [...fake.txs.values()].slice(-1);
    assert.equal(txA.body.return, `https://pdd-drive.ru/pay-done/?order=${android.order}`);
    assert.equal(txA.body.failedUrl, `https://pdd-drive.ru/pay-done/?order=${android.order}&failed=1`);
    assert.equal(JSON.parse(env.INSTALLS.data.get('pay_order:' + android.order)).client, 'android');

    // Тот же тариф в вебе в пределах 10 минут — свой платёж, а не ссылка из Android.
    const web = await (await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'weekly', method: 'sbp' }, token), env)).json();
    assert.notEqual(web.order, android.order);
    const txW = [...fake.txs.values()].slice(-1)[0];
    assert.equal(txW.body.return, `https://pdd-drive.ru/app/?pay=done&order=${web.order}`);
  } finally { fake.restore(); }
});

test('сбой создания СБП: один подробный инцидент, безопасная причина и проверенный аккаунт', async () => {
  const cases = [
    ['payment_provider_unavailable', null, () => { throw new Error('secret-1 https://pay.test/?token=private'); }],
    ['payment_provider_timeout', null, () => { throw new DOMException('private token', 'TimeoutError'); }],
    ['payment_provider_auth', 401, () => new Response('secret-1 raw provider response', { status: 401 })],
    ['payment_provider_rate_limited', 429, () => new Response('{}', { status: 429 })],
    ['payment_provider_rejected', 422, () => new Response('{}', { status: 422 })],
    ['payment_provider_unavailable', 502, () => new Response('{}', { status: 502 })],
    ['payment_provider_invalid_response', null, () => new Response('private non-json response')],
    ['payment_provider_invalid_response', null, () => Response.json({ transactionId: 'private', token: 'private' })],
    ['payment_provider_invalid_response', null, () => Response.json([])],
  ];
  for (const [code, providerStatus, create] of cases) {
    const fake = fakePlatega({ create });
    try {
      const env = baseEnv(); const token = await login(env); const incidents = captureIncidents(env);
      const response = await worker.fetch(req('/api/user/pay-intent', { email: 'receipt@example.org', tier: 'weekly', method: 'sbp', client: 'android', name: 'Подделка', userEmail: 'fake@example.org' }, token), env);
      assert.equal(response.status, 503, code);
      assert.equal(incidents.length, 1, code + ': без дублирующего общего лога');
      const event = incidents[0];
      assert.equal(event.operation, 'api.user.pay-intent'); assert.equal(event.code, code);
      assert.equal(event.userId, 'google_1'); assert.equal(event.userName, 'Анна'); assert.equal(event.userEmail, 'anna@example.com');
      assert.equal(event.payment.tier, 'weekly'); assert.equal(event.payment.amountRub, 99);
      assert.equal(event.payment.method, 'sbp'); assert.equal(event.payment.client, 'android');
      assert.equal(event.payment.providerOperation, 'create'); assert.equal(event.payment.providerStatus, providerStatus);
      assert.match(event.payment.orderId, /^[0-9a-f-]{36}$/);
      assert.doesNotMatch(JSON.stringify(event), /secret-1|private|Подделка|fake@example|receipt@example/);
      assert.ok(!user(env)?.isPremium);
    } finally { fake.restore(); }
  }
});

test('проверка и колбэк СБП сохраняют контекст заказа и точную причину сбоя Platega', async () => {
  let fail = false;
  const fake = fakePlatega({ status: () => {
    assert.ok(fail); return new Response('private provider body', { status: 503 });
  } });
  try {
    const env = baseEnv(); const token = await login(env);
    const start = await (await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'threeMonths', method: 'sbp' }, token), env)).json();
    fail = true;
    const incidents = captureIncidents(env);
    const response = await worker.fetch(req('/api/user/pay-check', { order: start.order }, token), env);
    assert.equal(response.status, 200); assert.equal((await response.json()).status, 'pending');
    assert.equal(incidents.length, 1); assert.equal(incidents[0].operation, 'payment.check');
    const [tx] = fake.txs.values();
    const result = await callback(env, { id: tx.id, payload: start.order, status: 'CONFIRMED' });
    assert.equal(result.status, 503); assert.equal(incidents.length, 2);
    assert.equal(incidents[1].operation, 'api.pay.platega.callback');
    for (const event of incidents) {
      assert.equal(event.code, 'payment_provider_unavailable');
      assert.equal(event.userName, 'Анна'); assert.equal(event.userEmail, 'anna@example.com');
      assert.equal(event.payment.orderId, start.order); assert.equal(event.payment.txId, tx.id);
      assert.equal(event.payment.amountRub, 290); assert.equal(event.payment.tier, 'threeMonths');
      assert.equal(event.payment.providerOperation, 'status'); assert.equal(event.payment.providerStatus, 503);
      assert.doesNotMatch(JSON.stringify(event), /private provider body/);
    }
    assert.ok(!user(env)?.isPremium);
  } finally { fake.restore(); }
});

test('сбой сохранения после создания СБП не раскрывает исключение и сохраняет номер транзакции в логе', async () => {
  for (const prefix of ['pay_order:', 'pay_tx:', 'pay_intent:']) {
    const fake = fakePlatega();
    try {
      const env = baseEnv(); const token = await login(env); const incidents = captureIncidents(env);
      const put = env.INSTALLS.put.bind(env.INSTALLS);
      env.INSTALLS.put = async (key, ...args) => {
        if (key.startsWith(prefix)) throw new Error('put 429 secret-1 private details');
        return put(key, ...args);
      };
      const response = await worker.fetch(req('/api/user/pay-intent', { email: 'a@b.ru', tier: 'weekly', method: 'sbp' }, token), env);
      assert.equal(response.status, 503); assert.deepEqual(await response.json(), { error: 'storage unavailable' });
      assert.equal(incidents.length, 1, prefix);
      const event = incidents[0], [tx] = fake.txs.values();
      assert.equal(event.code, 'storage_rate_limited'); assert.equal(event.payment.txId, tx.id);
      assert.match(event.payment.orderId, /^[0-9a-f-]{36}$/);
      assert.doesNotMatch(JSON.stringify(event), /secret-1|private details/);
      assert.ok(!user(env)?.isPremium);
    } finally { fake.restore(); }
  }
});
