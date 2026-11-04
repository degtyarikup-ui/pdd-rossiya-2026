import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeInvoices, normalizeUsage, getCloudflareBilling, cloudflareExpenseLines } from './economy_cloudflare.js';
import { computeEconomyStats, DEFAULT_ECONOMY_CONFIG } from './economy_admin.js';
import worker from './worker.js';
const now = Date.parse('2026-11-04T12:00:00Z');
const invoice = (id, amount, date) => ({ id, invoice_id: id, type: 'invoice', status: 'CLOSED', amount, currency: 'usd', occurred_at: date, receipt_id: 'IN-' + id });
const history = [invoice('hosting',10.15,'2026-10-22T10:47:07Z'),invoice('domain',1,'2026-10-10T21:50:08Z'),invoice('base',5,'2026-09-22T22:31:50Z')];
function env() {
 const store = new Map(); return { ADMIN_PASSWORD: crypto.randomUUID(), CLOUDFLARE_BILLING_TOKEN: crypto.randomUUID(), CLOUDFLARE_BILLING_ACCOUNT_ID: 'account', INSTALLS: { get: async key => store.get(key) ?? null, put: async (key,v) => store.set(key,v), list: async () => ({keys:[],list_complete:true}), store } };
}
const usage = [{ ChargeCategory:'Usage',BillingCurrency:'USD',BilledCost:0.15,ServiceFamilyName:'Durable Objects',ChargePeriodEnd:'2026-11-04T00:00:00Z',BillingPeriodStart:'2026-10-22T00:00:00Z' }];
const fakeFetch = async url => Response.json({success:true,result:url.includes('history')?history:url.endsWith('subscriptions')?[{state:'Paid',frequency:'monthly',currency:'USD',price:5,rate_plan:{public_name:'Workers Paid'}}]:usage,result_info:{next_page:false}});
test('invoice ledger excludes payments/open records, deduplicates and uses Moscow date', () => {
 const data=normalizeInvoices([...history,history[0],{...history[0],id:'payment',type:'payment'}, {...history[0],id:'open',status:'OPEN'}]);
 assert.equal(data.invoices.length,3); assert.equal(data.pending,2); assert.equal(data.invoices[1].date,'2026-10-11');
 assert.throws(()=>normalizeInvoices([{...history[0],amount:'10.15'}]));
 assert.throws(()=>normalizeInvoices([history[0],{...history[0],amount:20}]));
 assert.equal(normalizeUsage(usage).usd,0.15);
});
test('paginated import, hourly cache, single-flight and stale preservation', async () => {
 const e=env();let calls=0;
 const fetch=async url=>{calls++;if(url.includes('history'))return Response.json({success:true,result:url.includes('page=2')?history.slice(1):history.slice(0,1),result_info:{next_page:!url.includes('page=2')}});return fakeFetch(url);};
 const [a,b]=await Promise.all([getCloudflareBilling(e,{now,fetch}),getCloudflareBilling(e,{now,fetch})]);
 assert.equal(calls,4);assert.deepEqual(a,b);assert.equal(a.invoices.length,3);
 await getCloudflareBilling(e,{now:now+1000,fetch});assert.equal(calls,4);
 const stale=await getCloudflareBilling(e,{now:now+3600001,fetch:async()=>new Response('',{status:403})});
 assert.equal(stale.stale,true);assert.deepEqual(stale.invoices,a.invoices);assert.ok(!JSON.stringify(stale).includes(e.CLOUDFLARE_BILLING_TOKEN));
 await assert.rejects(getCloudflareBilling(env(),{now,fetch:async()=>new Response('',{status:403})}));
});
test('usage failure does not discard verified invoices or invent zero usage',async()=>{
 const data=await getCloudflareBilling(env(),{now,fetch:async url=>url.endsWith('billable-usage')?new Response('',{status:503}):fakeFetch(url)});
 assert.equal(data.invoices.length,3);assert.equal(data.usage,null);
});
test('real invoices replace budget and exactly matched legacy records once; usage stays outside profit',async()=>{
 const e=env();const extraExpenses=[{id:'manual-host',title:'Cloudflare',amount:10.15,currency:'USD',date:'2026-10-22',frequency:'once'},{id:'manual-domain',title:'Покупка домена на Claudlfare (pdd-drive.app)',amount:1,currency:'USD',date:'2026-10-11',frequency:'once'}];
 await e.INSTALLS.put('economy_config',JSON.stringify({...DEFAULT_ECONOMY_CONFIG,domainEnabled:false,extraExpenses}));
 const all=await computeEconomyStats(e,'all',{now,fetch:fakeFetch});
 assert.equal(all.expenses.totalRub,1534.25); // $16.15, no duplicate $11.15, no monthly budget or $0.15 usage
 assert.equal(all.expenses.lines.length,3);assert.equal(all.expenses.monthlyRub,475);
 assert.equal(all.expenses.lines.filter(l=>l.matchedManualId).length,2);
 assert.equal(all.config.extraExpenses.length,2);
 const month=await computeEconomyStats(e,'month',{now,fetch:fakeFetch});assert.equal(month.expenses.totalRub,0);
 const recent=await computeEconomyStats(e,'30d',{now,fetch:fakeFetch});assert.equal(recent.expenses.totalRub,1059.25);
 const ambiguous=cloudflareExpenseLines(all.cloudflare,[extraExpenses[0],{...extraExpenses[0],id:'another'}],95,'1970-01-01','2026-11-04');assert.equal(ambiguous.replaced.size,0);
});
test('billing routes require admin auth before any network or storage work',async()=>{
 const e=env();const response=await worker.fetch(new Request('https://example.invalid/api/admin/economy/cloudflare/sync',{method:'POST'}),e,{waitUntil(){}});
 assert.equal(response.status,401);assert.equal(e.INSTALLS.store.size,0);
});
