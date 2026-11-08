import test from 'node:test';
import assert from 'node:assert/strict';
import { durableRequest } from './durable_request.js';

function binding(outcomes) {
  const calls = [], stubs = [];
  const namespace = { get(id) {
    const index = stubs.length;
    const stub = { async fetch(request) {
      const body = request instanceof Request ? await request.text() : null;
      calls.push({ id, index, request, body });
      const outcome = outcomes[index];
      if (outcome?.error) throw outcome.error;
      return outcome?.response;
    } };
    stubs.push(stub);
    return stub;
  } };
  return { namespace, calls, stubs };
}
const failure = flags => Object.assign(new Error('injected Durable Object failure'), flags);

test('remote platform internal reads recover with fresh stubs and a bounded slower backoff', async () => {
  const internal = () => Object.assign(new Error('internal error; reference = 185s62c9h07iotqpjb2ek3ep'), { remote: true });
  const response = Response.json({ value: 'authoritative' });
  const f = binding([{ error: internal() }, { error: internal() }, { response }]);
  const delays = [], logs = [];
  assert.equal(await durableRequest(f.namespace, 'account', stub => stub.fetch('https://account/read'), {
    retryableRead: true, sleep: async delay => delays.push(delay), logger: event => logs.push(event),
  }), response);
  assert.equal(f.stubs.length, 3);
  assert.equal(new Set(f.stubs).size, 3);
  assert.deepEqual(delays, [100, 200]);
  assert.equal(logs.length, 1);
  assert.equal(logs[0].outcome, 'recovered');
  assert.equal(logs[0].remote, true);
  assert.equal(logs[0].attempts, 3);
});

test('remote platform read exhaustion preserves the last error and explicit terminal flags', async () => {
  const internal = flags => Object.assign(new Error('internal error; reference = 185s62c9h07iotqpjb2ek3ep'), { remote: true, ...flags });
  const errors = [internal(), internal(), internal()];
  const f = binding(errors.map(error => ({ error }))), delays = [], logs = [];
  await assert.rejects(durableRequest(f.namespace, 'account', stub => stub.fetch('https://account/read'), {
    retryableRead: true, sleep: async delay => delays.push(delay), logger: event => logs.push(event),
  }), error => error === errors[2]);
  assert.equal(f.calls.length, 3);
  assert.deepEqual(delays, [100, 200]);
  assert.equal(logs[0].outcome, 'exhausted');
  for (const flags of [{ retryable: false }, { overloaded: true }, { retryable: 'true' }]) {
    const error = internal(flags), terminal = binding([{ error }, { response: Response.json({ ok: true }) }]);
    await assert.rejects(durableRequest(terminal.namespace, 'account', stub => stub.fetch('https://account/read'), {
      retryableRead: true, sleep: async () => assert.fail('terminal flag must not retry'),
    }), caught => caught === error);
    assert.equal(terminal.calls.length, 1);
  }
});

test('an opted-in read recovers with fresh stubs and bounded exponential backoff', async () => {
  const first = failure({ retryable: true }), second = failure({ retryable: true });
  const response = Response.json({ value: 'authoritative' });
  const { namespace, calls, stubs } = binding([{ error: first }, { error: second }, { response }]);
  const delays = [], requests = [];
  const result = await durableRequest(namespace, 'account-id', stub => {
    const request = new Request('https://account.internal/_account/read', {
      method: 'POST', body: JSON.stringify({ key: 'auth_generation:account-id' }),
    });
    requests.push(request);
    return stub.fetch(request);
  }, { retryableRead: true, sleep: async delay => delays.push(delay) });
  assert.equal(result, response);
  assert.deepEqual(delays, [25, 50]);
  assert.equal(stubs.length, 3);
  assert.equal(new Set(stubs).size, 3);
  assert.equal(new Set(requests).size, 3);
  assert.deepEqual(calls.map(call => call.id), ['account-id', 'account-id', 'account-id']);
  assert.deepEqual(calls.map(call => call.body), Array(3).fill(JSON.stringify({ key: 'auth_generation:account-id' })));
});

