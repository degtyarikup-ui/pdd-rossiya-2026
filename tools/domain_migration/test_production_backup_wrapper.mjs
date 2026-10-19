import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { BACKUP_CLASS_NAMES, buildBackupWrapper, buildBrokerWorker } from './production_backup_wrapper.mjs';
import { BACKUP_PATH, backupHmac, canonicalStringify, decodeValue } from '../../server/install-notifier/durable_backup.js';
import { BackupMemoryStorage } from '../../server/install-notifier/closed-backup-fixtures.mjs';
import { createExportCredentials, exportClosedObject } from './secure_export.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const credentials = createExportCredentials(), runId = randomUUID();
const namespaceIds = Object.fromEntries(BACKUP_CLASS_NAMES.map((name, index) => [name, (index + 1).toString(16).padStart(32, '0')]));
const objectId = 'f'.repeat(64), sourceVersion = 'synthetic-original-byte-baseline', accountEpoch = '1';
let temporary, wrapped, broker;
const baseEnv = () => ({ DURABLE_BACKUP_ENABLED: 'true', DURABLE_BACKUP_UNTIL: new Date(Date.now() + 1800000).toISOString(),
  DURABLE_BACKUP_HMAC_SECRET: credentials.hmacSecret, DURABLE_BACKUP_NAMESPACE_IDS: JSON.stringify(namespaceIds),
  DURABLE_BACKUP_SOURCE_VERSION: sourceVersion, ACCOUNT_STATE_EPOCH: accountEpoch, DURABLE_BACKUP_RUN_ID: runId });
const stateFor = async () => {
  const storage = new BackupMemoryStorage(); await storage.put('fixture', { text: 'Прогресс Әлібек', optional: undefined });
  return { storage, id: { toString: () => objectId }, businessCalls: 0, exportStarted: false };
};

before(async () => {
  await mkdir(join(root, 'output'), { recursive: true, mode: 0o700 });
  temporary = await mkdtemp(join(root, 'output', 'production-backup-wrapper-test-'));
  const original = `export const unchanged = 'preserved named export';
export default { async fetch(request) { return new Response('original:' + new URL(request.url).pathname); } };
class Base {
 constructor(state, env) { this.state = state; this.env = env; this.tail = Promise.resolve(); }
 serial(fn) { const result = this.tail.then(fn); this.tail = result.catch(() => {}); return result; }
 fetch(request) { return this.serial(async () => { this.state.businessCalls++;
   if (this.state.gate) await this.state.gate;
   return new Response('business:' + new URL(request.url).pathname);
 }); }
}
${BACKUP_CLASS_NAMES.map(name => `export class ${name} extends Base {}`).join('\n')}`;
  const helper = `export * from ${JSON.stringify(new URL('../../server/install-notifier/durable_backup.js', import.meta.url).href)};`;
  for (const [name, contents] of Object.entries({
    'original.mjs': original, 'durable_backup_bundle.mjs': helper,
    'wrapper.mjs': buildBackupWrapper({ originalMain: 'original.mjs' }),
    'broker.mjs': buildBrokerWorker(),
  })) await writeFile(join(temporary, name), contents, { mode: 0o600 });
  wrapped = await import(pathToFileURL(join(temporary, 'wrapper.mjs')).href);
  broker = (await import(pathToFileURL(join(temporary, 'broker.mjs')).href)).default;
});
after(async () => { if (temporary) await rm(temporary, { recursive: true, force: true }); });

function brokerEnv(object, env, onRoute = () => {}) {
  return { ...env, ...Object.fromEntries(BACKUP_CLASS_NAMES.map(name => ['BACKUP_' + name, {
    idFromString(id) { onRoute(); assert.equal(id, objectId); return id; },
    get(id) { assert.equal(id, objectId); return { fetch: request => object.fetch(request) }; },
  }])) };
}
async function signedRequest(patch = {}, signingSecret = credentials.hmacSecret) {
  const raw = canonicalStringify({ format: 1, runId, className: 'AccountState', namespaceId: namespaceIds.AccountState,
    objectId, sourceVersion, accountEpoch, issuedAt: Date.now(), nonce: 'a'.repeat(32), recipientJwk: { kty: 'RSA' }, ...patch });
  return new Request('https://broker.example.invalid' + BACKUP_PATH, { method: 'POST', headers: {
    'content-type': 'application/json', 'x-backup-signature': await backupHmac(signingSecret, 'POST\n' + BACKUP_PATH + '\n' + raw),
  }, body: raw });
}

test('builders accept only safe local module names and all nine distinct known classes/bindings', () => {
  assert.match(buildBackupWrapper({ originalMain: 'worker.js' }), /export \{ default \}/);
  for (const originalMain of ['../worker.js', '/worker.js', 'https://host/main.mjs', 'worker.js?x', 'a//worker.js', "a'; throw 1;.js"])
    assert.throws(() => buildBackupWrapper({ originalMain }));
  assert.throws(() => buildBackupWrapper({ originalMain: 'worker.js', classes: ['AccountState'] }));
  assert.throws(() => buildBackupWrapper({ originalMain: 'worker.js', helperModule: 'worker.js' }));
  assert.throws(() => buildBrokerWorker({ bindings: { AccountState: 'X' } }));
  assert.throws(() => buildBrokerWorker({ bindings: Object.fromEntries(BACKUP_CLASS_NAMES.map(name => [name, 'X'])) }));
});

