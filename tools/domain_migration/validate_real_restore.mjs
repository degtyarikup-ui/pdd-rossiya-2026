#!/usr/bin/env node
// Offline recovery proof. Workerd SQLite uses a private temporary directory
// removed in finally; no business handler or alarm is loaded.
import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { open, mkdir, mkdtemp, chmod, rm, lstat } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { canonicalStringify, encodeValue, decodeValue } from '../../server/install-notifier/durable_backup.js';
import { createClosedTarget, restoreClosedBundle, readClosedObject, readClosedKV, validateClosedBundle } from './closed_restore.mjs';
import { BACKUP_CLASSES, decryptClosedBundle, writePrivateNew } from './secure_export.mjs';
import { entitlementsOf } from '../../server/install-notifier/entitlements.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const digest = value => createHash('sha256').update(canonicalStringify(value)).digest('hex');
const fail = () => { throw new Error('Real restore validation failed'); };
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
const json = value => { try { return JSON.parse(value); } catch { fail(); } };
const arraySize = value => Array.isArray(value) ? value.length : plain(value) ? Object.keys(value).length : 0;
const counts = names => Object.fromEntries(names.map(name => [name, 0]));

// This module is not a Worker entrypoint. This generated fixture has no public
// routing, production imports, namespaces, business secrets or alarm methods.
const fixtureSource = `
import { canonicalStringify, encodeValue, decodeValue } from './server/install-notifier/durable_backup.js';
const utf8 = new TextEncoder();
export class ClosedRecoveryDO {
  constructor(state) { this.state = state; }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === '/seed' && request.method === 'POST') {
      const { entries, fresh } = await request.json();
      if (!Array.isArray(entries) || entries.length>32 || fresh && (await this.state.storage.list({limit:1})).size) return new Response('Closed restore rejected', {status:409});
      await this.state.storage.transaction(async txn => {
        for (const entry of entries) {
          if (await txn.get(entry.key)!==undefined) throw new Error('Closed restore rejected');
          await txn.put(entry.key, decodeValue(entry.value));
        }
      });
      return Response.json({seeded: entries.length});
    }
    if (path === '/proof' && request.method === 'POST') {
      const {startAfter}=await request.json(), entries = [];
      const page=await this.state.storage.list({limit:32,...(startAfter===null?{}:{startAfter})});
      for(const [key,value]of page)entries.push({key,value:encodeValue(value)});
      const hash = await crypto.subtle.digest('SHA-256', utf8.encode(canonicalStringify(entries)));
      return Response.json({entryCount:entries.length, sha256:Array.from(new Uint8Array(hash), x=>x.toString(16).padStart(2,'0')).join(''),
        alarm:await this.state.storage.getAlarm(), sqliteProof:[...this.state.storage.sql.exec('SELECT 1 AS proof')][0].proof});
    }
    return new Response('Closed restore rejected', {status:404});
  }
}
export default { fetch() { return new Response('Closed restore rejected', {status:404}); } };
`;

function unpackRecords(entries, summary) {
  const records = new Map();
  for (const [key, record] of entries) {
    if (!key.startsWith('doc:')) continue;
    if (!plain(record) || record.key !== key.slice(4)) fail();
    let value = record.value;
    if (Object.hasOwn(record, 'chunks')) {
      const chunks = [];
      for (let index = 0; index < record.chunks; index++) {
        const chunk = entries.get('chunk:' + record.key + ':' + index);
        if (typeof chunk !== 'string') fail();
        chunks.push(Buffer.from(chunk, 'base64'));
      }
      try { value = new TextDecoder('utf-8', {fatal:true}).decode(Buffer.concat(chunks)); } catch { fail(); }
      summary.chunkedDocuments++;
    }
    if (value !== null && typeof value !== 'string') fail();
    records.set(record.key, { value, record });
    summary.accountDocuments++;
    if (value === null) summary.nullDocuments++;
  }
  return records;
}

