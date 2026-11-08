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

// Deliberately different launch and installation rankings expose a sort wired
// to the wrong metric. New modes have zero observations, not missing rows.
const usageModes = [
 ['tickets','Билеты',44890,2291], ['topics','Темы',14184,1626],
 ['exam','Экзамен',25112,2481], ['marathon','Марафон',1150,480],
 ['feed','Лента',5304,1455], ['mistakes','Работа над ошибками',0,0],
 ['favorites','Избранное',0,0], ['game','Живой город',7653,1836],
 ['sign_swiper','Это знак',7744,2043], ['traffic_controller','Регулировщик',4957,1448],
 ['crossroads','Перекрёсток',3799,977], ['road_signs','Знаки',1329,515],
 ['parking','Парковка',2433,845], ['violator','Нарушитель',0,0],
];
function usageFixture() {
 const collectionFrom = Object.fromEntries(usageModes.map(([key])=>[key,
  ['mistakes','favorites','violator'].includes(key)?'2026-11-04':
   ['marathon','road_signs'].includes(key)?'2026-10-27':'2026-10-08']));
 return {from:'2026-10-08',collectionFrom,
  features:Object.fromEntries(usageModes.map(([key,,starts,installations])=>[key,{starts,installations}])),
  timeline:['2026-11-03','2026-11-04'].map((date,index)=>({date,features:Object.fromEntries(usageModes.map(([key,,starts,installations])=>[key,
   date<collectionFrom[key]?{starts:null,installations:null}:
    {starts:index?Math.ceil(starts/2):Math.floor(starts/2),installations}]))})),
 };
}

