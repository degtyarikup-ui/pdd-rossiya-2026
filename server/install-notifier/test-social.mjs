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

async function schedulerFixture(posts = [], driveFiles = []) {
  const fixture = setup();
  const now = new Date(Date.now() + 3 * 3600000).toISOString().slice(11,13) + ':00';
  await fixture.env.INSTALLS.put('social:accounts', JSON.stringify([{ id:'a', name:'ПДД', active:true, targets:['youtube'], driveFolderId:'fixture-folder', postTime:now }]));
  await fixture.env.INSTALLS.put('social:settings', JSON.stringify({ googleApiKey:'fixture', workerOrigin:'https://w.test' }));
  await fixture.env.INSTALLS.put('social:posts', JSON.stringify(posts));
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async url => {
    requests.push(String(url));
    if (String(url).startsWith('https://www.googleapis.com/drive/v3/files?')) return Response.json({files:driveFiles});
    throw new Error('Unexpected external request: ' + String(url));
  };
  return {...fixture, requests, restore(){ globalThis.fetch=originalFetch; }};
}

test('cron imports new Drive videos during the former daily slot without publishing undated videos', async()=>{
  const {runAutoPost}=await import('./social.js');
  const originalPosts=[
    {id:'undated',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:null},
    {id:'failed-undated',accountId:'a',status:'failed',targets:['youtube'],error:'Earlier failure'},
    {id:'old-automatic-task',accountId:'a',status:'processing',targets:['youtube'],processingSince:new Date(Date.now()-4*60000).toISOString()},
    {id:'invalid',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:'invalid date'},
    {id:'future',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:new Date(Date.now()+86400000).toISOString()},
  ];
  const fixture=await schedulerFixture(originalPosts,[{id:'new-video',name:'001_new.mp4',mimeType:'video/mp4',size:'1024'}]);
  try {
    for(let i=0;i<2;i++) assert.deepEqual(await runAutoPost(fixture.env,'https://w.test'),[]);
    const after=fixture.read('posts');
    assert.equal(after.length,6,'repeated imports do not duplicate the video');
    for(const post of originalPosts)assert.deepEqual(after.find(p=>p.id===post.id),post);
    const added=after.find(p=>p.driveFileId==='new-video');
    assert.equal(added.status,'queued');assert.equal(added.scheduledAt,null);
    assert.equal(added.youtubeStatus,'queued');assert.equal(added.instagramStatus,'queued');
    assert.equal(fixture.requests.every(url=>url.startsWith('https://www.googleapis.com/drive/v3/files?')),true,'no upload or media publication requests');
  } finally {fixture.restore();}
});

test('cron only starts dated due videos; clearing a date stops automatic publishing',async()=>{
  const {runAutoPost}=await import('./social.js');
  const fixture=await schedulerFixture([
    {id:'due',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:new Date(Date.now()-60000).toISOString()},
    {id:'cleared',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:new Date(Date.now()-60000).toISOString()},
  ]);
  try {
    await fixture.call('posts/bulk',{ids:['cleared'],action:'unschedule'});
    const results=await runAutoPost(fixture.env,'https://w.test');
    assert.equal(results.length,1,'the explicit due date starts exactly one publication');
    // Deliberately absent OAuth credentials fail locally without an external upload.
    assert.equal(fixture.read('posts').find(p=>p.id==='due').status,'failed');
    assert.equal(fixture.read('posts').find(p=>p.id==='cleared').status,'queued');
    assert.equal(fixture.read('posts').find(p=>p.id==='cleared').scheduledAt,null);
    assert.equal(fixture.requests.every(url=>url.startsWith('https://www.googleapis.com/drive/v3/files?')),true);
  } finally {fixture.restore();}
});


test('cron can resume an explicitly requested manual publication without giving undated imports that permission',async()=>{
  const {runAutoPost}=await import('./social.js');
  const fixture=await schedulerFixture([{id:'manual',accountId:'a',status:'processing',targets:['youtube'],publishMode:'manual',processingSince:new Date(Date.now()-4*60000).toISOString()}]);
  try {
    await runAutoPost(fixture.env,'https://w.test');
    const post=fixture.read('posts')[0];
    assert.equal(post.status,'failed','manual request was resumed and failed locally without OAuth');
    assert.match(post.error,/YouTube/);
  } finally {fixture.restore();}
});


test('clearing the next date during a batch prevents a stale queue snapshot from publishing it',async()=>{
  const {runAutoPost}=await import('./social.js');
  const due=new Date(Date.now()-60000).toISOString();
  const fixture=await schedulerFixture([
    {id:'first',fileName:'001.mp4',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:due},
    {id:'next',fileName:'002.mp4',accountId:'a',status:'queued',targets:['youtube'],scheduledAt:due},
  ]);
  const put=fixture.env.INSTALLS.put;
  fixture.env.INSTALLS.put=async(key,value)=>{
    if(key==='social:posts') {
      const posts=JSON.parse(value);
      if(posts.find(p=>p.id==='first')?.status==='failed')posts.find(p=>p.id==='next').scheduledAt=null;
      value=JSON.stringify(posts);
    }
    return put(key,value);
  };
  try {
    assert.equal((await runAutoPost(fixture.env,'https://w.test')).length,1);
    const next=fixture.read('posts').find(p=>p.id==='next');
    assert.equal(next.status,'queued');assert.equal(next.scheduledAt,null);
  } finally {fixture.restore();}
});

