// Offline rehearsal only. This module has no Worker route, namespace binding,
// credentials, DNS operation or network client. Original object IDs are labels;
// they are deliberately never converted with another namespace's idFromName().
import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { canonicalStringify, decodeValue, validateSnapshot } from '../../server/install-notifier/durable_backup.js';

const targets = new WeakMap();
const digest = value => createHash('sha256').update(canonicalStringify(value)).digest('hex');
const locator = value => [value.className, value.namespaceId, value.objectId].join(':');
const fail = () => { throw new Error('Closed restore validation failed'); };
const exactKeys = (value, keys) => value && typeof value === 'object'
  && [Object.prototype, null].includes(Object.getPrototypeOf(value))
  && !Object.getOwnPropertySymbols(value).length
  && Object.getOwnPropertyNames(value).sort().join(',') === [...keys].sort().join(',')
  && keys.every(key => { const descriptor = Object.getOwnPropertyDescriptor(value, key);
    return descriptor?.enumerable && Object.hasOwn(descriptor, 'value'); });
const checkedKey = key => { if (!(key instanceof Uint8Array) || key.byteLength !== 32) fail(); return key; };
const signature = (value, key) => createHmac('sha256', checkedKey(key)).update('pdd-durable-inventory-v1\n')
  .update(canonicalStringify(value)).digest('hex');

function validateKV(kvEntries) {
  if (!Array.isArray(kvEntries)) fail();
  const keys = new Set();
  for (const entry of kvEntries) {
    if (!exactKeys(entry, ['key', 'valueBase64', 'expiration', 'metadata']) || typeof entry.key !== 'string'
      || !entry.key.length || Buffer.byteLength(entry.key) > 512 || keys.has(entry.key)
      || typeof entry.valueBase64 !== 'string' || entry.valueBase64.length > Math.ceil(25 * 1024 * 1024 / 3) * 4
      || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(entry.valueBase64)
      || Buffer.from(entry.valueBase64, 'base64').toString('base64') !== entry.valueBase64
      || (entry.expiration !== null
        && (!Number.isSafeInteger(entry.expiration) || entry.expiration < 0))) fail();
    if (entry.metadata !== null && (typeof entry.metadata !== 'object' || Array.isArray(entry.metadata))) fail();
    canonicalStringify(entry.metadata);
    keys.add(entry.key);
  }
  return kvEntries;
}

// KV values preserve raw bytes as canonical base64; metadata is JSON or null.
// Expiration is the original absolute Unix seconds, never a newly started TTL.
export function encodeClosedKVEntry({ key, value, expiration = null, metadata = null }) {
  if (typeof value !== 'string' && !(value instanceof ArrayBuffer) && !(value instanceof Uint8Array)) fail();
  const entry = { key, valueBase64: Buffer.from(value).toString('base64'), expiration, metadata: structuredClone(metadata) };
  validateKV([entry]); return entry;
}

function validateProvenance(provenance) {
  if (!exactKeys(provenance, ['kind', 'globalAtomic', 'inventoryComplete'])
    || !['synthetic-local', 'collected-nonatomic'].includes(provenance.kind)
    || provenance.globalAtomic !== false || typeof provenance.inventoryComplete !== 'boolean'
    || (provenance.kind === 'synthetic-local' && provenance.inventoryComplete !== false)) fail();
}

export function createClosedTarget() {
  const target = Object.freeze({ kind: 'in-process-closed-restore', version: 1 });
  targets.set(target, { objects: new Map(), kvEntries: [], busy: false, restored: false });
  return target;
}

export async function createClosedInventory(snapshots, { key, kvEntries = [],
  provenance = { kind: 'synthetic-local', globalAtomic: false, inventoryComplete: false } } = {}) {
  checkedKey(key);
  validateProvenance(provenance);
  snapshots = structuredClone(snapshots);
  kvEntries = validateKV(structuredClone(kvEntries));
  if (!Array.isArray(snapshots) || !snapshots.length) fail();
  const objects = [];
  for (const snapshot of snapshots) {
    await validateSnapshot(snapshot);
    const { className, namespaceId, objectId, runId, sourceVersion, accountEpoch } = snapshot.metadata;
    const first = snapshots[0].metadata;
    if (runId !== first.runId || sourceVersion !== first.sourceVersion || accountEpoch !== first.accountEpoch) fail();
    objects.push({ className, namespaceId, objectId, sha256: snapshot.sha256 });
  }
  objects.sort((a, b) => locator(a).localeCompare(locator(b)));
  if (new Set(objects.map(locator)).size !== objects.length) fail();
  const inventory = { format: 'pdd-durable-inventory', schema: 1,
    runId: snapshots[0].metadata.runId, objectCount: objects.length, objects,
    kv: { entryCount: kvEntries.length, sha256: digest(kvEntries) }, provenance: structuredClone(provenance) };
  const hashed = { ...inventory, sha256: digest(inventory) };
  return { ...hashed, authentication: { alg: 'HS256', signature: signature(hashed, key) } };
}

