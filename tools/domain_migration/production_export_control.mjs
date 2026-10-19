// Operator-only Cloudflare control client. Credentials stay local and are never
// included in backup payloads, command arguments, logs or exception messages.
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
export const ACCOUNT_ID = 'a4eee3dae596a9dd9ea14dc123874f9d';
export const SOURCE_SCRIPT = 'pdd-install-notifier';
export const API_BASE = '/accounts/' + ACCOUNT_ID;
export const SOURCE_BASE = API_BASE + '/workers/scripts/' + SOURCE_SCRIPT;
const fail = status => { throw new Error('Cloudflare operation failed' + (status ? ' HTTP ' + status : '')); };
export async function createControlClient({ allowWrites = false, fetchImpl = fetch } = {}) {
  const config = await readFile(join(homedir(), 'Library/Preferences/.wrangler/config/default.toml'), 'utf8');
  const token = /^\s*oauth_token\s*=\s*"([^"\r\n]+)"/m.exec(config)?.[1];
  if (!token) fail();
  let last = 0;
  async function raw(method, path, body) {
    if (!path.startsWith(API_BASE + '/') || path.includes('://') || /[\r\n]/.test(path)) fail();
    if (method !== 'GET' && !allowWrites) fail();
    for (let attempt = 0; attempt < 5; attempt++) {
      await new Promise(resolve => setTimeout(resolve, Math.max(0, 270 - (Date.now() - last))));
      last = Date.now();
      let response;
      try { response = await fetchImpl('https://api.cloudflare.com/client/v4' + path, {
        method, redirect: 'error', signal: AbortSignal.timeout(60000),
        headers: { authorization: 'Bearer ' + token, ...(body && !(body instanceof FormData) ? { 'content-type': 'application/json' } : {}) },
        ...(body ? { body: body instanceof FormData ? body : JSON.stringify(body) } : {}),
      }); } catch { if (attempt === 4) fail(); await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1))); continue; }
      if (!response.ok) {
        const status = response.status; await response.body?.cancel();
        if ([429, 500, 502, 503, 504].includes(status) && attempt < 4) { await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1))); continue; }
        fail(status);
      }
      return response;
    }
    fail();
  }
  async function json(method, path, body) {
    const response = await raw(method, path, body); let value;
    try { value = await response.json(); } catch { fail(); }
    if (value.success !== true) fail();
    return value;
  }
  return { raw, json };
}
export function makeUpload({ modules, mainModule, settings, extraBindings = [] }) {
  if (!Array.isArray(modules) || !modules.length || !modules.some(module => module.name === mainModule)
    || new Set(modules.map(module => module.name)).size !== modules.length
    || modules.some(module => typeof module.name !== 'string' || module.name === 'metadata' || module.name.startsWith('/')
      || module.name.split('/').some(part => !part || part === '.' || part === '..')
      || typeof module.type !== 'string' || !(module.bytes instanceof Uint8Array))) fail();
  const form = new FormData();
  // Opaque secret values cannot be downloaded. Preserve them by type, then
  // explicitly delete the one temporary export secret during cleanup.
  const metadata = { main_module: mainModule,
    bindings: [...settings.bindings.filter(binding => !['secret_text', 'secret_key'].includes(binding.type)), ...extraBindings],
    keep_bindings: ['secret_text', 'secret_key'],
  };
  for (const key of ['compatibility_date', 'compatibility_flags', 'usage_model', 'tags', 'tail_consumers', 'logpush', 'observability', 'placement', 'limits']) {
    if (settings[key] !== undefined) metadata[key] = settings[key];
  }
  form.set('metadata', JSON.stringify(metadata));
  for (const { name, type, bytes } of modules) form.set(name, new File([bytes], name, { type }));
  return form;
}
export async function readInventory(api, namespaces) {
  const objects = [], classes = {};
  for (const namespace of namespaces) {
    const seen = new Set(), cursors = new Set(); let cursor;
    for (;;) {
      const params = new URLSearchParams({ limit: '10000', ...(cursor ? { cursor } : {}) });
      const body = await api.json('GET', API_BASE + '/workers/durable_objects/namespaces/' + namespace.id + '/objects?' + params);
      if (!Array.isArray(body.result)) fail();
      for (const row of body.result) {
        if (!/^[a-f0-9]{64}$/.test(row.id) || seen.has(row.id)) fail();
        seen.add(row.id);
        objects.push({ className: namespace.class, namespaceId: namespace.id, objectId: row.id });
      }
      const next = body.result_info?.cursor || body.result_info?.cursors?.after;
      if (!next) { if (body.result_info?.list_complete === false || body.list_complete === false) fail(); break; }
      if (cursors.has(next)) fail(); cursors.add(next); cursor = next;
    }
    classes[namespace.class] = seen.size;
  }
  return { objects, classes, capturedAt: new Date().toISOString(), listingComplete: true };
}
