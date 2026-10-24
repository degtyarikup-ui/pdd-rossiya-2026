import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reportQuestionDetails, reportSourceLabel } from './report_questions.js';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import worker, { sendTelegram, buildReportMessage } from './worker.js';
import { signSession, revokeUserSessions } from './user_auth.js';
import { TelegramQueue } from './telegram_queue.js';

class Storage {
  data = new Map(); alarm = null;
  async get(key) { return structuredClone(this.data.get(key)); }
  async put(key, value) { this.data.set(key, structuredClone(value)); }
  async delete(key) { this.data.delete(key); }
  async list({ prefix = '', limit = Infinity } = {}) { return new Map([...this.data].filter(([key]) => key.startsWith(prefix)).sort().slice(0, limit)); }
  async getAlarm() { return this.alarm; }
  async setAlarm(value) { this.alarm = value; }
  async transaction(fn) { return fn(this); }
}
function setup() {
  const env = { INSTALLS: new Storage(), BOT_TOKEN: 'test', CHAT_ID: 'test', SHARED_SECRET: 'test', SESSION_SECRET: 'test', TELEGRAM_TOPIC_ERRORS: '7', TELEGRAM_TOPIC_PURCHASES: '8', TELEGRAM_TOPIC_REGISTRATIONS: '9' };
  const state = { storage: new Storage() }, queue = new TelegramQueue(state, env);
  env.TELEGRAM = { idFromName: name => name, get: () => ({ fetch: (url, options) => queue.fetch(new Request(url, options)) }) };
  return { env, state };
}
const request = (body, token, path = '/') => new Request('https://test' + path, {
  method: body === undefined ? 'GET' : 'POST',
  headers: { 'content-type': 'application/json', 'x-install-secret': 'test', ...(token ? { authorization: 'Bearer ' + token } : {}) },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});
const session = (env, user, expiresAt = Date.now() + 60000) => signSession(env, { user, expiresAt, generation: '' });
const queued = async state => [...(await state.storage.list({ prefix: 'q:' })).values()];

test('complaints use their own topic and server profile, ignoring forged identity', async () => {
  const { env, state } = setup();
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ errors: 7, purchases: 8, registrations: 9, reports: 42 }));
  const user = { id: 'google_real', name: 'Old name', email: 'old@example.com' };
  await env.INSTALLS.put('user:' + user.id, JSON.stringify({ ...user, name: '<Иван & Анна>', email: 'real@example.com' }));
  const token = await session(env, user);
  const response = await worker.fetch(request({ kind: 'report', message: '<Опечатка>', question_id: 'ru_ab_21_4', ticket: 21, userId: 'victim', user: { name: 'Подмена', email: 'victim@example.com' }, email: 'victim@example.com' }, token), env);
  assert.equal(response.status, 200);
  const [item] = await queued(state);
  assert.equal(item.threadId, 42);
  assert.match(item.text, /&lt;Иван &amp; Анна&gt;/);
  assert.match(item.text, /real@example.com/);
  assert.match(item.text, /google_real/);
  assert.match(item.text, /&lt;Опечатка&gt;/);
  assert.match(item.text, /ru_ab_21_4/);
  assert.doesNotMatch(item.text, /victim|Подмена|Old name|old@example/);
});

test('guests, old clients, invalid, expired and revoked sessions can report without claiming an account', async () => {
  const { env, state } = setup();
  const user = { id: 'google_real', name: 'Private name', email: 'private@example.com' };
  const expired = await session(env, user, Date.now() - 1), revoked = await session(env, user);
  await revokeUserSessions(env, user.id);
  for (const token of [undefined, 'forged', expired, revoked]) {
    const response = await worker.fetch(request({ kind: 'report', message: 'Ошибка', name: user.name, email: user.email, user_id: user.id }, token), env);
    assert.equal(response.status, 200);
  }
  for (const item of await queued(state)) {
    assert.match(item.text, /Гость \(без подтверждённого входа\)/);
    assert.doesNotMatch(item.text, /Private name|private@example.com|google_real/);
  }
});

