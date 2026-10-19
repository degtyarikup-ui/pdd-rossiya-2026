// Source builders for a temporary read-only production export. The original
// deployed modules are retained byte-for-byte; these builders never deploy.
export const BACKUP_CLASS_NAMES = Object.freeze([
  'AccountState', 'PurchaseClaims', 'TrafficState', 'StatsBuffer', 'TelegramQueue',
  'NotificationsState', 'SupportThread', 'TelegramAuthState', 'AiQuotaState',
]);
const fail = () => { throw new Error('Invalid production backup wrapper configuration'); };
function moduleName(value) {
  if (typeof value !== 'string' || value.length > 240 || !/^[A-Za-z0-9_./-]+\.(?:m?js)$/.test(value)
    || value.startsWith('/') || value.split('/').some(part => !part || part === '.' || part === '..')) fail();
  return './' + value;
}
function classesChecked(classes) {
  if (!Array.isArray(classes) || classes.length !== BACKUP_CLASS_NAMES.length
    || new Set(classes).size !== classes.length || classes.some(name => !BACKUP_CLASS_NAMES.includes(name))) fail();
  return classes;
}

export function buildBackupWrapper({ originalMain, helperModule = 'durable_backup_bundle.mjs', classes = BACKUP_CLASS_NAMES } = {}) {
  const original = JSON.stringify(moduleName(originalMain)), helper = JSON.stringify(moduleName(helperModule));
  if (original === helper) fail();
  classesChecked(classes);
  return `// Temporary read-only adapter. Original modules and their names are unchanged.
import * as Original from ${original};
export { default } from ${original};
export * from ${original};
import { isBackupRequest, handleBackupExport } from ${helper};
const backupState = Symbol('backupState');
const backupEnv = Symbol('backupEnv');
${classes.map(className => `export class ${className} extends Original.${className} {
  constructor(state, env) { super(state, env); this[backupState] = state; this[backupEnv] = env; }
  fetch(request) {
    if (!isBackupRequest(request)) return super.fetch(request);
    const read = () => handleBackupExport(request, { state: this[backupState], env: this[backupEnv], className: '${className}' });
    return typeof this.serial === 'function' ? this.serial(read) : read();
  }
}`).join('\n')}
`;
}

export function buildBrokerWorker({ helperModule = 'durable_backup_bundle.mjs', bindings = Object.fromEntries(BACKUP_CLASS_NAMES.map(name => [name, 'BACKUP_' + name])) } = {}) {
  const helper = JSON.stringify(moduleName(helperModule));
  if (!bindings || typeof bindings !== 'object' || Object.keys(bindings).length !== BACKUP_CLASS_NAMES.length
    || BACKUP_CLASS_NAMES.some(name => typeof bindings[name] !== 'string' || !/^[A-Za-z_][A-Za-z0-9_]{0,127}$/.test(bindings[name]))
    || new Set(Object.values(bindings)).size !== BACKUP_CLASS_NAMES.length) fail();
  return `// Temporary export-only broker. No restore, storage writes, business handlers or logs.
import { BACKUP_PATH, BACKUP_LIMITS, verifyBackupHmac } from ${helper};
const bindings = Object.freeze(${JSON.stringify(bindings)});
const headers = { 'Cache-Control': 'no-store, private', 'Pragma': 'no-cache', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
const denied = () => Response.json({ error: 'Backup unavailable' }, { status: 404, headers });
async function boundedBody(request) {
  const declared = request.headers.get('content-length');
  if (declared !== null && (!/^[0-9]+$/.test(declared) || Number(declared) > BACKUP_LIMITS.maxRequestBytes)) throw new Error();
  if (!request.body) throw new Error();
  const reader = request.body.getReader(), chunks = []; let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > BACKUP_LIMITS.maxRequestBytes) { await reader.cancel(); throw new Error(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}
export default {
  async fetch(request, env) {
    try {
      const now = Date.now(), until = Date.parse(env.DURABLE_BACKUP_UNTIL || ''), url = new URL(request.url);
      if (env.DURABLE_BACKUP_ENABLED !== 'true' || !Number.isFinite(until) || until <= now
        || until - now > BACKUP_LIMITS.maxEnableWindowMs || request.method !== 'POST'
        || url.pathname !== BACKUP_PATH || url.search || url.hash) return denied();
      const raw = await boundedBody(request), signature = request.headers.get('x-backup-signature');
      if (!await verifyBackupHmac(env.DURABLE_BACKUP_HMAC_SECRET, 'POST\\n' + BACKUP_PATH + '\\n' + raw, signature)) return denied();
      const body = JSON.parse(raw), namespaceIds = JSON.parse(env.DURABLE_BACKUP_NAMESPACE_IDS || 'null');
      if (!body || typeof body !== 'object' || Array.isArray(body)
        || Object.keys(body).sort().join(',') !== 'accountEpoch,className,format,issuedAt,namespaceId,nonce,objectId,recipientJwk,runId,sourceVersion'
        || body.format !== 1 || !Object.hasOwn(bindings, body.className)
        || typeof body.namespaceId !== 'string' || !/^[a-f0-9]{32}$/.test(body.namespaceId)
        || typeof body.objectId !== 'string' || !/^[a-f0-9]{64}$/.test(body.objectId)
        || !namespaceIds || !Object.hasOwn(namespaceIds, body.className) || namespaceIds[body.className] !== body.namespaceId
        || typeof env.DURABLE_BACKUP_RUN_ID !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(env.DURABLE_BACKUP_RUN_ID)
        || body.runId !== env.DURABLE_BACKUP_RUN_ID || body.sourceVersion !== env.DURABLE_BACKUP_SOURCE_VERSION
        || body.accountEpoch !== String(env.ACCOUNT_STATE_EPOCH || '1')
        || !Number.isSafeInteger(body.issuedAt) || Math.abs(now - body.issuedAt) > BACKUP_LIMITS.maxClockSkewMs
        || typeof body.nonce !== 'string' || !/^[A-Za-z0-9_-]{22,171}$/.test(body.nonce)) return denied();
      const namespace = env[bindings[body.className]];
      if (!namespace || typeof namespace.idFromString !== 'function' || typeof namespace.get !== 'function') return denied();
      const response = await namespace.get(namespace.idFromString(body.objectId)).fetch(new Request('https://durable-backup.internal' + BACKUP_PATH,
        { method: 'POST', headers: { 'content-type': 'application/json', 'x-backup-signature': signature }, body: raw }));
      const responseSignature = response.headers.get('x-backup-response-signature');
      if (response.status !== 200 || response.headers.get('content-type') !== 'application/jose'
        || !/^[A-Za-z0-9_-]{43}$/.test(responseSignature || '')) return denied();
      return new Response(response.body, { status: 200,
        headers: { ...headers, 'Content-Type': 'application/jose', 'X-Backup-Response-Signature': responseSignature } });
    } catch { return denied(); }
  },
};
`;
}