for (const bulk of [false, true]) {
  test(`${bulk ? 'bulk' : 'individual'} deletion excludes the Drive file from later imports`, async () => {
    const f = await schedulerFixture([{ id: 'removed', accountId: 'a', driveFileId: 'video', fileName: 'video.mp4', status: 'failed' }],
      [{ id: 'video', name: 'video.mp4', mimeType: 'video/mp4' }, { id: 'new-video', name: 'new.mp4', mimeType: 'video/mp4' }]);
    try {
      const response = await f.call(bulk ? 'posts/bulk' : 'posts/delete', bulk
        ? { ids: ['removed'], action: 'delete' } : { id: 'removed' });
      assert.equal(response.status, 200);
      assert.deepEqual(JSON.parse(await f.env.INSTALLS.get('social:excluded:a')), ['video']);
      await runAutoPostForTest(f);
      await runAutoPostForTest(f);
      assert.deepEqual(f.read('posts').map(p => p.driveFileId), ['new-video']);
      assert.ok(f.requests.every(url => url.includes('/drive/v3/files?')));
    } finally { f.restore(); }
  });
}

async function runAutoPostForTest(f) {
  const { runAutoPost } = await import('./social.js');
  return runAutoPost(f.env, 'https://w.test');
}

test('a failed exclusion write does not remove a record without remembering the deletion', async () => {
  const f = setup(), before = f.read('posts'), put = f.env.INSTALLS.put;
  f.env.INSTALLS.put = async (key, value) => {
    if (key.startsWith('social:excluded:')) throw new Error('fixture storage unavailable');
    return put(key, value);
  };
  await assert.rejects(f.call('posts/delete', { id: 'partial' }));
  assert.deepEqual(f.read('posts'), before);
});

test('deletion keeps an in-flight publication visible until its outcome is known', async () => {
  const f = setup(), before = f.read('posts');
  assert.equal((await f.call('posts/delete', { id: 'busy' })).status, 409);
  assert.equal((await f.call('posts/bulk', { ids: ['busy', 'partial'], action: 'delete' })).status, 409);
  assert.deepEqual(f.read('posts'), before);
});

test('an invalid exclusion record stops import without recreating removed videos', async () => {
  const f = await schedulerFixture([], [{ id: 'video', name: 'video.mp4', mimeType: 'video/mp4' }]);
  try {
    await f.env.INSTALLS.put('social:excluded:a', '{broken');
    await runAutoPostForTest(f);
    assert.deepEqual(f.read('posts'), []);
    assert.ok(f.read('log').some(entry => /Импорт остановлен/.test(entry.message)));
  } finally { f.restore(); }
});

test('Drive import preserves an edit made while a caption was being downloaded', async () => {
  const f = await schedulerFixture([{ id: 'existing', accountId: 'a', driveFileId: 'old', status: 'queued', caption: 'before' }],
    [{ id: 'video', name: 'video.mp4', mimeType: 'video/mp4' }, { id: 'caption', name: 'video.txt', mimeType: 'text/plain' }]);
  const fetch = globalThis.fetch;
  globalThis.fetch = async url => {
    if (String(url).includes('/files/caption?')) {
      await f.env.INSTALLS.put('social:posts', JSON.stringify([{ ...f.read('posts')[0], caption: 'concurrent edit' }]));
      return new Response('new caption');
    }
    return fetch(url);
  };
  try {
    await runAutoPostForTest(f);
    assert.equal(f.read('posts')[0].caption, 'concurrent edit');
    assert.equal(f.read('posts')[1].caption, 'new caption');
  } finally { f.restore(); }
});

test('Drive import skips identical bytes under different IDs or names, but keeps distinct content', async () => {
  const f = await schedulerFixture([], [
    {id:'one',name:'001.mp4',mimeType:'video/mp4',md5Checksum:'a'.repeat(32)},
    {id:'copy',name:'002.mp4',mimeType:'video/mp4',md5Checksum:'a'.repeat(32)},
    {id:'different',name:'003.mp4',mimeType:'video/mp4',md5Checksum:'b'.repeat(32)},
  ]);
  try {
    await runAutoPostForTest(f);
    assert.deepEqual(f.read('posts').map(p=>p.driveFileId),['one','different']);
    await runAutoPostForTest(f);
    assert.equal(f.read('posts').length,2);
  } finally { f.restore(); }
});

test('Drive checksum dedup recognizes old records without altering their publication history', async () => {
  const existing={id:'old',accountId:'a',driveFileId:'old-file',status:'published',youtubeStatus:'published',youtubeVideoId:'old-video'};
  const f=await schedulerFixture([existing],[
    {id:'old-file',name:'old.mp4',mimeType:'video/mp4',md5Checksum:'a'.repeat(32)},
    {id:'copy',name:'copy.mp4',mimeType:'video/mp4',md5Checksum:'a'.repeat(32)},
  ]);
  try { await runAutoPostForTest(f); assert.deepEqual(f.read('posts'),[existing]); }
  finally { f.restore(); }
});

