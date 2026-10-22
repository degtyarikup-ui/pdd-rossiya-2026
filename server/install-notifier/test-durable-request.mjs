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
