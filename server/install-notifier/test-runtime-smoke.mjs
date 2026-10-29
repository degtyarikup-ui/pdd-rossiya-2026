// Actual SQLite-backed workerd integration, deliberately opt-in:
// RUN_RUNTIME_SMOKE=1 WRANGLER_BIN=/path/to/wrangler node --test test-runtime-smoke.mjs
// No Cloudflare account, production secrets, provider requests or remote writes.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { signSession } from './user_auth.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const worker = fileURLToPath(new URL('./worker.js', import.meta.url));
const enabled = process.env.RUN_RUNTIME_SMOKE === '1';

async function unusedPort() {
  const server = createServer();
  await new Promise((resolve, reject) => server.once('error', reject).listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  await new Promise(resolve => server.close(resolve));
  return port;
}

test('real workerd acknowledges primary state independently of repair and persists progress, Premium and revocation', {
  skip: enabled ? false : 'set RUN_RUNTIME_SMOKE=1 and point WRANGLER_BIN at an installed Wrangler',
  timeout: 180000,
}, async t => {
  const base = resolve(root, 'scratch/reliability/runtime');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'smoke-'));
  const persist = join(directory, 'persist');
  const credential = 'runtime-fixture-' + crypto.randomUUID();
  const signingSecret = crypto.randomUUID();
  const config = join(directory, 'wrangler.toml');
  const entry = join(directory, 'entry.mjs');
  const classes = ['AccountState', 'AiQuotaState', 'StatsBuffer', 'PurchaseClaims', 'TrafficState',
    'TelegramQueue', 'NotificationsState', 'SupportThread', 'TelegramAuthState'];
  const bindings = ['ACCOUNTS', 'AI_QUOTAS', 'STATS', 'PURCHASE_CLAIMS', 'TRAFFIC',
    'TELEGRAM', 'NOTIFICATIONS', 'SUPPORT', 'TG_AUTH'];
  // This entry exists only inside the ignored fixture directory. All normal
  // routes execute the real production handler, with the real exported DOs.
  // Fixture-only routes expose initialization, repair injection and KV projection
  // for assertions. They never exist in the deployed production worker.
  await writeFile(entry, `import app, {AccountState as ProductionAccountState} from ${JSON.stringify(worker)};
export { ${classes.filter(name=>name!=='AccountState').join(', ')} } from ${JSON.stringify(worker)};
export class AccountState extends ProductionAccountState {
  constructor(state, env) {
    const repair={blocked:false,flushCalls:0,listCalls:0};
    const storage=new Proxy(state.storage,{get(target,key) {
      if(key==='list')return async options=>{
        if(['doc:','index:','effect:','projection:'].includes(options?.prefix)) {
          repair.listCalls++;
          if(repair.blocked)throw new Error('fixture repair list must not run in primary request');
        }
        return target.list(options);
      };
      const value=Reflect.get(target,key,target);
      return typeof value==='function'?value.bind(target):value;
    }});
    super(new Proxy(state,{get(target,key) {
      if(key==='storage')return storage;
      const value=Reflect.get(target,key,target);
      return typeof value==='function'?value.bind(target):value;
    }}),env);
    this.runtimeRepair=repair;
    this.runtimeInstance=crypto.randomUUID();
  }
  async flush() {
    this.runtimeRepair.flushCalls++;
    if(this.runtimeRepair.blocked)throw new Error('fixture repair flush must not run in primary request');
    return super.flush();
  }
  fetch(request) {
    const path=new URL(request.url).pathname;
    if(path.startsWith('/_runtime/')&&request.headers.get('x-runtime-fixture')===this.env.SHARED_SECRET) {
      if(path==='/_runtime/repair-mode')return this.serial(async()=>{
        const {blocked}=await request.json();
        this.runtimeRepair.blocked=blocked===true;
        this.runtimeRepair.flushCalls=0;this.runtimeRepair.listCalls=0;
        return Response.json(this.runtimeRepair);
      });
      if(path==='/_runtime/instance')return this.serial(()=>Response.json({instance:this.runtimeInstance}));
      if(path==='/_runtime/memory-write-fault')return this.serial(async()=>{
        await this.state.storage.transaction(async txn=>{
          await txn.put('doc:user_progress:google_runtime_fixture',{key:'user_progress:google_runtime_fixture',value:'{}',epoch:'1'});
          this.state.storage.sql.exec('SELECT 1 IN ('+Array.from({length:10000},(_,i)=>i).join(',')+')').toArray();
        });
        return Response.json({unexpectedSuccess:true});
      });
      if(path==='/_runtime/memory-fault')return this.serial(()=>{
        // Compile a deliberately oversized VM program in local SQLite only.
        // The workerd opcode limit produces a real SQLITE_NOMEM without large
        // data or touching any production/account table.
        this.state.storage.sql.exec('SELECT 1 IN ('+Array.from({length:10000},(_,i)=>i).join(',')+')').toArray();
        return Response.json({unexpectedSuccess:true});
      });
      if(path==='/_runtime/repair-state')return this.serial(()=>Response.json(this.runtimeRepair));
      if(path==='/_runtime/schedule-repair')return this.serial(async()=>{
        const scheduledAt=Date.now()+50;
        await this.state.storage.setAlarm(scheduledAt);
        return Response.json({scheduledAt});
      });
      if(path==='/_runtime/alarm-state')return this.serial(async()=>Response.json({alarm:await this.state.storage.getAlarm()}));
      if(path==='/_runtime/alarm')return this.alarm().then(()=>Response.json({ok:true}));
    }
    if (new URL(request.url).pathname === '/_runtime/pressure' && request.headers.get('x-runtime-fixture') === this.env.SHARED_SECRET) {
      return this.serial(async () => {
        const id=request.headers.get('x-account-id');
        const before=await this.loadRecord('user_progress:'+id);
        for(let i=0;i<61;i++) {
          const key='revoked_session:'+id+':'+i.toString(16).padStart(64,'0');
          await this.state.storage.put('doc:'+key,{key,value:'1',options:{},expiresAt:Date.now()-1000,epoch:'1'});
        }
        await this.expireRecords();
        const pendingBefore=(await this.state.storage.list({prefix:'projection:'})).size;
        for(let i=0;i<3;i++)await this.flush();
        return Response.json({pendingBefore,pendingAfter:(await this.state.storage.list({prefix:'projection:'})).size,
          progressUnchanged:before.value===(await this.loadRecord('user_progress:'+id)).value});
      });
    }
    return super.fetch(request);
  }
}
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/__runtime_fixture/')) {
      if (request.headers.get('x-runtime-fixture') !== env.SHARED_SECRET) return new Response(null, {status: 404});
      if (url.pathname === '/__runtime_fixture/support-state') {
        return env.SUPPORT.get(env.SUPPORT.idFromName(url.searchParams.get('clientId'))).fetch('https://support.internal/list');
      }
      if (url.pathname === '/__runtime_fixture/pressure') {
        return env.ACCOUNTS.get(env.ACCOUNTS.idFromName('google_runtime_fixture')).fetch('https://account.internal/_runtime/pressure', {
          headers:{'x-account-id':'google_runtime_fixture','x-runtime-fixture':env.SHARED_SECRET}});
      }
      if (['/__runtime_fixture/repair-mode','/__runtime_fixture/repair-state','/__runtime_fixture/schedule-repair',
        '/__runtime_fixture/alarm-state','/__runtime_fixture/alarm','/__runtime_fixture/instance','/__runtime_fixture/memory-fault','/__runtime_fixture/memory-write-fault'].includes(url.pathname)) {
        try { return await env.ACCOUNTS.get(env.ACCOUNTS.idFromName('google_runtime_fixture')).fetch('https://account.internal/_runtime/'+url.pathname.split('/').at(-1), {
          method:request.method,
          headers:{'x-account-id':'google_runtime_fixture','x-runtime-fixture':env.SHARED_SECRET},
          ...(request.method==='POST'?{body:await request.text()}:{}),
        }); } catch(error) { if(url.pathname.endsWith('/memory-fault')||url.pathname.endsWith('/memory-write-fault'))return Response.json({failed:true},{status:503}); throw error; }
      }
      if (url.pathname === '/__runtime_fixture/flush-stats') {
        const response=await env.STATS.get(env.STATS.idFromName('main')).fetch('https://stats/flush',{method:'POST'});
        return Response.json({status:response.status});
      }
      if (url.pathname === '/__runtime_fixture/kv') {
        const key = url.searchParams.get('key');
        if (request.method === 'POST') await env.INSTALLS.put(key, await request.text());
        return Response.json({value: await env.INSTALLS.get(key)});
      }
      return new Response(null, {status: 404});
    }
    return app.fetch(request, env, ctx);
  }
};
`);
  await writeFile(config, `name = "pdd-runtime-smoke"
main = ${JSON.stringify(entry)}
compatibility_date = "2024-11-01"
[vars]
ACCOUNT_STATE_REQUIRED = "true"
ACCOUNT_STATE_EPOCH = "1"
SESSION_SECRET = ${JSON.stringify(signingSecret)}
SHARED_SECRET = ${JSON.stringify(credential)}
ADMIN_PASSWORD = ${JSON.stringify(credential)}
[[kv_namespaces]]
binding = "INSTALLS"
id = "00000000000000000000000000000000"
[durable_objects]
bindings = [${classes.map((name, i) => `{name = "${bindings[i]}", class_name = "${name}"}`).join(', ')}]
[[migrations]]
tag = "runtime-v1"
new_sqlite_classes = [${classes.map(JSON.stringify).join(', ')}]
`);
  // Explicit empty env file and scratch cwd avoid loading the project's .dev.vars.
  const envFile = join(directory, 'fixture.env');
  await writeFile(envFile, '# Test-only bindings are declared in wrangler.toml.\n');
  const environment = Object.fromEntries(['PATH', 'HOME', 'USER', 'TMPDIR', 'LANG', 'SYSTEMROOT']
    .filter(key => process.env[key]).map(key => [key, process.env[key]]));
  Object.assign(environment, { CI: '1', NO_COLOR: '1', WRANGLER_SEND_METRICS: 'false' });
  let child, origin, generation = 0, log, stopped;
  const stop = async () => {
    if (!child) return;
    const processToStop = child;
    child = null;
    processToStop.kill('SIGTERM');
    const timer = setTimeout(() => processToStop.kill('SIGKILL'), 4000);
    try { await stopped; } finally { clearTimeout(timer); log.end(); }
  };
  const start = async () => {
    const port = await unusedPort();
    const inspector = await unusedPort();
    origin = `http://127.0.0.1:${port}`;
    log = createWriteStream(join(directory, `workerd-${++generation}.log`));
    child = spawn(process.env.WRANGLER_BIN || 'wrangler', [
      'dev', '--local', '--config', config, '--env-file', envFile,
      '--ip', '127.0.0.1', '--port', String(port), '--inspector-port', String(inspector),
      '--persist-to', persist, '--log-level', 'warn', '--show-interactive-dev-session=false',
    ], { cwd: directory, env: environment, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.pipe(log, { end: false });
    child.stderr.pipe(log, { end: false });
    let spawnError;
    child.once('error', error => { spawnError = error; });
    const running = child;
    stopped = new Promise(resolve => running.once('close', resolve));
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      if (spawnError) throw spawnError;
      if (running.exitCode !== null) throw new Error(`Wrangler exited ${running.exitCode}; see ${directory}`);
      try {
        const response = await fetch(origin + '/api/ads/config', { signal: AbortSignal.timeout(1000) });
        if (response.ok) return;
      } catch { /* Compilation and startup are bounded by the deadline. */ }
      await pause(200);
    }
    throw new Error(`Wrangler startup exceeded 30s; see ${directory}`);
  };
  const api = async (path, { body, token, expected = 200, fixture = false } = {}) => {
    const response = await fetch(origin + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { 'content-type': 'application/json', 'x-install-secret': credential,
        ...(fixture ? { 'x-runtime-fixture': credential } : {}),
        ...(token ? { authorization: 'Bearer ' + token } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(12000),
    });
    const text = await response.text();
    assert.equal(response.status, expected, `${path}: HTTP ${response.status}: ${text.slice(0, 300)}`);
    return JSON.parse(text);
  };
  const userId = 'google_runtime_fixture';
  const repairMode=blocked=>api('/__runtime_fixture/repair-mode',{fixture:true,body:{blocked}});
  const repairState=()=>api('/__runtime_fixture/repair-state',{fixture:true});
  const drainRepair=async()=>{
    await repairMode(false);
    await api('/__runtime_fixture/alarm',{fixture:true});
  };
  const automaticRepair=async(key,accept)=>{
    await repairMode(false);
    const scheduled=await api('/__runtime_fixture/schedule-repair',{fixture:true,body:{}});
    assert.ok(scheduled.scheduledAt>Date.now()-1000);
    // This path deliberately never invokes the alarm method. workerd must
    // dispatch the inherited production alarm from its persisted schedule.
    const deadline=Date.now()+12000;
    let projected;
    do {
      projected=(await api('/__runtime_fixture/kv?key='+encodeURIComponent(key),{fixture:true})).value;
      if(projected!==null&&accept(JSON.parse(projected)))break;
      await pause(100);
    } while(Date.now()<deadline);
    assert.ok(projected!==null&&accept(JSON.parse(projected)),'scheduled workerd alarm did not converge '+key);
    const repaired=await repairState();
    assert.equal(repaired.blocked,false);
    assert.ok(repaired.flushCalls>0,'workerd must invoke the actual inherited alarm');
    assert.ok(repaired.listCalls>0);
    const {alarm}=await api('/__runtime_fixture/alarm-state',{fixture:true});
    assert.ok(alarm===null||alarm>Date.now()+10*60000,
      'successful automatic repair must cancel its short recovery wake-up or retain only a future expiry');
    return JSON.parse(projected);
  };
  const identity = { id: userId, provider: 'google', name: 'Runtime fixture',
    email: 'runtime@example.invalid', createdAt: new Date().toISOString() };
  const token = await signSession({ SESSION_SECRET: signingSecret }, {
    user: identity, expiresAt: Date.now() + 3600000, generation: '',
  });
  const anotherToken = await signSession({ SESSION_SECRET: signingSecret }, {
    user: identity, expiresAt: Date.now() + 3600000, generation: '',
  });
  try {
    await start();
    await api('/api/user/status', { token, expected: 404 });
    await repairMode(true);
    const profile = await api('/api/user/sync', { token, body: { id: userId,
      platform: 'android', appVersion: 'runtime-smoke', app: 'ru' } });
    assert.equal(profile.user.id, userId);
    assert.equal(profile.isPremium, false);
    assert.equal((await api('/api/user/status', { token })).user.id, userId);
    assert.deepEqual(await repairState(),{blocked:true,flushCalls:0,listCalls:0});
    assert.equal((await api('/__runtime_fixture/kv?key=user:' + userId, { fixture: true })).value,null);
    await automaticRepair('user:'+userId,value=>value.id===userId);
    await api('/api/user/progress?userId=google_somebody_else', { token, expected: 403 });
    t.diagnostic('profile acknowledged with repair unavailable; workerd automatically fired its persisted alarm and converged KV; cross-account access denied');

    const stamp = Date.now();
    const progress = { questionProgressAb: { runtime_q: { answeredAt: stamp, correct: true, attemptsCount: 1 } },
      favoritesAb: ['runtime_q'], settings: { unicodeFixture: 'Проверка🚗'.repeat(14000) } };
    assert.ok(Buffer.byteLength(JSON.stringify(progress)) > 128 * 1024);
    const snapshot = { userId, progress, appVersion: 'runtime-smoke', platform: 'android' };
    await repairMode(true);
    const written = await api('/api/user/progress/sync', { token, body: snapshot });
    assert.equal(written.progress.questionProgressAb.runtime_q.correct, true);
    const duplicate = await api('/api/user/progress/sync', { token, body: snapshot });
    assert.equal(duplicate.serverUpdatedAt, written.serverUpdatedAt);
    const read = await api('/api/user/progress?userId=' + userId, { token });
    assert.deepEqual(read.progress, written.progress);
    assert.deepEqual(await repairState(),{blocked:true,flushCalls:0,listCalls:0});
    assert.equal((await api('/__runtime_fixture/kv?key=user_progress:' + userId, { fixture: true })).value,null);
    const grant=await api('/api/admin/users/grant-premium',{token:credential,body:{userId,days:7,notify:false}});
    assert.equal(grant.ok,true);
    const premium=await api('/api/user/status',{token});
    assert.equal(premium.isPremium,true);
    assert.ok(premium.premiumExpiresAt);
    assert.deepEqual(await repairState(),{blocked:true,flushCalls:0,listCalls:0});
    // Restart before the first repair event: the primary acknowledgement must
    // imply durable progress/Premium and a recoverable outbox, not a KV write.
    await stop();
    await start();
    await repairMode(true);
    assert.deepEqual((await api('/api/user/progress?userId='+userId,{token})).progress,written.progress);
    const premiumAfterRestart=await api('/api/user/status',{token});
    assert.equal(premiumAfterRestart.isPremium,true);
    assert.equal(premiumAfterRestart.premiumExpiresAt,premium.premiumExpiresAt);
    assert.deepEqual(await repairState(),{blocked:true,flushCalls:0,listCalls:0});
    const projected=await automaticRepair('user_progress:'+userId,value=>value.questionProgressAb?.runtime_q?.answeredAt===stamp);
    assert.deepEqual(projected,written.progress);
    const projectedUser=JSON.parse((await api('/__runtime_fixture/kv?key=user:'+userId,{fixture:true})).value);
    assert.equal(projectedUser.isPremium,true);
    assert.equal(projectedUser.premiumExpiresAt,premium.premiumExpiresAt);
    t.diagnostic('Unicode progress >128KiB and Premium survive process death before repair; automatically dispatched alarm converges KV and clears recovery wake-up; duplicate progress unchanged');

    const oldInstance=await api('/__runtime_fixture/instance',{fixture:true});
    await api('/__runtime_fixture/memory-fault',{fixture:true,body:{},expected:503});
    await api('/__runtime_fixture/memory-write-fault',{fixture:true,body:{},expected:503});
    const newInstance=await api('/__runtime_fixture/instance',{fixture:true});
    assert.notEqual(newInstance.instance,oldInstance.instance,'native SQLite failure must evict the volatile account instance');
    assert.deepEqual((await api('/api/user/progress?userId='+userId,{token})).progress,written.progress);
    const afterMemoryFault=await api('/api/user/status',{token});
    assert.equal(afterMemoryFault.premiumExpiresAt,premium.premiumExpiresAt);
    assert.equal(afterMemoryFault.isPremium,true);
    t.diagnostic('real SQLite allocation error resets only the running instance; confirmed progress and Premium survive');

    const pressure=await api('/__runtime_fixture/pressure',{fixture:true});
    assert.deepEqual(pressure,{pendingBefore:61,pendingAfter:0,progressUnchanged:true});
    const usage={installId:'a'.repeat(32),platform:'ios',events:Array.from({length:50},(_,i)=>({id:i.toString(16).padStart(32,'0'),feature:'tickets',ts:Date.now()}))};
    await api('/api/usage',{body:usage});
    await api('/api/usage',{body:usage});
    assert.equal((await api('/__runtime_fixture/flush-stats',{fixture:true})).status,200);
    const day=new Date(Date.now()+3*3600000).toISOString().slice(0,10);
    const counters=JSON.parse((await api('/__runtime_fixture/kv?key=day:'+day,{fixture:true})).value);
    assert.equal(counters.usage.tickets.starts,50);
    t.diagnostic('real SQLite paginated 61 expirations and bounded projections; 50 usage events deduplicated atomically');

    const client = 'runtime-empty-support';
    const statePath = '/__runtime_fixture/support-state?clientId=' + client;
    assert.equal((await api(statePath, { fixture: true })).initialized, false);
    assert.deepEqual((await api('/api/support/messages?clientId=' + client)).messages, []);
    assert.equal((await api(statePath, { fixture: true })).initialized, true);
    await api('/__runtime_fixture/kv?key=support:messages:' + client, { fixture: true,
      body: [{ id: 'late-stale-kv', ts: stamp, text: 'Must never be re-imported' }] });
    assert.deepEqual((await api('/api/support/messages?clientId=' + client)).messages, []);
    t.diagnostic('empty support poll initialized DO once; subsequent stale KV was not imported');

    await stop();
    await start();
    assert.equal((await api('/api/user/status', { token })).user.id, userId);
    assert.deepEqual((await api('/api/user/progress?userId=' + userId, { token })).progress, written.progress);
    assert.equal((await api(statePath, { fixture: true })).initialized, true);
    assert.deepEqual((await api('/api/support/messages?clientId=' + client)).messages, []);
    t.diagnostic('process restart preserved profile, large Unicode progress and support initialization');

    assert.equal((await api('/api/auth/logout', { token, body: {} })).ok, true);
    await api('/api/user/status', { token, expected: 401 });
    assert.equal((await api('/api/user/status', { token: anotherToken })).user.id, userId);
    await stop();
    await start();
    await api('/api/user/status', { token, expected: 401 });
    assert.equal((await api('/api/user/status', { token: anotherToken })).user.id, userId);
    t.diagnostic('logout revokes only the selected signed session, including after process restart');

    const deletion = await api('/api/user/delete', { token: anotherToken, body: { userId } });
    assert.equal(deletion.deleted, userId);
    await api('/api/user/status', { token: anotherToken, expected: 401 });
    await drainRepair();
    assert.equal((await api('/__runtime_fixture/kv?key=user:' + userId, { fixture: true })).value, null);
    assert.equal((await api('/__runtime_fixture/kv?key=user_progress:' + userId, { fixture: true })).value, null);
    await stop();
    await start();
    await api('/api/user/status', { token: anotherToken, expected: 401 });
    await api('/api/user/status', { token, expected: 401 });
    t.diagnostic('account deletion removed profile/progress and invalidated prior sessions across restart');
  } finally {
    await stop();
    t.diagnostic(`isolated fixture and runtime logs: ${directory}`);
  }
});
