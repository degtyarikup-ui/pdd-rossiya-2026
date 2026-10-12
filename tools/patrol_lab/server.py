#!/usr/bin/env python3
"""Локальный сервер для тестового стенда игры «Найди нарушителя».
Запуск: ./scripts/patrol_lab.sh или python3 tools/patrol_lab/server.py
Слушает только 127.0.0.1:8960.
"""
import os
import sys
import mimetypes
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PATROL_LAB_PORT", "8960"))

mimetypes.add_type("text/html", ".html")
mimetypes.add_type("text/css", ".css")
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("image/svg+xml", ".svg")
mimetypes.add_type("application/json", ".json")

class PatrolLabHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HERE, **kwargs)

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[PATROL_LAB] %s\n" % (fmt % args))
        sys.stderr.flush()

def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), PatrolLabHandler)
    url = f"http://127.0.0.1:{PORT}/"
    print("=" * 60)
    print(f"🚦 Тестовый стенд игры «Найди нарушителя» запущен!")
    print(f"🌐 Откройте в браузере: {url}")
    print(f"🛑 Для остановки нажмите: Ctrl+C")
    print("=" * 60)
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nСервер остановлен.")

if __name__ == "__main__":
    main()
