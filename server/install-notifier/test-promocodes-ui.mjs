import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
import worker from './worker.js';
import { fixture, request } from './fixture-account.mjs';
async function preview(){
 const {env}=fixture();const server=createServer(async(req,res)=>{try{const chunks=[];for await(const c of req)chunks.push(c);const headers=new Headers(req.headers);headers.set('authorization','Bearer '+env.ADMIN_PASSWORD);const response=await worker.fetch(new Request('http://127.0.0.1'+req.url,{method:req.method,headers,...(chunks.length?{body:Buffer.concat(chunks)}:{})}),env,{waitUntil:p=>p.catch(()=>{})});res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));}catch(e){res.writeHead(500);res.end(String(e));}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));return {env,url:'http://127.0.0.1:'+server.address().port,close:()=>{server.closeAllConnections();server.close();}};
}
test('promo CRUD, conflicts, filters, routing, history, safe text, mobile and load errors',{timeout:120000},async()=>{
 const app=await preview();const {chromium}=createRequire(import.meta.url)('playwright');const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try{
 const page=await browser.newPage({viewport:{width:1440,height:1050}});const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',route=>new URL(route.request().url()).origin===app.url?route.continue():route.abort());
 await page.goto(app.url+'/admin#promocodes');await page.locator('#pc-state').filter({hasText:'Обновлено'}).waitFor();assert.equal(await page.locator('#promocodes-view').isVisible(),true);
 await page.locator('#pc-create').click();assert.equal(await page.locator('#pc-dialog').evaluate(d=>d.contains(document.activeElement)),true);
 const fill=(n,v)=>page.locator('#pc-form [name="'+n+'"]').fill(v);
 assert.equal(await page.locator('#pc-delete').isVisible(),false);await fill('code','WINTER7');await fill('title','Зимняя акция');await fill('days','5');await fill('maxUses','80');
 await mkdir('../../output/promocodes-ui',{recursive:true});await page.screenshot({path:'../../output/promocodes-ui/create-desktop.png'});
 await page.locator('#pc-save').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});await page.locator('[data-code="WINTER7"]').waitFor();
 await page.locator('[data-action="edit"]').click();await fill('days','9');await page.locator('#pc-save').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});await page.waitForFunction(()=>document.querySelector('#pc-body').textContent.includes('9 дн.'));
 await page.locator('[data-action="toggle"]').click();await page.locator('#pc-body').filter({hasText:'Отключён'}).waitFor();
 await page.locator('[data-action="duplicate"]').click();assert.equal(await page.locator('[name="code"]').inputValue(),'');await fill('code','SECOND9');await fill('title','<img src=x onerror=alert(1)>');await page.locator('#pc-save').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});await page.locator('[data-code="SECOND9"]').waitFor();assert.equal(await page.locator('#pc-body img').count(),0);
 await page.locator('[data-code="SECOND9"] [data-action="history"]').click();await page.locator('#pc-history').filter({hasText:'Активаций пока нет'}).waitFor();await page.locator('#pc-history-close').click();
 await page.locator('[data-code="SECOND9"] [data-action="edit"]').click();await worker.fetch(request('/api/admin/promocodes',{operation:'toggle',code:'SECOND9',enabled:false},'fixture-admin'),app.env);
 await fill('days','10');await page.locator('#pc-save').click();await page.locator('#pc-form-error').filter({hasText:'другой вкладке'}).waitFor();await page.locator('#pc-cancel').click();await page.locator('#pc-refresh').click();await page.waitForFunction(()=>document.querySelectorAll('#pc-body .pc-badge.paused').length===2);
 await page.locator('[data-code="SECOND9"] [data-action="edit"]').click();await page.locator('#pc-delete').click();await page.locator('#pc-delete').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});await page.locator('[data-code="SECOND9"]').waitFor({state:'detached'});
 await page.locator('#pc-filter').selectOption('deleted');await page.locator('[data-code="SECOND9"]').waitFor();await page.locator('#pc-filter').selectOption('all');await page.locator('#pc-search').fill('nothing');await page.locator('#pc-body').filter({hasText:'не найдены'}).waitFor();await page.locator('#pc-search').fill('');await page.screenshot({path:'../../output/promocodes-ui/list-desktop.png'});
 await page.locator('[data-feature="users"]').click();assert.equal(await page.locator('#promocodes-view').isVisible(),false);await page.locator('[data-feature="promocodes"]').click();await page.reload();await page.locator('#pc-state').filter({hasText:'Обновлено'}).waitFor();
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:'../../output/promocodes-ui/list-mobile.png'});await page.locator('#pc-create').click();await page.screenshot({path:'../../output/promocodes-ui/create-mobile.png'});assert.equal(await page.locator('#pc-dialog').evaluate(d=>d.scrollWidth<=d.clientWidth),true);await page.locator('#pc-cancel').click();
 await page.locator('#pc-create').click();await fill('code','UNLIMITED');
 assert.equal(await page.locator('[name="maxUses"]').inputValue(),'');assert.equal(await page.locator('[name="expiresAt"]').inputValue(),'');
 await page.locator('#pc-save').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});
 await page.locator('[data-code="UNLIMITED"]').filter({hasText:'Бессрочно'}).waitFor();assert.ok((await page.locator('[data-code="UNLIMITED"]').textContent()).includes('∞'));
 await page.locator('[data-code="UNLIMITED"] [data-action="edit"]').click();assert.equal(await page.locator('[name="maxUses"]').inputValue(),'');await fill('maxUses','10');await page.locator('#pc-save').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});
 await page.locator('[data-code="UNLIMITED"]').filter({hasText:'0 / 10'}).waitFor();await page.locator('[data-code="UNLIMITED"] [data-action="edit"]').click();await fill('maxUses','');await page.locator('#pc-save').click();await page.locator('#pc-dialog').waitFor({state:'hidden'});await page.locator('[data-code="UNLIMITED"]').filter({hasText:'∞'}).waitFor();
 await page.route('**/api/admin/promocodes',route=>route.fulfill({status:503,contentType:'application/json',body:'{"error":"unavailable"}'}));await page.locator('#pc-refresh').click();await page.waitForTimeout(200);assert.equal(await page.locator('[data-code="WINTER7"]').count(),1);assert.deepEqual(errors,[]);
 }finally{await browser.close();app.close();}
});