// The caller must supply the independently retained inventory. Rebuilding it
// from whatever files survived cannot establish backup completeness. SHA256
// checks integrity; mandatory HMAC authenticates the complete inventory and KV
// list. The collector also encrypts the complete archive before it is retained.
export async function validateClosedBundle(bundle, { key } = {}) {
  checkedKey(key);
  // Check the original descriptors too: structuredClone would silently drop
  // symbols/non-enumerable extras and evaluate accessors before validation.
  const hasKV = bundle && Object.hasOwn(bundle, 'kvEntries');
  if (!exactKeys(bundle, hasKV ? ['inventory', 'snapshots', 'kvEntries'] : ['inventory', 'snapshots'])) fail();
  const cloned = structuredClone(bundle);
  if (cloned.kvEntries === undefined) cloned.kvEntries = [];
  if (!exactKeys(cloned, ['inventory', 'snapshots', 'kvEntries'])) fail();
  const { inventory, snapshots, kvEntries } = cloned;
  if (!exactKeys(inventory, ['format', 'schema', 'runId', 'objectCount', 'objects', 'kv', 'provenance', 'sha256', 'authentication'])
    || inventory.format !== 'pdd-durable-inventory' || inventory.schema !== 1
    || !Array.isArray(snapshots) || !Array.isArray(inventory.objects)
    || !Number.isSafeInteger(inventory.objectCount) || inventory.objectCount < 1
    || inventory.objectCount !== inventory.objects.length
    || inventory.objectCount !== snapshots.length) fail();
  const { authentication, ...authenticated } = inventory;
  if (!exactKeys(authentication, ['alg', 'signature']) || authentication.alg !== 'HS256'
    || typeof authentication.signature !== 'string' || !/^[a-f0-9]{64}$/.test(authentication.signature)
    || !timingSafeEqual(Buffer.from(authentication.signature, 'hex'), Buffer.from(signature(authenticated, key), 'hex'))) fail();
  const { sha256, ...unsigned } = authenticated;
  if (typeof sha256 !== 'string' || sha256 !== digest(unsigned)) fail();
  validateProvenance(inventory.provenance);
  validateKV(kvEntries);
  if (!exactKeys(inventory.kv, ['entryCount', 'sha256']) || inventory.kv.entryCount !== kvEntries.length
    || inventory.kv.sha256 !== digest(kvEntries)) fail();
  const listed = new Map();
  for (const entry of inventory.objects) {
    if (!exactKeys(entry, ['className', 'namespaceId', 'objectId', 'sha256'])
      || listed.has(locator(entry))) fail();
    listed.set(locator(entry), entry);
  }
  const seen = new Set();
  for (const snapshot of snapshots) {
    await validateSnapshot(snapshot);
    const id = locator(snapshot.metadata), expected = listed.get(id), first = snapshots[0].metadata;
    if (!expected || seen.has(id) || expected.sha256 !== snapshot.sha256
      || snapshot.metadata.runId !== inventory.runId
      || snapshot.metadata.sourceVersion !== first.sourceVersion
      || snapshot.metadata.accountEpoch !== first.accountEpoch) fail();
    seen.add(id);
  }
  if (seen.size !== listed.size) fail();
  return { inventory, snapshots, kvEntries };
}

export async function restoreClosedBundle(bundle, target, { key } = {}) {
  const state = targets.get(target);
  if (!state || state.busy || state.restored || state.objects.size) fail();
  state.busy = true;
  try {
    // Validate/decode everything before publishing a single staged value.
    const { snapshots, kvEntries } = await validateClosedBundle(bundle, { key });
    const staged = new Map();
    for (const snapshot of snapshots) {
      const entries = new Map(snapshot.entries.map(({ key, value }) => [key, decodeValue(value)]));
      staged.set(locator(snapshot.metadata), { metadata: structuredClone(snapshot.metadata), entries });
    }
    const stagedKV = kvEntries.map(({ key, valueBase64, expiration, metadata }) => ({
      key, value: Uint8Array.from(Buffer.from(valueBase64, 'base64')), expiration, metadata: structuredClone(metadata),
    }));
    state.objects = staged;
    state.kvEntries = stagedKV;
    state.restored = true;
    return inspectClosedTarget(target);
  } finally { state.busy = false; }
}

export function readClosedKV(target) {
  const state = targets.get(target);
  if (!state) fail();
  return structuredClone(state.kvEntries);
}

export function inspectClosedTarget(target) {
  const state = targets.get(target);
  if (!state) fail();
  return [...state.objects.values()].map(({ metadata, entries }) => ({
    metadata: structuredClone(metadata), entryCount: entries.size,
    scheduledAlarm: null, archivedAlarm: metadata.alarm,
    quarantinedKeys: [...entries.keys()].filter(key => /^(effect:|projection:|index:|out:)/.test(key)),
  }));
}

// Copies only: a handler under test cannot mutate the restored evidence.
export function readClosedObject(target, identity) {
  const state = targets.get(target), stored = state?.objects.get(locator(identity));
  if (!stored) fail();
  return { metadata: structuredClone(stored.metadata), entries: structuredClone(stored.entries), scheduledAlarm: null };
}