async function verifyUsage(page) {
 await page.evaluate(()=>{window.__usageOriginalData=window.__anData;});
 const render = usage=>page.evaluate(usage=>{
  window.__anData={...window.__usageOriginalData,usage};anRenderUsage(window.__anData);
 },usage);
 const keys=()=>page.locator('#an-usage-table [data-usage]').evaluateAll(elements=>elements.map(el=>el.dataset.usage));
 const row=key=>page.locator('#an-usage-table tr').filter({has:page.locator(`[data-usage="${key}"]`)});
 const number=key=>row(key).locator('td').nth(1).innerText();
 const fixture=usageFixture(), total=usageModes.reduce((sum,item)=>sum+item[2],0);
 await render(fixture);
 assert.equal(await page.locator('#an-usage-sort').inputValue(),'starts');
 assert.equal(await page.locator('#an-usage-table thead th').count(),3,'only mode, launches, installations');
 assert.deepEqual(new Set(await keys()),new Set(usageModes.map(([key])=>key)),'all fourteen current modes, including zeros');
 assert.deepEqual((await keys()).slice(0,3),['tickets','exam','topics']);
 assert.equal(await number('violator'),'0');
 assert.match(await page.locator('#an-usage-total').innerText(),new RegExp(total.toLocaleString('ru-RU').replace(/\s/g,'\\s')));
 const share=await row('tickets').locator('.an-usage-share').innerText();
 const totalLabel=await page.locator('#an-usage-total').innerText();
 assert.match(share,/38\s*%/);

 await page.locator('#an-usage-sort').selectOption('installations');
 assert.deepEqual((await keys()).slice(0,3),['exam','tickets','sign_swiper']);
 await page.locator('#an-usage-sort').selectOption('name');
 assert.deepEqual(await keys(),usageModes.slice().sort((a,b)=>a[1].localeCompare(b[1],'ru')).map(([key])=>key));
 await page.locator('[data-usage-group="training"]').click();
 assert.equal(await page.locator('[data-usage-group="training"]').getAttribute('aria-pressed'),'true');
 assert.deepEqual(new Set(await keys()),new Set(['tickets','topics','exam','marathon','feed','mistakes','favorites']));
 assert.equal(await row('tickets').locator('.an-usage-share').innerText(),share,'filter preserves share of all launches');
 assert.equal(await page.locator('#an-usage-total').innerText(),totalLabel,'filter preserves total of all launches');
 await page.locator('[data-usage-group="games"]').click();
 assert.deepEqual(new Set(await keys()),new Set(['game','sign_swiper','traffic_controller','crossroads','road_signs','parking','violator']));
 await page.locator('[data-usage="violator"]').focus();
 await page.keyboard.press('Enter');
 assert.equal(await page.locator('#an-usage-feature').inputValue(),'violator');
 assert.equal(await page.locator('#an-usage-details').evaluate(el=>el.open),true);
 assert.equal(await page.locator('[data-usage="violator"]').getAttribute('aria-expanded'),'true');
 assert.equal(await page.evaluate(()=>document.activeElement.id),'an-usage-feature','keyboard focus moves into the opened chart controls');
 assert.match(await page.locator('#an-usage-chart').innerText(),/нет запусков/);
 assert.match(await page.locator('#an-usage-caption').innerText(),/4\.11/);
 await page.locator('#an-usage-feature').selectOption('exam');
 assert.ok(await page.locator('#an-usage-chart svg').count()>0);
 assert.equal(await page.locator('[data-usage="violator"]').getAttribute('aria-expanded'),'false');
 await page.locator('#an-usage-details>summary').click();
 await page.locator('[data-usage-group="all"]').click();
 await page.locator('#an-usage-sort').selectOption('starts');

 // A populated historical mode must remain part of both the total and shares.
 const legacy=structuredClone(fixture);
 legacy.features.roundabout={starts:10000,installations:500};
 for(const day of legacy.timeline)day.features.roundabout={starts:5000,installations:500};
 await render(legacy);
 assert.equal((await keys()).length,15);
 assert.match(await row('roundabout').innerText(),/архив/i);
 assert.match(await page.locator('#an-usage-total').innerText(),new RegExp((total+10000).toLocaleString('ru-RU').replace(/\s/g,'\\s')));
 assert.match(await row('tickets').locator('.an-usage-share').innerText(),/35\s*%/);
 await page.locator('[data-usage="roundabout"]').click();
 assert.equal(await page.locator('#an-usage-feature').inputValue(),'roundabout');
 assert.ok(await page.locator('#an-usage-chart svg').count()>0);
 await page.locator('#an-usage-details>summary').click();

 const oldApi=structuredClone(fixture);
 delete oldApi.features.violator;
 for(const day of oldApi.timeline)delete day.features.violator;
 await render(oldApi);
 assert.equal(await number('violator'),'—','older API cannot imply a recorded zero');
 await page.locator('[data-usage="violator"]').click();
 assert.match(await page.locator('#an-usage-chart').innerText(),/нет данных|недоступ/i);
 await page.locator('#an-usage-details>summary').click();
 const historical=structuredClone(fixture);
 historical.timeline=historical.timeline.slice(0,1);
 for(const key of ['violator','mistakes','favorites'])historical.features[key]={starts:null,installations:null};
 await render(historical);
 for(const key of ['violator','mistakes','favorites'])assert.equal(await number(key),'—');
 await page.locator('[data-usage="violator"]').click();
 assert.match(await page.locator('#an-usage-chart').innerText(),/нет данных|сбор|начал/i);
 await page.locator('#an-details-usage-values>summary').click();
 assert.match(await page.locator('#an-usage-days').innerText(),/—/);
 await page.locator('#an-details-usage-values>summary').click();
 await page.locator('#an-usage-details>summary').click();

 const empty=structuredClone(fixture);
 for(const key of Object.keys(empty.features))empty.features[key]={starts:0,installations:0};
 for(const day of empty.timeline)for(const key of Object.keys(day.features))if(day.features[key].starts!==null)day.features[key]={starts:0,installations:0};
 await render(empty);
 assert.equal((await keys()).length,14,'zero observations never hide the mode catalogue');
 assert.equal(await number('violator'),'0');
 assert.equal(await number('tickets'),'0');
 await render(fixture);
 if(process.env.ANALYTICS_UI_SCREENSHOTS){
  await mkdir(new URL('../../output/analytics-layout/',import.meta.url),{recursive:true});
  for(const width of [1200,390,320]){
   await page.setViewportSize({width,height:1100});
   await page.waitForTimeout(220);
   assert.equal(await page.locator('#an-usage').evaluate(el=>el.scrollWidth>el.clientWidth),false,'usage card fits '+width);
   assert.equal(await page.locator('#an-usage-table').evaluate(el=>el.scrollWidth>el.clientWidth),false,'usage table fits '+width);
   await page.mouse.move(0,0);
   await page.evaluate(()=>document.activeElement?.blur());
   await page.locator('#an-usage').screenshot({path:fileURLToPath(new URL(`../../output/analytics-layout/usage-${width}.png`,import.meta.url))});
  }
 }
 await page.setViewportSize({width:1600,height:1100});
 await page.evaluate(()=>{window.__anData=window.__usageOriginalData;delete window.__usageOriginalData;anRenderUsage(window.__anData);});
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
  // Previous-version cached data never substitutes full-day averages for
  // missing intraday measurements. Render a measured zero and restore.
  const activityCard=page.locator('.an-activity-card');
  const activityChart=activityCard.locator('#an-activity-chart');
  const activitySummary=activityCard.locator('#an-activity-summary');
  assert.equal(await activityCard.locator('.an-caption,.an-day-details').count(),0);
  const days=[
   {date:'2026-11-06',total:25,android:10,ios:20},
   {date:'2026-11-07',total:0,android:0,ios:0},
   {date:'2026-11-08',total:20,android:0,ios:20},
  ];
  await page.evaluate(days=>anRenderActivity({users:{activity:{days}}}),days);
  assert.match(await activitySummary.innerText(),/Среднее\s*—/);
  assert.deepEqual(await activityChart.locator('svg > text').allTextContents(),['0','30','6.11','7.11','8.11']);
  assert.equal(await activityChart.locator('rect[data-i]').count(),days.length);
  const segments=await activityChart.locator('svg > path').evaluateAll(paths=>paths.map(path=>{
   const {x,y,width,height}=path.getBBox();
   return {color:path.getAttribute('fill'),x,y,width,height};
  }));
  const [android,ios,iosOnly]=segments;
  assert.deepEqual(segments.map(segment=>segment.color),['#0574F8','#000000','#000000']);
  assert.equal(android.x,ios.x);
  assert.equal(android.width,ios.width);
  assert.ok(Math.abs(android.y-ios.y-ios.height)<0.001,'the segments touch');
  assert.ok(Math.abs(2*android.height-ios.height)<0.001,'segment heights follow platform counts');
  assert.ok(Math.abs(iosOnly.y+iosOnly.height-android.y-android.height)<0.001,'iOS starts at zero without Android activity');
  await activityChart.locator('rect[data-i="0"]').hover();
  assert.match(await page.locator('#an-tip').innerText(),/Google Play \/ Android\s*10[\s\S]*iOS\s*20/);
  await page.evaluate(days=>{
    anRenderActivity({users:{activity:{days,comparison:{minute:852,today:0,average:12,days:3}}}});
  },days);
  assert.match(await activitySummary.innerText(),/Среднее к 14:12\s*12/);
  await page.evaluate(()=>anRenderActivity(window.__anData));

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
  assert.deepEqual(new Set(await page.locator('#an-usage-feature option').allTextContents()),new Set(usageModes.map(([,name])=>name)));
  await verifyUsage(page);
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
   assert.equal(await page.locator('#an-usage').evaluate(el=>el.scrollWidth>el.clientWidth),false,'usage card fits '+width);
   assert.equal(await page.locator('#an-usage-table').evaluate(el=>el.scrollWidth>el.clientWidth),false,'usage table fits '+width);
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
  const activityToggle=page.locator('[aria-controls="an-body-activity"]');
  await activityToggle.click();
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
  assert.equal(await activityToggle.getAttribute('aria-expanded'),'false');
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
  // A new authenticated session keeps the layout after the auth cache was cleared.
  await page.unroute('**/api/admin/session');
  await page.reload();
  await page.waitForFunction(()=>document.querySelector('#an-now .an-big')?.textContent==='160');
  assert.equal(await activityToggle.getAttribute('aria-expanded'),'false');
  await activityToggle.click();
  assert.equal(await activityChart.isVisible(),true);
  await page.reload();
  assert.equal(await activityToggle.getAttribute('aria-expanded'),'true');
  assert.deepEqual(errors,[]);
 } finally {await browser.close();await app.close();}
});
