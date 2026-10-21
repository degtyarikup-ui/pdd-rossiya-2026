import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import worker, { flushBufferedStats } from './worker.js';
import { AI_DEFAULT_MODEL, AI_MODELS, isSupportedAiModel, getActiveAiModel,
  aiModelPricing, aiGenerationConfig, aiReply, aiUsage } from './ai_models.js';
import { AI_PROVIDER_TIMEOUT_MS } from './ai_request.js';

class MemoryKV {
  data = new Map();
  async get(key) { return this.data.get(key) ?? null; }
  async put(key, value) { this.data.set(key, String(value)); }
  async list() { return { keys: [], list_complete: true }; }
}
function environment() {
  return { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: randomUUID(), GEMINI_API_KEY: randomUUID(),
    SHARED_SECRET: randomUUID(), __AI_TEST_QUOTA: true, __DURABLE_EFFECTS: [] };
}
function admin(env, suffix, body, authenticated = true) {
  return worker.fetch(new Request('https://test.invalid/api/admin/ai/' + suffix, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'content-type': 'application/json', ...(authenticated ? { authorization: 'Bearer ' + env.ADMIN_PASSWORD } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), env);
}
const success = () => ({ candidates: [{ content: { parts: [
  { thought: true, text: 'Private thought summary' }, { text: 'First paragraph.\n' }, { text: 'Second paragraph.' },
] } }], usageMetadata: { promptTokenCount: 800, candidatesTokenCount: 80, thoughtsTokenCount: 120 } });

test('retired settings migrate to the latest default while the legacy setting still supports current models', async () => {
  const env = environment();
  assert.equal(AI_DEFAULT_MODEL, 'gemini-3.8-flash');
  assert.equal(await getActiveAiModel({}), AI_DEFAULT_MODEL);
  for (const model of ['gemini-1.5-flash', 'gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-3.6-flash', 'unknown', '__proto__', 'constructor']) {
    await env.INSTALLS.put('ai_config_model', model);
    assert.equal(await getActiveAiModel(env), AI_DEFAULT_MODEL, model);
    assert.equal(isSupportedAiModel(model), false, model);
  }
  env.INSTALLS.data.delete('ai_config_model');
  await env.INSTALLS.put('AI_MODEL', 'gemini-3.5-flash-lite');
  assert.equal(await getActiveAiModel(env), 'gemini-3.5-flash-lite');
  await env.INSTALLS.put('ai_config_model', AI_DEFAULT_MODEL);
  assert.equal(await getActiveAiModel(env), AI_DEFAULT_MODEL);
  assert.deepEqual(Object.keys(AI_MODELS).sort(), ['gemini-3.5-flash-lite', 'gemini-3.8-flash']);
});

test('admin list and persistence accept only the two current models and require authentication', async () => {
  const env = environment();
  await env.INSTALLS.put('ai_config_model', 'gemini-2.5-pro');
  const statsResponse = await admin(env, 'stats');
  assert.equal(statsResponse.status, 200);
  const { stats } = await statsResponse.json();
  assert.equal(stats.activeModel, AI_DEFAULT_MODEL);
  assert.deepEqual(stats.availableModels.map(model => model.id).sort(), Object.keys(AI_MODELS).sort());
  for (const suffix of ['config', 'test']) assert.equal((await admin(env, suffix, { model: AI_DEFAULT_MODEL }, false)).status, 401);
  assert.equal((await admin(env, 'stats', undefined, false)).status, 401);
  for (const model of ['gemini-1.5-flash', 'gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-3.6-flash', '__proto__', 'constructor', 'toString', '']) {
    assert.equal((await admin(env, 'config', { model })).status, 400, model);
    assert.equal(await env.INSTALLS.get('ai_config_model'), 'gemini-2.5-pro');
  }
  for (const model of Object.keys(AI_MODELS)) {
    const response = await admin(env, 'config', { model });
    assert.equal(response.status, 200);
    assert.equal(await env.INSTALLS.get('ai_config_model'), model);
  }
});

test('Flash pricing changes at UTC New Year and buffered requests keep their request-time prices', async () => {
  const before = Date.parse('2026-12-31T23:59:59.999Z');
  const after = before + 1;
  const first = aiModelPricing('gemini-3.8-flash', before);
  const second = aiModelPricing('gemini-3.8-flash', after);
  assert.equal(first.inputPerM, 0.75);
  assert.equal(first.outputPerM, 3.75);
  assert.equal(second.inputPerM, 1.5);
  assert.equal(second.outputPerM, 7.5);
  const lite = aiModelPricing('gemini-3.5-flash-lite', after);
  assert.equal(lite.inputPerM, 0.3);
  assert.equal(lite.outputPerM, 2.5);
  const env = environment();
  await env.INSTALLS.put('ai_stats_cost_usd', '0');
  await flushBufferedStats(env, [
    { kind: 'ai', model: 'gemini-3.8-flash', ts: before, promptTokens: 1_000_000, candidateTokens: 1_000_000 },
    { kind: 'ai', model: 'gemini-3.8-flash', ts: after, promptTokens: 1_000_000, candidateTokens: 1_000_000 },
    { kind: 'ai', model: 'gemini-3.5-flash-lite', ts: after, promptTokens: 1_000_000, candidateTokens: 1_000_000 },
  ]);
  assert.equal(Number(await env.INSTALLS.get('ai_stats_cost_usd')), 16.3);
  assert.equal(Number(await env.INSTALLS.get('ai_stats_total_req')), 3);
  await flushBufferedStats(env, [{ kind: 'ai', model: 'gemini-3.6-flash', ts: before, promptTokens: 1_000_000, candidateTokens: 1_000_000 }]);
  assert.equal(Number(await env.INSTALLS.get('ai_stats_cost_usd')), 16.8, 'already queued legacy events retain their historical rates');
});

test('new models use low thinking without deprecated temperature and bill thoughts as output', () => {
  for (const model of Object.keys(AI_MODELS)) {
    const config = aiGenerationConfig(model, 2048);
    assert.equal(config.maxOutputTokens, 2048);
    assert.equal(config.thinkingConfig.thinkingLevel, 'low');
    assert.equal('temperature' in config, false);
  }
  assert.equal(aiReply(success()), 'First paragraph.\nSecond paragraph.');
  assert.equal(aiReply({ candidates: [{ content: { parts: [{ text: 'Thinking only', thought: true }] } }] }), '');
  assert.equal(aiReply({ candidates: [] }), '');
  const usage = aiUsage(success());
  assert.equal(usage.promptTokens, 800);
  assert.equal(usage.candidateTokens, 200);
  const zero = aiUsage({ usageMetadata: { promptTokenCount: 0, candidatesTokenCount: 0, thoughtsTokenCount: 0 } });
  assert.equal(zero.promptTokens, 0);
  assert.equal(zero.candidateTokens, 0);
});

test('admin can test a selected model without changing the globally saved model', async () => {
  const env = environment();
  await env.INSTALLS.put('ai_config_model', AI_DEFAULT_MODEL);
  const original = globalThis.fetch; const calls = [];
  globalThis.fetch = async (url, options) => { calls.push({ url: String(url), options }); return Response.json(success()); };
  try {
    const response = await admin(env, 'test', { model: 'gemini-3.5-flash-lite', prompt: 'Explain a traffic sign.' });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.ok, true);
    assert.equal(body.model, 'gemini-3.5-flash-lite');
    assert.equal(body.reply, 'First paragraph.\nSecond paragraph.');
    assert.equal(await env.INSTALLS.get('ai_config_model'), AI_DEFAULT_MODEL);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/models\/gemini-3\.5-flash-lite:generateContent/);
    assert.ok(calls[0].options.signal instanceof AbortSignal);
    const config = JSON.parse(calls[0].options.body).generationConfig;
    assert.equal(config.thinkingConfig.thinkingLevel, 'low');
    assert.equal('temperature' in config, false);
    const effect = env.__DURABLE_EFFECTS.find(effect => effect.kind === 'stats').item;
    assert.equal(effect.model, 'gemini-3.5-flash-lite');
    assert.equal(effect.promptTokens, 800);
    assert.equal(effect.candidateTokens, 200);
    for (const model of ['gemini-2.5-flash', '__proto__', 'constructor']) {
      assert.equal((await admin(env, 'test', { model, prompt: 'Fixture' })).status, 400);
    }
    assert.equal(calls.length, 1);
  } finally { globalThis.fetch = original; }
});

