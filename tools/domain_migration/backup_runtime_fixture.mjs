// TEST ONLY. Never import this module into the production Worker. Seed/read
// routes are bundled solely by test_backup_runtime.mjs in an isolated workerd.
import {
  AccountState as RealAccountState, PurchaseClaims as RealPurchaseClaims,
  TrafficState as RealTrafficState, StatsBuffer as RealStatsBuffer,
  TelegramQueue as RealTelegramQueue, NotificationsState as RealNotificationsState,
  SupportThread as RealSupportThread, TelegramAuthState as RealTelegramAuthState,
  AiQuotaState as RealAiQuotaState,
} from '../../server/install-notifier/worker.js';
import { BACKUP_PATH, encodeValue, decodeValue } from '../../server/install-notifier/durable_backup.js';

const names = ['AccountState', 'PurchaseClaims', 'TrafficState', 'StatsBuffer', 'TelegramQueue', 'NotificationsState', 'SupportThread', 'TelegramAuthState', 'AiQuotaState'];
async function fixtureRoute(object, request) {
  const path = new URL(request.url).pathname;
  if (path === '/__fixture/seed') {
    const { entries, alarm } = await request.json();
    if (object.env.FIXTURE_RESTORE_ONLY === 'true' && alarm !== null) throw new Error('Restored fixtures must have no scheduled alarm');
    if ((await object.state.storage.list({ limit: 1 })).size) throw new Error('Fixture must start empty');
    await object.state.storage.transaction(async txn => {
      for (const entry of entries) await txn.put(entry.key, decodeValue(entry.value));
      if (alarm !== null) await txn.setAlarm(alarm);
    });
    return Response.json({ seeded: true, objectId: object.state.id.toString() });
  }
  if (path === '/__fixture/inspect') {
    const entries = await object.state.storage.list();
    const sqliteProof = [...object.state.storage.sql.exec('SELECT 1 AS proof')][0].proof;
    return Response.json({ sqliteProof, alarm: await object.state.storage.getAlarm(),
      entries: [...entries].map(([key, value]) => ({ key, value: encodeValue(value) })) });
  }
  if (path === '/__fixture/mutate') {
    if (object.env.FIXTURE_RESTORE_ONLY === 'true') return new Response('Restored evidence is quarantined', { status: 404 });
    const { version } = await request.json();
    await object.state.storage.transaction(async txn => {
      await txn.put('version:a', version);
      await txn.put('version:b', version);
    });
    return Response.json({ committed: true });
  }
  return null;
}
function instrument(Base) {
  return class extends Base {
    async fetch(request) {
      const response = await fixtureRoute(this, request);
      // A restored test object cannot execute the real account/outbox/payment
      // handlers. Only the isolated fixture's seed/inspection routes exist.
      if (!response && this.env.FIXTURE_RESTORE_ONLY === 'true') return new Response('Restored evidence is quarantined', { status: 404 });
      return response || super.fetch(request);
    }
  };
}
export const AccountState = instrument(RealAccountState);
export const PurchaseClaims = instrument(RealPurchaseClaims);
export const TrafficState = instrument(RealTrafficState);
export const StatsBuffer = instrument(RealStatsBuffer);
export const TelegramQueue = instrument(RealTelegramQueue);
export const NotificationsState = instrument(RealNotificationsState);
export const SupportThread = instrument(RealSupportThread);
export const TelegramAuthState = instrument(RealTelegramAuthState);
export const AiQuotaState = instrument(RealAiQuotaState);

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/__fixture/egress') return fetch('https://egress-is-forbidden.invalid/');
    if (path !== BACKUP_PATH || request.method !== 'POST') return new Response('test fixture only', { status: 404 });
    const body = await request.clone().json();
    if (!names.includes(body.className) || typeof body.objectId !== 'string') return new Response('test fixture only', { status: 404 });
    return env[body.className].get(env[body.className].idFromString(body.objectId)).fetch(request);
  },
};
