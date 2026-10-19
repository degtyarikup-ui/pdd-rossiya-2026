#!/usr/bin/env node
// Read-only Cloudflare KV capture. Names, metadata and values are encrypted
// before the first disk write; credentials and plaintext stay outside archives.
import { createHash, createHmac, createPrivateKey, createPublicKey, randomUUID, timingSafeEqual } from 'node:crypto';
import { constants } from 'node:fs';
import { mkdir, open, readdir, lstat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { canonicalStringify } from '../../server/install-notifier/durable_backup.js';
import { writePrivateNew } from './secure_export.mjs';

const requireServer = createRequire(new URL('../../server/install-notifier/package.json', import.meta.url));
const { CompactEncrypt, compactDecrypt, importJWK } = await import(requireServer.resolve('jose'));
const API = 'https://api.cloudflare.com/client/v4';
const utf8 = new TextEncoder();
const fail = () => { throw new Error('Read-only encrypted KV export failed validation'); };
const sha = value => createHash('sha256').update(value).digest('hex');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const jsonBytes = value => utf8.encode(canonicalStringify(value));
const mac = (value, key) => createHmac('sha256', key).update('pdd-real-kv-v1\n').update(jsonBytes(value)).digest('hex');
const countUnique = array => new Set(array).size;
const isHex = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
class ApiError extends Error { constructor(status) { super('Cloudflare read failed (HTTP ' + status + ')'); this.status = status; } }

async function privateRead(file) {
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.mode & 0o077) fail();
    return await handle.readFile();
  } finally { await handle.close(); }
}

function checkedCredentials(credentials) {
  if (credentials?.schema !== 1 || !/^[A-Za-z0-9_-]{43}$/.test(credentials.hmacSecret)
    || Buffer.from(credentials.hmacSecret, 'base64url').toString('base64url') !== credentials.hmacSecret) fail();
  try {
    const key = createPrivateKey({ key: credentials.recipientPrivateJwk, format: 'jwk' });
    if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength < 2048) fail();
    return { key: Buffer.from(credentials.hmacSecret, 'base64url'), publicJwk: createPublicKey(key).export({ format: 'jwk' }) };
  } catch { fail(); }
}

async function seal(value, credentials) {
  const { key, publicJwk } = checkedCredentials(credentials);
  return new CompactEncrypt(jsonBytes({ payload: value, authentication: { alg: 'HS256', signature: mac(value, key) } }))
    .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-real-kv+jwe' })
    .encrypt(await importJWK(publicJwk, 'RSA-OAEP-256'));
}

async function unseal(ciphertext, credentials) {
  const { key } = checkedCredentials(credentials);
  const result = await compactDecrypt(ciphertext, await importJWK(credentials.recipientPrivateJwk, 'RSA-OAEP-256'),
    { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
  if (result.protectedHeader.typ !== 'pdd-real-kv+jwe') fail();
  const wrapper = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(result.plaintext));
  if (wrapper.authentication?.alg !== 'HS256' || !/^[a-f0-9]{64}$/.test(wrapper.authentication.signature)) fail();
  const expected = Buffer.from(mac(wrapper.payload, key), 'hex'), actual = Buffer.from(wrapper.authentication.signature, 'hex');
  if (!timingSafeEqual(expected, actual)) fail();
  return wrapper.payload;
}

export async function readKVExportCredentials(file) { return JSON.parse((await privateRead(file)).toString('utf8')); }
export async function readWranglerToken(file = join(homedir(), 'Library/Preferences/.wrangler/config/default.toml')) {
  // Wrangler owns the permissions on its config. Never return/log its contents.
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  let source;
  try { if (!(await handle.stat()).isFile()) fail(); source = await handle.readFile('utf8'); }
  finally { await handle.close(); }
  const token = source.match(/^\s*oauth_token\s*=\s*"([^"\r\n]+)"/m)?.[1];
  if (!token) fail();
  return token;
}

