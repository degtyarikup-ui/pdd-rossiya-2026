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
