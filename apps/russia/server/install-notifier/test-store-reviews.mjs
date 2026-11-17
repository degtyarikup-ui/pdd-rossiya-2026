import { test } from 'node:test';
import assert from 'node:assert/strict';
import { StoreReviews, reviewHash, reviewCard, handleStoreReviewUpdate } from './store_reviews.js';
import { ReviewStores, StoreError } from './review_stores.js';
class Storage {
  data = new Map(); alarm = null;
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k,v) { this.data.set(k,structuredClone(v)); }
  async delete(k) { this.data.delete(k); }
  async list({prefix='',limit=Infinity}={}) { return new Map([...this.data].filter(([k])=>k.startsWith(prefix)).sort().slice(0,limit).map(([k,v])=>[k,structuredClone(v)])); }
  async getAlarm() { return this.alarm; } async setAlarm(v) { this.alarm=v; }
}
async function fixture(store='google') {
  const storage=new Storage(), calls=[], writes=[], env={CHAT_ID:'-100123',STORE_REVIEWS_ENABLED:'true',INSTALLS:{get:async()=>null,put:async()=>{}},SESSION_SECRET:'fixture'};
  const hub=new StoreReviews({storage},env);
  const r={hash:await reviewHash(store+':one'),store,id:'one',author:'Tester',text:'Needs an improvement',rating:3,date:'2026-11-17T10:00:00.000Z',response:'',responseStatus:'',cardMessage:50};
  await storage.put('r:'+r.hash,r); await storage.put('m:50',r.hash);await storage.put('topic',42);await storage.put('webhookReady',true);
  hub.tg=async(method,body)=>{calls.push({method,body});if(method==='getChatMember')return {status:'administrator'};return {message_id:100+calls.length};};
  hub.stores={ get:async()=>structuredClone(r), publish:async(review,text)=>{writes.push({review,text});return {};},replyStatus:async()=>({responseStatus:'PUBLISHED'}), status:async()=>null };
  const update=(text='Спасибо!')=>({update_id:1,message:{message_id:60,chat:{id:-100123},message_thread_id:42,from:{id:77},text,reply_to_message:{message_id:50}}});
  const draft=async()=>{await hub.update(update());return [...(await storage.list({prefix:'d:'})).values()][0];};
  const confirm=(d,action='p',user=77)=>({id:'query',data:`rv:${action}:${d.id}`,from:{id:user},message:{message_id:d.previewMessage,chat:{id:-100123},message_thread_id:42}});
  return {hub,storage,calls,writes,r,update,draft,confirm};
}
test('reply prepares only draft; repeated Telegram delivery and concurrent clicks publish once after restart',async()=>{
 const f=await fixture();const d=await f.draft();assert.equal(f.writes.length,0);
 await f.hub.update(f.update());assert.equal((await f.storage.list({prefix:'d:'})).size,1);
 assert.match(f.calls.find(x=>x.method==='sendMessage').body.reply_markup.inline_keyboard[0][0].callback_data,/^rv:p:/);
 const restarted=new StoreReviews({storage:f.storage},f.hub.env);restarted.tg=f.hub.tg;restarted.stores=f.hub.stores;
 await Promise.all([1,2].map(()=>restarted.fetch(new Request('https://reviews/update',{method:'POST',body:JSON.stringify({callback_query:f.confirm(d)})}))));
 assert.equal(f.writes.length,1);assert.equal((await f.storage.get('d:'+d.id)).status,'published');
});
test('cancel never publishes and only draft author can confirm',async()=>{
 const f=await fixture();const d=await f.draft();await f.hub.update({callback_query:f.confirm(d,'p',88)});assert.equal(f.writes.length,0);
 await f.hub.update({callback_query:f.confirm(d,'x')});await f.hub.update({callback_query:f.confirm(d)});assert.equal(f.writes.length,0);assert.equal((await f.storage.get('d:'+d.id)).status,'cancelled');
});
test('wrong chat/topic, bot and non-admin cannot create or confirm public replies',async()=>{
 const f=await fixture();for(const change of [{chat:{id:9}},{message_thread_id:1},{from:{id:77,is_bot:true}}]){const u=f.update();Object.assign(u.message,change);await f.hub.update(u);}
 assert.equal((await f.storage.list({prefix:'d:'})).size,0);
 f.hub.tg=async()=>({status:'member'});await f.hub.update(f.update());assert.equal((await f.storage.list({prefix:'d:'})).size,0);
});
test('expired and stale drafts cannot overwrite changed user review or another operator response',async()=>{
 for(const change of ['expired','review','response']){
  const f=await fixture(),d=await f.draft();if(change==='expired'){d.createdAt-=86400001;await f.storage.put('d:'+d.id,d);}else{f.hub.stores.get=async()=>({...f.r,...(change==='review'?{rating:1}:{response:'Someone else replied'})});}
  await f.hub.update({callback_query:f.confirm(d)});assert.equal(f.writes.length,0);assert.equal((await f.storage.get('d:'+d.id)).status,change==='expired'?'expired':'stale');
 }
});
test('ambiguous timeout never retries public write; definitive rejection is shown as failed',async()=>{
 for(const error of [new Error('timeout'),new StoreError(403)]){
 const f=await fixture(),d=await f.draft();f.hub.stores.publish=async()=>{f.writes.push(1);throw error;};await f.hub.update({callback_query:f.confirm(d)});await f.hub.update({callback_query:f.confirm(d)});
 assert.equal(f.writes.length,1);assert.equal((await f.storage.get('d:'+d.id)).status,error.status?'failed':'unknown');}
});
test('limits enforced before confirmation and untrusted review text cannot corrupt cards',async()=>{
 const f=await fixture();await f.hub.update(f.update('a'.repeat(351)));assert.equal((await f.storage.list({prefix:'d:'})).size,0);
 const card=reviewCard({...f.r,author:'<script>',text:'<&'.repeat(5000),response:'<&'.repeat(5000)});assert.ok(card.length<4096);assert.ok(!card.includes('<script>'));assert.ok(card.includes('&lt;script&gt;'));
});
test('failed Telegram delivery stays in durable outbox and succeeds after restart',async()=>{
 const f=await fixture();await f.storage.put('out:'+f.r.hash,{hash:f.r.hash});f.hub.tg=async()=>{throw new Error('network');};await f.hub.alarm();assert.equal((await f.storage.list({prefix:'out:'})).size,1);
 const next=new StoreReviews({storage:f.storage},f.hub.env);next.tg=async()=>({message_id:999});await next.alarm();assert.equal((await f.storage.list({prefix:'out:'})).size,0);assert.equal(await f.storage.get('m:999'),f.r.hash);
});
test('polling detects edits without duplicates and isolates failure of one store',async()=>{
 const f=await fixture();f.hub.stores.list=async function*(s){if(s==='apple')throw new StoreError(401);yield {...f.r,store:s,id:'one',text:s==='google'?'Edited':'RuStore review'};};
 await f.hub.poll();const statuses=await f.storage.get('stores');assert.equal(statuses.apple.ok,false);assert.equal(statuses.google.ok,true);assert.equal(statuses.rustore.ok,true);assert.equal((await f.storage.get('r:'+f.r.hash)).text,'Edited');
 assert.equal((await f.storage.list({prefix:'out:'})).size,2);await f.hub.poll();assert.equal((await f.storage.list({prefix:'out:'})).size,2);
});
test('adapters route replies correctly and read existing Apple response',async()=>{
 const client=new ReviewStores({STORE_REVIEW_CREDENTIALS:JSON.stringify({rustore:{package:'ru.pdd.pdd_app'}})}),calls=[];client.call=async(...args)=>{calls.push(args);return {body:{id:2}};};
 for(const store of ['apple','google','rustore'])await client.publish({store,id:'id'},'Reply');
 assert.equal(calls[0][3].data.relationships.review.data.id,'id');assert.equal(calls[1][3].replyText,'Reply');assert.equal(calls[2][3].message,'Reply');
 const r=client.normalize('apple',{id:'id',attributes:{title:'Title',body:'Body'},relationships:{response:{data:{id:'resp'}}}},[{id:'resp',attributes:{responseBody:'Existing',state:'PUBLISHED'}}]);assert.equal(r.response,'Existing');assert.equal(r.responseId,'resp');
});
test('non-review updates pass through support handler, review callbacks forward once',async()=>{
 let forwarded=0;const env={STORE_REVIEWS_ENABLED:'true',STORE_REVIEWS:{idFromName:x=>x,get:()=>({fetch:async()=>{forwarded++;return Response.json({handled:true});}})}};
 assert.equal(await handleStoreReviewUpdate({message:{text:'Support'}},env),false);assert.equal(await handleStoreReviewUpdate({callback_query:{data:'rv:p:test'}},env),true);assert.equal(forwarded,1);
});
