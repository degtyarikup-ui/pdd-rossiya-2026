"""Local-only review app. Runtime uses Python standard library."""
import argparse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
from pathlib import Path
import secrets
import shutil
import sqlite3
from urllib.parse import urlsplit
import webbrowser

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'output/image-review'
UI = Path(__file__).with_name('index.html')
TOKEN = secrets.token_urlsafe(32)


def db():
    con = sqlite3.connect(DATA/'review.sqlite3', timeout=15)
    con.execute('CREATE TABLE IF NOT EXISTS reviews (key TEXT PRIMARY KEY, status TEXT NOT NULL, note TEXT NOT NULL)')
    return con


def state():
    with db() as con:
        return {k: dict(status=s, note=n) for k, s, n in con.execute('SELECT key,status,note FROM reviews')}


def export_selection(questions, destination):
    saved = state()
    selected = [q for q in questions if saved.get(q['key'], {}).get('status') == 'fix']
    if not selected:
        raise ValueError('Сначала отметьте картинки для исправления.')
    missing = [q['key'] for q in selected if not q.get('official') or not (DATA/'official'/q['official']['file']).is_file()]
    if missing:
        raise ValueError('Нет официального изображения для: '+', '.join(missing))
    folder = destination / ('ПДД АБ — оригиналы '+datetime.now().strftime('%Y-%m-%d %H-%M-%S-%f'))
    folder.mkdir(parents=True)
    report = []
    for q in selected:
        ref = q['official']
        name = f'Билет_{q["ticketNumber"]:02d}_Вопрос_{q["questionNumber"]:02d}'+Path(ref['file']).suffix
        shutil.copy2(DATA/'official'/ref['file'], folder/name)
        report.append(dict(key=q['key'], file=name, source=ref, note=saved[q['key']]['note']))
    (folder/'Источники.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    return dict(count=len(selected), path=str(folder))


class Handler(BaseHTTPRequestHandler):
    def send(self, body, kind='application/json; charset=utf-8', status=200):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.headers.get('Host') not in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}'):
            return self.send({'error': 'Invalid host'}, status=403)
        path = urlsplit(self.path).path
        if path == '/':
            return self.send(UI.read_text().replace('__TOKEN__', TOKEN), 'text/html; charset=utf-8')
        if path == '/api/data':
            return self.send(dict(self.server.manifest, reviews=state()))
        parts = path.strip('/').split('/')
        if len(parts) == 2 and parts[0] in ('official', 'ours'):
            allowed = self.server.images.get(path)
            if allowed and allowed.is_file():
                return self.send(allowed.read_bytes(), mimetypes.guess_type(allowed)[0] or 'application/octet-stream')
        self.send({'error': 'Not found'}, status=404)

    def do_POST(self):
        if self.headers.get('X-Review-Token') != TOKEN:
            return self.send({'error': 'Forbidden'}, status=403)
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size > 20000:
                raise ValueError('Слишком большой запрос')
            body = json.loads(self.rfile.read(size))
            if self.path == '/api/review':
                key, status, note = body['key'], body['status'], body.get('note', '')
                if key not in self.server.keys or status not in ('new', 'ok', 'fix') or not isinstance(note, str) or len(note) > 5000:
                    raise ValueError('Некорректная отметка')
                with db() as con:
                    con.execute('INSERT OR REPLACE INTO reviews VALUES (?,?,?)', (key, status, note))
                return self.send({'ok': True})
            if self.path == '/api/export':
                return self.send(export_selection(self.server.manifest['questions'], Path.home()/'Desktop'))
            return self.send({'error': 'Not found'}, status=404)
        except (ValueError, KeyError, OSError, sqlite3.Error) as exc:
            self.send({'error': str(exc)}, status=400)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8960)
    parser.add_argument('--open', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((DATA/'manifest.json').read_text())
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    server.manifest = manifest
    server.keys = {q['key'] for q in manifest['questions']}
    server.images = {}
    for q in manifest['questions']:
        server.images['/ours/'+q['image']+'.webp'] = ROOT/'assets/countries/ru/images/questions_ab'/(q['image']+'.webp')
        if q.get('official'):
            server.images['/official/'+q['official']['file']] = DATA/'official'/q['official']['file']
    print(f'http://127.0.0.1:{args.port}', flush=True)
    if args.open:
        webbrowser.open(f'http://127.0.0.1:{args.port}')
    server.serve_forever()

if __name__ == '__main__':
    main()