test('the admin test rejects upstream errors and empty or thought-only answers', async () => {
  const original = globalThis.fetch;
  try {
    for (const response of [
      () => Response.json({ error: { message: 'Provider error' } }, { status: 429 }),
      () => Response.json({ candidates: [] }),
      () => Response.json({ candidates: [{ content: { parts: [{ thought: true, text: 'Thought' }] } }] }),
    ]) {
      const env = environment();
      globalThis.fetch = async () => response();
      const result = await admin(env, 'test', { model: AI_DEFAULT_MODEL, prompt: 'Fixture' });
      assert.equal(result.status, 503);
      const data = await result.json();
      assert.equal(data.ok, false);
      assert.equal(data.error, 'ai_unavailable');
    }
  } finally { globalThis.fetch = original; }
});

test('app explanations use the migrated default, concatenate public answer parts and record thinking tokens', async () => {
  const env = environment();
  await env.INSTALLS.put('ai_config_model', 'gemini-2.5-pro');
  const originalFetch = globalThis.fetch, originalTimeout = AbortSignal.timeout;
  const calls = [], deadlines = [];
  globalThis.fetch = async (url, options) => { calls.push({ url: String(url), options }); return Response.json(success()); };
  AbortSignal.timeout = ms => { deadlines.push(ms); return originalTimeout(ms); };
  try {
    const result = await worker.fetch(new Request('https://test.invalid/api/ai/chat', {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': env.SHARED_SECRET },
      body: JSON.stringify({ installationId: 'a'.repeat(32), questionText: 'Fixture question?',
        answers: ['Fixture answer'], correctAnswerIndex: 0, officialExplanation: 'Official explanation.' }),
    }), env);
    assert.equal(result.status, 200);
    const data = await result.json();
    assert.equal(data.model, AI_DEFAULT_MODEL);
    assert.equal(data.reply, 'First paragraph.\nSecond paragraph.');
    assert.equal(data.generated, true);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/models\/gemini-3\.8-flash:generateContent/);
    assert.deepEqual(deadlines, [AI_PROVIDER_TIMEOUT_MS]);
    const config = JSON.parse(calls[0].options.body).generationConfig;
    assert.equal(config.thinkingConfig.thinkingLevel, 'low');
    assert.equal('temperature' in config, false);
    assert.equal(env.__DURABLE_EFFECTS.find(effect => effect.kind === 'stats').item.candidateTokens, 200);
  } finally { globalThis.fetch = originalFetch; AbortSignal.timeout = originalTimeout; }
});

