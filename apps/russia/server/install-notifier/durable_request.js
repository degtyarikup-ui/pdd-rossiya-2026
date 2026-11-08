const MAX_ATTEMPTS = 3;
const sleepFor = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const INTERNAL_REFERENCE = /^internal error; reference = ([a-z0-9]{16,64})$/;
const OPERATIONS = new Set(['durable.request', 'account.request', 'account.read', 'account.read-many',
  'account.write', 'account.apple-retain', 'account.metadata', 'account.reconcile', 'account.refresh',
  'account.iap-event', 'directory.find', 'directory.register', 'api.user.status', 'api.user.progress',
  'api.user.store.status', 'api.user.store.account-token']);
const logRetry = event => console.log(JSON.stringify(event));

// Exact platform signature observed at the DO boundary. Do not treat arbitrary
// application errors containing "internal error" as transient infrastructure.
export const isCloudflareInternalError = error => typeof error?.message === 'string'
  && INTERNAL_REFERENCE.test(error.message);

function failureDetails(error) {
  const message = typeof error?.message === 'string' ? error.message : '';
  const reference = INTERNAL_REFERENCE.exec(message)?.[1];
  const code = error?.overloaded === true ? 'durable_overloaded'
    : /\bSQLITE_NOMEM\b/.test(message) ? 'durable_memory_exhausted'
    : message.includes('Durable Object storage operation exceeded timeout which caused object to be reset.') ? 'durable_storage_timeout'
    : error?.retryable === true ? 'durable_retryable'
    : reference ? 'cloudflare_internal_error' : null;
  const details = { code: code || 'operation_failed' };
  if (reference) details.platformReference = reference;
  for (const key of ['retryable', 'overloaded', 'remote']) if (typeof error?.[key] === 'boolean') details[key] = error[key];
  return { platform: code !== null, details };
}

// Callers must explicitly identify a safe, idempotent read. The callback creates
// its request afresh: a Request whose body was consumed cannot be sent again.
// Cloudflare can leave a failed stub unusable, so acquire a new one each time.
export async function durableRequest(namespace, id, send, {
  retryableRead = false, sleep = sleepFor, maxAttempts = MAX_ATTEMPTS,
  operation = 'durable.request', logger = logRetry,
} = {}) {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > MAX_ATTEMPTS) {
    throw new RangeError('maxAttempts must be an integer from 1 to 3');
  }
  const attempts = retryableRead === true ? maxAttempts : 1;
  const startedAt = Date.now();
  let lastFailure = null, sawPlatformFailure = false;
  const record = (outcome, attempt, httpStatus) => {
    const event = { event: 'durable_request_retry', operation: OPERATIONS.has(operation) ? operation : 'durable.request',
      outcome, attempts: attempt, elapsedMs: Math.max(0, Date.now() - startedAt), ...lastFailure,
      ...(Number.isInteger(httpStatus) && httpStatus >= 100 && httpStatus <= 599 ? { httpStatus } : {}) };
    // Observability must never change the authoritative response or exception.
    try {
      const logging = logger(event);
      if (logging && typeof logging.catch === 'function') logging.catch(() => {});
    } catch { /* A logger failure must not affect a request. */ }
  };
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const response = await send(namespace.get(id));
      if (attempt > 1 && sawPlatformFailure) {
        const status = response instanceof Response ? response.status : undefined;
        record(status >= 400 ? 'returned_error' : 'recovered', attempt, status);
      }
      return response;
    } catch (error) {
      const failure = failureDetails(error);
      lastFailure = failure.details;
      sawPlatformFailure ||= failure.platform;
      const platformInternal = isCloudflareInternalError(error);
      // Cloudflare infrastructure errors can also be remote. That flag alone
      // must not disable an opted-in read's recovery for this exact signature.
      // An explicit retryable=false, overload, or a write still stops retries.
      const transient = error?.retryable === true || (platformInternal
        && error?.retryable === undefined);
      if (attempt === attempts || !transient || error?.overloaded) {
        if (sawPlatformFailure) record(retryableRead === true && transient && !error?.overloaded && attempt === attempts ? 'exhausted' : 'failed', attempt);
        throw error;
      }
      await sleep((platformInternal && error?.remote === true ? 100 : 25) * 2 ** (attempt - 1));
    }
  }
}
