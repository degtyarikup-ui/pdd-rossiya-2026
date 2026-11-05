// Real SQLite/workerd restart check. Fixture routes never enter the deployed worker.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {createServer} from 'node:net';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {setTimeout as pause} from 'node:timers/promises';

test('Telegram session survives real workerd restart and rejects another verifier', {skip:process.env.RUN_RUNTIME_SMOKE!=='1', timeout:60000}, async t=>{
 const base=fileURLToPath(new URL('../../scratch/reliability/',import.meta.url));await mkdir(base,{recursive:true});
 const dir=await mkdtemp(base+'telegram-');
 const module=fileURLToPath(new URL('./telegram_auth.js',import.meta.url));
 const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));
 await writeFile(dir+'/entry.mjs',`import {TelegramAuthState,handleTelegramAuthRequest,handleTelegramAuthCheck} from ${JSON.stringify(module)};
 export {TelegramAuthState};
 export default {async fetch(request,env){env.INSTALLS={get:async()=>null};const path=new URL(request.url).pathname;
 if(path==='/request')return handleTelegramAuthRequest(request,env);
 if(path==='/check')return handleTelegramAuthCheck(request,env);
 if(path==='/confirm'){const {nonce}=await request.json();const stub=env.TG_AUTH.get(env.TG_AUTH.idFromName(nonce));const {entry}=await (await stub.fetch('https://do/',{method:'POST',body:JSON.stringify({op:'get'})})).json();return stub.fetch('https://do/',{method:'POST',body:JSON.stringify({op:'put',entry:{...entry,status:'confirmed',user:{id:'telegram_fixture',provider:'telegram'}}})});}
 return new Response('ready');}};`);
 await writeFile(dir+'/wrangler.toml',`name="telegram-runtime-fixture"
 main="entry.mjs"
 compatibility_date="2024-11-01"
 [vars]
 SHARED_SECRET="fixture"
 SESSION_SECRET="${crypto.randomUUID()}"
 [[durable_objects.bindings]]
 name="TG_AUTH"
 class_name="TelegramAuthState"
 [[migrations]]
 tag="v1"
 new_sqlite_classes=["TelegramAuthState"]
 `);
 let proc;
 const stop=async()=>{if(proc&&!proc.killed){const done=new Promise(r=>proc.once('exit',r));proc.kill('SIGTERM');await done;}};
 t.after(stop);
 const start=async()=>{
  proc=spawn(process.env.WRANGLER_BIN||'wrangler',['dev','--local','--config',dir+'/wrangler.toml','--port',String(port),'--persist-to',dir+'/state'],{stdio:['ignore','pipe','pipe']});
  const log=createWriteStream(dir+'/runtime.log',{flags:'a'});proc.stdout.pipe(log,{end:false});proc.stderr.pipe(log,{end:false});proc.once('exit',()=>log.end());
  for(let i=0;i<100;i++){try{if((await fetch(`http://127.0.0.1:${port}`,{signal:AbortSignal.timeout(500)})).ok)return;}catch{}await pause(100);}
  throw Error('Worker startup failed: '+dir);
 };
 const call=async(path,body,status=200)=>{const r=await fetch(`http://127.0.0.1:${port}`+path,{method:'POST',headers:{'x-install-secret':'fixture'},body:JSON.stringify(body),signal:AbortSignal.timeout(5000)});assert.equal(r.status,status);return r.json();};
 await start();const c=await call('/request',{protocolVersion:2});await call('/confirm',{nonce:c.nonce});
 const first=await call('/check',c);assert.equal(first.status,'confirmed');assert.ok(first.token);
 await stop();await start();assert.deepEqual(await call('/check',c),first);
 await call('/check',{nonce:c.nonce,verifier:'wrong'},403);
 t.diagnostic('Real SQLite commit and restart verified; fixture: '+dir);
});
