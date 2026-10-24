#!/usr/bin/env python3
"""Copy the app's complete vector sign catalogue into the self-contained Godot/editor assets.

After exporting, import Godot, run build_sign_faces.gd, and import again to apply face scales.
--check validates the generated SVGs and searchable metadata without writing anything.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/countries/ru/questions/signs.json'
OUTPUT = ROOT / 'game_godot/signs'
# Source sheets contain several complete examples. A placed sign must show one panel.
PANELS = {
    **{f'2.3.{i + 2}': [(i % 2) * 100, (i // 2) * 116, 100, 116] for i in range(6)},
    '5.15.2':[11, 11, 80, 80], '5.15.3':[14, 11, 80, 80],
    '5.15.4':[14, 12, 80, 80], '5.15.7':[28, 19, 142, 72],
}


def panel_svg(data, region):
    svg = data.decode('utf-8')
    match = re.search(r'<svg\b[^>]*>', svg)
    tag = re.sub(r'\s+(?:width|height|viewBox)\s*=\s*["\'][^"\']*["\']', '', match[0])
    x, y, w, h = region
    tag = tag[:-1] + f' width="{w}" height="{h}" viewBox="{x} {y} {w} {h}">'
    return (svg[:match.start()] + tag + svg[match.end():]).encode('utf-8')


def expected():
    files, catalog = {}, {}
    for group, signs in json.loads(SOURCE.read_text(encoding='utf-8')).items():
        for code, sign in signs.items():
            source = ROOT / 'assets/countries/ru' / sign['image'].removeprefix('./')
            if source.suffix != '.svg' or not source.is_file():
                raise ValueError(f'{code}: missing vector source {source}')
            original = source.read_bytes()
            data = panel_svg(original, PANELS[code]) if code in PANELS else original
            data = re.sub(rb'[ \t]+\r?$', b'', data, flags=re.MULTILINE)
            if data.endswith((b'\n\n', b'\r\n\r\n')):
                data = data.rstrip(b'\r\n') + b'\n'
            files[f'{code}.svg'] = data
            catalog[code] = {'title':sign['title'], 'group':group, 'folkName':sign.get('folkName', ''),
                             'source':str(source.relative_to(ROOT)), 'sourceSha256':hashlib.sha256(original).hexdigest(),
                             'sha256':hashlib.sha256(data).hexdigest()}
            if code in PANELS:
                catalog[code]['panel'] = PANELS[code]
    files['catalog.json'] = (json.dumps(catalog, ensure_ascii=False, indent=2) + '\n').encode()
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    files = expected()
    mismatches = []
    for name, data in files.items():
        target = OUTPUT / name
        if target.is_file() and target.read_bytes() == data:
            continue
        mismatches.append(name)
        if not args.check:
            OUTPUT.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    if args.check and mismatches:
        raise SystemExit('Sign catalogue is out of date: ' + ', '.join(mismatches))
    print(f'Sign catalogue: {len(files) - 1} vectors; {len(mismatches)} updated' if not args.check
          else 'Sign catalogue: all vectors and searchable metadata match the app')


if __name__ == '__main__':
    main()
