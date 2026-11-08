// Stable text models for short PDD explanations, checked 2026-10-21.
// https://ai.google.dev/gemini-api/docs/models
// https://ai.google.dev/gemini-api/docs/pricing (Standard, text, USD / 1M)
export const AI_DEFAULT_MODEL = 'gemini-3.8-flash';
export const AI_MODELS = Object.freeze({
  'gemini-3.8-flash': Object.freeze({ name: 'Gemini 3.8 Flash', description: 'Основная модель для разбора вопросов' }),
  'gemini-3.5-flash-lite': Object.freeze({ name: 'Gemini 3.5 Flash-Lite', description: 'Экономичный вариант для коротких объяснений' }),
});

export const isSupportedAiModel = model => typeof model === 'string' && Object.hasOwn(AI_MODELS, model);

export async function getActiveAiModel(env) {
  if (env.INSTALLS) {
    try {
      const model = (await env.INSTALLS.get('ai_config_model')) || (await env.INSTALLS.get('AI_MODEL'));
      if (isSupportedAiModel(model)) return model;
    } catch (_) {}
  }
  // Retired selections migrate without writing KV on every request.
  return AI_DEFAULT_MODEL;
}

// Preserve the old rates for events already queued by a previous Worker.
// Historical accumulated totals are never recalculated on model changes.
const LEGACY_PRICING = Object.freeze({
  'gemini-3.6-flash': { inputPerM: 0.10, outputPerM: 0.40 },
  'gemini-2.5-flash': { inputPerM: 0.10, outputPerM: 0.40 },
  'gemini-1.5-flash': { inputPerM: 0.075, outputPerM: 0.30 },
  'gemini-2.5-pro': { inputPerM: 1.25, outputPerM: 5.00 },
  'gemini-1.5-pro': { inputPerM: 1.25, outputPerM: 5.00 },
});

export function aiModelPricing(model, at = Date.now()) {
  if (model === 'gemini-3.5-flash-lite') return { inputPerM: 0.30, outputPerM: 2.50 };
  if (Object.hasOwn(LEGACY_PRICING, model)) return LEGACY_PRICING[model];
  // Google introductory rates end at midnight UTC, independently of flush time.
  return new Date(at).getTime() < Date.parse('2027-01-01T00:00:00Z')
    ? { inputPerM: 0.75, outputPerM: 3.75 }
    : { inputPerM: 1.50, outputPerM: 7.50 };
}

export function aiGenerationConfig(_model, maxOutputTokens = 2048) {
  // Gemini 3.8 rejects deprecated sampling parameters. Low reasoning keeps
  // responses within the app's 10-second deadline; output also budgets thoughts.
  return { maxOutputTokens, thinkingConfig: { thinkingLevel: 'low' } };
}

export function aiReply(data) {
  return (data?.candidates?.[0]?.content?.parts || [])
    .filter(part => !part.thought && typeof part.text === 'string')
    .map(part => part.text).join('').trim();
}

export function aiUsage(data) {
  const usage = data?.usageMetadata || {};
  const count = value => Math.max(0, Number(value) || 0);
  return {
    promptTokens: count(usage.promptTokenCount),
    candidateTokens: count(usage.candidatesTokenCount) + count(usage.thoughtsTokenCount),
  };
}
