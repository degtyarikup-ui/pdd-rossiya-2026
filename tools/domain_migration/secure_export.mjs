#!/usr/bin/env node
// Closed rehearsal collector. No production endpoint or remote restore support.
import { generateKeyPairSync, randomBytes, randomUUID, createPrivateKey, createPublicKey } from 'node:crypto';
import { constants } from 'node:fs';
import { link, open, unlink } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { basename, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { BACKUP_PATH, BACKUP_LIMITS, backupHmac, verifyBackupHmac, canonicalStringify, validateSnapshot } from '../../server/install-notifier/durable_backup.js';
import { createClosedInventory, validateClosedBundle, createClosedTarget, restoreClosedBundle, inspectClosedTarget } from './closed_restore.mjs';

const requireServer = createRequire(new URL('../../server/install-notifier/package.json', import.meta.url));
const { CompactEncrypt, compactDecrypt, importJWK } = await import(requireServer.resolve('jose'));
export const BACKUP_CLASSES = Object.freeze(['AccountState', 'PurchaseClaims', 'TrafficState', 'StatsBuffer', 'TelegramQueue', 'NotificationsState', 'SupportThread', 'TelegramAuthState', 'AiQuotaState']);
const fail = () => { throw new Error('Closed export validation failed'); };
const utf8 = new TextEncoder();
const decode = bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes);
const locator = object => [object.className, object.namespaceId, object.objectId].join(':');

export function createExportCredentials() {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 3072 });
  return { format: 'pdd-closed-export-key', schema: 1, hmacSecret: randomBytes(32).toString('base64url'),
    recipientPrivateJwk: privateKey.export({ format: 'jwk' }) };
}
function checkedCredentials(credentials) {
  if (credentials?.format !== 'pdd-closed-export-key' || credentials.schema !== 1
    || typeof credentials.hmacSecret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(credentials.hmacSecret)
    || Buffer.from(credentials.hmacSecret, 'base64url').toString('base64url') !== credentials.hmacSecret) fail();
  try {
    const privateKey = createPrivateKey({ key: credentials.recipientPrivateJwk, format: 'jwk' });
    if (privateKey.asymmetricKeyType !== 'rsa' || privateKey.asymmetricKeyDetails.modulusLength < 2048) fail();
    return { publicJwk: createPublicKey(privateKey).export({ format: 'jwk' }), key: Buffer.from(credentials.hmacSecret, 'base64url') };
  } catch { fail(); }
}
export function checkedLoopbackEndpoint(endpoint) {
  let url; try { url = new URL(endpoint); } catch { fail(); }
  // Numeric loopback avoids DNS rebinding and accidental use of a public host.
  if (url.protocol !== 'http:' || !['127.0.0.1', '[::1]'].includes(url.hostname)
    || url.username || url.password || url.pathname !== BACKUP_PATH || url.search || url.hash) fail();
  return url.href;
}
function checkedObjects(objects) {
  if (!Array.isArray(objects) || !objects.length || objects.length > 100000) fail();
  const seen = new Set();
  for (const object of objects) {
    if (!object || Object.keys(object).sort().join(',') !== 'className,namespaceId,objectId'
      || !BACKUP_CLASSES.includes(object.className) || !/^[a-f0-9]{32}$/.test(object.namespaceId)
      || !/^[a-f0-9]{64}$/.test(object.objectId) || seen.has(locator(object))) fail();
    seen.add(locator(object));
  }
}
async function boundedText(response, limit) {
  if (!response.body) fail();
  const reader = response.body.getReader(), chunks = []; let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); fail(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return decode(Buffer.concat(chunks, size));
}

