import { digest as supportDigest } from './request_security.js';
const supportSecret = 'a'.repeat(64);
const supportGuest = 'guest_v2_' + await supportDigest(supportSecret);
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { handleSupportGetMessages, handleSupportSendMessage, resetSupportPollThrottle } from './support_chat.js';

const messages = [{ id: 'fixture-reply', sender: 'support', text: 'Saved reply', ts: 2000 }];
const request = () => new Request('https://fixture.invalid/api/support/messages?clientId=' + supportGuest + '&since=1000', { headers: { 'x-support-secret': supportSecret } });

function fixture(reply) {
  const legacy = JSON.stringify(messages), calls = [], kvReads = [];
  const env = {
    INSTALLS: {
      get: async (key, options) => {
        kvReads.push(key);
        return key === 'support:messages:' + supportGuest ? (options?.type === 'json' ? JSON.parse(legacy) : legacy) : null;
      },
      put: async () => { throw new Error('Unexpected KV write'); },
    },
    SUPPORT: {
      idFromName: id => id,
      get: () => ({ fetch: async (input, options) => {
        const path = new URL(typeof input === 'string' ? input : input.url).pathname;
        calls.push(path);
        assert.notEqual(path, '/append');
        return reply(path, options);
      } }),
    },
  };
  return { env, calls, kvReads, legacy };
}
function forbidExternalRequests(t) {
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('External calls forbidden'); });
}

test('optional Telegram metadata failure still returns fresh stored replies with a bounded warning', async t => {
  forbidExternalRequests(t);
  resetSupportPollThrottle();
  const { env, calls } = fixture(() => Response.json({ ok: true, initialized: true, messages }));
  Object.assign(env, { BOT_TOKEN: 'fixture', CHAT_ID: 'fixture', TELEGRAM: {
    idFromName: () => { throw new Error('Telegram polling must be skipped'); },
  } });
  env.INSTALLS.get = async () => { throw Object.assign(new Error('PRIVATE user@example.invalid https://private.invalid'), { retryable: true, overloaded: false }); };
  const warnings = [];
  t.mock.method(console, 'warn', line => warnings.push(JSON.parse(line)));
  const response = await handleSupportGetMessages(request(), env);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).messages, messages);
  assert.deepEqual(calls, ['/list']);
  assert.deepEqual(warnings, [{ event: 'support_optional_poll_unavailable', stage: 'webhook_flag', code: 'durable_retryable', retryable: true, overloaded: false }]);
  assert.doesNotMatch(JSON.stringify(warnings), /PRIVATE|user@|https:|fixture/);
});

test('an unavailable internal list returns HTTP 503 through the Worker without stale KV fallback', async t => {
  forbidExternalRequests(t);
  const { env, calls, kvReads } = fixture(() => new Response('private upstream details', { status: 503 }));
  const response = await worker.fetch(request(), env);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'server unavailable' });
  assert.deepEqual(calls, ['/list']);
  assert.equal(kvReads.includes('support:messages:' + supportGuest), false);
});

test('overload remains the same exception and is not immediately retried', async t => {
  forbidExternalRequests(t);
  const original = Object.assign(new Error('private platform details'), { overloaded: true, retryable: true });
  const { env, calls } = fixture(() => { throw original; });
  await assert.rejects(handleSupportGetMessages(request(), env), error => {
    assert.equal(error, original);
    assert.equal(error.overloaded, true);
    assert.equal(error.retryable, true);
    assert.equal(error.supportStage, 'list');
    return true;
  });
  assert.deepEqual(calls, ['/list']);
  const response = await worker.fetch(request(), env);
  assert.equal(response.status, 503);
  assert.equal(response.headers.get('retry-after'), '5');
  assert.equal(calls.length, 2, 'one attempt per separate request');
});

test('malformed list JSON or schema is an explicit failure, never an empty conversation', async t => {
  forbidExternalRequests(t);
  for (const payload of ['not JSON', 'null', '[]', '{}', '{"messages":null}', '{"messages":{}}', '{"messages":[],"initialized":"false"}', '{"messages":[],"ok":false}']) {
    const { env, calls, kvReads } = fixture(() => new Response(payload));
    await assert.rejects(handleSupportGetMessages(request(), env), error => {
      assert.equal(error.code, 'ERR_SUPPORT_READ_UNAVAILABLE');
      assert.equal(error.supportStage, 'list');
      assert.equal(error.upstreamStatus, undefined);
      return true;
    });
    assert.deepEqual(calls, ['/list']);
    assert.equal(kvReads.includes('support:messages:' + supportGuest), false);
  }
});

