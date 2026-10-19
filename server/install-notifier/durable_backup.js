// Raw, read-only Durable Object snapshots. This route is disabled by default;
// ordinary account reads must never be used here because they can import KV,
// expire documents, flush outboxes, or write payment indexes.
import { CompactEncrypt, importJWK } from 'jose';

export const BACKUP_PATH = '/_backup/v1/export';
export const BACKUP_LIMITS = Object.freeze({
  pageSize: 128, maxEntries: 100000, maxBytes: 64 * 1024 * 1024,
  maxValueBytes: 1024 * 1024, maxRequestBytes: 16384,
  maxDepth: 64, maxNodes: 1000000, maxEnableWindowMs: 60 * 60 * 1000,
  maxClockSkewMs: 60000,
});
const utf8 = new TextEncoder();
const forbidden = new Set(['__proto__', 'prototype', 'constructor']);
const classPattern = /^[A-Za-z][A-Za-z0-9]{0,79}$/;
const namespacePattern = /^[a-f0-9]{32}$/;
const objectPattern = /^[a-f0-9]{64}$/;
const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const fail = () => { throw new Error('Invalid durable backup'); };
const own = (value, key) => value !== null && value !== undefined && Object.prototype.hasOwnProperty.call(value, key);
const plain = value => value !== null && typeof value === 'object' && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
const exact = (value, keys) => {
  if (!plain(value) || Object.getOwnPropertySymbols(value).length || Object.getOwnPropertyNames(value).length !== keys.length || keys.some(key => !own(value, key) || !own(Object.getOwnPropertyDescriptor(value, key), 'value') || !Object.getOwnPropertyDescriptor(value, key).enumerable)) fail();
};
function checkedString(value, max, allowEmpty = false) {
  if (typeof value !== 'string' || (!allowEmpty && !value.length) || value.length > max) fail();
  return value;
}
function bytesToBase64(bytes, url = false) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  const encoded = btoa(binary);
  return url ? encoded.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') : encoded;
}
function base64ToBytes(value, url = false, maxBytes = BACKUP_LIMITS.maxValueBytes) {
  checkedString(value, Math.ceil(maxBytes * 4 / 3) + 4, true);
  if (url ? !/^[A-Za-z0-9_-]*$/.test(value) : !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) fail();
  let raw;
  try { raw = atob(url ? value.replace(/-/g, '+').replace(/_/g, '/') : value); } catch { fail(); }
  if (raw.length > maxBytes) fail();
  const bytes = Uint8Array.from(raw, char => char.charCodeAt(0));
  if (bytesToBase64(bytes, url) !== value) fail();
  return bytes;
}
function compareKeys(a, b) {
  const left = utf8.encode(a), right = utf8.encode(b);
  for (let i = 0; i < Math.min(left.length, right.length); i++) if (left[i] !== right[i]) return left[i] - right[i];
  return left.length - right.length;
}
function checkKey(key) {
  checkedString(key, 2048);
  if (utf8.encode(key).length > 2048 || /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(key)) fail();
}

