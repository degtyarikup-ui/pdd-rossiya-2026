#!/usr/bin/env python3
"""Export reusable parking objects and an editable fuel station for the network editor.

Geometry comes from the actual ParkingLocations/ParkingLevels building blocks.
No external models, textures, Python packages or Blender are needed. Generated
GLBs use the same COLOR/UV2 texture contract as every other scenery prop.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import subprocess
import tempfile

from build_buildings import Mesh, ROOT
from build_environment import PropMesh

SCENERY = ROOT / 'game_godot/scenery'
TRANSPARENT = {'fuel_roof': 77 / 255, 'wash_roof': 89 / 255}
BUILDINGS = {'fuel_shop', 'garage_open', 'garage_closed', 'wash_bay'}


def material(key):
    kind = None
    if key.startswith('tex:'):
        _, kind, key, *_ = key.split(':')
    rgb = tuple(int(key[i:i+2], 16)/255 for i in (1, 3, 5))
    # Alpha is the city's tint/snow selector, not opacity. Roof transparency is
    # a separate material so opaque props still batch into their normal pool.
    return (*rgb, 0), kind


def rotated_box(mesh, item):
    box = item['box']
    x, z = box['c']
    w, d = box['half']
    y, h = item.get('y0', 0), item['h']
    color, kind = material(item['colour'])
    start = len(mesh.positions)
    mesh.box((0, y+h/2, 0), (w*2, h, d*2), color, kind, bottom=True)
    yaw = box.get('yaw', 0)
    c, s = math.cos(yaw), math.sin(yaw)
    for i in range(start, len(mesh.positions)):
        px, py, pz = mesh.positions[i]
        nx, ny, nz = mesh.normals[i]
        mesh.positions[i] = (x + c*px+s*pz, py, z-s*px+c*pz)
        mesh.normals[i] = (c*nx+s*nz, ny, -s*nx+c*nz)


def post(mesh, item):
    x, z = item['pos']
    y, h, radius = item.get('y0', 0), item['h'], item['r']
    top = item.get('r_top', radius)
    color, kind = material(item['colour'])
    sides, phase = item.get('sides', 12), item.get('phase', 0)
    rings = [[(x+r*math.cos(i*math.tau/sides+phase), yy, z+r*math.sin(i*math.tau/sides+phase))
              for i in range(sides)] for yy, r in [(y, radius), (y+h, top)]]
    for i in range(sides):
        j = (i+1) % sides
        mesh.face([rings[0][j], rings[0][i], rings[1][i], rings[1][j]], color, kind)
        if top > 0:
            mesh.face([(x, y+h, z), rings[1][j], rings[1][i]], color, kind)


def text_mesh(mesh, item):
    color, _ = material(item['colour'])
    points, indices = item['points'], item['indices']
    for i in range(0, len(indices), 3):
        triangle = [points[indices[i+j]] for j in (0, 2, 1)]
        a, b, c = triangle
        u, v = [b[k]-a[k] for k in range(3)], [c[k]-a[k] for k in range(3)]
        cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        if sum(n*n for n in cross) > 1e-18:
            mesh.face(triangle, color)


def opacity(path, alpha):
    """Set the ordinary glTF material too, so editor and game show the same roof."""
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20+length])
    doc_material = document['materials'][0]
    doc_material.update(alphaMode='BLEND', doubleSided=True)
    doc_material['pbrMetallicRoughness']['baseColorFactor'] = [1, 1, 1, alpha]
    json_data = json.dumps(document, separators=(',', ':')).encode()
    json_data += b' '*(-len(json_data) % 4)
    tail = data[20+length:]
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 20+len(json_data)+len(tail)) +
                     struct.pack('<II', len(json_data), 0x4e4f534a) + json_data + tail)


def build(source, output):
    index = json.loads((SCENERY/'index.json').read_text())
    target = output/'parking'
    target.mkdir(parents=True, exist_ok=True)
    catalog = {'version': 1, 'props': [], 'presets': source['presets']}
    for name, data in source['assets'].items():
        mesh = PropMesh(index['textures'])
        mesh.generator = 'PDD parking source primitives'
        for wall in data['walls']: rotated_box(mesh, wall)
        for cylinder in data['posts']: post(mesh, cylinder)
        for ground in data['ground']:
            key = ground['key']
            # Small object bases, not the station's road/pavement surfaces.
            color = {'concrete': '#8C9096'}.get(key, key)
            rotated_box(mesh, {'box': ground['box'], 'h': .002, 'y0': 0, 'colour': color})
        for label in data['text']: text_mesh(mesh, label)
        if name in TRANSPARENT:
            mesh.colors = [(*color[:3], 1) for color in mesh.colors]
        # The dispenser is authored standing on a .15 m island; as a standalone
        # prop its origin rests on the ground, like other catalogue furniture.
        if name == 'fuel_pump':
            mesh.positions = [(x, y-.15, z) for x, y, z in mesh.positions]
        path = target/f'{name}.glb'
        size = mesh.save(path)
        if name in TRANSPARENT: opacity(path, TRANSPARENT[name])
        prop_id = f'parking/{name}'
        metadata = {'size': size, 'title': data['title'], 'source': 'parking'}
        if name in TRANSPARENT: metadata['opacity'] = TRANSPARENT[name]
        if name in BUILDINGS: metadata['occluder'] = True
        index['props'][prop_id] = metadata
        catalog['props'].append({'id': prop_id, 'title': data['title']})
        print(f'{prop_id}: {len(mesh.indices)//3} triangles')
    for preset in catalog['presets']:
        points = [p for area in preset['areas'] for p in area['points']]
        for item in preset['decor']:
            size = index['props'][item['prop']]['size']
            x, z = item['pos']
            points.extend([[x-size[0]/2, z-size[2]/2], [x+size[0]/2, z+size[2]/2]])
        preset['bounds'] = [min(p[0] for p in points), min(p[1] for p in points),
                            max(p[0] for p in points), max(p[1] for p in points)]
        preset['previewProp'] = 'parking/fuel_canopy'
    (target/'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
    (output/'index.json').write_text(json.dumps(index, ensure_ascii=False, indent=1)+'\n')
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=SCENERY)
    parser.add_argument('--source', type=Path, help='Reuse a previously exported source JSON')
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    if args.source:
        build(json.loads(args.source.read_text()), args.output)
        return
    scratch = ROOT.parent/'scratch/editor-parking-assets'
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='export-', dir=scratch) as directory:
        source = Path(directory)/'source.json'
        result = subprocess.run([args.godot, '--headless', '--path', str(ROOT/'game_godot'),
                                 '--script', str(Path(__file__).with_name('parking_asset_source.gd')),
                                 '--', str(source)], capture_output=True, text=True, check=True)
        if 'ERROR:' in result.stdout + result.stderr:
            raise RuntimeError(result.stdout + result.stderr)
        build(json.loads(source.read_text()), args.output)


if __name__ == '__main__':
    main()
