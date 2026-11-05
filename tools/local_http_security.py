"""Loopback editor boundary shared by blog and road editors."""
import hmac
import json
import secrets
from urllib.parse import urlsplit

_TOKEN = secrets.token_urlsafe(32)
_BOOTSTRAP = b"""(function(){var original=window.fetch.bind(window),pending;
window.fetch=async function(input,init){
 var u=new URL(typeof input==='string'?input:input.url,location.href);
 var method=((init&&init.method)||(input&&input.method)||'GET').toUpperCase();
 if(u.origin===location.origin&&!['GET','HEAD','OPTIONS'].includes(method)){
  pending=pending||original('/api/local-session',{cache:'no-store'}).then(function(r){if(!r.ok)throw Error('Local session unavailable');return r.json()});
  var token=(await pending).token;init=Object.assign({},init||{});
  var headers=new Headers(init.headers||(input&&input.headers));headers.set('X-Local-Token',token);init.headers=headers;
 }
 return original(input,init);
}})();"""


class LocalOnlyHandler:
    """Mixin before BaseHTTPRequestHandler. Reject before any route executes."""
    def _local_reply(self, code, body, content_type="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def parse_request(self):
        if not super().parse_request():
            return False
        port = self.server.server_address[1]
        hosts = {"127.0.0.1:%d" % port, "localhost:%d" % port, "[::1]:%d" % port}
        host = self.headers.get("Host", "")
        allowed = {"http://" + h for h in hosts}
        origin = self.headers.get("Origin")
        if host not in hosts or (origin and origin not in allowed) or self.headers.get("Sec-Fetch-Site") == "cross-site":
            self._local_reply(403, b'{"error":"local origin required"}')
            return False
        path = urlsplit(self.path).path
        if self.command in ("GET", "HEAD") and path in ("/api/local-session", "/local-security.js"):
            if path == "/api/local-session":
                self._local_reply(200, json.dumps({"token": _TOKEN}).encode())
            else:
                self._local_reply(200, _BOOTSTRAP, "application/javascript; charset=utf-8")
            return False
        if self.command not in ("GET", "HEAD", "OPTIONS"):
            if not hmac.compare_digest(self.headers.get("X-Local-Token", ""), _TOKEN):
                self._local_reply(403, b'{"error":"local token required"}')
                return False
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                size = -1
            if size < 0 or size > 16 * 1024 * 1024 or self.headers.get("Transfer-Encoding"):
                self._local_reply(413, b'{"error":"request too large"}')
                return False
        return True
