import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TelegramAuthState, handleTelegramAuthRequest, handleTelegramAuthCheck, processTelegramAuthMessage } from './telegram_auth.js';
function fixture() {
  const objects = new Map();
  const env = { SHARED_SECRET: crypto.randomUUID(), INSTALLS: {get:async()=>null}, TG_AUTH: {
    idFromName: n => n,
    get(n) {
      if (!objects.has(n)) {
        const data = new Map(); let tail = Promise.resolve();
        const storage = {get:async k=>structuredClone(data.get(k)), put:async(k,v)=>data.set(k,structuredClone(v)), delete:async k=>data.delete(k), deleteAll:async()=>data.clear(), setAlarm:async()=>{}};
        storage.transaction = fn => {const p=tail.then(()=>fn(storage));tail=p.catch(()=>{});return p;};
        objects.set(n, new TelegramAuthState({storage}));
      }
      return {fetch:(url,opts)=>objects.get(n).fetch(new Request(url,opts))};
    }
  }};
  const request = body => new Request('https://test/api/auth/telegram/check',{method:'POST',headers:{'x-install-secret':env.SHARED_SECRET},body:JSON.stringify(body)});
  const check = (body, sign=async()=> 'session')=>handleTelegramAuthCheck(request(body),env,sign);
  return {env,check,objects,async start(protocolVersion=2){const res=await handleTelegramAuthRequest(request({protocolVersion}),env);assert.equal(res.status,200);return res.json();},async confirm(nonce,id=123){await processTelegramAuthMessage({text:'/start '+nonce,chat:{type:'private',id},from:{id,first_name:'Test'}},env,true);}};
}
test('v2 keeps one durable result after a lost response; proof never enters bot link',async()=>{
 const f=fixture(), c=await f.start(); assert.match(c.verifier,/^[a-f0-9]{64}$/);assert.ok(!c.botUrl.includes(c.verifier));
 assert.equal((await f.check({nonce:c.nonce})).status,403);
 assert.equal((await f.check({nonce:c.nonce,verifier:'wrong'})).status,403);
 assert.equal((await (await f.check(c)).json()).status,'pending');await f.confirm(c.nonce);
 let signs=0;const sign=async()=>`session-${++signs}`;
 const first=await (await f.check(c,sign)).json();const retry=await (await f.check(c,sign)).json();
 assert.deepEqual(retry,first);assert.equal(signs,1);
 await f.confirm(c.nonce,456);assert.deepEqual(await (await f.check(c,sign)).json(),first);
 await f.objects.get(c.nonce).alarm();assert.equal((await (await f.check(c)).json()).status,'expired');
});
test('failure before signing does not consume v2 confirmation',async()=>{
 const f=fixture(), c=await f.start();await f.confirm(c.nonce);
 await assert.rejects(f.check(c,async()=>{throw Error('unavailable');}));
 assert.equal((await (await f.check(c)).json()).status,'confirmed');
});
test('concurrent checks return the exact same committed session',async()=>{
 const f=fixture(), c=await f.start();await f.confirm(c.nonce);let seq=0;
 const responses=await Promise.all(Array.from({length:8},()=>f.check(c,async()=>`session-${++seq}`)));
 const results=await Promise.all(responses.map(r=>r.json()));
 for(const result of results) assert.deepEqual(result,results[0]);
});
test('expired proof cannot retrieve or mint a session',async()=>{
 const f=fixture(), c=await f.start();await f.confirm(c.nonce);const original=Date.now;
 try{Date.now=()=>original()+301000;assert.equal((await (await f.check(c)).json()).status,'expired');}finally{Date.now=original;}
});

test('legacy signing failure keeps confirmation until a successful one-time exchange',async()=>{
 const f=fixture(), c=await f.start(1);await f.confirm(c.nonce);
 await assert.rejects(f.check(c,async()=>{throw Error('temporary signing failure');}));
 assert.equal((await (await f.check(c)).json()).status,'confirmed');
 assert.equal((await (await f.check(c)).json()).status,'expired');
});
