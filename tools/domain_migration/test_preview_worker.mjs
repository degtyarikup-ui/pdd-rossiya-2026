import assert from 'node:assert/strict';
import {gzipSync, gunzipSync} from 'node:zlib';
import test from 'node:test';
import {createPreviewWorker} from './preview_worker.mjs';

const policy = {
  'Content-Security-Policy': "default-src 'self'; connect-src 'self'; form-action 'none'",
  'X-Robots-Tag': 'noindex, nofollow, noarchive, nosnippet',
  'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
};
const checkPolicy = response => {
  for (const [key, value] of Object.entries(policy)) assert.equal(response.headers.get(key), value, key);
};
const request = (path, options = {}) => new Request('https://pdd-drive.app' + path, options);

test('methods and disabled paths never reach assets or an external fetch', async () => {
  const worker = createPreviewWorker(policy);
  const calls = [];
  const env = {ASSETS: {fetch: async value => {calls.push(value); throw Error('unexpected asset fetch');}}};
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => {throw Error('global network must never be used');};
  try {
    for (const method of ['POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']) {
      const response = await worker.fetch(request('/app/index.html', {method}), env);
      assert.equal(response.status, 405);
      assert.equal(response.headers.get('Allow'), 'GET, HEAD');
      checkPolicy(response);
    }
    for (const path of ['/api', '/api/user/status', '/app/api/login', '/app/API/login', '/%61pi/pay', '/app/%2561pi/progress', '/app/%252561pi/progress', '/__staging_disabled__', '/app/__staging_disabled__/api/pay', '/app/__staging_disabled__anything']) {
      const response = await worker.fetch(request(path), env);
      assert.equal(response.status, 403, path);
      checkPolicy(response);
    }
    for (const path of ['/app/%252e%252e/index.html', '/app/%255capi', '/app/%00x', '/app/%xx']) {
      const response = await worker.fetch(request(path), env);
      assert.equal(response.status, 400, path);
      checkPolicy(response);
    }
    assert.equal(calls.length, 0);
  } finally {globalThis.fetch = originalFetch;}
});

test('strict host validation rejects production API and arbitrary hosts', async () => {
  const worker = createPreviewWorker(policy);
  const calls = [];
  const env = {ASSETS: {fetch: async value => {calls.push(value.url); return new Response('local');}}};
  for (const host of ['api.pdd-drive.app', 'pdd-drive.ru', 'evil.test', 'pdd-drive.app.evil.test', 'evil.sergei-pdd.workers.dev']) {
    const response = await worker.fetch(new Request('https://' + host + '/index.html'), env);
    assert.equal(response.status, 403, host);
    checkPolicy(response);
  }
  assert.equal(calls.length, 0);
  for (const host of ['pdd-drive.app', 'pdd-domain-migration-preview.sergei-pdd.workers.dev', 'localhost:8787', '127.0.0.1:8787']) {
    assert.equal((await worker.fetch(new Request('https://' + host + '/index.html'), env)).status, 200);
  }
  assert.equal(calls.length, 4);
});

test('only assets binding receives sanitized GET/HEAD; directory and missing paths have no SPA fallback', async () => {
  const calls = [];
  const worker = createPreviewWorker(policy);
  const env = {ASSETS: {fetch: async value => {
    calls.push(value);
    const path = new URL(value.url).pathname;
    return path === '/app/index.html' ? new Response(value.method === 'HEAD' ? null : 'APP', {headers: {'Cache-Control': 'public', 'Set-Cookie': 'bad=1', 'Access-Control-Allow-Origin': '*'}}) : new Response('Missing', {status: 404});
  }}};
  const response = await worker.fetch(request('/app/?token=never-forward', {headers: {Authorization: 'Bearer synthetic', Cookie: 'synthetic=1', Range: 'bytes=0-4'}}), env);
  assert.equal(await response.text(), 'APP');
  checkPolicy(response);
  assert.equal(response.headers.get('Set-Cookie'), null);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
  assert.equal(calls[0].url, 'https://pdd-drive.app/app/index.html');
  assert.equal(calls[0].redirect, 'manual', 'asset redirects must never be followed before validation');
  assert.deepEqual([...calls[0].headers], [['accept-encoding', 'identity']]);
  const missing = await worker.fetch(request('/app/missing'), env);
  assert.equal(missing.status, 404);
  assert.equal(await missing.text(), 'Missing');
  assert.equal(new URL(calls[1].url).pathname, '/app/missing');
  checkPolicy(missing);
  const head = await worker.fetch(request('/app/', {method: 'HEAD'}), env);
  assert.equal(head.body, null);
  assert.equal(calls[2].method, 'HEAD');
});

