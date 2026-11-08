import test from 'node:test';
import assert from 'node:assert/strict';
import { SupportThread } from './support_thread.js';

function fakeState() {
  const data = new Map();
  const storage = {
    get: async (k) => data.get(k),
    put: async (k, v) => { data.set(k, v); },
    transaction: async (fn) => fn(storage),
  };
  return { storage };
}

const post = (path, body) => new Request('https://x' + path, { method: 'POST', body: JSON.stringify(body) });
const get = (path) => new Request('https://x' + path, { method: 'GET' });

test('reply written is read at once, since filters by server time, duplicates are ignored', async () => {
  const thread = new SupportThread(fakeState());
  await thread.fetch(post('/append', { id: 'u1', sender: 'user', text: 'Привет', ts: 1000 }));
  await thread.fetch(post('/append', { id: 'tg_9', sender: 'support', text: 'Здравствуйте', ts: 2000 }));
  await thread.fetch(post('/append', { id: 'tg_9', sender: 'support', text: 'Здравствуйте', ts: 2000 }));
  const all = await (await thread.fetch(get('/list'))).json();
  assert.deepEqual(all.messages.map((m) => m.id), ['u1', 'tg_9']);
  const fresh = await (await thread.fetch(get('/list?since=1500'))).json();
  assert.deepEqual(fresh.messages.map((m) => m.id), ['tg_9']);
});

test('keeps the last 200 messages and rejects a message without id or time', async () => {
  const thread = new SupportThread(fakeState());
  for (let i = 0; i < 205; i++) await thread.fetch(post('/append', { id: 'm' + i, sender: 'user', text: 't', ts: i + 1 }));
  const all = await (await thread.fetch(get('/list'))).json();
  assert.equal(all.messages.length, 200);
  assert.equal(all.messages[0].id, 'm5');
  const bad = await thread.fetch(post('/append', { sender: 'user' }));
  assert.equal(bad.status, 400);
});

test('seed copies the legacy messages once and never overwrites a thread that has messages', async () => {
  const thread = new SupportThread(fakeState());
  await thread.fetch(post('/seed', [{ id: 'old', sender: 'user', text: 'a', ts: 1 }]));
  await thread.fetch(post('/seed', [{ id: 'other', sender: 'user', text: 'b', ts: 2 }]));
  const all = await (await thread.fetch(get('/list'))).json();
  assert.deepEqual(all.messages.map((m) => m.id), ['old']);
});

test('persists and lists messages with imageUrl', async () => {
  const thread = new SupportThread(fakeState());
  await thread.fetch(post('/append', {
    id: 'u_img',
    sender: 'user',
    text: 'Вот скриншот ошибки',
    imageUrl: '/api/support/file?fileId=abc123xyz',
    ts: 1000,
  }));
  await thread.fetch(post('/append', {
    id: 'tg_img',
    sender: 'support',
    text: 'Ответ с фото',
    imageUrl: '/api/support/file?fileId=def456uvw',
    ts: 2000,
  }));
  const all = await (await thread.fetch(get('/list'))).json();
  assert.equal(all.messages.length, 2);
  assert.equal(all.messages[0].imageUrl, '/api/support/file?fileId=abc123xyz');
  assert.equal(all.messages[1].imageUrl, '/api/support/file?fileId=def456uvw');
});
