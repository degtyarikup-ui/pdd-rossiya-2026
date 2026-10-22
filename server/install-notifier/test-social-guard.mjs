import test from 'node:test';
import assert from 'node:assert/strict';
import { SocialPublisher, socialGuard, beginSocialWrite, completeSocialWrite, withSocialPublicationLease } from './social_guard.js';
import { publishPost } from './social.js';
import { TelegramQueue } from './telegram_queue.js';
import { sendTelegram } from './worker.js';

class Storage {
  data = new Map(); alarm = null;
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k,v) { this.data.set(k,structuredClone(v)); }
  async delete(k) { return this.data.delete(k); }
  async list({prefix='',limit=Infinity}={}) { return new Map([...this.data].filter(([k])=>k.startsWith(prefix)).sort().slice(0,limit)); }
  async getAlarm() { return this.alarm; }
  async setAlarm(v) { this.alarm=v; }
  async transaction(fn) { return fn(this); }
}
function guardFixture() {
  const storage = new Storage();
  let guard = new SocialPublisher({storage});
  const env = {SOCIAL_PUBLISHER_REQUIRED:'true',SOCIAL_PUBLISHER:{idFromName:s=>s,get:()=>({fetch:(url,options)=>guard.fetch(new Request(url,options))})}};
  return {env,storage,restart:()=>{guard=new SocialPublisher({storage});}};
}
test('one durable lease per account, release ownership, restart and expiry',async t=>{
  const f=guardFixture(),first=await socialGuard(f.env,'account','/claim');
  assert.equal((await socialGuard(f.env,'account','/claim')).busy,true);
  f.restart();
  assert.equal((await socialGuard(f.env,'account','/claim')).busy,true);
  await assert.rejects(socialGuard(f.env,'account','/release',{owner:'wrong'}));
  await socialGuard(f.env,'account','/release',first);
  const second=await socialGuard(f.env,'account','/claim');
  assert.notEqual(first.owner,second.owner);
  await f.storage.put('lease',{owner:second.owner,until:Date.now()-1});
  assert.ok((await socialGuard(f.env,'account','/claim')).owner);
});
test('ambiguous writes remain blocked after restart and a new queue-row ID',async()=>{
  const f=guardFixture(),p={id:'one',driveFileId:'drive-file',accountId:'account'};
  await withSocialPublicationLease(f.env,'account',async env=>{
    assert.equal((await beginSocialWrite(env,p,'youtube')).result.state,'new');
  });
  f.restart();
  await withSocialPublicationLease(f.env,'account',async env=>{
    await assert.rejects(beginSocialWrite(env,{...p,id:'new-row'},'youtube'),{code:'ERR_YT_PUBLICATION_UNCONFIRMED'});
  });
});
test('accepted outcome survives KV loss and coordinator restart',async()=>{
  const f=guardFixture(),p={id:'one',driveFileId:'drive-file',accountId:'account'};
  await withSocialPublicationLease(f.env,'account',async env=>{
    const write=await beginSocialWrite(env,p,'instagram');
    await completeSocialWrite(env,p,write,'123456');
  });
  f.restart();
  await withSocialPublicationLease(f.env,'account',async env=>{
    assert.equal((await beginSocialWrite(env,p,'instagram')).result.id,'123456');
  });
});
test('missing required coordinator fails closed before work',async()=>{
  let ran=false;
  await assert.rejects(withSocialPublicationLease({SOCIAL_PUBLISHER_REQUIRED:'true'},'account',()=>{ran=true;}));
  assert.equal(ran,false);
});

test('overlapping account publications run only one job',async()=>{
  const f=guardFixture();
  let release,entered;
  const started=new Promise(r=>{entered=r;});
  const first=withSocialPublicationLease(f.env,'a',async()=>{entered();await new Promise(r=>{release=r;});return 'done';});
  await started;
  let secondRan=false;
  assert.equal((await withSocialPublicationLease(f.env,'a',()=>{secondRan=true;})).status,'processing');
  assert.equal(secondRan,false);
  release();assert.equal(await first,'done');
});

test('Instagram lost create response stops automatic replacement after restart',async t=>{
  const f=guardFixture(),data=new Map([
    ['social:posts',JSON.stringify([{id:'p',accountId:'a',driveFileId:'drive',fileName:'test.mp4',streamToken:'fixture',status:'processing',targets:['instagram'],instagramStatus:'queued'}])],
    ['social:accounts',JSON.stringify([{id:'a',name:'Test',targets:['instagram'],instagramAccountId:'123',instagramToken:'fixture'}])],
  ]);
  f.env.INSTALLS={get:async k=>data.get(k)||null,put:async(k,v)=>data.set(k,v)};
  let creates=0;
  t.mock.method(globalThis,'fetch',async()=>{creates++;throw new TypeError('lost response');});
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'error');
  f.restart();
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'error');
  assert.equal(creates,1);
  assert.equal(JSON.parse(data.get('social:posts'))[0].instagramNeedsReview,true);
});

