// Synthetic, offline fixtures. Never import from the deployed Worker.
import { createHash, randomBytes } from 'node:crypto';
import { AccountState } from './account_state.js';
import { MemoryStorage, MemoryKV } from './fixture-account.mjs';
import { setEntitlement } from './entitlements.js';
import { signSession } from './user_auth.js';
import { snapshotStorage } from './durable_backup.js';
import { readClosedObject, readClosedKV, encodeClosedKVEntry } from '../../tools/domain_migration/closed_restore.mjs';

export const SYNTHETIC_USER = 'google_closed_backup';
export const DELETED_USER = 'apple_closed_deleted';
const hash = value => createHash('sha256').update(value).digest('hex');
export const identities = {
  active: { className: 'AccountState', namespaceId: 'a'.repeat(32), objectId: '1'.repeat(64) },
  deleted: { className: 'AccountState', namespaceId: 'a'.repeat(32), objectId: '2'.repeat(64) },
  directory: { className: 'AccountState', namespaceId: 'a'.repeat(32), objectId: '3'.repeat(64) },
  claim: { className: 'PurchaseClaims', namespaceId: 'b'.repeat(32), objectId: '4'.repeat(64) },
  traffic: { className: 'TrafficState', namespaceId: 'c'.repeat(32), objectId: '5'.repeat(64) },
};

// MemoryStorage's existing tests use a small transaction API. This subclass
// adds snapshot iteration/alarm access locally, without changing those tests.
export class BackupMemoryStorage extends MemoryStorage {
  async put(key, value) {
    if (typeof key === 'object') { for (const [name, entry] of Object.entries(key)) await super.put(name, entry); }
    else await super.put(key, value);
  }
  async list({ prefix = '', start, startAfter, end, limit = 1000, reverse = false } = {}) {
    let entries = [...this.data].filter(([key]) => key.startsWith(prefix)
      && (start === undefined || key >= start) && (startAfter === undefined || key > startAfter)
      && (end === undefined || key < end)).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
    if (reverse) entries.reverse();
    return new Map(entries.slice(0, limit).map(([key, value]) => [key, structuredClone(value)]));
  }
  async transaction(fn) {
    const result = this.tail.then(async () => {
      const view = new BackupMemoryStorage(); view.data = structuredClone(this.data); view.alarm = this.alarm;
      const txn = {
        get: view.get.bind(view), put: view.put.bind(view), delete: view.delete.bind(view),
        list: view.list.bind(view), getAlarm: view.getAlarm.bind(view), setAlarm: view.setAlarm.bind(view),
      };
      const value = await fn(txn);
      if (this.failCommit) { this.failCommit = false; throw new Error('Synthetic commit failure'); }
      this.data = view.data; this.alarm = view.alarm;
      return value;
    });
    this.tail = result.catch(() => {}); return result;
  }
}

