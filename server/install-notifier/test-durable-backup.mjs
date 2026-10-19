import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, compactDecrypt } from 'jose';
import {
  BACKUP_PATH, BACKUP_LIMITS, isBackupRequest, handleBackupExport,
  snapshotStorage, validateSnapshot, encodeValue, decodeValue,
  canonicalStringify, backupHmac, verifyBackupHmac,
} from './durable_backup.js';

const recipient = await generateKeyPair('RSA-OAEP-256', { modulusLength: 2048, extractable: true });
const recipientJwk = await exportJWK(recipient.publicKey);
const utf8 = new TextEncoder();
const objectId = 'b'.repeat(64), namespaceId = 'a'.repeat(32);
const meta = () => ({ className: 'AccountState', namespaceId, objectId, runId: crypto.randomUUID(), sourceVersion: 'fixture-build', accountEpoch: '1' });

function fixture(entries = [], alarm = 1950000000000) {
  const data = new Map(entries), calls = { transactions: 0, lists: 0, alarms: 0, writes: 0, network: 0 };
  const storage = {
    async list(options) {
      calls.lists++;
      assert.equal(options.limit, 128);
      return new Map([...data].sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)))
        .filter(([key]) => options.startAfter === undefined || Buffer.compare(Buffer.from(key), Buffer.from(options.startAfter)) > 0)
        .slice(0, options.limit));
    },
    async getAlarm() { calls.alarms++; return alarm; },
    async put() { calls.writes++; throw new Error('Forbidden write'); },
    async delete() { calls.writes++; throw new Error('Forbidden deletion'); },
    async setAlarm() { calls.writes++; throw new Error('Forbidden alarm'); },
    async deleteAlarm() { calls.writes++; throw new Error('Forbidden alarm deletion'); },
    async transaction(callback) { calls.transactions++; return callback(storage); },
  };
  const state = { id: { toString: () => objectId }, storage };
  const env = {
    DURABLE_BACKUP_ENABLED: 'true', DURABLE_BACKUP_UNTIL: new Date(Date.now() + 1800000).toISOString(),
    DURABLE_BACKUP_HMAC_SECRET: Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url'),
    DURABLE_BACKUP_NAMESPACE_IDS: JSON.stringify({ AccountState: namespaceId }),
    DURABLE_BACKUP_SOURCE_VERSION: 'fixture-build', ACCOUNT_STATE_EPOCH: '1',
  };
  return { state, env, calls, data };
}
function requestPayload(patch = {}) {
  return { format: 1, ...meta(), issuedAt: Date.now(), nonce: Buffer.from(crypto.getRandomValues(new Uint8Array(16))).toString('base64url'), recipientJwk, ...patch };
}
async function signedRequest(env, body, { path = BACKUP_PATH, method = 'POST', raw, signature } = {}) {
  raw ??= JSON.stringify(body);
  signature ??= await backupHmac(env.DURABLE_BACKUP_HMAC_SECRET, method + '\n' + new URL(path, 'https://fixture.invalid').pathname + '\n' + raw);
  return new Request('https://fixture.invalid' + path, { method, headers: { 'x-backup-signature': signature, 'content-type': 'application/json' }, ...(method === 'POST' || method === 'PUT' ? { body: raw } : {}) });
}
async function call(f, body = requestPayload(), options) {
  return handleBackupExport(await signedRequest(f.env, body, options), { state: f.state, env: f.env, className: 'AccountState' });
}
async function resign(snapshot) {
  const { sha256: _old, ...payload } = snapshot;
  snapshot.sha256 = Buffer.from(await crypto.subtle.digest('SHA-256', utf8.encode(canonicalStringify(payload)))).toString('hex');
  return snapshot;
}
function chunked(text, key = 'user_progress:google_fixture') {
  const bytes = Buffer.from(text), parts = [];
  for (let offset = 0; offset < bytes.length; offset += 49152) parts.push(['chunk:' + key + ':' + parts.length, bytes.subarray(offset, offset + 49152).toString('base64')]);
  return [['doc:' + key, { key, chunks: parts.length, options: {}, expiresAt: undefined, epoch: '1' }], ...parts];
}

