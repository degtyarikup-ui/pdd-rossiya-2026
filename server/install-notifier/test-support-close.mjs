import test from 'node:test';
import assert from 'node:assert/strict';
import { processTelegramMessageUpdate, handleSupportSendMessage, handleSupportGetMessages } from './support_chat.js';

function fakeKv(init = {}) {
  const data = new Map(Object.entries(init));
  return {
    get: async (k, opt) => { const v = data.get(k); return v == null ? null : (opt?.type === 'json' ? JSON.parse(v) : v); },
    put: async (k, v) => { data.set(k, v); },
  };
}

test('/close in the user topic sends a closed notice, closes the topic; a new user message reopens it', async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push(String(url).split('/').pop());
    return new Response(JSON.stringify({ ok: true, result: {} }));
  };
  const env = {
    BOT_TOKEN: 't', CHAT_ID: '-100',
    INSTALLS: fakeKv({
      'support:thread:7': 'user_1',
      'support:client:user_1': JSON.stringify({ threadId: 7, userName: 'Иван' }),
      'tg:webhook_active': '1',
    }),
  };

  const handled = await processTelegramMessageUpdate({ chat: { id: -100 }, from: {}, message_thread_id: 7, message_id: 55, text: '/close@PddBot' }, env);
  assert.equal(handled, true);
  const list = await (await handleSupportGetMessages(new Request('https://x/api/support/messages?clientId=user_1'), env)).json();
  assert.equal(list.messages.length, 1);
  assert.equal(list.messages[0].kind, 'closed');
  assert.equal(list.messages[0].sender, 'support');
  assert.match(list.messages[0].text, /Обращение завершено/);
  assert.equal((await env.INSTALLS.get('support:client:user_1', { type: 'json' })).closed, true);
  assert.ok(calls.includes('closeForumTopic'));

  await handleSupportSendMessage(new Request('https://x/api/support/send', { method: 'POST', body: JSON.stringify({ clientId: 'user_1', text: 'Ещё вопрос' }) }), env);
  assert.ok(calls.includes('reopenForumTopic'));
  assert.equal((await env.INSTALLS.get('support:client:user_1', { type: 'json' })).closed, false);
});

test('ordinary operator text is a normal reply, not a close', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ ok: true }));
  const env = { BOT_TOKEN: 't', CHAT_ID: '-100', INSTALLS: fakeKv({ 'support:thread:7': 'u2', 'tg:webhook_active': '1' }) };
  await processTelegramMessageUpdate({ chat: { id: -100 }, from: {}, message_thread_id: 7, message_id: 56, text: 'please /close later' }, env);
  const list = await (await handleSupportGetMessages(new Request('https://x/api/support/messages?clientId=u2'), env)).json();
  assert.equal(list.messages[0].kind, undefined);
});
