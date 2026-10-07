import test from 'node:test';
import assert from 'node:assert/strict';
import { usersSnapshot } from './analytics_data.js';
import { userSummary, listUserSummaries } from './user_store.js';
import { ANALYTICS_CLIENT_JS, ANALYTICS_VIEW_HTML } from './analytics_ui.js';
const now=Date.parse('2026-10-04T09:00:00Z');
const day=d=>d.toISOString().slice(0,10);
const base={provider:'google',app:'ru',createdAt:'2026-10-04T01:00:00Z',lastSeenAt:'2026-10-04T02:00:00Z'};
test('geography filters project and account creation period; does not guess missing locations',()=>{
 const users=[{...base,id:'a',ipCountry:'RU',ipRegion:'Moscow',ipCity:'Moscow',isPremium:true},{...base,id:'b',ipCountry:'RU',ipRegion:'Moscow',ipCity:'Moscow'},{...base,id:'c',ipCountry:'XX'},{...base,id:'d',app:'rs',ipCountry:'RS'},{...base,id:'e',createdAt:'2026-09-01T01:00:00Z',ipCountry:'BY'},{...base,id:'f',provider:'guest',ipCountry:'RU'},{...base,id:'g',suspect:true,ipCountry:'RU'}];
 const result=usersSnapshot(users,1,'ru',day,now);
 assert.equal(result.registrations,3);assert.equal(result.geography.known,2);assert.equal(result.geography.unknown,1);
 assert.deepEqual(result.geography.regions,[{name:'Moscow',country:'RU',accounts:2,active7:2,premium:1}]);
 assert.equal(result.geography.cities[0].accounts,2);
});
test('old v2 summaries retain counts while geographic enrichment is bounded',async()=>{
 const records=Array.from({length:160},(_,i)=>({...base,id:'u'+i,ipCountry:'RU',ipRegion:'Moscow'}));
 let reads=0,writes=0;
 const env={INSTALLS:{list:async()=>({keys:records.map(u=>({name:'user:'+u.id,metadata:{...base,id:u.id,v:2}})),list_complete:true}),get:async key=>{reads++;return JSON.stringify(records.find(u=>'user:'+u.id===key));},put:async()=>{writes++;}}};
 const result=await listUserSummaries(env);
 assert.equal(result.length,160);assert.equal(reads,150);assert.equal(writes,150);
 assert.equal(result.filter(u=>u.ipCountry==='RU').length,150);
 assert.equal(result.filter(u=>u.pending).length,0);
});
test('metadata stays under Cloudflare byte limit with multilingual fields',()=>{
 const meta=userSummary({...base,id:'apple_'+'.'.repeat(80),name:'Я'.repeat(60),email:'я'.repeat(80),avatarUrl:'https://example.com/'+'.'.repeat(270),ipRegion:'Ш'.repeat(60),ipCity:'Ш'.repeat(60)});
 assert.ok(new TextEncoder().encode(JSON.stringify(meta)).length<=1024);
 assert.equal(meta.v,4);
});
test('analytics client compiles and avoids false conversion presentation',()=>{
 assert.doesNotThrow(()=>new Function(ANALYTICS_CLIENT_JS));
 assert.ok(ANALYTICS_VIEW_HTML.includes('География'));
 assert.ok(!ANALYTICS_CLIENT_JS.includes("'посетителей'"));
 assert.ok(!ANALYTICS_CLIENT_JS.includes("name: 'Скачали'"));
});

test('geographic filtering preserves denominator under search and supports all pages',async()=>{
 const {selectGeoRows}=await import('./analytics_geo.js');
 const rows=Array.from({length:21},(_,i)=>({name:'region'+i,label:'Регион '+i,country:i===20?'BY':'RU',accounts:i+1,active7:20-i,premium:i%3,search:'Регион '+i}));
 const result=selectGeoRows(rows,{country:'RU',query:'Регион 1',pageSize:8});
 assert.equal(result.baseTotal,210);
 assert.equal(result.count,11);
 assert.equal(result.rows.length,8);
 assert.equal(result.pages,2);
 const second=selectGeoRows(rows,{country:'RU',query:'Регион 1',page:1,pageSize:8});
 assert.equal(second.rows.length,3);
 assert.equal(new Set([...result.rows,...second.rows].map(r=>r.name)).size,11);
 assert.equal(selectGeoRows(rows,{query:'absent',page:5}).page,0);
 assert.equal(selectGeoRows(rows,{sort:'active7'}).rows[0].active7,20);
 assert.equal(selectGeoRows(rows,{sort:'accounts',descending:false}).rows[0].accounts,1);
});

test('daily activity deduplicates syncs, preserves platform history and uses Moscow midnight', async () => {
 const {recordActivity, activitySnapshot, activityDay}=await import('./analytics_activity.js');
 const user={...base,platform:'android',lastSeenAt:'2026-10-07T20:59:00Z'};
 const first=Date.parse(user.lastSeenAt);
 recordActivity(user,first); recordActivity(user,first);
 user.platform='ios';recordActivity(user,first);
 user.lastSeenAt='2026-10-07T21:01:00Z';recordActivity(user,Date.parse(user.lastSeenAt));
 const days=activitySnapshot([user],['2026-10-06','2026-10-07','2026-10-08'],Date.parse(user.lastSeenAt)).days;
 assert.equal(activityDay(Date.parse(user.lastSeenAt)),'2026-10-08');
 assert.equal(days[0].total,null);
 assert.deepEqual(days[1],{date:'2026-10-07',total:1,android:1,ios:1,web:0,unknown:0});
 assert.deepEqual(days[2],{date:'2026-10-08',total:1,android:0,ios:1,web:0,unknown:0});
});
test('activity retains 90 days and never reconstructs past days from last seen', async () => {
 const {recordActivity,activitySnapshot}=await import('./analytics_activity.js');
 const user={...base,platform:'android',lastSeenAt:'2026-10-07T09:00:00Z'};
 recordActivity(user,Date.parse(user.lastSeenAt));
 user.lastSeenAt='2027-01-05T09:00:00Z'; recordActivity(user,Date.parse(user.lastSeenAt));
 assert.equal(user.activity.android,'1');
 const old={...base,lastSeenAt:'2026-10-08T09:00:00Z',platform:'ios'};
 const snapshot=activitySnapshot([old],['2026-10-07','2026-10-08'],Date.parse(old.lastSeenAt));
 assert.equal(snapshot.days[0].total,0); assert.equal(snapshot.days[1].ios,1);
 const result=usersSnapshot([{...old,app:'by'},{...old,provider:'guest'},{...old,suspect:true}],2,'ru',d=>d.toISOString().slice(0,10),Date.parse(old.lastSeenAt));
 assert.equal(result.activity.days[1].total,0);
});