export async function syntheticBackup() {
  const credentials = {
    SHARED_SECRET: crypto.randomUUID(), SESSION_SECRET: crypto.randomUUID(),
    PLATEGA_SECRET: crypto.randomUUID(), PLATEGA_MERCHANT_ID: crypto.randomUUID(),
  };
  const epoch = 'closed-fixture-epoch-7', runId = crypto.randomUUID(), objects = new Map();
  const user = { id: SYNTHETIC_USER, provider: 'google', name: 'Синтетический тест Әлібек',
    email: 'closed-backup@example.invalid', createdAt: '2026-01-02T03:04:05.000Z' };
  for (const [source, expiry] of Object.entries({ appstore: '2099-01-01T12:34:56.789Z',
    googleplay: '2099-02-02T12:34:56.789Z', web: '2099-03-03T12:34:56.789Z',
    admin_grant: '2099-04-04T12:34:56.789Z' })) setEntitlement(user, source, expiry);
  const ledger = { awarded: true, expiresAt: user.entitlements.web.expiresAt, tier: 'weekly', days: 7,
    amount: 99, txId: 'closed-confirmed-transaction', at: '2026-10-18T10:20:30.000Z' };
  const orderIds = Object.fromEntries(['confirmed', 'pending', 'creation_unknown', 'requires_refund']
    .map((status, index) => [status, `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`]));
  user.webPayments = { [orderIds.confirmed]: structuredClone(ledger) };
  const progress = { resetAt: 100, settings: { language: 'kk', sound: false },
    streak: { current: 8, longest: 25, activeDays: ['2026-10-18'], lastActiveDate: '2026-10-18' },
    game: { bestScore: 937, garageCars: [{ id: 'sedan', paint: 'blue' }], garageCorrect: 102,
      garageUnlocks: 3, vehicle: 'sedan', vehiclePaint: 'blue' },
    miniGames: { regulator: { bestScore: 24 }, signs: { totalSolved: 88 }, crossroads: { maxCombo: 12 } },
  };
  for (const suffix of ['Ab', 'Cd']) {
    progress['questionProgress' + suffix] = Object.fromEntries(Array.from({ length: 800 }, (_, i) =>
      ['question-' + i, { correct: i % 3 !== 0, answeredAt: 1000 + i, attemptsCount: i + 1,
        comment: 'Қазақша мәтін; русский текст; 🚦 '.repeat(12) }]));
    progress['ticketProgress' + suffix] = { ticket1: { answeredAt: 2000, score: 18 } };
    progress['favorites' + suffix] = ['question-1'];
    progress['favoriteStates' + suffix] = { 'question-1': { present: true, updatedAt: 1800 },
      'question-2': { present: false, updatedAt: 1900 } };
    progress['examResults' + suffix] = [JSON.stringify({ completedAt: 2000, score: 19, passed: true })];
  }
  const expiration = Date.now() + 86400000;
  const tokens = {};
  for (const [name, generation, person] of [
    ['active', 'generation-2', user], ['oldGeneration', 'generation-1', user],
    ['revoked', 'generation-2', user], ['deleted', 'generation-before-delete', { id: DELETED_USER, provider: 'apple' }],
  ]) tokens[name] = await signSession(credentials, { user: person, expiresAt: expiration, generation });
  tokens.legacy = randomBytes(32).toString('hex');
  const kvEntries = [
    encodeClosedKVEntry({ key: 'user:' + SYNTHETIC_USER,
      value: JSON.stringify({ ...user, isPremium: false, entitlements: {} }), metadata: { stale: true } }),
    encodeClosedKVEntry({ key: 'user:' + DELETED_USER, value: JSON.stringify({ id: DELETED_USER, isPremium: true }) }),
    encodeClosedKVEntry({ key: 'auth_generation:' + SYNTHETIC_USER, value: 'generation-1' }),
    encodeClosedKVEntry({ key: 'user_progress:' + SYNTHETIC_USER, value: '{}' }),
    encodeClosedKVEntry({ key: 'auth_session:' + hash(tokens.legacy), expiration: Math.ceil(expiration / 1000),
      value: JSON.stringify({ user, generation: 'generation-1', expiresAt: expiration }) }),
    encodeClosedKVEntry({ key: 'closed-expired-session', value: 'expired', expiration: Math.floor(Date.now() / 1000) - 1 }),
    encodeClosedKVEntry({ key: 'closed-raw-bytes', value: Uint8Array.from([0, 255, 128, 1]), metadata: { binary: true } }),
  ];

  const active = new BackupMemoryStorage(); objects.set('active', active);
  const recorder = new AccountState({ storage: active }, { ACCOUNT_STATE_EPOCH: epoch });
  const doc = async (storage, key, value, options = {}) => {
    const account = storage === active ? recorder : new AccountState({ storage }, { ACCOUNT_STATE_EPOCH: epoch });
    await storage.transaction(txn => account.persistRecord(txn, { key,
      value: value === null ? null : typeof value === 'string' ? value : JSON.stringify(value), options }));
  };
  await active.put('account-id', SYNTHETIC_USER);
  await doc(active, 'user:' + SYNTHETIC_USER, user);
  await doc(active, 'user_progress:' + SYNTHETIC_USER, progress);
  await doc(active, 'auth_generation:' + SYNTHETIC_USER, 'generation-2');
  await doc(active, 'account_deleted:' + SYNTHETIC_USER, null);
  await doc(active, 'revoked_session:' + SYNTHETIC_USER + ':' + hash(tokens.revoked), String(expiration));
  await doc(active, 'payment_ledger:' + orderIds.confirmed, ledger);
  const orders = {};
  for (const status of ['confirmed', 'pending', 'creation_unknown']) {
    const order = orders[status] = { orderId: orderIds[status], userId: SYNTHETIC_USER,
      txId: status === 'creation_unknown' ? null : status === 'confirmed' ? ledger.txId : 'closed-pending-transaction',
      name: user.name, accountEmail: user.email, email: user.email, app: 'ru', client: 'web', method: 'sbp',
      tier: 'weekly', days: 7, amount: 99, currency: 'RUB', status,
      createdAt: '2026-10-17T10:20:30.000Z', ...(status === 'confirmed' ? { confirmedAt: ledger.at } : {}) };
    await doc(active, 'pay_order:' + order.orderId, order);
    if (order.txId) await doc(active, 'pay_tx:' + order.txId, order.orderId);
  }
  await doc(active, 'pay_intent:' + SYNTHETIC_USER,
    { email: user.email, tier: 'weekly', method: 'sbp', lastOrder: { orderId: orderIds.creation_unknown } });
  await active.put('projection:user:' + SYNTHETIC_USER, { key: 'user:' + SYNTHETIC_USER });
  await active.put('index:pay_order:' + orderIds.pending, orders.pending);
  await active.put('effect:closed-fixture-notification', { kind: 'telegram', text: 'Must stay quarantined', dedupKey: 'closed' });
  await active.setAlarm(Date.now() + 60000);

  const deleted = new BackupMemoryStorage(); objects.set('deleted', deleted);
  await deleted.put('account-id', DELETED_USER);
  await doc(deleted, 'user:' + DELETED_USER, null);
  await doc(deleted, 'user_progress:' + DELETED_USER, null);
  await doc(deleted, 'auth_generation:' + DELETED_USER, 'generation-after-delete');
  await doc(deleted, 'account_deleted:' + DELETED_USER, { at: Date.parse('2026-10-18T00:00:00.000Z') });
  const refund = orders.requires_refund = { ...orders.pending, orderId: orderIds.requires_refund,
    userId: DELETED_USER, txId: 'closed-refund-transaction', name: '', accountEmail: '', status: 'requires_refund', supportReason: 'account_deleted' };
  await doc(deleted, 'pay_order:' + refund.orderId, refund);
  await doc(deleted, 'pay_tx:' + refund.txId, refund.orderId);
  const lateDeleted = orders.lateDeleted = { ...refund,
    orderId: '00000000-0000-4000-8000-000000000005', txId: 'closed-late-deleted-transaction', status: 'pending' };
  delete lateDeleted.supportReason;
  await doc(deleted, 'pay_order:' + lateDeleted.orderId, lateDeleted);
  await doc(deleted, 'pay_tx:' + lateDeleted.txId, lateDeleted.orderId);

  const directory = new BackupMemoryStorage(); objects.set('directory', directory);
  for (const order of Object.values(orders)) {
    await directory.put('order:' + order.orderId,
      { userId: order.userId, orderId: order.orderId, status: order.status, createdAt: order.createdAt });
    if (order.txId) await directory.put('tx:' + order.txId, order.userId);
  }
  const claim = new BackupMemoryStorage(); objects.set('claim', claim); await claim.put('owner', SYNTHETIC_USER);
  const traffic = new BackupMemoryStorage(); objects.set('traffic', traffic);
  await traffic.put({ key: 'game_lb:2026-W43', value: { [SYNTHETIC_USER]: { score: 937, runs: 3, best: 400 } },
    ['ranking:' + SYNTHETIC_USER]: { score: 937, runs: ['closed-run-1'], pointsByDay: { '2026-10-19': 937 } },
    'out:closed-event': { id: 'closed-event', kind: 'analytics', event: { type: 'game' }, telegram: { text: 'Do not send' } } });
  await traffic.setAlarm(Date.now() + 60000);
  const snapshots = [];
  for (const [name, storage] of objects) snapshots.push(await snapshotStorage({ storage },
    { ...identities[name], runId, sourceVersion: 'synthetic-closed-rehearsal', accountEpoch: epoch }));
  return { snapshots, objects, user, progress, orders, ledger, tokens, credentials, epoch, kvEntries, backupKey: randomBytes(32) };
}

