import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { chromium } from 'playwright';
import worker from './worker.js';
import { MemoryKV } from './fixture-account.mjs';
test('real admin client logs in and obtains CSRF for a cookie-authenticated change', { timeout: 45000 }, async () => {
  const env = { INSTALLS: new MemoryKV(), ADMIN_PASSWORD: crypto.randomUUID(), SESSION_SECRET: crypto.randomUUID() };
  const mutations = [];
  const server = createServer(async (incoming, outgoing) => {
    try {
      const parts = []; for await (const part of incoming) parts.push(part);
      const body = Buffer.concat(parts);
      const request = new Request('http://' + incoming.headers.host + incoming.url, { method: incoming.method, headers: incoming.headers, ...(body.length ? { body, duplex: 'half' } : {}) });
      if (incoming.method === 'POST') mutations.push({ path: incoming.url, csrf: incoming.headers['x-admin-csrf'] });
      const response = await worker.fetch(request, env, { waitUntil: p => p.catch(() => {}) });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch { outgoing.writeHead(500); outgoing.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
    const page = await browser.newPage();
    const origin = 'http://127.0.0.1:' + server.address().port;
    await page.goto(origin + '/admin', { waitUntil: 'domcontentloaded' });
    await page.locator('#login-pwd').fill(env.ADMIN_PASSWORD);
    await Promise.all([page.waitForNavigation({ waitUntil: 'domcontentloaded' }), page.locator('#login-submit-btn').click()]);
    const status = await page.evaluate(async () => (await fetch('/api/admin/ai/legacy', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ open: false }) })).status);
    assert.equal(status, 200);
    assert.equal(await env.INSTALLS.get('ai_legacy_open'), 'off');
    assert.match(mutations.find(m => m.path === '/api/admin/ai/legacy').csrf, /^[a-f0-9]{64}$/);
    const unsafe = await page.evaluate(async () => (await fetch('/?report=daily&send=true')).status);
    assert.equal(unsafe, 405);
  } finally { await browser?.close(); await new Promise(resolve => server.close(resolve)); }
});
