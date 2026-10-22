const MAX_ATTEMPTS = 3;
const sleepFor = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

// Callers must explicitly identify a safe, idempotent read. The callback creates
// its request afresh: a Request whose body was consumed cannot be sent again.
// Cloudflare can leave a failed stub unusable, so acquire a new one each time.
export async function durableRequest(namespace, id, send, {
  retryableRead = false, sleep = sleepFor, maxAttempts = MAX_ATTEMPTS,
} = {}) {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > MAX_ATTEMPTS) {
    throw new RangeError('maxAttempts must be an integer from 1 to 3');
  }
  const attempts = retryableRead === true ? maxAttempts : 1;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await send(namespace.get(id));
    } catch (error) {
      if (attempt === attempts || error?.retryable !== true || error?.overloaded) throw error;
      await sleep(25 * 2 ** (attempt - 1));
    }
  }
}