test('binding failure and any redirect fail closed with policy headers', async () => {
  const worker = createPreviewWorker(policy);
  assert.equal((await worker.fetch(request('/'), {})).status, 503);
  for (const assetFetch of [async () => {throw Error('unavailable');}, async () => Response.redirect('https://pdd-drive.ru/'), async () => Response.redirect('https://pdd-drive.app/app/')]) {
    const response = await worker.fetch(request('/'), {ASSETS: {fetch: assetFetch}});
    assert.equal(response.status, 502);
    assert.equal(response.headers.get('Location'), null);
    checkPolicy(response);
  }
});

test('gzip mapped wasm keeps exact bytes, correct MIME, manual encoding, HEAD and no direct .gz URL', async () => {
  const original = Buffer.concat([Buffer.from('\0asm\x01\0\0\0'), Buffer.alloc(4096, 42)]);
  const packed = gzipSync(original);
  const assetPath = '/app/godot/index.wasm.gz';
  const mappings = {'/app/godot/index.wasm': {assetPath, contentType: 'application/wasm', gzipBytes: packed.length}};
  const worker = createPreviewWorker(policy, mappings);
  const calls = [];
  const env = {ASSETS: {fetch: async value => {
    calls.push(value);
    return new Response(value.method === 'HEAD' ? null : packed, {headers: {'Content-Type': 'application/gzip', 'Content-Length': String(packed.length)}});
  }}};
  const NativeResponse = globalThis.Response;
  const inits = [];
  globalThis.Response = class extends NativeResponse {constructor(body, init) {super(body, init); inits.push(init);}};
  try {
    const response = await worker.fetch(request('/app/godot/index.wasm', {headers: {'Accept-Encoding': 'br, gzip'}}), env);
    assert.equal(response.headers.get('Content-Encoding'), 'gzip');
    assert.equal(response.headers.get('Content-Type'), 'application/wasm');
    assert.equal(response.headers.get('Content-Length'), String(packed.length));
    assert.deepEqual(gunzipSync(Buffer.from(await response.arrayBuffer())), original);
    assert.equal(inits.at(-1).encodeBody, 'manual');
    assert.equal(new URL(calls[0].url).pathname, assetPath);
    assert.equal(calls[0].redirect, 'manual');
    assert.equal(calls[0].headers.get('Accept-Encoding'), 'identity');
    checkPolicy(response);
    const head = await worker.fetch(request('/app/godot/index.wasm', {method: 'HEAD'}), env);
    assert.equal(head.status, 200);
    assert.equal(head.body, null);
    assert.equal(head.headers.get('Content-Encoding'), 'gzip');
    assert.equal(head.headers.get('Content-Type'), 'application/wasm');
    assert.equal((await worker.fetch(request(assetPath), env)).status, 404);
    const count = calls.length;
    for (const accepted of ['identity', 'gzip;q=0', 'gzip;q=0, *;q=1', 'br', 'gzip;q=bogus']) {
      assert.equal((await worker.fetch(request('/app/godot/index.wasm', {headers: {'Accept-Encoding': accepted}}), env)).status, 406, accepted);
    }
    assert.equal(calls.length, count);
  } finally {globalThis.Response = NativeResponse;}
});

test('gzip mapping cannot point at a backend, and compressed-source mismatch fails closed', async () => {
  assert.throws(() => createPreviewWorker(policy, {'/file.wasm': {assetPath: 'https://api.pdd-drive.app/file.gz', contentType: 'application/wasm', gzipBytes: 8}}));
  assert.throws(() => createPreviewWorker({}, {}));
  const worker = createPreviewWorker(policy, {'/file.wasm': {assetPath: '/file.wasm.gz', contentType: 'application/wasm', gzipBytes: 8}});
  const response = await worker.fetch(request('/file.wasm'), {ASSETS: {fetch: async () => new Response('encoded twice', {headers: {'Content-Encoding': 'br'}})}});
  assert.equal(response.status, 502);
  checkPolicy(response);
});
