import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { fixture, request, session } from './fixture-account.mjs';
import { accountRead } from './account_state.js';

const admin = (env, change, token = 'fixture-admin') =>
  worker.fetch(request('/api/admin/premium-offers', change, token), env);
const read = env => worker.fetch(request('/api/pay/catalog'), env);

test('offers start inactive, require admin and version every change independently', async () => {
  const { env, restart } = fixture();
  const publicResponse = await read(env);
  assert.equal(publicResponse.headers.get('Cache-Control'), 'no-store');
  const initial = await publicResponse.json();
  assert.equal(initial.tariffs.weekly.priceRub, 99);
  assert.equal(initial.tariffs.threeMonths.priceRub, 290);
  assert.deepEqual(initial.storeTrials, { appstore: false, googleplay: false });
  assert.deepEqual(initial.nativeQuarter, { appstore: 'legacy', googleplay: 'legacy' });
  assert.equal(initial.settings, undefined);
  const draft = { operation: 'save_promotion', revision: 0, priceRub: 250 };
  assert.equal((await admin(env, draft, null)).status, 401);
  assert.equal((await admin(env, draft, await session(env))).status, 401);
  assert.equal((await admin(env, {...draft, priceRub: 370})).status, 400);
  const results = await Promise.all([admin(env, draft), admin(env, draft)]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
  assert.deepEqual(await (await read(env)).json(), initial);
  const change = async (operation, revision, fields) => {
    const response = await admin(env, { operation, revision, ...fields });
    assert.equal(response.status, 200);
    return (await response.json()).catalog;
  };
  assert.equal((await change('activate_sbp', 1, { mode:'standard' })).tariffs.threeMonths.priceRub, 370);
  assert.equal((await change('activate_sbp', 2, { mode:'promotion' })).tariffs.threeMonths.priceRub, 250);
  assert.equal((await change('save_promotion', 3, { priceRub:200 })).tariffs.threeMonths.priceRub, 250);
  const apple = await change('set_store', 4, { store:'appstore', mode:'standard', trial:true });
  assert.deepEqual(apple.storeTrials, {appstore:true, googleplay:false});
  assert.deepEqual(apple.nativeQuarter, {appstore:'standard', googleplay:'legacy'});
  restart('premium-offers');
  assert.deepEqual(await (await read(env)).json(), apple);
  const former = await change('activate_sbp', 5, {mode:'legacy'});
  assert.deepEqual(former.tariffs, initial.tariffs);
});

test('checkout binds the quoted price, legacy protocol and in-flight orders to distinct terms', async () => {
  const { env } = fixture();
  const payments = new Map();
  const original = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (url === 'https://app.platega.io/transaction/process') {
      const data = JSON.parse(init.body);
      const transactionId = crypto.randomUUID();
      payments.set(transactionId, { ...data, status: 'PENDING' });
      return Response.json({ transactionId, url:'https://pay.platega.io/' + transactionId });
    }
    return Response.json(payments.get(String(url).split('/').at(-1)));
  };
  try {
    const oldId = 'google_old', modernId = 'google_new';
    const oldToken = await session(env, oldId), token = await session(env, modernId);
    const body = { email:'a@example.invalid', method:'sbp', tier:'threeMonths', checkout:'sbp' };
    const quote = expectedPriceRub => ({ catalogVersion:1, expectedPriceRub });
    const pay = (token, fields = {}) => worker.fetch(request('/api/user/pay-intent', {...body, ...fields}, token), env);
    const switchMode = (revision, mode) => admin(env, { operation:'activate_sbp', revision, mode });
    assert.equal((await switchMode(0, 'standard')).status, 200);
    const stale = await pay(token, quote(290));
    assert.equal(stale.status, 409);
    assert.equal((await stale.json()).catalog.tariffs.threeMonths.priceRub, 370);
    assert.equal((await pay(token, {expectedPriceRub:1})).status, 400);
    assert.equal((await pay(token, {tier:'__proto__'})).status, 400);
    assert.equal((await pay(token, {method:'constructor'})).status, 400);
    assert.equal(payments.size, 0);
    assert.equal((await pay(oldToken)).status, 200);
    const order = await (await pay(token, quote(370))).json();
    assert.ok(order.url);
    assert.deepEqual([...payments.values()].map(tx => tx.paymentDetails.amount), [290, 370]);
    assert.equal((await switchMode(1, 'promotion')).status, 200);
    const pending = await pay(token, quote(290));
    assert.equal(pending.status, 409);
    const conflict = await pending.json();
    assert.equal(conflict.code, 'pending_order');
    assert.equal(conflict.amount, 370);
    assert.equal(conflict.url, undefined);
    const check = () => worker.fetch(request('/api/user/pay-check', { catalogVersion:1, current:true }, token), env);
    const resumed = await (await check()).json();
    assert.equal(resumed.amount, 370);
    assert.equal(resumed.tier, 'threeMonths');
    assert.equal(resumed.url, order.url);
    const oldResume = await (await worker.fetch(request('/api/user/pay-check', {current:true}, token), env)).json();
    assert.equal(oldResume.status, 'pending');
    assert.equal(oldResume.url, undefined);
    assert.equal((await pay(token)).status, 409);
    assert.equal(payments.size, 2);
    const tx = [...payments.values()].at(-1);
    tx.status = 'CONFIRMED';
    assert.equal((await (await check()).json()).status, 'confirmed');
    const ledger = JSON.parse(await accountRead(env, modernId, 'payment_ledger:'+order.order));
    assert.equal(ledger.days, 90);
    assert.equal(ledger.amount, 370);
    const newDiscounted = await (await pay(token, quote(290))).json();
    assert.ok(newDiscounted.url);
    assert.deepEqual([...payments.values()].map(tx => tx.paymentDetails.amount), [290,370,290]);
  } finally { globalThis.fetch = original; }
});

test('lead checks price and a failed catalog read cannot silently charge a different price', async () => {
  const { env } = fixture();
  await admin(env, {operation:'activate_sbp', revision:0, mode:'standard'});
  const lead = fields => worker.fetch(request('/api/pay/lead', { email:'a@example.invalid', tier:'threeMonths', ...fields }), env);
  assert.equal((await lead({catalogVersion:1,expectedPriceRub:290})).status, 409);
  assert.equal(await env.INSTALLS.get('pay_lead:a@example.invalid'), null);
  assert.equal((await lead({catalogVersion:1,expectedPriceRub:370})).status, 200);
  assert.equal(JSON.parse(await env.INSTALLS.get('pay_lead:a@example.invalid')).priceRub, 370);
  const get = env.ACCOUNTS.get;
  env.ACCOUNTS.get = id => id === 'premium-offers'
    ? { fetch: async () => Response.json({error:'unavailable'}, {status:503}) } : get(id);
  assert.equal((await read(env)).status, 503);
  assert.equal((await lead({ catalogVersion:1, expectedPriceRub:370 })).status, 503);
  assert.equal((await lead({})).status, 200);
  assert.equal(JSON.parse(await env.INSTALLS.get('pay_lead:a@example.invalid')).priceRub, 290);
});
