#!/usr/bin/env python3
"""Version entry scripts so a fresh HTML page cannot load an older HTTP cache."""
import hashlib
import re
import sys
from pathlib import Path


def version_build(directory: Path) -> str:
    main_hash = hashlib.sha256((directory / 'main.dart.js').read_bytes()).hexdigest()[:16]
    bootstrap_path = directory / 'flutter_bootstrap.js'
    bootstrap = bootstrap_path.read_text()
    bootstrap, count = re.subn(
        r'"mainJsPath":"main\.dart\.js(?:\?release=[a-f0-9]+)?"',
        f'"mainJsPath":"main.dart.js?release={main_hash}"',
        bootstrap,
    )
    if count != 1:
        raise ValueError('Expected one dart2js entry point in Flutter bootstrap')
    bootstrap_path.write_text(bootstrap)
    bootstrap_hash = hashlib.sha256(bootstrap.encode()).hexdigest()[:16]
    index_path = directory / 'index.html'
    index, count = re.subn(
        r'src="flutter_bootstrap\.js(?:\?release=[a-f0-9]+)?"',
        f'src="flutter_bootstrap.js?release={bootstrap_hash}"',
        index_path.read_text(),
    )
    if count != 1:
        raise ValueError('Expected one Flutter bootstrap script in index.html')
    index_path.write_text(index)
    return main_hash


if __name__ == '__main__':
    print('Versioned web entry scripts:', version_build(Path(sys.argv[1])))
