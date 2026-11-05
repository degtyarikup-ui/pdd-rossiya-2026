import http.client
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from tools.local_http_security import LocalOnlyHandler


class Handler(LocalOnlyHandler, BaseHTTPRequestHandler):
    writes = 0
    def log_message(self, *args):
        pass
    def do_GET(self):
        self._local_reply(200, b"editor")
    def do_POST(self):
        type(self).writes += 1
        self._local_reply(200, b'{"ok":true}')


class LocalSecurityTest(unittest.TestCase):
    def setUp(self):
        Handler.writes = 0
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path="/", method="GET", headers=None, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port)
        conn.request(method, path, body, headers or {})
        response = conn.getresponse()
        result = response.status, response.read()
        conn.close()
        return result

    def test_foreign_host_origin_and_unsigned_write_rejected(self):
        self.assertEqual(self.request(headers={"Host": "attacker.invalid"})[0], 403)
        self.assertEqual(self.request(headers={"Origin": "https://attacker.invalid"})[0], 403)
        self.assertEqual(self.request("/api/deploy", "POST", {"Content-Type": "text/plain"}, "{}")[0], 403)
        self.assertEqual(Handler.writes, 0)

    def test_same_origin_token_allows_json_and_binary_upload(self):
        status, body = self.request("/api/local-session")
        self.assertEqual(status, 200)
        token = json.loads(body)["token"]
        headers = {"X-Local-Token": token, "Origin": "http://127.0.0.1:%d" % self.port}
        self.assertEqual(self.request("/api/articles", "POST", {**headers, "Content-Type": "application/json"}, "{}")[0], 200)
        self.assertEqual(self.request("/api/upload", "POST", {**headers, "Content-Type": "image/png"}, b"image")[0], 200)
        self.assertEqual(self.request("/api/deploy", "POST", {**headers, "Origin": "https://attacker.invalid"}, "{}")[0], 403)
        self.assertEqual(Handler.writes, 2)

    def test_dns_rebinding_cannot_obtain_token(self):
        self.assertEqual(self.request("/api/local-session", headers={"Host": "evil.invalid:%d" % self.port})[0], 403)
        self.assertEqual(self.request("/local-security.js", headers={"Sec-Fetch-Site": "cross-site"})[0], 403)


if __name__ == "__main__":
    unittest.main()
