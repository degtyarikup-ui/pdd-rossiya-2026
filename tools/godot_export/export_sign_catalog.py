#!/usr/bin/env python3
"""Copy the app's complete vector sign catalogue into the self-contained Godot/editor assets.

Game faces drop the app's black catalogue outline (sign_outline.py), and catalog.json records the
silhouette each face is clipped to. After exporting, import Godot, run build_sign_faces.gd, and
import again to apply face scales.
--check validates the generated SVGs and searchable metadata without writing anything.
"""
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import sign_outline

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


def game_face(code, data):
    """The face drawn in the game and the silhouette (shape, corner radius) the shader cuts it with."""
    # Plates keep their black frame, as on the road; the striped 8.22 posts have none.
    plate = code.startswith('8.') and not code.startswith('8.22.')
    try:
        svg = sign_outline.game_svg(data.decode('utf-8'), plate)
    except ValueError as error:
        raise ValueError(f'{code}: {error}') from None
    return svg.encode('utf-8'), sign_outline.silhouette(svg)


def expected():
    files, catalog, sources = {}, {}, {}
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
            sources[code] = data
            catalog[code] = {'title':sign['title'], 'group':group, 'folkName':sign.get('folkName', ''),
                             'source':str(source.relative_to(ROOT)), 'sourceSha256':hashlib.sha256(original).hexdigest()}
            if code in PANELS:
                catalog[code]['panel'] = PANELS[code]
    with ProcessPoolExecutor() as pool:
        faces = dict(zip(sources, pool.map(game_face, sources, sources.values())))
    for code, (data, face) in faces.items():
        files[f'{code}.svg'] = data
        catalog[code]['sha256'] = hashlib.sha256(data).hexdigest()
        catalog[code]['face'] = face
    # 5.33 also needs the plain panel used by the ticket: the original catalogue
    # drawing includes the 8.5.1 time restriction, which must not be baked into every placement.
    ET.register_namespace('', 'http://www.w3.org/2000/svg')
    root = ET.fromstring(sources['5.33'])
    root.set('height', '120')
    root.set('viewBox', '0 0 100 120')
    group = list(root)[0]
    original = list(group)
    assert original[0].tag.endswith('rect') and original[1].tag.endswith('path')
    original[0].set('height', '109.248')
    original[0].set('stroke', '#000')
    original[0].set('stroke-width', '1.5')
    group.remove(original[1])
    for element in list(group):
        if element.get('fill') == 'red': group.remove(element)
    files['5.33_plain.svg'] = ET.tostring(root, encoding='utf-8') + b'\n'
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