test('writes and unclassified requests never retry even when infrastructure says retryable', async () => {
  for (const options of [{}, { retryableRead: false }, { retryableRead: 'true' }]) {
    const error = failure({ retryable: true });
    const { namespace, calls } = binding([{ error }, { response: Response.json({ ok: true }) }]);
    const delays = [];
    await assert.rejects(durableRequest(namespace, 'account-id', stub => stub.fetch('https://account.internal/_account/write'), {
      ...options, sleep: async delay => delays.push(delay),
    }), caught => caught === error && caught.retryable === true);
    assert.equal(calls.length, 1);
    assert.deepEqual(delays, []);
  }
});

test('overload, unknown exceptions and non-boolean retry flags are terminal', async () => {
  for (const flags of [{ retryable: true, overloaded: true }, {}, { retryable: false }, { retryable: 'true' }]) {
    const error = failure(flags);
    const { namespace, calls } = binding([{ error }, { response: Response.json({ ok: true }) }]);
    const delays = [];
    await assert.rejects(durableRequest(namespace, 'account-id', stub => stub.fetch('https://account.internal/read'), {
      retryableRead: true, sleep: async delay => delays.push(delay),
    }), caught => caught === error);
    assert.equal(calls.length, 1);
    assert.deepEqual(delays, []);
  }
});

test('exhaustion preserves the last original exception and its Cloudflare flags', async () => {
  const errors = [failure({ retryable: true }), failure({ retryable: true }), failure({ retryable: true, remote: true })];
  const { namespace, calls } = binding(errors.map(error => ({ error })));
  const delays = [];
  await assert.rejects(durableRequest(namespace, 'account-id', stub => stub.fetch('https://account.internal/read'), {
    retryableRead: true, sleep: async delay => delays.push(delay),
  }), caught => caught === errors[2] && caught.retryable === true && caught.remote === true);
  assert.equal(calls.length, 3);
  assert.deepEqual(delays, [25, 50]);
});

test('a later non-retryable failure stops immediately and HTTP responses are never retried', async () => {
  const error = failure({ overloaded: true, retryable: true });
  const { namespace, calls } = binding([{ error: failure({ retryable: true }) }, { error }]);
  const delays = [];
  await assert.rejects(durableRequest(namespace, 'account-id', stub => stub.fetch('https://account.internal/read'), {
    retryableRead: true, sleep: async delay => delays.push(delay),
  }), caught => caught === error);
  assert.equal(calls.length, 2);
  assert.deepEqual(delays, [25]);

  for (const status of [429, 500, 503]) {
    const response = new Response('unavailable', { status });
    const fixture = binding([{ response }]);
    assert.equal(await durableRequest(fixture.namespace, 'account-id', stub => stub.fetch('https://account.internal/read'), {
      retryableRead: true, sleep: async () => assert.fail('HTTP status must not schedule retries'),
    }), response);
    assert.equal(fixture.calls.length, 1);
  }
});

test('the attempt budget may be reduced but cannot exceed three', async () => {
  const error = failure({ retryable: true });
  for (const maxAttempts of [1, 2]) {
    const { namespace, calls } = binding(Array.from({ length: maxAttempts }, () => ({ error })));
    const delays = [];
    await assert.rejects(durableRequest(namespace, 'account-id', stub => stub.fetch('https://account.internal/read'), {
      retryableRead: true, maxAttempts, sleep: async delay => delays.push(delay),
    }), caught => caught === error);
    assert.equal(calls.length, maxAttempts);
    assert.equal(delays.length, maxAttempts - 1);
  }
  for (const maxAttempts of [0, -1, 4, 1.5, Infinity, NaN]) {
    const { namespace, calls } = binding([]);
    await assert.rejects(durableRequest(namespace, 'account-id', stub => stub.fetch('https://account.internal/read'), {
      retryableRead: true, maxAttempts,
    }), RangeError);
    assert.equal(calls.length, 0);
  }
});

