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
 const original=await page.evaluate(()=>window.__anData);
 await page.evaluate(usage=>{window.__anData={...window.__anData,usage};anRenderUsage(window.__anData);},usageFixture());
 const columns=page.locator('.an-mode-column');
 assert.equal(await columns.count(),14);
 assert.equal(await columns.first().getAttribute('data-usage'),'tickets');
 assert.equal(await page.locator('#an-usage select').count(),0);
 assert.doesNotMatch(await columns.first().getAttribute('title'),/Установки/);
 await page.locator('[data-usage-group="games"]').click();
 assert.equal(await columns.count(),7);
 assert.equal(await page.locator('#an-usage-details').count(),0);
 await page.locator('[data-usage-group="all"]').click();
 await page.evaluate(data=>{window.__anData=data;anRenderUsage(data);},original);
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
  // Daily averages also work with cached data without intraday measurements.
  // A zero-activity day counts; the current partial day does not.
  const activityCard=page.locator('.an-activity-card');
  const activityChart=activityCard.locator('#an-activity-chart');
  const activitySummary=activityCard.locator('#an-activity-summary');
  await page.waitForFunction(()=>{
   const chart=document.getElementById('an-activity-chart');
   return Number(chart.querySelector('svg')?.getAttribute('width'))===chart.clientWidth;
  },null,{timeout:3000});
  assert.equal(await activityCard.locator('.an-caption,.an-day-details').count(),0);
  const days=[
   {date:'2026-11-06',total:30,android:8,ios:20,web:2},
   {date:'2026-11-07',total:0,android:0,ios:0},
   {date:'2026-11-08',total:20,android:0,ios:20},
  ];
  await page.evaluate(days=>anRenderActivity({usage:{activity:{days}}}),days);
  assert.match(await activitySummary.innerText(),/Среднее\s*15/);
  assert.deepEqual(await activityChart.locator('svg > text').allTextContents(),['6.11','7.11','8.11']);
  assert.equal(await activityChart.locator('rect[data-i]').count(),days.length);
  assert.deepEqual(await activityCard.locator('#an-activity-legend span').allTextContents(),['Общая','Android','iOS']);
  assert.equal(await activityChart.locator('.an-premium-line').count(),3);
  const positions=await activityChart.locator('circle[data-premium-dot="0"]').evaluateAll(dots=>dots.map(dot=>Number(dot.getAttribute('cy'))));
  assert.equal(positions.length,3);
  assert.ok(positions[0]<positions[2] && positions[2]<positions[1]);
  const markers=await activitySummary.locator('.an-dot').evaluateAll(dots=>dots.map(dot=>getComputedStyle(dot).backgroundColor));
  assert.deepEqual(markers,[]);
  assert.equal(await activitySummary.locator(':scope > span').count(),3);
  assert.doesNotMatch(await activitySummary.innerText(),/Google|iOS/);
  assert.doesNotMatch(await activityCard.innerText(),/Аккаунты · без гостей/);
  await activityChart.locator('rect[data-i="0"]').hover();
  const tip=await page.locator('#an-tip').innerText();
  assert.match(tip,/Общая\s*30[\s\S]*Android\s*8[\s\S]*iOS\s*20/);
  assert.doesNotMatch(tip,/Веб|Web|неизвестна/i);
  await activityChart.locator('svg').press('Home');
  assert.match(await activityChart.locator('svg').getAttribute('aria-label'),/Общая.*30.*Android: 8.*iOS: 20/);
  await activityChart.locator('svg').press('Escape');
  await page.evaluate(()=>anRenderActivity({usage:{activity:{days:[
   {date:'2026-11-05',total:7,unknown:7,android:0,ios:0}, {date:'2026-11-06',total:null},
  ]}}}));
  assert.equal(await activityChart.locator('circle[data-premium-dot]').count(),1,'only the known total gets a point');

  await page.evaluate(days=>{
    anRenderActivity({usage:{activity:{days,comparison:{minute:852,today:0,average:12,days:3}}}});
  },days);
  assert.match(await activitySummary.innerText(),/Среднее\s*15/);
  assert.doesNotMatch(await activitySummary.innerText(),/Среднее к/);
  await page.evaluate(days=>anRenderActivity({usage:{activity:{days:days.slice(-1)}}}),days);
  assert.match(await activitySummary.innerText(),/Среднее\s*—/);
  await page.evaluate(days=>anRenderActivity({usage:{activity:{days:[{date:'2026-11-05',total:null},...days]}}}),days);
  assert.match(await activitySummary.innerText(),/Среднее\s*15/);
  const periodDays=Array.from({length:90},(_,i)=>({
   date:new Date(Date.UTC(2026,7,17+i)).toISOString().slice(0,10),
   total:i<60?1000:i<83?300:i<89?400:166,
   android:0,ios:0,
  }));
  for(const [period,expected] of [[7,'400'],[30,'321'],[90,'779'],[1,'—']]){
   await page.evaluate(days=>anRenderActivity({usage:{activity:{days}}}),periodDays.slice(-period));
   assert.match(await activitySummary.innerText(),new RegExp('Среднее\\s*'+expected),'daily average follows the '+period+'-day period');
   assert.match(await activitySummary.innerText(),/Сегодня\s*166/);
  }
  await page.evaluate(()=>anRenderActivity({usage:{activity:{days:[]}}}));
  assert.deepEqual(await activitySummary.locator('b').allTextContents(),['—','—','—']);
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
  assert.equal(await cards.count(),14);
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
  await verifyUsage(page);
  const desktop=await page.locator('#an-auth').boundingBox(),versions=await page.locator('#an-updates').boundingBox();
  assert.equal(desktop.y,versions.y,'audience cards share a row');
  const geo=await page.locator('.an-geo-card').boundingBox();
  assert.ok(geo.width>desktop.width*1.9,'geography uses full content width');
  const auth=await page.locator('#an-auth-table').innerText();
  assert.equal(await page.locator('[data-chart]').count(),0);
  assert.match(await page.locator('#an-site-summary').innerText(),/Просмотры/);
  const activityBox=await activityCard.boundingBox();
  const launchesBox=await page.locator('#an-launches').boundingBox();
  const accountsBox=await page.locator('#an-registrations').boundingBox();
  assert.ok(Math.abs(activityBox.width-launchesBox.width)<1 && Math.abs(accountsBox.width-launchesBox.width)<1);
  assert.equal(activityBox.y,launchesBox.y);
  assert.equal(launchesBox.y,accountsBox.y);
  assert.ok(launchesBox.x<accountsBox.x);
  assert.ok(launchesBox.height<=activityBox.height+2,'growth cards stay compact');
  for (const [id, kind] of [['an-launches-summary','launches'],['an-registrations-summary','registrations']]) {
   const expected=await page.evaluate(kind=>{
    const {timeline,users}=window.__anData;
    const counts=timeline.map(day=>kind==='launches'?day.installs:users.registrationsByDay[day.date]);
    const complete=counts.slice(0,-1);
    return [counts.at(-1),Math.round(complete.reduce((sum,n)=>sum+n,0)/complete.length),counts.reduce((sum,n)=>sum+n,0)].map(anNum);
   },kind);
   assert.deepEqual(await page.locator('#'+id+' b').allTextContents(),expected);
  }
  assert.deepEqual(await page.locator('#an-site-chart .an-premium-line').evaluateAll(lines=>lines.map(line=>line.getAttribute('stroke'))),['#0574F8','#22a875']);
  const siteBox=await page.locator('#an-site-activity').boundingBox();
  assert.ok(siteBox.y>geo.y+geo.height,'site activity is a separate lower card');
  const expectedGrowth=await page.evaluate(()=>({
   launches:anNum(anSum(window.__anData.timeline,d=>d.installs)),
   registrations:anNum(window.__anData.users.registrations)
  }));
  assert.equal(await page.locator('#an-launches-summary b').last().innerText(),expectedGrowth.launches);
  assert.equal(await page.locator('#an-registrations-summary b').last().innerText(),expectedGrowth.registrations);
  for(const id of ['an-installs-chart','an-registrations-chart']){
   await page.locator('#'+id+' rect[data-i="0"]').hover();
   assert.match(await page.locator('#an-tip').innerText(),id==='an-installs-chart'?/Первые запуски/:/Новые аккаунты/);
  }
  await page.locator('[data-geo="cities"]').click();
  await page.locator('#an-geo-search').fill('Москва');
  assert.match(await page.locator('#an-geo').innerText(),/Москва/);
  await page.locator('#an-geo-reset').click();
  await page.setViewportSize({width:2415,height:900});
  await page.evaluate(()=>window.scrollTo(0,600));
  const sidebar=page.locator('.sidebar');
  for(const collapsed of [false,true]){
   const bounds=await sidebar.boundingBox();
   assert.equal(bounds.x,0,'sidebar meets the left edge');
   assert.equal(bounds.y,0,'sidebar stays at the top while the dashboard scrolls');
   assert.equal(bounds.height,900);
   assert.equal(await sidebar.evaluate(el=>el.classList.contains('collapsed')),collapsed);
   const main=await page.locator('main').boundingBox();
   assert.equal(main.x,bounds.width);
   assert.equal(main.x+main.width,await page.evaluate(()=>document.documentElement.clientWidth));
   if(!collapsed)await page.locator('#sidebar-toggle-btn').click();
  }
  for(const width of [2415,1600,1100,901,900,768,600,390,320]) {
   await page.setViewportSize({width,height:1100});
   await page.waitForTimeout(220); // dashboard debounces chart sizing for 150 ms
   if(width===1600||width===390) {
    const roles=await page.evaluate(()=>{
     const signature=selector=>{
      const style=getComputedStyle(document.querySelector(selector));
      return [style.fontFamily,style.fontSize,style.fontWeight,style.lineHeight].join('|');
     };
     return {
      section:['#analytics-view .an-title','#ec-recent-heading','.ai-card-title'].map(signature),
      action:['#ec-add-operation','.pb-tabs button','#nt-test'].map(signature),
      value:['.an-big','#tasks-kpi-total','#ai-m-total'].map(signature),
      dialog:['#ec-dialog h2','.pc-dialog-title','.task-modal-title'].map(signature),
     };
    });
    for(const [role,signatures] of Object.entries(roles)) {
     assert.equal(new Set(signatures).size,1,role+' typography at '+width+': '+signatures.join(', '));
    }
   }
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
   assert.equal(overflow,false,'page must fit '+width);
   if(width<=900){
    const menu=await sidebar.boundingBox(),main=await page.locator('main').boundingBox();
    assert.equal(main.width,menu.width,'horizontal menu leaves the full viewport for content');
    assert.equal(main.y,menu.y+menu.height);
    assert.ok(await page.locator('.sidebar-menu .nav-item.active span').isVisible());
   }
   assert.equal(await page.locator('#an-usage').evaluate(el=>el.scrollWidth>el.clientWidth),false,'usage card fits '+width);
   assert.equal(await page.locator('.an-mode-columns').evaluate(el=>el.getBoundingClientRect().right<=innerWidth),true,'chart fits '+width);
   for (const value of await page.locator('#an-now .an-big').evaluateAll(elements=>elements.map(el=>{
    const style=getComputedStyle(el);
    return {background:style.backgroundColor,aspectRatio:style.aspectRatio};
   }))) {
    assert.equal(value.background,'rgba(0, 0, 0, 0)','KPI values have no image placeholder background at '+width);
    assert.equal(value.aspectRatio,'auto','KPI height follows its text at '+width);
   }
   assert.equal(await page.locator('#analytics-view .an-help').count(),0,'analytics has no info badges');
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
  assert.equal(await page.locator('#analytics-view > .admin-load-notice').isVisible(),false);
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