// The codec is explicit instead of JSON.stringify(raw): undefined properties,
// sparse arrays, big integers, signed zero, and binary values must survive.
// Unsupported prototypes, accessors, shared references, and cycles fail closed.
const typedArrays = Object.freeze(Object.fromEntries([
  'Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array',
  'Int32Array', 'Uint32Array', 'Float32Array', 'Float64Array', 'BigInt64Array', 'BigUint64Array',
].filter(name => typeof globalThis[name] === 'function').map(name => [name, globalThis[name]])));
export function encodeValue(value) {
  const seen = new WeakSet(); let nodes = 0;
  function encode(current, depth) {
    if (++nodes > BACKUP_LIMITS.maxNodes || depth > BACKUP_LIMITS.maxDepth) fail();
    if (current === undefined) return { t: 'undefined' };
    if (current === null) return { t: 'null' };
    if (typeof current === 'boolean') return { t: 'boolean', v: current };
    if (typeof current === 'string') return { t: 'string', v: current };
    if (typeof current === 'number') return { t: 'number', v: Number.isNaN(current) ? 'NaN' : current === Infinity ? 'Infinity' : current === -Infinity ? '-Infinity' : Object.is(current, -0) ? '-0' : current };
    if (typeof current === 'bigint') return { t: 'bigint', v: String(current) };
    if (typeof current !== 'object' || seen.has(current) || Object.getOwnPropertySymbols(current).length) fail();
    seen.add(current);
    if (current instanceof ArrayBuffer) {
      if (Object.getPrototypeOf(current) !== ArrayBuffer.prototype || Object.getOwnPropertyNames(current).length || current.resizable || current.byteLength > BACKUP_LIMITS.maxValueBytes) fail();
      return { t: 'arraybuffer', v: bytesToBase64(new Uint8Array(current)) };
    }
    if (ArrayBuffer.isView(current)) {
      const name = current instanceof DataView ? 'DataView' : Object.keys(typedArrays).find(key => Object.getPrototypeOf(current) === typedArrays[key].prototype);
      if (!name || (name === 'DataView' && Object.getPrototypeOf(current) !== DataView.prototype) || !(current.buffer instanceof ArrayBuffer) || current.buffer.resizable || current.buffer.byteLength > BACKUP_LIMITS.maxValueBytes || seen.has(current.buffer)) fail();
      seen.add(current.buffer);
      // Named properties on views would be lost by a simple binary round trip.
      for (const key of Object.getOwnPropertyNames(current)) if (name === 'DataView' || !/^(0|[1-9][0-9]*)$/.test(key)) fail();
      return { t: 'view', name, offset: current.byteOffset, length: name === 'DataView' ? current.byteLength : current.length, v: bytesToBase64(new Uint8Array(current.buffer)) };
    }
    if (current instanceof Date) {
      if (Object.getPrototypeOf(current) !== Date.prototype || Object.getOwnPropertyNames(current).length || !Number.isFinite(current.getTime())) fail();
      return { t: 'date', v: current.toISOString() };
    }
    if (!Array.isArray(current) && !plain(current)) fail();
    if (Array.isArray(current) && (Object.getPrototypeOf(current) !== Array.prototype || current.length > BACKUP_LIMITS.maxNodes)) fail();
    const properties = [];
    for (const key of Object.getOwnPropertyNames(current).sort()) {
      if (Array.isArray(current) && key === 'length') continue;
      if (forbidden.has(key)) fail();
      const descriptor = Object.getOwnPropertyDescriptor(current, key);
      if (!own(descriptor, 'value') || !descriptor.enumerable || !descriptor.writable || !descriptor.configurable) fail();
      properties.push([key, encode(descriptor.value, depth + 1)]);
    }
    return Array.isArray(current)
      ? { t: 'array', length: current.length, v: properties }
      : { t: 'object', nullPrototype: Object.getPrototypeOf(current) === null, v: properties };
  }
  const result = encode(value, 0);
  if (utf8.encode(canonicalStringify(result)).length > BACKUP_LIMITS.maxValueBytes) fail();
  return result;
}