// Cross-object references are observations of a non-atomic source collection.
// They do not cause a payment lookup, queue replay, import or source write.
export function inspectRecoverySemantics(bundle) {
  const summary = {
    accountDocuments:0, chunkedDocuments:0, nullDocuments:0, profileDocuments:0,
    premiumProfiles:0, premiumEntitlements:counts(['appstore','googleplay','web','admin_grant','other']),
    progressDocuments:0, progressQuestionsAb:0, progressQuestionsCd:0,
    progressTicketsAb:0, progressTicketsCd:0, progressFavoritesAb:0, progressFavoritesCd:0,
    progressExamsAb:0, progressExamsCd:0, paymentOrders:0,
    paymentStatuses:counts(['confirmed','pending','creation_unknown','requires_refund','other']),
    paymentLedgers:0, paymentTransactionIndexes:0, pendingPaymentIndexes:0, paymentIntents:0,
    purchaseClaims:0, deletionTombstones:0, sessionGenerations:0, revokedSessions:0,
    retainedPrivateAppleAuthorizations:0, legacySessions:0, dormantKVProfiles:0,
    dormantKVProgress:0, queuedEffects:0, queuedProjections:0, quarantinedOutboxEntries:0,
    staleEpochDocuments:0, expiredDocumentsRetained:0,
    warnings:counts(['orphanAccountDocument','orphanPaymentIndex','missingPaymentOwner','missingClaimOwner',
      'missingDirectoryOwner','missingPaymentLedger','invalidEntitlementExpiry','duplicateAccountAuthority']),
  };
  const owners = new Set(), tombstones = new Set(), authorities = new Set(), profileDocs = new Set(), progressDocs = new Set(), authorityDocs = new Set();
  const paymentOwners = [], claimOwners = [], directoryOwners = [];
  const kv = new Map(bundle.kvEntries.map(entry => [entry.key, entry]));
  const now = Date.now();
  const inspectProfile = profile => {
    if (!plain(profile)) fail();
    summary.profileDocuments++;
    if (profile.isPremium === true) summary.premiumProfiles++;
    const entitlement = entitlementsOf(profile);
    if (!plain(entitlement)) fail();
    for (const [source, value] of Object.entries(entitlement)) {
      summary.premiumEntitlements[Object.hasOwn(summary.premiumEntitlements, source) ? source : 'other']++;
      if (!plain(value) || value.expiresAt !== null && (!Object.hasOwn(value,'expiresAt') || typeof value.expiresAt !== 'string' || !Number.isFinite(Date.parse(value.expiresAt)))) summary.warnings.invalidEntitlementExpiry++;
    }
  };
  const inspectProgress = progress => {
    if (!plain(progress)) fail();
    summary.progressDocuments++;
    for (const suffix of ['Ab','Cd']) {
      summary['progressQuestions'+suffix] += arraySize(progress['questionProgress'+suffix]);
      summary['progressTickets'+suffix] += arraySize(progress['ticketProgress'+suffix]);
      summary['progressFavorites'+suffix] += arraySize(progress['favorites'+suffix]);
      summary['progressExams'+suffix] += arraySize(progress['examResults'+suffix]);
    }
  };
  for (const snapshot of bundle.snapshots) {
    const entries = new Map(snapshot.entries.map(entry => [entry.key, decodeValue(entry.value)]));
    for (const key of entries.keys()) {
      if (key.startsWith('effect:')) summary.queuedEffects++;
      if (key.startsWith('projection:')) summary.queuedProjections++;
      if (key.startsWith('out:')) summary.quarantinedOutboxEntries++;
    }
    if (snapshot.metadata.className === 'PurchaseClaims' && entries.has('owner')) {
      const owner = entries.get('owner');
      if (owner !== null && (typeof owner !== 'string' || !owner.length)) fail();
      if (owner) { summary.purchaseClaims++; claimOwners.push(owner); }
    }
    if (snapshot.metadata.className !== 'AccountState') continue;
    const owner = entries.get('account-id');
    if (owner !== undefined && (typeof owner !== 'string' || !owner.length)) fail();
    if (owner) {
      if (authorities.has(owner)) summary.warnings.duplicateAccountAuthority++;
      authorities.add(owner);
    }
    const docs = unpackRecords(entries, summary);
    for (const [key, {value, record}] of docs) {
      authorityDocs.add(key);
      if (!key.startsWith('apple_auth:') && String(record.epoch || '1') !== snapshot.metadata.accountEpoch) summary.staleEpochDocuments++;
      if (record.expiresAt && record.expiresAt <= now) summary.expiredDocumentsRetained++;
      if (key.startsWith('user:')) {
        const id = key.slice(5); profileDocs.add(id);
        if (owner && owner !== id) fail();
        if (value !== null) { const profile=json(value); if (profile.id !== id) fail(); owners.add(id); inspectProfile(profile); }
      } else if (key.startsWith('user_progress:')) {
        const id = key.slice(14); progressDocs.add(id);
        if (owner && owner !== id) fail();
        if (value !== null) inspectProgress(json(value));
      } else if (key.startsWith('pay_order:') && value !== null) {
        const order = json(value); if (!plain(order) || typeof order.userId !== 'string' || !order.userId.length
          || owner && order.userId !== owner || order.orderId && order.orderId !== key.slice(10)) fail();
        paymentOwners.push(order.userId); summary.paymentOrders++;
        summary.paymentStatuses[Object.hasOwn(summary.paymentStatuses,order.status) ? order.status : 'other']++;
        if (order.status === 'confirmed' && !docs.get('payment_ledger:'+key.slice(10))?.value) summary.warnings.missingPaymentLedger++;
      } else if (key.startsWith('payment_ledger:') && value !== null) { if (!plain(json(value))) fail(); summary.paymentLedgers++; }
      else if (key.startsWith('pay_tx:') && value !== null) summary.paymentTransactionIndexes++;
      else if (key.startsWith('pay_intent:') && value !== null) summary.paymentIntents++;
      else if (key.startsWith('account_deleted:') && value !== null) { summary.deletionTombstones++; tombstones.add(key.slice(16)); }
      else if (key.startsWith('auth_generation:') && value !== null) summary.sessionGenerations++;
      else if (key.startsWith('revoked_session:') && value !== null) summary.revokedSessions++;
      else if (key.startsWith('apple_auth:') && value !== null) summary.retainedPrivateAppleAuthorizations++;
      if (value !== null && !owner && !key.startsWith('payment_ledger:')) summary.warnings.orphanAccountDocument++;
    }
    for (const [key,value] of entries) {
      if (key.startsWith('index:pay_order:')) {
        summary.pendingPaymentIndexes++;
        if (!plain(value) || typeof value.userId !== 'string' || owner && value.userId !== owner) fail();
        if (!docs.get(key.slice(6))?.value) summary.warnings.orphanPaymentIndex++;
      } else if (key.startsWith('order:')) {
        if (!plain(value) || typeof value.userId !== 'string') fail(); directoryOwners.push(value.userId);
      } else if (key.startsWith('tx:')) {
        if (typeof value !== 'string') fail(); directoryOwners.push(value);
      }
    }
  }
  for (const [key,entry] of kv) {
    let text;
    if (/^(user:|user_progress:|auth_session:|account_deleted:|auth_generation:|revoked_session:|pay_order:|payment_ledger:)/.test(key)) {
      try { text = new TextDecoder('utf-8',{fatal:true}).decode(Buffer.from(entry.valueBase64,'base64')); } catch { fail(); }
    }
    if (key.startsWith('user:') && !profileDocs.has(key.slice(5))) {
      const profile=json(text); if (!plain(profile) || profile.id !== key.slice(5)) fail();
      owners.add(profile.id); summary.dormantKVProfiles++; inspectProfile(profile);
    } else if (key.startsWith('user_progress:') && !progressDocs.has(key.slice(14))) { summary.dormantKVProgress++; inspectProgress(json(text)); }
    else if (key.startsWith('auth_session:')) summary.legacySessions++;
    else if (key.startsWith('pay_order:') && !authorityDocs.has(key)) {
      const order=json(text);if(!plain(order)||typeof order.userId!=='string'||!order.userId.length
        ||order.orderId&&order.orderId!==key.slice(10))fail();
      paymentOwners.push(order.userId);summary.paymentOrders++;
      summary.paymentStatuses[Object.hasOwn(summary.paymentStatuses,order.status)?order.status:'other']++;
      if(order.status==='confirmed'&&!authorityDocs.has('payment_ledger:'+key.slice(10))&&!kv.has('payment_ledger:'+key.slice(10)))summary.warnings.missingPaymentLedger++;
    } else if(key.startsWith('payment_ledger:')&&!authorityDocs.has(key)){if(!plain(json(text)))fail();summary.paymentLedgers++;}
    else if(key.startsWith('pay_tx:')&&!authorityDocs.has(key))summary.paymentTransactionIndexes++;
    else if(key.startsWith('pay_intent:')&&!authorityDocs.has(key))summary.paymentIntents++;
    else if(key.startsWith('auth_generation:')&&!authorityDocs.has(key))summary.sessionGenerations++;
    else if(key.startsWith('revoked_session:')&&!authorityDocs.has(key))summary.revokedSessions++;
    else if(key.startsWith('account_deleted:')&&!authorityDocs.has(key)){tombstones.add(key.slice(16));summary.deletionTombstones++;}
  }
  for (const owner of paymentOwners) if (!owners.has(owner) && !tombstones.has(owner)) summary.warnings.missingPaymentOwner++;
  for (const owner of claimOwners) if (!owners.has(owner) && !tombstones.has(owner)) summary.warnings.missingClaimOwner++;
  for (const owner of directoryOwners) if (!owners.has(owner) && !tombstones.has(owner)) summary.warnings.missingDirectoryOwner++;
  return summary;
}

