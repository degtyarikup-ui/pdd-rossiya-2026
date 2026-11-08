import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { fixture, identity, session, request } from './fixture-account.mjs';
import { accountRead } from './account_state.js';
const DAY = 86400000;
const admin = (env, body) => worker.fetch(request('/api/admin/promocodes', body, 'fixture-admin'), env);
const campaign = (code, extra = {}) => ({ operation: 'create', code, days: 7, maxUses: 10,
  startsAt: new Date(Date.now()-DAY).toISOString(), expiresAt: new Date(Date.now()+DAY).toISOString(), ...extra });
async function user(env, id, age = 0) {
  await env.INSTALLS.put('user:'+id, JSON.stringify({...identity(id),email:id+'@example.invalid',createdAt:new Date(Date.now()-age).toISOString()}));
  return session(env,id);
}
const claim = (env, token, code) => worker.fetch(request('/api/user/promo/claim',{code,days:365,userId:'google_victim'},token),env);

test('promotion admin and public endpoints require their own credentials', async () => {
 const {env}=fixture();
 assert.equal((await worker.fetch(request('/api/admin/promocodes',campaign('SALE7'),null),env)).status,401);
 const token=await user(env,'google_one');
 assert.equal((await worker.fetch(request('/api/admin/promocodes',campaign('SALE7'),token),env)).status,401);
 assert.equal((await claim(env,null,'SALE7')).status,401);
 assert.equal((await admin(env,campaign('SALE7'))).status,200);
 assert.equal((await admin(env,campaign('SALE7'))).status,409);
 assert.equal((await admin(env,campaign('BAD1',{days:-1}))).status,400);
 assert.equal((await admin(env,campaign('BAD2',{maxUses:0}))).status,400);
 assert.equal((await admin(env,campaign('BAD3',{expiresAt:'invalid'}))).status,400);
});

test('promotion works for old accounts, ignores client rewards and is replay safe',async()=>{
 const {env}=fixture(); const token=await user(env,'google_old',30*DAY);
 await admin(env,campaign('SALE7'));
 const first=await claim(env,token,'SALE7');assert.equal(first.status,200); const data=await first.json();
 assert.equal(data.kind,'promotion');assert.equal(data.daysAdded,7);
 const repeated=await claim(env,token,'SALE7');assert.equal((await repeated.json()).premiumExpiresAt,data.premiumExpiresAt);
 const profile=JSON.parse(await accountRead(env,'google_old','user:google_old'));
 assert.equal(profile.premiumSource,'promo');assert.equal(profile.referralCodeUsed,undefined);
 assert.equal((await (await admin(env)).json()).codes[0].uses,1);
});

test('concurrent claims respect capacity and do not double grant',async()=>{
 const {env}=fixture();const a=await user(env,'google_a'),b=await user(env,'google_b');
 await admin(env,campaign('LIMIT1',{maxUses:1}));
 const results=await Promise.all([claim(env,a,'LIMIT1'),claim(env,a,'LIMIT1'),claim(env,b,'LIMIT1')]);
 assert.deepEqual(results.map(r=>r.status),[200,200,400]);
 assert.equal((await results[2].json()).error,'promo_exhausted');
 assert.equal((await (await admin(env)).json()).codes[0].uses,1);
});

test('campaign dates, disabling, unknown codes and attempts are enforced',async()=>{
 const {env}=fixture();const token=await user(env,'google_a');
 await admin(env,campaign('FUTURE',{startsAt:new Date(Date.now()+DAY).toISOString(),expiresAt:new Date(Date.now()+2*DAY).toISOString()}));
 assert.equal((await (await claim(env,token,'FUTURE')).json()).error,'promo_not_started');
 await admin(env,campaign('PAUSED'));await admin(env,{operation:'toggle',code:'PAUSED',enabled:false});
 assert.equal((await (await claim(env,token,'PAUSED')).json()).error,'promo_inactive');
 for(let i=0;i<6;i++)assert.equal((await claim(env,token,'MISSING')).status,404);
 assert.equal((await claim(env,token,'MISSING')).status,429);
});

test('friend eligibility is exactly seven days and cannot be reset with a request',async()=>{
 const realNow=Date.now; const fixed=realNow(); Date.now=()=>fixed;
 try {
  const {env}=fixture();const inviter=await user(env,'google_inviter',30*DAY);
  const code=(await (await worker.fetch(request('/api/user/referral',undefined,inviter),env)).json()).code;
  for (const [name,age,status] of [['fresh',0,200],['boundary',7*DAY,200],['old',7*DAY+1,400]]) {
   const token=await user(env,'google_'+name,age);
   const res=await claim(env,token,code);assert.equal(res.status,status);
   if(status===400)assert.equal((await res.json()).error,'referral_ineligible');
  }
  // Common namespace prevents an advertising campaign from taking a friend's code.
  assert.equal((await admin(env,campaign(code))).status,409);
 } finally {Date.now=realNow;}
});

test('alarm retries a committed reward after response loss without consuming a second use',async()=>{
 const {env,objects,states}=fixture();const token=await user(env,'google_retry');
 await admin(env,campaign('RETRY7'));
 const original=env.ACCOUNTS.get;
 let lost=false;
 env.ACCOUNTS.get=id=>({fetch:async(req,opts)=>{
  const res=await original(id).fetch(req,opts);
  if(id==='google_retry' && String(typeof req==='string'?req:req.url).endsWith('/_account/promo')) {
   const data=await res.clone().json();
   if(data.ok&&!lost){lost=true;throw new Error('lost grant response');}
  }
  return res;
 }});
 assert.equal((await claim(env,token,'RETRY7')).status,500);
 const before=JSON.parse(await accountRead(env,'google_retry','user:google_retry')).premiumExpiresAt;
 await objects.get('promotions').alarm();
 assert.equal(JSON.parse(await accountRead(env,'google_retry','user:google_retry')).premiumExpiresAt,before);
 assert.equal((await states.get('promotions').list({prefix:'promo-pending:'})).size,0);
 assert.equal((await (await admin(env)).json()).codes[0].uses,1);
});

test('expiry boundary rejects new claims but keeps confirmed retries recoverable',async()=>{
 const {env}=fixture(); const a=await user(env,'google_a'),b=await user(env,'google_b');
 const expiry=Date.now()+DAY;await admin(env,campaign('EXPIRES',{expiresAt:new Date(expiry).toISOString()}));
 const first=await (await claim(env,a,'EXPIRES')).json();
 const realNow=Date.now;Date.now=()=>expiry;
 try {
  // Use the internal coordinator: the fixture's public session expires before the campaign.
  const {accountRpc}=await import('./account_state.js');
  const call=id=>accountRpc(env,'promotions','/_promo/catalog',{operation:'claim',userId:id,code:'EXPIRES'});
  assert.equal((await (await call('google_b')).json()).error,'promo_expired');
  assert.equal((await (await call('google_a')).json()).premiumExpiresAt,first.premiumExpiresAt);
 } finally {Date.now=realNow;}
});

test('missing or future registration dates cannot collect a friend bonus',async()=>{
 const {env}=fixture();const inviter=await user(env,'google_inviter');
 const {code}=await (await worker.fetch(request('/api/user/referral',undefined,inviter),env)).json();
 for(const [id,createdAt] of [['google_missing',null],['google_future',new Date(Date.now()+DAY).toISOString()]]) {
  await env.INSTALLS.put('user:'+id,JSON.stringify({...identity(id),createdAt}));
  assert.equal((await (await claim(env,await session(env,id),code)).json()).error,'referral_ineligible');
 }
});
