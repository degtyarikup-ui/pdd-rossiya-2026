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
      objects.set(code, {fetch:(url, init)=>grant.fetch(new Request(url,init))});
    }
    return objects.get(code);
  }}};
  const verifier = '0'.repeat(64);
  const identity = {id:'google_123', provider:'google', name:'Test', email:'', avatarUrl:'private'};
  const send = (op, body, user=identity) => {
    const path = '/api/auth/schools/' + op;
    const request = new Request('https://api.pdd-drive.app' + path, {method:'POST',headers:{origin:'https://pdd-drive.app'},body:JSON.stringify(body)});
    return schoolLogin(request, env, path, async () => user ? {user} : null, tokenHash);
  };
  const challenge = await tokenHash(verifier);
  assert.equal((await send('authorize',{challenge},null)).status, 401);
  const {code} = await (await send('authorize',{challenge})).json();
  assert.equal((await send('redeem',{code, verifier:'1'.repeat(64)})).status,400);
  assert.deepEqual(await (await send('redeem',{code,verifier})).json(), {provider:'google',uid:'123',name:'Test',email:''});
  assert.equal((await send('redeem',{code,verifier})).status,400);
});
