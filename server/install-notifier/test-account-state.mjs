import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { accountRead } from './account_state.js';
import { fixture, identity, session, request, seedOrder } from './fixture-account.mjs';
const callback=(env,order)=>worker.fetch(request('/api/pay/platega/callback',{id:order.txId,payload:order.orderId},null,{'x-secret':env.PLATEGA_SECRET,'x-merchantid':env.PLATEGA_MERCHANT_ID}),env);
async function withProvider(fn){const original=globalThis.fetch;globalThis.fetch=async()=>Response.json({status:'CONFIRMED',paymentDetails:{amount:99,currency:'RUB'}});try{return await fn();}finally{globalThis.fetch=original;}}

test('account DO serializes sync against payment; primary survives stale KV and object restart',async()=>withProvider(async()=>{
 const{env,restart}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify({...identity(),isPremium:false}));const order=await seedOrder(env);const token=await session(env);
 let held,release;const reached=new Promise(r=>held=r);const originalGet=env.INSTALLS.get.bind(env.INSTALLS);let pause=true;
 env.INSTALLS.get=async(key,options)=>{const value=await originalGet(key,options);if(key==='user:google_123'&&pause){pause=false;held();await new Promise(r=>release=r);}return value;};
 const syncing=worker.fetch(request('/api/user/sync',{id:'google_123'},token),env);await reached;
 const paying=callback(env,order);release();assert.equal((await syncing).status,200);assert.equal((await paying).status,200);
 let user=JSON.parse(await accountRead(env,'google_123','user:google_123'));assert.equal(user.isPremium,true);assert.ok(user.webPayments[order.orderId]);
 await env.INSTALLS.put('user:google_123',JSON.stringify({...identity(),isPremium:false}));restart('google_123');
 const status=await(await worker.fetch(request('/api/user/status',undefined,token),env)).json();assert.equal(status.isPremium,true);
}));

test('two simultaneous payments add both periods; duplicate callback/pay-check is idempotent',async()=>withProvider(async()=>{
 const{env}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const a=await seedOrder(env),b=await seedOrder(env),token=await session(env);
 assert.deepEqual((await Promise.all([callback(env,a),callback(env,b)])).map(r=>r.status),[200,200]);
 const before=JSON.parse(await accountRead(env,'google_123','user:google_123'));assert.equal(Object.keys(before.webPayments).length,2);assert.ok(Math.abs(Date.parse(before.premiumExpiresAt)-Date.now()-14*86400000)<3000);
 await Promise.all([callback(env,a),worker.fetch(request('/api/user/pay-check',{order:a.orderId},token),env),callback(env,b)]);
 const after=JSON.parse(await accountRead(env,'google_123','user:google_123'));assert.equal(after.premiumExpiresAt,before.premiumExpiresAt);assert.equal(Object.keys(after.webPayments).length,2);
 assert.ok(await accountRead(env,'google_123','payment_ledger:'+a.orderId));
}));

test('primary transaction failure commits no entitlement/order/ledger; retry succeeds once',async()=>withProvider(async()=>{
 const{env,states}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const order=await seedOrder(env);await accountRead(env,'google_123','user:google_123');await accountRead(env,'google_123','pay_order:'+order.orderId);await accountRead(env,'google_123','payment_ledger:'+order.orderId);await accountRead(env,'google_123','account_deleted:google_123');states.get('google_123').failCommit=true;
 assert.equal((await callback(env,order)).status,500);
 assert.equal(JSON.parse(await accountRead(env,'google_123','user:google_123')).isPremium,undefined);
 assert.equal(JSON.parse(await accountRead(env,'google_123','pay_order:'+order.orderId)).status,'pending');
 assert.equal(await accountRead(env,'google_123','payment_ledger:'+order.orderId),null);
 assert.equal((await callback(env,order)).status,200);assert.equal(JSON.parse(await accountRead(env,'google_123','user:google_123')).isPremium,true);
}));

test('KV projection failure cannot lose credited payment or invalidate primary reads',async()=>withProvider(async()=>{
 const{env,objects}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const order=await seedOrder(env);env.INSTALLS.failPuts=true;
 assert.equal((await callback(env,order)).status,200);assert.equal(JSON.parse(await accountRead(env,'google_123','user:google_123')).isPremium,true);
 env.INSTALLS.failPuts=false;await objects.get('google_123').alarm();assert.equal(JSON.parse(await env.INSTALLS.get('user:google_123')).isPremium,true);
}));

