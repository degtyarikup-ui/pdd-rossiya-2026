// Apple posts the result here. Credentials travel back in a URL fragment
// (never sent to GitHub Pages), and Flutter removes it before app startup.
// State/nonce are checked by the originating tab; /api/auth/session verifies
// Apple's signature/audience and issues the actual application session.
export const APPLE_WEB_CALLBACK_PATH = '/auth/apple/callback';
export async function handleAppleWebCallback(request) {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: { Allow: 'POST' } });
  if (!request.headers.get('content-type')?.startsWith('application/x-www-form-urlencoded')) return new Response('Invalid content type', { status: 415 });
  const reader = request.body?.getReader();
  if (!reader) return new Response('Missing body', { status: 400 });
  const chunks = []; let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 32768) { await reader.cancel(); return new Response('Too large', { status: 413 }); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const form = new URLSearchParams(new TextDecoder().decode(bytes));
  const state = form.get('state');
  if (!/^[a-f0-9]{64}$/.test(state || '')) return new Response('Invalid state', { status: 400 });
  const params = new URLSearchParams({ provider: 'apple', state });
  const error = form.get('error');
  if (error) {
    params.set('error', error === 'access_denied' || error === 'user_cancelled_authorize' ? 'access_denied' : 'provider_rejected');
  } else {
    const token = form.get('id_token'), code = form.get('code');
    if (!token || token.length > 16384 || !code || code.length > 2048) return new Response('Missing credential', { status: 400 });
    params.set('id_token', token);
    params.set('code', code);
    // Apple sends the name only on the first authorization.
    const user = form.get('user');
    if (user && user.length <= 4096) {
      try {
        const parsed = JSON.parse(user);
        for (const field of ['firstName', 'lastName']) {
          if (typeof parsed?.name?.[field] === 'string') params.set(field, parsed.name[field].slice(0, 120));
        }
      } catch { /* optional name must not break login */ }
    }
  }
  return new Response(null, { status: 303, headers: {
    Location: 'https://pdd-drive.ru/app/#pdd-oauth=' + encodeURIComponent(params.toString()),
    'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
  } });
}
