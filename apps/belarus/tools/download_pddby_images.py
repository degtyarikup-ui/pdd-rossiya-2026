#!/usr/bin/env python3
"""Download only image URLs observed by collect_pddby.py, into ignored local storage."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import re
import sys
import time
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from collect_pddby import atomic_json, requests


MAX_IMAGE_BYTES = 20 * 1024 * 1024


def download_image(url, session=None):
    """Image GETs are read-only and may safely retry a broken connection."""
    for attempt in range(3):
        try:
            headers = {'User-Agent': 'PDD-Belarus-content-review/1.0'}
            if session is None:
                with urlopen(Request(url, headers=headers), timeout=25) as r:
                    content_type = r.headers.get_content_type()
                    data = r.read(MAX_IMAGE_BYTES + 1)
            else:
                with session.get(url, headers=headers, timeout=(15, 25), stream=True) as r:
                    r.raise_for_status()
                    content_type = r.headers.get('Content-Type', '').split(';')[0].strip()
                    chunks = []
                    size = 0
                    for chunk in r.iter_content(65536):
                        size += len(chunk)
                        if size > MAX_IMAGE_BYTES:
                            raise ValueError('Invalid image size')
                        chunks.append(chunk)
                    data = b''.join(chunks)
            if not content_type.startswith('image/'):
                raise ValueError('Image URL returned non-image content')
            if not data or len(data) > MAX_IMAGE_BYTES:
                raise ValueError('Invalid image size')
            return data
        except Exception as error:
            retryable = isinstance(error, (TimeoutError, ConnectionError)) or (isinstance(error, URLError) and not isinstance(error, HTTPError)) or (requests is not None and isinstance(error, (requests.exceptions.ConnectionError, requests.exceptions.Timeout)))
            if not retryable or attempt == 2:
                raise
            print(json.dumps({'imageNetworkRetry': attempt + 1}), flush=True)
            time.sleep(10 * (attempt + 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    folder = args.source.resolve()
    if not any(p in ('scratch', 'output') for p in folder.parts):
        parser.error('Use ignored scratch/ or output/ for publisher material')
    bank = json.loads((folder / 'collected.json').read_text())
    urls = sorted({u for q in bank['questions'].values() for u in q['imageUrls']})
    media_path = folder / 'media.json'
    media = json.loads(media_path.read_text()) if media_path.exists() else {}
    images = folder / 'images'
    images.mkdir(exist_ok=True)
    session = requests.Session() if requests is not None else None
    for index, url in enumerate(urls):
        parsed = urlparse(url)
        if parsed.scheme != 'https' or parsed.hostname != 'pdd.by' or not parsed.path.startswith('/img/tickets/'):
            raise ValueError('Unexpected source image location')
        suffix = Path(parsed.path).suffix.lower()
        if suffix not in ('.jpg', '.jpeg', '.png', '.webp', '.gif'):
            raise ValueError('Unsupported image format')
        existing = media.get(url)
        if existing:
            local = folder / existing['path']
            if local.is_file() and hashlib.sha256(local.read_bytes()).hexdigest() == existing['sha256']:
                continue
        time.sleep(0.35)
        data = download_image(url, session)
        digest = hashlib.sha256(data).hexdigest()
        local = images / (digest + suffix)
        local.write_bytes(data)
        if sys.platform == 'darwin':
            result = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(local)], capture_output=True, text=True, check=True)
            dimensions = re.findall(r'pixel(?:Width|Height): (\d+)', result.stdout)
            if len(dimensions) != 2 or any(int(n) <= 0 for n in dimensions):
                raise ValueError('Image decoder rejected file')
        media[url] = {'path': str(local.relative_to(folder)), 'sha256': digest, 'bytes': len(data)}
        atomic_json(media_path, media)
        print(json.dumps({'downloaded': index + 1, 'total': len(urls), 'bytes': len(data)}), flush=True)
    print(json.dumps({'verifiedImages': len(urls), 'completeForObservedQuestions': True}), flush=True)


if __name__ == '__main__':
    main()
