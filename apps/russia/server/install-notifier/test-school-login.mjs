import { test } from 'node:test';
import assert from 'node:assert/strict';
import { schoolLogin, SchoolLoginGrant } from './school_login.js';
import { tokenHash } from './user_auth.js';

test('a grant is bound to its verifier and can be redeemed once', async () => {
  const objects = new Map();
  const env = {SCHOOL_GRANTS: {idFromName: v => v, get(code) {
    if (!objects.has(code)) {
      const entries = new Map();
      const storage = {get:k=>entries.get(k),put:(k,v)=>entries.set(k,v),delete:k=>entries.delete(k),
        setAlarm() {}, transaction(fn) { return fn(this); }};
      const grant = new SchoolLoginGrant({ storage });
      objects.set(code, {async fetch(url, init) {
        const response = await grant.fetch(new Request(url, init));
        // Network responses have immutable headers in workerd.
        const immutableHeaders = Response.redirect('https://school-grant/').headers;
        Object.defineProperty(response, 'headers', {value: immutableHeaders});
        return response;
      }});
    }
    return objects.get(code);
  }}};
  const verifier = '0'.repeat(64);
  const identity = {id:'google_123', provider:'google', name:'Test', email:'', avatarUrl:'private'};
  const send = (op, body, user=identity) => {
    const path = '/api/auth/schools/' + op;
    const request = new Request('https://api.pdd-drive.app' + path, {method:'POST',headers:{origin:'https://pdd-drive.app'},body:JSON.stringify(body)});
    return schoolLogin(request, env, path, async () => user ? {user} : null, tokenHash).then(response => {
      response.headers.set('Access-Control-Allow-Origin', '*');
      return response;
    });
  };
  const challenge = await tokenHash(verifier);
  assert.equal((await send('authorize',{challenge},null)).status, 401);
  const {code} = await (await send('authorize',{challenge})).json();
  assert.equal((await send('redeem',{code, verifier:'1'.repeat(64)})).status,400);
  assert.deepEqual(await (await send('redeem',{code,verifier})).json(), {provider:'google',uid:'123',name:'Test',email:''});
  assert.equal((await send('redeem',{code,verifier})).status,400);
});

test('group membership uses the account from the verified app session', async () => {
  const {schoolGroup} = await import('./school_login.js');
  const body = {name: 'Анна', invite: 'ABCD', version: '0', accountId: 'wrong'};
  const request = () => new Request('https://api.pdd-drive.app/api/auth/schools/group/join',
    { method: 'POST', body: JSON.stringify(body) });
  const received = [];
  const env = { SCHOOL_PORTAL: {getByName(name) {
    assert.equal(name, 'schools-v1');
    return {async studentGroup(...args) {
      received.push(args);
      return JSON.stringify({status: 409, body: {error: 'membership_changed'}});
    }};
  }}};
  assert.equal((await schoolGroup(request(), env, 'join', async () => null)).status, 401);
  const result = await schoolGroup(request(), env, 'join', async () => ({user:{id:'apple_123',provider:'apple'}}));
  assert.equal(result.status, 409);
  assert.equal(received.length, 1);
  assert.deepEqual(received[0].slice(0, 2), ['apple_123', 'join']);
  assert.equal(JSON.parse(received[0][2]).accountId, undefined);
});