for (const bulk of [false, true]) {
  test(`${bulk ? 'bulk' : 'individual'} requeue preserves successful platform status and identity`, async () => {
    const f = setup(), before = f.read('posts').find(p => p.id === 'partial');
    const response = await f.call(bulk ? 'posts/bulk' : 'posts/mark', bulk
      ? { ids: ['partial', 'done', 'busy'], action: 'requeue' } : { id: 'partial', status: 'queued' });
    assert.equal(response.status, 200);
    const after = f.read('posts').find(p => p.id === 'partial');
    assert.equal(after.youtubeStatus, 'published');
    assert.equal(after.youtubePermalink, before.youtubePermalink);
    assert.equal(after.instagramStatus, 'queued');
    assert.equal(f.read('posts').find(p => p.id === 'done').status, 'published');
    assert.equal(f.read('posts').find(p => p.id === 'busy').status, 'processing');
  });
}

test('manual platform retry preserves an already published destination and refuses concurrent publication', async () => {
  const {call,read}=setup();
  const before=read('posts');
  assert.equal((await (await call('posts/publish-platform',{id:'partial',platform:'youtube'})).json()).ok,true);
  assert.deepEqual(read('posts'),before);
  assert.equal((await call('posts/publish-platform',{id:'busy',platform:'youtube'})).status,409);
});

for (const mode of ['missing','available','private','api-error','changed','lost-upload']) {
  test(`explicit YouTube replacement: ${mode}`,async t=>{
    const data=new Map();
    const post={id:'p',accountId:'a',driveFileId:'drive',fileName:'game_005.mp4',status:'failed',targets:['youtube'],youtubeStatus:'failed',youtubeNeedsReview:true,youtubeVideoId:'R7sWTbIi7c8',youtubePermalink:'https://youtube.com/shorts/R7sWTbIi7c8',instagramStatus:'published'};
    data.set('social:posts',JSON.stringify([post]));
    data.set('social:accounts',JSON.stringify([{id:'a',targets:['youtube']}]));
    data.set('social:settings',JSON.stringify({googleClientId:'fixture',googleClientSecret:'fixture',googleRefreshToken:'fixture-refresh'}));
    data.set('social:google_token:fixture-refresh'.replace('fixture-refresh','fixture-refresh'.slice(-12)),JSON.stringify({token:'fixture',exp:Date.now()+3600000}));
    const env={INSTALLS:{get:async k=>data.get(k)||null,put:async(k,v)=>data.set(k,v)}};
    let uploads=0;const tasks=[];
    const current=()=>JSON.parse(data.get('social:posts'))[0];
    t.mock.method(globalThis,'fetch',async url=>{
      const u=String(url);
      if(u.includes('/channels?'))return Response.json({items:[{id:'channel'}]});
      if(u.includes('/videos?') && !u.includes('/upload/')){
        if(mode==='api-error')return Response.json({error:{}},{status:503});
        if(mode==='changed')data.set('social:posts',JSON.stringify([{...post,title:'changed'}]));
        return Response.json({items:['available','private'].includes(mode)?[{id:post.youtubeVideoId,snippet:{channelId:'channel'},status:{uploadStatus:'processed',privacyStatus:mode==='private'?'private':'public'}}]:[]});
      }
      if(u.includes('/drive/v3/files/'))return new Response(new Uint8Array(2000));
      if(u.includes('/upload/youtube/'))return new Response('',{headers:{location:'https://upload.fixture/session'}});
      if(u==='https://upload.fixture/session'){uploads++;if(mode==='lost-upload')throw new Error('lost');return Response.json({id:'newVideo123'});}
      throw new Error('Unexpected fixture call');
    });
    const call=async confirmReplacement=>{
      const req=new Request('https://w.test/api/admin/social/posts/replace-youtube',{method:'POST',body:JSON.stringify({id:'p',confirmReplacement})});
      return handleSocialAdmin(req,env,{waitUntil:p=>tasks.push(p)},new URL(req.url),{jsonResponse:(b,s=200)=>Response.json(b,{status:s})});
    };
    assert.equal((await call(false)).status,400);
    await call(true);await Promise.all(tasks);
    assert.equal(uploads,['missing','lost-upload'].includes(mode)?1:0, JSON.stringify(current()));
    assert.equal(current().instagramStatus,'published');
    if(mode==='missing'){
      assert.equal(current().youtubeVideoId,'newVideo123');assert.equal(current().youtubeStatus,'published');
      assert.equal(current().youtubePreviousAttempts[0].videoId,post.youtubeVideoId);
      assert.equal(current().youtubeReplacementAttempt.stage,'published');
    } else if(mode==='available')assert.equal(current().youtubeStatus,'published');
    else if(mode!=='lost-upload')assert.equal(current().youtubeVideoId,post.youtubeVideoId);
    if(mode==='lost-upload'){await call(true);await Promise.all(tasks);assert.equal(uploads,1);assert.equal(current().youtubeNeedsReview,true);}
  });
}