function youtubeFixture(t,mode) {
  const f=guardFixture();
  const post={id:'p',accountId:'a',driveFileId:'drive',fileName:'test.mp4',status:'processing',targets:['youtube'],youtubeStatus:'queued'};
  const data=new Map([
    ['social:posts',JSON.stringify([post])],
    ['social:accounts',JSON.stringify([{id:'a',name:'Test',targets:['youtube']}])],
    ['social:settings',JSON.stringify({googleClientId:'fixture',googleClientSecret:'fixture',googleRefreshToken:'fixture-refresh'})],
  ]);
  data.set('social:google_token:'+ 'fixture-refresh'.slice(-12),JSON.stringify({token:'fixture',exp:Date.now()+3600000}));
  let putCalls=0,initCalls=0,failSave=mode==='save-fails';
  f.env.INSTALLS={get:async k=>data.get(k)||null,put:async(k,v)=>{
    if(k==='social:posts'&&failSave&&JSON.parse(v)[0].youtubeStatus==='published'){failSave=false;throw new Error('KV save interrupted');}
    data.set(k,v);
  }};
  t.mock.method(globalThis,'fetch',async(url,options={})=>{
    if(String(url).includes('/drive/v3/files/'))return new Response(new Uint8Array(2000),{headers:{'content-type':'video/mp4'}});
    if(String(url).includes('/upload/youtube/')){
      initCalls++;
      if(mode==='init-fails'&&initCalls===1)return new Response('{}',{status:503});
      return new Response('',{headers:{location:'https://upload.fixture/session'}});
    }
    if(String(url)==='https://upload.fixture/session'){
      putCalls++;
      if(mode==='lost-response')throw new TypeError('response lost after acceptance');
      return Response.json({id:'video123'});
    }
    throw new Error('Unexpected fixture network call');
  });
  return {...f,post,current:()=>JSON.parse(data.get('social:posts'))[0],counts:()=>({putCalls,initCalls})};
}
test('YouTube lost upload response cannot upload again, even after restart',async t=>{
  const f=youtubeFixture(t,'lost-response');
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'error');
  f.restart();
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'error');
  assert.equal(f.counts().putCalls,1);
  assert.equal(f.current().youtubeNeedsReview,true);
});
test('YouTube successful upload with failed KV save recovers without new upload',async t=>{
  const f=youtubeFixture(t,'save-fails');
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'error');
  f.restart();
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'ok');
  assert.equal(f.counts().putCalls,1);
  assert.equal(f.current().youtubeVideoId,'video123');
  assert.equal(f.current().youtubeNeedsReview,false);
});
test('failed YouTube session initialization can safely retry without a public-upload intent',async t=>{
  const f=youtubeFixture(t,'init-fails');
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'error');
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'ok');
  assert.equal(f.counts().putCalls,1);
});
test('published platform is never uploaded by a retry of the other platform',async t=>{
  const f=youtubeFixture(t,'ok');
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'ok');
  assert.equal((await publishPost(f.env,'p','https://fixture')).status,'ok');
  assert.equal(f.counts().putCalls,1);
});

test('social notices group concurrent duplicates for an hour, survive restart, keep new failures and purchases',async()=>{
  const storage=new Storage(),env={BOT_TOKEN:'fixture',CHAT_ID:'fixture'};
  let q=new TelegramQueue({storage},env);
  env.TELEGRAM={idFromName:s=>s,get:()=>({fetch:(u,o)=>q.fetch(new Request(u,o))})};
  const opts={topic:'errors',errorGroupKey:'social:'+'a'.repeat(64)};
  await Promise.all(Array.from({length:12},()=>sendTelegram(env,'Failure',null,opts)));
  assert.equal((await storage.list({prefix:'q:'})).size,1);
  q=new TelegramQueue({storage},env);
  await sendTelegram(env,'Failure',null,opts);
  assert.equal((await storage.list({prefix:'q:'})).size,1);
  await sendTelegram(env,'Different failure',null,{...opts,errorGroupKey:'social:'+'b'.repeat(64)});
  await sendTelegram(env,'Purchase success');
  assert.equal((await storage.list({prefix:'q:'})).size,3);
  const groups=await storage.get('social:error_groups');
  groups[opts.errorGroupKey].at-=3600001;
  await storage.put('social:error_groups',groups);
  await sendTelegram(env,'Still failing',null,opts);
  assert.match([...await storage.list({prefix:'q:'})].at(-1)[1].text,/Повторов с прошлого сообщения: 12/);
});
