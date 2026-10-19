// Actual local workerd + SQLite proof. No production config is read and no
// network destination is permitted. Runtime packages are explicitly supplied
// by the operator instead of modifying this repository's dependencies.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, join, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { encodeValue, decodeValue, BACKUP_PATH, BACKUP_LIMITS, validateSnapshot } from '../../server/install-notifier/durable_backup.js';
import { BACKUP_CLASSES, createExportCredentials, exportClosedObject, collectClosedBundle, encryptClosedBundle, decryptClosedBundle } from './secure_export.mjs';
import { createClosedTarget, restoreClosedBundle, inspectClosedTarget, readClosedObject } from './closed_restore.mjs';

const runtimeRoot = process.env.PDD_MINIFLARE_MODULE_ROOT;
if (!runtimeRoot || !isAbsolute(runtimeRoot)) throw new Error('Provide an absolute runtime package directory: PDD_MINIFLARE_MODULE_ROOT=/path/to/node_modules node --test tools/domain_migration/test_backup_runtime.mjs');
const requireRuntime = createRequire(join(runtimeRoot, '__pdd_test_runtime__.cjs'));
const { Miniflare, convertV4MiniflareOptions } = requireRuntime('miniflare');
const { build } = requireRuntime('esbuild');
const root = fileURLToPath(new URL('../../', import.meta.url));
const output = join(root, 'output', 'domain-migration', 'runtime-sqlite-' + randomUUID());
const credentials = createExportCredentials();
const sourceVersion = 'synthetic-workerd-runtime-v1', accountEpoch = '1';
const namespaceIds = Object.fromEntries(BACKUP_CLASSES.map((name, i) => [name, (i + 1).toString(16).padStart(32, '0')]));
const alarm = Date.now() + 86400000;
const expectedAlarm = className => ['PurchaseClaims', 'SupportThread', 'TelegramAuthState'].includes(className) ? null : alarm;
let mf, endpoint, outboundAttempts = 0;
const objects = new Map(), seeded = new Map();

function rawEntries(className) {
  const entries = Array.from({ length: 300 }, (_, index) => ['fixture:' + index.toString().padStart(4, '0'), { index, optional: undefined, text: 'Қазақша русский 😀' }]);
  entries.push(['version:a', 0], ['version:b', 0]);
  // A small native dense array expands beyond 1 MiB when each index/value is
  // explicitly tagged. This is synthetic and fits the SQLite value budget.
  if (className === 'TrafficState') entries.push(['fixture:dense-array', Array.from({ length: 45000 }, (_, index) => index % 10)]);
  if (className === 'AccountState') {
    const id = 'google_synthetic_runtime';
    entries.push(['account-id', id]);
    entries.push(['doc:user:' + id, { key: 'user:' + id, value: JSON.stringify({ id, entitlements: { web: { expiresAt: '2030-01-01T00:00:00.000Z' } } }), options: {}, expiresAt: undefined, epoch: accountEpoch }]);
    const key = 'user_progress:' + id, bytes = Buffer.from(JSON.stringify({ progress: 'Қазақша русский 😀 '.repeat(5000) }));
    const chunks = Math.ceil(bytes.length / 49152);
    entries.push(['doc:' + key, { key, chunks, options: {}, expiresAt: undefined, epoch: accountEpoch }]);
    for (let index = 0; index < chunks; index++) entries.push(['chunk:' + key + ':' + index, bytes.subarray(index * 49152, (index + 1) * 49152).toString('base64')]);
    entries.push(['doc:payment_ledger:fixture', { key: 'payment_ledger:fixture', value: '{"orderId":"synthetic","amount":99}', options: {}, epoch: accountEpoch }]);
    entries.push(['effect:synthetic', { type: 'synthetic', retained: true }], ['projection:synthetic', { key: 'synthetic' }], ['index:synthetic', { orderId: 'synthetic', userId: id }]);
  }
  return entries.sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b))).map(([key, value]) => ({ key, value: encodeValue(value) }));
}
async function stubFor(className, workerName = 'closed-enabled') {
  const namespace = await mf.getDurableObjectNamespace(className, workerName);
  const id = namespace.idFromName('synthetic-runtime-' + className);
  return { stub: namespace.get(id), object: { className, namespaceId: namespaceIds[className], objectId: id.toString() } };
}
async function inspect(stub) {
  const response = await stub.fetch('https://fixture.internal/__fixture/inspect');
  assert.equal(response.status, 200); return response.json();
}

