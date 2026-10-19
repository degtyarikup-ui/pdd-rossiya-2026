import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, readFile, readdir, rm, symlink, chmod } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createHash, createPrivateKey, createPublicKey, randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createExportCredentials } from './secure_export.mjs';
import { collectRealObjects, encryptRunEvidence, decryptRunEvidence } from './collect_real_objects.mjs';
import { API_BASE, makeUpload, readInventory } from './production_export_control.mjs';
import { backupHmac, canonicalStringify, snapshotStorage, verifyBackupHmac } from '../../server/install-notifier/durable_backup.js';
import { BackupMemoryStorage } from '../../server/install-notifier/closed-backup-fixtures.mjs';
const requireServer = createRequire(new URL('../../server/install-notifier/package.json', import.meta.url));
const { CompactEncrypt, importJWK } = await import(requireServer.resolve('jose'));
const root = fileURLToPath(new URL('../../', import.meta.url));
const credentials = createExportCredentials(), brokerName = 'pdd-account-export-1234abcd', accountSubdomain = 'synthetic-account';
const endpoint = `https://${brokerName}.${accountSubdomain}.workers.dev/_backup/v1/export`;
const runId = randomUUID(), sourceVersion = 'synthetic-source-version', accountEpoch = '1';
const object = { className: 'AccountState', namespaceId: 'a'.repeat(32), objectId: 'b'.repeat(64) };
const originalFetch = globalThis.fetch;
let temporary, snapshot, directory = 0;
const identity = value => [value.className, value.namespaceId, value.objectId].join(':');
const cacheFile = dir => join(dir, createHash('sha256').update(identity(object)).digest('hex') + '.pddjwe');
async function newDirectory() { const dir = join(temporary, String(++directory)); await mkdir(dir, { mode: 0o700 }); return dir; }
function plan(outputDir, patch = {}) { return { endpoint, brokerName, accountSubdomain, objects: [object], runId, sourceVersion, accountEpoch, credentials, outputDir, ...patch }; }
async function withFetch(fetchImpl, fn) {
  globalThis.fetch = fetchImpl;
  try { return await fn(); } finally { globalThis.fetch = originalFetch; }
}
function sequenceApi(pages) {
  const paths = [];
  return { paths, json: async (method, path) => {
    assert.equal(method, 'GET'); paths.push(path);
    assert.ok(path.startsWith(API_BASE + '/workers/durable_objects/namespaces/'));
    assert.ok(pages.length, 'unexpected extra inventory API request');
    return pages.shift();
  } };
}

before(async () => {
  await mkdir(join(root, 'output'), { recursive: true, mode: 0o700 });
  temporary = await mkdtemp(join(root, 'output', 'real-object-export-unit-'));
  const storage = new BackupMemoryStorage(); await storage.put('account-id', 'google_synthetic_export');
  await storage.put('doc:user:google_synthetic_export', { key: 'user:google_synthetic_export', value: '{"id":"google_synthetic_export"}', options: {}, epoch: accountEpoch });
  snapshot = await snapshotStorage({ storage, id: { toString: () => object.objectId } }, { ...object, runId, sourceVersion, accountEpoch });
});
after(async () => { globalThis.fetch = originalFetch; if (temporary) await rm(temporary, { recursive: true, force: true }); });

test('run evidence requires an authenticated envelope; encryption with the public key cannot forge evidence', async () => {
  const encrypted = await encryptRunEvidence(snapshot, credentials);
  assert.deepEqual(await decryptRunEvidence(encrypted, credentials), snapshot);
  const publicJwk = createPublicKey(createPrivateKey({ key: credentials.recipientPrivateJwk, format: 'jwk' })).export({ format: 'jwk' });
  const key = await importJWK(publicJwk, 'RSA-OAEP-256');
  for (const payload of [snapshot, { value: snapshot, signature: 'A'.repeat(43) }, { value: snapshot, signature: 'A'.repeat(43), extra: true }]) {
    const forged = await new CompactEncrypt(new TextEncoder().encode(canonicalStringify(payload)))
      .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-export-evidence+jwe' }).encrypt(key);
    await assert.rejects(decryptRunEvidence(forged, credentials));
  }
  await assert.rejects(decryptRunEvidence(encrypted, { ...credentials, hmacSecret: Buffer.alloc(32, 7).toString('base64url') }));
  await assert.rejects(decryptRunEvidence(await encryptRunEvidence(snapshot, credentials, 'other-evidence+jwe'), credentials));
});

