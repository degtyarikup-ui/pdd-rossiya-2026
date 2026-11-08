import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { ANALYTICS_LOADER_JS } from './analytics_loader.js';

test('an authorization failure retires an already-resolved session check before it can reveal the app', async () => {
  let resolveSession, dataReads = 0, renders = 0, resets = 0;
  const session = new Promise(resolve => { resolveSession = resolve; });
  const elements = new Map(['app', 'login-overlay', 'refresh-btn', 'admin-data-state',
    'admin-error-banner', 'admin-error-text'].map(id => [id, {
    style: {}, classList: { remove() {}, add() {} }, setAttribute() {}, textContent: '',
  }]));
  const snapshotKey = 'pdd-admin-analytics-v1:ru:7';
  const storage = {
    [snapshotKey]: JSON.stringify({ at: Date.now(), data: { totals: { views: 123 }, timeline: [] } }),
    getItem(key) { return this[key] ?? null; },
    removeItem(key) { delete this[key]; },
  };
  const sandbox = {
    console, AbortController, Date, Number, JSON,
    // The regression depends on microtask order, not wall-clock delays.
    setTimeout() { return 1; }, clearTimeout() {},
    currentApp: 'ru', currentDays: 7, __analyticsRequestId: 0,
    localStorage: storage, document: { getElementById(id) { return elements.get(id); } },
    renderDashboard() { renders++; },
    AdminData: {
      ensureSession() { return session; },
      reset() { resets++; },
      async load() { dataReads++; },
    },
  };
  sandbox.window = sandbox;
  vm.runInNewContext(ANALYTICS_LOADER_JS, sandbox);
  sandbox.__anData = { privatePreviousSession: true };

  const loading = sandbox.checkAuthAndLoad();
  const controller = sandbox.anActiveLoad.controller;
  const pendingRequestId = sandbox.__analyticsRequestId;

  // /session succeeded, but another endpoint rejects authorization before the
  // awaiting analytics loader gets its next microtask. Its success is obsolete.
  resolveSession();
  sandbox.anAuthRequired();
  assert.equal(elements.get('app').style.display, 'none');
  await loading;

  assert.equal(elements.get('app').style.display, 'none', 'stale session success must not show old private DOM');
  assert.equal(elements.get('login-overlay').style.display, 'flex');
  assert.equal(sandbox.anAuthenticated, false);
  assert.equal(sandbox.anActiveLoad, null);
  assert.ok(sandbox.__analyticsRequestId > pendingRequestId);
  assert.equal(controller.signal.aborted, true);
  assert.equal(sandbox.__anData, null);
  assert.equal(storage.getItem(snapshotKey), null);
  assert.equal(resets, 1);
  assert.equal(dataReads, 0, 'retired loader must not start another private data request');
  assert.equal(renders, 0, 'retired loader must not replay a persisted snapshot');
});