export function decodeValue(value) {
  let nodes = 0;
  function decode(current, depth) {
    if (++nodes > BACKUP_LIMITS.maxNodes || depth > BACKUP_LIMITS.maxDepth || !plain(current) || typeof current.t !== 'string') fail();
    switch (current.t) {
      case 'undefined': exact(current, ['t']); return undefined;
      case 'null': exact(current, ['t']); return null;
      case 'boolean': exact(current, ['t', 'v']); if (typeof current.v !== 'boolean') fail(); return current.v;
      case 'string': exact(current, ['t', 'v']); if (typeof current.v !== 'string') fail(); return current.v;
      case 'number': {
        exact(current, ['t', 'v']);
        if (typeof current.v === 'number' && Number.isFinite(current.v) && !Object.is(current.v, -0)) return current.v;
        if (current.v === 'NaN') return NaN;
        if (current.v === 'Infinity') return Infinity;
        if (current.v === '-Infinity') return -Infinity;
        if (current.v === '-0') return -0;
        fail(); break;
      }
      case 'bigint': exact(current, ['t', 'v']); if (typeof current.v !== 'string' || !/^(0|-?[1-9][0-9]*)$/.test(current.v)) fail(); return BigInt(current.v);
      case 'arraybuffer': exact(current, ['t', 'v']); return base64ToBytes(current.v).buffer;
      case 'view': {
        exact(current, ['t', 'name', 'offset', 'length', 'v']);
        if (!Number.isSafeInteger(current.offset) || current.offset < 0 || !Number.isSafeInteger(current.length) || current.length < 0) fail();
        const buffer = base64ToBytes(current.v).buffer;
        try {
          if (current.name === 'DataView') return new DataView(buffer, current.offset, current.length);
          if (!own(typedArrays, current.name)) fail();
          return new typedArrays[current.name](buffer, current.offset, current.length);
        } catch { fail(); }
        break;
      }
      case 'date': {
        exact(current, ['t', 'v']); const date = new Date(current.v);
        if (typeof current.v !== 'string' || !Number.isFinite(date.getTime()) || date.toISOString() !== current.v) fail();
        return date;
      }
      case 'object': case 'array': {
        const array = current.t === 'array';
        exact(current, array ? ['t', 'length', 'v'] : ['t', 'nullPrototype', 'v']);
        if (!Array.isArray(current.v) || (array ? !Number.isSafeInteger(current.length) || current.length < 0 || current.length > BACKUP_LIMITS.maxNodes : typeof current.nullPrototype !== 'boolean')) fail();
        const result = array ? new Array(current.length) : Object.create(current.nullPrototype ? null : Object.prototype);
        let previous = null;
        for (const pair of current.v) {
          if (!Array.isArray(pair) || pair.length !== 2 || typeof pair[0] !== 'string' || forbidden.has(pair[0]) || (previous !== null && pair[0] <= previous)) fail();
          const key = pair[0]; previous = key;
          if (array && (key === 'length' || /^(0|[1-9][0-9]*)$/.test(key) && Number(key) < 0xffffffff && Number(key) >= current.length)) fail();
          Object.defineProperty(result, key, { value: decode(pair[1], depth + 1), enumerable: true, writable: true, configurable: true });
        }
        return result;
      }
      default: fail();
    }
  }
  // Check byte size before potentially expanding a tagged input.
  if (utf8.encode(canonicalStringify(value)).length > BACKUP_LIMITS.maxValueBytes) fail();
  return decode(value, 0);
}

