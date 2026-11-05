import test from 'node:test';
import assert from 'node:assert/strict';
import edge from './worker.js';
test('origin content is preserved and the static CSP is promoted to a response header', async t => {
  t.mock.method(globalThis, 'fetch', async request => {
    assert.equal(new URL(request.url).hostname, 'pdd-drive.ru');
    assert.equal(request.headers.has('cookie'), false);
    assert.equal(request.headers.has('authorization'), false);
    return new Response('<head><meta http-equiv="Content-Security-Policy" content="script-src &#x27;self&#x27;"></head><body>site</body>', { headers: { 'content-type': 'text/html' } });
  });
  const r = await edge.fetch(new Request('https://pdd-drive.app/app/', { headers: { Cookie: 'private=1', Authorization: 'Bearer private' } }));
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-security-policy'), /script-src 'self';.*frame-ancestors 'self'/);
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  assert.match(r.headers.get('strict-transport-security'), /31536000/);
  assert.match(await r.text(), /<body>site/);
});
test('app hostname has a fixed HTTPS target and no arbitrary proxy access exists', async () => {
  const r = await edge.fetch(new Request('https://app.pdd-drive.app/?next=https://evil.invalid'));
  assert.equal(r.status, 308);
  assert.equal(new URL(r.headers.get('location')).origin, 'https://pdd-drive.app');
  assert.equal(new URL(r.headers.get('location')).pathname, '/app/');
  assert.equal((await edge.fetch(new Request('https://evil.invalid/'))).status, 404);
});
