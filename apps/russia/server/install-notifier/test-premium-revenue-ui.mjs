// Runs the assembled admin against isolated data; no working payments or accounts.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import { userSummary } from './user_store.js';
import { premiumRevenueInUsd } from './premium_revenue_usd.js';

const FX={source:'CBR',rubPerUsd:80,rubPerUnit:{RUB:1,USD:80,EUR:100,KZT:0.2}};
const withUsd=(data,fx=FX)=>data.available?{...data,usd:premiumRevenueInUsd(data,fx)}:data;

class MemoryKV {
 constructor(){this.store=new Map();this.metadata=new Map();}
 async get(key,options){const value=this.store.get(key)??null;return options==='json'||options?.type==='json'?value===null?null:JSON.parse(value):value;}
 async put(key,value,options){this.store.set(key,String(value));if(options?.metadata)this.metadata.set(key,options.metadata);else this.metadata.delete(key);}
 async delete(key){this.store.delete(key);this.metadata.delete(key);}
 async list({prefix='',limit=1000,cursor='0'}={}){const all=[...this.store.keys()].filter(key=>key.startsWith(prefix)).sort(),start=Number(cursor)||0;const keys=all.slice(start,start+limit).map(name=>({name,metadata:this.metadata.get(name)}));return{keys,list_complete:start+keys.length>=all.length,cursor:String(start+keys.length)};}
}
const metrics=(purchases=0,missingAmounts=0,amounts={},pricedPurchases={})=>({purchases,missingAmounts,amounts,pricedPurchases});
function revenueFixture(days=7){
 const end=Date.now()+3*3600000;
 const timeline=Array.from({length:days},(_,i)=>({date:new Date(end-(days-1-i)*86400000).toISOString().slice(0,10),...metrics()}));
 const methods=[
  {key:'web',label:'СБП',...metrics(2,0,{RUB:389000},{RUB:2})},
  {key:'appstore',label:'App Store',...metrics(1,0,{USD:4990},{USD:1})},
  {key:'googleplay',label:'Google Play',...metrics(1,1)},
 ];
 Object.assign(timeline[timeline.length-1],metrics(4,1,{RUB:389000,USD:4990},{RUB:2,USD:1}),{methods});
 return{available:true,timeZone:'Europe/Moscow',totals:metrics(4,1,{RUB:389000,USD:4990},{RUB:2,USD:1}),timeline,methods,currencies:['RUB','USD'],coverage:{historicalPurchases:false,from:timeline[0].date}};
}
// Richer isolated fixture for visual inspection; assertions use the small fixture.
function screenshotFixture(){
 const data=revenueFixture(7);
 const amounts={web:[290000,99000,580000,389000,198000,870000,488000],appstore:[0,199000,0,499000,0,199000,0],googleplay:[99000,0,199000,0,99000,290000,199000]};
 const count=(key,i)=>amounts[key][i]>0?key==='web'?Math.ceil(amounts[key][i]/290000):1:0;
 const method=(key,i)=>({key,label:{web:'СБП',appstore:'App Store',googleplay:'Google Play'}[key],...metrics(count(key,i),0,amounts[key][i]?{RUB:amounts[key][i]}:{},amounts[key][i]?{RUB:count(key,i)}:{})});
 const sum=rows=>metrics(rows.reduce((n,r)=>n+r.purchases,0),rows.reduce((n,r)=>n+r.missingAmounts,0),{RUB:rows.reduce((n,r)=>n+(r.amounts.RUB||0),0)},{RUB:rows.reduce((n,r)=>n+(r.pricedPurchases.RUB||0),0)});
 data.timeline=data.timeline.map((day,i)=>{const methods=Object.keys(amounts).map(key=>method(key,i));return{date:day.date,...sum(methods),methods};});
 data.methods=Object.keys(amounts).map(key=>({key,label:{web:'СБП',appstore:'App Store',googleplay:'Google Play'}[key],...sum(data.timeline.map(day=>day.methods.find(row=>row.key===key)))}));
 data.totals=sum(data.timeline);data.currencies=['RUB'];
 return data;
}
async function preview(){
 const env={INSTALLS:new MemoryKV(),ADMIN_PASSWORD:crypto.randomUUID()};
 const user={id:'premium_preview',provider:'google',app:'ru',createdAt:new Date().toISOString(),lastSeenAt:new Date().toISOString()};
 await env.INSTALLS.put('user:'+user.id,JSON.stringify(user),{metadata:userSummary(user)});
 const server=createServer(async(incoming,outgoing)=>{
  try{
   const url=new URL(incoming.url,`http://${incoming.headers.host}`),headers=new Headers(incoming.headers);
   if(url.pathname.startsWith('/api/admin/'))headers.set('authorization',`Bearer ${env.ADMIN_PASSWORD}`);
   const response=await worker.fetch(new Request(url,{headers}),env,{waitUntil(p){p.catch(()=>{});}});
   if(url.pathname==='/api/admin/stats'&&response.ok){
    const data=await response.json();data.premiumPurchases=withUsd(revenueFixture(Number(url.searchParams.get('days'))||7));
    outgoing.writeHead(200,{'content-type':'application/json'});outgoing.end(JSON.stringify(data));return;
   }
   outgoing.writeHead(response.status,Object.fromEntries(response.headers));outgoing.end(Buffer.from(await response.arrayBuffer()));
  }catch(error){outgoing.writeHead(500);outgoing.end(String(error));}
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 return{url:`http://127.0.0.1:${server.address().port}`,async close(){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}};
}
const compact=value=>value.replace(/\s/g,'');

test('premium revenue combines currencies in USD with four metrics and logos across periods and viewport sizes',{timeout:90000},async()=>{
 const{chromium}=createRequire(import.meta.url)('playwright');
 const app=await preview(),browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try{
  const context=await browser.newContext({viewport:{width:1600,height:1100},reducedMotion:'reduce'});
  await context.route('**/*',async route=>{
   const url=new URL(route.request().url());
   if(url.origin===app.url)return route.continue();
   if(url.hostname==='pdd-drive.ru'&&['/assets/icon-192.png','/assets/favicon.png'].includes(url.pathname))return route.fulfill({contentType:'image/png',body:await readFile(new URL('../../web_landing/ru'+url.pathname,import.meta.url))});
   return route.abort();
  });
  const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto(app.url+'/admin#analytics');
  await page.waitForFunction(()=>window.__anData?.premiumPurchases?.available);
  const card=page.locator('#an-premium'),summary=page.locator('#an-premium-summary'),chart=page.locator('#an-premium-chart');
  const render=(data,fx=FX)=>page.evaluate(premiumPurchases=>{window.__anData={...window.__anData,premiumPurchases};anRenderPremium(window.__anData);},withUsd(data,fx));
  assert.equal(await card.locator('.an-fold').getAttribute('aria-expanded'),'true');
  assert.equal(await summary.locator(':scope>span').count(),4,'revenue, purchases, average check and daily average');
  assert.match(compact(await summary.innerText()),/Выручказапериод9,85\$/);
  assert.match(compact(await summary.innerText()),/Среднийчек3,28\$/,'average check combines all priced currencies');
  assert.match(compact(await summary.innerText()),/Всреднемзадень1,41\$/,'daily average includes zero-purchase days');
  assert.match(await summary.innerText(),/Покупки\s*4/);
  assert.equal(await summary.locator('b').first().evaluate(el=>getComputedStyle(el).color),'rgb(255, 122, 0)','Premium headline is orange');
  assert.equal(await chart.locator('.an-premium-line').count(),1,'daily revenue is a single line');
  assert.equal(await chart.locator('.an-premium-line').getAttribute('stroke'),'#FF7A00');
  assert.equal(await chart.locator('.an-premium-area').count(),1,'line retains a soft area fill');
  assert.equal(await chart.locator('[data-premium-dot]').count(),7,'each recorded day has a point');
  assert.equal(await card.locator('#an-premium-coverage,#an-details-premium-values,.an-help').count(),0,'no footer table, history caption or info badge');
  assert.equal(await card.locator('.an-card').count(),0,'no cards inside the card');
  assert.equal(await card.locator('select,[data-premium-mode],#an-premium-modes').count(),0,'no currency or chart-mode controls');
  assert.equal(await page.locator('#an-premium-sources .an-logo svg').count(),3,'SBP, App Store and Google Play use shared brand logos');
  assert.match(compact(await page.locator('#an-premium-sources .an-premium-source').filter({hasText:'СБП'}).locator('b').innerText()),/4,86\$/);
  const last=(await chart.locator('rect[data-i]').count())-1;
  await chart.locator(`rect[data-i="${last}"]`).hover();
  assert.match(compact(await page.locator('#an-tip').innerText()),/9,85\$/);
  assert.equal(await chart.getAttribute('data-active-point'),String(last),'hover selects a daily point');
  assert.equal(await chart.locator('[data-premium-marker]').getAttribute('visibility'),'visible');
  assert.match(await page.locator('#an-tip').innerText(),/СБП/,'selected day includes its payment methods');
  assert.match(await page.locator('#an-premium-sources').innerText(),/СБП/);
  assert.match(await page.locator('#an-tip').innerText(),/Покупки\s*4/);

  for(const period of [1,7,30,90]){
   await page.locator(`#period-buttons [data-days="${period}"]`).click();
   await page.waitForFunction(days=>window.__anData?.premiumPurchases?.timeline?.length===days,period);
   assert.equal(await chart.locator('[data-premium-point]').count(),period,'all '+period+' days retain individual daily points');
   assert.equal(await chart.locator('[data-premium-dot]').count(),period);
   assert.match(await summary.innerText(),/Покупки\s*4/);
   assert.equal(compact(await summary.locator('b').nth(3).innerText()),compact(new Intl.NumberFormat('ru-RU',{style:'currency',currency:'USD'}).format(Math.round(985/period)/100)));
  }
  await chart.locator('svg').focus();
  await page.keyboard.press('Home');
  assert.equal(await chart.getAttribute('data-active-point'),'0','keyboard selects first day');
  await page.keyboard.press('ArrowRight');
  assert.equal(await chart.getAttribute('data-active-point'),'1');
  await page.keyboard.press('End');
  assert.equal(await chart.getAttribute('data-active-point'),'89');
  await page.keyboard.press('Escape');
  assert.equal(await chart.locator('[data-premium-marker]').getAttribute('visibility'),'hidden');
  const toggle=card.locator('.an-fold');
  await toggle.click();assert.equal(await page.locator('#an-body-premium').isVisible(),false);
  await page.reload();await page.waitForFunction(()=>window.__anData?.premiumPurchases?.available);
  assert.equal(await toggle.getAttribute('aria-expanded'),'false','fold persists after reload');
  await toggle.press('Enter');assert.equal(await page.locator('#an-body-premium').isVisible(),true);
  await page.locator('#period-buttons [data-days="7"]').click();
  await page.waitForFunction(()=>window.__anData?.premiumPurchases?.timeline?.length===7);
  for(const width of [1600,768,390,320]){
   await page.setViewportSize({width,height:1100});await page.waitForTimeout(220);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'page fits '+width);
   assert.equal(await card.evaluate(el=>el.scrollWidth>el.clientWidth),false,'premium card fits '+width);
   assert.equal(await summary.evaluate(el=>el.scrollWidth>el.clientWidth),false,'premium metrics fit '+width);
   assert.equal(await page.locator('#an-premium-sources').evaluate(el=>el.scrollWidth>el.clientWidth),false,'methods fit '+width);
   await chart.locator('rect[data-i="6"]').click();
   const tip=await page.locator('#an-tip').boundingBox();
   assert.ok(tip&&tip.x>=0&&tip.x+tip.width<=width+1,'touch tooltip fits '+width);
   await page.keyboard.press('Escape');
   if(process.env.PREMIUM_UI_SCREENSHOTS){
    await render(screenshotFixture());
    await mkdir(new URL('../../output/premium-revenue/',import.meta.url),{recursive:true});
    await page.mouse.move(0,0);await page.evaluate(()=>document.activeElement?.blur());
    await card.screenshot({path:fileURLToPath(new URL(`../../output/premium-revenue/${width}.png`,import.meta.url))});
    await render(revenueFixture(7));
   }
  }

  const incomplete=revenueFixture(7);incomplete.coverage.unverifiedPurchases=3;
  await render(incomplete);
  assert.doesNotMatch(await card.innerText(),/Неполная история/);
  assert.match(await summary.innerText(),/Покупки\s*4/,'unverified history is not counted as paid purchases');

  const gap=screenshotFixture();
  Object.assign(gap.timeline[3],metrics(1,1),{methods:[{key:'googleplay',...metrics(1,1)}]});
  await render(gap);
  assert.equal(await chart.locator('.an-premium-line').count(),2,'an unknown amount breaks the line instead of becoming a false zero');
  assert.equal(await chart.locator('[data-premium-dot="3"]').count(),0);
  await chart.locator('[data-premium-point="3"]').hover();
  assert.match(await page.locator('#an-tip').innerText(),/Выручка\s*—/);

  const small=revenueFixture(7);
  const smallMethod={key:'appstore',label:'App Store',...metrics(1,0,{USD:4},{USD:1})};
  small.totals=metrics(1,0,{USD:4},{USD:1});
  small.methods=[smallMethod];
  Object.assign(small.timeline[6],small.totals,{methods:[smallMethod]});
  await render(small);
  await chart.locator('[data-premium-point="6"]').hover();
  assert.match(compact(await page.locator('#an-tip').innerText()),/Выручка<0,01\$Покупки1AppStore<0,01\$/);
  assert.match(await chart.locator('svg').getAttribute('aria-label'),/< 0,01 \$/);

  const missing=revenueFixture(7);
  missing.totals=metrics(1,1);missing.currencies=[];
  missing.methods=[{key:'appstore',label:'App Store',...metrics(1,1)}];
  for(const day of missing.timeline)Object.assign(day,metrics(),{methods:[]});
  Object.assign(missing.timeline[6],metrics(1,1),{methods:missing.methods});
  await render(missing);
  assert.match(await summary.innerText(),/Выручка за период\s*—/);
  assert.match(await summary.innerText(),/Покупки\s*1/);
  assert.match(await chart.innerText(),/Суммы покупок не сохранены/);
  assert.match(await summary.innerText(),/В среднем за день\s*—/,'unknown amounts cannot imply zero daily revenue');
  const empty=revenueFixture(7);empty.totals=metrics();empty.methods=[];empty.currencies=[];
  for(const day of empty.timeline)Object.assign(day,metrics(),{methods:[]});
  await render(empty);
  assert.match(compact(await summary.innerText()),/Выручказапериод0,00\$/,'observed no purchases is a real zero');
  assert.match(await chart.innerText(),/нет покупок|Покупок.*нет/i);
  empty.coverage={missingDates:2};
  await render(empty);
  assert.match(await summary.innerText(),/Выручка за период\s*—/,'missing-date purchases cannot imply zero revenue');
  assert.match(await chart.innerText(),/Нет подтверждённых сумм за период/);
  await render(revenueFixture(7),null);
  assert.match(await chart.innerText(),/курс валют/,'FX failure does not silently omit non-USD sales');
  assert.match(await summary.innerText(),/Покупки\s*4/);
  assert.match(await summary.innerText(),/Выручка за период\s*—/);
  await render({available:false});
  assert.match(await chart.innerText(),/недоступ/i,'unavailable is distinct from no purchases');
  assert.doesNotMatch(compact(await summary.innerText()),/0,00\$/);
  assert.deepEqual(errors,[]);
 }finally{await browser.close();await app.close();}
});
