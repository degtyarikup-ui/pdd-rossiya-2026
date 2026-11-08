import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  handleTelegramAuthRequest,
  handleTelegramAuthCheck,
  processTelegramAuthMessage,
} from './telegram_auth.js';

class MockKV {
  constructor() {
    this.map = new Map();
  }
  async get(key) {
    return this.map.get(key) || null;
  }
  async put(key, value) {
    this.map.set(key, String(value));
  }
  async delete(key) {
    this.map.delete(key);
  }
}

const mockEnv = () => ({
  INSTALLS: new MockKV(),
  SHARED_SECRET: 'test-secret',
  SESSION_SECRET: 'test-session-secret',
  BOT_TOKEN: '123456:TEST_TOKEN',
  TELEGRAM_BOT_USERNAME: 'pdda_bot',
});

test('handleTelegramAuthRequest requires SHARED_SECRET', async () => {
  const env = mockEnv();
  const req = new Request('https://test/api/auth/telegram/request', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
  });
  const res = await handleTelegramAuthRequest(req, env);
  assert.equal(res.status, 403);
});

test('handleTelegramAuthRequest creates pending auth and returns URLs', async () => {
  const env = mockEnv();
  const req = new Request('https://test/api/auth/telegram/request', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-install-secret': 'test-secret',
    },
  });
  const res = await handleTelegramAuthRequest(req, env);
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.ok, true);
  assert.ok(data.nonce.startsWith('auth_'));
  assert.equal(data.botUsername, 'pdda_bot');
  assert.equal(data.botUrl, `https://t.me/pdda_bot?start=${data.nonce}`);
  assert.equal(data.tgUrl, `tg://resolve?domain=pdda_bot&start=${data.nonce}`);

  // Проверяем запись в KV
  const stored = JSON.parse(await env.INSTALLS.get('tg_auth:' + data.nonce));
  assert.equal(stored.status, 'pending');
});

test('processTelegramAuthMessage confirms auth on /start with valid nonce', async () => {
  const env = mockEnv();
  const nonce = 'auth_test_12345';
  await env.INSTALLS.put(
    'tg_auth:' + nonce,
    JSON.stringify({ status: 'pending', createdAt: Date.now() })
  );

  const sentMessages = [];
  const origFetch = globalThis.fetch;
  globalThis.fetch = async (url, opts) => {
    sentMessages.push({ url, body: JSON.parse(opts.body) });
    return new Response('{"ok":true}', { status: 200 });
  };

  try {
    const msg = {
      text: '/start ' + nonce,
      chat: { id: 998877, type: 'private' },
      from: {
        id: 998877,
        first_name: 'Иван',
        last_name: 'Петров',
        username: 'ivan_p',
      },
    };

    const handled = await processTelegramAuthMessage(msg, env, true);
    assert.equal(handled, true);

    const stored = JSON.parse(await env.INSTALLS.get('tg_auth:' + nonce));
    assert.equal(stored.status, 'confirmed');
    assert.equal(stored.user.id, 'telegram_998877');
    assert.equal(stored.user.name, 'Иван Петров');
    assert.equal(stored.user.provider, 'telegram');

    assert.equal(sentMessages.length, 1);
    assert.equal(sentMessages[0].body.chat_id, 998877);
    assert.ok(sentMessages[0].body.text.includes('Вход подтверждён'));
  } finally {
    globalThis.fetch = origFetch;
  }
});

test('handleTelegramAuthCheck lifecycle: pending -> confirmed -> claimed (one-time)', async () => {
  const env = mockEnv();
  const nonce = 'auth_lifecycle_123';
  await env.INSTALLS.put(
    'tg_auth:' + nonce,
    JSON.stringify({ status: 'pending', createdAt: Date.now() })
  );

  const mockSign = async (_env, entry) => 'mock-jwt-token.' + entry.user.id;

  // 1. Пока pending — возвращает { ok: false, status: 'pending' }
  const reqPending = new Request('https://test/api/auth/telegram/check', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-install-secret': 'test-secret',
    },
    body: JSON.stringify({ nonce }),
  });
  const resPending = await handleTelegramAuthCheck(reqPending, env, mockSign);
  assert.equal(resPending.status, 200);
  assert.deepEqual(await resPending.json(), { ok: false, status: 'pending' });

  // 2. Имитируем подтверждение в боте
  await env.INSTALLS.put(
    'tg_auth:' + nonce,
    JSON.stringify({
      status: 'confirmed',
      user: {
        id: 'telegram_123',
        name: 'Тестер',
        email: '',
        avatarUrl: null,
        provider: 'telegram',
        createdAt: new Date().toISOString(),
      },
      confirmedAt: Date.now(),
    })
  );

  // 3. Запрос проверки confirmed — выдаёт сессию и удаляет nonce
  const reqConfirmed = new Request('https://test/api/auth/telegram/check', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-install-secret': 'test-secret',
    },
    body: JSON.stringify({ nonce }),
  });
  const resConfirmed = await handleTelegramAuthCheck(reqConfirmed, env, mockSign);
  assert.equal(resConfirmed.status, 200);
  const dataConfirmed = await resConfirmed.json();
  assert.equal(dataConfirmed.ok, true);
  assert.equal(dataConfirmed.status, 'confirmed');
  assert.equal(dataConfirmed.user.id, 'telegram_123');
  assert.equal(dataConfirmed.token, 'mock-jwt-token.telegram_123');

  // 4. Повторный запрос того же nonce — уже expired (защита от replay-атак)
  const reqReplay = new Request('https://test/api/auth/telegram/check', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-install-secret': 'test-secret',
    },
    body: JSON.stringify({ nonce }),
  });
  const resReplay = await handleTelegramAuthCheck(reqReplay, env, mockSign);
  assert.equal(resReplay.status, 200);
  assert.deepEqual(await resReplay.json(), { ok: false, status: 'expired' });
});
