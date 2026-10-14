#!/usr/bin/env python3
"""Rebuild the game's lightweight houses with one indexed, vertex-coloured surface.

No Blender/additional packages required. Facades use the existing scenery detail
array; COLOR alpha retains the instance-tint / winter-roof contract. All geometry
stays inside the original plots. See docs/game/building-models.md.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
SCENERY = ROOT / 'game_godot/scenery'
# Explicit authoring dimensions, independent of generated bounds in index.json.
HOMES = [(6, 6, 1), (7, 7, 1), (8, 6.5, 1),
         (6.5, 7, 2), (7.5, 7.5, 2), (8, 6, 2)]
BLOCKS = [(10, 10.5, 8), (11, 13.5, 9), (12, 16.5, 10),
          (13, 10.5, 9), (10.5, 16.5, 8.5), (12.5, 13.5, 10),
          (11.5, 19.5, 11), (13, 22.5, 10)]
TOWERS = [(14, 28.5, 11), (15, 34.5, 11), (16, 40.5, 11), (13.5, 46.5, 11)]
WALL = (0.95, 0.95, 0.95, 1.0)
TRIM = (0.78, 0.79, 0.78, 0.0)
PLINTH = (0.40, 0.43, 0.45, 0.0)
GLASS = (0.56, 0.66, 0.74, 0.0)
ROOF = (0.29, 0.33, 0.36, 0.5)


class Mesh:
    def __init__(self, textures):
        self.textures = textures
        self.positions, self.normals, self.uv, self.colors, self.uv2 = [], [], [], [], []
        self.indices = []

    def face(self, points, color, kind=None, uv=None):
        """Flat triangle/quad, CCW outward; shared corners within each face."""
        a, b, c = points[:3]
        u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
        n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        length = math.sqrt(sum(x*x for x in n))
        normal = tuple(x/length for x in n)
        layer = next((i+1 for i, t in enumerate(self.textures) if t['kind'] == kind), 0)
        vertical = 1.0 if abs(normal[1]) < 0.5 else 0.0
        if uv is None:
            params = self.textures[layer-1] if layer else {}
            su = params.get('u') or params.get('period') or 4
            sv = params.get('v') or params.get('period') or 4
            uv = [((p[2] if abs(normal[0]) > 0.5 else p[0])/su,
                   (p[1] if vertical else p[2])/sv) for p in points]
        start = len(self.positions)
        self.positions.extend(points)
        self.normals.extend([normal]*len(points))
        self.uv.extend(uv)
        self.colors.extend([color]*len(points))
        self.uv2.extend([(layer, vertical if kind not in ('window', 'door') else 0)]*len(points))
        self.indices.extend([start, start+1, start+2])
        if len(points) == 4:
            self.indices.extend([start, start+2, start+3])

    def box(self, center, size, color, kind=None, bottom=False):
        x,y,z = center
        w,h,d = (s/2 for s in size)
        self.face([(x-w,y-h,z+d),(x+w,y-h,z+d),(x+w,y+h,z+d),(x-w,y+h,z+d)], color, kind)
        self.face([(x+w,y-h,z-d),(x-w,y-h,z-d),(x-w,y+h,z-d),(x+w,y+h,z-d)], color, kind)
        self.face([(x+w,y-h,z+d),(x+w,y-h,z-d),(x+w,y+h,z-d),(x+w,y+h,z+d)], color, kind)
        self.face([(x-w,y-h,z-d),(x-w,y-h,z+d),(x-w,y+h,z+d),(x-w,y+h,z-d)], color, kind)
        self.face([(x-w,y+h,z+d),(x+w,y+h,z+d),(x+w,y+h,z-d),(x-w,y+h,z-d)], color, kind)
        if bottom:
            self.face([(x-w,y-h,z-d),(x+w,y-h,z-d),(x+w,y-h,z+d),(x-w,y-h,z+d)], color, kind)

    def wall_quad(self, side, offset, horizontal, y, w, h, color, kind=None):
        """A feature on any of the four walls, in facade metres."""
        points = [(horizontal-w/2,y-h/2),(horizontal+w/2,y-h/2),
                  (horizontal+w/2,y+h/2),(horizontal-w/2,y+h/2)]
        if side == 0: world = [(offset,yy,-xx) for xx,yy in points]  # +X
        elif side == 1: world = [(-offset,yy,xx) for xx,yy in points]  # -X
        elif side == 2: world = [(xx,yy,offset) for xx,yy in points]  # +Z
        else: world = [(-xx,yy,-offset) for xx,yy in points]  # -Z
        self.face(world,color,kind,[(0,0),(1,0),(1,1),(0,1)])

    def save(self, path):
        binary = bytearray()
        views, accessors = [], []
        attributes = {}
        arrays = [('POSITION',self.positions,3),('NORMAL',self.normals,3),
                  ('TEXCOORD_0',self.uv,2),('COLOR_0',self.colors,4),('TEXCOORD_1',self.uv2,2)]
        for name, values, count in arrays:
            offset = len(binary)
            for row in values:
                binary.extend(struct.pack('<'+'f'*count,*row))
            views.append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset,'target':34962})
            accessor = {'bufferView':len(views)-1,'componentType':5126,'count':len(values),'type':f'VEC{count}'}
            if name == 'POSITION':
                accessor['min'] = [min(p[i] for p in values) for i in range(3)]
                accessor['max'] = [max(p[i] for p in values) for i in range(3)]
            attributes[name] = len(accessors)
            accessors.append(accessor)
        offset = len(binary)
        binary.extend(struct.pack('<'+'H'*len(self.indices),*self.indices))
        views.append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset,'target':34963})
        accessors.append({'bufferView':len(views)-1,'componentType':5123,'count':len(self.indices),'type':'SCALAR'})
        binary.extend(b'\0'*(-len(binary)%4))
        document = {'asset':{'version':'2.0','generator':'PDD lightweight buildings'},
                    'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':path.stem,'mesh':0}],
                    'meshes':[{'primitives':[{'attributes':attributes,'indices':len(accessors)-1,'material':0,'mode':4}]}],
                    'materials':[{'name':'scenery','pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':1}}],
                    'buffers':[{'byteLength':len(binary)}],'bufferViews':views,'accessors':accessors}
        data = json.dumps(document,separators=(',',':')).encode()
        data += b' '*(-len(data)%4)
        path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(data)+len(binary))+
                         struct.pack('<II',len(data),0x4e4f534a)+data+
                         struct.pack('<II',len(binary),0x004e4942)+binary)
        return [round(accessors[0]['max'][i]-accessors[0]['min'][i],6) for i in range(3)]


def window(mesh, side, offset, x, y, w, h, seed):
    # Frame, reveal and glass are baked into one opaque textured quad.
    shade = [0.89,1.0,0.94,1.05][seed % 4]
    color = tuple(v*shade for v in GLASS[:3])+(0,)
    mesh.wall_quad(side,offset+.095,x,y,w,h,color,'window')


def entrance(mesh, side, offset, y=.35, compact=False):
    mesh.wall_quad(side,offset+.065,0,y+1.1,1.25,2.2,TRIM)
    mesh.wall_quad(side,offset+.10,0,y+1.05,1.02,2.1,(.23,.29,.32,0),'door')
    mesh.wall_quad(side,offset+.135,0,y+1.55,.66,.55,GLASS,'window')
    # Small canopy and a solid step: only two boxes, merged into the facade mesh.
    reach = .19 if compact else .43
    x = (offset+reach/2)*(1 if side == 0 else -1)
    mesh.box((x,y+2.36,0),(reach,.12,1.7),ROOF,'metal',bottom=True)
    mesh.box((x,y/2,0),(reach,y,1.6),PLINTH)


def house(mesh, variant, w, d, floors):
    h = 3.35 if floors == 1 else 6.25
    wall_kind = 'brick' if variant in (1,4) else 'plaster'
    mesh.box((0,h/2,0),(w,h,d),WALL,wall_kind)
    mesh.box((0,.23,0),(w+.08,.46,d+.08),PLINTH,'plaster')
    # Eaves and ridge make a hipped roof rather than a square pyramid.
    mesh.box((0,h+.07,0),(w+.9,.14,d+.9),TRIM,'wood',bottom=True)
    rw,rd = w/2+.45,d/2+.45
    peak = h + 1.75
    ridge = d*.23
    roof_color = [(.36,.24,.20,.5),(.30,.33,.35,.5),(.38,.28,.23,.5)][variant % 3]
    mesh.face([(-rw,h+.14,rd),(rw,h+.14,rd),(0,peak,ridge)],roof_color,'roofTile')
    mesh.face([(rw,h+.14,-rd),(-rw,h+.14,-rd),(0,peak,-ridge)],roof_color,'roofTile')
    mesh.face([(rw,h+.14,rd),(rw,h+.14,-rd),(0,peak,-ridge),(0,peak,ridge)],roof_color,'roofTile')
    mesh.face([(-rw,h+.14,-rd),(-rw,h+.14,rd),(0,peak,ridge),(0,peak,-ridge)],roof_color,'roofTile')
    mesh.box((-w*.22,peak-.18,-d*.17),(.48,1.35,.58),(.52,.44,.37,0),'brick')
    mesh.box((-w*.22,peak+.52,-d*.17),(.62,.12,.72),ROOF,'metal')
    for side in range(4):
        span,offset = (d,w/2) if side < 2 else (w,d/2)
        cols = 3 if span >= 7 else 2
        for floor in range(floors):
            y = .55+(floor+.5)*(h-.55)/floors
            for col in range(cols):
                x = (col-(cols-1)/2)*(span/(cols+.25))
                # Leave a real entrance bay instead of putting a door over a window.
                if side < 2 and floor == 0 and abs(x) < .7:
                    continue
                window(mesh,side,offset,x,y,1.18,1.48,variant+col+floor*3+side)
        if side < 2:
            entrance(mesh,side,offset)
    if floors == 2:
        mesh.box((0,3.18,0),(w+.10,.12,d+.10),TRIM)


def apartment(mesh, variant, w, h, d, tower):
    floors = round(h/3)
    pitch = (h-.45)/floors
    kind = 'brick' if variant % 3 == 2 else 'panel'
    mesh.box((0,h/2,0),(w,h,d),WALL,kind)
    mesh.box((0,.32,0),(w+.10,.64,d+.10),PLINTH,'plaster')
    mesh.box((0,h+.08,0),(w+.40,.16,d+.40),ROOF,'roofFlat')
    # Actual parapet and small service cabin, never a second roof-sized slab.
    for x in (-w/2,w/2):
        mesh.box((x,h+.24,0),(.16,.32,d+.24),TRIM)
    for z in (-d/2,d/2):
        mesh.box((0,h+.24,z),(w,.32,.16),TRIM)
    cabin_h = .95 if variant % 2 == 0 else .55
    mesh.box((w*.16,h+cabin_h/2,-d*.16),(2.2,cabin_h,2.0),PLINTH,'plaster')
    mesh.box((w*.16,h+cabin_h+.06,-d*.16),(2.36,.12,2.16),ROOF,'roofFlat')
    for side in range(4):
        span,offset = (d,w/2) if side < 2 else (w,d/2)
        cols = max(3,round(span/2.65))
        spacing = span/(cols+.5)
        # One quiet vertical accent per entrance wall; no extra materials.
        if side < 2:
            mesh.wall_quad(side,offset+.065,0,h/2,1.7,h-.64,(.78,.80,.81,1))
        for floor in range(floors):
            y = .45+(floor+.5)*pitch
            for col in range(cols):
                x = (col-(cols-1)/2)*spacing
                if side < 2 and floor == 0 and abs(x) < 1.3:
                    continue
                window(mesh,side,offset,x,y,1.25 if tower else 1.35,1.55,variant+floor*7+col+side*3)
            # Panel joints are planar colour strips: no subdivided wall or decals.
            if kind == 'panel' and floor > 0:
                mesh.wall_quad(side,offset+.032,0,.45+floor*pitch,span,.035,(.81,.82,.81,1))
        if side < 2:
            entrance(mesh,side,offset,compact=True)
            # Two narrow loggia stacks on a few variants, inside the existing plot.
            if variant % 2 == 1:
                for floor in range(1,floors):
                    y = .45+floor*pitch
                    z = spacing*(cols-1)/2
                    bx = (offset+.09)*(1 if side == 0 else -1)
                    mesh.box((bx,y+.45,z),(.18,.9,1.85),(.64,.67,.68,1))
    # No glass transparency, interiors, per-window nodes or dynamic lights.


def window_detail(path):
    """Neutral, mipmapped detail encoding consumed by the existing scenery shader.

    The R/B value multiplies vertex colour; it is NOT an albedo image. Painted
    frame, asymmetric mullion and a subdued reflection cost no extra geometry.
    """
    size = 256
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            frame = x < 13 or x >= 243 or y < 13 or y >= 243 or 157 <= x < 166
            if min(x,y,255-x,255-y) < 4:
                value = .25
            elif frame:
                value = .80 if y > 18 else .66
            else:
                value = .35 + .05*(1-y/size)
                if 30 < x-y*.47 < 57:
                    value += .065
                if x < 19 or y > 236:
                    value *= .78  # baked inner reveal
            v = round(value*255)
            rows.extend((v,128,v,255))
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+
                     chunk(b'IDAT',zlib.compress(bytes(rows),9))+chunk(b'IEND',b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=SCENERY)
    args = parser.parse_args()
    index = json.loads((SCENERY/'index.json').read_text())
    dest = args.output/'buildings'
    dest.mkdir(parents=True,exist_ok=True)
    for group, entries in [('home',HOMES),('block',BLOCKS),('tower',TOWERS)]:
        for variant, dimensions in enumerate(entries):
            name = f'{group}_{variant}'
            mesh = Mesh(index['textures'])
            if group == 'home':
                house(mesh,variant,*dimensions)
                index['props'][f'buildings/{name}']['footprint'][1] = 3.35 if dimensions[2] == 1 else 6.25
            else:
                apartment(mesh,variant,*dimensions,group == 'tower')
            bounds = mesh.save(dest/f'{name}.glb')
            index['props'][f'buildings/{name}']['size'] = bounds
            print(f'{name}: {len(mesh.indices)//3} triangles, {len(mesh.positions)} vertices')
    (args.output/'index.json').write_text(json.dumps(index,ensure_ascii=False,indent=1)+'\n')
    texture = ROOT/'game_godot/textures/detail/window.png' if args.output == SCENERY else args.output/'window.png'
    window_detail(texture)


if __name__ == '__main__':
    main()
