#!/usr/bin/env python3
"""Audit explicit country asset paths in APK/AAB/IPA or an unpacked web build.

Inspects standalone and nested Godot PCKs plus scene country metadata.
Unlabelled resources still require the source ownership registry.
Reports uncompressed sizes; these are not store download/install sizes.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import zipfile
try:
    from .pck import inspect as inspect_pck
except ImportError:
    from pck import inspect as inspect_pck


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



def inspect_artifact(artifact, country, game_only=False):
    artifact = Path(artifact)
    if artifact.suffix == '.pck':
        with artifact.open('rb') as stream:
            pack = inspect_pck(stream, country)
        return {'country': country, 'ok': not pack['errors'], 'packs': [pack],
                'uncompressed_bytes': artifact.stat().st_size,
                'container_bytes': artifact.stat().st_size, 'errors': pack['errors']}
    report = audit(inventory(artifact), country)
    if game_only:
        if not artifact.is_dir() or not (artifact / 'project.binary').is_file():
            raise ValueError('Loose game assets must contain project.binary')
        report['ok'] = not report['foreign_assets']
    report['container_bytes'] = artifact.stat().st_size if artifact.is_file() else None
    report['store_download_bytes'] = None
    report['scope'] = 'Country paths, scene metadata and PCK directory/content; unlabelled assets use source ownership policy.'
    report['packs'] = []
    errors = []
    archive = zipfile.ZipFile(artifact) if artifact.is_file() else None
    try:
        for name, size in inventory(artifact):
            if not (name.endswith('.pck') or name.endswith('/scene.json')):
                continue
            if name.endswith('.pck'):
                # PCK needs seeks. Copy a nested pack to a bounded-memory temporary file.
                import tempfile
                import shutil
                if archive:
                    with archive.open(name) as source, tempfile.TemporaryFile() as stream:
                        shutil.copyfileobj(source, stream)
                        pack = inspect_pck(stream, country)
                else:
                    with (artifact / name).open('rb') as stream:
                        pack = inspect_pck(stream, country)
                report['packs'].append(dict(path=name, **pack))
                errors.extend(pack['errors'])
            else:
                if size > 16 * 1024 * 1024:
                    raise ValueError(f'Scene JSON unexpectedly large: {name}')
                data = archive.read(name) if archive else (artifact / name).read_bytes()
                scene = json.loads(data)
                if scene.get('country', country) != country:
                    errors.append(f'Foreign scene country: {name}: {scene.get("country")}')
    finally:
        if archive:
            archive.close()
    report['errors'] = errors
    report['ok'] = report['ok'] and not errors
    return report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--country', required=True)
    parser.add_argument('--game-only', action='store_true')
    parser.add_argument('--profile', help='Explicit comparable build profile for size budget')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z]{2}', args.country):
        parser.error('country must be a two-letter lowercase code')
    try:
        result = inspect_artifact(args.artifact, args.country, args.game_only)
        if args.profile:
            budgets = json.loads(Path(__file__).with_name('size_budgets.json').read_text())
            budget = budgets['profiles'][args.profile]
            if budget['country'] != args.country:
                raise ValueError('Size profile country mismatch')
            result['size_profile'] = args.profile
            result['size_limit_bytes'] = budget['max_uncompressed_bytes']
            result['size_ok'] = result['uncompressed_bytes'] <= budget['max_uncompressed_bytes']
            result['ok'] = result['ok'] and result['size_ok']
    except (OSError, zipfile.BadZipFile, ValueError, KeyError) as error:
        parser.exit(2, f'Cannot inspect artifact: {error}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
