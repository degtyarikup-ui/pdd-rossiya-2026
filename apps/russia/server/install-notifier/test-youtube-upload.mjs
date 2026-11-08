import test from 'node:test';
import assert from 'node:assert/strict';
import { SocialPublisher, withSocialPublicationLease } from './social_guard.js';
import { resumableYoutubeUpload } from './youtube_upload.js';

function fixture(t, { changed=false, probe='partial' }={}) {
  const map=new Map();const storage={get:async k=>structuredClone(map.get(k)),put:async(k,v)=>map.set(k,structuredClone(v)),delete:async k=>map.delete(k)};
  let object=new SocialPublisher({storage}),initializations=0,downloads=0,uploads=0,probes=0;
  const sent=[];const env={SOCIAL_PUBLISHER_REQUIRED:'true',SOCIAL_PUBLISHER:{idFromName:s=>s,get:()=>({fetch:(u,o)=>object.fetch(new Request(u,o))})}};
  t.mock.method(globalThis,'fetch',async(u,options)=>{
    const range=options.headers['content-range'];
    if(range==='bytes */2000'){
      probes++;
      if(probe==='complete')return Response.json({id:'accepted123'});
      if(probe==='expired')return new Response('{}',{status:404});
      if(probe==='invalid')return new Response('',{status:308,headers:{range:'bytes=10-999'}});
      if(probe==='unavailable')return new Response('{}',{status:503});
      return new Response('',{status:308,headers:{range:'bytes=0-999'}});
    }
    uploads++;sent.push({range,length:options.body.byteLength});
    if(uploads===1)throw new TypeError('lost response');
    return Response.json({id:'accepted123'});
  });
  const run=()=>withSocialPublicationLease(env,'a',owned=>resumableYoutubeUpload(owned,{id:'p',accountId:'a',driveFileId:'drive'},async()=> 'fixture',async()=>{
    downloads++;return new Uint8Array(2000).fill(changed&&downloads>1?1:0).buffer;
  },async()=>{initializations++;return 'https://www.googleapis.com/upload/youtube/v3/videos?upload_id=fixture';}));
  return {run,restart:()=>object=new SocialPublisher({storage}),counts:()=>({initializations,downloads,uploads,probes}),sent};
}
test('interrupted YouTube resumes only missing bytes in the original session',async t=>{
  const f=fixture(t);await assert.rejects(f.run(),{code:'ERR_YT_PROCESSING'});f.restart();
  assert.equal((await f.run()).videoId,'accepted123');
  assert.deepEqual(f.counts(),{initializations:1,downloads:2,uploads:2,probes:1});
  assert.deepEqual(f.sent,[{range:'bytes 0-1999/2000',length:2000},{range:'bytes 1000-1999/2000',length:1000}]);
});
test('accepted YouTube upload with lost response is restored without downloading or sending bytes again',async t=>{
  const f=fixture(t,{probe:'complete'});await assert.rejects(f.run(),{code:'ERR_YT_PROCESSING'});f.restart();
  assert.equal((await f.run()).videoId,'accepted123');await f.run();
  assert.deepEqual(f.counts(),{initializations:1,downloads:1,uploads:1,probes:1});
});
for(const probe of ['expired','invalid','unavailable'])test('YouTube '+probe+' never starts a second session or guesses a byte offset',async t=>{
  const f=fixture(t,{probe});await assert.rejects(f.run());f.restart();await assert.rejects(f.run());
  assert.deepEqual(f.counts(),{initializations:1,downloads:1,uploads:1,probes:1});
});
test('changed source bytes cannot be mixed into an existing upload',async t=>{
  const f=fixture(t,{changed:true});await assert.rejects(f.run());f.restart();
  await assert.rejects(f.run(),{code:'ERR_YT_PUBLICATION_UNCONFIRMED'});assert.equal(f.counts().uploads,1);
});