export async function exportClosedObject({ endpoint, object, runId, sourceVersion, accountEpoch, credentials, fetchImpl = fetch }) {
  endpoint = checkedLoopbackEndpoint(endpoint); checkedObjects([object]);
  const { publicJwk } = checkedCredentials(credentials);
  const body = { format: 1, runId, ...object, sourceVersion, accountEpoch, issuedAt: Date.now(),
    nonce: randomBytes(24).toString('base64url'), recipientJwk: publicJwk };
  const raw = canonicalStringify(body);
  const signature = await backupHmac(credentials.hmacSecret, 'POST\n' + BACKUP_PATH + '\n' + raw);
  const response = await fetchImpl(endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
    headers: { 'content-type': 'application/json', 'x-backup-signature': signature }, body: raw });
  if (response.status !== 200 || response.headers.get('content-type') !== 'application/jose'
    || response.redirected || response.url && response.url !== endpoint) fail();
  const ciphertext = await boundedText(response, Math.ceil(BACKUP_LIMITS.maxBytes * 4 / 3) + 16384);
  if (!await verifyBackupHmac(credentials.hmacSecret, 'response\n' + body.nonce + '\n' + ciphertext,
    response.headers.get('x-backup-response-signature'))) fail();
  const privateKey = await importJWK(credentials.recipientPrivateJwk, 'RSA-OAEP-256');
  const { plaintext, protectedHeader } = await compactDecrypt(ciphertext, privateKey,
    { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
  if (protectedHeader.typ !== 'pdd-durable-backup+jwe') fail();
  const snapshot = await validateSnapshot(JSON.parse(decode(plaintext)));
  if (locator(snapshot.metadata) !== locator(object) || snapshot.metadata.runId !== runId
    || snapshot.metadata.sourceVersion !== sourceVersion || snapshot.metadata.accountEpoch !== accountEpoch) fail();
  return snapshot;
}

export async function collectClosedBundle({ endpoint, expectedObjects, runId = randomUUID(), sourceVersion, accountEpoch,
  credentials, kvEntries = [], fetchImpl = fetch }) {
  checkedLoopbackEndpoint(endpoint); checkedObjects(expectedObjects);
  const { key } = checkedCredentials(credentials), snapshots = [];
  // All expected IDs must succeed. A failed object never produces a valid partial bundle.
  for (const object of expectedObjects) snapshots.push(await exportClosedObject({ endpoint, object, runId, sourceVersion, accountEpoch, credentials, fetchImpl }));
  const inventory = await createClosedInventory(snapshots, { key, kvEntries,
    provenance: { kind: 'synthetic-local', globalAtomic: false, inventoryComplete: false } });
  return validateClosedBundle({ inventory, snapshots, kvEntries }, { key });
}
export async function encryptClosedBundle(bundle, credentials) {
  const { key, publicJwk } = checkedCredentials(credentials);
  const verified = await validateClosedBundle(bundle, { key });
  return new CompactEncrypt(utf8.encode(canonicalStringify(verified)))
    .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ: 'pdd-closed-bundle+jwe' })
    .encrypt(await importJWK(publicJwk, 'RSA-OAEP-256'));
}
export async function decryptClosedBundle(ciphertext, credentials) {
  const { key } = checkedCredentials(credentials);
  const { plaintext, protectedHeader } = await compactDecrypt(ciphertext,
    await importJWK(credentials.recipientPrivateJwk, 'RSA-OAEP-256'),
    { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
  if (protectedHeader.typ !== 'pdd-closed-bundle+jwe') fail();
  return validateClosedBundle(JSON.parse(decode(plaintext)), { key });
}
async function privateRead(file) {
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.mode & 0o077) throw new Error('Expected a private regular file (mode 600).');
    return await handle.readFile('utf8');
  } finally { await handle.close(); }
}
export async function writePrivateNew(file, contents) {
  // A failed write must not leave a truncated key/archive at the final path.
  // Same-directory hard-link publication is atomic and cannot replace a file
  // or symlink created by another process while the contents are written.
  const pending = join(dirname(file), '.' + basename(file) + '.' + randomUUID() + '.pending');
  const handle = await open(pending, 'wx', 0o600);
  try {
    try { await handle.writeFile(contents); await handle.sync(); } finally { await handle.close(); }
    await link(pending, file);
  } finally { await unlink(pending); }
}
async function main(args) {
  const [command, ...paths] = args;
  if (command === 'init' && paths.length === 1) {
    await writePrivateNew(paths[0], canonicalStringify(createExportCredentials()));
    console.log('Created private rehearsal credentials. Keep outside every backup.'); return;
  }
  if (command === 'collect' && paths.length === 4) {
    const [planFile, credentialsFile, endpoint, archive] = paths;
    const credentials = JSON.parse(await privateRead(credentialsFile));
    const plan = JSON.parse(await privateRead(planFile));
    const bundle = await collectClosedBundle({ ...plan, endpoint, credentials });
    await writePrivateNew(archive, await encryptClosedBundle(bundle, credentials));
    console.log(JSON.stringify({ encrypted: true, objectCount: bundle.inventory.objectCount, globalAtomic: false, inventoryComplete: false })); return;
  }
  if (command === 'verify' && paths.length === 2) {
    const [archive, credentialsFile] = paths, credentials = JSON.parse(await privateRead(credentialsFile));
    const bundle = await decryptClosedBundle(await privateRead(archive), credentials), target = createClosedTarget();
    await restoreClosedBundle(bundle, target, { key: Buffer.from(credentials.hmacSecret, 'base64url') });
    const objects = inspectClosedTarget(target);
    console.log(JSON.stringify({ restoredObjects: objects.length,
      restoredEntries: objects.reduce((sum, object) => sum + object.entryCount, 0),
      quarantinedAlarms: objects.filter(object => object.archivedAlarm !== null).length,
      quarantinedJobs: objects.reduce((sum, object) => sum + object.quarantinedKeys.length, 0),
      networkRequests: 0, globalAtomic: false, inventoryComplete: false })); return;
  }
  throw new Error('Usage: secure_export.mjs init KEY | collect PLAN KEY http://127.0.0.1:PORT/_backup/v1/export ARCHIVE | verify ARCHIVE KEY');
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(() => { console.error('Closed export failed; no production operation was performed. Check local input, permissions and test server.'); process.exitCode = 1; });
}