export function canonicalStringify(value) {
  const seen = new WeakSet();
  function canonical(current, depth) {
    if (depth > BACKUP_LIMITS.maxDepth + 12) fail();
    if (current === null || typeof current === 'string' || typeof current === 'boolean') return JSON.stringify(current);
    if (typeof current === 'number' && Number.isFinite(current) && !Object.is(current, -0)) return JSON.stringify(current);
    if (typeof current !== 'object' || seen.has(current)) fail();
    seen.add(current);
    let result;
    if (Array.isArray(current)) {
      if (Object.getOwnPropertySymbols(current).length || Object.getOwnPropertyNames(current).length !== current.length + 1 || Object.keys(current).length !== current.length) fail();
      for (let index = 0; index < current.length; index++) if (!own(Object.getOwnPropertyDescriptor(current, String(index)), 'value')) fail();
      result = '[' + current.map(child => canonical(child, depth + 1)).join(',') + ']';
    } else {
      if (!plain(current) || Object.getOwnPropertySymbols(current).length) fail();
      result = '{' + Object.getOwnPropertyNames(current).sort().map(key => {
        if (forbidden.has(key) || !own(Object.getOwnPropertyDescriptor(current, key), 'value') || !Object.getOwnPropertyDescriptor(current, key).enumerable) fail();
        return JSON.stringify(key) + ':' + canonical(current[key], depth + 1);
      }).join(',') + '}';
    }
    seen.delete(current);
    return result;
  }
  return canonical(value, 0);
}
async function hash(payload) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', utf8.encode(canonicalStringify(payload)))), byte => byte.toString(16).padStart(2, '0')).join('');
}
function checkMetadata(metadata) {
  exact(metadata, ['className', 'namespaceId', 'objectId', 'runId', 'sourceVersion', 'accountEpoch', 'capturedAt', 'alarm']);
  if (typeof metadata.className !== 'string' || !classPattern.test(metadata.className) || typeof metadata.namespaceId !== 'string' || !namespacePattern.test(metadata.namespaceId) || typeof metadata.objectId !== 'string' || !objectPattern.test(metadata.objectId) || typeof metadata.runId !== 'string' || !uuidPattern.test(metadata.runId)) fail();
  checkedString(metadata.sourceVersion, 128); checkedString(metadata.accountEpoch, 64);
  if (typeof metadata.capturedAt !== 'string' || !Number.isFinite(Date.parse(metadata.capturedAt)) || new Date(metadata.capturedAt).toISOString() !== metadata.capturedAt || metadata.alarm !== null && (!Number.isSafeInteger(metadata.alarm) || metadata.alarm < 0)) fail();
}
function validateChunks(entries, className) {
  if (className !== 'AccountState') return;
  const records = new Map(entries.map(({ key, value }) => [key, decodeValue(value)]));
  const expected = new Set();
  for (const [key, record] of records) if (key.startsWith('doc:') && record && own(record, 'chunks')) {
    if (!plain(record) || record.key !== key.slice(4) || !Number.isSafeInteger(record.chunks) || record.chunks < 1 || record.chunks > BACKUP_LIMITS.maxEntries || own(record, 'value') && record.value !== undefined) fail();
    const parts = []; let size = 0;
    for (let index = 0; index < record.chunks; index++) {
      const chunkKey = 'chunk:' + record.key + ':' + index;
      if (!records.has(chunkKey)) fail();
      expected.add(chunkKey);
      const bytes = base64ToBytes(records.get(chunkKey), false, 49152);
      if (!bytes.length || index < record.chunks - 1 && bytes.length !== 49152) fail();
      parts.push(bytes); size += bytes.length;
      if (size > BACKUP_LIMITS.maxBytes) fail();
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    try { new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { fail(); }
  }
  for (const key of records.keys()) if (key.startsWith('chunk:') && !expected.has(key)) fail();
}
export async function validateSnapshot(snapshot) {
  exact(snapshot, ['format', 'schema', 'metadata', 'entries', 'entryCount', 'sha256']);
  if (snapshot.format !== 'pdd-durable-backup' || snapshot.schema !== 1 || !Array.isArray(snapshot.entries) || snapshot.entries.length > BACKUP_LIMITS.maxEntries || snapshot.entryCount !== snapshot.entries.length || typeof snapshot.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(snapshot.sha256)) fail();
  checkMetadata(snapshot.metadata);
  let previous = null;
  for (const entry of snapshot.entries) {
    exact(entry, ['key', 'value']); checkKey(entry.key);
    if (previous !== null && compareKeys(previous, entry.key) >= 0) fail();
    previous = entry.key; decodeValue(entry.value);
  }
  const { sha256, ...payload } = snapshot;
  if (utf8.encode(canonicalStringify(payload)).length > BACKUP_LIMITS.maxBytes || await hash(payload) !== sha256) fail();
  validateChunks(snapshot.entries, snapshot.metadata.className);
  return snapshot;
}
export async function snapshotStorage(state, metadata) {
  if (!state?.storage || typeof state.storage.transaction !== 'function' || state.id && state.id.toString() !== metadata.objectId) fail();
  const snapshot = await state.storage.transaction(async txn => {
    const alarmStorage = typeof txn.getAlarm === 'function' ? txn : state.storage;
    if (typeof alarmStorage.getAlarm !== 'function') fail();
    const entries = []; let previous = null, totalBytes = 0;
    for (;;) {
      const options = { limit: BACKUP_LIMITS.pageSize };
      if (previous !== null) options.startAfter = previous;
      const page = await txn.list(options);
      if (!(page instanceof Map) || page.size > BACKUP_LIMITS.pageSize) fail();
      for (const [key, value] of page) {
        checkKey(key);
        if (previous !== null && compareKeys(previous, key) >= 0) fail();
        previous = key;
        const entry = { key, value: encodeValue(value) };
        totalBytes += utf8.encode(canonicalStringify(entry)).length;
        if (entries.length >= BACKUP_LIMITS.maxEntries || totalBytes > BACKUP_LIMITS.maxBytes) fail();
        entries.push(entry);
      }
      if (page.size < BACKUP_LIMITS.pageSize) break;
    }
    // The SQLite transaction also covers direct storage operations. The
    // deprecated transaction facade may omit getAlarm in some runtimes.
    const alarm = await alarmStorage.getAlarm();
    const payload = { format: 'pdd-durable-backup', schema: 1, metadata: { ...metadata, capturedAt: new Date().toISOString(), alarm: alarm ?? null }, entries, entryCount: entries.length };
    checkMetadata(payload.metadata);
    return { ...payload, sha256: await hash(payload) };
  });
  return validateSnapshot(snapshot);
}

export function isBackupRequest(request) {
  try { const path = new URL(request.url).pathname; return path === '/_backup' || path.startsWith('/_backup/'); } catch { return false; }
}
export async function backupHmac(secretBase64Url, message) {
  const secret = base64ToBytes(secretBase64Url, true, 256);
  if (secret.length < 32 || typeof message !== 'string') fail();
  const key = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return bytesToBase64(new Uint8Array(await crypto.subtle.sign('HMAC', key, utf8.encode(message))), true);
}
export async function verifyBackupHmac(secretBase64Url, message, signatureBase64Url) {
  try {
    const secret = base64ToBytes(secretBase64Url, true, 256), signature = base64ToBytes(signatureBase64Url, true, 32);
    if (secret.length < 32 || signature.length !== 32 || typeof message !== 'string') return false;
    const key = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
    return crypto.subtle.verify('HMAC', key, signature, utf8.encode(message));
  } catch { return false; }
}
async function requestBody(request) {
  const declared = request.headers.get('content-length');
  if (declared !== null && (!/^[0-9]+$/.test(declared) || Number(declared) > BACKUP_LIMITS.maxRequestBytes)) fail();
  if (!request.body) fail();
  const reader = request.body.getReader(), parts = []; let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      length += value.byteLength;
      if (length > BACKUP_LIMITS.maxRequestBytes) { await reader.cancel(); fail(); }
      parts.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.length; }
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { fail(); }
}
function checkRecipient(jwk) {
  if (!plain(jwk) || Object.keys(jwk).some(key => !['kty', 'n', 'e', 'kid', 'alg', 'use', 'key_ops'].includes(key)) || jwk.kty !== 'RSA') fail();
  const modulus = base64ToBytes(jwk.n, true, 1024), exponent = base64ToBytes(jwk.e, true, 8);
  if (modulus.length < 256 || modulus.length === 256 && modulus[0] < 128 || !modulus[0] || !exponent.length || jwk.alg && jwk.alg !== 'RSA-OAEP-256' || jwk.use && jwk.use !== 'enc' || jwk.kid !== undefined && (typeof jwk.kid !== 'string' || jwk.kid.length > 128)) fail();
  if (jwk.key_ops !== undefined && (!Array.isArray(jwk.key_ops) || !jwk.key_ops.length || jwk.key_ops.some(operation => !['encrypt', 'wrapKey'].includes(operation)))) fail();
}
export async function handleBackupExport(request, { state, env, className }) {
  const headers = { 'Cache-Control': 'no-store, private', 'Pragma': 'no-cache', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
  try {
    const now = Date.now(), until = Date.parse(env.DURABLE_BACKUP_UNTIL || '');
    if (env.DURABLE_BACKUP_ENABLED !== 'true' || !Number.isFinite(until) || until <= now || until - now > BACKUP_LIMITS.maxEnableWindowMs) fail();
    const url = new URL(request.url);
    if (request.method !== 'POST' || url.pathname !== BACKUP_PATH || url.search || !classPattern.test(className)) fail();
    const secret = base64ToBytes(env.DURABLE_BACKUP_HMAC_SECRET, true, 256);
    if (secret.length < 32) fail();
    const signature = base64ToBytes(request.headers.get('x-backup-signature'), true, 32);
    if (signature.length !== 32) fail();
    const raw = await requestBody(request);
    const signingKey = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
    if (!await crypto.subtle.verify('HMAC', signingKey, signature, utf8.encode(request.method + '\n' + url.pathname + '\n' + raw))) fail();
    const body = JSON.parse(raw);
    exact(body, ['format', 'runId', 'className', 'namespaceId', 'objectId', 'sourceVersion', 'accountEpoch', 'issuedAt', 'nonce', 'recipientJwk']);
    if (body.format !== 1 || body.className !== className || typeof body.namespaceId !== 'string' || !namespacePattern.test(body.namespaceId) || typeof body.objectId !== 'string' || !objectPattern.test(body.objectId) || typeof body.runId !== 'string' || !uuidPattern.test(body.runId) || !Number.isSafeInteger(body.issuedAt) || Math.abs(now - body.issuedAt) > BACKUP_LIMITS.maxClockSkewMs || !state?.id || state.id.toString() !== body.objectId) fail();
    checkedString(body.sourceVersion, 128); checkedString(body.accountEpoch, 64);
    if (body.sourceVersion !== env.DURABLE_BACKUP_SOURCE_VERSION || body.accountEpoch !== String(env.ACCOUNT_STATE_EPOCH || '1')) fail();
    if (base64ToBytes(body.nonce, true, 128).length < 16) fail();
    const namespaceIds = JSON.parse(env.DURABLE_BACKUP_NAMESPACE_IDS || 'null');
    if (!plain(namespaceIds) || !own(namespaceIds, className) || namespaceIds[className] !== body.namespaceId) fail();
    checkRecipient(body.recipientJwk);
    const recipient = await importJWK(body.recipientJwk, 'RSA-OAEP-256');
    const snapshot = await snapshotStorage(state, {
      className, namespaceId: body.namespaceId, objectId: body.objectId, runId: body.runId,
      sourceVersion: env.DURABLE_BACKUP_SOURCE_VERSION, accountEpoch: String(env.ACCOUNT_STATE_EPOCH || '1'),
    });
    const ciphertext = await new CompactEncrypt(utf8.encode(canonicalStringify(snapshot)))
      .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-durable-backup+jwe' }).encrypt(recipient);
    const responseSignature = await backupHmac(env.DURABLE_BACKUP_HMAC_SECRET, 'response\n' + body.nonce + '\n' + ciphertext);
    return new Response(ciphertext, { status: 200, headers: { ...headers, 'Content-Type': 'application/jose', 'X-Backup-Response-Signature': responseSignature } });
  } catch {
    // Neither authentication failures nor corrupt storage reveal account names,
    // identifiers, counts, tokens, or exception text in HTTP bodies or logs.
    return Response.json({ error: 'Backup unavailable' }, { status: 404, headers });
  }
}
