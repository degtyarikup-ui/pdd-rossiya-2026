// Optional proof against a privately downloaded live baseline. The baseline is
// never committed, modified in place, logged or deployed by this test.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { resolve, join, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { BACKUP_CLASS_NAMES, buildBackupWrapper } from './production_backup_wrapper.mjs';
import { encodeValue, decodeValue, BACKUP_PATH } from '../../server/install-notifier/durable_backup.js';
import { createExportCredentials, exportClosedObject } from './secure_export.mjs';

const baseline = process.env.PDD_BACKUP_BASELINE_DIR, runtimeRoot = process.env.PDD_MINIFLARE_MODULE_ROOT;
if (!baseline || !isAbsolute(baseline) || !runtimeRoot || !isAbsolute(runtimeRoot))
  throw new Error('Provide absolute PDD_BACKUP_BASELINE_DIR and PDD_MINIFLARE_MODULE_ROOT for the private baseline proof.');
const requireRuntime = createRequire(join(runtimeRoot, '__pdd_baseline_runtime__.cjs'));
const { Miniflare, convertV4MiniflareOptions } = requireRuntime('miniflare');
const { build } = requireRuntime('esbuild');
const root = fileURLToPath(new URL('../../', import.meta.url));
const credentials = createExportCredentials(), runId = randomUUID();
const namespaceIds = Object.fromEntries(BACKUP_CLASS_NAMES.map((name, index) => [name, (index + 1).toString(16).padStart(32, '0')]));
const sourceVersion = 'synthetic-local-private-baseline-proof', accountEpoch = '1';
let mf, output, endpoint, outboundAttempts = 0, sourceBytes;
const expected = new Map();
function fixtureSource(main) {
  return `import * as Source from './${main}';
import { encodeValue, decodeValue } from './durable_backup_bundle.mjs';
function instrument(Base) { return class extends Base {
 constructor(state, env) { super(state, env); this.fixtureState = state; }
 async fetch(request) {
  const path = new URL(request.url).pathname;
  if (path === '/__fixture/seed') {
   if ((await this.fixtureState.storage.list({ limit: 1 })).size) throw new Error('Fresh fixture required');
   const entries = await request.json();
   await this.fixtureState.storage.transaction(async txn => { for (const { key, value } of entries) await txn.put(key, decodeValue(value)); });
   return Response.json({ seeded: true });
  }
  if (path === '/__fixture/inspect') return Response.json({ alarm: await this.fixtureState.storage.getAlarm(),
   sqliteProof: [...this.fixtureState.storage.sql.exec('SELECT 1 AS proof')][0].proof,
   entries: [...await this.fixtureState.storage.list()].map(([key, value]) => ({ key, value: encodeValue(value) })) });
  return super.fetch(request);
 }
}; }
${BACKUP_CLASS_NAMES.map(name => `export const ${name} = instrument(Source.${name});`).join('\n')}
export default Source.default;
`;
}
async function namespaceObject(className, workerName) {
  const namespace = await mf.getDurableObjectNamespace(className, workerName);
  const id = namespace.idFromName('synthetic-private-baseline-' + className);
  return { stub: namespace.get(id), object: { className, namespaceId: namespaceIds[className], objectId: id.toString() } };
}
async function inspect(stub) {
  const response = await stub.fetch('https://fixture.invalid/__fixture/inspect'); assert.equal(response.status, 200); return response.json();
}

