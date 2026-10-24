import test from 'node:test';
import assert from 'node:assert/strict';
import { runAutoPost, publishPost } from './social.js';
import { SocialPublisher } from './social_guard.js';
import { readSocialPosts } from './social_queue.js';

class Storage {
  data=new Map();alarm=null;
  async get(k){return structuredClone(this.data.get(k));}async put(k,v){this.data.set(k,structuredClone(v));}
  async delete(k){this.data.delete(k);}async list({prefix=''}){return new Map([...this.data].filter(([k])=>k.startsWith(prefix)).map(([k,v])=>[k,structuredClone(v)]));}
  async getAlarm(){return this.alarm;}async setAlarm(t){this.alarm=t;}async transaction(fn){return fn(this);}
}
function fixture(t,{ig='missing',yt='missing',postPatch={},queue=true,failLog=false,failMediaSave=false}={}){
  const post={id:'p',accountId:'a',fileName:'game_006.mp4',driveFileId:'drive',streamToken:'fixture',caption:'caption',targets:['instagram','youtube'],
    status:'failed',instagramStatus:'failed',youtubeStatus:'failed',instagramNeedsReview:true,instagramReviewReason:'media_unavailable',youtubeNeedsReview:true,
    instagramContainerId:'100',instagramMediaId:'101',instagramPermalink:'https://www.instagram.com/reel/old/',youtubeVideoId:'oldVideo123',
    scheduledAt:new Date(Date.now()-60000).toISOString(),publishedAt:null,...postPatch};
  const next={id:'next',accountId:'a',fileName:'game_007.mp4',status:'queued',targets:['instagram','youtube'],instagramStatus:'queued',youtubeStatus:'queued',scheduledAt:new Date(Date.now()+86400000).toISOString()};
  const data=new Map([['social:posts',JSON.stringify([post,next])],['social:accounts',JSON.stringify([{id:'a',name:'Fixture',active:true,targets:['instagram','youtube'],instagramAccountId:'123',instagramToken:'fixture',instagramTokenUpdatedAt:new Date().toISOString()}])],
    ['social:settings',JSON.stringify({googleClientId:'fixture',googleClientSecret:'fixture',googleRefreshToken:'fixture-refresh'})],
    ['social:google_token:'+ 'fixture-refresh'.slice(-12),JSON.stringify({token:'fixture',exp:Date.now()+3600000})]]);
  const objects=new Map(),storage=new Map();let published=false,savedFailure=false;
  const env={SOCIAL_PUBLISHER_REQUIRED:'true',SOCIAL_QUEUE_REQUIRED:queue?'true':'false',INSTALLS:{get:async k=>data.get(k)??null,put:async(k,v)=>{
    if(failLog&&k==='social:log')throw Error('log unavailable');
    if(failMediaSave&&!savedFailure&&k==='social:posts'&&JSON.parse(v)[0].instagramMediaId==='201'){savedFailure=true;throw Error('save interrupted');}
    data.set(k,v);
  }}};
  env.SOCIAL_PUBLISHER={idFromName:s=>s,get:id=>({fetch:(url,options)=>{
    if(!objects.has(id)){if(!storage.has(id))storage.set(id,new Storage());objects.set(id,new SocialPublisher({storage:storage.get(id)},env));}
    return objects.get(id).fetch(new Request(url,options));
  }})};
  const calls=[];
  t.mock.method(globalThis,'fetch',async(input,options={})=>{
    const url=new URL(input),method=options.method||'GET';calls.push({url,method,body:options.body});
    if(url.hostname==='graph.instagram.com'){
      if(method==='POST'&&url.pathname.endsWith('/media'))return Response.json({id:'200'});
      if(method==='POST'&&url.pathname.endsWith('/media_publish')){published=true;return Response.json({id:'201'});}
      if(url.pathname.endsWith('/me'))return Response.json({user_id:'123'});
      if(url.pathname.endsWith('/123/media'))return Response.json({data:[{id:'other'}]});
      if(url.pathname.endsWith('/100'))return Response.json({status_code:'PUBLISHED'});
      if(url.pathname.endsWith('/200'))return Response.json({status_code:published?'PUBLISHED':'FINISHED'});
      if(url.pathname.endsWith('/201'))return Response.json({id:'201',permalink:'https://www.instagram.com/reel/new/'});
      if(url.pathname.endsWith('/101')){
        if(ig==='missing')return Response.json({error:{code:100,error_subcode:33}},{status:400});
        if(ig==='unauthorized')return Response.json({error:{code:190}},{status:401});
        if(ig==='temporary')return Response.json({error:{}},{status:503});
        return Response.json({id:'101',permalink:post.instagramPermalink});
      }
    }
    if(url.pathname.endsWith('/channels'))return Response.json({items:[{id:'channel'}]});
    if(url.pathname==='/youtube/v3/videos'){
      if(yt==='temporary')return Response.json({error:{}},{status:503});
      return Response.json({items:yt==='missing'?[]:[{id:post.youtubeVideoId,snippet:{channelId:'channel'},status:{uploadStatus:'processed',privacyStatus:yt==='private'?'private':'public'}}]});
    }
    if(url.pathname.startsWith('/drive/v3/files/'))return new Response(new Uint8Array(2000));
    if(url.pathname.startsWith('/upload/youtube/')&&method==='POST')return new Response('',{headers:{location:'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=fixture'}});
    if(url.pathname.startsWith('/upload/youtube/')&&method==='PUT')return Response.json({id:'newVideo123'});
    throw Error('Unexpected provider request '+url.pathname);
  });
  return {env,post,next,calls,restart:()=>objects.clear(),current:async()=> (await readSocialPosts(env)).find(p=>p.id==='p'),
    creates:platform=>calls.filter(c=>c.method==='POST'&&(platform==='instagram'?c.url.pathname.endsWith('/media'):c.url.pathname.startsWith('/upload/youtube/'))).length};
}
test('scheduled unavailable legacy IDs are archived and replaced exactly once; future queue is untouched',async t=>{
  const f=fixture(t);await runAutoPost(f.env,'https://fixture.invalid');
  let p=await f.current();assert.equal(p.status,'published');assert.equal(p.instagramMediaId,'201');assert.equal(p.youtubeVideoId,'newVideo123');
  assert.equal(p.instagramPreviousAttempts[0].mediaId,'101');assert.equal(p.youtubePreviousAttempts[0].videoId,'oldVideo123');
  assert.equal(p.scheduledAt,f.post.scheduledAt);assert.deepEqual((await readSocialPosts(f.env)).find(p=>p.id==='next'),f.next);
  f.restart();await runAutoPost(f.env,'https://fixture.invalid');
  assert.equal(f.creates('instagram'),1);assert.equal(f.creates('youtube'),1);
});
test('already visible scheduled publications are restored through reads without replacement',async t=>{
  const f=fixture(t,{ig:'available',yt:'available'});await runAutoPost(f.env,'https://fixture.invalid');
  const p=await f.current();assert.equal(p.status,'published');assert.equal(p.instagramMediaId,'101');assert.equal(p.youtubeVideoId,'oldVideo123');
  assert.equal(f.creates('instagram'),0);assert.equal(f.creates('youtube'),0);assert.equal(p.instagramPreviousAttempts,undefined);
});
for(const mode of ['unauthorized','temporary'])test('Instagram '+mode+' does not authorize replacement, while YouTube still completes',async t=>{
  const f=fixture(t,{ig:mode,yt:'available'});await runAutoPost(f.env,'https://fixture.invalid');
  const p=await f.current();assert.equal(p.instagramMediaId,'101');assert.equal(f.creates('instagram'),0);assert.equal(p.youtubeStatus,'published');
});
test('private YouTube video is held for review and never uploaded again',async t=>{
  const f=fixture(t,{ig:'available',yt:'private'});await runAutoPost(f.env,'https://fixture.invalid');
  const p=await f.current();assert.equal(p.youtubeVideoId,'oldVideo123');assert.equal(p.youtubeNeedsReview,true);assert.equal(f.creates('youtube'),0);
});
test('no date and future dates cannot replace legacy IDs or release new videos',async t=>{
  for(const date of [null,new Date(Date.now()+86400000).toISOString()]){
    const f=fixture(t,{postPatch:{scheduledAt:date}});await runAutoPost(f.env,'https://fixture.invalid');
    assert.equal(f.calls.length,0);assert.equal((await f.current()).instagramMediaId,'101');
  }
});
test('failed log projection cannot change a successfully published result',async t=>{
  const f=fixture(t,{ig:'available',yt:'available',failLog:true});await runAutoPost(f.env,'https://fixture.invalid');
  assert.equal((await f.current()).status,'published');
});
test('durable Instagram media receipt recovers a lost queue save without repeating media_publish',async t=>{
  const f=fixture(t,{queue:false,failMediaSave:true,postPatch:{targets:['instagram'],instagramMediaId:null,instagramContainerId:'200',instagramNeedsReview:false,youtubeStatus:'published',status:'processing'}});
  assert.equal((await publishPost(f.env,'p','https://fixture.invalid')).status,'error');f.restart();
  assert.equal((await publishPost(f.env,'p','https://fixture.invalid')).status,'ok');
  assert.equal((await f.current()).instagramMediaId,'201');assert.equal(f.calls.filter(c=>c.method==='POST'&&c.url.pathname.endsWith('/media_publish')).length,1);
});