test('backup prefix is reserved including unknown versions, with no broad false matches', () => {
  for (const path of ['/_backup', '/_backup/', BACKUP_PATH, '/_backup/v2/restore']) assert.equal(isBackupRequest(new Request('https://fixture.invalid' + path)), true);
  for (const path of ['/api/user/status', '/_backups', '/_backup-other']) assert.equal(isBackupRequest(new Request('https://fixture.invalid' + path)), false);
});

test('encrypted signed response preserves every raw key without storage, alarm, KV, payment, or network writes', async () => {
  const f = fixture([
    ['account-id', 'google_fixture'],
    ['doc:user:google_fixture', { key: 'user:google_fixture', value: '{"id":"google_fixture","entitlements":{"web":{"expiresAt":"2030-01-01"}}}', options: {}, epoch: '1', expiresAt: undefined }],
    ['doc:payment_ledger:fixture', { key: 'payment_ledger:fixture', value: '{"amount":99,"source":"web"}', options: {}, epoch: '1' }],
    ['effect:pending', { type: 'fixture', pending: true }], ['projection:user:google_fixture', { key: 'user:google_fixture' }],
  ]);
  const before = structuredClone([...f.data]), body = requestPayload(), originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { f.calls.network++; throw new Error('Network forbidden'); };
  let response;
  try { response = await call(f, body); } finally { globalThis.fetch = originalFetch; }
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'application/jose');
  assert.match(response.headers.get('cache-control'), /no-store/);
  const ciphertext = await response.text();
  assert.equal(ciphertext.split('.').length, 5);
  assert.equal(ciphertext.includes('google_fixture'), false);
  assert.equal(await verifyBackupHmac(f.env.DURABLE_BACKUP_HMAC_SECRET, 'response\n' + body.nonce + '\n' + ciphertext, response.headers.get('x-backup-response-signature')), true);
  const decrypted = await compactDecrypt(ciphertext, recipient.privateKey, { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
  const snapshot = await validateSnapshot(JSON.parse(new TextDecoder().decode(decrypted.plaintext)));
  assert.equal(snapshot.metadata.objectId, objectId);
  assert.equal(snapshot.metadata.runId, body.runId);
  assert.equal(snapshot.metadata.alarm, 1950000000000);
  assert.equal(snapshot.entryCount, before.length);
  assert.deepEqual(snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]), [...before].sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b))));
  assert.deepEqual([...f.data], before);
  assert.deepEqual(f.calls, { transactions: 1, lists: 1, alarms: 1, writes: 0, network: 0 });
});

test('bounded authenticated replay creates only freshly encrypted responses to the signed recipient', async () => {
  const f = fixture([['account-id', 'google_fixture']]), body = requestPayload();
  const first = await call(f, body), second = await call(f, body);
  assert.equal(first.status, 200); assert.equal(second.status, 200);
  assert.notEqual(await first.text(), await second.text());
  assert.equal(f.calls.writes, 0);
});

test('response authentication binds the nonce, ciphertext and credential', async () => {
  const secret = Buffer.alloc(32, 4).toString('base64url'), text = 'response\nfixture\nencrypted';
  const signature = await backupHmac(secret, text);
  assert.equal(await verifyBackupHmac(secret, text, signature), true);
  assert.equal(await verifyBackupHmac(secret, text + 'x', signature), false);
  assert.equal(await verifyBackupHmac(Buffer.alloc(32, 5).toString('base64url'), text, signature), false);
  assert.equal(await verifyBackupHmac(secret, text, 'invalid'), false);
});

