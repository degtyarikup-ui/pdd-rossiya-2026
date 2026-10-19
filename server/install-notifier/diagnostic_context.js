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
  })) if (allowed.includes(input[key])) result[key] = input[key];
  for (const key of ['attempt', 'requestedCount', 'returnedCount', 'missingCount']) {
    if (Number.isInteger(input[key]) && input[key] >= 0 && input[key] <= 100) result[key] = input[key];
  }
  if (typeof input.sdkCodeHash === 'string' && /^[a-f0-9]{16}$/.test(input.sdkCodeHash)) result.sdkCodeHash = input.sdkCodeHash;
  if (Array.isArray(input.missingIds)) result.missingIds = [...new Set(input.missingIds.filter(v => products.has(v)))].slice(0, 4);
  if (Array.isArray(input.frames)) result.frames = input.frames.filter(v => typeof v === 'string' && v.length <= 160 && /^(?:package:pdd_app\/(?:[a-zA-Z0-9_]+\/)*[a-zA-Z0-9_]+\.dart(?::\d{1,6}(?::\d{1,5})?)?|[a-z_]{1,48}\.js:\d{1,6}:\d{1,5})$/.test(v)).slice(0, 6);
  return result;
}

export function diagnosticOs(value) {
  return typeof value === 'string' && /^(?:Android|iOS) [\d.]{1,16}(?: \(SDK \d{1,3}\))?$/.test(value) ? value : null;
}

export function diagnosticNotificationPolicy(event) {
  // A recovered sign-in is a successful outcome; it remains in the CSV.
  if (event.operation === 'auth.recovered') return { notify: false, windowMs: 600000 };
  const expectedSlowStartup = event.operation === 'startup.premium' && event.code === 'timeout';
  // Old clients cannot tell prefetch from paywall. Keep their first warning,
  // but group repetition for an hour. Foreground reports keep a 10 min window.
  const productPrefetch = event.operation === 'iap.products' && !['paywall', 'purchase'].includes(event.context?.phase);
  return { notify: true, windowMs: expectedSlowStartup || productPrefetch ? 3600000 : 600000 };
}

// Strip server stack locations down to module basename and line/column only.
export function serverErrorContext(error) {
  const frames = [...String(error?.stack || '').matchAll(/(?:^|[\s(/])([a-z_]{1,48}\.js:\d{1,6}:\d{1,5})(?=[)\s]|$)/g)].map(match => match[1]);
  return sanitizeDiagnosticContext({ stage: 'server', errorType: error?.name, frames });
}
