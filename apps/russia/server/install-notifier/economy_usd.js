// Primary USD view. Native USD amounts never round-trip through historical RUB.
// Legacy RUB response fields remain for older clients; the UI consumes this view.
import { profitAllocation } from './economy_shares.js';

const round=n=>Math.round((n+Number.EPSILON)*100)/100;
const sum=(items,key)=>round(items.reduce((total,item)=>total+(item[key]||0),0));
export function economyInUsd(data,fx){
 const rate=fx.rubPerUsd,convert=rub=>round(rub/rate),native=(amount,currency)=>currency==='USD'?round(amount):convert(amount);
 const receipts=data.receipts.filter(r=>!r.isTest).map(r=>{
   const amountUsd=r.type==='manual'?native(r.amount,r.currency):convert(r.amountRub);
   const feeUsd=r.storeKey==='web'&&r.includedInRevenue?round(amountUsd*data.config.paymentFeePercent/100):0;
   return {...r,amountUsd,feeUsd,netUsd:round(amountUsd-feeUsd)};
 });
 const lines=data.expenses.lines.map(line=>{
   const amountUsd=native(line.amount??line.amountRub,line.currency);
   const periodUsd=line.builtin?(line.currency==='USD'?round(line.amount*data.periodInfo.budgetMonths):convert(line.periodRub)):round(amountUsd*line.occurrences);
   const monthlyUsd=line.builtin?amountUsd:line.monthlyRub>0?round(amountUsd/(line.frequency==='yearly'?12:1)):0;
   return {...line,amountUsd,periodUsd,monthlyUsd};
 });
 const withdrawals=data.withdrawals.map(row=>{
   const amountUsd=native(row.amount,row.currency),feeUsd=native(row.fee,row.currency);
   return {...row,amountUsd,feeUsd,receivedUsd:row.feeMode==='included'?round(amountUsd-feeUsd):amountUsd,debitedUsd:row.feeMode==='additional'?round(amountUsd+feeUsd):amountUsd};
 });
 const included=receipts.filter(r=>r.includedInRevenue),byStore=store=>sum(included.filter(r=>r.storeKey===store),'amountUsd');
 const grossUsd=sum(included,'amountUsd'),paymentFeesUsd=sum(receipts,'feeUsd'),withdrawalFeesUsd=sum(withdrawals,'feeUsd');
 const aiUsd=round(data.expenses.ai.usd||0),aiPeriod=data.expenses.ai.includedInTotal?aiUsd:0;
 const totalUsd=round(sum(lines,'periodUsd')+paymentFeesUsd+withdrawalFeesUsd+aiPeriod),operatingUsd=round(grossUsd-totalUsd);
 const allocation=profitAllocation(data.config,operatingUsd);
 const monthlyUsd=round(sum(lines,'monthlyUsd')+(data.cloudflare?.subscriptions||[]).reduce((n,s)=>n+s.usd,0));
 return {currency:'USD',fx,receipts,withdrawals,withdrawalSummary:{count:withdrawals.length,amountUsd:sum(withdrawals,'amountUsd'),feeUsd:withdrawalFeesUsd,receivedUsd:sum(withdrawals,'receivedUsd'),debitedUsd:sum(withdrawals,'debitedUsd')},
 revenue:{...data.revenue,grossUsd,webUsd:byStore('web'),appstoreUsd:byStore('appstore'),gplayUsd:byStore('googleplay'),rustoreUsd:byStore('rustore'),otherUsd:byStore('other'),includedStoreSalesUsd:sum(included.filter(r=>r.type==='estimate'),'amountUsd')},
 expenses:{...data.expenses,totalUsd,monthlyUsd,paymentFeesUsd,withdrawalFeesUsd,lines,ai:{...data.expenses.ai,usd:aiUsd,periodUsd:aiPeriod}},
 profit:{...data.profit,operatingUsd,reinvestUsd:allocation.reinvest,distributableNetUsd:allocation.distributable,marginPercent:grossUsd>0?round(allocation.distributable/grossUsd*100):0},
 profitShares:allocation.shares.map(({amount,...share},i)=>({...data.profitShares[i],...share,payoutUsd:amount})),
 partners:Object.fromEntries(Object.entries(allocation.partners).map(([key,partner])=>[key,{...data.partners[key],payoutUsd:partner.amount}])),
 unitEconomics:{...data.unitEconomics,arppu: data.unitEconomics.activePayingCount?round(grossUsd/data.unitEconomics.activePayingCount):0,arpu:data.unitEconomics.totalUsersCount?round(grossUsd/data.unitEconomics.totalUsersCount):0},
 tariffs:{weeklyUsd:convert(99),quarterlyUsd:convert(290)},targetMonthlyProfitUsd:round(data.config.targetMonthlyProfit/data.config.usdRate),
 };
}
