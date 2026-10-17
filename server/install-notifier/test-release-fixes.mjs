import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { SignJWT, importPKCS8 } from 'jose';
import worker from './worker.js';
import { NotificationsState, DEFAULT_NOTIFICATION_CONFIG } from './notifications.js';
import { verifyIdentity, handleAuth } from './user_auth.js';
import { verifyStorePurchase, claimPurchase, refreshStoreEntitlement } from './store_verification.js';
import { PurchaseClaims } from './purchase_claims.js';
import { accountTokenForUserId } from './store_account.js';
import { accountRead } from './account_state.js';
import { privatePushTopic } from './notification_identity.js';
import { fixture, identity, session, request, MemoryStorage } from './fixture-account.mjs';

test('Google access-token audience never becomes optional and expiry must be numeric',async()=>{
 const original=globalThis.fetch;
 try{for(const env of [{},{GOOGLE_CLIENT_IDS:'ours'},{GOOGLE_ANDROID_CLIENT_IDS:'android',GOOGLE_CLIENT_IDS:'ours'}]){
  globalThis.fetch=async()=>Response.json({aud:'foreign',sub:'123',expires_in:3600});await assert.rejects(verifyIdentity({provider:'google',credential:'fixture-access'},env),/wrong client/);
 }
 for(const expiry of [undefined,'invalid',0,-1]){globalThis.fetch=async()=>Response.json({aud:'ours',sub:'123',expires_in:expiry});await assert.rejects(verifyIdentity({provider:'google',credential:'fixture-access'},{GOOGLE_CLIENT_IDS:'ours'}),/invalid credential/);}
 for(const aud of ['ours','android']){globalThis.fetch=async url=>Response.json(String(url).includes('tokeninfo')?{aud,sub:'123',expires_in:3600}:{sub:'123'});assert.equal((await verifyIdentity({provider:'google',credential:'fixture-access'},{GOOGLE_CLIENT_IDS:'ours',GOOGLE_ANDROID_CLIENT_IDS:'android'})).id,'google_123');}
 }finally{globalThis.fetch=original;}
});

test('AI guest explanation quota is atomic; app key cannot authorize a free-form chat',async()=>{
 const{env}=fixture();env.GEMINI_API_KEY='fixture-provider';const original=globalThis.fetch;let calls=0;
 globalThis.fetch=async()=>{calls++;return Response.json({candidates:[{content:{parts:[{text:'fixture answer'}]}}]});};
 try{
  const body={installationId:'a'.repeat(32),questionText:'Question?',answers:['Answer'],correctAnswerIndex:0,locale:'kk'};
  const replies=await Promise.all(Array.from({length:20},()=>worker.fetch(request('/api/ai/chat',body),env)));
  assert.equal(replies.filter(r=>r.status===200).length,3);assert.equal(replies.filter(r=>r.status===429).length,17);assert.equal(calls,3);
  assert.equal((await worker.fetch(request('/api/ai/chat',{...body,userMessage:'Free form'}),env)).status,401);
  const status=await(await worker.fetch(request('/api/ai/status?installationId='+body.installationId),env)).json();assert.equal(status.remaining,0);assert.equal(status.limit,3);
 }finally{globalThis.fetch=original;}
});

test('AI signed free/premium quotas and global ceiling come from server entitlement',async()=>{
 const{env}=fixture();env.GEMINI_API_KEY='fixture-provider';env.AI_GLOBAL_DAILY_LIMIT='2';await env.INSTALLS.put('user:google_123',JSON.stringify({...identity(),isPremium:false}));const token=await session(env);
 const original=globalThis.fetch;globalThis.fetch=async(_url,options)=>{const prompt=JSON.parse(options.body).systemInstruction.parts[0].text;assert.match(prompt,/английском/);return Response.json({candidates:[{content:{parts:[{text:'answer'}]}}]});};
 try{const body={locale:'en',userMessage:'Follow up',isPremium:true};for(let i=0;i<2;i++)assert.equal((await worker.fetch(request('/api/ai/chat',body,token),env)).status,200);const globalResponse=await worker.fetch(request('/api/ai/chat',body,token),env);assert.equal(globalResponse.status,429);const globalQuota=await globalResponse.json();assert.equal(globalQuota.reason,'global_limit');assert.equal(globalQuota.remaining,8);
 const state=await(await worker.fetch(request('/api/ai/status',undefined,token),env)).json();assert.equal(state.limit,10);
 }finally{globalThis.fetch=original;}
 const premium=fixture();await premium.env.INSTALLS.put('user:google_123',JSON.stringify({...identity(),entitlements:{admin_grant:{expiresAt:null}}}));const premiumToken=await session(premium.env);assert.equal((await(await worker.fetch(request('/api/ai/status',undefined,premiumToken),premium.env)).json()).limit,200);
});