test('game complaints log verified email, device, OS, scene and question text', async () => {
  const { env, state } = setup();
  const user = { id: 'google_driver', name: 'Водитель', email: 'driver@example.com' };
  const token = await session(env, user);
  const response = await worker.fetch(request({
    kind: 'report', mode: 'city', question_id: 'ticket_8_15', ticket: 8,
    question_text: 'Кому уступить дорогу?', message: 'Машина едет неверно',
    device: 'Google Pixel 9', os: 'Android 16 (SDK 36)', version: '2.3.0+59',
    platform: 'android', email: 'forged@example.com',
  }, token), env);
  assert.equal(response.status, 200);
  const [item] = await queued(state);
  for (const field of ['driver@example.com', 'Google Pixel 9', 'Android 16', 'ticket_8_15', 'билет 8', 'Игра «Живой город»', 'Кому уступить дорогу?', '2.3.0+59']) {
    assert.ok(item.text.includes(field), field);
  }
  assert.doesNotMatch(item.text, /forged@example.com/);
});

test('verified session identity survives a missing profile or profile lookup failure', async () => {
  for (const failLookup of [false, true]) {
    const { env, state } = setup(), user = { id: 'apple_real', name: 'Иван', email: '' };
    const token = await session(env, user);
    if (failLookup) {
      const original = env.INSTALLS.get.bind(env.INSTALLS);
      env.INSTALLS.get = key => key.startsWith('user:') ? Promise.reject(new Error('unavailable')) : original(key);
    }
    assert.equal((await worker.fetch(request({ kind: 'report', message: 'Ошибка' }, token), env)).status, 200);
    const [item] = await queued(state);
    assert.match(item.text, /Иван/);
    assert.match(item.text, /Email:<\/b> —/);
    assert.doesNotMatch(item.text, /Гость/);
  }
});

test('topic setup reuses existing IDs and creates only the complaint topic once', async () => {
  const { env, state } = setup(), original = globalThis.fetch, calls = [];
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ support: 100 }));
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  let writes = 0;
  env.INSTALLS.put = async (key, value) => { if (key === 'telegram_topics') writes++; return put(key, value); };
  globalThis.fetch = async (url, options) => {
    calls.push(JSON.parse(options.body));
    assert.match(url, /createForumTopic$/);
    return Response.json({ ok: true, result: { message_thread_id: 42 } });
  };
  try {
    for (let i = 0; i < 2; i++) {
      const response = await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env);
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).topics, { errors: 7, purchases: 8, registrations: 9, reports: 42 });
    }
    assert.equal(calls.length, 1);
    assert.equal(writes, 1, 'one KV write for setup, none for an unchanged retry');
    assert.equal(calls[0].name, '🚩 Жалобы на вопросы');
    assert.equal(JSON.parse(await env.INSTALLS.get('telegram_topics')).support, 100);
    assert.equal((await queued(state)).length, 1, 'only the new topic gets an announcement');
    const response = await worker.fetch(request(undefined, null, '/api/admin/telegram/topics'), env);
    assert.equal((await response.json()).topics.reports, 42);
  } finally { globalThis.fetch = original; }
});

test('topic setup rejects unauthorized requests and invalid IDs without creating topics', async () => {
  const { env } = setup();
  const unauthorized = new Request('https://test/api/admin/telegram/setup-topics', { method: 'POST', body: '{}' });
  assert.equal((await worker.fetch(unauthorized, env)).status, 401);
  for (const reports of [0, -1, 1.5, 'oops', null, true, [], {}]) {
    const response = await worker.fetch(request({ reports }, null, '/api/admin/telegram/setup-topics'), env);
    assert.equal(response.status, 400, JSON.stringify(reports));
  }
  assert.equal((await worker.fetch(request({ errors: 99 }, null, '/api/admin/telegram/setup-topics'), env)).status, 409);
});

test('concurrent setup requests create one complaint topic through the durable queue', async () => {
  const { env } = setup(), original = globalThis.fetch;
  let creates = 0;
  globalThis.fetch = async () => Response.json({ ok: true, result: { message_thread_id: 41 + ++creates } });
  try {
    const responses = await Promise.all([1, 2].map(() => worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)));
    assert.equal(creates, 1);
    for (const response of responses) assert.equal((await response.json()).topics.reports, 42);
  } finally { globalThis.fetch = original; }
});

