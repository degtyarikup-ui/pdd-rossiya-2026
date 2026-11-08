// Local workerd + SQLite only. No production credentials or provider requests.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve, join } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
const port=async()=>{const s=createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;};
test('real SQLite queue survives restart, rejects stale status writes and projects through automatic alarms after KV recovery',{
  skip:process.env.RUN_RUNTIME_SMOKE!=='1',timeout:120000,
},async t=>{
  const base=fileURLToPath(new URL('../../scratch/reliability/runtime/',import.meta.url));await mkdir(base,{recursive:true});
  const dir=await mkdtemp(join(base,'social-')),config=join(dir,'wrangler.toml'),entry=join(dir,'entry.mjs'),empty=join(dir,'empty.env');
  const guard=fileURLToPath(new URL('./social_guard.js',import.meta.url));
  const queue=fileURLToPath(new URL('./social_queue.js',import.meta.url));
  await writeFile(entry,`import {SocialPublisher as Production} from ${JSON.stringify(guard)};
import {readSocialPosts,saveSocialPosts} from ${JSON.stringify(queue)};
export class SocialPublisher extends Production {
 constructor(state,env){super(state,{...env,INSTALLS:{get:(...a)=>env.INSTALLS.get(...a),put:async(...a)=>{
  if(await state.storage.get('fixture:blocked'))throw Error('fixture KV outage');return env.INSTALLS.put(...a);
 }}});this.fixtureState=state;}
 async fetch(request){const p=new URL(request.url).pathname;
  if(p==='/fixture/block'){await this.fixtureState.storage.put('fixture:blocked',(await request.json()).blocked);return Response.json({ok:true});}
  if(p==='/fixture/wake'){await this.fixtureState.storage.setAlarm(Date.now()+100);return Response.json({ok:true});}
  if(p==='/fixture/state')return Response.json({dirty:await this.fixtureState.storage.get('queue:dirty'),alarm:await this.fixtureState.storage.getAlarm()});
  return super.fetch(request);
 }
}
export default {async fetch(request,env){const p=new URL(request.url).pathname;
 if(p==='/health')return new Response('ok');
 if(p==='/seed'){await env.INSTALLS.put('social:posts',JSON.stringify(await request.json()));return Response.json({ok:true});}
 if(p==='/kv')return Response.json({posts:JSON.parse(await env.INSTALLS.get('social:posts'))});
 if(p==='/read')return Response.json({posts:await readSocialPosts(env)});
 return env.SOCIAL_PUBLISHER.get(env.SOCIAL_PUBLISHER.idFromName('queue-state-v1')).fetch(request);
}};
`);
  await writeFile(config,`name = "social-runtime-fixture"
main = ${JSON.stringify(entry)}
compatibility_date = "2024-11-01"
[vars]
SOCIAL_QUEUE_REQUIRED = "true"
[[kv_namespaces]]
binding = "INSTALLS"
id = "fixture"
[[durable_objects.bindings]]
name = "SOCIAL_PUBLISHER"
class_name = "SocialPublisher"
[[migrations]]
tag = "fixture-v1"
new_sqlite_classes = ["SocialPublisher"]
`);await writeFile(empty,'');
  const env=Object.fromEntries(['PATH','HOME','USER','TMPDIR','LANG'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]));Object.assign(env,{CI:'1',WRANGLER_SEND_METRICS:'false'});
  let child,closed,origin,log,generation=0;
  const stop=async()=>{if(!child)return;child.kill('SIGTERM');const timer=setTimeout(()=>child?.kill('SIGKILL'),4000);await closed;clearTimeout(timer);log.end();child=null;};
  t.after(stop);
  const start=async()=>{const p=await port();origin='http://127.0.0.1:'+p;log=createWriteStream(join(dir,'workerd-'+(++generation)+'.log'));
    child=spawn(process.env.WRANGLER_BIN||'wrangler',['dev','--local','--config',config,'--env-file',empty,'--ip','127.0.0.1','--port',String(p),'--inspector-port',String(await port()),'--persist-to',join(dir,'persist'),'--log-level','warn','--show-interactive-dev-session=false'],{cwd:dir,env,stdio:['ignore','pipe','pipe']});
    child.stdout.pipe(log,{end:false});child.stderr.pipe(log,{end:false});closed=new Promise(r=>child.once('close',r));
    const until=Date.now()+30000;while(Date.now()<until){if(child.exitCode!==null)throw Error('workerd failed: '+dir);try{if((await fetch(origin+'/health')).ok)return;}catch{}await pause(200);}throw Error('startup timeout: '+dir);
  };
  const api=async(path,body,expected=200)=>{const r=await fetch(origin+path,{method:body===undefined?'GET':'POST',...(body===undefined?{}:{body:JSON.stringify(body)})});const text=await r.text();assert.equal(r.status,expected,path+': '+text);return expected===200?JSON.parse(text):text;};
  await start();
  const posts=Array.from({length:180},(_,i)=>({id:'p'+i,status:'queued',caption:'содержимое '.repeat(100)}));
  await api('/seed',posts);assert.equal((await api('/read')).posts.length,180);
  await api('/fixture/block',{blocked:true});
  await api('/queue/change',{changes:[{id:'p0',fields:[{key:'status',before:'queued',after:'published'}]}]});
  await stop();await start();
  assert.equal((await api('/read')).posts.find(p=>p.id==='p0').status,'published');
  await api('/queue/change',{changes:[{id:'p0',fields:[{key:'status',before:'queued',after:'processing'}]},{id:'p1',fields:[{key:'status',before:'queued',after:'failed'}]}]},409);
  assert.equal((await api('/read')).posts.find(p=>p.id==='p1').status,'queued');
  await api('/fixture/wake',{});await pause(700);
  const pending=await api('/fixture/state');assert.equal(pending.dirty,true);assert.ok(pending.alarm>Date.now());
  await api('/fixture/block',{blocked:false});await api('/fixture/wake',{});
  const until=Date.now()+10000;let mirrored;
  do{mirrored=(await api('/kv')).posts;if(mirrored.find(p=>p.id==='p0')?.status==='published')break;await pause(100);}while(Date.now()<until);
  assert.equal(mirrored.find(p=>p.id==='p0').status,'published');assert.equal((await api('/fixture/state')).dirty,undefined);
  t.diagnostic('Real workerd: >128KiB queue, restart, conflict atomicity, durable retry alarm and automatic KV projection verified. '+dir);
});
