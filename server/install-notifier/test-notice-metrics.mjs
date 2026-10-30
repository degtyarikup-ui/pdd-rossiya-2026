import test from 'node:test';
import assert from 'node:assert/strict';
import { acceptNoticeMetrics, noticeMetricsForAdmin } from './notice_metrics.js';
import { StatsBuffer } from './stats_buffer.js';
import { flushBufferedStats } from './worker.js';
import worker from './worker.js';

const fixture = 'test-only';
const campaignId = 'a069e042-5b7b-40a0-b15e-b80c4444ce1d';
const now = Date.now();
const campaign = { id: campaignId, kind: 'banner', enabled: true, app: 'ru', platform: 'android', createdAt: now - 10000, expiresAt: now + 10000 };
function setup() {
  const durable = new Map(), kv = new Map(); let alarm = null;
  const storage = {
    get: async k => structuredClone(durable.get(k)),
    put: async (k,v) => durable.set(k, structuredClone(v)),
    delete: async k => { for (const key of Array.isArray(k) ? k : [k]) durable.delete(key); },
    list: async ({prefix,limit=Infinity}) => new Map([...durable].filter(([k])=>k.startsWith(prefix)).slice(0,limit)),
    getAlarm: async()=>alarm, setAlarm:async v=>{alarm=v;}, deleteAlarm: async()=>{alarm=null;},
    transaction: async fn=>fn(storage),
  };
  const env = { SESSION_SECRET:fixture, INSTALLS:{get:async k=>kv.get(k),put:async(k,v)=>kv.set(k,v)} };
  const buffer = new StatsBuffer({storage},env);
  env.STATS={idFromName:()=>'', get:()=>({fetch:(url,init)=>buffer.fetch(new Request(url,init))})};
  const records = [];
  const deps = {
    readSession: async()=>({user:{id:'google_123',email:'test@example.test'}}),
    notificationRequest:async()=>Response.json({messages:[campaign]}),
    trackStats:async(env,ctx,item)=>{records.push(item);await buffer.fetch(new Request('https://stats/enqueue',{method:'POST',body:JSON.stringify(item)}));},
  };
  const send = (events, overrides={}) => acceptNoticeMetrics(new Request('https://test/api/notifications/events',{method:'POST',body:JSON.stringify({installId:'a'.repeat(32),platform:'android',events,...overrides})}),env,deps,now);
  return {env,deps,send,buffer,kv,records,durable};
}
const event = (type='view', extra={})=>({campaignId,event:type,ts:now,...extra});
test('unique account views and clicks deduplicate across retries and devices in the durable buffer',async()=>{
  const {send,buffer,kv,records}=setup();
  assert.equal((await send([event('click')])).status,200);
  await send([event('click'),event()],{installId:'b'.repeat(32)});
  await buffer.flush();
  assert.deepEqual(JSON.parse(kv.get('notice_metrics:'+campaignId)),{view:1,click:1});
  assert.ok(records.every(r=>!JSON.stringify(r).includes('google_123')&&!JSON.stringify(r).includes('test@example.test')));
});
test('guest installations remain distinct and malformed events fail before enqueue',async()=>{
  const {send,deps,buffer,kv}=setup();deps.readSession=async()=>null;
  await send([event()]);await send([event()],{installId:'b'.repeat(32)});
  assert.equal((await send([event('arbitrary')])).status,400);
  assert.equal((await send([event('view',{ts:now-31*86400000})])).status,400);
  assert.equal((await send([event()],{installId:'bad'})).status,400);
  await buffer.flush();assert.equal(JSON.parse(kv.get('notice_metrics:'+campaignId)).view,2);
});
test('wrong platform, unknown campaign and out-of-period events do not count',async()=>{
  const {send,records}=setup();
  await send([event()],{platform:'ios'});await send([event('view',{campaignId:crypto.randomUUID()})]);
  await send([event('view',{ts:now-20000})]);assert.equal(records.length,0);
});
test('delayed events for disabled banners count, personal recipients remain protected',async()=>{
  const {send,deps,records}=setup();
  deps.notificationRequest=async()=>Response.json({messages:[{...campaign,enabled:false,target:'another@example.test'}]});
  await send([event()]);assert.equal(records.length,0);
  deps.notificationRequest=async()=>Response.json({messages:[{...campaign,enabled:false}]});
  await send([event()]);assert.equal(records.length,1);
});
test('admin gets only aggregated metrics; batch produces one KV write per campaign',async()=>{
  const writes=[];
  await flushBufferedStats({INSTALLS:{get:async()=>null,put:async(k,v)=>writes.push([k,v])}},[
    {kind:'notice',campaignId,event:'view'}, {kind:'notice',campaignId,event:'click'}, {kind:'notice',campaignId,event:'view'},
  ]);
  assert.equal(writes.length,1);assert.deepEqual(JSON.parse(writes[0][1]),{view:2,click:1});
  const response=await noticeMetricsForAdmin({INSTALLS:{get:async()=>writes[0][1]}},Response.json({messages:[campaign]}));
  assert.deepEqual((await response.json()).messages[0].metrics,{view:2,click:1});
});
test('public metrics route requires configured app secret',async()=>{
  for(const env of [{},{SHARED_SECRET:fixture}]) {
    const r=await worker.fetch(new Request('https://test/api/notifications/events',{method:'POST',body:'{}'}),env);
    assert.equal(r.status,401);
  }
});
test('windows and pushes report views and taps like banners',async()=>{
  for(const kind of ['popup','push','news']) {
    const {send,deps,records}=setup();
    deps.notificationRequest=async()=>Response.json({messages:[{...campaign,kind}]});
    await send([event('click')]);
    assert.deepEqual(records.map(r=>r.event),['view','click'],kind);
  }
});

test('category metrics use the authoritative profile and keep premium views', async () => {
  const {send,deps,records,kv}=setup();
  deps.notificationRequest=async()=>Response.json({messages:[{...campaign,audiences:['premium']}]});
  kv.set('user:google_123',JSON.stringify({id:'google_123',isPremium:true,premiumExpiresAt:new Date(now+86400000).toISOString()}));
  await send([event('click')]);
  assert.deepEqual(records.map(r=>r.event),['view','click']);
  records.length=0;
  deps.notificationRequest=async()=>Response.json({messages:[{...campaign,audiences:['registered']}]});
  await send([event()]);assert.equal(records.length,0);
  kv.set('user:google_123',JSON.stringify({id:'google_123',isPremium:true,premiumExpiresAt:new Date(now-1000).toISOString()}));
  await send([event()]);assert.equal(records.length,1);
  records.length=0;
  deps.readSession=async()=>null;
  await send([event()],{isPremium:true,premiumActive:true});assert.equal(records.length,0);
  deps.notificationRequest=async()=>Response.json({messages:[{...campaign,audiences:['guest']}]});
  await send([event()]);assert.equal(records.length,1);
});