// KV raw values may exceed the DO per-value limit, so the local SQLite proof
// uses surrogate keys and <=48KiB binary chunks. Metadata and absolute expiry
// are retained separately, without activating either TTLs or any queues.
function sqliteKVGroups(kvEntries) {
  const groups = []; let entries=[], size=0;
  const flush = () => { if (entries.length) groups.push(entries); entries=[]; size=0; };
  for (let index=0; index<kvEntries.length; index++) {
    const {key,valueBase64,expiration,metadata}=kvEntries[index];
    const bytes=Buffer.from(valueBase64,'base64'), chunks=Math.ceil(bytes.length/49152);
    const raw=[{key:'kv:'+String(index).padStart(8,'0')+':record',value:encodeValue({key,expiration,metadata,chunks})}];
    for(let part=0;part<chunks;part++) raw.push({key:'kv:'+String(index).padStart(8,'0')+':chunk:'+String(part).padStart(8,'0'),value:encodeValue(Uint8Array.from(bytes.subarray(part*49152,(part+1)*49152)))});
    for(const entry of raw){
      const bytesSize=Buffer.byteLength(canonicalStringify(entry));
      if(size && size+bytesSize>4*1024*1024)flush();
      entries.push(entry);size+=bytesSize;
    }
  }
  flush();
  return groups.map(entries=>entries.sort((a,b)=>Buffer.compare(Buffer.from(a.key),Buffer.from(b.key))));
}