test('unflagged platform internal errors recover only for explicit reads; terminal flags and writes stay terminal', async () => {
  const internal = flags => Object.assign(new Error('internal error; reference = 185s62c9h07iotqpjb2ek3ep'), flags);
  const response = Response.json({ value: 'preserved' });
  const recovered = binding([{ error: internal() }, { response }]);
  const delays = [];
  assert.equal(await durableRequest(recovered.namespace, 'account', stub => stub.fetch('https://account/read'), {
    retryableRead: true, sleep: async n => delays.push(n),
  }), response);
  assert.equal(recovered.stubs.length, 2);
  assert.deepEqual(delays, [25]);
  for (const flags of [{ retryable: false }, { remote: true, retryable: false }, { overloaded: true }, { retryable: 'true' }]) {
    const error = internal(flags), f = binding([{ error }]);
    await assert.rejects(durableRequest(f.namespace, 'account', stub => stub.fetch('https://account/read'), {
      retryableRead: true, sleep: async () => assert.fail('terminal error must not wait'),
    }), e => e === error);
    assert.equal(f.calls.length, 1);
  }
  for (const retryableRead of [false, undefined]) {
    const error = internal(), f = binding([{ error }]);
    await assert.rejects(durableRequest(f.namespace, 'account', stub => stub.fetch('https://account/write'), { retryableRead }), e => e === error);
    assert.equal(f.calls.length, 1);
  }
  for (const message of ['internal error', 'internal error; reference = private?token=secret',
    'application internal error; reference = 185s62c9h07iotqpjb2ek3ep']) {
    const error = new Error(message), f = binding([{ error }]);
    await assert.rejects(durableRequest(f.namespace, 'account', stub => stub.fetch('https://account/read'), { retryableRead: true }), e => e === error);
    assert.equal(f.calls.length, 1);
  }
});

test('first-attempt successes, HTTP failures and ordinary application exceptions produce no retry event', async () => {
  const logs = [];
  const logger = event => logs.push(event);
  for (const status of [200, 429, 500, 503]) {
    const response = new Response(null, { status }), f = binding([{ response }]);
    assert.equal(await durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
      retryableRead: true, operation: 'api.user.status', logger,
    }), response);
    assert.equal(f.calls.length, 1);
  }
  for (const flags of [{}, { remote: true }, { retryable: false }, { retryable: 'true' }]) {
    const error = Object.assign(new Error('invalid purchase private-token'), flags), f = binding([{ error }]);
    await assert.rejects(durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
      retryableRead: true, operation: 'account.write', logger,
    }), caught => caught === error);
  }
  assert.deepEqual(logs, []);
});

test('recovered read emits one structured retry summary with exact opaque reference and bounded operation', async t => {
  let clock = 1000;
  t.mock.method(Date, 'now', () => clock);
  const reference = '185s62c9h07iotqpjb2ek3ep';
  const error = new Error('internal error; reference = ' + reference);
  const response = Response.json({ profile: 'not in logs' });
  const f = binding([{ error }, { response }]), logs = [];
  assert.equal(await durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private?token=secret'), {
    retryableRead: true, operation: 'account.read-many', logger: event => logs.push(event),
    sleep: async delay => { clock += delay; },
  }), response);
  assert.equal(f.stubs.length, 2);
  assert.deepEqual(logs, [{ event: 'durable_request_retry', operation: 'account.read-many',
    outcome: 'recovered', attempts: 2, elapsedMs: 25, code: 'cloudflare_internal_error', platformReference: reference,
    httpStatus: 200 }]);
});

test('a returned HTTP error after a platform retry is qualified rather than counted as recovery', async () => {
  const response = new Response(null, { status: 503 });
  const f = binding([{ error: failure({ retryable: true }) }, { response }]), logs = [], delays = [];
  assert.equal(await durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
    retryableRead: true, operation: 'api.user.status', logger: event => logs.push(event), sleep: async delay => delays.push(delay),
  }), response);
  assert.equal(f.calls.length, 2, 'the returned HTTP failure must not start another retry');
  assert.deepEqual(delays, [25]);
  assert.equal(logs.length, 1);
  assert.equal(logs[0].outcome, 'returned_error');
  assert.equal(logs[0].httpStatus, 503);
  assert.equal(logs[0].attempts, 2);

  const value = { status: 503 }, generic = binding([{ error: failure({ retryable: true }) }, { response: value }]);
  const genericLogs = [];
  assert.equal(await durableRequest(generic.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
    retryableRead: true, logger: event => genericLogs.push(event), sleep: async () => {},
  }), value);
  assert.equal(genericLogs[0].outcome, 'recovered');
  assert.equal(Object.hasOwn(genericLogs[0], 'httpStatus'), false, 'a generic result is not an HTTP response');
});

