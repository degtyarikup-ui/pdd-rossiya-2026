#!/usr/bin/env python3
"""Audit explicit country asset paths in APK/AAB/IPA or an unpacked web build.

Does not inspect opaque Godot packs or infer the country of unlabelled assets.
Reports uncompressed sizes; these are not store download/install sizes.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import zipfile


def inventory(artifact):
    artifact = Path(artifact)
    if artifact.is_dir():
        return [(p.relative_to(artifact).as_posix(), p.stat().st_size)
                for p in artifact.rglob('*') if p.is_file()]
    with zipfile.ZipFile(artifact) as archive:
        return [(p.filename, p.file_size) for p in archive.infolist()
                if not p.is_dir()]


def audit(entries, country):
    found = set()
    foreign = []
    for name, _ in entries:
        parts = PurePosixPath(name).parts
        for i in range(len(parts) - 2):
            if parts[i:i + 2] == ('assets', 'countries'):
                code = parts[i + 2]
                found.add(code)
                if code != country:
                    foreign.append(name)
    return {
        'country': country,
        'countries_found': sorted(found),
        'foreign_assets': sorted(foreign),
        'ok': country in found and not foreign,
        'files': len(entries),
        'uncompressed_bytes': sum(size for _, size in entries),
        'largest_files': [{'path': name, 'bytes': size} for name, size in
                          sorted(entries, key=lambda item: (-item[1], item[0]))[:20]],
        'scope': 'Explicit assets/countries paths only; opaque packs require a separate audit.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--country', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z]{2}', args.country):
        parser.error('country must be a two-letter lowercase code')
    try:
        result = audit(inventory(args.artifact), args.country)
    except (OSError, zipfile.BadZipFile) as error:
        parser.exit(2, f'Cannot inspect artifact: {error}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
