// Reads only the signed, short-lived export broker selected by this run.
import { createRequire } from 'node:module';
import { randomBytes, createPrivateKey, createPublicKey, createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { open, mkdir, lstat } from 'node:fs/promises';
import { join } from 'node:path';
import { BACKUP_PATH, backupHmac, verifyBackupHmac, canonicalStringify, validateSnapshot } from '../../server/install-notifier/durable_backup.js';
import { writePrivateNew, BACKUP_CLASSES } from './secure_export.mjs';
const require = createRequire(new URL('../../server/install-notifier/package.json', import.meta.url));
const { compactDecrypt, importJWK, CompactEncrypt } = await import(require.resolve('jose'));
const fail = () => { throw new Error('Real object export failed'); };
const decode = bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes);
const identity = object => [object.className, object.namespaceId, object.objectId].join(':');
async function checkpointRead(file) {
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try { const info = await handle.stat(); if (!info.isFile() || info.mode & 0o077) fail(); return await handle.readFile('utf8'); }
  finally { await handle.close(); }
}
async function boundedCiphertext(response) {
  if (!response.body) fail();
  const reader = response.body.getReader(), chunks = []; let size = 0;
  try { for (;;) { const { value, done } = await reader.read(); if (done) break;
    size += value.byteLength; if (size > 90 * 1024 * 1024) { await reader.cancel(); fail(); } chunks.push(value);
  } } finally { reader.releaseLock(); }
  return decode(Buffer.concat(chunks, size));
}
export async function encryptRunEvidence(value, credentials, typ = 'pdd-export-evidence+jwe') {
  const jwk = createPublicKey(createPrivateKey({ key: credentials.recipientPrivateJwk, format: 'jwk' })).export({ format: 'jwk' });
  const signature = await backupHmac(credentials.hmacSecret, typ + '\n' + canonicalStringify(value));
  return new CompactEncrypt(new TextEncoder().encode(canonicalStringify({ value, signature })))
    .setProtectedHeader({ alg: 'RSA-OAEP-256', enc: 'A256GCM', typ }).encrypt(await importJWK(jwk, 'RSA-OAEP-256'));
}
export async function decryptRunEvidence(value, credentials, typ = 'pdd-export-evidence+jwe') {
  const { plaintext, protectedHeader } = await compactDecrypt(value, await importJWK(credentials.recipientPrivateJwk, 'RSA-OAEP-256'),
    { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
  if (protectedHeader.typ !== typ) fail();
  const envelope = JSON.parse(decode(plaintext));
  if (!envelope || Object.keys(envelope).sort().join(',') !== 'signature,value'
    || !await verifyBackupHmac(credentials.hmacSecret, typ + '\n' + canonicalStringify(envelope.value), envelope.signature)) fail();
  return envelope.value;
}
export async function collectRealObjects({ endpoint, brokerName, accountSubdomain, objects, runId, sourceVersion, accountEpoch, credentials, outputDir, onProgress = () => {} }) {
  const expected = 'https://' + brokerName + '.' + accountSubdomain + '.workers.dev' + BACKUP_PATH;
  if (endpoint !== expected || !/^pdd-account-export-[a-f0-9]{8}$/.test(brokerName) || !/^[a-z0-9-]+$/.test(accountSubdomain)) fail();
  const publicJwk = createPublicKey(createPrivateKey({ key: credentials.recipientPrivateJwk, format: 'jwk' })).export({ format: 'jwk' });
  const privateKey = await importJWK(credentials.recipientPrivateJwk, 'RSA-OAEP-256');
  await mkdir(outputDir, { recursive: true, mode: 0o700 });
  const directory = await lstat(outputDir); if (!directory.isDirectory() || directory.isSymbolicLink() || directory.mode & 0o077) fail();
  const snapshots = [];
  for (const object of objects) {
    if (!BACKUP_CLASSES.includes(object.className) || !/^[a-f0-9]{32}$/.test(object.namespaceId) || !/^[a-f0-9]{64}$/.test(object.objectId)) fail();
    const file = join(outputDir, createHash('sha256').update(identity(object)).digest('hex') + '.pddjwe');
    let snapshot;
    try { snapshot = await decryptRunEvidence(await checkpointRead(file), credentials); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (!snapshot) {
      let success = false;
      for (let attempt = 0; attempt < 5; attempt++) {
        const body = { format: 1, ...object, runId, sourceVersion, accountEpoch, issuedAt: Date.now(), nonce: randomBytes(24).toString('base64url'), recipientJwk: publicJwk };
        const raw = canonicalStringify(body), signature = await backupHmac(credentials.hmacSecret, 'POST\n' + BACKUP_PATH + '\n' + raw);
        let response;
        try { response = await fetch(endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45000),
          headers: { 'content-type': 'application/json', 'x-backup-signature': signature }, body: raw }); }
        catch { if (attempt === 4) fail(); await new Promise(r => setTimeout(r, 1000 * (attempt + 1))); continue; }
        if (response.status !== 200) {
          const status = response.status, contentType = response.headers.get('content-type');
          await response.body?.cancel();
          onProgress({ phase: 'export-retry', className: object.className, httpStatus: status,
            jsonErrorResponse: Boolean(contentType?.startsWith('application/json')), attempt: attempt + 1 });
          if ([404, 429, 500, 502, 503, 504].includes(status) && attempt < 4) { await new Promise(r => setTimeout(r, 1000 * (attempt + 1))); continue; }
          fail();
        }
        if (response.url !== endpoint || response.headers.get('content-type') !== 'application/jose') fail();
        const ciphertext = await boundedCiphertext(response);
        if (!await verifyBackupHmac(credentials.hmacSecret, 'response\n' + body.nonce + '\n' + ciphertext, response.headers.get('x-backup-response-signature'))) fail();
        const { plaintext, protectedHeader } = await compactDecrypt(ciphertext, privateKey,
          { keyManagementAlgorithms: ['RSA-OAEP-256'], contentEncryptionAlgorithms: ['A256GCM'] });
        if (protectedHeader.typ === 'pdd-durable-backup-diagnostic+jwe') {
          const diagnostic = JSON.parse(decode(plaintext));
          const reasons = ['storage_transaction','storage_api','storage_list','storage_page','key_validation','key_order',
            'value_encoding','value_byte_limit','entry_encoding','snapshot_limit','storage_alarm','metadata_validation','snapshot_hash','snapshot_validation'];
          if (diagnostic?.format !== 'pdd-durable-backup-diagnostic' || diagnostic.schema !== 1
            || Object.keys(diagnostic).sort().join(',') !== 'encodedBytes,entryCount,errorKind,format,pageCount,reason,schema'
            || !reasons.includes(diagnostic.reason) || !['Error','TypeError','RangeError','DataCloneError','QuotaExceededError',
              'InvalidStateError','OperationError','AbortError','UnknownError'].includes(diagnostic.errorKind)
            || ['entryCount','pageCount','encodedBytes'].some(key => !Number.isSafeInteger(diagnostic[key]) || diagnostic[key] < 0)) fail();
          const diagnosticFile = join(outputDir, 'diagnostic-' + createHash('sha256').update(identity(object)).digest('hex') + '-' + body.nonce + '.pddjwe');
          await writePrivateNew(diagnosticFile, await encryptRunEvidence(diagnostic, credentials));
          throw new Error('Authenticated backup diagnostic: ' + diagnostic.reason + ' / ' + diagnostic.errorKind
            + ', entries=' + diagnostic.entryCount + ', pages=' + diagnostic.pageCount + ', encodedBytes=' + diagnostic.encodedBytes);
        }
        if (protectedHeader.typ !== 'pdd-durable-backup+jwe') fail();
        snapshot = JSON.parse(decode(plaintext)); success = true; break;
      }
      if (!success) fail();
      await validateSnapshot(snapshot);
      if (identity(snapshot.metadata) !== identity(object) || snapshot.metadata.runId !== runId || snapshot.metadata.sourceVersion !== sourceVersion || snapshot.metadata.accountEpoch !== accountEpoch) fail();
      // Re-encrypt the validated object with a separate evidence type for safe,
      // authenticated resumption. No plaintext checkpoint reaches disk.
      await writePrivateNew(file, await encryptRunEvidence(snapshot, credentials));
    }
    await validateSnapshot(snapshot);
    if (identity(snapshot.metadata) !== identity(object) || snapshot.metadata.runId !== runId || snapshot.metadata.sourceVersion !== sourceVersion || snapshot.metadata.accountEpoch !== accountEpoch) fail();
    snapshots.push(snapshot);
    if (snapshots.length % 25 === 0 || snapshots.length === objects.length) onProgress({ exported: snapshots.length, expected: objects.length });
  }
  return snapshots;
}