export async function validateRealRestore(bundle, {credentials, key, runtimeRoot, outputReport, storageRoot}={}) {
  if (!key && credentials) key=Buffer.from(credentials.hmacSecret||'','base64url');
  if (!(key instanceof Uint8Array) || key.byteLength!==32 || !isAbsolute(runtimeRoot||'')) fail();
  const verified=await validateClosedBundle(bundle,{key});
  const namespaces=new Map(),namespaceClasses=new Map();
  for(const snapshot of verified.snapshots){
    const {className,namespaceId}=snapshot.metadata;
    if(!BACKUP_CLASSES.includes(className)||(namespaces.has(className)&&namespaces.get(className)!==namespaceId)
      ||(namespaceClasses.has(namespaceId)&&namespaceClasses.get(namespaceId)!==className))fail();
    namespaces.set(className,namespaceId);namespaceClasses.set(namespaceId,className);
  }
  // Real customer SQLite may only be created on an operator-selected private
  // root (the runbook mounts an encrypted volume there). Synthetic fixtures
  // alone may use the repository's ignored output directory.
  if(verified.inventory.provenance.kind!=='synthetic-local'&&!storageRoot)fail();
  if(storageRoot){
    if(!isAbsolute(storageRoot))fail();
    const stat=await lstat(storageRoot);
    if(!stat.isDirectory()||stat.isSymbolicLink()||(stat.mode&0o077)
      ||typeof process.getuid==='function'&&stat.uid!==process.getuid())fail();
  }
  const semantic=inspectRecoverySemantics(verified);
  const target=createClosedTarget();
  await restoreClosedBundle(verified,target,{key});
  const classes=counts(BACKUP_CLASSES);
  let sourceEntries=0, archivedAlarms=0;
  for(const snapshot of verified.snapshots){
    if(!BACKUP_CLASSES.includes(snapshot.metadata.className))fail();
    classes[snapshot.metadata.className]++;
    const restored=readClosedObject(target,snapshot.metadata);
    if(restored.scheduledAlarm!==null || digest([...restored.entries].map(([key,value])=>({key,value:encodeValue(value)})))!==digest(snapshot.entries))fail();
    sourceEntries+=snapshot.entryCount;if(snapshot.metadata.alarm!==null)archivedAlarms++;
  }
  const restoredKV=readClosedKV(target);
  if(digest(restoredKV.map(({key,value,expiration,metadata})=>({key,valueBase64:Buffer.from(value).toString('base64'),expiration,metadata})))!==digest(verified.kvEntries))fail();
  const requireRuntime=createRequire(join(runtimeRoot,'__pdd_real_restore__.cjs'));
  const {Miniflare,convertV4MiniflareOptions}=requireRuntime('miniflare');
  const {build}=requireRuntime('esbuild');
  const compiled=await build({stdin:{contents:fixtureSource,resolveDir:root,sourcefile:'closed-generic-fixture.mjs'},bundle:true,write:false,format:'esm',platform:'browser',target:'es2022',minify:true,legalComments:'none'});
  let outboundAttempts=0,mf, temporaryDirectory;
  const groupedKV=sqliteKVGroups(verified.kvEntries);
  let sqliteObjects=0,sqliteEntries=0;
  try{
    const temporaryRoot=storageRoot||join(root,'output','account-export-preparation');
    if(!storageRoot)await mkdir(temporaryRoot,{recursive:true,mode:0o700});
    temporaryDirectory=await mkdtemp(join(temporaryRoot,'closed-real-sqlite-'));
    await chmod(temporaryDirectory,0o700);
    const options={host:'127.0.0.1',port:0,inspectorHost:'127.0.0.1',cf:false,telemetry:{enabled:false},unsafeLocalExplorer:false,
      resourcePersistencePath:temporaryDirectory,
      workers:[{name:'closed-real-restore',modules:true,script:compiled.outputFiles[0].text,compatibilityDate:'2024-11-01',
        durableObjects:{CLOSED:{className:'ClosedRecoveryDO',useSQLite:true}},
        outboundService:()=>{outboundAttempts++;return new Response('Closed restore egress denied',{status:502});}}]};
    mf=new Miniflare(convertV4MiniflareOptions?convertV4MiniflareOptions(options):options);
    const url=await mf.ready;if(url.hostname!=='127.0.0.1')fail();
    const namespace=await mf.getDurableObjectNamespace('CLOSED','closed-real-restore'), run=randomUUID();
    const prove=async(entries)=>{
      // Only fresh locally assigned names enter this namespace. Never parse a
      // source object ID as an identity in a newly created namespace.
      const stub=namespace.get(namespace.idFromName('closed-'+run+'-'+sqliteObjects));
      for(let offset=0;offset<entries.length||offset===0;offset+=32){
        const page=entries.slice(offset,offset+32);
        const seed=await stub.fetch('https://closed.invalid/seed',{method:'POST',body:JSON.stringify({entries:page,fresh:offset===0})});
        if(seed.status!==200 || (await seed.json()).seeded!==page.length)fail();
      }
      for(let offset=0;offset<=entries.length;offset+=32){
        const expected=entries.slice(offset,offset+32),startAfter=offset===0?null:entries[offset-1].key;
        const proofResponse=await stub.fetch('https://closed.invalid/proof',{method:'POST',body:JSON.stringify({startAfter})});
        if(proofResponse.status!==200)fail();const proof=await proofResponse.json();
        if(proof.sqliteProof!==1 || proof.alarm!==null || proof.entryCount!==expected.length || proof.sha256!==digest(expected))fail();
        if(expected.length<32)break;
      }
      if((await stub.fetch('https://closed.invalid/_account/read',{method:'POST'})).status!==404)fail();
      sqliteObjects++;sqliteEntries+=entries.length;
    };
    for(const snapshot of verified.snapshots)await prove(snapshot.entries);
    for(const entries of groupedKV)await prove(entries);
    if((await mf.dispatchFetch('http://localhost/_backup/v1/export',{method:'POST'})).status!==404 || outboundAttempts!==0)fail();
  }finally{
    try{if(mf)await mf.dispose();}finally{if(temporaryDirectory)await rm(temporaryDirectory,{recursive:true,force:true});}
  }
  const times=verified.snapshots.map(snapshot=>Date.parse(snapshot.metadata.capturedAt));
  const report={format:'pdd-real-restore-report',schema:1,completedAt:new Date().toISOString(),
    authenticatedInventory:true,encryptedArchiveInput:false,inventoryComplete:verified.inventory.provenance.inventoryComplete,
    sourceCollectionKind:verified.inventory.provenance.kind,globalAtomic:false,
    capturedFrom:new Date(Math.min(...times)).toISOString(),capturedUntil:new Date(Math.max(...times)).toISOString(),
    durableObjects:verified.snapshots.length,objectsByClass:classes,durableEntries:sourceEntries,kvEntries:verified.kvEntries.length,
    rawDOValuesExact:true,rawKVValuesMetadataExpiryExact:true,premiumDatesExact:true,progressExact:true,paymentRecordsExact:true,
    restoredAlarmsScheduled:0,archivedAlarmsQuarantined:archivedAlarms,businessHandlersExecuted:0,outboundAttempts,
    sqlite:{runtime:'workerd',storage:'private-temporary-sqlite-removed',operatorStorageRootProvided:Boolean(storageRoot),objectsVerified:sqliteObjects,entriesVerified:sqliteEntries,
      durableObjectsVerified:verified.snapshots.length,kvGroupsVerified:groupedKV.length,kvLogicalEntriesVerified:verified.kvEntries.length,disposed:true,temporaryStorageRemoved:true},
    temporarySqliteCleaned:true,semantic,productionModified:false,plategaContacted:false};
  if(outputReport)await writePrivateNew(outputReport,JSON.stringify(report,null,2)+'\n');
  return report;
}