test('confirmed historic order missing profile credit is repaired without granting a fresh period today',async()=>withProvider(async()=>{
 const{env}=fixture();const confirmedAt=new Date(Date.now()-2*86400000).toISOString();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const order=await seedOrder(env,{status:'confirmed',confirmedAt});
 assert.equal((await callback(env,order)).status,200);const user=JSON.parse(await accountRead(env,'google_123','user:google_123'));
 assert.equal(user.premiumExpiresAt,new Date(Date.parse(confirmedAt)+7*86400000).toISOString());assert.equal(user.webPayments[order.orderId].legacyReconciled,true);
}));

test('self deletion removes personal remnants, denies old session immediately and holds late payments for refund',async()=>withProvider(async()=>{
 const{env}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));await env.INSTALLS.put('user_admin:google_123','{"note":"fixture"}');await env.INSTALLS.put('pay_intent:google_123','{"email":"fixture@example.invalid"}');const order=await seedOrder(env);const token=await session(env);
 assert.equal((await worker.fetch(request('/api/user/delete',{userId:'google_123'},token),env)).status,200);
 for(const prefix of ['user:','user_admin:','pay_intent:'])assert.equal(await accountRead(env,'google_123',prefix+'google_123'),null);
 assert.equal((await worker.fetch(request('/api/user/status',undefined,token),env)).status,401);
 assert.equal((await callback(env,order)).status,200);assert.equal(await accountRead(env,'google_123','user:google_123'),null);assert.equal(JSON.parse(await accountRead(env,'google_123','pay_order:'+order.orderId)).status,'requires_refund');
}));

test('missing binding fails closed and a premature authenticated callback retries instead of ignored success',async()=>withProvider(async()=>{
 const{env}=fixture();const fresh={...env,ACCOUNTS:null};assert.equal((await worker.fetch(request('/api/user/status'),fresh)).status,503);
 assert.equal((await callback(env,{orderId:crypto.randomUUID(),txId:crypto.randomUUID()})).status,503);
}));

test('large bilingual progress is atomically chunked below Durable Object value limits and survives restart',async()=>{
 const{env,states,restart}=fixture();const token=await session(env);
 const progress={questionProgressAb:Object.fromEntries(Array.from({length:800},(_,i)=>['question-'+i,{answeredAt:Date.now(),correct:true,comment:'Казахский русский текст '.repeat(25)}]))};
 assert.ok(Buffer.byteLength(JSON.stringify(progress))>128*1024);
 const response=await worker.fetch(request('/api/user/progress/sync',{userId:'google_123',progress},token),env);assert.equal(response.status,200);
 for(const value of states.get('google_123').data.values())assert.ok(Buffer.byteLength(JSON.stringify(value))<128*1024);
 restart('google_123');const loaded=await(await worker.fetch(request('/api/user/progress?userId=google_123',undefined,token),env)).json();assert.equal(Object.keys(loaded.progress.questionProgressAb).length,800);assert.equal(loaded.progress.questionProgressAb['question-7'].comment,progress.questionProgressAb['question-7'].comment);
});

