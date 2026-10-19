import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { createClosedInventory, createClosedTarget, restoreClosedBundle, validateClosedBundle, readClosedObject, readClosedKV, inspectClosedTarget } from './closed_restore.mjs';
import { syntheticBackup, identities, denyNetwork } from '../../server/install-notifier/closed-backup-fixtures.mjs';
import { canonicalStringify } from '../../server/install-notifier/durable_backup.js';

test('offline restore preserves every raw value/object ID and quarantines alarms and deferred jobs', async () => denyNetwork(async counts => {
  const source = await syntheticBackup(), target = createClosedTarget();
  const inventory = await createClosedInventory(source.snapshots, { key: source.backupKey, kvEntries: source.kvEntries });
  const result = await restoreClosedBundle({ inventory, snapshots: source.snapshots, kvEntries: source.kvEntries }, target, { key: source.backupKey });
  assert.equal(result.length, 5);
  for (const [name, storage] of source.objects) {
    const restored = readClosedObject(target, identities[name]);
    assert.deepEqual(restored.entries, storage.data);
    assert.equal(restored.metadata.objectId, identities[name].objectId);
    assert.equal(restored.scheduledAlarm, null);
    // Mutating an inspection result cannot mutate the evidence.
    restored.entries.clear();
    assert.equal(readClosedObject(target, identities[name]).entries.size, storage.data.size);
  }
  assert.ok(result.find(x => x.metadata.objectId === identities.active.objectId).quarantinedKeys.length >= 3);
  assert.ok(result.some(x => x.archivedAlarm !== null));
  const kv = readClosedKV(target);
  assert.deepEqual([...kv.find(x => x.key === 'closed-raw-bytes').value], [0, 255, 128, 1]);
  assert.deepEqual(kv.find(x => x.key === 'closed-raw-bytes').metadata, { binary: true });
  const archivedSession = source.kvEntries.find(x => x.key.startsWith('auth_session:'));
  assert.equal(kv.find(x => x.key === archivedSession.key).expiration, archivedSession.expiration);
  assert.deepEqual(counts, { blocked: 0, providerMocks: 0, outgoing: 0 });
}));

test('tamper/missing inventory/duplicates/mixed runs reject before any write; same empty target can retry', async () => {
  const { snapshots, backupKey: key, kvEntries } = await syntheticBackup();
  const inventory = await createClosedInventory(snapshots, { key, kvEntries });
  const variants = [
    { inventory, snapshots: snapshots.slice(1), kvEntries },
    { inventory: { ...inventory, objectCount: 4 }, snapshots, kvEntries },
    { inventory: undefined, snapshots, kvEntries },
    { inventory, snapshots: [snapshots[0], snapshots[0], ...snapshots.slice(2)], kvEntries },
    { inventory, snapshots: snapshots.map((x, i) => i ? x : { ...x, entryCount: x.entryCount + 1 }), kvEntries },
    { inventory, snapshots: snapshots.map((x, i) => i ? x : { ...x, metadata: { ...x.metadata, runId: crypto.randomUUID() } }), kvEntries },
    { inventory, snapshots, kvEntries: kvEntries.slice(1) },
    { inventory, snapshots, kvEntries: kvEntries.map((x, i) => i ? x : { ...x, valueBase64: Buffer.from('tampered').toString('base64') }) },
  ];
  for (const bundle of variants) {
    const target = createClosedTarget();
    await assert.rejects(restoreClosedBundle(bundle, target, { key }));
    assert.deepEqual(inspectClosedTarget(target), []);
    await restoreClosedBundle({ inventory, snapshots, kvEntries }, target, { key });
    await assert.rejects(restoreClosedBundle({ inventory, snapshots, kvEntries }, target, { key }));
  }
});

test('only factory-owned fresh local targets accepted; arbitrary production-like bindings never invoked', async () => {
  const { snapshots, backupKey: key } = await syntheticBackup(), inventory = await createClosedInventory(snapshots, { key });
  let calls = 0;
  const remoteLike = { kind: 'in-process-closed-restore', version: 1,
    storage: { put() { calls++; }, transaction() { calls++; } },
    ACCOUNTS: { idFromName() { calls++; }, get() { calls++; } } };
  for (const target of [remoteLike, { ...createClosedTarget() }, null]) {
    await assert.rejects(restoreClosedBundle({ inventory, snapshots }, target, { key }));
  }
  assert.equal(calls, 0);
});

