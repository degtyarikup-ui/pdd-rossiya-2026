import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCbrUsd, getUsdRate } from './economy_fx.js';
import { computeEconomyStats, DEFAULT_ECONOMY_CONFIG, handleEconomyAdmin } from './economy_admin.js';
const now=Date.parse('2026-11-04T12:00:00Z');
function environment(){const store=new Map();return {INSTALLS:{get:async k=>store.get(k)??null,put:async(k,v)=>store.set(k,v),list:async({prefix})=>({keys:[...store.keys()].filter(k=>k.startsWith(prefix)).map(name=>({name})),list_complete:true}),store}};}
const xml=(date='04.11.2026',value='81,6699',nominal='1')=>`<ValCurs Date="${date}"><Valute><CharCode>EUR</CharCode><Nominal>1</Nominal><Value>90</Value></Valute><Valute ID="R01235"><CharCode>USD</CharCode><Nominal>${nominal}</Nominal><Value>${value}</Value></Valute></ValCurs>`;
test('CBR parser handles decimal comma and nominal, rejects future/malformed rates',()=>{
 assert.equal(parseCbrUsd(xml(),'2026-11-04').rubPerUsd,81.6699);
 assert.equal(parseCbrUsd(xml('03.11.2026','816,699','10'),'2026-11-04').rubPerUsd,81.6699);
 for(const bad of [xml('05.11.2026'),xml('31.02.2026'),xml(undefined,'0'),xml(undefined,'abc'),xml(undefined,'80','0'),'<html>error</html>'])assert.throws(()=>parseCbrUsd(bad,'2026-11-04'));
});
test('FX caches official date, deduplicates refresh, survives outage without fabricated rate',async()=>{
 const env=environment();let calls=0;
 const fxFetch=async(url,options)=>{calls++;assert.match(url,/date_req=04%2F11%2F2026/);assert.equal(options.redirect,'manual');return new Response(xml('03.11.2026'));};
 const [a,b]=await Promise.all([getUsdRate(env,{now,fxFetch}),getUsdRate(env,{now,fxFetch})]);assert.deepEqual(a,b);assert.equal(calls,1);
 assert.equal((await getUsdRate(env,{now:now+1000,fxFetch})).stale,false);assert.equal(calls,1);
 const failed=async()=>new Response('',{status:503});
 const fallback=await getUsdRate(env,{now:now+3600001,fxFetch:failed});assert.equal(fallback.stale,true);assert.equal(fallback.rubPerUsd,81.6699);
 await assert.rejects(getUsdRate(environment(),{now,fxFetch:failed}));
});
test('USD accounting preserves dollars, converts rubles, excludes all sandbox data and reconciles cents',async()=>{
 const env=environment();
 await env.INSTALLS.put('economy_config',JSON.stringify({...DEFAULT_ECONOMY_CONFIG,cloudflareEnabled:false,domainEnabled:false,excludeTestOrders:false,reinvestPercent:50,nikitaSharePercent:10,sergeySharePercent:90,
 extraExpenses:[{id:'dollar-expense',title:'Hosting',currency:'USD',amount:10.15,date:'2026-11-04',frequency:'once'},{id:'ruble-expense',title:'RUB expense',currency:'RUB',amount:160,date:'2026-11-04',frequency:'once'}],
 manualRevenues:[{id:'income',title:'USD income',currency:'USD',amount:20,usdRate:95,store:'other',date:'2026-11-04'}],
 withdrawals:[{id:'withdrawal',title:'Вывод',currency:'USD',amount:25,usdRate:95,fee:1.5,feeMode:'additional',store:'web',date:'2026-11-04'}]}));
 for(const [id,isTest,amount] of [['real',false,800],['test',true,800]])await env.INSTALLS.put('pay_order:'+id,JSON.stringify({orderId:id,status:'confirmed',confirmedAt:'2026-11-04T10:00:00Z',amount,isTest}));
 const users=[{id:'sandbox',isPremium:true,premiumSource:'appstore',purchasedAt:'2026-11-04T09:00:00Z',verifiedPurchase:{isTest:true,productId:'premium_3months'}}];
 const deps={now,fx:{rubPerUsd:80,effectiveDate:'2026-11-04'},listUserSummaries:async()=>users};
 const data=await computeEconomyStats(env,'month',deps),usd=data.usd;
 assert.equal(data.receipts.length,2);assert.equal(data.estimatedReceipts.length,0);assert.equal(data.config.excludeTestOrders,true);assert.equal(data.unitEconomics.activePayingCount,0);assert.equal(data.unitEconomics.totalUsersCount,0);
 assert.equal(usd.revenue.grossUsd,30);assert.equal(usd.expenses.totalUsd,14.45);assert.equal(usd.expenses.paymentFeesUsd,.8);assert.equal(usd.profit.operatingUsd,15.55);
 assert.equal(usd.withdrawals[0].receivedUsd,25);assert.equal(usd.withdrawals[0].debitedUsd,26.5);assert.equal(usd.withdrawals[0].feeUsd,1.5);
 assert.equal(Math.round((usd.partners.sergey.payoutUsd+usd.partners.nikita.payoutUsd)*100),Math.round(usd.profit.distributableNetUsd*100));
 const other=(await computeEconomyStats(env,'month',{...deps,fx:{rubPerUsd:100,effectiveDate:'2026-11-04'}})).usd;
 assert.equal(other.withdrawals[0].receivedUsd,25);assert.equal(other.receipts.find(r=>r.id==='income').amountUsd,20);assert.equal(other.expenses.lines.find(r=>r.id==='dollar-expense').periodUsd,10.15);assert.equal(other.receipts.find(r=>r.id==='real').amountUsd,8);
});
test('old clients cannot enable tests or manually change the global exchange rate',async()=>{
 const env=environment();for(const body of [{excludeTestOrders:false},{usdRate:95}]){
 const req=new Request('https://test/api/admin/economy/settings',{method:'POST',body:JSON.stringify(body)});const response=await handleEconomyAdmin(req,env,new URL(req.url));assert.equal(response.status,400);
 }
});