// Account handlers run on a disposable copy. Their real domain logic executes,
// but alarms/flush never run; quarantined effects/index/projection jobs remain.
export function guardedApplicationFixture(target, synthetic) {
  const states = new Map(), accounts = new Map(), signals = { scheduled: 0, flushes: 0 };
  const archivedEpoch = readClosedObject(target, identities.active).metadata.accountEpoch;
  if (synthetic.epoch !== archivedEpoch) throw new Error('Closed fixture epoch must match restored evidence');
  for (const name of ['active', 'deleted', 'directory', 'claim', 'traffic']) {
    const raw = readClosedObject(target, identities[name]), storage = new BackupMemoryStorage();
    if (raw.metadata.accountEpoch !== archivedEpoch) throw new Error('Mixed closed fixture epoch');
    storage.data = raw.entries;
    storage.setAlarm = async () => { signals.scheduled++; }; // record intent only
    states.set(name, storage);
  }
  const env = { ...synthetic.credentials, INSTALLS: new MemoryKV(), ACCOUNT_STATE_REQUIRED: 'true',
    PLATEGA_API: 'https://provider.closed.invalid' };
  Object.defineProperty(env, 'ACCOUNT_STATE_EPOCH', { value: archivedEpoch, enumerable: true, writable: false, configurable: false });
  const expirations = new Map();
  for (const entry of readClosedKV(target)) {
    if (entry.key === 'closed-raw-bytes') continue; // binary evidence is asserted directly, not a text KV document
    env.INSTALLS.data.set(entry.key, new TextDecoder('utf-8', { fatal: true }).decode(entry.value));
    if (entry.metadata !== null) env.INSTALLS.meta.set(entry.key, entry.metadata);
    if (entry.expiration !== null) expirations.set(entry.key, entry.expiration);
  }
  const kvGet = env.INSTALLS.get.bind(env.INSTALLS);
  env.INSTALLS.get = async (key, options) => expirations.has(key) && expirations.get(key) * 1000 <= Date.now()
    ? null : kvGet(key, options);
  class QuarantinedAccount extends AccountState {
    async flush() { signals.flushes++; }
    async scheduleExpiry() { signals.scheduled++; }
    async alarm() { throw new Error('Closed fixture alarms are quarantined'); }
  }
  const names = new Map([[SYNTHETIC_USER, 'active'], [DELETED_USER, 'deleted'], ['payment-directory', 'directory']]);
  env.ACCOUNTS = Object.freeze({
    // LOCAL fixture routing only, not a namespace identity migration.
    idFromName: name => { if (!names.has(name)) throw new Error('Unknown closed fixture identity'); return name; },
    get: name => {
      if (!names.has(name)) throw new Error('Unknown closed fixture identity');
      if (!accounts.has(name)) accounts.set(name, new QuarantinedAccount({ storage: states.get(names.get(name)) }, env));
      return { fetch: (request, options) => accounts.get(name).fetch(
        typeof request === 'string' ? new Request(request, options) : request) };
    },
  });
  const request = (path, body, token, extra = {}) => new Request('https://closed.invalid' + path, {
    method: body === undefined ? 'GET' : 'POST', headers: { 'content-type': 'application/json',
      'x-install-secret': env.SHARED_SECRET, ...(token ? { authorization: 'Bearer ' + token } : {}), ...extra },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { env, states, accounts, signals, request };
}

export async function denyNetwork(fn, providerTransactions = new Map()) {
  const original = globalThis.fetch, counts = { blocked: 0, providerMocks: 0, outgoing: 0 };
  globalThis.fetch = async (input, options) => {
    const url = new URL(typeof input === 'string' ? input : input.url);
    const method = options?.method || input.method || 'GET';
    const tx = url.origin === 'https://provider.closed.invalid' && method === 'GET'
      ? providerTransactions.get(decodeURIComponent(url.pathname.replace(/^\/transaction\//, ''))) : null;
    if (tx) { counts.providerMocks++; return Response.json(structuredClone(tx)); }
    counts.blocked++;
    throw new Error('Network denied in closed backup rehearsal');
  };
  try { return await fn(counts); } finally { globalThis.fetch = original; }
}