test('AI minute cooldown preserves Premium daily remaining for the next retry',async()=>{
 const{env}=fixture();env.GEMINI_API_KEY='fixture';await env.INSTALLS.put('user:google_123',JSON.stringify({...identity(),entitlements:{admin_grant:{expiresAt:null}}}));const token=await session(env);const original=globalThis.fetch;
 globalThis.fetch=async()=>Response.json({candidates:[{content:{parts:[{text:'answer'}]}}]});
 try{for(let i=0;i<10;i++)assert.equal((await worker.fetch(request('/api/ai/chat',{userMessage:'Follow up'},token),env)).status,200);const response=await worker.fetch(request('/api/ai/chat',{userMessage:'Follow up'},token),env);assert.equal(response.status,429);const quota=await response.json();assert.equal(quota.reason,'rate_limit');assert.equal(quota.limit,200);assert.equal(quota.remaining,190);assert.ok(quota.retryAfterSeconds>0&&quota.retryAfterSeconds<=60);
 }finally{globalThis.fetch=original;}
});

test('AI provider failure returns explicit unavailability for chat and only official text for explanation',async()=>{
 const{env}=fixture();env.GEMINI_API_KEY='fixture';const token=await session(env);const original=globalThis.fetch,originalLog=console.error;globalThis.fetch=async()=>{throw new Error('fixture unavailable');};console.error=()=>{};
 try{const chat=await worker.fetch(request('/api/ai/chat',{userMessage:'test'},token),env);assert.equal(chat.status,503);assert.equal((await chat.json()).generated,false);
 const explained=await(await worker.fetch(request('/api/ai/chat',{installationId:'b'.repeat(32),officialExplanation:'Exact official comment'},null),env)).json();assert.equal(explained.reply,'Exact official comment');assert.equal(explained.generated,false);
 }finally{globalThis.fetch=original;console.error=originalLog;}
});

test('targeted notification identity is verified; private push topic cannot be derived from email',async()=>{
 const{env}=fixture();const store=new MemoryStorage();const object=new NotificationsState({storage:store},{});env.NOTIFICATIONS={idFromName:id=>id,get:()=>({fetch:(url,options)=>object.fetch(new Request(url,options))})};
 await object.fetch(new Request('https://notifications/publish',{method:'POST',body:JSON.stringify({id:crypto.randomUUID(),kind:'popup',app:'ru',platform:'all',title:'Private',body:'Test',target:'fixture@example.invalid',expiresAt:Date.now()+86400000})}));
 const forged=await(await worker.fetch(request('/api/notifications?app=ru&platform=android&email=fixture@example.invalid&userId=google_123'),env)).json();assert.deepEqual(forged.messages,[]);assert.deepEqual(forged.pushTopics,[]);
 const token=await session(env);const signed=await(await worker.fetch(request('/api/notifications?app=ru&platform=android',undefined,token),env)).json();assert.equal(signed.messages.length,1);assert.match(signed.pushTopics[0],/^pdd_account_[a-f0-9]{64}$/);assert.ok(!signed.pushTopics[0].includes(Buffer.from('fixture@example.invalid').toString('hex')));
 assert.notEqual(await privatePushTopic(env,'google_123'),await privatePushTopic({...env,SESSION_SECRET:'another'},'google_123'));
});

