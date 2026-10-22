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

test('real workerd persists accounts, immediate progress, revocation and support initialization', {
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
  // Fixture-only routes expose initialization and KV projection for assertions.
  await writeFile(entry, `import app from ${JSON.stringify(worker)};
export { ${classes.join(', ')} } from ${JSON.stringify(worker)};
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/__runtime_fixture/')) {
      if (request.headers.get('x-runtime-fixture') !== env.SHARED_SECRET) return new Response(null, {status: 404});
      if (url.pathname === '/__runtime_fixture/support-state') {
        return env.SUPPORT.get(env.SUPPORT.idFromName(url.searchParams.get('clientId'))).fetch('https://support.internal/list');
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
    const profile = await api('/api/user/sync', { token, body: { id: userId,
      platform: 'android', appVersion: 'runtime-smoke', app: 'ru' } });
    assert.equal(profile.user.id, userId);
    assert.equal(profile.isPremium, false);
    assert.equal((await api('/api/user/status', { token })).user.id, userId);
    assert.ok((await api('/__runtime_fixture/kv?key=user:' + userId, { fixture: true })).value);
    await api('/api/user/progress?userId=google_somebody_else', { token, expected: 403 });
    t.diagnostic('profile created; immediate status and KV projection; cross-account access denied');

    const stamp = Date.now();
    const progress = { questionProgressAb: { runtime_q: { answeredAt: stamp, correct: true, attemptsCount: 1 } },
      favoritesAb: ['runtime_q'], settings: { unicodeFixture: 'Проверка🚗'.repeat(14000) } };
    assert.ok(Buffer.byteLength(JSON.stringify(progress)) > 128 * 1024);
    const snapshot = { userId, progress, appVersion: 'runtime-smoke', platform: 'android' };
    const written = await api('/api/user/progress/sync', { token, body: snapshot });
    assert.equal(written.progress.questionProgressAb.runtime_q.correct, true);
    const duplicate = await api('/api/user/progress/sync', { token, body: snapshot });
    assert.equal(duplicate.serverUpdatedAt, written.serverUpdatedAt);
    const read = await api('/api/user/progress?userId=' + userId, { token });
    assert.deepEqual(read.progress, written.progress);
    const projected = await api('/__runtime_fixture/kv?key=user_progress:' + userId, { fixture: true });
    assert.deepEqual(JSON.parse(projected.value), written.progress);
    t.diagnostic('Unicode progress >128KiB committed, read immediately, projected to KV and duplicate unchanged');

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