async function privateRead(file){
  const handle=await open(file,constants.O_RDONLY|constants.O_NOFOLLOW);
  try{const stat=await handle.stat();if(!stat.isFile()||(stat.mode&0o077))fail();return await handle.readFile('utf8');}finally{await handle.close();}
}
export async function validateRealArchive(archive,credentialsFile,options={}){
  const credentials=JSON.parse(await privateRead(credentialsFile));
  const bundle=await decryptClosedBundle(await privateRead(archive),credentials);
  const {outputReport,...restoreOptions}=options;
  const report=await validateRealRestore(bundle,{...restoreOptions,credentials});
  report.encryptedArchiveInput=true;
  if(outputReport)await writePrivateNew(outputReport,JSON.stringify(report,null,2)+'\n');
  return report;
}
async function main(args){
  if(args.length!==5)throw new Error('Usage: validate_real_restore.mjs ARCHIVE PRIVATE_KEY RUNTIME_NODE_MODULES REPORT PRIVATE_STORAGE_ROOT');
  const report=await validateRealArchive(args[0],args[1],{runtimeRoot:args[2],outputReport:args[3],storageRoot:args[4]});
  console.log(JSON.stringify(report));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  main(process.argv.slice(2)).catch(()=>{console.error('Closed real restore failed. No customer values are included in this message.');process.exitCode=1;});
}
