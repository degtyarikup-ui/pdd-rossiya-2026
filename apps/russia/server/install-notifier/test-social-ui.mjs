// Real assembled admin and Worker routes, isolated from production accounts.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
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


async function startPreview() {
  const env = { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: crypto.randomUUID() };
  await env.INSTALLS.put('social:settings', JSON.stringify({googleClientId:'fixture',googleClientSecret:'fixture',googleRefreshToken:'fixture'}));
  await env.INSTALLS.put('social:accounts', JSON.stringify([{id:'a',name:'ПДД Россия',active:true,postTime:'19:00',targets:['youtube'],driveFolderId:'fixture',instagramAccountId:'fixture',instagramToken:'fixture'}]));
  await env.INSTALLS.put('social:posts', JSON.stringify([
    {id:'q',accountId:'a',title:'Pilot 01 v3',fileName:'001_pilot.mp4',status:'queued',targets:['youtube'],instagramStatus:'queued',youtubeStatus:'queued',streamToken:'fixture'},
    {id:'done',accountId:'a',title:'Успей узнать знак',fileName:'002_znak.mp4',status:'published',targets:['instagram','youtube'],instagramStatus:'published',youtubeStatus:'published',streamToken:'fixture'},
    {id:'fail',accountId:'a',title:'Разворот на перекрёстке',fileName:'003_turn.mp4',status:'failed',targets:['instagram','youtube'],instagramStatus:'failed',instagramNeedsReview:true,youtubeStatus:'published',error:'Instagram: прежняя публикация недоступна',streamToken:'fixture'}
  ]));
  const requests = [];
  const server = createServer(async (incoming,outgoing)=>{
    try {
      const body=[];for await(const chunk of incoming)body.push(chunk);
      const url=new URL(incoming.url,`http://${incoming.headers.host}`);
      // Local placeholder for video posters; external media/publication is never requested.
      if(url.pathname.startsWith('/s/')) {outgoing.writeHead(200,{'content-type':'image/svg+xml'});outgoing.end('<svg xmlns="http://www.w3.org/2000/svg" width="90" height="160"><path fill="#e8eceb" d="M0 0h90v160H0z"/><path fill="#899397" d="M31 0h28v160H31zM0 70h90v28H0z"/><path stroke="#fff" stroke-dasharray="8 8" d="M45 0v160"/><path fill="#0574f8" d="M48 110h6v13h-6z"/></svg>');return;}
      const headers=new Headers(incoming.headers);
      if(url.pathname.startsWith('/api/admin/'))headers.set('authorization',`Bearer ${env.ADMIN_PASSWORD}`);
      const request=new Request(url,{method:incoming.method,headers,...(body.length?{body:Buffer.concat(body)}:{})});
      requests.push({method:incoming.method,path:url.pathname});
      const pending=[];
      const response=await worker.fetch(request,env,{waitUntil(p){pending.push(p);}});
      outgoing.writeHead(response.status,Object.fromEntries(response.headers));outgoing.end(Buffer.from(await response.arrayBuffer()));
      await Promise.allSettled(pending);
    } catch(e) {outgoing.writeHead(500);outgoing.end(String(e));}
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  return {env,requests,url:`http://127.0.0.1:${server.address().port}`,async close(){server.closeAllConnections();await new Promise(r=>server.close(r));}};
}
if(process.argv.includes('--serve')) {
  const preview=await startPreview();console.log(`Isolated social preview: ${preview.url}/admin#publications/videos`);
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{await preview.close();process.exit(0);});
} else {
  test('Drive folder filters scope bulk dates, include hidden rows and descendants, and retain an empty selection', {timeout:90000},async()=>{
    const {chromium}=createRequire(import.meta.url)('playwright');
    const preview=await startPreview();
    const root={id:'root',name:''}, first={id:'folder-1',name:'PDD_1'}, second={id:'folder-2',name:'PDD_2'};
    const posts=Array.from({length:28},(_,i)=>({id:'first-'+i,accountId:'a',title:'Видео',fileName:'game_'+String(i+1).padStart(3,'0')+'.mp4',
      driveFolders:[root,first,...(i===27?[{id:'nested',name:'Подпапка'}]:[])],status:'queued',scheduledAt:null,targets:['youtube'],streamToken:'fixture'}));
    posts.push(
      {id:'second',accountId:'a',title:'Видео',fileName:'game_001.mp4',driveFolders:[root,second],status:'queued',scheduledAt:'2026-12-30T16:00:00Z',targets:['youtube'],streamToken:'fixture'},
      {id:'done',accountId:'a',fileName:'done.mp4',driveFolders:[root,first],status:'published',youtubeStatus:'published',youtubeVideoId:'keep',targets:['youtube'],streamToken:'fixture'},
      {id:'busy',accountId:'a',fileName:'busy.mp4',driveFolders:[root,first],status:'processing',scheduledAt:'2026-12-30T16:00:00Z',targets:['youtube'],streamToken:'fixture'},
      {id:'legacy',accountId:'a',fileName:'legacy.mp4',status:'queued',scheduledAt:null,targets:['youtube'],streamToken:'fixture'},
      {id:'same-name',accountId:'a',fileName:'other.mp4',driveFolders:[root,{id:'another-id',name:'PDD_1'}],status:'queued',scheduledAt:null,targets:['youtube'],streamToken:'fixture'},
      {id:'root-video',accountId:'a',fileName:'root.mp4',driveFolders:[root],status:'queued',scheduledAt:null,targets:['youtube'],streamToken:'fixture'}
    );
    await preview.env.INSTALLS.put('social:posts',JSON.stringify(posts));
    const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
    const context=await browser.newContext({viewport:{width:1440,height:1100},reducedMotion:'reduce'});
    await context.route('**/*',route=>new URL(route.request().url()).origin===preview.url?route.continue():route.abort());
    const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
    const read=async()=>JSON.parse(await preview.env.INSTALLS.get('social:posts'));
    try {
      await page.goto(preview.url+'/admin#publications/videos');
      const folder=page.getByRole('combobox',{name:'Папка на Диске'});
      await page.locator('[data-post="first-0"]').waitFor();
      await folder.selectOption('folder-1');
      assert.equal(await page.locator('#sc-list [data-post]').count(),24);
      assert.equal(await page.locator('#sc-n-q').innerText(),'29');
      assert.equal(await page.locator('#sc-n-p').innerText(),'1');
      assert.match(await page.locator('#sc-plan').innerText(),/28/);
      await page.getByRole('button',{name:'Выбрать все · 29',exact:true}).click();
      assert.match(await page.locator('#sc-bulk .sc-count').innerText(),/29/,'all rows, including hidden ones, are selected');
      await folder.selectOption('folder-2');
      assert.equal(await page.locator('[data-pick]:checked').count(),0,'changing folders clears previous selections');
      assert.equal(await page.locator('#sc-list [data-post]').count(),1);
      assert.equal(await page.locator('[data-post="second"]').count(),1,'same filenames in another folder are isolated');
      await folder.selectOption('nested');
      assert.equal(await page.locator('[data-post="first-27"]').count(),1);
      assert.match(await page.locator('#sc-plan').innerText(),/1/);
      await folder.selectOption('folder-1');
      await page.getByRole('searchbox',{name:'Найти видео'}).fill('game_00');
      assert.equal(await page.locator('#sc-list [data-post]').count(),9);
      assert.match(await page.locator('#sc-plan').innerText(),/9/,'folder and search both scope scheduling');
      await page.getByRole('searchbox',{name:'Найти видео'}).clear();
      await page.locator('#sc-plan').click();
      const modal=page.getByRole('dialog');
      assert.match(await modal.innerText(),/Расставить 28 роликов/);
      assert.match(await modal.innerText(),/Папка: PDD_1/);
      await modal.locator('#sc-m-date').fill('2026-12-10');
      await modal.locator('#sc-m-time').fill('12:30');
      await modal.locator('#sc-m-every').fill('2');
      await modal.locator('[data-ok]').click();await modal.waitFor({state:'hidden'});
      const afterFirst=await read();
      for(let i=0;i<28;i++)assert.equal(afterFirst.find(p=>p.id==='first-'+i).scheduledAt,new Date(Date.UTC(2026,11,10+2*i,9,30)).toISOString());
      assert.deepEqual(afterFirst.filter(p=>!p.id.startsWith('first-')),posts.filter(p=>!p.id.startsWith('first-')),'other folders, published and in-flight posts keep all fields');
      await folder.selectOption('folder-2');
      await page.getByRole('button',{name:'Выбрать все · 1',exact:true}).click();
      await page.locator('#sc-bulk').getByRole('button',{name:'Дата',exact:true}).click();
      await modal.locator('#sc-m-date').fill('2026-12-11');await modal.locator('#sc-m-time').fill('19:00');
      await modal.locator('#sc-m-every').fill('2');await modal.locator('[data-ok]').click();await modal.waitFor({state:'hidden'});
      const afterSecond=await read();
      assert.equal(afterSecond.find(p=>p.id==='second').scheduledAt,'2026-12-11T16:00:00.000Z');
      assert.deepEqual(afterSecond.filter(p=>p.id!=='second'),afterFirst.filter(p=>p.id!=='second'));
      await preview.env.INSTALLS.put('social:posts',JSON.stringify(afterSecond.filter(p=>p.id!=='second')));
      await page.locator('#sc-refresh').click();
      await page.waitForFunction(()=>document.querySelector('#sc-plan').disabled);
      assert.equal(await folder.inputValue(),'folder-2','disappearing folder must never silently select the entire queue');
      assert.match(await page.locator('#sc-list').innerText(),/не найдены/);
      await folder.selectOption('__unknown');
      assert.equal(await page.locator('[data-post="legacy"]').count(),1);
      assert.equal(await page.locator('#sc-folder-note').isVisible(),true);
      await folder.selectOption('folder-1');
      for(const width of [390,760]) {
        await page.setViewportSize({width,height:1000});
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`folder filter fits ${width}px`);
      }
      if(process.env.SOCIAL_UI_SCREENSHOTS) {
        const dir=fileURLToPath(new URL('../../output/social-ui/',import.meta.url));await mkdir(dir,{recursive:true});
        await page.screenshot({path:dir+'folder-filter-mobile.png',fullPage:true});
        await page.setViewportSize({width:1440,height:1100});
        await page.screenshot({path:dir+'folder-filter-desktop.png',fullPage:true});
      }
      assert.deepEqual(errors,[]);
      assert.equal(preview.requests.some(r=>r.path.includes('publish')),false,'assigning dates never triggers an immediate publication');
    } finally {await browser.close();await preview.close();}
  });

  test('video workspace saves both destinations, retains drafts, edits individual targets, and fits mobile', {timeout:90000},async()=>{
    const {chromium}=createRequire(import.meta.url)('playwright');
    const preview=await startPreview();
    const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
    const context=await browser.newContext({viewport:{width:1440,height:1100},reducedMotion:'reduce'});
    await context.route('**/*',async route=>{
      const url=new URL(route.request().url());
      if(url.origin===preview.url)return route.continue();
      if(url.hostname==='pdd-drive.ru'&&['/assets/icon-192.png','/assets/favicon.png'].includes(url.pathname))return route.fulfill({contentType:'image/png',body:await readFile(new URL(`../../web_landing/ru${url.pathname}`,import.meta.url))});
      return route.abort();
    });
    const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
    const read=async key=>JSON.parse(await preview.env.INSTALLS.get('social:'+key));
    async function screenshot(name){if(!process.env.SOCIAL_UI_SCREENSHOTS)return;const dir=fileURLToPath(new URL('../../output/social-ui/',import.meta.url));await mkdir(dir,{recursive:true});await page.screenshot({path:`${dir}/${name}.png`,fullPage:true});}
    try {
      await page.goto(preview.url+'/admin#publications/videos');
      const row=page.locator('[data-post="q"]');await row.waitFor();
      // The legacy analytics view may render an Instagram icon before being hidden.
      // Copies must not resolve their gradient against that invisible SVG.
      await page.evaluate(()=>{
        const hidden=document.createElement('div');hidden.hidden=true;hidden.id='hidden-brand-fixture';
        hidden.innerHTML=window.BRAND_SVGS.instagram;document.body.prepend(hidden);
      });
      const {PNG}=createRequire(import.meta.url)('pngjs');
      async function assertInstagramVisible(selector) {
        const png=PNG.sync.read(await page.locator(selector).screenshot());let colored=0;
        for(let i=0;i<png.data.length;i+=4) {
          const [r,g,b,a]=png.data.subarray(i,i+4);
          if(a>128&&Math.max(r,g,b)-Math.min(r,g,b)>60)colored++;
        }
        assert.ok(colored>8,`Instagram logo remains visible: ${selector}, colored pixels: ${colored}`);
      }
      await assertInstagramVisible('.sc-connection:nth-child(2) .sc-connection-logo');
      await assertInstagramVisible('#sc-t-ig svg');
      await assertInstagramVisible('[data-post="q"] .sc-platform:first-child svg');
      assert.match(await row.innerText(),/Instagram\s+Не выбрано/);
      assert.match(await row.innerText(),/Без даты/);
      assert.match(await row.innerText(),/Ожидает планирования/);
      assert.doesNotMatch(await row.innerText(),/По расписанию/);
      assert.equal(await page.locator('#sc-t-ig').getAttribute('aria-pressed'),'false');
      await page.locator('#sc-t-ig').click();
      assert.equal(await page.locator('#sc-save-schedule').isEnabled(),true);
      await page.locator('#sc-refresh').click();
      assert.equal(await page.locator('#sc-t-ig').getAttribute('aria-pressed'),'true','refresh keeps unsaved choices');
      await page.locator('#sc-save-schedule').click();
      await page.waitForFunction(()=>document.querySelector('#sc-save-state').textContent==='Сохранено');
      assert.deepEqual((await read('accounts'))[0].targets,['instagram','youtube']);
      assert.deepEqual((await read('posts'))[0].targets,['instagram','youtube']);
      assert.deepEqual((await read('posts'))[1].targets,['instagram','youtube']);
      await page.reload();await row.waitFor();
      assert.equal(await page.locator('#sc-t-ig').getAttribute('aria-pressed'),'true');
      assert.match(await row.innerText(),/Instagram\s+В очереди/);
      await screenshot('desktop');
      await row.locator('[data-pick]').check();
      await page.locator('#sc-bulk-targets').click();
      const modal=page.getByRole('dialog');
      assert.equal(await modal.evaluate(el=>el.contains(document.activeElement)),true);
      await modal.locator('[data-target="youtube"]').click();
      await modal.locator('[data-ok]').click();await modal.waitFor({state:'hidden'});
      assert.deepEqual((await read('posts'))[0].targets,['instagram']);
      await row.locator('.sc-title').click();
      await modal.locator('[data-target="instagram"]').click();
      await modal.locator('[data-ok]').click();
      assert.equal(await modal.isVisible(),true,'empty targets retain the editor');
      assert.match(await modal.locator('[role="alert"]').innerText(),/соцсеть/);
      await modal.locator('[data-target="instagram"]').click();await modal.locator('[data-target="youtube"]').click();
      await modal.locator('[data-ok]').click();await modal.waitFor({state:'hidden'});
      assert.deepEqual((await read('posts'))[0].targets,['instagram','youtube']);
      await page.locator('#sc-search').fill('нет такого видео');assert.match(await page.locator('#sc-list').innerText(),/не найдены/);
      await page.locator('#sc-search').clear();
      await page.locator('[data-filter="failed"]').click();await page.locator('[data-post="fail"]').waitFor();
      assert.match(await page.locator('[data-post="fail"]').innerText(),/YouTube\s+Опубликовано/);
      const beforeReplacement=await read('posts');
      let replacementDialog=false;
      page.once('dialog',async dialog=>{replacementDialog=true;assert.match(dialog.message(),/Создать новую запись Instagram/);assert.match(dialog.message(),/YouTube повторно публиковаться не будет/);await dialog.dismiss();});
      await page.locator('[data-post="fail"]').getByRole('button',{name:'Новая публикация'}).click();
      assert.equal(replacementDialog,true);
      assert.deepEqual(await read('posts'),beforeReplacement,'cancelling replacement does not change the queue');
      await screenshot('partial-error');
      await page.locator('[data-filter="queued"]').click();
      await page.locator('#sc-active').uncheck();await page.locator('#sc-save-schedule').click();
      await page.waitForFunction(()=>document.querySelector('#sc-save-state').textContent==='Сохранено');
      assert.equal((await read('accounts'))[0].active,false);
      for(const width of [390,760]) {
        await page.setViewportSize({width,height:1000});
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`no overflow at ${width}`);
        await screenshot('mobile-'+width);
        await row.locator('.sc-title').click();
        assert.equal(await page.evaluate(()=>document.querySelector('.sc-modal').getBoundingClientRect().right<=innerWidth),true);
        await screenshot('dialog-'+width);
        await page.keyboard.press('Escape');await modal.waitFor({state:'hidden'});
      }
      assert.deepEqual(errors,[]);
      assert.equal(preview.requests.some(r=>r.path.includes('publish')),false,'editing never triggers publication');
    } finally {await browser.close();await preview.close();}
  });
}