// One shared scheduler limits starts to <= 4 requests/second even with parallel
// batch workers. Only the exact documented bulk-read POST can pass this client.
export class ReadOnlyKVClient {
  constructor({ token, accountId, namespaceId, fetchImpl = fetch, intervalMs = 260, attempts = 6, sleep = delay }) {
    if (!token || !isHex(accountId) || !isHex(namespaceId) || !Number.isFinite(intervalMs) || intervalMs < 0) fail();
    this.token = token; this.base = '/accounts/' + accountId + '/storage/kv/namespaces/' + namespaceId;
    this.fetchImpl = fetchImpl; this.intervalMs = intervalMs; this.attempts = attempts; this.sleep = sleep;
    this.nextStart = 0; this.schedule = Promise.resolve(); this.requests = 0;
  }
  async request(method, suffix, body) {
    if (method === 'POST') {
      if (suffix !== '/bulk/get' || !body || Object.keys(body).sort().join(',') !== 'keys,type,withMetadata'
        || body.type !== 'text' || body.withMetadata !== true || !Array.isArray(body.keys)
        || !body.keys.length || body.keys.length > 100 || body.keys.some(key => typeof key !== 'string')) fail();
    } else if (method !== 'GET' || body !== undefined
      || !(/^\/keys\?(?:limit=1000)(?:&cursor=[^&#]*)?$/.test(suffix) || /^\/values\/[^/?#]+$/.test(suffix))) fail();
    for (let attempt = 0; attempt < this.attempts; attempt++) {
      const turn = this.schedule.then(async () => {
        await this.sleep(Math.max(0, this.nextStart - Date.now())); this.nextStart = Date.now() + this.intervalMs;
      });
      this.schedule = turn.catch(() => {}); await turn;
      try {
        this.requests++;
        const response = await this.fetchImpl(API + this.base + suffix, { method, redirect: 'error',
          signal: AbortSignal.timeout(60000), headers: { Authorization: 'Bearer ' + this.token,
            'User-Agent': 'pdd-encrypted-readonly-kv/1', ...(body ? { 'Content-Type': 'application/json' } : {}) },
          ...(body ? { body: JSON.stringify(body) } : {}) });
        if (response.redirected) fail();
        if (response.status >= 200 && response.status < 300) return response;
        await response.body?.cancel();
        if (![429, 500, 502, 503, 504].includes(response.status) || attempt + 1 === this.attempts) throw new ApiError(response.status);
      } catch (error) {
        if (error instanceof ApiError || attempt + 1 === this.attempts) throw error;
      }
      await this.sleep(Math.min(1000 * 2 ** attempt, 16000));
    }
    fail();
  }
  async json(method, suffix, body) {
    const response = await this.request(method, suffix, body);
    let result; try { result = await response.json(); } catch { fail(); }
    if (result?.success !== true) fail(); return result;
  }
  async list() {
    const rows = [], seen = new Set(), cursors = new Set(); let cursor = '';
    do {
      const payload = await this.json('GET', '/keys?limit=1000' + (cursor ? '&cursor=' + encodeURIComponent(cursor) : ''));
      if (!Array.isArray(payload.result)) fail();
      for (const row of payload.result) {
        if (typeof row?.name !== 'string' || !row.name.length || Buffer.byteLength(row.name) > 512 || seen.has(row.name)) fail();
        checkedMetadata(row); seen.add(row.name); rows.push(row);
      }
      const info = payload.result_info ?? {};
      cursor = info.cursor || info.cursors?.after || '';
      if (cursor && (typeof cursor !== 'string' || cursors.has(cursor))) fail();
      if (!cursor && (payload.list_complete === false || info.list_complete === false)) fail();
      cursors.add(cursor);
      if (cursors.size > 100000) fail();
    } while (cursor);
    return rows;
  }
  async bulk(keys) {
    const payload = await this.json('POST', '/bulk/get', { keys, type: 'text', withMetadata: true });
    if (!payload.result?.values || Array.isArray(payload.result.values) || typeof payload.result.values !== 'object') fail();
    return payload.result.values;
  }
  async raw(key) {
    const response = await this.request('GET', '/values/' + encodeURIComponent(key));
    const bytes = Buffer.from(await response.arrayBuffer()); if (bytes.byteLength > 25 * 1024 * 1024) fail(); return bytes;
  }
}

function checkedMetadata(item) {
  const expiration = item.expiration ?? null, metadata = item.metadata ?? null;
  if (expiration !== null && (!Number.isSafeInteger(expiration) || expiration < 0)) fail();
  if (metadata !== null && (typeof metadata !== 'object' || Array.isArray(metadata))) fail();
  canonicalStringify(metadata); return { expiration, metadata };
}
function binary(row) {
  const mime = row.metadata?.type ?? '';
  return row.name.startsWith('ntimg:') || /^(image\/|audio\/|video\/|application\/octet-stream)/.test(String(mime));
}
function usableText(value) {
  return typeof value === 'string' && !/[\uFFFD\u0000]/.test(value) && !value.startsWith('\uFEFF')
    && value.isWellFormed() && Buffer.byteLength(value) <= 25 * 1024 * 1024;
}
async function parallel(items, concurrency, fn) {
  let offset = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    for (;;) { const index = offset++; if (index >= items.length) break; await fn(items[index], index); }
  }));
}

export async function collectRealKV({ credentials, outputDir, accountId, namespaceId, token,
  client, fetchImpl, onProgress = () => {}, maxCatchupRounds = 4, concurrency = 3, runId = randomUUID() }) {
  checkedCredentials(credentials);
  if (!isHex(accountId) || !isHex(namespaceId) || concurrency < 1 || concurrency > 3
    || !Number.isSafeInteger(concurrency) || maxCatchupRounds < 1 || maxCatchupRounds > 10) fail();
  outputDir = resolve(outputDir);
  await mkdir(outputDir, { recursive: true, mode: 0o700 });
  const dirStat = await lstat(outputDir); if (!dirStat.isDirectory() || dirStat.isSymbolicLink() || dirStat.mode & 0o077) fail();
  if ((await readdir(outputDir)).length) throw new Error('Encrypted KV destination must be empty');
  client ??= new ReadOnlyKVClient({ token: token ?? await readWranglerToken(), accountId, namespaceId, fetchImpl });
  const startedAt = new Date().toISOString(), captured = new Map(), missing = new Map(), descriptors = [];
  let batchSequence = 0, totalBytes = 0, rawValues = 0;
  const first = await client.list(), allListed = new Map(first.map(row => [row.name, row]));
  const progress = phase => onProgress({ phase, captured: captured.size, missing: missing.size, listed: allListed.size });
  async function collect(rows) {
    const batches = []; for (let i = 0; i < rows.length; i += 100) batches.push(rows.slice(i, i + 100));
    await parallel(batches, concurrency, async batch => {
      let values = Object.create(null);
      const textRows = batch.filter(row => !binary(row));
      if (textRows.length) {
        try { values = await client.bulk(textRows.map(row => row.name)); }
        catch (error) { if (!(error instanceof ApiError) || ![400, 413, 422].includes(error.status)) throw error; }
      }
      const entries = [], missingInBatch = [];
      // The outer batch pool is the only concurrency, including raw fallbacks.
      for (const row of batch) {
        const item = Object.hasOwn(values, row.name) ? values[row.name] : undefined;
        let bytes, method = 'bulk-text';
        let attributes = checkedMetadata(row);
        if (!binary(row) && item && typeof item === 'object' && usableText(item.value)) {
          bytes = Buffer.from(item.value, 'utf8');
          attributes = checkedMetadata({ expiration: Object.hasOwn(item, 'expiration') ? item.expiration : row.expiration,
            metadata: Object.hasOwn(item, 'metadata') ? item.metadata : row.metadata });
        } else {
          method = 'raw';
          try { bytes = await client.raw(row.name); rawValues++; }
          catch (error) {
            if (!(error instanceof ApiError) || error.status !== 404) throw error;
            const record = { key: row.name, ...attributes, observedAt: new Date().toISOString(), status: 'missing-at-read' };
            missing.set(row.name, record); missingInBatch.push(record); continue;
          }
        }
        const entry = { key: row.name, valueBase64: bytes.toString('base64'), ...attributes };
        totalBytes += bytes.length; captured.set(row.name, { sha256: sha(bytes), capturedAt: new Date().toISOString(), method });
        missing.delete(row.name); entries.push(entry);
      }
      const sequence = ++batchSequence, file = 'batch-' + String(sequence).padStart(6, '0') + '.jwe';
      const payload = { format: 'pdd-real-kv-batch', schema: 1, runId, accountId, namespaceId, sequence, entries, missing: missingInBatch };
      const ciphertext = await seal(payload, credentials);
      await writePrivateNew(join(outputDir, file), ciphertext);
      descriptors.push({ file, sha256: sha(ciphertext), payloadSha256: sha(jsonBytes(payload)), entryCount: entries.length });
      progress('kv-values');
    });
  }
  await collect(first); let finalRows, catchupRounds = 0;
  for (; catchupRounds < maxCatchupRounds; catchupRounds++) {
    finalRows = await client.list();
    for (const row of finalRows) allListed.set(row.name, row);
    const uncaptured = finalRows.filter(row => !captured.has(row.name));
    if (!uncaptured.length) break;
    // Re-read missing rows too: a transient 404 must never masquerade as a
    // successfully captured live key at the final inventory boundary.
    await collect(uncaptured);
  }
  if (catchupRounds === maxCatchupRounds) {
    finalRows = await client.list(); for (const row of finalRows) allListed.set(row.name, row);
  }
  const finalNames = new Set(finalRows.map(row => row.name)), nowSeconds = Date.now() / 1000;
  const uncapturedLive = finalRows.filter(row => !captured.has(row.name)
    && (row.expiration === undefined || row.expiration === null || row.expiration > nowSeconds));
  if (uncapturedLive.length) throw new Error('KV final inventory has uncaptured live keys; encrypted partial capture retained');
  const missingRecords = [...missing.values()].map(record => ({ ...record,
    status: record.expiration !== null && record.expiration <= nowSeconds ? 'expired-at-read'
      : !finalNames.has(record.key) ? 'deleted-during-capture' : 'expired-at-final-list' }));
  const proof = { format: 'pdd-real-kv-proof', schema: 1, runId, accountId, namespaceId,
    startedAt, completedAt: new Date().toISOString(), globalAtomic: false, inventoryComplete: true,
    initialListed: first.length, finalListed: finalRows.length, unionListed: allListed.size,
    captured: captured.size, missingAtRead: missingRecords.length,
    expiredDuringCapture: missingRecords.filter(record => record.status.startsWith('expired')).length,
    deletedDuringCapture: missingRecords.filter(record => record.status === 'deleted-during-capture').length,
    capturedNotInFinalList: [...captured.keys()].filter(key => !finalNames.has(key)).length,
    uncapturedLiveKeys: 0, bytes: totalBytes, rawValues, requests: client.requests ?? null,
    catchupRounds, batches: descriptors.length, productionWrites: 0 };
  const index = { format: 'pdd-real-kv-index', schema: 1, runId, accountId, namespaceId, proof,
    batches: descriptors.sort((a, b) => a.file.localeCompare(b.file)),
    initialKeys: first, finalKeys: finalRows, capturedKeys: [...captured].map(([key, metadata]) => ({ key, ...metadata })),
    missingKeys: missingRecords };
  const artifact = join(outputDir, 'index.jwe'); await writePrivateNew(artifact, await seal(index, credentials));
  progress('kv-complete'); return { artifact, proof };
}

export async function loadRealKV({ credentials, outputDir }) {
  checkedCredentials(credentials); outputDir = resolve(outputDir);
  const index = await unseal((await privateRead(join(outputDir, 'index.jwe'))).toString('utf8'), credentials);
  if (index?.format !== 'pdd-real-kv-index' || index.schema !== 1 || !Array.isArray(index.batches)
    || !Array.isArray(index.capturedKeys) || !Array.isArray(index.finalKeys) || !Array.isArray(index.missingKeys)
    || index.proof?.uncapturedLiveKeys !== 0 || index.proof?.inventoryComplete !== true
    || index.proof?.globalAtomic !== false || countUnique(index.batches.map(item => item.file)) !== index.batches.length) fail();
  const entries = [], seen = new Set(), expected = new Map(index.capturedKeys.map(row => [row.key, row]));
  if (expected.size !== index.capturedKeys.length) fail();
  for (const descriptor of index.batches) {
    if (!/^batch-\d{6}\.jwe$/.test(descriptor.file)) fail();
    const ciphertext = (await privateRead(join(outputDir, descriptor.file))).toString('utf8');
    if (sha(ciphertext) !== descriptor.sha256) fail();
    const batch = await unseal(ciphertext, credentials);
    if (sha(jsonBytes(batch)) !== descriptor.payloadSha256 || batch.format !== 'pdd-real-kv-batch' || batch.schema !== 1
      || batch.runId !== index.runId || batch.accountId !== index.accountId || batch.namespaceId !== index.namespaceId
      || !Array.isArray(batch.entries) || batch.entries.length !== descriptor.entryCount) fail();
    for (const entry of batch.entries) {
      if (typeof entry?.key !== 'string' || !entry.key.length || Buffer.byteLength(entry.key) > 512 || seen.has(entry.key)
        || typeof entry.valueBase64 !== 'string' || Buffer.from(entry.valueBase64, 'base64').toString('base64') !== entry.valueBase64
        || !expected.has(entry.key) || sha(Buffer.from(entry.valueBase64, 'base64')) !== expected.get(entry.key).sha256) fail();
      checkedMetadata(entry); seen.add(entry.key); entries.push(entry);
    }
  }
  if (entries.length !== index.proof.captured || seen.size !== expected.size
    || index.finalKeys.some(row => !seen.has(row.name)
      && !index.missingKeys.some(missing => missing.key === row.name && missing.status.startsWith('expired')))) fail();
  return { kvEntries: entries, inventoryProof: structuredClone(index.proof) };
}

async function main(args) {
  const [command, credentialsFile, outputDir, accountId, namespaceId] = args;
  const credentials = await readKVExportCredentials(credentialsFile);
  if (command === 'collect' && args.length === 5) {
    const result = await collectRealKV({ credentials, outputDir, accountId, namespaceId,
      onProgress: counts => console.log(JSON.stringify(counts)) });
    console.log(JSON.stringify(result)); return;
  }
  if (command === 'verify' && args.length === 3) {
    const { inventoryProof } = await loadRealKV({ credentials, outputDir }); console.log(JSON.stringify(inventoryProof)); return;
  }
  throw new Error('Usage: real_kv_export.mjs collect KEY OUTPUT ACCOUNT NAMESPACE | verify KEY OUTPUT');
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(() => { console.error('Encrypted KV export failed; no production write was performed.'); process.exitCode = 1; });
}
