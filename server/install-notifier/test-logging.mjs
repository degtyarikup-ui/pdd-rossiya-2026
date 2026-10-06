import { test } from 'node:test';
import assert from 'node:assert/strict';
import { inflateSync } from 'node:zlib';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import worker, { buildUserRegistrationMessage, buildPremiumPurchaseMessage, buildReportMessage, dailyChartPoints, sendDailyReport, finishPendingDailyReport, dailyReportEnd, buildDailyReportMessage, flushBufferedStats } from './worker.js';
import { renderDailyChart, pngBase64 } from './daily_chart.js';
import { metadataFields, attributedDestination } from './attribution.js';
import { TelegramQueue } from './telegram_queue.js';
import { signSession } from './user_auth.js';

class Storage {
  data=new Map(); alarm=null;
  async get(k){ return this.data.get(k); }
  async put(k,v){ this.data.set(k,structuredClone(v)); }
  async delete(k){ this.data.delete(k); }
  async list({prefix='',limit=Infinity}={}){return new Map([...this.data].filter(([k])=>k.startsWith(prefix)).sort().slice(0,limit));}
  async getAlarm(){return this.alarm;}
  async setAlarm(v){this.alarm=v;}
  async transaction(fn){return fn(this);}
}
function setup(){
  const env={INSTALLS:new Storage(), BOT_TOKEN:'test',CHAT_ID:'test',SHARED_SECRET:'test',SESSION_SECRET:'test'};
  const state={storage:new Storage()},queue=new TelegramQueue(state,env);
  env.TELEGRAM={idFromName:s=>s,get:()=>({fetch:(u,o)=>queue.fetch(new Request(u,o))})};
  return {env,state,queue};
}
test('marketing attribution is distinct from store, sanitized and HTML-escaped',()=>{
  const u={id:'google_test',platform:'android',installStore:'Google Play',marketingSource:'threads',marketingCampaign:'release_48',attributionMethod:'play_referrer',device:'<device>',name:'<name>',ipCountry:'RU',ipCity:'<city>'};
  const msg=buildUserRegistrationMessage(u,42);
  assert.doesNotMatch(msg,/Новая регистрация|<b>Имя:<\/b>/);
  assert.match(msg,/Источник:<\/b> Threads · release_48/);assert.match(msg,/Установка:<\/b> Google Play/);
  assert.match(msg,/&lt;device&gt;/);assert.doesNotMatch(msg,/<device>|<name>|<city>/);
  assert.doesNotMatch(buildUserRegistrationMessage({platform:'ios'},1),/Источник:/);
  assert.equal(metadataFields({marketingSource:'__proto__',marketingCampaign:'<script>',device:'x'.repeat(400)}).marketingSource,'unknown');
  assert.equal(metadataFields({device:'x'.repeat(400)}).device.length,100);
  assert.ok(buildPremiumPurchaseMessage({...u,tierName:'<b>fake</b>'}).startsWith('⭐⭐⭐⭐⭐⭐⭐⭐\n'));
  assert.match(buildPremiumPurchaseMessage({...u,tierName:'<b>fake</b>'}),/&lt;b&gt;fake&lt;\/b&gt;/);
  assert.ok(buildReportMessage({message:'<complaint>'}).startsWith('🚩🚩🚩🚩🚩🚩🚩🚩\n'));
});
test('Google Play and web receive campaign tags; iOS receives aggregate ct without guessed identity',()=>{
  const play=new URL(attributedDestination('https://play.google.com/store/apps/details?id=ru.pdd.pdd_app','threads','launch'));
  assert.equal(play.searchParams.get('id'),'ru.pdd.pdd_app');
  assert.equal(new URLSearchParams(play.searchParams.get('referrer')).get('utm_source'),'threads');
  assert.equal(new URL(attributedDestination('https://apps.apple.com/ru/app/id6792369533','threads','launch')).searchParams.get('ct'),'launch');
  assert.equal(new URL(attributedDestination('https://app.pdd-drive.ru/','threads','launch')).searchParams.get('utm_source'),'threads');
});
test('landing link used by user preserves Threads through clicks into stores',()=>{
  const listeners={},events=[];
  const context={URL,URLSearchParams,window:{location:{search:'?ref=threads',pathname:'/links/',hostname:'pdd-drive.ru'}},document:{referrer:'',readyState:'loading',addEventListener:(n,f)=>{listeners[n]=f;}},navigator:{userAgent:'Android',sendBeacon:(u,b)=>events.push(JSON.parse(b))},sessionStorage:{getItem:()=>null,setItem:()=>{}},localStorage:{getItem:()=>true},setTimeout};
  vm.runInNewContext(readFileSync(new URL('../../web_landing/ru/assets/tracker.js', import.meta.url),'utf8'),context);
  assert.equal(events[0].source,'threads');
  const anchor={tagName:'A',href:'https://play.google.com/store/apps/details?id=ru.pdd.pdd_app'};
  listeners.click({target:anchor});
  assert.equal(events.at(-1).source,'threads');assert.equal(events.at(-1).type,'click');
  assert.equal(new URLSearchParams(new URL(anchor.href).searchParams.get('referrer')).get('utm_source'),'threads');
});
test('first known acquisition survives subsequent profile sync and missing fields',async()=>{
  const {env,state}=setup(),id='google_test';
  const token=await signSession(env,{user:{id,provider:'google',email:'test@example.org'},expiresAt:Date.now()+60000,generation:''});
  const call=body=>worker.fetch(new Request('https://test/api/user/sync',{method:'POST',headers:{'x-install-secret':'test',authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify({id,provider:'google',name:'Test',app:'ru',platform:'android',...body})}),env);
  assert.equal((await call({marketingSource:'threads',marketingCampaign:'launch',attributionMethod:'play_referrer',device:'Phone',installStore:'Google Play'})).status,200);
  assert.equal((await call({marketingSource:'instagram',marketingCampaign:'later'})).status,200);
  const saved=JSON.parse(await env.INSTALLS.get('user:'+id));
  assert.equal(saved.marketingSource,'threads');assert.equal(saved.marketingCampaign,'launch');assert.equal(saved.device,'Phone');
  assert.equal((await state.storage.list({prefix:'q:'})).size,1,'no duplicate registration');
});
test('seven-day chart uses 22–22 slots and missing history is explicitly unavailable',async()=>{
  const {env}=setup();await env.INSTALLS.put('slot:2026-10-03:night',JSON.stringify({installs:5,registrations:2}));await env.INSTALLS.put('slot:2026-10-03:day',JSON.stringify({installs:8,registrations:6}));
  const points=await dailyChartPoints(env,new Date('2026-10-03T19:00:00Z'));
  assert.equal(points.at(-1).installs,13);assert.equal(points.at(-1).registrations,8);assert.equal(points[0].available,false);
  const png=await renderDailyChart(points);
  assert.equal(Buffer.from(png).subarray(0,8).toString('hex'),'89504e470d0a1a0a');
  let offset=8,idat=[];while(offset<png.length){const length=new DataView(png.buffer,png.byteOffset+offset).getUint32(0);if(Buffer.from(png.subarray(offset+4,offset+8)).toString()==='IDAT')idat.push(png.subarray(offset+8,offset+8+length));offset+=length+12;}
  assert.equal(inflateSync(Buffer.concat(idat)).length,961*520);assert.ok(pngBase64(png).length<100000);
});
test('daily report photo and text enqueue atomically, deduplicate and survive photo rejection',async()=>{
  const {env,state,queue}=setup(),original=globalThis.fetch;
  try{
    await sendDailyReport(env,new Date('2026-10-03T19:00:00Z'),'daily:2026-10-03');
    const entries=await state.storage.list({prefix:'q:'});assert.ok(entries.size>=1);assert.ok(entries.values().next().value.photoBase64);
    await sendDailyReport(env,new Date('2026-10-03T19:00:00Z'),'daily:2026-10-03');assert.equal((await state.storage.list({prefix:'q:'})).size,entries.size);
    let calls=0;
    globalThis.fetch=async(url,options)=>{calls++;assert.match(url,/sendPhoto$/);assert.ok(options.body instanceof FormData);assert.equal(options.body.get('photo').type,'image/png');return Response.json({ok:false},{status:400});};
    await queue.alarm();assert.equal(calls,1);assert.equal((await state.storage.list({prefix:'q:'})).values().next().value.photoBase64,undefined);
    globalThis.fetch=async(url)=>{assert.match(url,/sendMessage$/);return Response.json({ok:true});};await queue.alarm();assert.equal((await state.storage.list({prefix:'q:'})).size,entries.size-1);
  }finally{globalThis.fetch=original;}
});
test('public tracker cannot forge purchases, reports or registrations',async()=>{
  const {env}=setup();for(const type of ['purchase','report','registration']){
    const r=await worker.fetch(new Request('https://test/api/track',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({type})}),env);assert.equal(r.status,400);
  }
});
test('daily report waits for stats backlog and retries without a duplicate summary',async()=>{
  const {env,state}=setup();
  await env.INSTALLS.put('tg:daily_pending',JSON.stringify({scheduledTime:Date.parse('2026-10-03T19:00:00Z')}));
  let complete=false;
  env.STATS={idFromName:s=>s,get:()=>({fetch:async()=>new Response('stats',{status:complete?200:202})})};
  await finishPendingDailyReport(env);
  assert.ok(await env.INSTALLS.get('tg:daily_pending'));assert.equal((await state.storage.list({prefix:'q:'})).size,0);
  complete=true;await finishPendingDailyReport(env);
  assert.equal(await env.INSTALLS.get('tg:daily_pending'),undefined);
  const count=(await state.storage.list({prefix:'q:'})).size;assert.ok(count>0);
  await finishPendingDailyReport(env);assert.equal((await state.storage.list({prefix:'q:'})).size,count);
});
test('photo delivery retains durable bytes and retries Telegram rate limits after restart',async()=>{
  const {env,state,queue}=setup(),original=globalThis.fetch;
  try{
    const png=await renderDailyChart(Array.from({length:7},()=>({date:'2026-10-03',available:false})));
    await queue.fetch(new Request('https://queue/enqueue',{method:'POST',body:JSON.stringify({text:'Report',photoBase64:pngBase64(png)})}));
    globalThis.fetch=async()=>Response.json({ok:false,parameters:{retry_after:120}},{status:429});
    const before=Date.now();await queue.alarm();assert.ok(state.storage.alarm>=before+120000);
    const restarted=new TelegramQueue(state,env);
    globalThis.fetch=async(_,opts)=>{assert.equal((await opts.body.get('photo').arrayBuffer()).byteLength,png.length);return Response.json({ok:true});};
    await restarted.alarm();assert.equal((await state.storage.list({prefix:'q:'})).size,0);
  }finally{globalThis.fetch=original;}
});