test('inventory HMAC is mandatory and binds membership/KV/provenance before any target mutation', async () => {
  const { snapshots, backupKey: key, kvEntries } = await syntheticBackup();
  const inventory = await createClosedInventory(snapshots, { key, kvEntries });
  const bundle = { inventory, snapshots, kvEntries }, target = createClosedTarget();
  await assert.rejects(restoreClosedBundle(bundle, target));
  await assert.rejects(restoreClosedBundle(bundle, target, { key: new Uint8Array(32) }));
  await assert.rejects(validateClosedBundle({ ...bundle, inventory: { ...inventory, authentication: undefined } }, { key }));
  await assert.rejects(validateClosedBundle({ ...bundle, inventory: { ...inventory,
    provenance: { kind: 'synthetic-local', globalAtomic: false, inventoryComplete: true } } }, { key }));
  assert.deepEqual(inspectClosedTarget(target), []);
  assert.equal((await validateClosedBundle(bundle, { key })).inventory.sha256, inventory.sha256);
  await restoreClosedBundle(bundle, target, { key });
});

test('mixed source versions/epochs fail even when snapshot hashes and signed inventory are recomputed', async () => {
  const { snapshots, backupKey: key, kvEntries } = await syntheticBackup();
  const original = await createClosedInventory(snapshots, { key, kvEntries });
  const digest = value => createHash('sha256').update(canonicalStringify(value)).digest('hex');
  for (const field of ['sourceVersion', 'accountEpoch']) {
    const mixed = structuredClone(snapshots), changed = mixed[3];
    changed.metadata[field] += '-different';
    const { sha256: ignoredHash, ...snapshotBody } = changed;
    changed.sha256 = digest(snapshotBody);
    await assert.rejects(createClosedInventory(mixed, { key, kvEntries }));
    const inventory = structuredClone(original);
    inventory.objects.find(entry => entry.objectId === changed.metadata.objectId).sha256 = changed.sha256;
    const { sha256: oldHash, authentication: oldAuth, ...inventoryBody } = inventory;
    inventory.sha256 = digest(inventoryBody);
    const { authentication, ...authenticated } = inventory;
    inventory.authentication.signature = createHmac('sha256', key).update('pdd-durable-inventory-v1\n')
      .update(canonicalStringify(authenticated)).digest('hex');
    const target = createClosedTarget();
    await assert.rejects(validateClosedBundle({ inventory, snapshots: mixed, kvEntries }, { key }));
    await assert.rejects(restoreClosedBundle({ inventory, snapshots: mixed, kvEntries }, target, { key }));
    assert.deepEqual(inspectClosedTarget(target), []);
  }
});

test('bundle rejects all extras, symbols, accessors and hidden properties; omitted KV normalizes to exact schema', async () => {
  const { snapshots, backupKey: key } = await syntheticBackup();
  const inventory = await createClosedInventory(snapshots, { key });
  const bundle = { inventory, snapshots, kvEntries: [] };
  const hidden = { ...bundle };
  Object.defineProperty(hidden, 'recipientPrivateJwk', { value: 'must not be retained' });
  const symbol = { ...bundle, [Symbol('private-key')]: 'must not be retained' };
  let accessorCalls = 0;
  const getter = { snapshots, kvEntries: [] };
  Object.defineProperty(getter, 'inventory', { enumerable: true, get() { accessorCalls++; return inventory; } });
  for (const input of [{ ...bundle, recipientPrivateJwk: 'must not be retained' }, hidden, symbol, getter]) {
    await assert.rejects(validateClosedBundle(input, { key }));
  }
  assert.equal(accessorCalls, 0);
  const normalized = await validateClosedBundle({ inventory, snapshots }, { key });
  assert.deepEqual(Object.keys(normalized).sort(), ['inventory', 'kvEntries', 'snapshots']);
  assert.deepEqual(normalized.kvEntries, []);
});