test('partial topic creation saves IDs so the next attempt resumes without duplicates', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM_TOPIC_ERRORS; delete env.TELEGRAM_TOPIC_PURCHASES; delete env.TELEGRAM_TOPIC_REGISTRATIONS;
  let calls = 0;
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  let writes = 0;
  env.INSTALLS.put = async (key, value) => { if (key === 'telegram_topics') writes++; return put(key, value); };
  globalThis.fetch = async () => {
    calls++;
    return calls === 2 ? Response.json({ ok: false }, { status: 502 }) : Response.json({ ok: true, result: { message_thread_id: calls + 10 } });
  };
  try {
    assert.equal((await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)).status, 502);
    assert.equal(writes, 1);
    assert.equal(JSON.parse(await env.INSTALLS.get('telegram_topics')).errors, 11);
    assert.equal((await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)).status, 200);
    assert.equal(writes, 2);
    assert.equal(calls, 5);
    assert.equal(JSON.parse(await env.INSTALLS.get('telegram_topics')).errors, 11);
  } finally { globalThis.fetch = original; }
});

test('direct Telegram fallback also resolves the saved complaint topic', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM;
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ reports: 42 }));
  globalThis.fetch = async (_, options) => {
    assert.equal(JSON.parse(options.body).message_thread_id, 42);
    return Response.json({ ok: true });
  };
  try { assert.equal((await sendTelegram(env, 'Test', null, { topic: 'reports' })).status, 200); }
  finally { globalThis.fetch = original; }
});

test('an immediate partial-setup retry preserves newly created IDs despite the KV per-key limit', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM_TOPIC_ERRORS; delete env.TELEGRAM_TOPIC_PURCHASES; delete env.TELEGRAM_TOPIC_REGISTRATIONS;
  const put = env.INSTALLS.put.bind(env.INSTALLS);
  let lastWrite = 0, limited = 0, creates = 0;
  env.INSTALLS.put = async (key, value) => {
    if (key === 'telegram_topics') {
      if (Date.now() - lastWrite < 1000) { limited++; throw new Error('KV PUT failed: 429 Too Many Requests'); }
      lastWrite = Date.now();
    }
    return put(key, value);
  };
  globalThis.fetch = async () => {
    creates++;
    return creates === 2 ? Response.json({ ok: false }, { status: 502 }) : Response.json({ ok: true, result: { message_thread_id: creates + 10 } });
  };
  try {
    assert.equal((await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env)).status, 502);
    const response = await worker.fetch(request({}, null, '/api/admin/telegram/setup-topics'), env);
    assert.equal(response.status, 200);
    assert.equal(limited, 1);
    assert.equal(creates, 5, 'no duplicate topics after the KV retry');
    assert.deepEqual(JSON.parse(await env.INSTALLS.get('telegram_topics')), { errors: 11, purchases: 13, registrations: 14, reports: 15 });
  } finally { globalThis.fetch = original; }
});


test('report catalogue stays in sync with canonical ticket content', () => {
  execFileSync('python3', ['../../tools/ru_content/export_report_questions.py', '--check'], { cwd: new URL('.', import.meta.url) });
});

test('the two-second answer and official explanation agree in tickets and topics in all languages', () => {
  for (const language of ['', '_en', '_kk']) {
    const load = name => JSON.parse(readFileSync(new URL(`../../assets/countries/ru/questions/${name}_ab${language}.json`, import.meta.url)));
    const question = load('questions').tickets[25].questions[19];
    const topicQuestion = load('topics').topics.flatMap(t => t.questions).find(q => q.id === question.id);
    assert.equal(question.answers.findIndex(a => a.correct), 1);
    assert.deepEqual(question, topicQuestion);
    for (const value of language === '_en' ? ['0.4', '1.6', '0.1', '2 seconds'] : ['0,4', '1,6', '0,1', '2 секунд']) {
      assert.ok(question.comment.includes(value), `${language}: ${value}`);
    }
    assert.doesNotMatch(question.comment, /вклиниван|напрягать/);
  }
});

