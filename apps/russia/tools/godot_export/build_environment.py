#!/usr/bin/env python3
"""Indexed street props with the original local bounds, pivots and texture contract.

Only replaces existing GLBs. Never edits the scenery index or location data.
Python standard library; one opaque surface per prop, no leaf cards or lights.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from build_buildings import Mesh, ROOT

SCENERY = ROOT / 'game_godot/scenery'
# Authoring envelope of the archived models. Off-centre bounds are intentional:
# a lamp's arm points toward -X, the fence faces +X, the bush pivot is at its centre.
BOUNDS = {
    'trees/round_0': ((-1.5, 0, -1.2), (1.6, 4.05, 1.2)),
    'trees/birch_0': ((-.8, 0, -.75), (.87, 4.865, .75)),
    'trees/pine_0': ((-1.4, 0, -1.4), (1.4, 4.45, 1.4)),
    'street/bush': ((-.76, -.55, -.55), (.8, .55, .55)),
    'street/fence_12': ((-.05, 0, -6.05), (.16, 1, 6.05)),
    'street/fence_14': ((-.05, 0, -7.05), (.16, 1, 7)),
    'street/lamp': ((-1.5, 0, -.17), (.17, 5.2, .17)),
    **{f'street/kiosk_{i}': ((-1.4, 0, -1), (1.4, 2.4, 1.795906782)) for i in range(3)},
}
BARK = (.34, .27, .20, 0)
METAL = (.52, .57, .60, 0)
DARK = (.22, .27, .30, 0)
SNOW = (.29, .56, .30, .5)


class PropMesh(Mesh):
    generator = 'PDD lightweight environment'

    def stem(self, a, b, radius, tip, color, kind='bark', sides=6):
        axis = [b[i]-a[i] for i in range(3)]
        length = math.sqrt(sum(x*x for x in axis))
        axis = [x/length for x in axis]
        helper = (1, 0, 0) if abs(axis[1]) > .9 else (0, 1, 0)
        u = [axis[1]*helper[2]-axis[2]*helper[1], axis[2]*helper[0]-axis[0]*helper[2], axis[0]*helper[1]-axis[1]*helper[0]]
        norm = math.sqrt(sum(x*x for x in u))
        u = [x/norm for x in u]
        v = [axis[1]*u[2]-axis[2]*u[1], axis[2]*u[0]-axis[0]*u[2], axis[0]*u[1]-axis[1]*u[0]]
        rings = [[tuple(p[j]+r*(math.cos(i*math.tau/sides)*u[j]+math.sin(i*math.tau/sides)*v[j]) for j in range(3)) for i in range(sides)] for p, r in [(a, radius), (b, tip)]]
        for i in range(sides):
            j = (i+1) % sides
            self.face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], color, kind)
        for ring, reverse in [(rings[0], True), (rings[1], False)]:
            pts = list(reversed(ring)) if reverse else ring
            for i in range(1, sides-1): self.face([pts[0], pts[i], pts[i+1]], color, kind)

    def crown(self, center, size, seed=0, snow=False, sides=8):
        """Closed broad foliage masses; irregular silhouette, no individual leaves."""
        x, y, z = center
        rx, ry, rz = [s/2 for s in size]
        rings = []
        for row, (height, radius) in enumerate([(-.78, .56), (-.20, 1), (.42, .88), (.80, .50)]):
            ring = []
            for i in range(sides):
                angle = i*math.tau/sides
                wobble = 1 + .07*math.sin(i*2.3 + seed*1.7 + row*.5)
                ring.append((x+rx*radius*wobble*math.cos(angle), y+ry*height, z+rz*radius*wobble*math.sin(angle)))
            rings.append(ring)
        for row in range(len(rings)-1):
            for i in range(sides):
                j = (i+1) % sides
                shade = .80 + .16*((i+seed) % 4)/3
                color = (shade, shade, shade, 1)
                if snow and row == 2 and i % 3 == 0: color = SNOW
                self.face([rings[row][j], rings[row][i], rings[row+1][i], rings[row+1][j]], color, 'leaves')
        for ring, tip, reverse in [(rings[0], (x,y-ry,z), False), (rings[-1], (x,y+ry,z), True)]:
            for i in range(sides):
                pts = [ring[i], ring[(i+1) % sides], tip]
                self.face(list(reversed(pts)) if reverse else pts, SNOW if snow and reverse else (.92,.92,.92,1), 'leaves')

    def fit_envelope(self, bounds, foliage_only=False):
        # Preserve the old min AND max, not merely its size or a re-centred pivot.
        lo, hi = [list(v) for v in bounds]
        slots = [i for i,c in enumerate(self.colors) if not foliage_only or c[3]>.25]
        points = [self.positions[i] for i in slots]
        minimum = [min(p[i] for p in points) for i in range(3)]
        maximum = [max(p[i] for p in points) for i in range(3)]
        # Tree trunks stay rooted at exactly (0,0,0); only reshape the crown.
        if foliage_only: lo[1] = minimum[1]
        scale = [(hi[i]-lo[i])/(maximum[i]-minimum[i]) for i in range(3)]
        for i in slots:
            p = self.positions[i]
            self.positions[i] = tuple(lo[j]+(p[j]-minimum[j])*scale[j] for j in range(3))
            normal = self.normals[i]
            n = [normal[j]/scale[j] for j in range(3)]
            length = math.sqrt(sum(x*x for x in n))
            self.normals[i] = tuple(x/length for x in n)


def tree(m, kind):
    if kind == 'round':
        m.stem((0,0,0), (0,2.85,0), .16, .075, BARK)
        for tip in [(-.65,2.7,.12), (.65,2.9,-.22), (.1,3.3,.45)]:
            m.stem((.02,1.8,0), tip, .07, .035, BARK)
        for i, (pos, size) in enumerate([((-.55,2.8,.05),(1.9,2.0,2.15)), ((.65,3.04,-.1),(1.9,2.02,2.2)), ((.12,3.48,.05),(1.9,1.14,1.7))]):
            m.crown(pos,size,i)
    elif kind == 'birch':
        white = (.81,.83,.78,0)
        m.stem((0,0,0), (0,3.9,0), .085, .025, white)
        for tip in [(-.43,3.35,.08), (.42,3.73,-.12)]: m.stem((.03,2.3,0),tip,.04,.018,white)
        # Three broad bark marks; no repeated tiny spots, branch/leaf geometry.
        for y in [.65,1.3,1.95]:
            m.box((.005,y,0),(.15,.10,.13),(.27,.30,.28,0))
        for i, (pos,size) in enumerate([((-.28,3.19,.03),(1.12,1.9,1.4)),((.32,3.83,-.02),(1.1,2.07,1.5)),((.02,4.30,0),(.88,1.13,1.02))]):
            m.crown(pos,size,i+4)
    else:
        m.stem((0,0,0),(0,3.7,0),.14,.035,BARK)
        for tier, (bottom, radius, height) in enumerate([(.65,1.4,1.75),(1.65,1.08,1.6),(2.6,.76,1.3),(3.35,.49,1.1)]):
            # Two rings and a tip give each tier a broad overhang and tapered shoulder.
            rings=[]
            for y, r in [(bottom,radius*.80),(bottom+.14,radius),(bottom+height*.55,radius*.42)]:
                rings.append([(r*math.cos(i*math.tau/8),y,r*math.sin(i*math.tau/8)) for i in range(8)])
            for row in range(2):
                for i in range(8):
                    j=(i+1)%8
                    shade = .80 + .12 * ((i + tier * 2) % 4) / 3.0
                    color = (shade, shade, shade, 1)
                    m.face([rings[row][j],rings[row][i],rings[row+1][i],rings[row+1][j]],color,'leaves')
            for i in range(8):
                j=(i+1)%8
                shade_top = .86 + .06 * (i % 2)
                m.face([rings[-1][j],rings[-1][i],(0,bottom+height,0)],(shade_top, shade_top, shade_top, 1),'leaves')
                m.face([rings[0][i],rings[0][j],(0,bottom,0)],(.72,.72,.72,1),'leaves')


def bush(m):
    # Two well-proportioned smooth 8-sided crowns (2*64 = 128 tris <= 150) forming a lush natural shrub.
    for i,(pos,size) in enumerate([((-.22,-.02,0),(.92,.98,.90)),((.20,.04,.02),(.98,1.08,1.02))]):
        m.crown(pos,size,i+7,sides=8)


def fence(m, length):
    # Preserve the original faces/pole line. Broad rails remain readable on a phone.
    lo, hi = BOUNDS[f'street/fence_{length}']
    span = hi[2]-lo[2]
    count = 7 if length == 12 else 8
    for i in range(count):
        z = lo[2]+.05 + i*(span-.10)/(count-1)
        m.box((0,.49,z),(.10,.98,.10),DARK,'metal')
        m.box((0,.98,z),(.10,.04,.10),METAL,'metal')
    for y in [.28,.76]:
        m.box((.12,y,(hi[2]+lo[2])/2),(.08,.10,span-.10),METAL,'metal')
    # One upright per bay, not dozens of thin pickets and diagonal wires.
    for i in range(count-1):
        z = lo[2]+.05 + (i+.5)*(span-.10)/(count-1)
        m.box((.12,.52,z),(.08,.66,.075),METAL,'metal')


def lamp(m):
    m.box((0,.14,0),(.34,.28,.34),(.43,.47,.49,0),'metal')
    m.stem((0,.28,0),(0,4.77,0),.105,.052,METAL,'metal',8)
    m.stem((0,4.69,0),(-.40,5.13,0),.055,.05,METAL,'metal')
    m.stem((-.40,5.13,0),(-1.12,5.13,0),.05,.045,METAL,'metal')
    m.box((-1.20,5.12,0),(.60,.16,.28),DARK,'metal')
    # Opaque diffuser underneath; no real light, halo or transparent glass.
    m.box((-1.23,5.025,0),(.46,.035,.20),(.88,.87,.75,0))


def kiosk(m, variant):
    paint = [(.59,.67,.70,1),(.73,.66,.54,1),(.57,.66,.58,1)][variant]
    m.box((0,1.09,0),(2.66,2.18,1.9),paint,'plaster')
    m.box((0,.13,0),(2.74,.26,2.0),DARK,'metal')
    m.box((0,2.30,0),(2.8,.20,2),(.36,.42,.44,.5),'roofFlat')
    # Preserve the original front canopy reach (+Z), without shifting the body.
    reach = BOUNDS['street/kiosk_0'][1][2]
    m.face([(-1.4,2.16,reach),(1.4,2.16,reach),(1.4,2.36,.90),(-1.4,2.36,.90)],(.43,.49,.50,.5),'metal')
    m.box((0,2.13,reach-.035),(2.8,.10,.07),DARK,'metal')
    glass=(.31,.42,.48,0)
    m.wall_quad(2,.958,0,1.32,1.75,1.12,DARK)
    m.wall_quad(2,.966,0,1.33,1.60,.97,glass,'window')
    m.box((0,.77,1.08),(1.85,.09,.25),METAL,'metal')
    m.box((0,1.30,.979),(.055,1.0,.025),METAL)
    m.wall_quad(0,1.338,-.02,1.1,.84,1.88,DARK)
    m.wall_quad(0,1.346,-.02,1.42,.65,1.02,glass,'window')
    m.wall_quad(1,1.338,0,1.38,1.20,.90,glass,'window')
    m.box((1.36,.91,.27),(.025,.055,.15),METAL)


def build(output):
    index = json.loads((SCENERY/'index.json').read_text())
    totals = [0,0,0]
    for prop, bounds in BOUNDS.items():
        m = PropMesh(index['textures'])
        if prop.startswith('trees/'): tree(m,prop.split('/')[1].split('_')[0])
        elif prop == 'street/bush': bush(m)
        elif 'fence_' in prop: fence(m,int(prop.rsplit('_',1)[1]))
        elif prop == 'street/lamp': lamp(m)
        else: kiosk(m,int(prop.rsplit('_',1)[1]))
        m.fit_envelope(bounds,prop.startswith('trees/'))
        target = output / (prop+'.glb')
        target.parent.mkdir(parents=True,exist_ok=True)
        m.save(target)
        v,t,b = len(m.positions),len(m.indices)//3,target.stat().st_size
        totals = [totals[0]+v,totals[1]+t,totals[2]+b]
        print(f'{prop}: {v} vertices, {t} triangles, {b} bytes')
    print(f'Total: {totals[0]} vertices, {totals[1]} triangles, {totals[2]} bytes')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=SCENERY)
    build(parser.parse_args().output)
