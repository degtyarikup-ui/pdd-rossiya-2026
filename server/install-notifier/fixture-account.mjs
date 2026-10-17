import { AccountState } from './account_state.js';
import { AiQuotaState } from './ai_quota.js';
import { signSession } from './user_auth.js';
const appCredential = crypto.randomUUID();
const adminCredential = 'fixture-admin';
const paymentCredential = 'fixture-pay';
export class MemoryStorage {
  constructor() { this.data = new Map(); this.tail = Promise.resolve(); this.alarm = null; this.failCommit = false; }
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { return this.data.delete(key); }
  async list({ prefix = '', limit = 1000 } = {}) { return new Map([...this.data].filter(([key]) => key.startsWith(prefix)).sort().slice(0, limit).map(([k,v])=>[k,structuredClone(v)])); }
  async setAlarm(value) { this.alarm = value; }
  async getAlarm() { return this.alarm; }
  async transaction(fn) {
    const result = this.tail.then(async () => {
      const copy = new Map([...this.data].map(([k,v]) => [k,structuredClone(v)]));
      const txn = { get: async key => structuredClone(copy.get(key)), put: async (key,value) => copy.set(key,structuredClone(value)), delete: async key => copy.delete(key) };
      const value = await fn(txn);
      if (this.failCommit) { this.failCommit = false; throw new Error('fixture transaction commit failure'); }
      this.data = copy; return value;
    });
    this.tail = result.catch(()=>{}); return result;
  }
}
export class MemoryKV {
  constructor() { this.data = new Map(); this.meta = new Map(); this.failPuts = false; }
  async get(key, options) { const raw=this.data.get(key) ?? null; return options === 'json' || options?.type==='json' ? raw && JSON.parse(raw) : raw; }
  async put(key, value, options={}) { if(this.failPuts)throw new Error('fixture KV unavailable');this.data.set(key,String(value));if(options.metadata)this.meta.set(key,options.metadata); }
  async delete(key) { this.data.delete(key);this.meta.delete(key); }
  async list({prefix='',limit=1000,cursor='0'}={}) {const keys=[...this.data.keys()].filter(k=>k.startsWith(prefix)).sort();const start=Number(cursor);const page=keys.slice(start,start+limit);return{keys:page.map(name=>({name,metadata:this.meta.get(name)})),list_complete:start+page.length>=keys.length,cursor:String(start+page.length)};}
}
export function fixture() {
  const env={INSTALLS:new MemoryKV(),SHARED_SECRET:appCredential,SESSION_SECRET:crypto.randomUUID(),ADMIN_PASSWORD:adminCredential,PLATEGA_SECRET:paymentCredential,PLATEGA_MERCHANT_ID:crypto.randomUUID(),ACCOUNT_STATE_REQUIRED:'true'};
  const states=new Map(),objects=new Map();
  env.ACCOUNTS={idFromName:id=>id,get:id=>({fetch:(request,options)=>{if(!states.has(id))states.set(id,new MemoryStorage());if(!objects.has(id))objects.set(id,new AccountState({storage:states.get(id)},env));return objects.get(id).fetch(typeof request==='string'?new Request(request,options):request);}})};
  const quotaStorage=new MemoryStorage(),quota=new AiQuotaState({storage:quotaStorage});
  env.AI_QUOTAS={idFromName:id=>id,get:()=>({fetch:(url,options)=>quota.fetch(new Request(url,options))})};
  return{env,states,objects,quotaStorage,restart:id=>objects.delete(id)};
}
export const identity=(id='google_123')=>({id,provider:id.split('_')[0],name:'Fixture user',email:'fixture@example.invalid',createdAt:new Date().toISOString()});
export async function session(env,id='google_123') {return signSession(env,{user:identity(id),expiresAt:Date.now()+3600000,generation:''});}
export function request(path,body,token,extra={}) {return new Request('https://fixture.invalid'+path,{method:body===undefined?'GET':'POST',headers:{'content-type':'application/json','x-install-secret':appCredential,...(token?{authorization:'Bearer '+token}:{}),...extra},...(body===undefined?{}:{body:JSON.stringify(body)})});}
export async function seedOrder(env, overrides={}) {
 const order={orderId:crypto.randomUUID(),txId:crypto.randomUUID(),userId:'google_123',name:'Fixture',accountEmail:'fixture@example.invalid',app:'ru',tier:'weekly',days:7,amount:99,currency:'RUB',status:'pending',createdAt:new Date().toISOString(),...overrides};
 await env.INSTALLS.put('pay_order:'+order.orderId,JSON.stringify(order));await env.INSTALLS.put('pay_tx:'+order.txId,order.orderId);return order;
}
