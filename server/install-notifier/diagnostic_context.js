// Only bounded technical enums, counts and app source locations cross the
// diagnostic boundary. Never retain raw SDK messages, URLs or stack traces.
const products = new Set(['u.pdd.pddApp.premium.week', 'ru.pdd.pddApp.sub.3months', 'ru.pdd.pddapp.sub.week', 'ru.pdd.pddapp.sub.3months']);
export function sanitizeDiagnosticContext(value) {
  const input = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const result = {};
  for (const [key, allowed] of Object.entries({
    phase: ['background', 'paywall', 'purchase'],
    stage: ['availability', 'query', 'framework', 'unhandled', 'server'],
    sdkSource: ['app_store', 'google_play'],
    errorType: ['Error', 'TypeError', 'RangeError', 'ReferenceError', 'SyntaxError'],
    supportStage: ['list', 'seed'],
  })) if (allowed.includes(input[key])) result[key] = input[key];
  for (const key of ['attempt', 'requestedCount', 'returnedCount', 'missingCount']) {
    if (Number.isInteger(input[key]) && input[key] >= 0 && input[key] <= 100) result[key] = input[key];
  }
  for (const key of ['retryable', 'overloaded']) if (typeof input[key] === 'boolean') result[key] = input[key];
  if (Number.isInteger(input.upstreamStatus) && input.upstreamStatus >= 400 && input.upstreamStatus <= 599) result.upstreamStatus = input.upstreamStatus;
  if (typeof input.sdkCodeHash === 'string' && /^[a-f0-9]{16}$/.test(input.sdkCodeHash)) result.sdkCodeHash = input.sdkCodeHash;
  if (Array.isArray(input.missingIds)) result.missingIds = [...new Set(input.missingIds.filter(v => products.has(v)))].slice(0, 4);
  if (Array.isArray(input.frames)) result.frames = input.frames.filter(v => typeof v === 'string' && v.length <= 160 && /^(?:package:pdd_app\/(?:[a-zA-Z0-9_]+\/)*[a-zA-Z0-9_]+\.dart(?::\d{1,6}(?::\d{1,5})?)?|[a-z_]{1,48}\.js:\d{1,6}:\d{1,5})$/.test(v)).slice(0, 6);
  return result;
}

export function diagnosticOs(value) {
  return typeof value === 'string' && /^(?:Android|iOS) [\d.]{1,16}(?: \(SDK \d{1,3}\))?$/.test(value) ? value : null;
}

const AUTH_TRANSPORT_PROVIDERS = new Set(['google', 'apple', 'yandex', 'telegram']);
// Correlate sign-in transport failures only by the already-anonymized install.
// Credential/configuration, billing and unknown-provider failures stay separate.
export function authTransportIdentity(event) {
  if (event.origin !== 'client' || event.category !== 'auth' || event.userId || event.payment
      || !['auth.provider', 'auth.session'].includes(event.operation)
      || !/^[a-f0-9]{16}$/.test(event.installation || '')
      || !AUTH_TRANSPORT_PROVIDERS.has(event.provider)
      || !/^(?:timeout|network|network_error)(?::[1-9]\d?x)?$/.test(event.code || '')
      || (event.status != null && (!Number.isInteger(event.status) || event.status < 500 || event.status > 599))
      || event.context?.phase || event.context?.sdkSource
      || ['framework', 'unhandled'].includes(event.context?.stage)) return null;
  const platform = typeof event.platform === 'string' ? event.platform.toLowerCase() : '';
  if (!['android', 'ios', 'web', 'macos', 'windows', 'linux'].includes(platform)
      || typeof event.appVersion !== 'string' || !/^\d[\d.+-]{0,31}$/.test(event.appVersion)
      || (event.device != null && (typeof event.device !== 'string' || event.device.length > 100))) return null;
  return JSON.stringify(['auth-transport-v1', event.installation, platform, event.appVersion,
    event.device || '', diagnosticOs(event.os), event.status ?? null]);
}

export function diagnosticNotificationPolicy(event) {
  // A recovered sign-in is a successful outcome; it remains in the CSV.
  if (event.operation === 'auth.recovered') return { notify: false, windowMs: 600000 };
  const expectedSlowStartup = event.operation === 'startup.premium' && event.code === 'timeout';
  // Old clients cannot tell prefetch from paywall. Keep their first warning,
  // but group repetition for an hour. Foreground reports keep a 10 min window.
  const productPrefetch = event.operation === 'iap.products' && !['paywall', 'purchase'].includes(event.context?.phase);
  const urgentPayment = event.category === 'purchase' && !expectedSlowStartup && !productPrefetch;
  return { notify: true, windowMs: urgentPayment ? 600000 : 3600000 };
}

// Strip server stack locations down to module basename and line/column only.
export function serverErrorContext(error) {
  const frames = [...String(error?.stack || '').matchAll(/(?:^|[\s(/])([a-z_]{1,48}\.js:\d{1,6}:\d{1,5})(?=[)\s]|$)/g)].map(match => match[1]);
  return sanitizeDiagnosticContext({ stage: 'server', errorType: error?.name, frames,
    retryable: error?.retryable, overloaded: error?.overloaded,
    supportStage: error?.supportStage, upstreamStatus: error?.upstreamStatus });
}
