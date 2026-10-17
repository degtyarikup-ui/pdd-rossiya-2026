import { createRemoteJWKSet, jwtVerify, decodeJwt } from 'jose';
import { accountRpc, accountRead } from './account_state.js';
import { tokenHash } from './user_auth.js';
const keys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
export async function appleNotificationToken(env) {
  if (!env.SESSION_SECRET) return '';
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.SESSION_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return [...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode('apple-store-callback-v1')))].map(b=>b.toString(16).padStart(2,'0')).join('');
}
function same(a,b){if(!a||!b||a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}
export async function verifyGooglePush(request, env) {
  if (!env.GOOGLE_RTDN_AUDIENCE || !env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL) return false;
  const token=request.headers.get('authorization')?.match(/^Bearer (\S{1,16384})$/)?.[1];if(!token)return false;
  try{const{payload}=await jwtVerify(token,keys,{algorithms:['RS256'],issuer:['https://accounts.google.com','accounts.google.com'],audience:env.GOOGLE_RTDN_AUDIENCE,requiredClaims:['sub','exp','iat']});return payload.email===env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL&&payload.email_verified===true;}catch{return false;}
}
async function receiptOwner(env,key){
 const r=await env.PURCHASE_CLAIMS.get(env.PURCHASE_CLAIMS.idFromName(key)).fetch('https://purchase-claims/owner');return r.ok?(await r.json()).userId:null;
}
export async function handleStoreNotification(request, env, store, verifyGoogle=verifyGooglePush) {
  if (!env.ACCOUNTS || !env.PURCHASE_CLAIMS) return reply({error:'store notifications unavailable'},503);
  if (request.method!=='POST') return reply({error:'method not allowed'},405);
  if (Number(request.headers.get('content-length'))>32768) return reply({error:'too large'},413);
  if(store==='appstore') {
   if(!same(new URL(request.url).searchParams.get('token')||'',await appleNotificationToken(env)))return reply({error:'unauthorized'},401);
  } else if (!await verifyGoogle(request,env))return reply({error:'unauthorized'},401);
  const reader=request.body?.getReader();if(!reader)return reply({error:'invalid json'},400);
  const parts=[];let length=0;
  while(true){const{done,value}=await reader.read();if(done)break;length+=value.length;if(length>32768){await reader.cancel();return reply({error:'too large'},413);}parts.push(value);}
  const bytes=new Uint8Array(length);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  const raw=new TextDecoder().decode(bytes);
  let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid json'},400);}
  let key,reference;
  try {
   if(store==='appstore') {
    // The configured callback has a private MAC token. JWS fields are only
    // lookup hints: entitlement always comes from an authenticated Apple API
    // reread in AccountState, including exact originalTransactionId/account UUID.
    const envelope=decodeJwt(body.signedPayload);
    if(envelope.notificationType==='TEST')return reply({ok:true,test:true});
    const tx=decodeJwt(envelope.data?.signedTransactionInfo);
    if(!/^\d{1,40}$/.test(tx.transactionId||'')||!/^\d{1,40}$/.test(tx.originalTransactionId||''))throw new Error('invalid transaction');
    key='appstore:'+tx.originalTransactionId;reference={store,country:'ru',productId:tx.productId,transactionId:tx.transactionId};
   } else {
    const data=JSON.parse(atob(body.message?.data||''));
    if(data.testNotification)return reply({ok:true,test:true});
    if(data.packageName!=='ru.pdd.pdd_app')return reply({error:'wrong package'},400);
    const token=data.subscriptionNotification?.purchaseToken;if(typeof token!=='string'||token.length>8192)throw new Error('invalid transaction');
    key='googleplay:ru:'+await tokenHash(token);reference={store,country:'ru',purchaseToken:token};
   }
   const userId=await receiptOwner(env,key);if(!userId)return reply({error:'purchase owner not ready'},503);
   if(store==='googleplay') {
    const user=JSON.parse(await accountRead(env,userId,'user:'+userId)||'null');
    const saved=user?.verifiedPurchases?.googleplay||user?.verifiedPurchase;
    if(!saved||saved.store!=='googleplay')return reply({error:'purchase reference not ready'},503);
    reference.productId=saved.productId;
   }
   const response=await accountRpc(env,userId,'/_account/iap-event',{reference,key});
   return response?.ok?reply({ok:true}):response?.status===410?reply({ok:true,accountDeleted:true}):reply({error:'store status unavailable'},503);
  } catch{return reply({error:'invalid or unavailable store event'},503);}
}