test('lost Platega create response retains durable reservation; no second POST and tx-only callback recovers it',async()=>{
 const{env,restart}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const token=await session(env),original=globalThis.fetch;let creates=0,orderId;const txId=crypto.randomUUID();
 globalThis.fetch=async(url,options)=>{
  if(String(url).endsWith('/transaction/process')){creates++;orderId=JSON.parse(options.body).payload;throw new DOMException('fixture lost response','TimeoutError');}
  assert.ok(String(url).endsWith('/transaction/'+txId));return Response.json({status:'CONFIRMED',payload:orderId,paymentDetails:{amount:99,currency:'RUB'}});
 };
 try{const body={email:'receipt@example.invalid',tier:'weekly',method:'sbp'};
  assert.equal((await worker.fetch(request('/api/user/pay-intent',body,token),env)).status,503);assert.equal(creates,1);
  const reserved=JSON.parse(await accountRead(env,'google_123','pay_order:'+orderId));assert.equal(reserved.status,'creating');assert.equal(reserved.txId,null);
  restart('google_123');assert.equal((await worker.fetch(request('/api/user/pay-intent',body,token),env)).status,503);assert.equal(creates,1);
  const clock=Date.now;Date.now=()=>clock()+21*60000;
  try{for(let i=0;i<2;i++)assert.equal((await worker.fetch(request('/api/user/pay-intent',body,token),env)).status,409);assert.equal(creates,1);assert.equal(JSON.parse(await accountRead(env,'google_123','pay_order:'+orderId)).status,'creation_unknown');}finally{Date.now=clock;}
  assert.equal((await callback(env,{txId})).status,200);
  const paid=JSON.parse(await accountRead(env,'google_123','user:google_123'));assert.equal(paid.isPremium,true);assert.ok(paid.webPayments[orderId]);
  assert.equal(JSON.parse(await accountRead(env,'google_123','pay_order:'+orderId)).status,'confirmed');
 }finally{globalThis.fetch=original;}
});

test('local TTLs expire in the primary and signed logout cannot replay through stale KV',async()=>{
 const{env,objects}=fixture();const token=await session(env);
 const rpc=await env.ACCOUNTS.get('google_123').fetch('https://account.internal/_account/write',{method:'POST',headers:{'x-account-id':'google_123'},body:JSON.stringify({key:'notified_purch:expired',value:'1',options:{expiration:Math.floor(Date.now()/1000)-1}})});assert.equal(rpc.status,200);
 assert.equal(await accountRead(env,'google_123','notified_purch:expired'),null);await objects.get('google_123').alarm();assert.equal(await env.INSTALLS.get('notified_purch:expired'),null);
 assert.equal((await worker.fetch(request('/api/auth/logout',{},token),env)).status,200);
 assert.equal((await worker.fetch(request('/api/user/status',undefined,token),env)).status,401);
});

test('financial commit includes a durable notification outbox; queue outage and object restart cannot lose it',async()=>withProvider(async()=>{
 const{env,states,objects,restart}=fixture();env.BOT_TOKEN='fixture-bot';env.CHAT_ID='fixture-chat';let available=false;const queued=[];
 env.TELEGRAM={idFromName:id=>id,get:()=>({fetch:async(_url,options)=>{queued.push(JSON.parse(options.body));return Response.json({ok:available},{status:available?200:503});}})};
 env.STATS={idFromName:id=>id,get:()=>({fetch:async()=>Response.json({ok:true})})};
 await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const order=await seedOrder(env);assert.equal((await callback(env,order)).status,200);
 assert.equal(JSON.parse(await env.INSTALLS.get('user:google_123')).isPremium,true);assert.equal([...states.get('google_123').data.keys()].filter(k=>k.startsWith('effect:')).length,1);
 restart('google_123');available=true;await accountRead(env,'google_123','user:google_123');await objects.get('google_123').alarm();
 assert.equal([...states.get('google_123').data.keys()].filter(k=>k.startsWith('effect:')).length,0);assert.ok(queued.length>=2);assert.ok(queued.every(item=>item.dedupKey==='pay_paid:'+order.orderId));
}));


test('admin user IDs normalize before DO routing and never escape canonical account transaction',async()=>{
 const{env,restart}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const token=await session(env);await accountRead(env,'google_123','user:google_123');
 assert.equal((await worker.fetch(request('/api/admin/users/grant-premium',{userId:'x'.repeat(221),days:7},null,{authorization:'Bearer fixture-admin'}),env)).status,400);
 const grant=await worker.fetch(request('/api/admin/users/grant-premium',{userId:' google_123 ',days:7,notify:false},null,{authorization:'Bearer fixture-admin'}),env);assert.equal(grant.status,200);
 restart('google_123');const user=JSON.parse(await accountRead(env,'google_123','user:google_123'));assert.equal(user.isPremium,true);assert.ok(user.entitlements.admin_grant);
 await worker.fetch(request('/api/user/sync',{id:'google_123'},token),env);assert.equal(JSON.parse(await accountRead(env,'google_123','user:google_123')).isPremium,true);
 const detail=await worker.fetch(request('/api/admin/users/detail?id=%20google_123%20',undefined,null,{authorization:'Bearer fixture-admin'}),env);assert.equal(detail.status,200);
});


