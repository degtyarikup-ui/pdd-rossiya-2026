import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { sendSupportReplyPush, handleSupportSendMessage } from './support_chat.js';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const FCM_SERVICE_ACCOUNT = JSON.stringify({ project_id: 'test-project', client_email: 'sender@test.invalid',
  private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }) });

function fakeKv(init = {}) {
  const data = new Map(Object.entries(init));
  return {
    data,
    get: async (k, opt) => { const v = data.get(k); return v == null ? null : (opt?.type === 'json' ? JSON.parse(v) : v); },
    put: async (k, v) => { data.set(k, v); },
  };
}
const fcm = calls => async (url, opts) => {
  calls.push({ url, opts });
  return Response.json(url.includes('oauth2') ? { access_token: 't', expires_in: 3600 } : { name: 'projects/test-project/messages/1' });
};

test('operator reply goes as a push to the account topic when the app asked for it', async () => {
  const env = { FCM_SERVICE_ACCOUNT, SESSION_SECRET: 's', INSTALLS: fakeKv({
    'support:client:google_1': JSON.stringify({ threadId: 7, replyPush: true }) }) };
  const calls = [];
  assert.equal(await sendSupportReplyPush(env, 'google_1', { text: 'Здравствуйте! Проверили оплату.' }, fcm(calls)), true);
  const message = JSON.parse(calls.at(-1).opts.body).message;
  assert.match(message.topic, /^pdd_account_[a-f0-9]{64}$/);
  assert.equal(message.data.kind, 'support_reply');
  assert.equal(message.data.action, 'support');
  assert.equal(message.notification.body, 'Здравствуйте! Проверили оплату.');
});

test('no push for guests, old apps or when push is not configured', async () => {
  const calls = [];
  const kv = fakeKv({ 'support:client:guest_1': JSON.stringify({ threadId: 8 }) });
  assert.equal(await sendSupportReplyPush({ FCM_SERVICE_ACCOUNT, SESSION_SECRET: 's', INSTALLS: kv }, 'guest_1', { text: 'x' }, fcm(calls)), false);
  const on = fakeKv({ 'support:client:google_1': JSON.stringify({ threadId: 7, replyPush: true }) });
  assert.equal(await sendSupportReplyPush({ SESSION_SECRET: 's', INSTALLS: on }, 'google_1', { text: 'x' }, fcm(calls)), false);
  assert.equal(calls.length, 0);
});

test('a push request without the account session is not honoured', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ ok: true, result: {} }));
  const kv = fakeKv({ 'support:client:google_1': JSON.stringify({ threadId: 7, replyPush: true }) });
  const env = { BOT_TOKEN: 't', CHAT_ID: '-100', INSTALLS: kv };
  const response = await handleSupportSendMessage(new Request('https://x/api/support/send', {
    method: 'POST', body: JSON.stringify({ clientId: 'google_1', text: 'Привет', replyPush: true }),
  }), env);
  assert.equal(response.status, 200);
  assert.equal(JSON.parse(kv.data.get('support:client:google_1')).replyPush, false);
});
