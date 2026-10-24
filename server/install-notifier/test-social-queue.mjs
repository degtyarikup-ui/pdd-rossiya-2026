import test from 'node:test';
import assert from 'node:assert/strict';
import { SocialPublisher } from './social_guard.js';
import { readSocialPosts, saveSocialPosts } from './social_queue.js';

class Storage {
  data = new Map(); alarm = null;
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k,v) { this.data.set(k,structuredClone(v)); }
  async delete(k) { this.data.delete(k); }
  async list({prefix=''}) { return new Map([...this.data].filter(([k])=>k.startsWith(prefix)).map(([k,v])=>[k,structuredClone(v)])); }
  async getAlarm() { return this.alarm; }
  async setAlarm(t) { this.alarm=t; }
  async transaction(fn) { const saved=structuredClone(this.data),alarm=this.alarm;try{return await fn(this);}catch(e){this.data=saved;this.alarm=alarm;throw e;} }
}
function fixture(posts=[{id:'one',status:'queued',title:'original'},{id:'two',status:'queued'}]) {
  const storage=new Storage();let mirror=JSON.stringify(posts),writes=0,unavailable=false;
  const env={SOCIAL_QUEUE_REQUIRED:'true',INSTALLS:{get:async()=>mirror,put:async(_,v)=>{if(unavailable)throw Error('offline');writes++;mirror=v;}}};
  let object=new SocialPublisher({storage},env);
  env.SOCIAL_PUBLISHER={idFromName:s=>s,get:()=>({fetch:(url,options)=>object.fetch(new Request(url,options))})};
  return {env,storage,restart:()=>object=new SocialPublisher({storage},env),alarm:()=>object.alarm(),
    writes:()=>writes,mirror:()=>JSON.parse(mirror),offline:v=>unavailable=v,stale:v=>mirror=JSON.stringify(v)};
}
test('queue imports once, survives restart, and ignores a stale KV replica',async()=>{
  const f=fixture(),posts=await readSocialPosts(f.env);posts[0].status='published';await saveSocialPosts(f.env,posts);
  assert.equal(f.writes(),0);f.restart();f.stale([]);
  assert.equal((await readSocialPosts(f.env))[0].status,'published');assert.ok(f.storage.alarm);
  await f.alarm();assert.equal(f.writes(),1);assert.equal(f.mirror()[0].status,'published');
});
test('concurrent edits merge disjoint fields and rows without overwriting publication results',async()=>{
  const f=fixture(),publisher=await readSocialPosts(f.env),admin=await readSocialPosts(f.env);
  publisher[0].status='published';admin[0].title='edited';admin[1].scheduledAt='2026-10-25T16:00:00Z';
  await Promise.all([saveSocialPosts(f.env,publisher),saveSocialPosts(f.env,admin)]);
  assert.deepEqual(await readSocialPosts(f.env),[{id:'one',status:'published',title:'edited'},{id:'two',status:'queued',scheduledAt:'2026-10-25T16:00:00Z'}]);
});
test('stale writes to the same field fail atomically; replaying the exact write is idempotent',async()=>{
  const f=fixture(),first=await readSocialPosts(f.env),stale=await readSocialPosts(f.env);
  first[0].status='processing';await saveSocialPosts(f.env,first);await saveSocialPosts(f.env,first);
  stale[0].status='published';stale[1].status='failed';
  await assert.rejects(saveSocialPosts(f.env,stale),{code:'ERR_SOCIAL_QUEUE_CONFLICT'});
  assert.deepEqual((await readSocialPosts(f.env)).map(p=>p.status),['processing','queued']);
});
test('stale deletion cannot erase a publication that started concurrently',async()=>{
  const f=fixture(),remove=await readSocialPosts(f.env),publisher=await readSocialPosts(f.env);
  publisher[0].status='processing';await saveSocialPosts(f.env,publisher);
  await assert.rejects(saveSocialPosts(f.env,remove,remove.slice(1)),{code:'ERR_SOCIAL_QUEUE_CONFLICT'});
  assert.equal((await readSocialPosts(f.env)).length,2);
});
test('KV outage cannot roll back committed queue state; alarm retains recovery and later projects it',async()=>{
  const f=fixture(),posts=await readSocialPosts(f.env);f.offline(true);
  posts[0].status='published';await saveSocialPosts(f.env,posts);await f.alarm();f.restart();
  assert.ok(f.storage.alarm);assert.equal((await readSocialPosts(f.env))[0].status,'published');
  f.offline(false);await f.alarm();assert.equal(f.mirror()[0].status,'published');assert.equal(await f.storage.get('queue:dirty'),undefined);
});
test('failed or malformed legacy reads never initialize an empty authoritative queue',async()=>{
  for(const get of [async()=>{throw Error('offline');},async()=>'{invalid',async()=>JSON.stringify([{id:'x'},{id:'x'}])]){
    const f=fixture();f.env.INSTALLS.get=get;
    await assert.rejects(readSocialPosts(f.env));assert.equal(await f.storage.get('queue:initialized'),undefined);
  }
});
test('queue records are stored separately, including a queue larger than one SQLite value',async()=>{
  const f=fixture(Array.from({length:300},(_,i)=>({id:String(i),caption:'я'.repeat(400)})));
  const posts=await readSocialPosts(f.env);posts[299].status='published';await saveSocialPosts(f.env,posts);f.restart();
  assert.equal((await readSocialPosts(f.env)).find(p=>p.id==='299').status,'published');
  assert.ok([...f.storage.data.values()].every(v=>JSON.stringify(v).length<128*1024));
});
test('overlapping imports cannot add a second row for the same Drive file or checksum',async()=>{
  for(const identity of [{driveFileId:'same-file'},{contentMd5:'a'.repeat(32)}]){
    const f=fixture([]),a=await readSocialPosts(f.env),b=await readSocialPosts(f.env);
    await saveSocialPosts(f.env,a,[{id:'a',accountId:'account',...identity}]);
    await assert.rejects(saveSocialPosts(f.env,b,[{id:'b',accountId:'account',...identity}]),{code:'ERR_SOCIAL_QUEUE_CONFLICT'});
    assert.equal((await readSocialPosts(f.env)).length,1);
  }
});
