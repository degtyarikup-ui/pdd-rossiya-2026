import test from 'node:test';
import assert from 'node:assert/strict';
import { access, mkdir, mkdtemp, readFile, readdir, rm, stat, symlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { handleBackupExport, BACKUP_PATH } from '../../server/install-notifier/durable_backup.js';
import { createExportCredentials, checkedLoopbackEndpoint, exportClosedObject, collectClosedBundle,
  encryptClosedBundle, decryptClosedBundle, writePrivateNew } from './secure_export.mjs';
import { createClosedTarget, restoreClosedBundle, readClosedObject, encodeClosedKVEntry, readClosedKV } from './closed_restore.mjs';

const credentials = createExportCredentials();
const endpoint = 'http://127.0.0.1:43819' + BACKUP_PATH;
const expectedObjects = ['AccountState', 'PurchaseClaims'].map((className, index) => ({ className,
  namespaceId: String(index + 1).repeat(32), objectId: String(index + 1).repeat(64) }));
const sourceVersion = 'synthetic-closed-build', accountEpoch = '1';
function fixture() {
  let requests = 0, writes = 0;
  const env = { DURABLE_BACKUP_ENABLED: 'true', DURABLE_BACKUP_HMAC_SECRET: credentials.hmacSecret,
    DURABLE_BACKUP_UNTIL: new Date(Date.now() + 1800000).toISOString(), DURABLE_BACKUP_SOURCE_VERSION: sourceVersion,
    DURABLE_BACKUP_NAMESPACE_IDS: JSON.stringify(Object.fromEntries(expectedObjects.map(o => [o.className, o.namespaceId]))),
    ACCOUNT_STATE_EPOCH: accountEpoch };
  const data = new Map([['account-id', 'google_synthetic_closed'], ['private-fixture', { token: 'SYNTHETIC-NEVER-REAL', absent: undefined }]]);
  const states = expectedObjects.map(object => {
    const storage = { async list() { return new Map(data); }, async getAlarm() { return 2000000000000; },
      async transaction(fn) { return fn(storage); }, async put() { writes++; throw new Error('Forbidden'); } };
    return { id: { toString: () => object.objectId }, storage };
  });
  async function fetchImpl(url, options) {
    assert.equal(url, endpoint); assert.equal(options.redirect, 'error');
    requests++;
    const body = JSON.parse(options.body), index = expectedObjects.findIndex(object => object.objectId === body.objectId);
    return handleBackupExport(new Request(url, options), { env, state: states[index], className: body.className });
  }
  return { fetchImpl, counts: () => ({ requests, writes }) };
}
test('closed collector authenticates expected objects and binary KV, encrypts all retained data, and restores without network', async () => {
  const f = fixture(), kvEntries = [encodeClosedKVEntry({ key: 'binary-fixture', value: Uint8Array.of(0, 255, 13, 10),
    expiration: 2000000000, metadata: { fixture: true } })];
  const bundle = await collectClosedBundle({ endpoint, expectedObjects, sourceVersion, accountEpoch, credentials, kvEntries, fetchImpl: f.fetchImpl });
  assert.equal(bundle.inventory.objectCount, 2);
  assert.deepEqual(bundle.inventory.provenance, { kind: 'synthetic-local', globalAtomic: false, inventoryComplete: false });
  const ciphertext = await encryptClosedBundle(bundle, credentials);
  assert.equal(ciphertext.split('.').length, 5);
  assert.equal(ciphertext.includes('SYNTHETIC-NEVER-REAL'), false);
  assert.equal(ciphertext.includes('google_synthetic_closed'), false);
  const recovered = await decryptClosedBundle(ciphertext, credentials), target = createClosedTarget();
  await restoreClosedBundle(recovered, target, { key: Buffer.from(credentials.hmacSecret, 'base64url') });
  assert.equal(readClosedObject(target, expectedObjects[0]).entries.get('private-fixture').token, 'SYNTHETIC-NEVER-REAL');
  assert.deepEqual(readClosedKV(target)[0].value, Uint8Array.of(0, 255, 13, 10));
  assert.deepEqual(f.counts(), { requests: 2, writes: 0 });
  await assert.rejects(decryptClosedBundle(ciphertext, createExportCredentials()));
  const parts = ciphertext.split('.'); parts[3] = (parts[3][0] === 'A' ? 'B' : 'A') + parts[3].slice(1);
  await assert.rejects(decryptClosedBundle(parts.join('.'), credentials));
});
test('collector refuses public, named, credential-bearing and unexpected URL targets before making a request', async () => {
  for (const url of ['https://pdd-drive.ru' + BACKUP_PATH, 'https://pdd-drive.app' + BACKUP_PATH,
    'http://localhost:1234' + BACKUP_PATH, 'http://127.0.0.1.evil.invalid' + BACKUP_PATH,
    'http://user:password@127.0.0.1' + BACKUP_PATH, endpoint + '?test=1', endpoint + '#test', 'file:///tmp/export']) {
    assert.throws(() => checkedLoopbackEndpoint(url));
    await assert.rejects(collectClosedBundle({ endpoint: url, expectedObjects, credentials, sourceVersion, accountEpoch,
      fetchImpl: () => { assert.fail('Must not fetch'); } }));
  }
  assert.equal(checkedLoopbackEndpoint('http://[::1]:1234' + BACKUP_PATH), 'http://[::1]:1234' + BACKUP_PATH);
});
test('collector rejects incomplete, duplicate and unknown inventories and never treats a partial collection as complete', async () => {
  const f = fixture();
  for (const objects of [[], [...expectedObjects, expectedObjects[0]], [{ ...expectedObjects[0], className: 'UnknownState' }]]) {
    await assert.rejects(collectClosedBundle({ endpoint, expectedObjects: objects, credentials, sourceVersion, accountEpoch, fetchImpl: f.fetchImpl }));
  }
  assert.deepEqual(f.counts(), { requests: 0, writes: 0 });
  await assert.rejects(collectClosedBundle({ endpoint, expectedObjects, credentials, sourceVersion, accountEpoch,
    fetchImpl: async (url, options) => JSON.parse(options.body).className === 'PurchaseClaims'
      ? new Response('Unavailable', { status: 404 }) : f.fetchImpl(url, options) }));
});
test('collector rejects unauthenticated or swapped encrypted responses and redirects', async () => {
  const f = fixture(), base = { endpoint, object: expectedObjects[0], runId: randomUUID(), sourceVersion, accountEpoch, credentials };
  await assert.rejects(exportClosedObject({ ...base, fetchImpl: async (url, options) => {
    const response = await f.fetchImpl(url, options);
    response.headers.delete('x-backup-response-signature'); return response;
  } }));
  await assert.rejects(exportClosedObject({ ...base, fetchImpl: async () => new Response('', { status: 302, headers: { location: 'https://pdd-drive.ru' } }) }));
  let previous;
  await exportClosedObject({ ...base, fetchImpl: async (url, options) => { previous = (await f.fetchImpl(url, options)).clone(); return previous.clone(); } });
  await assert.rejects(exportClosedObject({ ...base, fetchImpl: async () => previous.clone() }));
});
test('files are private and existing files or symlink targets cannot be overwritten', async () => {
  const parent = resolve('output/secure-export-tests'); await mkdir(parent, { recursive: true, mode: 0o700 });
  const dir = await mkdtemp(join(parent, 'closed-'));
  try {
    const file = join(dir, 'credentials.json'), link = join(dir, 'alias');
    await writePrivateNew(file, 'private fixture');
    assert.equal((await stat(file)).mode & 0o077, 0);
    await assert.rejects(writePrivateNew(file, 'overwrite'), { code: 'EEXIST' });
    await symlink(file, link);
    await assert.rejects(writePrivateNew(link, 'overwrite'), { code: 'EEXIST' });
    assert.equal(await readFile(file, 'utf8'), 'private fixture');
    const failed = join(dir, 'failed.key');
    await assert.rejects(writePrivateNew(failed, { invalid: 'simulate write failure' }));
    await assert.rejects(access(failed));
    assert.deepEqual((await readdir(dir)).sort(), ['alias', 'credentials.json']);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
