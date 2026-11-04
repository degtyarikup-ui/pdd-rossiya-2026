import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { ADMIN_DATA_CLIENT_JS } from './admin_data.js';

const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return {promise,resolve,reject}; };
const json = (value, status=200) => new Response(JSON.stringify(value), {status,headers:{'content-type':'application/json'}});
const tick = () => new Promise(resolve=>setImmediate(resolve));
function fixture(handler, session=()=>json({ok:true})) {
  const calls=[];
  const sandbox={URL,AbortController,Response,Request,structuredClone,setTimeout,clearTimeout,console,
    location:{href:'https://admin.example/admin',origin:'https://admin.example'},
    document:{getElementById(){return null;},addEventListener(){}},localStorage:{removeItem(){}},
    async fetch(input,opts={}){calls.push([input,opts]);return input==='/api/admin/session'?session():handler(input,opts);}
  };
  sandbox.window=sandbox;vm.runInNewContext(ADMIN_DATA_CLIENT_JS,sandbox);
  return {...sandbox,api:sandbox.AdminData,calls};
}

test('authenticated reads deduplicate, retain isolated snapshots, key by filters and refresh explicitly',async()=>{
  let value=1;const gate=deferred();
  const app=fixture(async()=>{await gate.promise;return json({value});});
  const values=[];
  const first=app.api.load('/api/admin/users',{onData:d=>{d.value=99;values.push(d.value);}});
  const second=app.api.load('/api/admin/users');await tick();
  assert.equal(app.calls.length,2); // one session and one shared GET
  gate.resolve();assert.equal((await first).value,1);assert.equal((await second).value,1);
  assert.equal((await app.api.load('/api/admin/users')).value,1);assert.equal(app.calls.length,2);
  value=2;
  await app.api.load('/api/admin/users',{force:true,onData:(d,m)=>values.push([d.value,m.cached])});
  assert.deepEqual(values,[99,[1,true],[2,false]]);
  await app.api.load('/api/admin/users?filter=premium');assert.equal(app.calls.length,4);
});

test('stale data renders before a failed refresh; failures never replace cache',async()=>{
  let failed=false;const app=fixture(()=>failed?json({error:'offline'},503):json({value:42}));
  await app.api.load('/api/admin/economy/stats?period=month');failed=true;
  const events=[];
  await assert.rejects(app.api.load('/api/admin/economy/stats?period=month',{ttl:0,onData:(d,m)=>events.push([d.value,m.cached,m.refreshing])}),/offline/);
  assert.deepEqual(events,[[42,true,true]]);
  assert.equal((await app.api.load('/api/admin/economy/stats?period=month')).value,42);
});

test('a mutation retires old GETs; their callers wait for the write and render the fresh result only',async()=>{
  const getGate=deferred(),writeGate=deferred();let reads=0,value=1;
  const app=fixture(async(url,opts)=>{
    if(opts.method==='POST'){await writeGate.promise;value=2;return json({ok:true});}
    if(++reads===1){await getGate.promise;return json({value:1});}
    return json({value});
  });
  const values=[];const load=app.api.load('/api/admin/tasks',{onData:d=>values.push(d.value)});
  await tick();const write=app.fetch('/api/admin/tasks',{method:'POST',body:'{}'});
  getGate.resolve();await tick();assert.deepEqual(values,[]);assert.equal(reads,1);
  writeGate.resolve();await write;assert.equal((await load).value,2);assert.deepEqual(values,[2]);
  assert.equal((await app.api.load('/api/admin/tasks')).value,2);assert.equal(reads,2);
});

test('logout clears snapshots and rejects late responses without callbacks',async()=>{
  const gate=deferred();const app=fixture(async(url,opts)=>{
    if(opts.method==='POST')return json({ok:true});
    await gate.promise;return json({privateValue:7});
  });
  const seen=[];const load=app.api.load('/api/admin/users',{onData:d=>seen.push(d)});
  const rejected=assert.rejects(load,{name:'AbortError'});
  await tick();await app.fetch('/api/admin/logout',{method:'POST'});gate.resolve();await rejected;
  assert.deepEqual(seen,[]);
  await app.api.load('/api/admin/users');
  assert.equal(app.calls.filter(([u])=>u==='/api/admin/session').length,2);
  assert.equal(app.calls.filter(([u])=>u==='/api/admin/users').length,2);
});

test('aborting one consumer leaves the shared GET available to another',async()=>{
  const gate=deferred();const app=fixture(async()=>{await gate.promise;return json({value:9});});
  const controller=new AbortController(),seen=[];
  const first=app.api.load('/api/admin/blog',{signal:controller.signal,onData:d=>seen.push(d)});
  const second=app.api.load('/api/admin/blog');await tick();
  const rejected=assert.rejects(first,{name:'AbortError'});controller.abort();await rejected;
  gate.resolve();assert.equal((await second).value,9);assert.deepEqual(seen,[]);
  assert.equal(app.calls.filter(([u])=>u==='/api/admin/blog').length,1);
});

test('cache is bounded and external requests do not invalidate admin data',async()=>{
  const app=fixture(()=>json({value:1}));
  for(let i=0;i<34;i++)await app.api.load('/api/admin/stats?days='+i);
  await app.fetch('https://outside.example/action',{method:'POST'});
  let count=app.calls.length;await app.api.load('/api/admin/stats?days=33');assert.equal(app.calls.length,count);
  await app.api.load('/api/admin/stats?days=0');assert.equal(app.calls.length,count+1);
  await assert.rejects(app.api.load('https://outside.example/api/admin/users'),/Недопустимый/);
});


test('a short consumer deadline does not abort a longer reader sharing the same URL',async()=>{
  const gate=deferred();const app=fixture(async()=>{await gate.promise;return json({value:3});});
  const short=app.api.load('/api/admin/stats',{timeout:10});
  const long=app.api.load('/api/admin/stats',{timeout:10000});
  await assert.rejects(short,{name:'TimeoutError'});
  gate.resolve();assert.equal((await long).value,3);
  assert.equal(app.calls.filter(([u])=>u==='/api/admin/stats').length,1);
});

test('a denied session never reads private endpoints or invokes data callbacks',async()=>{
  const gate=deferred();const app=fixture(()=>json({privateValue:1}),()=>gate.promise);
  const seen=[];const a=app.api.load('/api/admin/users',{onData:d=>seen.push(d)});
  const b=app.api.load('/api/admin/economy/stats');
  const checks=Promise.all([assert.rejects(a),assert.rejects(b)]);
  await tick();assert.equal(app.calls.length,1);
  gate.resolve(json({error:'unauthorized'},401));await checks;
  assert.equal(app.calls.length,1);assert.deepEqual(seen,[]);
});

test('application errors and rejected payloads do not poison a successful snapshot',async()=>{
  let mode=0;const app=fixture(()=>json(mode===0?{value:4}:mode===1?{ok:false,error:'incomplete'}:{broken:true}));
  await app.api.load('/api/admin/users');mode=1;
  await assert.rejects(app.api.load('/api/admin/users',{force:true}),/incomplete/);
  assert.equal((await app.api.load('/api/admin/users')).value,4);mode=2;
  await assert.rejects(app.api.load('/api/admin/users',{force:true,onData:data=>{if(data.broken)throw new Error('bad payload');}}),/bad payload/);
  assert.equal((await app.api.load('/api/admin/users')).value,4);
});
