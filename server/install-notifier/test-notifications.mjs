import test from 'node:test';
import assert from 'node:assert/strict';
import { NotificationsState, validateCampaign, campaignMatches, pushCondition, DEFAULT_NOTIFICATION_CONFIG } from './notifications.js';
import { NOTIFICATIONS_CLIENT_JS } from './notifications_ui.js';
import worker from './worker.js';
const sample = (overrides = {}) => ({ id: crypto.randomUUID(), kind: 'popup', app:'ru', platform:'all', title:'Новости', body:'Новые вопросы', expiresAt:Date.now()+86400000, ...overrides });
function setup(env={}) {
 const data = new Map(); const storage = { get:async k=>data.get(k),put:async(k,v)=>data.set(k,structuredClone(v)),delete:async k=>data.delete(k),list:async({prefix})=>new Map([...data].filter(([k])=>k.startsWith(prefix))),setAlarm:async()=>{} };
 const object = new NotificationsState({storage},env);
 const call=(path,body)=>object.fetch(new Request('https://notifications'+path,{method:body?'POST':'GET',...(body?{body:JSON.stringify(body)}:{})}));
 return {call,data,object};
}
test('input validation rejects missing text, unknown country, expired and oversized campaigns',()=>{
 for(const bad of [{body:''},{app:'xx'},{expiresAt:Date.now()-1},{title:'x'.repeat(81)},{kind:'push',body:'x'.repeat(301)},{kind:'push',platform:'web'}])assert.throws(()=>validateCampaign(sample(bad)));
});
test('country and platform targeting is exact; expired/disabled messages are hidden',()=>{
 const item=validateCampaign(sample({platform:'ios'}));
 assert.equal(campaignMatches(item,'ru','ios'),true);
 assert.equal(campaignMatches(item,'by','ios'),false);
 assert.equal(campaignMatches(item,'ru','android'),false);
 assert.equal(campaignMatches({...item,enabled:false},'ru','ios'),false);
 assert.equal(campaignMatches(item,'ru','ios',item.expiresAt),false);
});
test('push targeting uses mobile topic for six combinations, exact topics otherwise',()=>{
 assert.equal(pushCondition(sample({app:'all',platform:'all'})),"'pdd_mobile' in topics");
 assert.equal(pushCondition(sample({platform:'ios'})),"'pdd_ru_ios' in topics");
 assert.equal((pushCondition(sample({app:'all',platform:'android'})).match(/in topics/g)||[]).length,3);
});
test('publication survives concurrent retries without duplicate campaigns',async()=>{
 const {call,data}=setup(), msg=sample();
 const results=await Promise.all([call('/publish',msg),call('/publish',msg)]);
 assert.equal(results[0].status,200);assert.equal((await results[1].json()).duplicate,true);
 assert.equal([...data.keys()].filter(k=>k.startsWith('message:')).length,1);
 assert.equal((await call('/publish',{...msg,title:'Другое'})).status,409);
});
test('global and individual popup toggles immediately affect client feed',async()=>{
 const {call}=setup(), msg=sample({platform:'ios'}); await call('/publish',msg);
 assert.equal((await (await call('/client?app=ru&platform=ios')).json()).messages.length,1);
 assert.equal((await (await call('/client?app=by&platform=ios')).json()).messages.length,0);
 await call('/toggle',{id:msg.id,enabled:false});
 assert.equal((await (await call('/client?app=ru&platform=ios')).json()).messages.length,0);
 await call('/toggle',{id:msg.id,enabled:true});
 await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,popupEnabled:false});
 assert.equal((await (await call('/client?app=ru&platform=ios')).json()).messages.length,0);
 assert.equal((await call('/publish',sample())).status,409);
 assert.equal((await call('/client?app=invalid&platform=ios')).status,400);
});
test('pushes cannot be enabled or queued without real provider credentials',async()=>{
 const {call}=setup();
 assert.equal((await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,pushEnabled:true})).status,409);
 assert.equal((await call('/publish',sample({kind:'push'}))).status,409);
 assert.equal((await (await call('/admin')).json()).pushConfigured,false);
});
test('worker protects all notification mutations and admin read with session auth',async()=>{
 for(const path of ['/api/admin/notifications','/api/admin/notifications/config','/api/admin/notifications/publish','/api/admin/notifications/toggle']){
 const r=await worker.fetch(new Request('https://test'+path,{method:path.endsWith('notifications')?'GET':'POST',body:path.endsWith('notifications')?undefined:'{}'}),{INSTALLS:{get:async()=>null}});
 assert.equal(r.status,401);
 }
});
test('admin page embeds one functional notifications screen and complete client compiles',async()=>{
 new Function(NOTIFICATIONS_CLIENT_JS);
 const html=await(await worker.fetch(new Request('https://test/admin'),{})).text();
 assert.equal((html.match(/id="notifications-view"/g)||[]).length,1);
 new Function(html.match(/<script>([\s\S]*)<\/script>/)[1]);
 assert.match(html,/data-feature="notifications"/);
});