for (const [name, envPatch] of [
  ['default off', { DURABLE_BACKUP_ENABLED: undefined }], ['explicit off', { DURABLE_BACKUP_ENABLED: 'false' }],
  ['missing expiry', { DURABLE_BACKUP_UNTIL: undefined }], ['expired window', { DURABLE_BACKUP_UNTIL: '2000-01-01T00:00:00.000Z' }],
  ['unbounded window', { DURABLE_BACKUP_UNTIL: '2999-01-01T00:00:00.000Z' }],
  ['missing namespace map', { DURABLE_BACKUP_NAMESPACE_IDS: undefined }],
  ['wrong namespace map', { DURABLE_BACKUP_NAMESPACE_IDS: JSON.stringify({ AccountState: 'f'.repeat(32) }) }],
  ['wrong source version', { DURABLE_BACKUP_SOURCE_VERSION: 'other-build' }],
  ['wrong epoch', { ACCOUNT_STATE_EPOCH: '2' }],
]) test('rejects ' + name + ' before any storage access', async () => {
  const f = fixture(); Object.assign(f.env, envPatch);
  const response = await call(f);
  assert.equal(response.status, 404); assert.deepEqual(await response.json(), { error: 'Backup unavailable' });
  assert.deepEqual(f.calls, { transactions: 0, lists: 0, alarms: 0, writes: 0, network: 0 });
});

for (const [name, patch] of [
  ['wrong object', { objectId: 'c'.repeat(64) }], ['wrong class', { className: 'PurchaseClaims' }],
  ['wrong namespace', { namespaceId: 'd'.repeat(32) }], ['wrong format', { format: 2 }],
  ['stale request', { issuedAt: Date.now() - 120000 }], ['future request', { issuedAt: Date.now() + 120000 }],
  ['fractional timestamp', { issuedAt: Date.now() + 0.5 }], ['short nonce', { nonce: 'AA' }],
  ['bad run UUID', { runId: 'fixture' }], ['extra property', { unexpected: true }],
  ['array run UUID', { runId: [crypto.randomUUID()] }],
  ['private recipient key', { recipientJwk: { ...recipientJwk, d: 'AA' } }],
  ['unknown recipient key field', { recipientJwk: { ...recipientJwk, x5u: 'https://fixture.invalid' } }],
  ['small recipient key', { recipientJwk: { ...recipientJwk, n: Buffer.alloc(128, 255).toString('base64url') } }],
  ['recipient for signing', { recipientJwk: { ...recipientJwk, use: 'sig' } }],
  ['recipient private operation', { recipientJwk: { ...recipientJwk, key_ops: ['decrypt'] } }],
]) test('rejects signed ' + name + ' before any storage access', async () => {
  const f = fixture(), response = await call(f, requestPayload(patch));
  assert.equal(response.status, 404);
  assert.deepEqual(f.calls, { transactions: 0, lists: 0, alarms: 0, writes: 0, network: 0 });
});

test('invalid or missing secret/signature and tampered raw body never read storage', async () => {
  const f = fixture(), body = requestPayload();
  for (const secret of [undefined, '', 'literal-password', Buffer.alloc(31).toString('base64url')]) {
    const env = { ...f.env, DURABLE_BACKUP_HMAC_SECRET: secret };
    assert.equal((await handleBackupExport(new Request('https://fixture.invalid' + BACKUP_PATH, { method: 'POST', body: JSON.stringify(body), headers: { 'x-backup-signature': 'AA' } }), { state: f.state, env, className: 'AccountState' })).status, 404);
  }
  for (const signature of ['', 'AA', Buffer.alloc(32).toString('base64url')]) assert.equal((await call(f, body, { signature })).status, 404);
  const original = JSON.stringify(body), signature = await backupHmac(f.env.DURABLE_BACKUP_HMAC_SECRET, 'POST\n' + BACKUP_PATH + '\n' + original);
  assert.equal((await call(f, body, { raw: original + ' ', signature })).status, 404);
  assert.deepEqual(f.calls, { transactions: 0, lists: 0, alarms: 0, writes: 0, network: 0 });
});

