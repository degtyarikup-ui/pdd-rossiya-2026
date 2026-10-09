#!/usr/bin/env python3
"""Локальный сервер для предпросмотра веб-версии Flutter приложения.
Слушает только 127.0.0.1:8080.
"""
import os
import sys
import mimetypes
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
WEB_DIR = os.path.join(REPO, "build", "web")
PORT = int(os.environ.get("WEB_PORT", "8080"))

mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("image/webp", ".webp")
mimetypes.add_type("application/json", ".json")

class FlutterWebHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_GET(self):
        if self.path in ('', '/'):
            self.send_response(302)
            self.send_header("Location", "/app/")
            self.end_headers()
            return
        super().do_GET()

    def do_POST(self):
        length = int(self.headers.get('content-length', 0))
        body = self.rfile.read(length).decode('utf-8', errors='ignore')
        sys.stderr.write(f"\n[BROWSER_LOG] {body}\n")
        sys.stderr.flush()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def log_message(self, format, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), format % args))
        sys.stderr.flush()

def main():
    if not os.path.isdir(WEB_DIR):
        print(f"Directory {WEB_DIR} does not exist. Run flutter build web first.", file=sys.stderr)
        sys.exit(1)

    ThreadingHTTPServer.allow_reuse_address = True
    server = ThreadingHTTPServer(("127.0.0.1", PORT), FlutterWebHandler)
    print(f"Flutter Web serving from {WEB_DIR} on http://127.0.0.1:{PORT}/")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
