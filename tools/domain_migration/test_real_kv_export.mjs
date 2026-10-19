import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, readdir, rm, chmod, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createExportCredentials } from './secure_export.mjs';
import { collectRealKV, loadRealKV, ReadOnlyKVClient } from './real_kv_export.mjs';

const credentials = createExportCredentials();
const accountId = 'a'.repeat(32), namespaceId = 'b'.repeat(32);
async function temporary(fn) {
  await mkdir(new URL('../../output/', import.meta.url), { recursive: true });
  const dir = await mkdtemp(fileURLToPath(new URL('../../output/test-real-kv-', import.meta.url)));
  try { await chmod(dir, 0o700); await fn(dir); } finally { await rm(dir, { recursive: true, force: true }); }
}
const ok = result => Response.json({ success: true, result });
function fakeClient({ lists, values, raw = new Map(), bulkTransform = entries => entries }) {
  let listIndex = 0; const calls = [];
  const fetchImpl = async (url, options) => {
    const parsed = new URL(url); calls.push({ method: options.method, pathname: parsed.pathname });
    assert.equal(parsed.origin, 'https://api.cloudflare.com'); assert.equal(options.redirect, 'error');
    if (parsed.pathname.endsWith('/keys')) {
      return ok(lists[Math.min(listIndex++, lists.length - 1)]);
    }
    if (parsed.pathname.endsWith('/bulk/get')) {
      const body = JSON.parse(options.body); assert.deepEqual([body.type, body.withMetadata], ['text', true]);
      return ok({ values: bulkTransform(Object.fromEntries(body.keys.filter(key => values.has(key)).map(key => [key, values.get(key)]))) });
    }
    if (parsed.pathname.includes('/values/')) {
      const key = decodeURIComponent(parsed.pathname.split('/values/')[1]);
      return raw.has(key) ? new Response(raw.get(key)) : new Response(null, { status: 404 });
    }
    throw new Error('Unexpected request');
  };
  return { client: new ReadOnlyKVClient({ token: 'synthetic', accountId, namespaceId, fetchImpl, intervalMs: 0, sleep: async () => {} }), calls };
}

test('encrypted round trip preserves Unicode, binary bytes, absolute expiry and bulk metadata', async () => temporary(async outputDir => {
  const rows = [{ name: 'user:synthetic' }, { name: 'ntimg:private', metadata: { type: 'image/png' } },
    { name: 'nul-data' }, { name: 'bom-data' }, { name: 'surrogate-data' }];
  const values = new Map([['user:synthetic', { value: 'Привет 👋', metadata: { provider: 'example' }, expiration: 2000000000 }],
    ['nul-data', { value: 'a\0b' }], ['bom-data', { value: '\uFEFFx' }], ['surrogate-data', { value: '\uD800' }]]);
  const raw = new Map([['ntimg:private', Buffer.from([0, 255, 128, 1])], ['nul-data', Buffer.from([0, 42])],
    ['bom-data', Buffer.from([239, 187, 191, 120])], ['surrogate-data', Buffer.from([0xED, 0xA0, 0x80])]]);
  const { client } = fakeClient({ lists: [rows], values, raw });
  const result = await collectRealKV({ credentials, outputDir, accountId, namespaceId, client });
  assert.equal(result.proof.captured, 5); assert.equal(result.proof.rawValues, 4); assert.equal(result.proof.uncapturedLiveKeys, 0);
  const loaded = await loadRealKV({ credentials, outputDir });
  assert.equal(loaded.kvEntries.length, 5);
  const user = loaded.kvEntries.find(entry => entry.key === 'user:synthetic');
  assert.deepEqual(user, { key: 'user:synthetic', valueBase64: Buffer.from('Привет 👋').toString('base64'),
    expiration: 2000000000, metadata: { provider: 'example' } });
  for (const [key, bytes] of raw) assert.deepEqual(Buffer.from(loaded.kvEntries.find(entry => entry.key === key).valueBase64, 'base64'), bytes);
  for (const file of await readdir(outputDir)) {
    assert.match(file, /^(batch-\d{6}|index)\.jwe$/);
    const contents = await readFile(join(outputDir, file), 'utf8');
    assert.equal(contents.includes('user:synthetic'), false); assert.equal(contents.includes('Привет'), false);
  }
}));

