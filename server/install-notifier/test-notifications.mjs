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
 for(const bad of [{kind:'push',body:''},{app:'xx'},{expiresAt:Date.now()-1},{title:'x'.repeat(81)},{kind:'push',body:'x'.repeat(301)},{kind:'push',platform:'web'}])assert.throws(()=>validateCampaign(sample(bad)));
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
test('client feed sends each CORS header once so browsers accept it',async()=>{
 const env={NOTIFICATIONS:{idFromName:()=> 'state',get:()=>({fetch:async()=>Response.json({messages:[]},{headers:{'cache-control':'no-store'}})})}};
 const r=await worker.fetch(new Request('https://test/api/notifications?app=ru&platform=web'),env);
 assert.equal(r.status,200);assert.equal(r.headers.get('Access-Control-Allow-Origin'),'*');
 assert.equal(r.headers.get('Access-Control-Allow-Methods'),'GET, POST, OPTIONS');assert.equal(r.headers.get('cache-control'),'no-store');
 assert.deepEqual((await r.json()).messages,[]);
});
import { buildPushMessage, clientMessage, userTopic } from './notifications.js';
test('customization: banner limits, https-only images/links, accent format, scheduling',()=>{
  for(const bad of [{kind:'banner',body:'x'.repeat(201)},{imageUrl:'http://x.test/a.png'},{accent:'red'},{action:'url'},{action:'hack'},{layout:'x'},{startAt:Date.now()+40*86400000}])assert.throws(()=>validateCampaign(sample(bad)));
  const start=Date.now()+3600000;
  const item=validateCampaign(sample({kind:'banner',imageUrl:'https://x.test/a.png',accent:'#112233',action:'url',actionUrl:'https://x.test',startAt:start,expiresAt:start+86400000}));
  assert.equal(item.status,'scheduled');assert.equal(campaignMatches(item,'ru','ios'),false);assert.equal(campaignMatches(item,'ru','ios',start+1),true);
  assert.equal(clientMessage(item).kind,'banner');assert.equal(clientMessage(item).status,undefined);
});
test('image banners accept image-only content and preserve the link in the client payload',()=>{
  const item=validateCampaign(sample({kind:'banner',layout:'image',title:undefined,body:undefined,imageUrl:'https://cdn.test/banner.png',action:'url',actionUrl:'https://pdd-drive.ru/tarify/'}));
  assert.equal(item.title,'');assert.equal(item.body,'');
  const message=clientMessage(item);
  assert.equal(message.layout,'image');assert.equal(message.imageUrl,'https://cdn.test/banner.png');
  assert.equal(message.action,'url');assert.equal(message.actionUrl,'https://pdd-drive.ru/tarify/');
  assert.equal(validateCampaign(sample({kind:'banner',layout:'image',title:'',body:'',imageUrl:'https://cdn.test/banner.png'})).action,'none');
});
test('image-only layout requires an HTTPS image and is not allowed for pushes; empty messages are rejected',()=>{
  const image={layout:'image',imageUrl:'https://cdn.test/banner.png',title:'',body:''};
  for(const bad of [{...image,kind:'push'},{...image,kind:'banner',imageUrl:''},{...image,kind:'banner',imageUrl:'http://cdn.test/banner.png'},{...image,kind:'banner',imageUrl:'javascript:alert(1)'},{...image,kind:'banner',action:'url',actionUrl:''},{...image,kind:'banner',action:'url',actionUrl:'http://pdd-drive.ru'},{...image,kind:'banner',title:42},{kind:'banner',title:'',body:''},{kind:'popup',title:'',body:''}]) {
    assert.throws(()=>validateCampaign(sample(bad)));
  }
});
test('image campaigns survive publication, retry and dismissal toggles in the client feed',async()=>{
  const {call}=setup(),msg=sample({kind:'banner',layout:'image',title:'',body:'',imageUrl:'https://cdn.test/banner.webp',action:'url',actionUrl:'https://pdd-drive.ru/'});
  assert.equal((await call('/publish',msg)).status,200);
  assert.equal((await (await call('/publish',msg)).json()).duplicate,true);
  const feed=await (await call('/client?app=ru&platform=android&imageBanners=1')).json();
  assert.equal(feed.messages.length,1);assert.equal(feed.messages[0].layout,'image');assert.equal(feed.messages[0].title,'');
  assert.equal(feed.messages[0].actionUrl,'https://pdd-drive.ru/');
  assert.equal((await call('/publish',{...msg,layout:'standard',title:'Новости',body:'Новые вопросы'})).status,409);
  await call('/toggle',{id:msg.id,enabled:false});
  assert.equal((await (await call('/client?app=ru&platform=android&imageBanners=1')).json()).messages.length,0);
});
test('image campaigns require explicit client capability while legacy cards remain visible',async()=>{
  const {call}=setup();
  const image=sample({kind:'banner',layout:'image',title:'',body:'',imageUrl:'https://cdn.test/banner.png'});
  const ordinary=sample({kind:'banner'});
  await call('/publish',image);await call('/publish',ordinary);
  for(const suffix of ['', '&imageBanners=0', '&imageBanners=true']) {
    const feed=await (await call('/client?app=ru&platform=ios'+suffix)).json();
    assert.deepEqual(feed.messages.map(m=>m.id),[ordinary.id]);
  }
  const feed=await (await call('/client?app=ru&platform=ios&imageBanners=1')).json();
  assert.equal(feed.messages.length,2);assert.ok(feed.messages.some(m=>m.id===image.id));
});
test('public notification route forwards image capability to the Durable Object',async()=>{
  const paths=[];
  const env={NOTIFICATIONS:{idFromName:()=> 'state',get:()=>({fetch:async path=>{paths.push(new URL(path));return Response.json({messages:[]});}})}};
  await worker.fetch(new Request('https://test/api/notifications?app=ru&platform=web&imageBanners=1'),env);
  assert.equal(paths[0].searchParams.get('imageBanners'),'1');
  await worker.fetch(new Request('https://test/api/notifications?app=ru&platform=web'),env);
  assert.notEqual(paths[1].searchParams.get('imageBanners'),'1');
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
  const topic='pdd_account_'+'a'.repeat(64);
  personal.targetTopic=topic;
  assert.throws(()=>pushCondition({...personal,targetTopic:''}),/защищённым аккаунтом/);
  assert.equal(pushCondition(validateCampaign({...personal,kind:'push'})),`'${topic}' in topics && 'pdd_ru_ios' in topics`);
  assert.equal(pushCondition(validateCampaign({...personal,kind:'push',platform:'all'})),`'${topic}' in topics`);
});
test('campaign editor remains Russia-only; release settings support all countries',async()=>{
  const html=await(await worker.fetch(new Request('https://test/admin'),{})).text();
  assert.match(html, /id="up-app"[\s\S]*value="by"[\s\S]*value="rs"/);
  assert.doesNotMatch(html.match(/<form id="nt-form"[\s\S]*?<\/form>/)[0], /Беларусь|Сербия/);
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



test('windows and banners compose optional title, text and button',()=>{
  const popup=validateCampaign(sample({kind:'popup',title:'',body:'',layout:'standard',imageUrl:'https://cdn.test/p.png',action:'url',actionUrl:'https://pdd-drive.ru/',buttonText:'Открыть'}));
  assert.equal(popup.layout,'image');assert.equal(popup.button,false);assert.equal(popup.buttonText,'');
  const titleOnly=validateCampaign(sample({title:'Новая версия',body:'',button:false,buttonText:'x',dismissText:'Позже'}));
  assert.equal(titleOnly.layout,'standard');assert.equal(titleOnly.body,'');assert.equal(titleOnly.button,false);assert.equal(titleOnly.buttonText,'');assert.equal(titleOnly.dismissText,'');
  const textOnly=validateCampaign(sample({kind:'banner',title:'',body:'Обновитесь',layout:'image'}));
  assert.equal(textOnly.layout,'standard');assert.equal(textOnly.button,true);
  assert.equal(clientMessage(titleOnly).button,false);
  assert.equal(clientMessage({...titleOnly,button:undefined}).button,true,'legacy campaigns keep their button');
  assert.throws(()=>validateCampaign(sample({title:'',body:'',imageUrl:''})));
});
test('picture-only windows require the newer client capability',async()=>{
  const {call}=setup(),msg=sample({kind:'popup',title:'',body:'',imageUrl:'https://cdn.test/p.png'});
  assert.equal((await call('/publish',msg)).status,200);
  assert.equal((await (await call('/client?app=ru&platform=android&imageBanners=1')).json()).messages.length,0);
  assert.equal((await (await call('/client?app=ru&platform=android&imagePopups=1')).json()).messages.length,0);
  const feed=await (await call('/client?app=ru&platform=android&imageBanners=1&imagePopups=1')).json();
  assert.equal(feed.messages.length,1);assert.equal(feed.messages[0].kind,'popup');assert.equal(feed.messages[0].layout,'image');
});

test('in-app messages can target one Android store',async()=>{
  for(const bad of [{store:'play'},{platform:'android',store:'apple'},{kind:'push',platform:'android',store:'rustore'}])assert.throws(()=>validateCampaign(sample(bad)));
  const {call}=setup(),msg=sample({platform:'android',store:'rustore'});
  assert.equal((await call('/publish',msg)).status,200);
  const feed=async q=>(await (await call('/client?app=ru&platform=android'+q)).json()).messages.length;
  assert.equal(await feed('&store=rustore'),1);
  assert.equal(await feed('&store=play'),0);
  assert.equal(await feed(''),0,'builds without a store never get store-only messages');
  assert.equal(validateCampaign(sample()).store,'all');
});

test('inbox news reach only clients with the notification inbox',async()=>{
  assert.throws(()=>validateCampaign(sample({kind:'news',title:'',body:'',imageUrl:'https://cdn.test/n.png'})),/заголовок или текст/);
  const {call}=setup(),msg=sample({kind:'news',title:'Оплата по СБП',body:'Премиум теперь можно купить по СБП',action:'premium',buttonText:'Открыть'});
  assert.equal((await call('/publish',msg)).status,200);
  assert.equal((await (await call('/client?app=ru&platform=android')).json()).messages.length,0,'old clients would show news as a popup');
  const feed=await (await call('/client?app=ru&platform=android&inbox=1')).json();
  assert.equal(feed.messages.length,1);assert.equal(feed.messages[0].kind,'news');assert.equal(feed.messages[0].action,'premium');
  assert.ok(feed.messages[0].createdAt>0);
});