test('legacy successful lists without initialized and genuinely empty lists remain compatible', async t => {
  forbidExternalRequests(t);
  for (const payload of [{ messages }, { ok: true, messages }, { messages: [{}] }, { ok: true, initialized: true, messages: [] }]) {
    const { env, calls } = fixture(() => Response.json(payload));
    const response = await handleSupportGetMessages(request(), env);
    assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).messages, payload.messages);
    assert.deepEqual(calls, ['/list']);
  }
});

test('malformed message elements return HTTP 503 rather than a successful empty history', async t => {
  forbidExternalRequests(t);
  for (const item of [null, 'invalid message', []]) {
    const { env, calls, kvReads } = fixture(() => Response.json({ ok: true, initialized: true, messages: [item] }));
    const response = await worker.fetch(request(), env);
    assert.equal(response.status, 503);
    const body = await response.json();
    assert.equal(body.error, 'server unavailable');
    assert.equal(Object.hasOwn(body, 'messages'), false);
    assert.deepEqual(calls, ['/list']);
    assert.equal(kvReads.includes('support:messages:' + supportGuest), false);
  }
});

test('a failed seed preserves legacy history and an ambiguous committed seed is readable next time', async t => {
  forbidExternalRequests(t);
  for (const failure of ['status', 'json', 'schema']) {
    let stored = null;
    const { env, calls, legacy } = fixture((path, options) => {
      if (path === '/list') return Response.json({ ok: true, initialized: stored !== null, messages: stored || [] });
      assert.equal(path, '/seed');
      assert.deepEqual(JSON.parse(options.body), messages);
      if (failure === 'status') return new Response(null, { status: 503 });
      stored = JSON.parse(options.body); // The write can commit before its response is lost.
      return failure === 'json' ? new Response('incomplete response') : Response.json({});
    });
    await assert.rejects(handleSupportGetMessages(request(), env), error => {
      assert.equal(error.code, 'ERR_SUPPORT_READ_UNAVAILABLE');
      assert.equal(error.supportStage, 'seed');
      assert.equal(error.upstreamStatus, failure === 'status' ? 503 : undefined);
      return true;
    });
    assert.equal(await env.INSTALLS.get('support:messages:' + supportGuest), legacy);
    assert.deepEqual(calls, ['/list', '/seed']);
    if (failure !== 'status') {
      const response = await handleSupportGetMessages(request(), env);
      assert.deepEqual((await response.json()).messages, messages);
      assert.deepEqual(calls, ['/list', '/seed', '/list']);
    } else assert.equal(stored, null);
  }
});

test('corrupt legacy history is rejected before seeding or erasing either storage', async t => {
  forbidExternalRequests(t);
  for (const legacy of [{}, 'invalid history', 1, false, [null], ['invalid message'], [[]]]) {
    const original = structuredClone(legacy);
    const { env, calls } = fixture(() => Response.json({ ok: true, initialized: false, messages: [] }));
    env.INSTALLS.get = async () => legacy;
    const response = await worker.fetch(request(), env);
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, 'server unavailable');
    assert.deepEqual(calls, ['/list']);
    assert.deepEqual(legacy, original);
  }
});

test('legacy JSON errors retain identity and flags and identify the seed stage', async t => {
  forbidExternalRequests(t);
  const original = Object.assign(new SyntaxError('PRIVATE history body'), { retryable: true });
  const { env, calls } = fixture(() => Response.json({ ok: true, initialized: false, messages: [] }));
  env.INSTALLS.get = async () => { throw original; };
  await assert.rejects(handleSupportGetMessages(request(), env), error => {
    assert.equal(error, original);
    assert.equal(error.name, 'SyntaxError');
    assert.equal(error.retryable, true);
    assert.equal(error.supportStage, 'seed');
    assert.equal(error.code, 'ERR_SUPPORT_READ_UNAVAILABLE');
    return true;
  });
  assert.deepEqual(calls, ['/list']);
});

test('a genuinely absent legacy history seeds an empty thread only once', async t => {
  forbidExternalRequests(t);
  for (const absent of [null, undefined]) {
    let initialized = false;
    const { env, calls } = fixture((path, options) => {
      if (path === '/list') return Response.json({ ok: true, initialized, messages: [] });
      assert.equal(path, '/seed');
      assert.deepEqual(JSON.parse(options.body), []);
      initialized = true;
      return Response.json({ ok: true });
    });
    env.INSTALLS.get = async () => absent;
    for (let i = 0; i < 2; i++) {
      const response = await handleSupportGetMessages(request(), env);
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).messages, []);
    }
    assert.deepEqual(calls, ['/list', '/seed', '/list', '/list']);
  }
});


