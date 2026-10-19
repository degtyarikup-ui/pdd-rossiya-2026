import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { canonicalStringify, snapshotStorage } from '../../server/install-notifier/durable_backup.js';
import { syntheticBackup, SYNTHETIC_USER } from '../../server/install-notifier/closed-backup-fixtures.mjs';
import { createClosedInventory, encodeClosedKVEntry } from './closed_restore.mjs';
import { createExportCredentials, encryptClosedBundle } from './secure_export.mjs';
import { inspectRecoverySemantics, validateRealRestore } from './validate_real_restore.mjs';

const runtimeRoot=process.env.PDD_MINIFLARE_MODULE_ROOT;
async function fixture(){
  const data=await syntheticBackup(), credentials=createExportCredentials();
  const active=data.objects.get('active'), privateKey='apple_auth:'+SYNTHETIC_USER;
  await active.put('doc:'+privateKey,{key:privateKey,value:JSON.stringify({refreshToken:'synthetic-private-token'}),options:{},epoch:data.epoch});
  const {capturedAt,alarm,...metadata}=data.snapshots[0].metadata;
  data.snapshots[0]=await snapshotStorage({storage:active},metadata);
  data.kvEntries.push(encodeClosedKVEntry({key:'large-binary-fixture',value:Uint8Array.from({length:160000},(_,index)=>index%251),expiration:1234567890,metadata:{fixture:true}}));
  const key=Buffer.from(credentials.hmacSecret,'base64url');
  const inventory=await createClosedInventory(data.snapshots,{key,kvEntries:data.kvEntries});
  return {data,credentials,key,bundle:{inventory,snapshots:data.snapshots,kvEntries:data.kvEntries}};
}

test('semantic proof counts premium sources, both progress categories, payment states and deletion/session evidence',async()=>{
  const {bundle}=await fixture();
  const report=inspectRecoverySemantics(bundle);
  assert.equal(report.profileDocuments,1);
  assert.equal(report.premiumProfiles,1);
  assert.deepEqual(report.premiumEntitlements,{appstore:1,googleplay:1,web:1,admin_grant:1,other:0});
  assert.equal(report.progressDocuments,1);
  assert.equal(report.progressQuestionsAb,800);
  assert.equal(report.progressQuestionsCd,800);
  assert.equal(report.paymentOrders,5);
  assert.equal(report.paymentLedgers,1);
  assert.deepEqual(report.paymentStatuses,{confirmed:1,pending:2,creation_unknown:1,requires_refund:1,other:0});
  assert.equal(report.purchaseClaims,1);
  assert.equal(report.deletionTombstones,1);
  assert.equal(report.legacySessions,1);
  assert.equal(report.revokedSessions,1);
  assert.equal(report.retainedPrivateAppleAuthorizations,1);
  assert.equal(report.queuedEffects,1);
  assert.equal(report.queuedProjections,1);
  assert.equal(report.quarantinedOutboxEntries,1);
  assert.equal(report.warnings.missingPaymentOwner,0);
  assert.equal(report.warnings.missingClaimOwner,0);
});

test('within-object owner corruption fails without exposing identity',async()=>{
  const {data,bundle}=await fixture();
  const active=data.objects.get('active');
  await active.put('account-id','google_wrong_owner');
  const old=bundle.snapshots[0],{capturedAt,alarm,...metadata}=old.metadata;
  bundle.snapshots[0]=await snapshotStorage({storage:active},metadata);
  assert.throws(()=>inspectRecoverySemantics(bundle),{message:'Real restore validation failed'});
});

test('unlisted and tampered storage is rejected before runtime startup',async()=>{
  const {bundle,key}=await fixture();
  const changed=structuredClone(bundle);changed.snapshots.pop();
  await assert.rejects(validateRealRestore(changed,{key,runtimeRoot:'/must/not/be/read'}),/Closed restore validation failed/);
  const corrupted=structuredClone(bundle);corrupted.snapshots[0].entries.pop();
  await assert.rejects(validateRealRestore(corrupted,{key,runtimeRoot:'/must/not/be/read'}),/Invalid durable backup/);
});

test('real bundles require an explicit private storage root before starting SQLite',async()=>{
  const {bundle,key}=await fixture();
  bundle.inventory=await createClosedInventory(bundle.snapshots,{key,kvEntries:bundle.kvEntries,
    provenance:{kind:'collected-nonatomic',globalAtomic:false,inventoryComplete:true}});
  await assert.rejects(validateRealRestore(bundle,{key,runtimeRoot:'/must/not/be/read'}),{message:'Real restore validation failed'});
});

test('the fixture cannot load business handlers, source IDs, alarms or network; SQLite directory is private and removed',async()=>{
  const source=await readFile(new URL('./validate_real_restore.mjs',import.meta.url),'utf8');
  const script=source.slice(source.indexOf('const fixtureSource = `'),source.indexOf('\n`;'));
  assert.equal(script.includes('worker.js'),false);
  assert.equal(script.includes('account_state.js'),false);
  assert.equal(script.includes('setAlarm('),false);
  assert.equal(script.includes('fetch('),true); // the private generic method itself
  assert.equal(script.includes('idFromString('),false);
  assert.equal(source.includes('await chmod(temporaryDirectory,0o700)'),true);
  assert.equal(source.includes('await rm(temporaryDirectory,{recursive:true,force:true})'),true);
});

test('all raw DO values and binary KV, expiry and metadata restore to ephemeral workerd SQLite', {skip:!runtimeRoot}, async()=>{
  const {bundle,credentials}=await fixture();
  const before=createHash('sha256').update(canonicalStringify(bundle)).digest('hex');
  // Round-trip the encrypted archive first, proving no plaintext values are
  // retained in the only persistable backup format used by the command.
  const encrypted=await encryptClosedBundle(bundle,credentials);
  assert.equal(encrypted.includes(SYNTHETIC_USER),false);
  const report=await validateRealRestore(bundle,{credentials,runtimeRoot});
  assert.equal(report.authenticatedInventory,true);
  assert.equal(report.rawDOValuesExact,true);
  assert.equal(report.rawKVValuesMetadataExpiryExact,true);
  assert.equal(report.sqlite.durableObjectsVerified,5);
  assert.equal(report.sqlite.kvLogicalEntriesVerified,bundle.kvEntries.length);
  assert.equal(report.sqlite.storage,'private-temporary-sqlite-removed');
  assert.equal(report.sqlite.temporaryStorageRemoved,true);
  assert.equal(report.sqlite.disposed,true);
  assert.equal(report.archivedAlarmsQuarantined,2);
  assert.equal(report.restoredAlarmsScheduled,0);
  assert.equal(report.outboundAttempts,0);
  assert.equal(report.businessHandlersExecuted,0);
  assert.equal(report.productionModified,false);
  assert.equal(report.plategaContacted,false);
  assert.equal(report.globalAtomic,false);
  assert.equal(report.inventoryComplete,false);
  assert.equal(createHash('sha256').update(canonicalStringify(bundle)).digest('hex'),before);
  const text=JSON.stringify(report);
  for(const value of [SYNTHETIC_USER,'closed-backup@example.invalid','closed-confirmed-transaction',credentials.hmacSecret])assert.equal(text.includes(value),false);
});
