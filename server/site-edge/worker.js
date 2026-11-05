// pdd-drive.app is the public site. GitHub Pages remains the static origin and
// the legacy .ru site, preserving browser storage and old OAuth/payment returns.
const HOSTS = new Set(['pdd-drive.app', 'www.pdd-drive.app', 'app.pdd-drive.app']);
const ORIGIN = 'https://pdd-drive.ru';
export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (!HOSTS.has(url.hostname)) return new Response('Not found', { status: 404 });
    if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    if (url.hostname !== 'pdd-drive.app' || url.protocol !== 'https:') {
      if (url.hostname === 'app.pdd-drive.app' && !url.pathname.startsWith('/app/')) url.pathname = '/app' + url.pathname;
      url.hostname = 'pdd-drive.app'; url.protocol = 'https:'; url.port = '';
      return new Response(null, { status: 308, headers: { Location: url.href, 'Strict-Transport-Security': 'max-age=31536000; includeSubDomains' } });
    }
    // Never send browser cookies, authorization or arbitrary proxy headers to
    // GitHub Pages. The origin is fixed and cannot be selected by the caller.
    const originUrl = new URL(ORIGIN);
    originUrl.pathname = url.pathname; originUrl.search = url.search;
    const originHeaders = new Headers();
    for (const name of ['accept', 'accept-encoding', 'if-none-match', 'if-modified-since', 'range', 'if-range']) {
      if (request.headers.has(name)) originHeaders.set(name, request.headers.get(name));
    }
    const upstream = await fetch(new Request(originUrl, { method: request.method, headers: originHeaders, redirect: 'manual' }));
    const headers = new Headers(upstream.headers);
    headers.delete('set-cookie');
    headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    headers.set('X-Content-Type-Options', 'nosniff');
    headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
    headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    headers.set('X-Frame-Options', 'SAMEORIGIN');
    if (headers.has('location')) {
      const target = new URL(headers.get('location'), originUrl);
      if (target.origin === ORIGIN) { target.hostname = 'pdd-drive.app'; headers.set('Location', target.href); }
    }
    let body = upstream.body;
    if ((headers.get('content-type') || '').includes('text/html')) headers.set('Content-Security-Policy', "object-src 'none'; base-uri 'self'; frame-ancestors 'self'");
    if (request.method !== 'HEAD' && (headers.get('content-type') || '').includes('text/html')) {
      body = await upstream.text();
      const policy = body.match(/<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]+)"/i)?.[1];
      const decode = value => value.replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
      headers.set('Content-Security-Policy', (policy ? decode(policy) + '; ' : "object-src 'none'; base-uri 'self'; ") + "frame-ancestors 'self'");
      headers.delete('Content-Length');
    }
    return new Response(body, { status: upstream.status, statusText: upstream.statusText, headers });
  },
};
