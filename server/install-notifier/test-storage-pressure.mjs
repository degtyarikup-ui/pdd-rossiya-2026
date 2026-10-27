import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import {StatsBuffer} from './stats_buffer.js';
import {accountRead} from './account_state.js';
import {errorCode} from './diagnostics.js';
import {AccountState} from './account_state.js';
import {NotificationsState} from './notifications.js';
import {TrafficState} from './traffic_state.js';
import {SocialPublisher} from './social_guard.js';
import {TelegramQueue} from './telegram_queue.js';
import {fixture,MemoryStorage,request,session,identity} from './fixture-account.mjs';

test('durable queues preserve result, ordering and error recovery without retaining response payloads',async()=>{
  for(const Class of [AccountState,NotificationsState,TrafficState,StatsBuffer,TelegramQueue,SocialPublisher]){
    const obj=new Class({storage:new MemoryStorage()},{}),payload=Response.json({progress:'x'.repeat(128*1024)});
    if(Class===SocialPublisher)obj.handle=fn=>fn();
    const run=fn=>Class===SocialPublisher?obj.fetch(fn):obj.serial(fn);
    let release;
    const held=new Promise(r=>{release=r;});
    const order=[];
    const first=run(async()=>{order.push(1);await held;return payload;});
    const second=run(async()=>{order.push(2);throw new Error('expected');});
    const rejected=assert.rejects(second,/expected/);
    release();
    assert.equal(await first,payload);
    await rejected;
    assert.deepEqual(order,[1,2]);
    assert.equal(await obj.tail,undefined,Class.name+' must keep only completion');
    assert.equal(await run(()=>payload),payload);
    assert.equal(await obj.tail,undefined,Class.name+' must release the successful response');
  }
});

