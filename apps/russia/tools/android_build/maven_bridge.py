"""Per-build localhost bridge; remote files always come from official HTTPS Google Maven."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import threading
import time

from download import metadata, download, file_sha256

UPSTREAM = 'https://dl.google.com/dl/android/maven2'


class Bridge(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, cache):
        self.cache = Path(cache)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.guard = threading.Lock()
        self.locks = {}
        self.metadata_cache = {}
        self.metadata_locks = {}
        self.slots = threading.BoundedSemaphore(8)
        super().__init__(('127.0.0.1', 0), Handler)

    def upstream_metadata(self, url):
        with self.guard:
            lock = self.metadata_locks.setdefault(url, threading.Lock())
        with lock:
            if url not in self.metadata_cache:
                saved = self.cache / ('head-' + hashlib.sha256(url.encode()).hexdigest() + '.json')
                try:
                    cached = json.loads(saved.read_text())
                    if (0 <= time.time() - cached['time'] < 3600 and cached['status'] == 200
                            and isinstance(cached['headers'], dict)
                            and int(cached['headers'].get('content-length', -1)) >= 0):
                        self.metadata_cache[url] = cached['status'], cached['headers']
                except (OSError, ValueError, KeyError, TypeError):
                    pass
            if url not in self.metadata_cache:
                self.metadata_cache[url] = metadata(url, self.cache)
                status, headers = self.metadata_cache[url]
                if status == 200:
                    saved.write_text(json.dumps({'time': time.time(), 'status': status, 'headers': headers}))
            return self.metadata_cache[url]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.serve(False)

    def do_GET(self):
        self.serve(True)

    def serve(self, body):
        if not self.path.startswith('/') or self.path.startswith('//') or '?' in self.path:
            self.send_error(400)
            return
        url = UPSTREAM + self.path
        try:
            with self.server.slots:
                status, headers = self.server.upstream_metadata(url)
                if status == 404:
                    self.send_error(404)
                    return
                size = int(headers['content-length'])
                identity = json.dumps([url, size, headers.get('etag'), headers.get('last-modified')])
                path = self.server.cache / hashlib.sha256(identity.encode()).hexdigest()
                checksum = path.with_suffix('.sha256')
                if body:
                    with self.server.guard:
                        lock = self.server.locks.setdefault(str(path), threading.Lock())
                    with lock:
                        valid = (path.exists() and path.stat().st_size == size and checksum.exists()
                                 and file_sha256(path) == checksum.read_text())
                        if not valid:
                            download(url, path, size, workers=4)
                            checksum.write_text(file_sha256(path))
                self.send_response(200)
                self.send_header('Content-Length', str(size))
                self.send_header('Content-Type', headers.get('content-type', 'application/octet-stream'))
                if headers.get('last-modified'):
                    self.send_header('Last-Modified', headers['last-modified'])
                self.end_headers()
                if body:
                    with path.open('rb') as stream:
                        shutil.copyfileobj(stream, self.wfile)
        except (BrokenPipeError, ConnectionResetError):
            # Gradle can cancel speculative HEAD requests when another repository wins.
            return
        except Exception as exc:
            print(f'Google Maven: {self.path}: {exc}', flush=True)
            try:
                self.send_error(502, 'Official upstream download failed')
            except (BrokenPipeError, ConnectionResetError):
                pass