test('email is always explicit, including Apple private addresses and unavailable email',()=>{
  for(const email of ['alias@privaterelay.appleid.com','alias@private.icloud.com']){
    const msg=buildUserRegistrationMessage({email},1);
    assert.ok(msg.includes(email));assert.match(msg,/защищённый адрес Apple/);
    assert.ok(buildPremiumPurchaseMessage({email}).includes(email));
  }
  assert.match(buildUserRegistrationMessage({},1),/Email:<\/b> —/);
  assert.match(buildUserRegistrationMessage({email:'real@example.com'},1),/real@example.com/);
  assert.match(buildUserRegistrationMessage({email:'<bad>@example.com'},1),/&lt;bad&gt;/);
});

test('midnight report and chart select the last completed period', async () => {
  const now = new Date('2026-10-03T21:07:00Z');
  assert.equal(dailyReportEnd(now).toISOString(), '2026-10-03T19:00:00.000Z');
  assert.equal(dailyReportEnd(new Date('2026-10-04T18:59:59Z')).toISOString(), '2026-10-03T19:00:00.000Z');
  assert.equal(dailyReportEnd(new Date('2026-10-04T19:00:00Z')).toISOString(), '2026-10-04T19:00:00.000Z');
  const {env} = setup();
  await env.INSTALLS.put('slot:2026-10-03:day',JSON.stringify({installs:2263,registrations:2703}));
  await env.INSTALLS.put('slot:2026-10-04:night',JSON.stringify({installs:352,registrations:366}));
  assert.equal((await dailyChartPoints(env,now)).at(-1).installs,2263);
  const text = buildDailyReportMessage({data:{views:10,clicks:20,clicksByStore:{'App Store':4,social_youtube:16},installs:2263,registrations:2703,purchases:0,reports:0},end:dailyReportEnd(now)});
  assert.match(text,/2 окт 22:00 — 3 окт 22:00/);
  assert.match(text,/Переходы в магазины: <b>4<\/b>/);
  assert.match(text,/Покупки Premium: <b>—<\/b>/);
  assert.doesNotMatch(text,/CR|Посетители/);
});

