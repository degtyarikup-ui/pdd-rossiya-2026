import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleAppleWebCallback } from './apple_web_callback.js';
import worker from './worker.js';

const state = 'a'.repeat(64);
const request = (fields, path = '/auth/apple/callback') => new Request('https://worker.test' + path, {
  method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(fields),
});
test('Apple form POST routes without app key, returns credentials only in a fragment, without issuing a session', async () => {
  const response = await worker.fetch(request({ state, code: 'single-use-code', id_token: 'signed-token', user: JSON.stringify({name:{firstName:'Test',lastName:'User'}}), redirect_uri:'https://evil.test' }), {});
  assert.equal(response.status, 303);
  const destination = new URL(response.headers.get('location'));
  assert.equal(destination.origin, 'https://pdd-drive.ru');
  assert.equal(destination.pathname, '/app/');
  assert.equal(destination.search, '?oauth=2');
  const params = new URLSearchParams(decodeURIComponent(destination.hash.slice('#pdd-oauth='.length)));
  assert.equal(params.get('provider'), 'apple');
  assert.equal(params.get('id_token'), 'signed-token');
  assert.equal(params.get('state'), state);
  assert.equal(params.get('firstName'), 'Test');
  assert.equal(params.has('token'), false);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
});
test('callback rejects unexpected methods, missing state/credentials and oversized body', async () => {
  assert.equal((await handleAppleWebCallback(new Request('https://worker.test/auth/apple/callback'))).status, 405);
  for (const fields of [{code:'x',id_token:'y'}, {state:'invalid',code:'x',id_token:'y'}, {state,code:'x'}, {state,id_token:'y'}]) assert.equal((await handleAppleWebCallback(request(fields))).status, 400);
  assert.equal((await handleAppleWebCallback(request({state,code:'x',id_token:'x'.repeat(40000)}))).status, 413);
  assert.equal((await handleAppleWebCallback(new Request('https://worker.test/auth/apple/callback',{method:'POST',body:'{}',headers:{'content-type':'application/json'}}))).status,415);
});
test('provider cancellation preserves the state and never forwards arbitrary error text', async () => {
  for (const error of ['access_denied', 'user_cancelled_authorize', 'private provider error']) {
    const response = await handleAppleWebCallback(request({state,error}));
    const params = new URLSearchParams(decodeURIComponent(new URL(response.headers.get('location')).hash.slice('#pdd-oauth='.length)));
    assert.equal(params.get('state'),state);
    assert.equal(params.get('error'),error === 'private provider error' ? 'provider_rejected' : 'access_denied');
  }
});
test('app host callback returns to the fixed app origin without changing the OAuth state', async () => {
  const response = await handleAppleWebCallback(request({
    state, code: 'single-use-code', id_token: 'signed-token',
    redirect_uri: 'https://evil.test', return_origin: 'https://evil.test',
  }), 'https://pdd-drive.app');
  assert.equal(response.status, 303);
  const destination = new URL(response.headers.get('location'));
  assert.equal(destination.origin, 'https://pdd-drive.app');
  assert.equal(destination.pathname, '/app/');
  assert.equal(destination.search, '?oauth=2');
  const params = new URLSearchParams(decodeURIComponent(destination.hash.slice('#pdd-oauth='.length)));
  assert.equal(params.get('state'), state);
  assert.equal(params.get('id_token'), 'signed-token');
  assert.equal(params.get('code'), 'single-use-code');
  assert.equal(params.has('redirect_uri'), false);
  assert.equal(params.has('return_origin'), false);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(response.headers.get('set-cookie'), null);
});
test('return origin is an exact server-side allowlist and cannot become an open redirect', async () => {
  for (const returnOrigin of [
    'https://evil.test', 'https://pdd-drive.app.evil.test',
    'https://pdd-drive.app@evil.test', 'http://pdd-drive.app',
    'https://pdd-drive.app/', 'https://pdd-drive.app/app/',
    '//pdd-drive.app', '__proto__', 'constructor', {}, null,
  ]) {
    const response = await handleAppleWebCallback(request({ state, code: 'x', id_token: 'y' }), returnOrigin);
    assert.equal(response.status, 400);
    assert.equal(response.headers.get('location'), null);
  }
});
test('both callback origins reject state routing markers and preserve safe cancellation', async () => {
  for (const returnOrigin of ['https://pdd-drive.ru', 'https://pdd-drive.app']) {
    for (const invalidState of ['app.' + state, 'ru.' + state, 'https://evil.test/' + state, state.toUpperCase(), state.slice(1)]) {
      const response = await handleAppleWebCallback(request({ state: invalidState, code: 'x', id_token: 'y' }), returnOrigin);
      assert.equal(response.status, 400);
      assert.equal(response.headers.get('location'), null);
    }
    const response = await handleAppleWebCallback(request({ state, error: 'private provider error' }), returnOrigin);
    assert.equal(response.status, 303);
    const destination = new URL(response.headers.get('location'));
    assert.equal(destination.origin, returnOrigin);
    const params = new URLSearchParams(decodeURIComponent(destination.hash.slice('#pdd-oauth='.length)));
    assert.deepEqual(Object.fromEntries(params), { provider: 'apple', state, error: 'provider_rejected' });
  }
});