test('unsupported route, query string, method, malformed JSON and oversized body fail closed', async () => {
  const f = fixture();
  for (const options of [{ path: '/_backup/v1/restore' }, { path: BACKUP_PATH + '?fixture=1' }, { method: 'GET' }, { raw: '{invalid' }, { raw: 'x'.repeat(BACKUP_LIMITS.maxRequestBytes + 1) }]) assert.equal((await call(f, requestPayload(), options)).status, 404);
  assert.equal(f.calls.transactions, 0);
});

test('snapshot paginates every raw entry in one transaction and preserves non-BMP key order', async () => {
  const f = fixture(Array.from({ length: 300 }, (_, i) => ['raw:' + i.toString().padStart(4, '0'), { index: i, absent: undefined }]).concat([['raw:\uE000', 'BMP'], ['raw:😀', 'supplementary']]));
  const snapshot = await snapshotStorage(f.state, meta());
  assert.equal(snapshot.entryCount, 302); assert.equal(f.calls.lists, 3); assert.equal(f.calls.transactions, 1); assert.equal(f.calls.alarms, 1);
  assert.equal(snapshot.entries.at(-1).key, 'raw:😀');
});

test('exact full page needs one terminating empty page; empty objects still record alarm', async () => {
  const full = fixture(Array.from({ length: 128 }, (_, i) => [String(i).padStart(3, '0'), i]));
  assert.equal((await snapshotStorage(full.state, meta())).entryCount, 128); assert.equal(full.calls.lists, 2);
  const empty = fixture([], null), snapshot = await snapshotStorage(empty.state, meta());
  assert.equal(snapshot.entryCount, 0); assert.equal(snapshot.metadata.alarm, null);
});

test('alarm compatibility fallback stays inside the active transaction', async () => {
  const f = fixture(); let active = false;
  const getAlarm = f.state.storage.getAlarm.bind(f.state.storage);
  f.state.storage.getAlarm = async () => { assert.equal(active, true); return getAlarm(); };
  f.state.storage.transaction = async callback => { active = true; try { return await callback({ list: f.state.storage.list.bind(f.state.storage) }); } finally { active = false; } };
  assert.equal((await snapshotStorage(f.state, meta())).metadata.alarm, 1950000000000);
});

test('undefined properties, holes, null prototypes and binary views round trip exactly', () => {
  const sparse = new Array(4); sparse[2] = undefined; sparse.caption = 'Қазақша русский 😀';
  const nullObject = Object.create(null); nullObject.value = undefined;
  const buffer = new ArrayBuffer(16); new Uint8Array(buffer).set([1, 2, 3, 4, 5, 6]);
  const values = [undefined, null, true, false, '', 'Қазақша русский 😀', NaN, Infinity, -Infinity, -0, 7n, -9n,
    { missing: undefined, nested: { optional: undefined } }, sparse, nullObject, buffer,
    new Uint16Array(buffer.slice(0), 2, 3), new DataView(buffer.slice(0), 3, 5), new BigInt64Array([1n, -2n]), new Date('2026-10-19T12:00:00.000Z')];
  for (const value of values) assert.deepEqual(decodeValue(encodeValue(value)), value);
  assert.equal(Object.hasOwn(decodeValue(encodeValue({ present: undefined })), 'present'), true);
  assert.equal(Object.hasOwn(decodeValue(encodeValue(sparse)), 0), false);
});

test('codec rejects cycles, aliasing, pollution, accessors and unsupported values instead of losing data', () => {
  const cycle = {}; cycle.self = cycle;
  const alias = {}, buffer = new ArrayBuffer(8);
  const getter = {}; Object.defineProperty(getter, 'secret', { enumerable: true, get() { throw new Error('Getter must not run'); } });
  const symbol = { [Symbol('fixture')]: true }, hidden = {}; Object.defineProperty(hidden, 'fixture', { value: 1 });
  for (const value of [cycle, { a: alias, b: alias }, { buffer, view: new Uint8Array(buffer) }, new Set([1]), /fixture/, () => {}, Symbol('fixture'), getter, hidden, symbol,
    JSON.parse('{"__proto__":{"polluted":true}}'), JSON.parse('{"constructor":{"prototype":{"polluted":true}}}')]) assert.throws(() => encodeValue(value), /Invalid durable backup/);
  assert.equal({}.polluted, undefined);
  assert.throws(() => decodeValue({ t: 'object', nullPrototype: false, v: [['__proto__', { t: 'null' }]] }), /Invalid durable backup/);
});