before(async () => {
  await mkdir(output, { recursive: true, mode: 0o700 });
  const bundled = await build({ entryPoints: [join(root, 'tools/domain_migration/backup_runtime_fixture.mjs')], bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022', minify: true, legalComments: 'none' });
  const script = bundled.outputFiles[0].text;
  const durableObjects = Object.fromEntries(BACKUP_CLASSES.map(className => [className, { className, useSQLite: true }]));
  const outboundService = () => { outboundAttempts++; return new Response('Outbound disabled for closed rehearsal', { status: 502 }); };
  const common = { modules: true, script, compatibilityDate: '2024-11-01', durableObjects, outboundService,
    bindings: { DURABLE_BACKUP_UNTIL: new Date(Date.now() + 1800000).toISOString(), DURABLE_BACKUP_HMAC_SECRET: credentials.hmacSecret,
      DURABLE_BACKUP_NAMESPACE_IDS: JSON.stringify(namespaceIds), DURABLE_BACKUP_SOURCE_VERSION: sourceVersion, ACCOUNT_STATE_EPOCH: accountEpoch } };
  const options = { host: '127.0.0.1', port: 0, inspectorHost: '127.0.0.1', cf: false,
    telemetry: { enabled: false }, resourcePersistencePath: join(output, 'storage'), unsafeLocalExplorer: false,
    workers: [{ ...common, name: 'closed-enabled', bindings: { ...common.bindings, DURABLE_BACKUP_ENABLED: 'true' } },
      { ...common, name: 'closed-disabled' },
      { ...common, name: 'closed-restored', bindings: { ...common.bindings, FIXTURE_RESTORE_ONLY: 'true' } }] };
  mf = new Miniflare(convertV4MiniflareOptions ? convertV4MiniflareOptions(options) : options);
  const url = await mf.ready;
  assert.equal(url.hostname, '127.0.0.1');
  endpoint = new URL(BACKUP_PATH, url).href;
  for (const className of BACKUP_CLASSES) {
    const entries = rawEntries(className); seeded.set(className, entries);
    for (const workerName of ['closed-enabled', 'closed-disabled']) {
      const { stub, object } = await stubFor(className, workerName);
      assert.equal((await stub.fetch('https://fixture.internal/__fixture/seed', { method: 'POST', body: JSON.stringify({ entries, alarm: expectedAlarm(className) }) })).status, 200);
      if (workerName === 'closed-enabled') objects.set(className, { stub, object });
    }
  }
});
after(async () => { if (mf) await mf.dispose(); });

test('real SQLite runtime keeps all nine default-off classes unchanged, with no egress', async () => {
  for (const className of BACKUP_CLASSES) {
    const { stub } = await stubFor(className, 'closed-disabled');
    const before = await inspect(stub);
    assert.equal(before.sqliteProof, 1);
    for (const path of [BACKUP_PATH, '/_backup/v9/unknown', '/_backup']) {
      const response = await stub.fetch('https://fixture.internal' + path, { method: 'POST', body: '{}' });
      assert.equal(response.status, 404, className + ' must fail closed');
      assert.deepEqual(await response.json(), { error: 'Backup unavailable' });
    }
    const after = await inspect(stub);
    assert.deepEqual(after, before);
    assert.deepEqual(after.entries, seeded.get(className));
  }
  assert.equal(outboundAttempts, 0);
});

test('real transaction pagination, alarm, HMAC/JWE round trip, encrypted archive and closed restore preserve all nine classes', async () => {
  const runId = randomUUID(), expectedObjects = [...objects.values()].map(({ object }) => object);
  const before = new Map();
  for (const [name, { stub }] of objects) before.set(name, await inspect(stub));
  const bundle = await collectClosedBundle({ endpoint, expectedObjects, runId, sourceVersion, accountEpoch, credentials });
  assert.equal(bundle.snapshots.length, 9);
  const encrypted = await encryptClosedBundle(bundle, credentials);
  assert.equal(encrypted.includes('google_synthetic_runtime'), false);
  const restoredBundle = await decryptClosedBundle(encrypted, credentials), target = createClosedTarget();
  await restoreClosedBundle(restoredBundle, target, { key: Buffer.from(credentials.hmacSecret, 'base64url') });
  const sqliteRestoredLabels = [];
  for (const [name, { stub, object }] of objects) {
    const snapshot = restoredBundle.snapshots.find(snapshot => snapshot.metadata.className === name);
    await validateSnapshot(snapshot);
    assert.equal(snapshot.metadata.alarm, expectedAlarm(name));
    assert.ok(snapshot.entryCount > BACKUP_LIMITS.pageSize * 2);
    assert.deepEqual(snapshot.entries, seeded.get(name));
    if (name === 'TrafficState') {
      const dense = snapshot.entries.find(entry => entry.key === 'fixture:dense-array');
      assert.ok(Buffer.byteLength(JSON.stringify(dense.value)) > 1024 * 1024);
      assert.ok(Buffer.byteLength(JSON.stringify(dense.value)) < BACKUP_LIMITS.maxValueBytes);
      assert.deepEqual(decodeValue(dense.value), Array.from({ length: 45000 }, (_, index) => index % 10));
    }
    const restored = readClosedObject(target, object);
    assert.deepEqual([...restored.entries], snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]));
    assert.equal(restored.scheduledAlarm, null);
    // Seed a fresh real SQLite object from the already validated evidence.
    // Its namespace/id are new local test identities, never a production
    // remapping. Keep original locators only as evidence labels.
    const { stub: restoredStub, object: restoredIdentity } = await stubFor(name, 'closed-restored');
    assert.notEqual(restoredIdentity.objectId, object.objectId);
    const seedResponse = await restoredStub.fetch('https://fixture.internal/__fixture/seed', {
      method: 'POST', body: JSON.stringify({ entries: snapshot.entries, alarm: null }),
    });
    assert.equal(seedResponse.status, 200);
    const actualRestored = await inspect(restoredStub);
    assert.equal(actualRestored.sqliteProof, 1);
    assert.equal(actualRestored.alarm, null);
    assert.deepEqual(actualRestored.entries, snapshot.entries);
    assert.equal((await restoredStub.fetch('https://fixture.internal/_account/read', { method: 'POST', body: '{}' })).status, 404);
    assert.equal((await restoredStub.fetch('https://fixture.internal/_backup/v1/export', { method: 'POST', body: '{}' })).status, 404);
    sqliteRestoredLabels.push({ sourceIdentity: object, localTestIdentity: { worker: 'closed-restored', className: name, objectId: restoredIdentity.objectId },
      originalIdIsLabelOnly: true, rawEntryCount: actualRestored.entries.length, scheduledAlarm: null });
    assert.deepEqual(await inspect(stub), before.get(name));
  }
  const inspected = inspectClosedTarget(target);
  assert.equal(inspected.length, 9); assert.ok(inspected.every(object => object.scheduledAlarm === null));
  assert.equal(outboundAttempts, 0);
  await writeFile(join(output, 'verification.json'), JSON.stringify({ syntheticOnly: true, runtime: 'Miniflare/workerd SQLite',
    classes: BACKUP_CLASSES, objectCount: 9, pagination: true, encryptedRoundTrip: true, restoreVerified: true,
    sourceUnchanged: true, archivedAlarms: true, restoredAlarmsScheduled: false, actualSqliteRestore: true, sqliteRestoredLabels, outboundAttempts,
    globalAtomic: false, inventoryComplete: false }, null, 2), { mode: 0o600 });
});

test('SQLite snapshot stays internally consistent while concurrent atomic updates are queued', async () => {
  const { stub, object } = objects.get('AccountState');
  const snapshots = [];
  const tasks = [];
  for (let version = 1; version <= 12; version++) {
    tasks.push(stub.fetch('https://fixture.internal/__fixture/mutate', { method: 'POST', body: JSON.stringify({ version }) }));
    tasks.push(exportClosedObject({ endpoint, object, runId: randomUUID(), sourceVersion, accountEpoch, credentials }).then(snapshot => snapshots.push(snapshot)));
  }
  await Promise.all(tasks);
  assert.equal(snapshots.length, 12);
  for (const snapshot of snapshots) {
    const values = new Map(snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]));
    assert.equal(values.get('version:a'), values.get('version:b'));
  }
  assert.equal(outboundAttempts, 0);
});

test('explicit egress probe is denied by the local runtime outbound service', async () => {
  const response = await fetch(new URL('/__fixture/egress', endpoint));
  assert.equal(response.status, 502); assert.equal(outboundAttempts, 1);
});
