import test from 'node:test';
import assert from 'node:assert/strict';
import { AccountState } from './account_state.js';
import { MemoryStorage, MemoryKV } from './fixture-account.mjs';

for (const remote of [false, true]) {
  test(`local SQLite failure resets volatile instance only (remote=${remote})`, async () => {
    const storage = new MemoryStorage();
    await storage.put('confirmed', { progress: 'kept', premium: '2030-01-01' });
    const before = structuredClone(storage.data);
    let resets = 0, executions = 0;
    const state = { storage, abort: () => { resets++; throw new Error('fixture reset'); } };
    const object = new AccountState(state, { INSTALLS: new MemoryKV() });
    const error = Object.assign(new Error('out of memory: SQLITE_NOMEM'), { remote });
    await assert.rejects(object.serial(() => { executions++; throw error; }));
    assert.equal(resets, remote ? 0 : 1);
    assert.equal(executions, 1, 'never replay an uncertain write');
    assert.deepEqual(storage.data, before);
    const reopened = new AccountState(state, {});
    assert.deepEqual(await reopened.serial(() => storage.get('confirmed')), before.get('confirmed'));
  });
}

test('ordinary errors and overload never reset an account', async () => {
  const object = new AccountState({ abort: () => assert.fail('unexpected reset') }, {});
  for (const error of [new Error('invalid input'), Object.assign(new Error('overloaded'), {overloaded:true}),
    new Error('internal error; reference = opaque')]) {
    await assert.rejects(object.serial(() => {throw error;}), e => e === error);
  }
  assert.equal(await object.serial(() => 42), 42);
});

test('local SQLite failure in projection cleanup is not swallowed by background retry', async () => {
  const storage = new MemoryStorage();
  const kv = new MemoryKV();
  await storage.put('projection:user:fixture', {key:'user:fixture'});
  await storage.put('doc:user:fixture', {key:'user:fixture', value:'{"isPremium":true}', epoch:'1', options:{}});
  const originalGet = storage.get.bind(storage);
  storage.get = key => { if(key==='doc:user:fixture')throw new Error('out of memory: SQLITE_NOMEM'); return originalGet(key); };
  let resets=0;
  const object=new AccountState({storage,abort:()=>{resets++;throw new Error('fixture reset');}}, {INSTALLS:kv});
  await assert.rejects(object.alarm());
  assert.equal(resets,1);
  assert.ok(storage.data.has('projection:user:fixture'));
  assert.ok(await storage.getAlarm(), 'persisted alarm survives and can finish after reset');
  storage.get=originalGet;
  await new AccountState({storage}, {INSTALLS:kv}).alarm();
  assert.equal(await kv.get('user:fixture'), '{"isPremium":true}');
});