test('alarm is durable before primary commit so a crash before first flush cannot strand outbox',async()=>{
 const{env,objects,states,restart}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));await accountRead(env,'google_123','user:google_123');
 const object=objects.get('google_123');object.flush=async()=>{throw new Error('fixture death immediately after primary commit');};
 const response=await worker.fetch(request('/api/admin/users/grant-premium',{userId:'google_123',days:7,notify:false},null,{authorization:'Bearer fixture-admin'}),env);assert.equal(response.status,500);
 assert.equal(JSON.parse(await env.INSTALLS.get('user:google_123')).isPremium,undefined);assert.ok((await states.get('google_123').list({prefix:'projection:'})).size>0);assert.ok(await states.get('google_123').getAlarm());
 restart('google_123');assert.equal(JSON.parse(await accountRead(env,'google_123','user:google_123')).isPremium,true);await objects.get('google_123').alarm();assert.equal(JSON.parse(await env.INSTALLS.get('user:google_123')).isPremium,true);assert.equal((await states.get('google_123').list({prefix:'projection:'})).size,0);
});


test('admin recovery rereads provider payload/status and credits an unknown creation exactly once',async()=>{
 const{env}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const order=await seedOrder(env,{status:'creation_unknown',txId:null});const original=globalThis.fetch;let payload='foreign-order';
 globalThis.fetch=async()=>Response.json({status:'CONFIRMED',payload,paymentDetails:{amount:99,currency:'RUB'}});
 const body={userId:'google_123',order:order.orderId,txId:'provider-fixture'};const recover=()=>worker.fetch(request('/api/admin/users/reconcile-payment',body,null,{authorization:'Bearer fixture-admin'}),env);
 try{assert.equal((await worker.fetch(request('/api/admin/users/reconcile-payment',body),env)).status,401);assert.equal((await recover()).status,409);assert.equal(await accountRead(env,'google_123','payment_ledger:'+order.orderId),null);
 payload=order.orderId;assert.equal((await recover()).status,200);const before=JSON.parse(await accountRead(env,'google_123','user:google_123'));assert.equal(before.isPremium,true);assert.equal(JSON.parse(await accountRead(env,'google_123','pay_order:'+order.orderId)).status,'confirmed');assert.equal((await recover()).status,200);assert.equal(JSON.parse(await accountRead(env,'google_123','user:google_123')).premiumExpiresAt,before.premiumExpiresAt);
 }finally{globalThis.fetch=original;}
});


test('unknown creation stays blocked after verified PENDING and unlocks only after verified cancellation',async()=>{
 const{env}=fixture();await env.INSTALLS.put('user:google_123',JSON.stringify(identity()));const order=await seedOrder(env,{status:'creation_unknown',txId:null});await env.INSTALLS.put('pay_intent:google_123',JSON.stringify({lastOrder:{orderId:order.orderId}}));const token=await session(env);const original=globalThis.fetch;let status='PENDING',creates=0;
 globalThis.fetch=async(url)=>{if(String(url).endsWith('/transaction/process')){creates++;return Response.json({transactionId:'new-provider-tx',redirect:'https://pay.example.invalid/fixture'});}return Response.json({status,payload:order.orderId,paymentDetails:{amount:99,currency:'RUB'}});};
 const recover=()=>worker.fetch(request('/api/admin/users/reconcile-payment',{userId:'google_123',order:order.orderId,txId:'pending-provider-tx'},null,{authorization:'Bearer fixture-admin'}),env);
 try{const pending=await(await recover()).json();assert.equal(pending.status,'creation_unknown');const blocked=await worker.fetch(request('/api/user/pay-intent',{email:'receipt@example.invalid',tier:'weekly',method:'sbp'},token),env);assert.equal(blocked.status,409);assert.equal((await blocked.json()).code,'payment_creation_unknown');assert.equal(creates,0);
 status='CANCELED';assert.equal((await(await recover()).json()).status,'canceled');assert.equal((await worker.fetch(request('/api/user/pay-intent',{email:'receipt@example.invalid',tier:'weekly',method:'sbp'},token),env)).status,200);assert.equal(creates,1);
 }finally{globalThis.fetch=original;}
});