function usageFixture() {
  const f=fixture(),storage=new MemoryStorage(),buffer=new StatsBuffer({storage},f.env),calls=[];
  f.env.STATS={idFromName:s=>s,get:()=>({fetch:async(u,o)=>{calls.push(new URL(u).pathname);return buffer.fetch(new Request(u,o));}})};
  const body={installId:'a'.repeat(32),platform:'ios',events:Array.from({length:50},(_,i)=>({id:i.toString(16).padStart(32,'0'),ts:Date.now(),feature:'tickets'}))};
  return {...f,storage,buffer,calls,body,post:()=>worker.fetch(request('/api/usage',body),f.env)};
}
test('50 usage events use one durable invocation and repeated batches count once',async()=>{
  const f=usageFixture();
  assert.equal((await f.post()).status,200);
  assert.deepEqual(f.calls,['/enqueue-batch']);
  assert.equal((await f.storage.list({prefix:'q:'})).size,50);
  assert.equal((await f.post()).status,200);
  assert.equal((await f.storage.list({prefix:'q:'})).size,50);
  assert.equal(await f.buffer.flush(),true);
  const day=[...f.env.INSTALLS.data].find(([k])=>k.startsWith('day:'));
  assert.equal(JSON.parse(day[1]).usage.tickets.starts,50);
});
test('partially failed batch transaction accepts nothing; retry accepts all original events',async()=>{
  const f=usageFixture();f.storage.failCommit=true;
  assert.equal((await f.post()).status,500);
  assert.equal((await f.storage.list({prefix:'q:'})).size,0);
  assert.equal((await f.storage.list({prefix:'seen:'})).size,0);
  assert.equal((await f.post()).status,200);
  assert.equal((await f.storage.list({prefix:'q:'})).size,50);
});
test('lost batch acceptance response does not double count or replay inside the same API call',async()=>{
  const f=usageFixture(),get=f.env.STATS.get;
  let lost=true;
  f.env.STATS.get=()=>({fetch:async(u,o)=>{const r=await get().fetch(u,o);if(lost){lost=false;throw Object.assign(new Error('overloaded'),{overloaded:true});}return r;}});
  assert.equal((await f.post()).status,503);
  assert.equal(f.calls.length,1);
  assert.equal((await f.post()).status,200);
  assert.equal((await f.storage.list({prefix:'q:'})).size,50);
});
test('only explicit legacy 404 falls back to single-event acceptance',async()=>{
  const f=usageFixture(),get=f.env.STATS.get;
  f.env.STATS.get=()=>({fetch:(u,o)=>new URL(u).pathname==='/enqueue-batch'?new Response('not found',{status:404}):get().fetch(u,o)});
  assert.equal((await f.post()).status,200);
  assert.equal(f.calls.length,50);
  assert.equal((await f.storage.list({prefix:'q:'})).size,50);
});
test('flush bounds a large backlog to 200 events and retains remaining events for its alarm',async t=>{
  const f=usageFixture(),base=Date.now();
  for(let i=0;i<201;i++)await f.buffer.fetch(new Request('https://stats/enqueue',{method:'POST',body:JSON.stringify({id:'event'+i,kind:'usage',feature:'tickets',installation:'a'.repeat(32),ts:base})}));
  assert.equal(await f.buffer.flush(),false);
  assert.equal((await f.storage.list({prefix:'q:'})).size,1);
  assert.ok(await f.storage.getAlarm());
  t.mock.method(Date,'now',()=>base+66000);
  assert.equal(await f.buffer.flush(),true);
  const day=[...f.env.INSTALLS.data].find(([k])=>k.startsWith('day:'));
  assert.equal(JSON.parse(day[1]).usage.tickets.starts,201);
});
test('expiry scans pages and projection drains in bounded batches without losing premium or records',async()=>{
  const f=fixture(),premium={...identity(),isPremium:true,premiumExpiresAt:'2099-01-01T00:00:00Z'};
  await f.env.INSTALLS.put('user:google_123',JSON.stringify(premium));
  await accountRead(f.env,'google_123','user:google_123');
  const storage=f.states.get('google_123'),obj=f.objects.get('google_123'),now=Date.now();
  const expired=[];
  for(let i=0;i<61;i++){
    const key='revoked_session:google_123:'+i.toString(16).padStart(64,'0');expired.push(key);
    await storage.put('doc:'+key,{key,value:'1',expiresAt:now-1000,options:{}});
  }
  const limits=[],original=storage.list.bind(storage);
  storage.list=async options=>{if(['doc:','projection:','index:'].includes(options?.prefix)){assert.ok(options.limit<=25);limits.push(options);}return original(options);};
  await obj.expireRecords();
  assert.ok(limits.filter(v=>v.prefix==='doc:').length>=3);
  for(const key of expired)assert.equal(await storage.get('doc:'+key),undefined);
  await obj.flush();assert.equal([...storage.data.keys()].filter(k=>k.startsWith('projection:')).length,36);
  await obj.flush();await obj.flush();
  assert.equal([...storage.data.keys()].filter(k=>k.startsWith('projection:')).length,0);
  assert.equal(JSON.parse(await accountRead(f.env,'google_123','user:google_123')).isPremium,true);
});
test('SQLITE_NOMEM becomes 503 without retrying a write or exposing an internal error',async()=>{
  assert.equal(errorCode(new Error('out of memory: SQLITE_NOMEM')),'durable_memory_exhausted');
  for(const [path,body]of [['/api/user/status',undefined],['/api/user/progress/sync',{userId:'google_123',progress:{}}]]){
    const f=fixture(),token=await session(f.env),calls=[];
    const before={...identity(),isPremium:true};await f.env.INSTALLS.put('user:google_123',JSON.stringify(before));
    f.env.ACCOUNTS={idFromName:s=>s,get:()=>({fetch:async(input)=>{calls.push(new URL(input.url||input).pathname);throw new Error('out of memory: SQLITE_NOMEM');}})};
    const r=await worker.fetch(request(path,body,token),f.env);
    assert.equal(r.status,503);
    assert.equal(r.headers.get('Retry-After'),'5');
    assert.equal(calls.filter(p=>p===path).length,1);
    assert.doesNotMatch(await r.text(),/SQLITE|memory/);
    assert.deepEqual(JSON.parse(await f.env.INSTALLS.get('user:google_123')),before);
  }
});