test('old clients get the trusted correct answer without an illustration for a text-only question', async () => {
  const { env, state } = setup();
  const response = await worker.fetch(request({ kind: 'report', message: 'Ты уверен', country: 'ru',
    question_id: '4ccb8ce62e426d6ee62eb435bf9cdf91', ticket: 26,
    correct_answer: '3 секунды', photoUrl: 'https://attacker.test/fake.png' }), env);
  assert.equal(response.status, 200);
  const items = await queued(state);
  assert.equal(items.length, 1);
  assert.match(items[0].text, /Верный ответ:<\/b> 2\. 2 секунды/);
  assert.doesNotMatch(items[0].text, /3 секунды|attacker/);
  assert.equal(items[0].photoUrl, undefined);
});

test('picture reports enqueue full text and the canonical image in the same complaint topic', async () => {
  const { env, state } = setup();
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ reports: 42 }));
  const response = await worker.fetch(request({ kind: 'report', message: 'Картинка неверная',
    question_id: '050bbd8d2ba901e0b895141adadf7a60', ticket: 1, category: 'ab' }), env);
  assert.equal(response.status, 200);
  const [text, photo] = await queued(state);
  assert.match(text.text, /Верный ответ:<\/b> 1\. Разрешен/);
  assert.equal(text.threadId, 42);
  assert.equal(photo.threadId, 42);
  assert.equal(photo.photoUrl, 'https://pdd-drive.ru/app/assets/assets/countries/ru/images/questions_ab/eca08a0e2b5ffcd12bdd8ffee34afcc3.webp');
});

test('game IDs and variant IDs resolve their precise diagram and ambiguous legacy IDs never guess', () => {
  for (const category of ['ab', 'cd']) {
    const data = JSON.parse(readFileSync(new URL(`../../assets/countries/ru/questions/questions_${category}.json`, import.meta.url)));
    for (const ticket of data.tickets) {
      for (const [index, question] of ticket.questions.entries()) {
        const scene = `ticket_${category === 'cd' ? 'cd_' : ''}${ticket.number}_${index + 1}`;
        const details = reportQuestionDetails({ question_id: scene });
        assert.equal(details.correctAnswer, question.answers.map((a, i) => a.correct ? `${i + 1}. ${a.text}` : null).filter(Boolean).join('\n'));
        assert.equal(Boolean(details.photoUrl), Boolean(question.image));
        if (question.image) assert.ok(details.photoUrl.endsWith(`/${question.image}.webp`));
        if (question.variantId) {
          const variant = reportQuestionDetails({ question_id: question.variantId, ticket: ticket.number, category });
          assert.ok(variant.photoUrl.endsWith(`/${question.image}.webp`));
        }
      }
    }
  }
  assert.equal(reportQuestionDetails({ question_id: '050bbd8d2ba901e0b895141adadf7a60', ticket: 1 }).photoUrl, null);
  assert.equal(reportQuestionDetails({ question_id: '050bbd8d2ba901e0b895141adadf7a60', ticket: 1 }).correctAnswer, '1. Разрешен');
  assert.equal(reportQuestionDetails({ question_id: 'ticket_1_2', ticket: 26 }), null);
  assert.equal(reportQuestionDetails({ question_id: '__proto__' }), null);
  assert.equal(reportQuestionDetails({ question_id: 'ticket_1_2', country: 'rs' }), null);
});