test('union catchup captures new keys and records deleted or expired missing entries', async () => temporary(async outputDir => {
  const initial = [{ name: 'a' }, { name: 'deleted' }, { name: 'expired', expiration: 1 }];
  const final = [{ name: 'a' }, { name: 'new' }];
  const { client } = fakeClient({ lists: [initial, final, final], values: new Map([['a', { value: 'one' }], ['new', { value: 'two' }]]) });
  const { proof } = await collectRealKV({ credentials, outputDir, accountId, namespaceId, client });
  assert.equal(proof.captured, 2); assert.equal(proof.deletedDuringCapture, 1); assert.equal(proof.expiredDuringCapture, 1);
  assert.equal(proof.unionListed, 4); assert.equal(proof.globalAtomic, false);
  assert.equal((await loadRealKV({ credentials, outputDir })).kvEntries.length, 2);
}));

test('live listed 404 rejects completeness and never publishes an index', async () => temporary(async outputDir => {
  const { client } = fakeClient({ lists: [[{ name: 'still-live' }]], values: new Map() });
  await assert.rejects(collectRealKV({ credentials, outputDir, accountId, namespaceId, client, maxCatchupRounds: 1 }), /uncaptured live keys/);
  assert.equal((await readdir(outputDir)).includes('index.jwe'), false);
}));

test('authenticated batch ciphertext tampering is rejected', async () => temporary(async outputDir => {
  const { client } = fakeClient({ lists: [[{ name: 'a' }]], values: new Map([['a', { value: 'one' }]]) });
  await collectRealKV({ credentials, outputDir, accountId, namespaceId, client });
  const file = join(outputDir, 'batch-000001.jwe'), contents = await readFile(file, 'utf8');
  await writeFile(file, contents.slice(0, -2) + (contents.at(-2) === 'A' ? 'B' : 'A') + contents.at(-1), { mode: 0o600 });
  await assert.rejects(loadRealKV({ credentials, outputDir }));
}));

test('read-only client rejects mutation paths before any request', async () => {
  let calls = 0;
  const client = new ReadOnlyKVClient({ token: 'synthetic', accountId, namespaceId, intervalMs: 0, fetchImpl: async () => { calls++; return ok([]); } });
  await assert.rejects(client.request('PUT', '/values/a', 'value'));
  await assert.rejects(client.request('POST', '/bulk', { keys: ['a'], type: 'text', withMetadata: true }));
  await assert.rejects(client.request('GET', '/values/a?token=x'));
  await assert.rejects(client.request('GET', '/keys?limit=1000&cursor=x#bad'));
  assert.equal(calls, 0);
});

test('pagination detects repeated cursors, retries transient failures and rejects public destinations', async () => {
  let calls = 0;
  const client = new ReadOnlyKVClient({ token: 'synthetic', accountId, namespaceId, intervalMs: 0, sleep: async () => {},
    fetchImpl: async () => { calls++; return calls === 1 ? new Response(null, { status: 429 })
      : Response.json({ success: true, result: [{ name: 'same' }], result_info: { cursor: 'again' } }); } });
  await assert.rejects(client.list()); assert.equal(calls, 3);
  assert.throws(() => new ReadOnlyKVClient({ token: 'synthetic', accountId: '../bad', namespaceId }));
});

test('encrypted output rejects nonempty destinations, wrong keys and insecure permissions', async () => temporary(async outputDir => {
  const { client } = fakeClient({ lists: [[]], values: new Map() });
  await collectRealKV({ credentials, outputDir, accountId, namespaceId, client });
  await assert.rejects(collectRealKV({ credentials, outputDir, accountId, namespaceId, client }), /must be empty/);
  await assert.rejects(loadRealKV({ credentials: createExportCredentials(), outputDir }));
  await chmod(join(outputDir, 'index.jwe'), 0o644);
  await assert.rejects(loadRealKV({ credentials, outputDir }));
}));