before(async () => {
  sourceBytes = await readFile(join(baseline, 'module-worker.js'));
  await mkdir(join(root, 'output'), { recursive: true, mode: 0o700 });
  output = await mkdtemp(join(root, 'output', 'private-baseline-wrapper-proof-'));
  const helper = await build({ entryPoints: [join(root, 'server/install-notifier/durable_backup.js')], bundle: true, write: false,
    format: 'esm', platform: 'browser', target: 'es2022', minify: true, legalComments: 'none' });
  for (const [name, contents] of Object.entries({
    'worker.js': sourceBytes, 'durable_backup_bundle.mjs': helper.outputFiles[0].text,
    'backup_entry.mjs': buildBackupWrapper({ originalMain: 'worker.js' }),
    'original_fixture.mjs': fixtureSource('worker.js'), 'wrapped_fixture.mjs': fixtureSource('backup_entry.mjs'),
  })) await writeFile(join(output, name), contents, { mode: 0o600 });
  const scripts = {};
  for (const kind of ['original', 'wrapped']) {
    const bundled = await build({ entryPoints: [join(output, kind + '_fixture.mjs')], bundle: true, write: false,
      format: 'esm', platform: 'browser', target: 'es2022', minify: true, legalComments: 'none' });
    scripts[kind] = bundled.outputFiles[0].text;
  }
  const durableObjects = Object.fromEntries(BACKUP_CLASS_NAMES.map(className => [className, { className, useSQLite: true }]));
  const bindings = { DURABLE_BACKUP_ENABLED: 'true', DURABLE_BACKUP_UNTIL: new Date(Date.now() + 1800000).toISOString(),
    DURABLE_BACKUP_HMAC_SECRET: credentials.hmacSecret, DURABLE_BACKUP_NAMESPACE_IDS: JSON.stringify(namespaceIds),
    DURABLE_BACKUP_SOURCE_VERSION: sourceVersion, ACCOUNT_STATE_EPOCH: accountEpoch };
  const common = { modules: true, compatibilityDate: '2024-11-01', durableObjects,
    outboundService: () => { outboundAttempts++; return new Response('External network forbidden', { status: 502 }); } };
  const options = { host: '127.0.0.1', port: 0, inspectorHost: '127.0.0.1', cf: false,
    telemetry: { enabled: false }, resourcePersistencePath: join(output, 'sqlite'), unsafeLocalExplorer: false,
    workers: [
      { ...common, name: 'baseline-original', script: scripts.original },
      { ...common, name: 'baseline-wrapped', script: scripts.wrapped, bindings },
      { ...common, name: 'baseline-disabled', script: scripts.wrapped, bindings: { ...bindings, DURABLE_BACKUP_ENABLED: 'false' } },
    ] };
  mf = new Miniflare(convertV4MiniflareOptions ? convertV4MiniflareOptions(options) : options);
  const url = await mf.ready; assert.equal(url.hostname, '127.0.0.1'); endpoint = new URL(BACKUP_PATH, url).href;
  for (const className of BACKUP_CLASS_NAMES) {
    const raw = [['fixture:raw', { text: 'Синтетический прогресс қазақша 🚦', optional: undefined }],
      ...Array.from({ length: 260 }, (_, index) => ['fixture:page:' + String(index).padStart(4, '0'), index])];
    if (className === 'AccountState') raw.push(['account-id', 'google_synthetic_private_baseline'],
      ['doc:user:google_synthetic_private_baseline', { key: 'user:google_synthetic_private_baseline', value: '{"id":"google_synthetic_private_baseline"}', options: {}, epoch: '1' }]);
    const entries = raw.sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b))).map(([key, value]) => ({ key, value: encodeValue(value) }));
    expected.set(className, entries);
    for (const workerName of ['baseline-wrapped', 'baseline-disabled']) {
      const { stub } = await namespaceObject(className, workerName);
      assert.equal((await stub.fetch('https://fixture.invalid/__fixture/seed', { method: 'POST', body: JSON.stringify(entries) })).status, 200);
    }
  }
});
after(async () => { if (mf) await mf.dispose(); if (output) await rm(output, { recursive: true, force: true }); });

test('private live bundle adapter preserves ordinary payment/status HTTP responses and forbids external network', async () => {
  const original = await mf.getWorker('baseline-original'), wrapped = await mf.getWorker('baseline-wrapped');
  for (const [path, method] of [['/api/user/pay-check', 'POST'], ['/api/user/pay-status', 'GET'], ['/api/config', 'GET']]) {
    const input = 'https://pdd-drive.ru' + path, init = { method, headers: { origin: 'https://pdd-drive.ru', 'content-type': 'application/json' }, ...(method === 'POST' ? { body: '{}' } : {}) };
    const first = await original.fetch(input, init), second = await wrapped.fetch(input, init);
    assert.equal(second.status, first.status);
    assert.deepEqual([...second.headers], [...first.headers]);
    assert.equal(await second.text(), await first.text());
  }
  assert.equal(outboundAttempts, 0);
  assert.deepEqual(await readFile(join(baseline, 'module-worker.js')), sourceBytes);
});

test('private live bundle wrapper exports every class with SQLite pagination and leaves raw source unchanged', async () => {
  const wrappedWorker = await mf.getWorker('baseline-wrapped');
  for (const className of BACKUP_CLASS_NAMES) {
    const { stub, object } = await namespaceObject(className, 'baseline-wrapped'), before = await inspect(stub);
    const snapshot = await exportClosedObject({ endpoint, object, runId, sourceVersion, accountEpoch, credentials,
      fetchImpl: async (_url, options) => stub.fetch('https://durable-backup.internal' + BACKUP_PATH, options) });
    assert.equal(before.sqliteProof, 1); assert.ok(snapshot.entryCount > 256);
    assert.deepEqual(snapshot.entries, expected.get(className));
    assert.deepEqual(snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]), before.entries.map(({ key, value }) => [key, decodeValue(value)]));
    assert.deepEqual(await inspect(stub), before);
    const { stub: disabled } = await namespaceObject(className, 'baseline-disabled'), disabledBefore = await inspect(disabled);
    const response = await disabled.fetch('https://durable-backup.internal' + BACKUP_PATH, { method: 'POST', body: '{}' });
    assert.equal(response.status, 404); assert.deepEqual(await inspect(disabled), disabledBefore);
  }
  // The original public Worker router is unchanged and never forwards export.
  const response = await wrappedWorker.fetch('https://pdd-drive.ru' + BACKUP_PATH, { method: 'POST', body: '{}' });
  assert.notEqual(response.headers.get('content-type'), 'application/jose');
  assert.equal(outboundAttempts, 0);
});