test('queue delivers picture after the report, retries rate limits and falls back to a link on rejected media', async t => {
  const { env, state } = setup(), original = globalThis.fetch;
  let now = Date.now(); t.mock.method(Date, 'now', () => now);
  const queue = new TelegramQueue(state, env);
  const photoUrl = reportQuestionDetails({ question_id: 'ticket_1_2' }).photoUrl;
  await queue.enqueue({ topic: 'reports', threadId: 42, messages: [{ text: 'Full report' }, { text: 'Picture', photoUrl }] });
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, body: JSON.parse(options.body) });
    if (calls.length === 2) return Response.json({ ok: false, parameters: { retry_after: 20 } }, { status: 429 });
    if (calls.length === 3) return Response.json({ ok: false, description: 'wrong file' }, { status: 400 });
    return Response.json({ ok: true });
  };
  try {
    await queue.alarm();
    await queue.alarm();
    assert.ok((await queued(state))[0].photoUrl);
    assert.ok(await state.storage.getAlarm() > Date.now() + 19000);
    now = await state.storage.getAlarm();
    await queue.alarm();
    assert.equal((await queued(state))[0].photoUrl, undefined);
    await queue.alarm();
    assert.equal((await queued(state)).length, 0);
    assert.match(calls[0].url, /sendMessage$/);
    assert.match(calls[1].url, /sendPhoto$/);
    assert.equal(calls[1].body.photo, photoUrl);
    assert.equal(calls[1].body.message_thread_id, 42);
    assert.match(calls[3].url, /sendMessage$/);
    assert.ok(calls[3].body.text.includes(photoUrl));
  } finally { globalThis.fetch = original; }
});

test('queue rejects arbitrary image URLs and oversized photo captions', async () => {
  const { env, state } = setup(), queue = new TelegramQueue(state, env);
  for (const photoUrl of ['https://attacker.test/x.webp', 'http://pdd-drive.ru/app/assets/assets/countries/ru/images/questions_ab/x.webp', 'https://pdd-drive.ru/app/assets/assets/countries/ru/images/questions_ab/../secret.webp']) {
    assert.equal((await queue.enqueue({ messages: [{ text: 'Photo', photoUrl }] })).status, 400);
  }
  const photoUrl = reportQuestionDetails({ question_id: 'ticket_1_2' }).photoUrl;
  assert.equal((await queue.enqueue({ messages: [{ text: 'x'.repeat(1025), photoUrl }] })).status, 400);
  assert.equal((await queued(state)).length, 0);
});

test('direct report fallback sends text and picture to the same topic', async () => {
  const { env } = setup(), original = globalThis.fetch;
  delete env.TELEGRAM;
  await env.INSTALLS.put('telegram_topics', JSON.stringify({ reports: 42 }));
  const calls = [];
  globalThis.fetch = async (url, options) => { calls.push({ url, body: JSON.parse(options.body) }); return Response.json({ ok: true }); };
  try {
    const response = await worker.fetch(request({ kind: 'report', message: 'Ошибка', question_id: 'ticket_1_2' }), env);
    assert.equal(response.status, 200);
    assert.equal(calls.length, 2);
    assert.match(calls[0].url, /sendMessage$/);
    assert.match(calls[1].url, /sendPhoto$/);
    assert.equal(calls[0].body.message_thread_id, 42);
    assert.equal(calls[1].body.message_thread_id, 42);
  } finally { globalThis.fetch = original; }
});


test('report origin distinguishes legacy game, training and missing context without guessing from IDs',()=>{
 assert.match(reportSourceLabel({mode:'city',question_id:'ticket_3_6'}),/Игра «Живой город»/);
 assert.match(reportSourceLabel({source:'training',mode:'Работа над ошибками'}),/Обычное обучение/);
 assert.match(reportSourceLabel({mode:'Билет 3'}),/Обычное обучение/);
 assert.match(reportSourceLabel({source:'game'}),/Источник:<\/b> Игра$/);
 for(const body of [{question_id:'ticket_3_6'},{source:'<script>'},{}])
  assert.match(reportSourceLabel(body),/Не указан/);
});


test('report messages put origin near the heading and keep training mode separate',()=>{
 const game=buildReportMessage({mode:'city',question_id:'ticket_3_6',message:'Ошибка'});
 assert.match(game,/Жалоба на вопрос<\/b>\n🎮 <b>Источник:<\/b> Игра «Живой город»/);
 assert.doesNotMatch(game,/ • city|^- city/m);
 const training=buildReportMessage({source:'training',mode:'Работа над ошибками',message:'Ошибка'});
 assert.match(training,/📚 <b>Источник:<\/b> Обычное обучение/);
 assert.match(training,/- Работа над ошибками/);
});
