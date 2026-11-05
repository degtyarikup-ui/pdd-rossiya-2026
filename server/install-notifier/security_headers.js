export async function secureResponse(request, response) {
  const headers = new Headers(response.headers), url = new URL(request.url);
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  if (url.protocol === 'https:') headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  let body = response.body;
  if ((headers.get('content-type') || '').includes('text/html') && url.pathname.startsWith('/admin')) {
    const nonce = [...crypto.getRandomValues(new Uint8Array(24))].map(b => b.toString(16).padStart(2, '0')).join('');
    body = (await response.text()).replace(/<script\b/gi, '<script nonce="' + nonce + '"');
    // Legacy feature views still use inline click attributes. Scripts themselves
    // require a fresh nonce; attributes are explicitly isolated in script-src-attr.
    headers.set('Content-Security-Policy', [
      "default-src 'none'", "script-src 'nonce-" + nonce + "' 'strict-dynamic'",
      "script-src-attr 'unsafe-inline'", "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
      "font-src 'self' data: https://fonts.gstatic.com", "img-src 'self' data: blob: https:",
      "connect-src 'self'", "media-src 'self' blob:", "frame-ancestors 'none'",
      "object-src 'none'", "base-uri 'none'", "form-action 'self'"
    ].join('; '));
    headers.set('X-Frame-Options', 'DENY');
    headers.set('Cache-Control', 'no-store');
    headers.delete('Content-Length');
  }
  if (url.pathname.startsWith('/api/') && !headers.has('Cache-Control')) headers.set('Cache-Control', 'no-store');
  return new Response(body, { status: response.status, statusText: response.statusText, headers });
}