test('empty generated answers preserve the official explanation fallback for app users', async () => {
  const env = environment(), original = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ candidates: [{ content: { parts: [{ thought: true, text: 'Thought only' }] } }] });
  try {
    const result = await worker.fetch(new Request('https://test.invalid/api/ai/chat', {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-install-secret': env.SHARED_SECRET },
      body: JSON.stringify({ installationId: 'b'.repeat(32), questionText: 'Fixture?', answers: ['Answer'],
        correctAnswerIndex: 0, officialExplanation: 'Official fallback.' }),
    }), env);
    assert.equal(result.status, 200);
    const data = await result.json();
    assert.equal(data.reply, 'Official fallback.');
    assert.equal(data.generated, false);
    assert.equal(data.aiUnavailable, true);
  } finally { globalThis.fetch = original; }
});

test('assembled admin has only current model options and valid JavaScript', async () => {
  const response = await worker.fetch(new Request('https://test.invalid/admin'), environment());
  assert.equal(response.status, 200);
  const html = await response.text();
  const select = html.match(/<select\b[^>]*\bid="ai-model-select"[^>]*>([\s\S]*?)<\/select>/)?.[1];
  assert.ok(select, 'AI model selector must be present');
  const models = [...select.matchAll(/<option\b[^>]*\bvalue="([^"]+)"/g)].map(match => match[1]);
  assert.deepEqual(models.sort(), Object.keys(AI_MODELS).sort());
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(match => match[1]);
  assert.ok(scripts.length > 0);
  for (const script of scripts) assert.doesNotThrow(() => new Function(script));
  const client = scripts.join('\n');
  assert.match(client, /\/api\/admin\/ai\/test/);
  assert.doesNotMatch(client, /gemini-3\.6-flash/);
});
