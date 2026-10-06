import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { NotificationsState } from './notifications.js';
import { validateRelease } from './app_updates.js';
import { APP_UPDATES_CLIENT_JS } from './app_updates_ui.js';
const release = (extra={}) => ({app:'ru',platform:'android',enabled:true,version:'2.1.9',build:49,packageId:'ru.pdd.pdd_app',storeUrl:'https://play.google.com/store/apps/details?id=ru.pdd.pdd_app',notes:'Исправления игры',...extra});
function setup(){
 const data=new Map(),storage={get:async key=>data.get(key),put:async(key,value)=>data.set(key,structuredClone(value)),list:async({prefix})=>new Map([...data].filter(([key])=>key.startsWith(prefix)))};
 const obj=new NotificationsState({storage},{});
 const call=(path,body)=>obj.fetch(new Request('https://test'+path,{method:body?'POST':'GET',...(body?{body:JSON.stringify(body)}:{})}));
 return {data,call,env:{NOTIFICATIONS:{idFromName:()=> 'test',get:()=>({fetch:(url,options)=>obj.fetch(new Request(url,options))})}}};
}
test('release settings require exact audience, version/build and official store matching package',()=>{
 for(const extra of [{app:'all'},{platform:'web'},{version:'2.beta'},{version:'9999999.0'},{build:0},{build:'49'},{build:1.5},{enabled:'true'},{storeUrl:'https://example.com'},{storeUrl:'https://play.google.com/store/apps/details?id=other.app'},{storeUrl:'http://play.google.com/store/apps/details?id=ru.pdd.pdd_app'},{notes:'x'.repeat(1001)}]) assert.throws(()=>validateRelease(release(extra)));
 assert.equal(validateRelease(release({platform:'ios',storeUrl:'https://apps.apple.com/ru/app/id6792369533'})).platform,'ios');
 for(const storeUrl of ['https://apps.apple.com/anything','https://apps.apple.com.evil.test/app/id123','https://user:pass@apps.apple.com/app/id123']) assert.throws(()=>validateRelease(release({platform:'ios',storeUrl})));
});
test('release policy survives edits, isolates all countries/platforms, and supports disabling',async()=>{
 const {call}=setup();
 assert.deepEqual(await(await call('/updates?app=ru&platform=ios')).json(),{release:null});
 for(const app of ['ru','by','rs']) {
  const item=release({app,packageId:app+'.pdd.pdd_app',storeUrl:'https://play.google.com/store/apps/details?id='+app+'.pdd.pdd_app'});
  assert.equal((await call('/updates/save',item)).status,200);
  assert.equal((await(await call('/updates?app='+app+'&platform=android')).json()).release.app,app);
  assert.equal((await(await call('/updates?app='+app+'&platform=ios')).json()).release,null);
 }
 await call('/updates/save',release({enabled:false}));
 assert.equal((await(await call('/updates?app=ru&platform=android')).json()).release.enabled,false);
 assert.equal((await(await call('/updates/admin')).json()).releases.length,3);
 assert.equal((await call('/updates?app=all&platform=android')).status,400);
 assert.equal((await call('/updates/save',release({build:0}))).status,400);
});
test('public worker update API has CORS/no-store and never discloses another country',async()=>{
 const {call,env}=setup();await call('/updates/save',release());
 const get=path=>worker.fetch(new Request('https://test'+path),env);
 const ru=await get('/api/app-update?app=ru&platform=android');
 assert.equal(ru.status,200);assert.equal(ru.headers.get('Access-Control-Allow-Origin'),'*');assert.equal(ru.headers.get('Cache-Control'),'no-store');
 assert.equal((await ru.json()).release.build,49);
 assert.equal((await(await get('/api/app-update?app=by&platform=android')).json()).release,null);
 for(const method of ['GET','POST']) {
  const r=await worker.fetch(new Request('https://test/api/admin/app-updates',{method,...(method==='POST'?{body:JSON.stringify(release())}:{})}),{INSTALLS:{get:async()=>null}});
  assert.equal(r.status,401);
 }
});
test('admin embeds release editor and scripts compile without touching campaign editor',async()=>{
 new Function(APP_UPDATES_CLIENT_JS);
 const html=await(await worker.fetch(new Request('https://test/admin'),{})).text();
 assert.equal((html.match(/id="up-form"/g)||[]).length,1);
 new Function(html.match(/<script>([\s\S]*)<\/script>/)[1]);
 assert.match(html,/id="up-platform"/);assert.match(html,/id="nt-form"/);
});
