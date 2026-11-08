// Bound every part of the paid provider request, including chat history.
// The app may keep a longer conversation locally; only recent turns are sent
// upstream. These limits preserve all current RU/EN/KK question content.
export const AI_REQUEST_LIMITS = Object.freeze({
  bodyBytes: 65536, questionChars: 1000, answerChars: 1000,
  explanationChars: 8000, messageChars: 2000, userMessageChars: 4000,
  messages: 20, answers: 6,
});
// Flutter gives explanations 10 seconds and follow-ups 12 seconds. Stop the
// provider first so the worker can return its existing local fallback.
export const AI_PROVIDER_TIMEOUT_MS = 9000;

export class AiRequestError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

function text(value, max) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') throw new AiRequestError('invalid text');
  return value.slice(0, max);
}

export async function readAiRequest(request) {
  const limit = AI_REQUEST_LIMITS;
  const declared = Number(request.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > limit.bodyBytes) throw new AiRequestError('request too large', 413);
  const reader = request.body?.getReader();
  if (!reader) throw new AiRequestError('invalid json');
  const chunks = []; let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit.bodyBytes) {
      await reader.cancel();
      throw new AiRequestError('request too large', 413);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  let body;
  try { body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
  catch { throw new AiRequestError('invalid json'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new AiRequestError('invalid json');
  if (body.answers != null && !Array.isArray(body.answers)) throw new AiRequestError('invalid answers');
  if (body.messages != null && !Array.isArray(body.messages)) throw new AiRequestError('invalid messages');
  const answers = (body.answers || []).slice(0, limit.answers).map(answer => text(answer, limit.answerChars));
  const messages = (body.messages || []).slice(-limit.messages).map(message => {
    if (!message || typeof message !== 'object' || Array.isArray(message) || typeof message.isUser !== 'boolean') throw new AiRequestError('invalid messages');
    return { isUser: message.isUser, text: text(message.text, limit.messageChars) };
  });
  return {
    installationId: text(body.installationId || body.installId, 80), locale: text(body.locale, 16),
    questionText: text(body.questionText, limit.questionChars), answers,
    correctAnswerIndex: Number.isInteger(body.correctAnswerIndex) && body.correctAnswerIndex >= 0 && body.correctAnswerIndex < answers.length ? body.correctAnswerIndex : undefined,
    officialExplanation: text(body.officialExplanation, limit.explanationChars),
    messages, userMessage: text(body.userMessage, limit.userMessageChars),
  };
}