import { generateKeyPairSync } from 'node:crypto';
import { sendPush } from './notifications.js';
const { privateKey } = generateKeyPairSync('rsa', { modulusLength:2048 });
const fcmEnv={FCM_SERVICE_ACCOUNT:JSON.stringify({project_id:'test-project',client_email:'sender@test.invalid',private_key:privateKey.export({type:'pkcs8',format:'pem'})})};
test('FCM sender exchanges signed credentials and sends exact audience without user emails',async()=>{
 const calls=[];
 const result=await sendPush(fcmEnv,validateCampaign(sample({kind:'push',platform:'ios'})),async(url,opts)=>{
   calls.push({url,opts});
   return Response.json(url.includes('oauth2')?{access_token:'test-token',expires_in:3600}:{name:'projects/test-project/messages/id'});
 });
 assert.match(result,/messages\/id$/);assert.equal(calls.length,2);
 assert.equal(calls[0].opts.body.get('assertion').split('.').length,3);
 const message=JSON.parse(calls[1].opts.body).message;
 assert.equal(message.condition,"'pdd_ru_ios' in topics");assert.equal(message.android.notification.channel_id,'admin_messages');
 assert.equal(message.data.campaignId,message.apns.headers['apns-collapse-id']);
 assert.equal(message.token,undefined);assert.equal(message.data.email,undefined);
});
test('persistent queue sends once; accepted broadcasts cannot be recalled',async()=>{
 const {call,object,data}=setup(fcmEnv);
 await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,pushEnabled:true});
 const msg=sample({kind:'push'});await call('/publish',msg);
 const original=globalThis.fetch;let calls=0;
 globalThis.fetch=async()=>{calls++;return Response.json({name:'projects/test-project/messages/ok'});};
 try{await object.alarm();await object.alarm();}finally{globalThis.fetch=original;}
 assert.equal(calls,1);assert.equal(data.get('message:'+msg.id).status,'accepted');
 assert.equal((await call('/toggle',{id:msg.id,enabled:false})).status,409);
});
test('unknown network outcome never automatically repeats a broadcast',async()=>{
 const {call,object,data}=setup(fcmEnv);
 await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,pushEnabled:true});
 const msg=sample({kind:'push'});await call('/publish',msg);
 const original=globalThis.fetch;let calls=0;
 globalThis.fetch=async()=>{calls++;throw new Error('timeout');};
 try{await object.alarm();await object.alarm();}finally{globalThis.fetch=original;}
 assert.equal(calls,1);assert.equal(data.get('message:'+msg.id).status,'unknown');
});
test('global push switch pauses pending broadcasts without a network call',async()=>{
 const {call,object,data}=setup(fcmEnv);
 await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,pushEnabled:true});
 const msg=sample({kind:'push'});await call('/publish',msg);
 await call('/config',DEFAULT_NOTIFICATION_CONFIG);
 const original=globalThis.fetch;globalThis.fetch=async()=>{throw new Error('must not send');};
 try{await object.alarm();}finally{globalThis.fetch=original;}
 assert.equal(data.get('message:'+msg.id).status,'queued');
});
test('client route clones immutable Durable Object response headers before adding CORS',async()=>{
 const env={NOTIFICATIONS:{idFromName:()=> 'state',get:()=>({fetch:async()=>Response.redirect('https://test/client',302)})}};
 const r=await worker.fetch(new Request('https://test/api/notifications?app=ru&platform=ios'),env);
 assert.equal(r.status,302);assert.equal(r.headers.get('Access-Control-Allow-Origin'),'*');
});
import { buildPushMessage, clientMessage, userTopic } from './notifications.js';
test('customization: banner limits, https-only images/links, accent format, scheduling',()=>{
  for(const bad of [{kind:'banner',body:'x'.repeat(201)},{imageUrl:'http://x.test/a.png'},{accent:'red'},{action:'url'},{action:'hack'},{layout:'x'},{startAt:Date.now()+40*86400000}])assert.throws(()=>validateCampaign(sample(bad)));
  const start=Date.now()+3600000;
  const item=validateCampaign(sample({kind:'banner',imageUrl:'https://x.test/a.png',accent:'#112233',action:'url',actionUrl:'https://x.test',startAt:start,expiresAt:start+86400000}));
  assert.equal(item.status,'scheduled');assert.equal(campaignMatches(item,'ru','ios'),false);assert.equal(campaignMatches(item,'ru','ios',start+1),true);
  assert.equal(clientMessage(item).kind,'banner');assert.equal(clientMessage(item).status,undefined);
});
test('push payload carries image, accent, action and iOS mutable-content',()=>{
  const m=buildPushMessage(validateCampaign(sample({kind:'push',emoji:'🎉',imageUrl:'https://x.test/a.png',accent:'#112233',action:'game'})));
  assert.equal(m.notification.image,'https://x.test/a.png');assert.equal(m.notification.title,'🎉 Новости');
  assert.equal(m.android.notification.color,'#112233');assert.equal(m.apns.payload.aps['mutable-content'],1);
  assert.equal(m.apns.fcm_options.image,'https://x.test/a.png');assert.equal(m.data.action,'game');
});
test('push with inApp shows as popup in client feed; scheduled push waits',async()=>{
  const {call,object,data}=setup(fcmEnv);
  await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,pushEnabled:true});
  const msg=sample({kind:'push',inApp:true,platform:'ios'});await call('/publish',msg);
  const feed=await (await call('/client?app=ru&platform=ios')).json();
  assert.equal(feed.messages.length,1);assert.equal(feed.messages[0].kind,'popup');
  const later=sample({kind:'push',startAt:Date.now()+3600000,expiresAt:Date.now()+7200000});await call('/publish',later);
  const original=globalThis.fetch;let calls=0;globalThis.fetch=async()=>{calls++;return Response.json({name:'ok'});};
  try{await object.alarm();await object.alarm();}finally{globalThis.fetch=original;}
  assert.equal(calls,1);assert.equal(data.get('message:'+later.id).status,'queued');
  assert.equal((await call('/delete',{id:later.id})).status,200);assert.equal(data.has('message:'+later.id),false);
});
test('personal account test targeting delivers only to matching email or userId and uses personal push topic',async()=>{
  const {call}=setup();
  const personal=sample({target:'  Admin@Test.ru  ',platform:'ios'});
  await call('/publish',personal);
  assert.equal((await (await call('/client?app=ru&platform=ios')).json()).messages.length,0);
  assert.equal((await (await call('/client?app=ru&platform=ios&email=other@test.ru')).json()).messages.length,0);
  assert.equal((await (await call('/client?app=ru&platform=ios&email=admin@test.ru')).json()).messages.length,1);
  assert.equal((await (await call('/client?app=ru&platform=ios&userId=admin@test.ru')).json()).messages.length,1);
  const topic=userTopic('Admin@Test.ru');
  assert.match(topic,/^pdd_u_[0-9a-f]+$/);
  assert.equal(pushCondition(validateCampaign({...personal,kind:'push'})),`'${topic}' in topics && 'pdd_ru_ios' in topics`);
  assert.equal(pushCondition(validateCampaign({...personal,kind:'push',platform:'all'})),`'${topic}' in topics`);
});
test('admin page has no Belarus or Serbia selectors',async()=>{
  const html=await(await worker.fetch(new Request('https://test/admin'),{})).text();
  assert.doesNotMatch(html,/Беларусь|Сербия/);
  assert.match(html,/id="nt-audience"/);
  assert.match(html,/id="nt-target"/);
});
test('alarm route dispatches due pushes and onFormEdit handles form events',async()=>{
  const {call}=setup(fcmEnv);
  await call('/config',{...DEFAULT_NOTIFICATION_CONFIG,pushEnabled:true});
  const res=await call('/alarm');
  assert.equal(res.status,200);
  assert.equal((await res.json()).ok,true);
  const html=await(await worker.fetch(new Request('https://test/admin'),{})).text();
  assert.match(html,/function onFormEdit/);
});