test('large multilingual AccountState documents preserve every base64 chunk and byte', async () => {
  const text = JSON.stringify({ progress: 'Қазақша русский 😀 '.repeat(10000) }), raw = chunked(text), f = fixture(raw);
  const snapshot = await snapshotStorage(f.state, meta());
  const restored = new Map(snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]));
  const doc = restored.get('doc:user_progress:google_fixture');
  const reconstructed = Buffer.concat(Array.from({ length: doc.chunks }, (_, i) => Buffer.from(restored.get('chunk:' + doc.key + ':' + i), 'base64'))).toString('utf8');
  assert.equal(reconstructed, text); assert.deepEqual(restored, f.data);
});

test('missing, orphaned, truncated, invalid UTF-8 or malformed AccountState chunks cannot export', async () => {
  const valid = chunked('я'.repeat(70000));
  const cases = [
    valid.filter(([key]) => !key.endsWith(':1')),
    valid.concat([['chunk:orphan:0', 'eA==']]),
    valid.map(([key, value]) => [key, key.endsWith(':0') ? 'eA==' : value]),
    [['doc:user:x', { key: 'user:x', chunks: 1 }], ['chunk:user:x:0', '/w==']],
    [['doc:user:x', { key: 'user:y', chunks: 1 }], ['chunk:user:y:0', 'eA==']],
    [['doc:user:x', { key: 'user:x', chunks: 0 }]],
  ];
  for (const raw of cases) await assert.rejects(snapshotStorage(fixture(raw).state, meta()), /Invalid durable backup/);
});

test('snapshot hash detects value or metadata tampering and exact schema rejects hidden fields', async () => {
  const snapshot = await snapshotStorage(fixture([['fixture', { value: 'safe' }]]).state, meta());
  for (const mutate of [s => { s.entries[0].value.v[0][1].v = 'changed'; }, s => { s.metadata.accountEpoch = '2'; }, s => { s.extra = 'field'; }, s => { s.entryCount++; }]) {
    const copy = structuredClone(snapshot); mutate(copy); await assert.rejects(validateSnapshot(copy), /Invalid durable backup/);
  }
});

test('even recomputed hashes cannot hide duplicate, reordered, or malformed snapshot entries', async () => {
  const snapshot = await snapshotStorage(fixture([['a', 1], ['b', 2]]).state, meta());
  for (const mutate of [s => { s.entries.reverse(); }, s => { s.entries[1].key = 'a'; }, s => { s.entries[0].key = ''; }, s => { s.entries[0].value = { t: 'number', v: 'wrong' }; }, s => { s.metadata.alarm = -1; }, s => { s.metadata.runId = [s.metadata.runId]; }, s => { s.metadata.namespaceId = [s.metadata.namespaceId]; }]) {
    const copy = structuredClone(snapshot); mutate(copy); await resign(copy); await assert.rejects(validateSnapshot(copy), /Invalid durable backup/);
  }
});

test('malformed sparse canonical arrays reject through the same generic validation error', () => {
  const value = new Array(1); value.extra = true;
  assert.throws(() => canonicalStringify(value), /Invalid durable backup/);
});