test('collector pins the exact temporary HTTPS broker before any filesystem/network operation', async () => {
  let requests = 0;
  await withFetch(() => { requests++; throw new Error('Network must never be contacted'); }, async () => {
    for (const wrong of [endpoint.replace('https:', 'http:'), endpoint + '?x', endpoint + '#fragment',
      endpoint.replace('synthetic-account', 'other-account'), 'https://pdd-install-notifier.example.workers.dev/_backup/v1/export',
      endpoint.replace('https://', 'https://user@')]) await assert.rejects(collectRealObjects(plan(join(temporary, 'must-not-exist'), { endpoint: wrong })));
    await assert.rejects(collectRealObjects(plan(join(temporary, 'must-not-exist'), { brokerName: 'pdd-install-notifier' })));
    await assert.rejects(collectRealObjects(plan(join(temporary, 'must-not-exist'), { accountSubdomain: '../unsafe' })));
  });
  assert.equal(requests, 0);
});

test('cached snapshots must retain matching run, source, epoch, namespace and object identities', async () => {
  let requests = 0;
  await withFetch(() => { requests++; throw new Error('Cache rejection must not fallback to network'); }, async () => {
    const dir = await newDirectory(), file = cacheFile(dir);
    await writeFile(file, await encryptRunEvidence(snapshot, credentials), { mode: 0o600 });
    assert.deepEqual(await collectRealObjects(plan(dir)), [snapshot]);
    for (const patch of [{ runId: randomUUID() }, { sourceVersion: 'wrong-source' }, { accountEpoch: 'stale-epoch' }])
      await assert.rejects(collectRealObjects(plan(dir, patch)));
    const wrongIdentity = await snapshotStorage({ storage: new BackupMemoryStorage() }, {
      ...object, objectId: 'c'.repeat(64), runId, sourceVersion, accountEpoch,
    });
    await writeFile(file, await encryptRunEvidence(wrongIdentity, credentials), { mode: 0o600 });
    await assert.rejects(collectRealObjects(plan(dir)));
  });
  assert.equal(requests, 0);
});

test('corrupt, forged, nonprivate and symbolic-link cache files are refused without network fallback', async () => {
  let requests = 0;
  await withFetch(() => { requests++; throw new Error('Unsafe cache must not fallback to network'); }, async () => {
    const corruptedDir = await newDirectory();
    await writeFile(cacheFile(corruptedDir), 'truncated-ciphertext', { mode: 0o600 });
    await assert.rejects(collectRealObjects(plan(corruptedDir)));
    const forgedDir = await newDirectory();
    const publicJwk = createPublicKey(createPrivateKey({ key: credentials.recipientPrivateJwk, format: 'jwk' })).export({ format: 'jwk' });
    const forged = await new CompactEncrypt(new TextEncoder().encode(canonicalStringify({ value: snapshot, signature: 'A'.repeat(43) })))
      .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-export-evidence+jwe' }).encrypt(await importJWK(publicJwk, 'RSA-OAEP-256'));
    await writeFile(cacheFile(forgedDir), forged, { mode: 0o600 });
    await assert.rejects(collectRealObjects(plan(forgedDir)));
    const nonprivateDir = await newDirectory(); await writeFile(cacheFile(nonprivateDir), await encryptRunEvidence(snapshot, credentials), { mode: 0o600 });
    await chmod(cacheFile(nonprivateDir), 0o644); await assert.rejects(collectRealObjects(plan(nonprivateDir)));
    const linkDir = await newDirectory(), real = join(temporary, 'separate-private-evidence.pddjwe');
    await writeFile(real, await encryptRunEvidence(snapshot, credentials), { mode: 0o600 }); await symlink(real, cacheFile(linkDir));
    await assert.rejects(collectRealObjects(plan(linkDir)));
  });
  assert.equal(requests, 0);
});

