import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';

test('Telegram route GET probe is public and CORS-enabled without auth, payment, nonce, webhook or notification side effects', async () => {
  const effects = [], tasks = [], fixtureAccess = 'test-only';
  const forbidden = name => () => { effects.push(name); throw new Error('Unexpected side effect'); };
  const env = {
    SHARED_SECRET: fixtureAccess, SESSION_SECRET: fixtureAccess, BOT_TOKEN: fixtureAccess, CHAT_ID: fixtureAccess,
    INSTALLS: { get: async () => null, list: async () => ({ keys: [], list_complete: true }),
      put: forbidden('kv.put'), delete: forbidden('kv.delete') },
    TG_AUTH: { idFromName: forbidden('tg_auth.id'), get: forbidden('tg_auth.get') },
    ACCOUNTS: { idFromName: forbidden('accounts.id'), get: forbidden('accounts.get') },
    TELEGRAM: { idFromName: forbidden('telegram.id'), get: forbidden('telegram.get') },
  };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = forbidden('external.fetch');
  try {
    for (const available of [false, true]) {
      const configured = { ...env, ...(available ? { PLATEGA_MERCHANT_ID: fixtureAccess, PLATEGA_SECRET: fixtureAccess } : {}) };
      for (const host of ['https://pdd-install-notifier.sergei-pdd.workers.dev', 'https://api.pdd-drive.app']) {
      const result = await worker.fetch(new Request(host + '/api/pay/status', { method: 'GET' }), configured,
        { waitUntil: task => tasks.push(task) });
      assert.equal(result.status, 200);
      assert.deepEqual(await result.json(), { ok: true, available, methods: ['sbp'] });
      assert.equal(result.headers.get('access-control-allow-origin'), '*');
      assert.equal(result.headers.get('cache-control'), 'no-store');
      }
    }
    await Promise.all(tasks);
    assert.deepEqual(effects, []);
    assert.equal(tasks.length, 0);
  } finally { globalThis.fetch = originalFetch; }
});