test('exhausted read logs once and preserves the original terminal error and boolean flags', async () => {
  const errors = [failure({ retryable: true }), failure({ retryable: true }), failure({ retryable: true, remote: true, overloaded: false })];
  const f = binding(errors.map(error => ({ error }))), logs = [], delays = [];
  await assert.rejects(durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
    retryableRead: true, operation: 'api.user.status', logger: event => logs.push(event), sleep: async delay => delays.push(delay),
  }), caught => caught === errors[2]);
  assert.equal(f.stubs.length, 3);
  assert.deepEqual(delays, [25, 50]);
  assert.equal(logs.length, 1);
  const { elapsedMs, ...event } = logs[0];
  assert.ok(Number.isFinite(elapsedMs) && elapsedMs >= 0);
  assert.deepEqual(event, { event: 'durable_request_retry', operation: 'api.user.status', outcome: 'exhausted',
    attempts: 3, code: 'durable_retryable', retryable: true, overloaded: false, remote: true });
});

test('platform failures in writes and remote terminal reads are logged once without introducing retries', async () => {
  for (const retryableRead of [false, true]) {
    const error = Object.assign(new Error('internal error; reference = 185s62c9h07iotqpjb2ek3ep'),
      retryableRead ? { remote: true, retryable: false } : { retryable: true });
    const f = binding([{ error }, { response: Response.json({ ok: true }) }]), logs = [];
    await assert.rejects(durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
      retryableRead, operation: retryableRead ? 'account.read' : 'account.write', logger: event => logs.push(event),
      sleep: async () => assert.fail('a terminal failure must not wait'),
    }), caught => caught === error);
    assert.equal(f.calls.length, 1);
    assert.equal(logs.length, 1);
    assert.equal(logs[0].outcome, 'failed');
    assert.equal(logs[0].attempts, 1);
    if (retryableRead) assert.equal(logs[0].remote, true);
  }
});

test('retry events redact arbitrary operation, malformed reference, error payloads and non-boolean flags', async () => {
  const errors = [
    Object.assign(new Error('internal error; reference = private?token=secret'), { retryable: true, remote: 'private-profile' }),
    Object.assign(new Error('internal error; reference = 185s62c9h07iotqpjb2ek3ep private-token'), { retryable: true, overloaded: 'private-email' }),
  ];
  const logs = [];
  for (const error of errors) {
    error.stack = 'private-stack secret';
    error.profile = { email: 'private@example.invalid' };
    error.platformReference = 'private-injected-reference';
    const f = binding([{ error }]);
    await assert.rejects(durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private?token=secret'), {
      operation: 'api.user.status?email=private@example.invalid', logger: event => logs.push(event),
    }), caught => caught === error);
    assert.equal(f.calls.length, 1);
  }
  assert.equal(logs.length, 2);
  for (const { elapsedMs, ...event } of logs) {
    assert.ok(Number.isFinite(elapsedMs) && elapsedMs >= 0);
    assert.deepEqual(event, { event: 'durable_request_retry', operation: 'durable.request', outcome: 'failed',
      attempts: 1, code: 'durable_retryable', retryable: true });
  }
  assert.doesNotMatch(JSON.stringify(logs), /private|secret|stack|profile|https|@/);
});

test('a later application failure is summarized without hiding it after a platform retry', async () => {
  const terminal = new Error('private application failure');
  const f = binding([{ error: failure({ retryable: true }) }, { error: terminal }]), logs = [];
  await assert.rejects(durableRequest(f.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
    retryableRead: true, logger: event => logs.push(event), sleep: async () => {},
  }), caught => caught === terminal);
  assert.equal(f.calls.length, 2);
  assert.equal(logs.length, 1);
  assert.equal(logs[0].outcome, 'failed');
  assert.equal(logs[0].code, 'operation_failed');
  assert.equal(logs[0].attempts, 2);
  assert.doesNotMatch(JSON.stringify(logs), /private|application/);
});

test('a failed diagnostic logger cannot change successful recovery or the thrown platform error', async () => {
  for (const logger of [() => { throw new Error('fixture logger unavailable'); },
    async () => { throw new Error('fixture async logger unavailable'); }]) {
    const response = Response.json({ ok: true }), recovered = binding([{ error: failure({ retryable: true }) }, { response }]);
    assert.equal(await durableRequest(recovered.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
      retryableRead: true, logger, sleep: async () => {},
    }), response);
    const error = failure({ overloaded: true }), failed = binding([{ error }]);
    await assert.rejects(durableRequest(failed.namespace, 'private-account-id', stub => stub.fetch('https://account/private'), {
      retryableRead: true, logger,
    }), caught => caught === error);
  }
});