function sendFixture(reply = () => Response.json({ ok: true })) {
  const calls = [], puts = [];
  const env = {
    BOT_TOKEN: 'fixture-token', CHAT_ID: '-100',
    INSTALLS: {
      get: async key => key.startsWith('support:client:') ? { threadId: 7 } : null,
      put: async (...args) => puts.push(args),
    },
    SUPPORT: { idFromName: id => id, get: () => ({ fetch: async (url, options) => {
      calls.push(new URL(url).pathname);
      return reply(JSON.parse(options.body));
    } }) },
  };
  return { env, calls, puts };
}
const sendRequest = extra => new Request('https://fixture.invalid/api/support/send', {
  method: 'POST', headers: { 'x-support-secret': supportSecret },
  body: JSON.stringify({ clientId: supportGuest, text: 'Help please', ...extra }),
});

test('send acknowledges the internal append only after HTTP and JSON success', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ ok: true, result: {} }));
  for (const response of [new Response(null, { status: 503 }), new Response('broken'), Response.json({}), Response.json({ ok: false })]) {
    const { env, calls } = sendFixture(() => response);
    const result = await worker.fetch(sendRequest(), env);
    assert.equal(result.status, 503);
    assert.equal((await result.json()).error, 'support storage unavailable');
    assert.deepEqual(calls, ['/append'], 'ambiguous append is never replayed');
  }
});

test('Telegram rejects or loses a message: do not record it as delivered', async t => {
  const replies = [
    () => new Response(null, { status: 504 }),
    () => Response.json({ ok: false, description: 'PRIVATE' }),
    () => new Response('malformed'),
    () => { throw new Error('PRIVATE'); },
  ];
  for (const reply of replies) {
    t.mock.method(globalThis, 'fetch', async () => reply());
    const { env, calls } = sendFixture();
    const result = await worker.fetch(sendRequest(), env);
    assert.equal(result.status, 503);
    assert.deepEqual(await result.json(), { error: 'support delivery unavailable' });
    assert.deepEqual(calls, [], 'failed delivery is not a sent message');
    t.mock.restoreAll();
  }
});

test('failed photo delivery never becomes an empty successful message', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ ok: false }, { status: 503 }));
  const { env, calls } = sendFixture();
  const result = await worker.fetch(sendRequest({ text: '', imageBase64: 'AA==', imageMimeType: 'image/png' }), env);
  assert.equal(result.status, 503);
  assert.deepEqual(calls, []);
});

test('a short first contact needs one Telegram message after topic creation', async t => {
  const telegramCalls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    telegramCalls.push({ method: String(url).split('/').pop(), body: JSON.parse(options.body) });
    return Response.json({ ok: true, result: { message_thread_id: 7 } });
  });
  const { env, calls } = sendFixture();
  env.INSTALLS.get = async () => null;
  const result = await handleSupportSendMessage(sendRequest(), env);
  assert.equal(result.status, 200);
  assert.deepEqual(telegramCalls.map(c => c.method), ['createForumTopic', 'sendMessage']);
  assert.match(telegramCalls[1].body.text, /Новое обращение/);
  assert.match(telegramCalls[1].body.text, /Help please/);
  assert.deepEqual(calls, ['/append']);
});

test('auxiliary metadata failure cannot turn a delivered stored message into a retry', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ ok: true, result: {} }));
  const { env, calls } = sendFixture();
  env.INSTALLS.put = async () => { throw new Error('KV unavailable'); };
  const result = await handleSupportSendMessage(sendRequest(), env);
  assert.equal(result.status, 200);
  assert.equal((await result.json()).message.text, 'Help please');
  assert.deepEqual(calls, ['/append']);
});

test('a long photo caption never truncates escaped HTML', async t => {
  const captions = [], messages = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    if (String(url).endsWith('/sendPhoto')) {
      captions.push(options.body.get('caption'));
      return Response.json({ ok: true, result: { photo: [{ file_id: 'fixture-photo' }] } });
    }
    messages.push(JSON.parse(options.body).text);
    return Response.json({ ok: true, result: {} });
  });
  const { env } = sendFixture();
  const text = '&'.repeat(1100);
  const result = await handleSupportSendMessage(sendRequest({ text, userName: 'Name & Name', imageBase64: 'AA==', imageMimeType: 'image/png' }), env);
  assert.equal(result.status, 200);
  assert.deepEqual(captions, ['<b>Name &amp; Name</b>']);
  assert.equal(messages.length, 1);
  assert.ok(messages[0].endsWith('&amp;'.repeat(1100)));
  const saved = (await result.json()).message;
  assert.equal(saved.text, text);
  assert.match(saved.imageUrl, /fixture-photo/);
});
