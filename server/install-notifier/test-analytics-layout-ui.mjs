// Full assembled admin page with local, isolated analytics data.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import worker, { flushBufferedStats } from './worker.js';
import { userSummary } from './user_store.js';
import { recordActivity } from './analytics_activity.js';

class MemoryKV {
  constructor() { this.store = new Map(); this.metadata = new Map(); }
  async get(key, options) {
    const value = this.store.get(key) ?? null;
    return options === 'json' || options?.type === 'json' ? value === null ? null : JSON.parse(value) : value;
  }
  async put(key, value, options) {
    this.store.set(key, String(value));
    if (options?.metadata) this.metadata.set(key, options.metadata);
    else this.metadata.delete(key);
  }
  async delete(key) { this.store.delete(key); this.metadata.delete(key); }
  async list({ prefix = '', limit = 1000, cursor = '0' } = {}) {
    const all = [...this.store.keys()].filter(key => key.startsWith(prefix)).sort();
    const start = Number(cursor) || 0;
    const keys = all.slice(start, start + limit).map(name => ({ name, metadata: this.metadata.get(name) }));
    return { keys, list_complete: start + keys.length >= all.length, cursor: String(start + keys.length) };
  }
}

async function preview() {
 const env={INSTALLS:new MemoryKV(),ADMIN_PASSWORD:crypto.randomUUID()};
 const today=Date.now();
 const date=new Date(today+3*3600000).toISOString().slice(0,10);
 await env.INSTALLS.put('store-reports:v1:googleplay',JSON.stringify({checkedAt:new Date(today).toISOString(),days:{[date]:{'Google Play explore':7},'2001-01-01':{'Google Play explore':100}}}));
 await env.INSTALLS.put('store-reports:v1:appstore',JSON.stringify({checkedAt:new Date(today).toISOString(),days:{}}));
 for(let i=0;i<160;i++) {
  const user={id:'preview_'+i,provider:['yandex','google','apple','telegram'][i%4],app:'ru',
   platform:i%3?'ios':'android',appVersion:i%3?'2.2.3+59':'2.2.4+65',
   createdAt:new Date(today-(i%12)*86400000).toISOString(),lastSeenAt:new Date(today).toISOString(),
   ipCountry:i%6?'RU':'BY',ipRegion:i%2?'Moscow':'Moscow Oblast',ipCity:i%2?'Moscow':'Khimki',
   versionObservations:i<12?{android:{version:'2.2.4+65',updatedAt:new Date(today).toISOString()}}:{}};
  for(let offset=6;offset>=0;offset--)if(i<(offset?120-offset*10:90)) {
   user.lastSeenAt=new Date(today-offset*86400000).toISOString();recordActivity(user,today-offset*86400000);
  }
  user.lastSeenAt=new Date(today).toISOString();
  await env.INSTALLS.put('user:'+user.id,JSON.stringify(user),{metadata:userSummary(user)});
 }
 const events=[];
 for(let d=6;d>=0;d--)for(let i=0;i<60+d*6;i++) {
  const ts=today-d*86400000;
  events.push({kind:'analytics',ts,event:{type:'install',app:'ru',platform:i%3?'ios':'android',source:i%3?'appstore':'googleplay'}});
  events.push({kind:'analytics',ts,event:{type:'view',app:'ru',source:i%2?'google':'yandex'}});
  if(i%3===0)events.push({kind:'analytics',ts,event:{type:'click',app:'ru',source:'google',target:'appstore'}});
  events.push({kind:'usage',ts,app:'ru',platform:'android',feature:['tickets','topics','exam','feed','game'][i%5],installation:i.toString(16).padStart(32,'0')});
 }
 await flushBufferedStats(env,events);
 const server=createServer(async(incoming,outgoing)=>{
  try {
   const url=new URL(incoming.url,`http://${incoming.headers.host}`),headers=new Headers(incoming.headers);
   if(url.pathname.startsWith('/api/admin/'))headers.set('authorization',`Bearer ${env.ADMIN_PASSWORD}`);
   const response=await worker.fetch(new Request(url,{headers}),env,{waitUntil(p){p.catch(()=>{});}});
   outgoing.writeHead(response.status,Object.fromEntries(response.headers));
   outgoing.end(Buffer.from(await response.arrayBuffer()));
  } catch(e){outgoing.writeHead(500);outgoing.end(String(e));}
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 return {url:`http://127.0.0.1:${server.address().port}`,async close(){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}};
}

if(process.argv.includes('--serve')) {
 const app=await preview();console.log(app.url+'/admin#analytics');
 for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{await app.close();process.exit(0);});
} else test('analytics page preserves hierarchy, scopes and controls on desktop and mobile', {timeout:90000}, async()=>{
 const {chromium}=createRequire(import.meta.url)('playwright');
 const app=await preview();
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try {
  const context=await browser.newContext({viewport:{width:1600,height:1100},reducedMotion:'reduce'});
  await context.route('**/*',async route=>{
   const url=new URL(route.request().url());
   if(url.origin===app.url)return route.continue();
   if(url.hostname==='pdd-drive.ru'&&['/assets/icon-192.png','/assets/favicon.png'].includes(url.pathname))
    return route.fulfill({contentType:'image/png',body:await readFile(new URL('../../web_landing/ru'+url.pathname,import.meta.url))});
   return route.abort();
  });
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(app.url+'/admin#analytics');
  await page.waitForFunction(()=>document.querySelector('#an-now .an-big')?.textContent==='160');
  assert.equal(await page.locator('#an-auth-table tbody tr').count(),4);
  assert.equal(await page.locator('#an-versions tbody tr').count(),2);
  assert.match(await page.locator('#an-updates-summary').innerText(),/12/);
  for(const label of ['Обзор','Сейчас','Активность и рост','Состав аудитории','Источники привлечения','За выбранный период','Отчёты магазинов · ПДД Россия']){
   assert.equal(await page.locator('#analytics-view').getByText(label,{exact:true}).count(),0);
  }
  assert.equal(await page.locator('#an-now .an-big:visible').count(),4);
  assert.equal(await page.locator('#an-now button').count(),0);
  const cards=page.locator('#analytics-view .an-card:not(.an-kpi)');
  assert.equal(await cards.count(),11);
  for(const card of await cards.all()){
   const toggle=card.locator('.an-fold'), body=page.locator('#'+await toggle.getAttribute('aria-controls'));
   await toggle.click();
   assert.equal(await body.isVisible(),false);
   assert.equal(await toggle.getAttribute('aria-expanded'),'false');
   await toggle.press('Enter');
   assert.equal(await body.isVisible(),true);
  }
  assert.match(await page.locator('#an-report-googleplay').innerText(), /Обзор Google Play\s+7/);
  assert.match(await page.locator('#an-report-appstore').innerText(), /пока не предоставил/);
  assert.deepEqual(await page.locator('#an-usage-feature option').allTextContents(),
   ['Билеты','Темы','Экзамен','Марафон','Лента','Живой город','Это знак','Регулировщик','Перекрёсток','Знаки','Парковка']);
  assert.match(await page.locator('#an-usage-coverage').innerText(),/требуется обновление приложения/);
  for (const feature of ['marathon','road_signs','parking']) {
   await page.locator(`[data-usage="${feature}"]`).click();
   assert.equal(await page.locator('#an-usage-feature').inputValue(),feature);
   assert.match(await page.locator('#an-usage-chart').innerText(),/пока нет запусков/);
   assert.match(await page.locator('#an-usage-caption').innerText(),feature==='parking'?/8\.10/:/27\.10/);
  }
  await page.locator('#an-usage-details>summary').click();
  const desktop=await page.locator('#an-auth').boundingBox(),versions=await page.locator('#an-updates').boundingBox();
  assert.equal(desktop.y,versions.y,'audience cards share a row');
  const geo=await page.locator('.an-geo-card').boundingBox();
  assert.ok(geo.width>desktop.width*1.9,'geography uses full content width');
  const auth=await page.locator('#an-auth-table').innerText();
  await page.locator('[data-chart="site"]').click();
  assert.match(await page.locator('#an-dynamics-summary').innerText(),/Просмотры/);
  await page.locator('[data-chart="app"]').click();
  await page.locator('[data-usage="exam"]').click();
  assert.equal(await page.locator('#an-usage-details').evaluate(el=>el.open),true);
  await page.locator('#an-usage-details>summary').click();
  await page.locator('[data-geo="cities"]').click();
  await page.locator('#an-geo-search').fill('Москва');
  assert.match(await page.locator('#an-geo').innerText(),/Москва/);
  await page.locator('#an-geo-reset').click();
  for(const width of [1600,1100,768,390,320]) {
   await page.setViewportSize({width,height:1100});
   await page.waitForTimeout(220); // dashboard debounces chart sizing for 150 ms
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
   assert.equal(overflow,false,'page must fit '+width);
   for (const value of await page.locator('#an-now .an-big').evaluateAll(elements=>elements.map(el=>{
    const style=getComputedStyle(el);
    return {background:style.backgroundColor,aspectRatio:style.aspectRatio};
   }))) {
    assert.equal(value.background,'rgba(0, 0, 0, 0)','KPI values have no image placeholder background at '+width);
    assert.equal(value.aspectRatio,'auto','KPI height follows its text at '+width);
   }
   await page.locator('#an-auth .an-help>summary').click();
   const help=await page.locator('#an-auth .an-help>div').boundingBox();
   assert.ok(help.x>=0&&help.x+help.width<=width,'help stays on screen');
   await page.keyboard.press('Escape');
   assert.equal(await page.locator('#an-auth .an-help').evaluate(el=>el.open),false);
   if(process.env.ANALYTICS_UI_SCREENSHOTS){
    await page.evaluate(()=>{document.activeElement?.blur();window.scrollTo(0,0);});
    await mkdir(new URL('../../output/analytics-layout/',import.meta.url),{recursive:true});
    await page.screenshot({path:fileURLToPath(new URL(`../../output/analytics-layout/${width}.png`,import.meta.url)),fullPage:true});
   }
  }
  await page.evaluate(()=>anRenderVersions({users:{versions:{updated:0,rows:Array.from({length:18},(_,i)=>({platform:i%2?'ios':'android',version:i===0?'Неизвестна':'2.2.4+'+i,accounts:1}))}}}));
  assert.equal(await page.locator('#an-versions tbody tr').count(),18);
  assert.equal(await page.locator('#an-versions').evaluate(el=>el.scrollHeight>el.clientHeight),true);
  await page.locator('#an-versions').focus();
  await page.keyboard.press('End');
  await page.waitForFunction(()=>document.getElementById('an-versions').scrollTop>0);
  // All-time audience is stable after choosing another graph period.
  const response=await context.request.get(app.url+'/api/admin/stats?days=1&app=ru');
  const oneDay=await response.json();
  await page.evaluate(data=>renderDashboard(data),oneDay);
  assert.equal(await page.locator('#an-auth-table').innerText(),auth);
  // Reopening renders persisted aggregates before a slow background refresh.
  let releaseRefresh;
  let pendingRefresh;
  let refreshRequests=0;
  await page.route('**/api/admin/stats?**',async route=>{
   pendingRefresh=route;
   refreshRequests++;
   await new Promise(resolve=>{releaseRefresh=resolve;});
   const fresh=structuredClone(oneDay);
   fresh.users.registered=161;
   await route.fulfill({json:fresh});
  });
  await page.reload();
  await page.waitForFunction(()=>document.querySelector('#an-now .an-big')?.textContent==='160');
  assert.match(await page.locator('#admin-data-state').innerText(),/Данные на.*обновление/);
  assert.equal(await page.locator('#refresh-btn').isDisabled(),true);
  await page.emulateMedia({reducedMotion:'no-preference'});
  assert.equal(await page.locator('#refresh-btn svg').evaluate(el=>getComputedStyle(el).animationName),'adminRefreshSpin');
  await page.evaluate(()=>{checkAuthAndLoad();checkAuthAndLoad();});
  assert.ok(pendingRefresh);
  assert.equal(refreshRequests,1);
  for(const width of [1600,1100,768,390,320]) {
   await page.setViewportSize({width,height:1100});
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'cached status fits '+width);
  }
  releaseRefresh();
  await page.waitForFunction(()=>document.querySelector('#an-now .an-big')?.textContent==='161');
  await page.waitForFunction(()=>document.getElementById('refresh-btn').getAttribute('aria-busy')==='false');
  await page.unroute('**/api/admin/stats?**');
  await page.route('**/api/admin/stats?**',route=>route.fulfill({status:503,json:{error:'temporarily unavailable'}}));
  await page.locator('#refresh-btn').click();
  await page.waitForFunction(()=>document.querySelector('#admin-error-banner.visible'));
  assert.equal(await page.locator('#an-now .an-big').first().innerText(),'161');
  assert.equal(await page.locator('#refresh-btn').isDisabled(),false);
  await page.locator('#period-buttons [data-days="1"]').click();
  await page.waitForFunction(()=>document.querySelector('#an-now .an-big')?.textContent==='—');
  await page.unroute('**/api/admin/stats?**');
  await page.route('**/api/admin/session',route=>route.fulfill({status:401,json:{error:'unauthorized'}}));
  await page.reload();
  await page.waitForFunction(()=>document.getElementById('login-overlay').style.display==='flex');
  assert.equal(await page.evaluate(()=>Object.keys(localStorage).some(k=>k.startsWith('pdd-admin-analytics-v1:'))),false);
  assert.equal(await page.locator('#app').isVisible(),false);
  await page.evaluate(()=>renderDashboard({timeline:[],totals:{},sources:[]}));
  assert.match(await page.locator('#an-auth-table').innerText(),/недоступны/);
  assert.match(await page.locator('#an-versions').innerText(),/Нет данных/);
  assert.deepEqual(errors,[]);
 } finally {await browser.close();await app.close();}
});
