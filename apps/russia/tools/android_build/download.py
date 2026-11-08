"""Official HTTPS downloads in bounded ranges when ordinary transfers hang."""
import concurrent.futures
import hashlib
from pathlib import Path
import subprocess
import tempfile

CHUNK = 64 * 1024


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda: stream.read(CHUNK), b''):
            digest.update(data)
    return digest.hexdigest()


def curl(url, directory, *, head=False, start=None, end=None):
    with tempfile.TemporaryDirectory(dir=directory) as tmp:
        headers, body = Path(tmp) / 'headers', Path(tmp) / 'body'
        args = ['curl', '-sS', '--connect-timeout', '10', '--max-time', '20',
                '-D', str(headers), '-o', str(body)]
        if head:
            args.append('-I')
        if start is not None:
            args += ['-r', f'{start}-{end}']
        result = subprocess.run(args + [url], capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError(f'curl: {result.stderr.decode(errors="replace").strip()}')
        # curl can emit a proxy CONNECT header before the actual response.
        blocks = headers.read_text().replace('\r\n', '\n').strip().split('\n\n')
        lines = blocks[-1].splitlines()
        status = int(lines[0].split()[1])
        meta = {k.lower(): v.strip() for line in lines[1:] if ':' in line
                for k, v in [line.split(':', 1)]}
        return status, meta, body.read_bytes()


def metadata(url, directory):
    status, headers, _ = curl(url, directory, head=True)
    if status not in (200, 404):
        raise RuntimeError(f'HTTP {status}: {url}')
    return status, headers


def download(url, destination, size, *, sha1=None, workers=8):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    size = int(size)
    if size < 0:
        raise ValueError('Negative download size')

    def part(start):
        end = min(start + CHUNK - 1, size - 1)
        last = None
        for _ in range(3):
            try:
                status, headers, data = curl(url, destination.parent, start=start, end=end)
                expected = f'bytes {start}-{end}/{size}'
                if status == 206 and headers.get('content-range') != expected:
                    raise RuntimeError(f'Unexpected Content-Range: {headers.get("content-range")}')
                if status != 206 and not (status == 200 and start == 0 and size <= CHUNK):
                    raise RuntimeError(f'Range download returned HTTP {status}')
                if len(data) != end - start + 1:
                    raise RuntimeError('Incomplete range download')
                return data
            except (RuntimeError, subprocess.TimeoutExpired) as exc:
                last = exc
        raise RuntimeError(f'Cannot download {url} bytes {start}-{end}: {last}')

    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as out:
        temporary = Path(out.name)
        digest = hashlib.sha1()
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
                # Batches bound memory even for large Android SDK archives.
                for batch in range(0, size, CHUNK * workers):
                    for data in pool.map(part, range(batch, min(size, batch + CHUNK * workers), CHUNK)):
                        digest.update(data)
                        out.write(data)
            out.flush()
            if sha1 and digest.hexdigest() != sha1.lower():
                raise RuntimeError('Archive checksum mismatch')
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def fetch(url, destination):
    status, headers = metadata(url, Path(destination).parent)
    if status != 200:
        raise RuntimeError(f'HTTP {status}: {url}')
    download(url, destination, headers['content-length'])
    return headers