test('real collector verifies request/response HMAC, retains only encrypted evidence and resumes without network', async () => {
  const dir = await newDirectory(); let requests = 0;
  const result = await withFetch(async (url, options) => {
    requests++; assert.equal(url, endpoint); assert.equal(options.redirect, 'error');
    assert.equal(options.method, 'POST');
    assert.equal(await verifyBackupHmac(credentials.hmacSecret, 'POST\n/_backup/v1/export\n' + options.body, options.headers['x-backup-signature']), true);
    const body = JSON.parse(options.body); assert.equal(body.recipientJwk.d, undefined);
    const encrypted = await new CompactEncrypt(new TextEncoder().encode(canonicalStringify(snapshot)))
      .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-durable-backup+jwe' }).encrypt(await importJWK(body.recipientJwk, 'RSA-OAEP-256'));
    const response = new Response(encrypted, { headers: { 'content-type': 'application/jose',
      'x-backup-response-signature': await backupHmac(credentials.hmacSecret, 'response\n' + body.nonce + '\n' + encrypted) } });
    Object.defineProperty(response, 'url', { value: endpoint }); return response;
  }, () => collectRealObjects(plan(dir)));
  assert.deepEqual(result, [snapshot]); assert.equal(requests, 1);
  const saved = await readFile(cacheFile(dir), 'utf8'); assert.equal(saved.includes('google_synthetic_export'), false);
  assert.deepEqual(await decryptRunEvidence(saved, credentials), snapshot);
  await withFetch(() => { throw new Error('A verified cache must not use network'); }, async () => assert.deepEqual(await collectRealObjects(plan(dir)), [snapshot]));
});

test('authenticated diagnostic stays encrypted, reports only allowed enums and cannot become a snapshot', async () => {
  const diagnostic = { format: 'pdd-durable-backup-diagnostic', schema: 1, reason: 'value_byte_limit',
    errorKind: 'Error', entryCount: 832, pageCount: 7, encodedBytes: 305758 };
  for (const payload of [diagnostic, { ...diagnostic, message: 'SYNTHETIC-PRIVATE-MUST-NOT-LOG' }]) {
    const dir = await newDirectory();
    await withFetch(async (_url, options) => {
      const body = JSON.parse(options.body);
      const ciphertext = await new CompactEncrypt(new TextEncoder().encode(canonicalStringify(payload)))
        .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-durable-backup-diagnostic+jwe' })
        .encrypt(await importJWK(body.recipientJwk, 'RSA-OAEP-256'));
      const response = new Response(ciphertext, { headers: { 'content-type': 'application/jose',
        'x-backup-response-signature': await backupHmac(credentials.hmacSecret, 'response\n' + body.nonce + '\n' + ciphertext) } });
      Object.defineProperty(response, 'url', { value: endpoint }); return response;
    }, async () => {
      await assert.rejects(collectRealObjects(plan(dir)), payload === diagnostic ? /Authenticated backup diagnostic: value_byte_limit/ : /Real object export failed/);
    });
    const files = await readdir(dir);
    if (payload === diagnostic) {
      assert.equal(files.length, 1); assert.ok(files[0].startsWith('diagnostic-'));
      const bytes = await readFile(join(dir, files[0]), 'utf8'); assert.equal(bytes.includes('value_byte_limit'), false);
      assert.deepEqual(await decryptRunEvidence(bytes, credentials), diagnostic);
    } else assert.deepEqual(files, []);
  }
});

test('upload retains opaque secrets, original configuration, module bytes and main entry', async () => {
  const settings = { bindings: [{ type: 'secret_text', name: 'SYNTHETIC_SECRET' }, { type: 'secret_key', name: 'SYNTHETIC_KEY' },
    { type: 'plain_text', name: 'FEATURE', text: 'unchanged' }, { type: 'kv_namespace', name: 'INSTALLS', namespace_id: 'a'.repeat(32) }],
    compatibility_date: '2024-11-01', compatibility_flags: ['some_flag'], usage_model: 'bundled', tags: ['tag'],
    tail_consumers: [{ service: 'tail' }], logpush: false, observability: { enabled: true }, placement: { mode: 'smart' }, limits: { cpu_ms: 50 } };
  const extraBindings = [{ type: 'plain_text', name: 'DURABLE_BACKUP_ENABLED', text: 'true' }];
  const bytes = Uint8Array.from([0, 255, 1, 2]);
  const form = makeUpload({ modules: [{ name: 'worker.js', type: 'application/javascript+module', bytes }], mainModule: 'worker.js', settings, extraBindings });
  const metadata = JSON.parse(form.get('metadata'));
  assert.deepEqual(metadata.keep_bindings, ['secret_text', 'secret_key']);
  assert.deepEqual(metadata.bindings, [...settings.bindings.slice(2), ...extraBindings]);
  for (const key of Object.keys(settings).filter(key => key !== 'bindings')) assert.deepEqual(metadata[key], settings[key]);
  assert.equal(metadata.main_module, 'worker.js'); assert.equal(metadata.migrations, undefined);
  assert.deepEqual(new Uint8Array(await form.get('worker.js').arrayBuffer()), bytes);
});