test('value byte/depth limits and broken pagination fail closed', async () => {
  assert.throws(() => encodeValue('x'.repeat(BACKUP_LIMITS.maxValueBytes)), /Invalid durable backup/);
  let deep = {}; for (let i = 0; i < 100; i++) deep = { child: deep };
  assert.throws(() => encodeValue(deep), /Invalid durable backup/);
  const f = fixture(); f.state.storage.list = async () => new Map([['b', 1], ['a', 2]]);
  await assert.rejects(snapshotStorage(f.state, meta()), /Invalid durable backup/);
  const repeated = fixture(); const page = new Map(Array.from({ length: 128 }, (_, i) => [String(i).padStart(3, '0'), i]));
  repeated.state.storage.list = async () => page;
  await assert.rejects(snapshotStorage(repeated.state, meta()), /Invalid durable backup/);
});

test('storage exceptions return a generic failure without leaking account IDs or logging them', async () => {
  const f = fixture(); f.state.storage.list = async () => { throw new Error('secret google_fixture private-payment'); };
  const originalError = console.error, originalLog = console.log, logs = [];
  console.error = (...args) => logs.push(args); console.log = (...args) => logs.push(args);
  let response;
  try { response = await call(f); } finally { console.error = originalError; console.log = originalLog; }
  assert.equal(response.status, 404); assert.deepEqual(await response.json(), { error: 'Backup unavailable' }); assert.deepEqual(logs, []);
});

