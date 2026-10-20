import test from 'node:test';
import assert from 'node:assert/strict';
import { handleSocialAdmin, publishPost } from './social.js';

function setup() {
  const account = { id:'a', name:'ПДД', active:true, targets:['youtube'], postTime:'19:00', driveFolderId:'', instagramAccountId:'ig' };
  const posts = [
    { id:'q', accountId:'a', status:'queued', targets:['youtube'], scheduledAt:'2026-12-01T16:00:00Z' },
    { id:'done', accountId:'a', status:'published', targets:['youtube'], youtubeStatus:'published' },
    { id:'busy', accountId:'a', status:'processing', targets:['youtube'], youtubeStatus:'processing' },
    { id:'partial', accountId:'a', status:'failed', targets:['instagram','youtube'], youtubeStatus:'published', instagramStatus:'failed', youtubePermalink:'https://youtube.com/shorts/existing', error:'Instagram failed' },
    { id:'other', accountId:'b', status:'queued', targets:['youtube'] },
  ];
  const data = new Map([['social:accounts',JSON.stringify([account])],['social:posts',JSON.stringify(posts)],['social:settings',JSON.stringify({workerOrigin:'https://w.test'})]]);
  const env = { INSTALLS:{ get:async k=>data.get(k)||null, put:async(k,v)=>data.set(k,v) } };
  const read = k=>JSON.parse(data.get('social:'+k));
  const call = async(path,body)=>{
    const req = new Request('https://w.test/api/admin/social/'+path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body)});
    return handleSocialAdmin(req,env,{waitUntil(){}},new URL(req.url),{jsonResponse:(body,status=200)=>Response.json(body,{status})});
  };
  return {env,read,call};
}

test('saving networks applies to waiting videos and future imports, preserving dates and publication history', async()=>{
  const {call,read}=setup(), before=read('posts');
  const res=await call('accounts',{account:{id:'a',targets:['instagram','youtube'],active:false,postTime:'18:30'},applyToQueued:true});
  assert.equal(res.status,200);assert.equal((await res.json()).updatedQueued,1);
  assert.deepEqual(read('accounts')[0].targets,['instagram','youtube']);
  assert.equal(read('accounts')[0].active,false);assert.equal(read('accounts')[0].postTime,'18:30');
  assert.deepEqual(read('posts')[0],{...before[0],targets:['instagram','youtube']});
  assert.deepEqual(read('posts').slice(1),before.slice(1));
});

test('updating defaults alone leaves existing videos intact',async()=>{
  const {call,read}=setup(),before=read('posts');
  await call('accounts',{account:{id:'a',targets:['instagram']}});
  assert.deepEqual(read('posts'),before);
});

test('empty and invalid destinations are rejected by every editor',async()=>{
  for(const targets of [[],['tiktok'],['instagram','bad'],'youtube']) {
    const {call,read}=setup(),before=read('posts');
    assert.equal((await call('accounts',{account:{id:'a',targets},applyToQueued:true})).status,400);
    assert.equal((await call('posts/update',{id:'q',targets})).status,400);
    assert.equal((await call('posts/bulk',{ids:['q'],action:'targets',targets})).status,400);
    assert.deepEqual(read('posts'),before);
  }
});

test('destination editing protects completed/in-flight videos and keeps partial publication metadata',async()=>{
  const {call,read}=setup(),before=read('posts');
  for(const id of ['busy','done'])assert.equal((await call('posts/update',{id,targets:['instagram']})).status,409);
  const res=await call('posts/bulk',{ids:['q','done','busy','partial'],action:'targets',targets:['instagram','youtube','youtube']});
  assert.equal((await res.json()).changed,2);
  assert.deepEqual(read('posts')[1],before[1]);assert.deepEqual(read('posts')[2],before[2]);assert.deepEqual(read('posts')[3],before[3]);
  assert.deepEqual(read('posts')[0].targets,['instagram','youtube']);
});

test('both targets attempt missing Instagram without re-uploading a published YouTube video',async()=>{
  const {env,call,read}=setup();
  await call('posts/update',{id:'partial',targets:['instagram','youtube']});
  const res=await publishPost(env,'partial','https://w.test');
  assert.equal(res.status,'error');
  const post=read('posts').find(p=>p.id==='partial');
  assert.match(post.error,/Instagram/);assert.equal(post.youtubeStatus,'published');
  assert.equal(post.youtubePermalink,'https://youtube.com/shorts/existing');
});


test('connection check includes configured Instagram even when only YouTube is selected',async()=>{
  const {env,call}=setup();
  const accounts=JSON.parse(await env.INSTALLS.get('social:accounts'));
  accounts[0].instagramToken='fixture';await env.INSTALLS.put('social:accounts',JSON.stringify(accounts));
  const original=globalThis.fetch,urls=[];
  globalThis.fetch=async url=>{urls.push(String(url));return Response.json({username:'pdd_fixture',account_type:'BUSINESS'});};
  try {
    const res=await call('check',{}),body=await res.json();
    assert.ok(body.checks.some(c=>c.name.startsWith('Instagram')&&c.ok));
    assert.equal(urls.length,1);assert.match(urls[0],/^https:\/\/graph.instagram.com\//);
  } finally {globalThis.fetch=original;}
});