test('summary fits a photo caption with visible hierarchy', () => {
 const text=buildDailyReportMessage({data:{views:5630,clicksByStore:{'App Store':5729},installs:2263,registrations:2703},end:new Date('2026-10-03T19:00Z')});
 assert.ok(text.length < 1024);
 assert.match(text,/<b>Итоги за сутки<\/b>/);
 assert.match(text,/Новые установки: <b>2 263<\/b>/);
 assert.doesNotMatch(text,/2026|Всего:|Google Play|CR|\$0/);
});

test('unknown sources stay hidden; verified sources are generic; no fake cohort arrows', () => {
 const base={views:1,installs:1,registrations:2,aiRequests:3,reports:4};
 const end=new Date('2026-10-05T19:00Z');
 const unknown=buildDailyReportMessage({data:base,end});
 assert.doesNotMatch(unknown,/Threads|Источники|↓/);
 assert.match(unknown,/Жалобы: <b>4<\/b>\n🤖 ИИ-запросы: <b>3<\/b>/);
 const known=buildDailyReportMessage({data:{...base,registrationsByMarketingSource:{threads:2,youtube:1,unknown:10,'<script>':5}},end});
 assert.match(known,/Источники новых аккаунтов/);
 assert.match(known,/Threads: <b>2<\/b>/);
 assert.match(known,/YouTube: <b>1<\/b>/);
 assert.doesNotMatch(known,/unknown|script/);
});

test('registration source aggregation preserves multiple channels without guessing unknown', async () => {
 const {env}=setup();
 await flushBufferedStats(env,['threads','youtube','unknown'].map(marketingSource=>({kind:'analytics',ts:Date.parse('2026-10-05T15:00Z'),event:{type:'registration',app:'ru',marketingSource}})));
 const slot=JSON.parse(await env.INSTALLS.get('slot:2026-10-05:day'));
 assert.equal(slot.registrations,3);
 assert.deepEqual(slot.registrationsByMarketingSource,{threads:1,youtube:1});
});