test('wrapper preserves original default/named exports and ordinary fetches for all nine classes', async () => {
  assert.equal(wrapped.unchanged, 'preserved named export');
  assert.equal(await (await wrapped.default.fetch(new Request('https://fixture.invalid/app/'))).text(), 'original:/app/');
  for (const name of BACKUP_CLASS_NAMES) {
    const state = await stateFor(), object = new wrapped[name](state, baseEnv());
    assert.equal(await (await object.fetch(new Request('https://fixture.invalid/ordinary'))).text(), 'business:/ordinary');
    assert.equal(state.businessCalls, 1);
    const before = [...state.storage.data];
    const denied = await object.fetch(new Request('https://fixture.invalid/_backup/unknown'));
    assert.equal(denied.status, 404); assert.equal(state.businessCalls, 1);
    assert.deepEqual([...state.storage.data], before);
  }
});

test('signed broker export round trip reads raw state without invoking business code for every class', async () => {
  for (const className of BACKUP_CLASS_NAMES) {
    const state = await stateFor(), env = baseEnv(), object = new wrapped[className](state, env), before = [...state.storage.data];
    let routes = 0;
    const snapshot = await exportClosedObject({ endpoint: 'http://127.0.0.1:1234' + BACKUP_PATH,
      object: { className, namespaceId: namespaceIds[className], objectId }, runId, sourceVersion, accountEpoch, credentials,
      fetchImpl: (url, options) => broker.fetch(new Request(url, options), brokerEnv(object, env, () => routes++)),
    });
    assert.equal(routes, 1); assert.equal(state.businessCalls, 0);
    assert.equal(snapshot.metadata.className, className);
    assert.deepEqual(snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]), before);
    assert.deepEqual([...state.storage.data], before);
  }
});

test('wrapper backup joins the original serial queue', async () => {
  const state = await stateFor(), env = baseEnv();
  let release;
  state.gate = new Promise(resolve => { release = resolve; });
  const object = new wrapped.AccountState(state, env);
  const business = object.fetch(new Request('https://fixture.invalid/ordinary'));
  await Promise.resolve(); assert.equal(state.businessCalls, 1);
  let exportComplete = false;
  const snapshot = exportClosedObject({ endpoint: 'http://127.0.0.1:1234' + BACKUP_PATH,
    object: { className: 'AccountState', namespaceId: namespaceIds.AccountState, objectId }, runId, sourceVersion, accountEpoch, credentials,
    fetchImpl: (url, options) => broker.fetch(new Request(url, options), brokerEnv(object, env)),
  }).then(value => { exportComplete = true; return value; });
  await new Promise(resolve => setTimeout(resolve, 20)); assert.equal(exportComplete, false);
  release(); await business; assert.equal((await snapshot).entryCount, 1); assert.equal(state.businessCalls, 1);
});

test('broker rejects unauthorized, stale, wrong run/source/epoch/namespace requests before contacting DO', async () => {
  const state = await stateFor(), env = baseEnv(), object = new wrapped.AccountState(state, env);
  let routes = 0;
  const bound = brokerEnv(object, env, () => routes++);
  for (const patch of [{ runId: randomUUID() }, { sourceVersion: 'wrong' }, { accountEpoch: '2' },
    { namespaceId: '0'.repeat(32) }, { objectId: 'short' }, { className: '__proto__' },
    { issuedAt: Date.now() - 120000 }, { nonce: 'tiny' }]) {
    const response = await broker.fetch(await signedRequest(patch), bound);
    assert.equal(response.status, 404); assert.deepEqual(await response.json(), { error: 'Backup unavailable' });
  }
  const unauthorized = await signedRequest(); unauthorized.headers.set('x-backup-signature', 'a'.repeat(43));
  assert.equal((await broker.fetch(unauthorized, bound)).status, 404);
  assert.equal((await broker.fetch(new Request('https://fixture.invalid/any'), bound)).status, 404);
  assert.equal((await broker.fetch(await signedRequest(), { ...bound, DURABLE_BACKUP_ENABLED: 'false' })).status, 404);
  assert.equal((await broker.fetch(await signedRequest(), { ...bound, DURABLE_BACKUP_UNTIL: new Date(Date.now() - 1).toISOString() })).status, 404);
  assert.equal(routes, 0); assert.equal(state.businessCalls, 0);
});

test('broker rejects oversized body and refuses nonencrypted/upstream redirects', async () => {
  const env = baseEnv(); let routes = 0;
  const oversized = new Request('https://fixture.invalid' + BACKUP_PATH, { method: 'POST', body: 'x'.repeat(17000) });
  assert.equal((await broker.fetch(oversized, env)).status, 404);
  const fake = { fetch: () => new Response('must not pass', { status: 302, headers: { location: 'https://example.invalid' } }) };
  assert.equal((await broker.fetch(await signedRequest(), brokerEnv(fake, env, () => routes++))).status, 404);
  fake.fetch = () => Response.json({ unexpected: 'plaintext' });
  assert.equal((await broker.fetch(await signedRequest(), brokerEnv(fake, env, () => routes++))).status, 404);
  assert.equal(routes, 2);
});