test('independent inventory traverses cursor pages and retains empty-state DOs', async () => {
  const api = sequenceApi([{ result: [{ id: '1'.repeat(64), hasStoredData: false }], result_info: { cursor: 'next cursor' } },
    { result: [{ id: '2'.repeat(64), hasStoredData: true }], result_info: {} }]);
  const result = await readInventory(api, [{ id: 'a'.repeat(32), class: 'AccountState' }]);
  assert.equal(result.objects.length, 2); assert.equal(result.classes.AccountState, 2); assert.equal(result.listingComplete, true);
  assert.equal(new URL('https://api.invalid' + api.paths[1]).searchParams.get('cursor'), 'next cursor');
});

test('independent inventory follows empty batches with a cursor and rejects an explicitly incomplete terminal batch', async () => {
  const api = sequenceApi([{ result: [], result_info: { cursor: 'continue', list_complete: false } },
    { result: [{ id: '3'.repeat(64) }], result_info: {} }]);
  assert.equal((await readInventory(api, [{ id: 'a'.repeat(32), class: 'AccountState' }])).objects.length, 1);
  await assert.rejects(readInventory(sequenceApi([{ result: [], result_info: { list_complete: false } }]), [{ id: 'a'.repeat(32), class: 'AccountState' }]));
});

test('independent inventory refuses repeated object IDs and cyclic cursors', async () => {
  const namespace = [{ id: 'a'.repeat(32), class: 'AccountState' }];
  await assert.rejects(readInventory(sequenceApi([{ result: [{ id: '1'.repeat(64) }, { id: '1'.repeat(64) }] }]), namespace));
  const api = sequenceApi([{ result: [{ id: '1'.repeat(64) }], result_info: { cursor: 'A' } },
    { result: [{ id: '2'.repeat(64) }], result_info: { cursor: 'B' } },
    { result: [{ id: '3'.repeat(64) }], result_info: { cursor: 'A' } }]);
  await assert.rejects(readInventory(api, namespace)); assert.equal(api.paths.length, 3);
});

test('upload rejects missing main, duplicate names, metadata collisions and escaping module paths', () => {
  const settings = { bindings: [] }, module = { name: 'worker.js', type: 'application/javascript+module', bytes: new Uint8Array([1]) };
  const upload = modules => makeUpload({ modules, mainModule: 'worker.js', settings });
  assert.throws(() => upload([])); assert.throws(() => upload([{ ...module, name: 'other.js' }]));
  assert.throws(() => upload([module, { ...module }]));
  for (const name of ['metadata', '../worker.js', '/worker.js', 'a//worker.js', 'a/./worker.js']) assert.throws(() => upload([module, { ...module, name }]));
  assert.throws(() => upload([{ ...module, bytes: 'source must be bytes' }]));
});

test('collector refuses symbolic-link/nonprivate output directories and unrecognized DO classes', async () => {
  const dir = await newDirectory(), linked = join(temporary, 'linked-output'); await symlink(dir, linked);
  let requests = 0;
  await withFetch(() => { requests++; throw new Error('Must fail before network'); }, async () => {
    await assert.rejects(collectRealObjects(plan(linked)));
    await chmod(dir, 0o755); await assert.rejects(collectRealObjects(plan(dir)));
    await chmod(dir, 0o700); await assert.rejects(collectRealObjects(plan(dir, { objects: [{ ...object, className: 'OtherNamespace' }] })));
  });
  assert.equal(requests, 0);
});

test('collector bounds streamed ciphertext before decoding/decrypting or saving any checkpoint', async () => {
  const dir = await newDirectory(); let cancelled = false, chunks = 0;
  const block = new Uint8Array(1024 * 1024);
  const body = new ReadableStream({ pull(controller) { chunks++; controller.enqueue(block); }, cancel() { cancelled = true; } });
  await withFetch(async () => {
    const response = new Response(body, { headers: { 'content-type': 'application/jose', 'x-backup-response-signature': 'A'.repeat(43) } });
    Object.defineProperty(response, 'url', { value: endpoint }); return response;
  }, async () => assert.rejects(collectRealObjects(plan(dir))));
  assert.equal(cancelled, true); assert.ok(chunks <= 93);
  await assert.rejects(readFile(cacheFile(dir)), { code: 'ENOENT' });
});
