import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { AccountState, PurchaseClaims, TrafficState, StatsBuffer, TelegramQueue,
  NotificationsState, SupportThread, TelegramAuthState, AiQuotaState } from './worker.js';
import { BACKUP_PATH } from './durable_backup.js';

const classes = [AccountState, PurchaseClaims, TrafficState, StatsBuffer, TelegramQueue,
  NotificationsState, SupportThread, TelegramAuthState, AiQuotaState];
test('all nine real DO classes reserve backup routes while disabled without touching storage or business handlers', async () => {
  let accesses = 0;
  const storage = new Proxy({}, { get() { accesses++; throw new Error('Storage forbidden'); } });
  for (const Class of classes) {
    const instance = new Class({ storage }, {});
    for (const path of [BACKUP_PATH, '/_backup/v1/restore', '/_backup/v2/export']) {
      const response = await instance.fetch(new Request('https://closed.invalid' + path, { method: 'POST', body: '{}' }));
      assert.equal(response.status, 404, Class.name);
      assert.deepEqual(await response.json(), { error: 'Backup unavailable' });
    }
  }
  assert.equal(accesses, 0);
});
test('public Worker never forwards backup paths to a DO, even with export enabled in its environment', async () => {
  let calls = 0;
  const forbidden = new Proxy({}, { get() { calls++; throw new Error('Binding access forbidden'); } });
  const env = { DURABLE_BACKUP_ENABLED: 'true', INSTALLS: forbidden };
  for (const binding of ['ACCOUNTS', 'PURCHASE_CLAIMS', 'TRAFFIC', 'STATS_BUFFER', 'TELEGRAM_QUEUE',
    'NOTIFICATIONS', 'SUPPORT_THREADS', 'TELEGRAM_AUTH', 'AI_QUOTA']) env[binding] = forbidden;
  for (const origin of ['https://pdd-drive.ru', 'https://api.pdd-drive.app']) {
    for (const path of [BACKUP_PATH, '/_backup/v1/restore']) {
      const response = await worker.fetch(new Request(origin + path, { method: 'POST', body: '{}' }), env);
      assert.notEqual(response.headers.get('content-type'), 'application/jose');
      assert.equal((await response.text()).includes('pdd-durable-backup'), false);
    }
  }
  assert.equal(calls, 0);
});