function appleFixture(){const{privateKey}=generateKeyPairSync('ec',{namedCurve:'P-256'});const pem=privateKey.export({format:'pem',type:'pkcs8'});return{APPLE_IAP_PRIVATE_KEY:pem,APPLE_IAP_KEY_ID:'fixture',APPLE_IAP_ISSUER_ID:'fixture',pem};}
const jws=data=>Buffer.from(JSON.stringify({alg:'ES256'})).toString('base64url')+'.'+Buffer.from(JSON.stringify(data)).toString('base64url')+'.fixture';
const appleTransaction=extra=>({bundleId:'ru.pdd.pddApp',productId:'u.pdd.pddApp.premium.week',transactionId:'999',originalTransactionId:'999',environment:'Production',expiresDate:Date.now()+86400000,...extra});

test('Apple UUID binds original account and rejects another account before receipt claim',async()=>{
 const a=await accountTokenForUserId('apple_A'),b=await accountTokenForUserId('apple_B');assert.match(a,/^[a-f0-9-]{14}5[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);assert.notEqual(a,b);
 const env=appleFixture();const original=globalThis.fetch;globalThis.fetch=async()=>Response.json({signedTransactionInfo:jws(appleTransaction({appAccountToken:a}))});
 try{const body={store:'appstore',country:'ru',productId:'u.pdd.pddApp.premium.week',transactionId:'999'};assert.equal((await verifyStorePurchase(body,env,'apple_A')).active,true);await assert.rejects(verifyStorePurchase(body,env,'apple_B'),/another account/);}finally{globalThis.fetch=original;}
});

test('unbound legacy Apple receipt cannot be claimed first by a different replayed account',async()=>{
 const storage=new MemoryStorage(),claims=new PurchaseClaims({storage});const env={PURCHASE_CLAIMS:{idFromName:id=>id,get:()=>({fetch:(url,options)=>claims.fetch(new Request(url,options))})}};
 const verified={key:'appstore:legacy',reference:{store:'appstore'},accountToken:null};await assert.rejects(claimPurchase(env,'apple_B',verified),/legacy purchase owner required/);
 await storage.put('owner','apple_A');await claimPurchase(env,'apple_A',verified);await assert.rejects(claimPurchase(env,'apple_B',verified),/another account/);
});

test('Apple deletion revokes retained authorization and erases private tokens; legacy users get manual fallback',async()=>{
 const f=fixture(),env={...f.env,...appleFixture()};Object.assign(f.env,env);const e=f.env;e.APPLE_AUTH_PRIVATE_KEY=e.pem;e.APPLE_AUTH_KEY_ID='auth-fixture';e.APPLE_AUTH_TEAM_ID='fixture-team';
 const key=await importPKCS8(e.pem,'ES256');const credential=await new SignJWT({sub:'fixture',aud:'ru.pdd.pddApp'}).setProtectedHeader({alg:'ES256'}).sign(key);const appleUser=identity('apple_fixture');const original=globalThis.fetch;let revoked=0;
 globalThis.fetch=async(url,options)=>{if(String(url).endsWith('/auth/token'))return Response.json({refresh_token:'fixture-private-refresh',id_token:credential});if(String(url).endsWith('/auth/revoke')){assert.equal(options.body.get('token'),'fixture-private-refresh');revoked++;return new Response(null,{status:200});}throw new Error('unexpected fixture request');};
 try{const logged=await handleAuth(request('/api/auth/session',{provider:'apple',credential,authorizationCode:'fixture-code'}),e,async()=>appleUser);assert.equal(logged.status,200);const token=(await logged.json()).token;
 await e.INSTALLS.put('user:'+appleUser.id,JSON.stringify(appleUser));assert.ok(await accountRead(e,appleUser.id,'apple_auth:'+appleUser.id));assert.equal(await e.INSTALLS.get('apple_auth:'+appleUser.id),null);
 const response=await worker.fetch(request('/api/user/delete',{userId:appleUser.id},token),e);assert.equal((await response.json()).appleRevocation,'revoked');assert.equal(revoked,1);assert.equal(await accountRead(e,appleUser.id,'apple_auth:'+appleUser.id),null);
 }finally{globalThis.fetch=original;}
 const legacy=fixture();await legacy.env.INSTALLS.put('user:apple_legacy',JSON.stringify(identity('apple_legacy')));const token=await session(legacy.env,'apple_legacy');const result=await(await worker.fetch(request('/api/user/delete',{userId:'apple_legacy'},token),legacy.env)).json();assert.equal(result.appleRevocation,'manual_required');assert.match(result.appleManageUrl,/^https:\/\/account\.apple\.com\//);
});

test('worker Apple sign-in verifies fixture JWKS and serializes repeated authorization-code exchange in account DO',async()=>{
 const f=fixture(),e=f.env;const authKey=appleFixture();Object.assign(e,{APPLE_AUTH_PRIVATE_KEY:authKey.pem,APPLE_AUTH_KEY_ID:'fixture-auth',APPLE_AUTH_TEAM_ID:'fixture-team'});
 const rsa=generateKeyPairSync('rsa',{modulusLength:2048});const privateKey=await importPKCS8(rsa.privateKey.export({type:'pkcs8',format:'pem'}),'RS256');
 const credential=await new SignJWT({email:'fixture@example.invalid',email_verified:true}).setProtectedHeader({alg:'RS256',kid:'fixture-apple-signin'}).setIssuer('https://appleid.apple.com').setAudience('ru.pdd.pddApp').setSubject('worker_fixture').setIssuedAt().setExpirationTime('5m').sign(privateKey);
 const jwk={...rsa.publicKey.export({format:'jwk'}),kid:'fixture-apple-signin',alg:'RS256',use:'sig'};
 const original=globalThis.fetch;let exchanges=0;
 globalThis.fetch=async url=>{if(String(url)==='https://appleid.apple.com/auth/keys')return Response.json({keys:[jwk]});if(String(url)==='https://appleid.apple.com/auth/token'){exchanges++;return Response.json({refresh_token:'fixture-private-refresh',id_token:credential});}throw new Error('unexpected fixture URL');};
 try{const body={provider:'apple',credential,authorizationCode:'same-fixture-code'};const responses=await Promise.all([worker.fetch(request('/api/auth/session',body),e),worker.fetch(request('/api/auth/session',body),e)]);assert.deepEqual(responses.map(r=>r.status),[200,200]);assert.equal(exchanges,1);const stored=JSON.parse(await accountRead(e,'apple_worker_fixture','apple_auth:apple_worker_fixture'));assert.equal(stored.refreshToken,'fixture-private-refresh');assert.equal(await e.INSTALLS.get('apple_auth:apple_worker_fixture'),null);
 }finally{globalThis.fetch=original;}
});

test('all writer types serialize: IAP, SBP, admin grant, profile and progress metadata preserve each other',async()=>{
 const{env}=fixture();Object.assign(env,appleFixture());await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const token=await session(env);
 const{seedOrder}=await import('./fixture-account.mjs');const order=await seedOrder(env);const storage=new MemoryStorage(),claims=new PurchaseClaims({storage});env.PURCHASE_CLAIMS={idFromName:id=>id,get:()=>({fetch:(url,options)=>claims.fetch(new Request(url,options))})};
 const data=appleTransaction({appAccountToken:await accountTokenForUserId('google_123')});const original=globalThis.fetch;
 globalThis.fetch=async url=>String(url).includes('storekit')?Response.json({signedTransactionInfo:jws(data)}):Response.json({status:'CONFIRMED',paymentDetails:{amount:99,currency:'RUB'}});
 try{const jobs=[
  worker.fetch(request('/api/user/sync',{id:'google_123',appVersion:'3.0.0+100'},token),env),
  worker.fetch(request('/api/user/progress/sync',{userId:'google_123',appVersion:'3.0.0+100',progress:{questionProgressAb:{q:{answeredAt:Date.now(),correct:true}}}},token),env),
  worker.fetch(request('/api/user/purchase',{store:'appstore',country:'ru',productId:data.productId,transactionId:'999'},token),env),
  worker.fetch(request('/api/admin/users/grant-premium',{userId:'google_123',days:30,notify:false},null,{authorization:'Bearer fixture-admin'}),env),
  worker.fetch(request('/api/pay/platega/callback',{id:order.txId,payload:order.orderId},null,{'x-secret':env.PLATEGA_SECRET,'x-merchantid':env.PLATEGA_MERCHANT_ID}),env),
 ];assert.deepEqual((await Promise.all(jobs)).map(r=>r.status),[200,200,200,200,200]);const user=JSON.parse(await accountRead(env,'google_123','user:google_123'));
 assert.deepEqual(Object.keys(user.entitlements).sort(),['admin_grant','appstore','web']);assert.equal(user.appVersion,'3.0.0+100');assert.ok(user.webPayments[order.orderId]);assert.ok(user.verifiedPurchases.appstore);assert.equal(JSON.parse(await accountRead(env,'google_123','user_progress:google_123')).questionProgressAb.q.correct,true);
 }finally{globalThis.fetch=original;}
});

test('explicit expiring legacy mode preserves bounded explanations for already published clients',async()=>{
 const{env}=fixture();env.AI_LEGACY_EXPLANATIONS='true';env.AI_LEGACY_UNTIL=new Date(Date.now()+86400000).toISOString();env.GEMINI_API_KEY='fixture';const original=globalThis.fetch;let calls=0;globalThis.fetch=async()=>{calls++;return Response.json({candidates:[{content:{parts:[{text:'safe fixture explanation'}]}}]});};
 try{const body={questionText:'Fixture question',answers:['Answer'],correctAnswerIndex:0};const responses=await Promise.all(Array.from({length:10},()=>worker.fetch(request('/api/ai/chat',body,null,{'cf-connecting-ip':'192.0.2.1','user-agent':'Dart/3.0'}),env)));assert.equal(responses.filter(r=>r.status===200).length,3);assert.equal(calls,3);
 assert.equal((await worker.fetch(request('/api/ai/chat',{...body,userMessage:'Free form'}),env)).status,401);
 env.AI_LEGACY_UNTIL='2020-01-01T00:00:00Z';assert.equal((await worker.fetch(request('/api/ai/chat',body),env)).status,400);
 }finally{globalThis.fetch=original;}
});

test('both store references refresh independently and preserve a longer web entitlement',async()=>{
 const env=appleFixture();const rsa=generateKeyPairSync('rsa',{modulusLength:2048});env.GOOGLE_PLAY_SERVICE_ACCOUNT=JSON.stringify({client_email:'fixture-play@example.invalid',private_key:rsa.privateKey.export({type:'pkcs8',format:'pem'})});env.INSTALLS={put:async()=>{}};
 const googleId='ru.pdd.pddapp.sub.week',apple=appleTransaction({appAccountToken:await accountTokenForUserId('google_123')});
 const googleRef={store:'googleplay',country:'ru',productId:googleId,purchaseToken:'fixture-token'},appleRef={store:'appstore',country:'ru',productId:apple.productId,transactionId:'999'};
 const expiresAt=new Date(Date.now()+86400000).toISOString(),webEnd=new Date(Date.now()+180*86400000).toISOString();const user={id:'google_123',entitlements:{googleplay:{expiresAt},appstore:{expiresAt},web:{expiresAt:webEnd}},verifiedPurchases:{googleplay:googleRef,appstore:appleRef}};
 const original=globalThis.fetch;const seen=[];
 globalThis.fetch=async url=>{const u=String(url);seen.push(u);if(u==='https://oauth2.googleapis.com/token')return Response.json({access_token:crypto.randomUUID(),expires_in:3600});if(u.includes('androidpublisher'))return Response.json({subscriptionState:'SUBSCRIPTION_STATE_ACTIVE',lineItems:[{productId:googleId,expiryTime:new Date(Date.now()+30*86400000).toISOString()}]});if(u.includes('/subscriptions/'))return Response.json({environment:'Production',bundleId:apple.bundleId,data:[{lastTransactions:[{originalTransactionId:'999',status:1,signedTransactionInfo:jws(apple)}]}]});return Response.json({signedTransactionInfo:jws(apple)});};
 try{await refreshStoreEntitlement(env,user);assert.ok(seen.some(u=>u.includes('androidpublisher')));assert.ok(seen.some(u=>u.includes('storekit')));assert.deepEqual(Object.keys(user.verifiedPurchases).sort(),['appstore','googleplay']);assert.deepEqual(Object.keys(user.storeVerifiedAtByStore).sort(),['appstore','googleplay']);assert.equal(user.premiumSource,'web');assert.equal(user.premiumExpiresAt,webEnd);}finally{globalThis.fetch=original;}
});

test('Apple callback authentication and provider reread defeat forged notification entitlement',async()=>{
 const{appleNotificationToken}=await import('./store_notifications.js');const{env}=fixture();Object.assign(env,appleFixture());const owner='google_123',storage=new MemoryStorage();await storage.put('owner',owner);const claims=new PurchaseClaims({storage});env.PURCHASE_CLAIMS={idFromName:id=>id,get:()=>({fetch:(url,options)=>claims.fetch(new Request(url,options))})};
 const expiry=new Date(Date.now()+86400000).toISOString();await env.INSTALLS.put('user:'+owner,JSON.stringify({...identity(),entitlements:{appstore:{expiresAt:expiry},admin_grant:{expiresAt:null}}}));
 const hint=appleTransaction({expiresDate:Date.now()+365*86400000,appAccountToken:await accountTokenForUserId(owner)}),revoked={...hint,revocationDate:Date.now()};const body={signedPayload:jws({notificationType:'DID_RENEW',data:{signedTransactionInfo:jws(hint)}})};const original=globalThis.fetch;let calls=0;
 globalThis.fetch=async url=>{calls++;return String(url).includes('/subscriptions/')?Response.json({environment:'Production',bundleId:revoked.bundleId,data:[{lastTransactions:[{originalTransactionId:'999',status:5,signedTransactionInfo:jws(revoked)}]}]}):Response.json({signedTransactionInfo:jws(revoked)});};
 try{assert.equal((await worker.fetch(request('/api/store/apple/notifications',body),env)).status,401);assert.equal(calls,0);const mac=await appleNotificationToken(env);assert.equal((await worker.fetch(request('/api/store/apple/notifications?token='+mac,body),env)).status,200);const user=JSON.parse(await accountRead(env,owner,'user:'+owner));assert.ok(Date.parse(user.entitlements.appstore.expiresAt)<=Date.now());assert.equal(user.isPremium,true);assert.equal(user.premiumSource,'admin_grant');assert.ok(calls>=2);
 }finally{globalThis.fetch=original;}
});

test('Google Pub/Sub authentication requires exact audience and configured verified service account email',async()=>{
 const{verifyGooglePush}=await import('./store_notifications.js');const rsa=generateKeyPairSync('rsa',{modulusLength:2048}),key=await importPKCS8(rsa.privateKey.export({type:'pkcs8',format:'pem'}),'RS256');const jwk={...rsa.publicKey.export({format:'jwk'}),kid:'fixture-google-push',alg:'RS256',use:'sig'};
 const env={GOOGLE_RTDN_AUDIENCE:'https://api.example.invalid/api/store/google/notifications',GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL:'pubsub@example.invalid'};
 const original=globalThis.fetch;globalThis.fetch=async()=>Response.json({keys:[jwk]});
 const signed=async(aud,email,verified=true)=>new SignJWT({email,email_verified:verified}).setProtectedHeader({alg:'RS256',kid:'fixture-google-push'}).setIssuer('https://accounts.google.com').setAudience(aud).setSubject('123').setIssuedAt().setExpirationTime('5m').sign(key);
 try{for(const[aud,email,verified,expected]of[[env.GOOGLE_RTDN_AUDIENCE,env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL,true,true],['wrong',env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL,true,false],[env.GOOGLE_RTDN_AUDIENCE,'foreign@example.invalid',true,false],[env.GOOGLE_RTDN_AUDIENCE,env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL,false,false]]){const token=await signed(aud,email,verified);assert.equal(await verifyGooglePush(new Request(env.GOOGLE_RTDN_AUDIENCE,{headers:{authorization:'Bearer '+token}}),env),expected);}
 assert.equal(await verifyGooglePush(new Request(env.GOOGLE_RTDN_AUDIENCE),env),false);
 }finally{globalThis.fetch=original;}
});
