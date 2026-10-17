import test from 'node:test';
import { randomUUID } from 'node:crypto';
const fixtureSharedSecret = randomUUID();
const fixtureProviderKey = randomUUID();
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import worker from './worker.js';
import { readAiRequest, AiRequestError, AI_REQUEST_LIMITS as limits, AI_PROVIDER_TIMEOUT_MS } from './ai_request.js';

const request = body => new Request('https://audit.invalid/api/ai/chat', {
  method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': fixtureSharedSecret },
  body: JSON.stringify(body),
});
const env = { SHARED_SECRET: fixtureSharedSecret, GEMINI_API_KEY: fixtureProviderKey, INSTALLS: { get: async () => null } };

test('all 4800 current RU/EN/KK question payloads fit without truncation', async () => {
  const directory = new URL('../../assets/countries/ru/questions/', import.meta.url);
  let count = 0;
  for (const name of (await readdir(directory)).filter(name => /^questions_(ab|cd)(_(en|kk))?\.json$/.test(name))) {
    const data = JSON.parse(await readFile(new URL(name, directory), 'utf8'));
    for (const question of data.tickets.flatMap(ticket => ticket.questions)) {
      const body = { questionText: question.question, answers: question.answers.map(answer => answer.text),
        correctAnswerIndex: question.answers.findIndex(answer => answer.correct), officialExplanation: question.comment };
      const parsed = await readAiRequest(request(body));
      for (const key of ['questionText', 'answers', 'correctAnswerIndex', 'officialExplanation']) assert.deepEqual(parsed[key], body[key], name + ':' + question.id + ':' + key);
      count++;
    }
  }
  assert.equal(count, 4800);
});

test('malformed AI schemas return 400 before making a paid request', async () => {
  const original = globalThis.fetch; let calls = 0;
  globalThis.fetch = async () => { calls++; throw new Error('must not reach provider'); };
  try {
    for (const body of [null, [], { questionText: {} }, { answers: {} }, { answers: [42] },
      { messages: 'history' }, { messages: [null] }, { messages: [{ text: 'test' }] },
      { messages: [{ isUser: true, text: {} }] }, { officialExplanation: 42 }, { userMessage: [] }]) {
      assert.equal((await worker.fetch(request(body), env)).status, 400);
    }
    assert.equal(calls, 0);
  } finally { globalThis.fetch = original; }
});

test('actual UTF-8 body bytes are bounded even without Content-Length', async () => {
  const oversized = request({ officialExplanation: 'я'.repeat(limits.bodyBytes / 2) });
  assert.equal(oversized.headers.has('content-length'), false);
  await assert.rejects(readAiRequest(oversized), error => error instanceof AiRequestError && error.status === 413);
  const response = await worker.fetch(request({ officialExplanation: 'x'.repeat(limits.bodyBytes) }), env);
  assert.equal(response.status, 413);
});

test('chat history keeps recent turns and bounds every upstream text', async () => {
  const body = { questionText: 'q'.repeat(1200), answers: ['a'.repeat(1200)], correctAnswerIndex: 0,
    officialExplanation: 'e'.repeat(9000), userMessage: 'u'.repeat(5000),
    messages: Array.from({ length: 25 }, (_, i) => ({ isUser: i % 2 === 0, text: String(i) })) };
  body.messages[24].text = 'm'.repeat(3000);
  const parsed = await readAiRequest(request(body));
  assert.equal(parsed.questionText.length, limits.questionChars);
  assert.equal(parsed.answers[0].length, limits.answerChars);
  assert.equal(parsed.officialExplanation.length, limits.explanationChars);
  assert.equal(parsed.userMessage.length, limits.userMessageChars);
  assert.equal(parsed.messages.length, limits.messages);
  assert.equal(parsed.messages[0].text, '5');
  assert.equal(parsed.messages.at(-1).text.length, limits.messageChars);
});

test('Gemini request receives a deadline inside the client timeout and bounded content', async () => {
  const originalFetch = globalThis.fetch, originalTimeout = AbortSignal.timeout;
  const deadlines = [], calls = [];
  AbortSignal.timeout = milliseconds => { deadlines.push(milliseconds); return originalTimeout(milliseconds); };
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    return Response.json({ candidates: [{ content: { parts: [{ text: 'fixture answer' }] } }] });
  };
  try {
    const response = await worker.fetch(request({ questionText: 'fixture', answers: ['answer'], correctAnswerIndex: 0,
      officialExplanation: 'e'.repeat(9000), messages: [{ isUser: true, text: 'm'.repeat(3000) }], userMessage: 'u'.repeat(5000) }), env);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).reply, 'fixture answer');
    assert.equal(calls.length, 1);
    assert.ok(calls[0].options.signal instanceof AbortSignal);
    assert.deepEqual(deadlines, [AI_PROVIDER_TIMEOUT_MS]);
    assert.ok(AI_PROVIDER_TIMEOUT_MS < 10000);
    const sent = JSON.parse(calls[0].options.body);
    assert.ok(sent.systemInstruction.parts[0].text.length < 10000);
    assert.equal(sent.contents[0].parts[0].text.length, limits.messageChars + 1 + limits.userMessageChars);
  } finally { globalThis.fetch = originalFetch; AbortSignal.timeout = originalTimeout; }
});

test('provider timeout preserves the existing deterministic explanation fallback', async () => {
  const original = globalThis.fetch, originalLog = console.error;
  globalThis.fetch = async (_url, options) => { assert.ok(options.signal instanceof AbortSignal); throw new DOMException('fixture timeout', 'TimeoutError'); };
  console.error = () => {};
  try {
    const response = await worker.fetch(request({ questionText: 'Fixture?', answers: ['First'], correctAnswerIndex: 0, officialExplanation: 'Official fixture comment.' }), env);
    assert.equal(response.status, 200);
    assert.match((await response.json()).reply, /Official fixture comment\./);
  } finally { globalThis.fetch = original; console.error = originalLog; }
});