test('optional diagnostics reveal only authenticated encrypted enum/counts, never exception text or stored data', async () => {
  const f = fixture([['private:google_fixture', 'private-payment-value']]);
  f.env.DURABLE_BACKUP_DIAGNOSTICS = 'true';
  f.state.storage.list = async () => { throw new Error('secret google_fixture private-payment'); };
  const body = requestPayload(), response = await call(f, body);
  assert.equal(response.status, 200); assert.equal(response.headers.get('content-type'), 'application/jose');
  const ciphertext = await response.text(); assert.equal(ciphertext.includes('google_fixture'), false);
  assert.equal(await verifyBackupHmac(f.env.DURABLE_BACKUP_HMAC_SECRET, 'response\n' + body.nonce + '\n' + ciphertext,
    response.headers.get('x-backup-response-signature')), true);
  const decrypted = await compactDecrypt(ciphertext, recipient.privateKey,
    { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
  assert.equal(decrypted.protectedHeader.typ, 'pdd-durable-backup-diagnostic+jwe');
  assert.deepEqual(JSON.parse(new TextDecoder().decode(decrypted.plaintext)), {
    format: 'pdd-durable-backup-diagnostic', schema: 1, reason: 'storage_list', errorKind: 'Error',
    entryCount: 0, pageCount: 0, encodedBytes: 0,
  });
  assert.equal(f.calls.writes, 0);
});

test('diagnostic phases identify failed API, pagination, codec, key order, alarm and snapshot checks', async () => {
  for (const [expectedReason, modify] of [
    ['storage_transaction', f => { f.state.storage.transaction = async () => { throw new Error('never disclose this'); }; }],
    ['storage_api', f => { f.state.storage.getAlarm = undefined; }],
    ['storage_page', f => { f.state.storage.list = async () => []; }],
    ['key_validation', f => { f.state.storage.list = async () => new Map([['', 1]]); }],
    ['key_order', f => { f.state.storage.list = async () => new Map([['b', 1], ['a', 2]]); }],
    ['value_encoding', f => { f.state.storage.list = async () => new Map([['fixture', new Set([1])]]); }],
    ['value_byte_limit', f => { f.state.storage.list = async () => new Map([['fixture', 'x'.repeat(BACKUP_LIMITS.maxValueBytes)]]); }],
    ['storage_alarm', f => { f.state.storage.getAlarm = async () => { const error = new Error('account data'); error.name = 'private customer text'; throw error; }; }],
    ['snapshot_validation', f => { f.state.storage.list = async () => new Map([['chunk:orphan:0', 'eA==']]); }],
  ]) {
    const f = fixture(); f.env.DURABLE_BACKUP_DIAGNOSTICS = 'true'; modify(f);
    const response = await call(f); assert.equal(response.status, 200);
    const { plaintext, protectedHeader } = await compactDecrypt(await response.text(), recipient.privateKey,
      { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
    assert.equal(protectedHeader.typ, 'pdd-durable-backup-diagnostic+jwe');
    const diagnostic = JSON.parse(new TextDecoder().decode(plaintext));
    assert.equal(diagnostic.reason, expectedReason);
    assert.deepEqual(Object.keys(diagnostic).sort(), ['encodedBytes', 'entryCount', 'errorKind', 'format', 'pageCount', 'reason', 'schema']);
    assert.ok(Number.isSafeInteger(diagnostic.entryCount)); assert.ok(Number.isSafeInteger(diagnostic.pageCount));
    assert.ok(Number.isSafeInteger(diagnostic.encodedBytes));
    if (expectedReason === 'storage_alarm') assert.equal(diagnostic.errorKind, 'UnknownError');
    assert.equal(f.calls.writes, 0);
  }
});

test('diagnostic counters retain successfully read pages and entries before a later page failure', async () => {
  const f = fixture(Array.from({ length: 128 }, (_, i) => ['fixture:' + String(i).padStart(4, '0'), i]));
  f.env.DURABLE_BACKUP_DIAGNOSTICS = 'true';
  const originalList = f.state.storage.list.bind(f.state.storage);
  f.state.storage.list = async options => { if (options.startAfter !== undefined) throw new TypeError('private page token'); return originalList(options); };
  const response = await call(f), { plaintext } = await compactDecrypt(await response.text(), recipient.privateKey);
  const diagnostic = JSON.parse(new TextDecoder().decode(plaintext));
  assert.equal(diagnostic.reason, 'storage_list'); assert.equal(diagnostic.errorKind, 'TypeError');
  assert.equal(diagnostic.entryCount, 128); assert.equal(diagnostic.pageCount, 1); assert.ok(diagnostic.encodedBytes > 0);
});

test('diagnostic flag never grants unauthenticated or invalid-recipient requests storage access or details', async () => {
  const f = fixture(); f.env.DURABLE_BACKUP_DIAGNOSTICS = 'true';
  for (const [body, options] of [[requestPayload(), { signature: 'A'.repeat(43) }],
    [requestPayload({ recipientJwk: { ...recipientJwk, d: 'private-key-field' } }), {}]]) {
    const response = await call(f, body, options);
    assert.equal(response.status, 404); assert.deepEqual(await response.json(), { error: 'Backup unavailable' });
  }
  assert.equal(f.calls.transactions, 0); assert.equal(f.calls.writes, 0);
});

test('dense SQLite values whose lossless tags exceed 1 MiB preserve every array index and byte under the 8 MiB budget', async () => {
  const value = { values: Array.from({ length: 45000 }, (_, index) => index % 10) };
  assert.ok(Buffer.byteLength(JSON.stringify(value)) < 128 * 1024);
  const encoded = encodeValue(value), encodedBytes = Buffer.byteLength(canonicalStringify(encoded));
  assert.ok(encodedBytes > 1024 * 1024); assert.ok(encodedBytes < BACKUP_LIMITS.maxValueBytes);
  assert.deepEqual(decodeValue(encoded), value);
  const f = fixture([['dense:synthetic', value]]);
  const snapshot = await snapshotStorage(f.state, { ...meta(), className: 'TrafficState' });
  assert.equal(snapshot.entryCount, 1);
  assert.equal(canonicalStringify(snapshot.entries[0].value), canonicalStringify(encoded));
  assert.deepEqual(decodeValue(snapshot.entries[0].value), value);
  assert.equal(BACKUP_LIMITS.maxValueBytes, 8 * 1024 * 1024);
  assert.equal(BACKUP_LIMITS.maxBytes, 64 * 1024 * 1024);
  assert.equal(BACKUP_LIMITS.maxEntries, 100000); assert.equal(BACKUP_LIMITS.maxRequestBytes, 16384);
  assert.throws(() => encodeValue('x'.repeat(BACKUP_LIMITS.maxValueBytes)), /Invalid durable backup/);
});
