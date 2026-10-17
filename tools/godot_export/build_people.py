#!/usr/bin/env python3
"""Build stylized blocky pedestrians (man, woman, child) and a three-piece officer.

One flat-shaded surface per mesh, no textures. Walker UV2 carries the
hip/shoulder swing, UV0 the knee; vertex alpha 1 marks clothes that take the
instance paint. `head()` is the older round head still used by vehicle drivers.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct

from build_buildings import Mesh, ROOT

MODELS = ROOT / 'game_godot/models'
SKINS = [(0.83,0.64,0.51,0), (0.88,0.70,0.58,0), (0.79,0.60,0.48,0)]
HAIR = [(0.20,0.15,0.11,0), (0.36,0.28,0.19,0), (0.57,0.48,0.32,0), (0.35,0.34,0.32,0)]
JACKET = (.92,.92,.92,1)
SHIRT = (.80,.80,.77,0)
NAVY = (.12,.17,.23,0)
SILVER = (.82,.86,.87,0)
VEST = (.65,.74,.22,0)
BLACK = (.10,.12,.14,0)
WHITE = (.86,.88,.87,0)
OFFICER_NAVY = (.07,.11,.19,0)
OFFICER_SILVER = (.96,.98,1.0,0)
OFFICER_VEST = (.86,1.0,.04,0)
OFFICER_BLACK = (.03,.04,.05,0)
OFFICER_WHITE = (1.0,1.0,1.0,0)
OFFICER_RED = (.85,.12,.12,0)



class PersonMesh(Mesh):
    generator = 'PDD lightweight people'

    def __init__(self, scale=1):
        super().__init__([])
        self.scale = scale
        self.swing = (0,0)
        self.knee = (0,0)

    def face(self, points, color, kind=None, uv=None):
        start = len(self.positions)
        points = [(x,y*self.scale,z) for x,y,z in points]
        super().face(points,color)
        count = len(points)
        self.uv2[start:] = [(self.swing[0],self.swing[1]*self.scale)]*count
        self.uv[start:] = [(max(0,min(1,(self.knee[1]*self.scale-p[1])/(.13*self.scale)))
                           if self.knee[0] else 0,self.knee[1]*self.scale) for p in points]

    def profile(self, rings, color, segments=8, caps=True, smooth=True):
        """Elliptical cross sections (y, x-radius, z-radius, centre-x, centre-z)."""
        points = [[(cx+rx*math.cos(i*math.tau/segments),y,
                    cz+rz*math.sin(i*math.tau/segments)) for i in range(segments)]
                  for y,rx,rz,cx,cz in rings]
        for row in range(len(rings)-1):
            for i in range(segments):
                j = (i+1)%segments
                before = len(self.positions)
                self.face([points[row][i],points[row+1][i],points[row+1][j],points[row][j]],color)
                if smooth:
                    # Analytic radial normals soften a low-sided silhouette without more faces.
                    normals = []
                    for r,corner in [(row,i),(row+1,i),(row+1,j),(row,j)]:
                        _,rx,rz,_,_ = rings[r]
                        dy = (rings[row+1][0]-rings[row][0])*self.scale
                        slope = ((rings[row][1]+rings[row][2])-(rings[row+1][1]+rings[row+1][2]))/(2*dy)
                        angle = corner*math.tau/segments
                        n = (math.cos(angle),slope,math.sin(angle)*rx/rz)
                        length = math.sqrt(sum(v*v for v in n))
                        normals.append(tuple(v/length for v in n))
                    self.normals[before:] = normals
        if caps:
            for i in range(1,segments-1):
                self.face([points[0][0],points[0][i],points[0][i+1]],color)
                self.face([points[-1][0],points[-1][i+1],points[-1][i]],color)

    def panel(self, x, y, z, w, h, color, back=False):
        pts = [(x-w/2,y-h/2,z),(x+w/2,y-h/2,z),
               (x+w/2,y+h/2,z),(x-w/2,y+h/2,z)]
        self.face(list(reversed(pts)) if back else pts,color)

    def save(self, path):
        # Smooth ring corners can share vertices between adjacent faces. Keep
        # colour and gait boundaries split, so clothes and joints never smear.
        attributes = [self.positions,self.normals,self.uv,self.colors,self.uv2]
        compact = [[] for _ in attributes]
        remap, known = [], {}
        for i in range(len(self.positions)):
            rows = [a[i] for a in attributes]
            flat = [v for row in rows for v in row]
            key = struct.pack('<'+'f'*len(flat),*flat)
            if key not in known:
                known[key] = len(compact[0])
                for output,row in zip(compact,rows): output.append(row)
            remap.append(known[key])
        self.positions,self.normals,self.uv,self.colors,self.uv2 = compact
        self.indices = [remap[i] for i in self.indices]
        return super().save(path)


def head(mesh, y, skin, hair, style=0, officer=False):
    mesh.profile([(y-.13,.078,.072,0,.006),(y-.035,.118,.096,0,.008),
                  (y+.08,.105,.092,0,.005),(y+.13,.07,.065,0,0)],skin,8)
    # Small eyes/brows and a tapered nose read naturally; no separate eyeballs/glints.
    for x in [-.046,.046]:
        mesh.panel(x,y+.003,.103,.026,.012,(.18,.19,.18,0))
        mesh.panel(x,y+.031,.100,.035,.010,hair)
        mesh.profile([(y-.045,.025,.030,x*2.5,-.002),
                      (y+.014,.025,.030,x*2.5,-.002)],skin,4)
    mesh.face([(-.018,y+.01,.104),(.018,y+.01,.104),(0,y-.045,.136)],skin)
    mesh.face([(.018,y+.01,.104),(.017,y-.049,.103),(0,y-.045,.136)],skin)
    mesh.face([(-.017,y-.049,.103),(-.018,y+.01,.104),(0,y-.045,.136)],skin)
    mesh.panel(0,y-.08,.088,.044,.009,(.43,.29,.25,0))
    if not officer:
        mesh.profile([(y+.065,.107,.094,0,0),(y+.15,.075,.072,0,-.006)],hair,8)
        if style == 1:  # bob, kept behind the cheek and neck
            mesh.profile([(y-.13,.111,.067,0,-.042),(y+.075,.108,.073,0,-.030)],hair,8)
            # Front cheek panel restores the face over the bob's front plane.
            mesh.panel(0,y-.035,.045,.125,.16,skin)
        elif style == 2:  # ponytail
            mesh.profile([(y-.15,.035,.040,0,-.11),(y+.06,.052,.046,0,-.105)],hair,6)
        elif style == 3:  # modest cap with shaped visor
            mesh.profile([(y+.09,.118,.101,0,0),(y+.18,.084,.083,0,-.005)],(.24,.31,.34,0),8)
            mesh.box((0,y+.092,.115),(.18,.024,.10),(.19,.24,.26,0),bottom=True)
    else:
        mesh.profile([(y+.105,.134,.111,0,0),(y+.165,.134,.111,0,0)],OFFICER_NAVY,10)
        mesh.profile([(y+.163,.149,.125,0,-.01),(y+.22,.132,.112,0,-.008)],OFFICER_NAVY,10)
        mesh.box((0,y+.109,.134),(.23,.022,.125),OFFICER_BLACK,bottom=True)
        mesh.panel(0,y+.144,.115,.038,.043,(.85,.68,.30,0))


# --- Stylized blocky people -------------------------------------------------
# Every figure is a handful of flat-shaded boxes: a cube head, a solid torso
# and limbs that start inside it, so a swing never opens a gap. Each limb is a
# rigid segment with one joint (hip/shoulder in UV2, knee in UV0): the vertex
# shader is the skeleton, with no bones, nodes or extra draw calls.

KINDS = ['man','woman','man','woman','child','man','woman','man','woman','child','man','woman']
SCALES = [1.0,.95,.97,.93,.70,1.02,.96,.99,.92,.66,.98,.94]
TROUSERS = [(.20,.25,.33,0),(.25,.26,.28,0),(.36,.31,.26,0),(.16,.18,.22,0)]
SKIRTS = [(.20,.22,.30,0),(.42,.20,.24,0),(.25,.30,.27,0),(.18,.18,.20,0)]
SHOES = [(.16,.17,.19,0),(.36,.27,.20,0),(.85,.86,.86,0)]
BAGS = [(.95,.73,.15,0),(.85,.25,.22,0),(.25,.62,.45,0)]
EYES = (.11,.12,.14,0)
CHEEK = (.93,.62,.58,0)
PAINT = (.92,.92,.92,1)
SLEEVE = (.84,.84,.84,1)


def frustum(mesh, y0, y1, w0, d0, w1, d1, color, cz=0):
    """Closed tapered box: (w0,d0) at y0, (w1,d1) at y1."""
    b = [(-w0/2,y0,cz+d0/2),(w0/2,y0,cz+d0/2),(w0/2,y0,cz-d0/2),(-w0/2,y0,cz-d0/2)]
    t = [(-w1/2,y1,cz+d1/2),(w1/2,y1,cz+d1/2),(w1/2,y1,cz-d1/2),(-w1/2,y1,cz-d1/2)]
    for i in range(4):
        j = (i+1)%4
        mesh.face([b[i],b[j],t[j],t[i]],color)
    mesh.face([t[0],t[1],t[2],t[3]],color)
    mesh.face([b[3],b[2],b[1],b[0]],color)


def block_head(mesh, s, neck, skin, hair, style, eyes=True):
    """Cube head on a short neck; hair is a cap plus an optional back block."""
    h = .25*s
    mesh.box((0,neck+.03*s,0),(.10*s,.07*s,.10*s),skin)
    cy = neck+.05*s+h/2
    mesh.box((0,cy,0),(.24*s,h,.235*s),skin,bottom=True)
    front = .1175*s+.002
    if eyes:
        for x in [-.052*s,.052*s]:
            mesh.panel(x,cy+.005*s,front,.034*s,.040*s,EYES)
        for x in [-.078*s,.078*s]:
            mesh.panel(x,cy-.045*s,front,.032*s,.018*s,CHEEK)
    top = cy+h/2
    if style is None:
        return top
    mesh.box((0,top+.012*s,-.004*s),(.255*s,.05*s,.25*s),hair)
    # Fringe: a thin band over the brow keeps the face open and readable.
    mesh.box((0,top-.025*s,.112*s),(.255*s,.035*s,.03*s),hair)
    if style == 'short':
        mesh.box((0,cy+.03*s,-.118*s),(.255*s,.17*s,.03*s),hair)
    elif style == 'long':
        mesh.box((0,cy-.06*s,-.125*s),(.27*s,.36*s,.05*s),hair)
        for x in [-.126*s,.126*s]:
            mesh.box((x,cy-.01*s,-.02*s),(.03*s,.24*s,.19*s),hair)
    elif style == 'bun':
        mesh.box((0,cy+.03*s,-.118*s),(.255*s,.17*s,.03*s),hair)
        mesh.box((0,top+.06*s,-.07*s),(.11*s,.09*s,.10*s),hair)
    elif style == 'cap':
        mesh.box((0,top+.025*s,0),(.265*s,.06*s,.26*s),(.85,.30,.22,0))
        mesh.box((0,top,.17*s),(.22*s,.02*s,.10*s),(.85,.30,.22,0),bottom=True)
    return top


def block_leg(mesh, s, x, hip, swing, trousers, shoe, bare=None):
    """Thigh from inside the pelvis to the knee, then shin + shoe on the knee."""
    knee = .47*s
    mesh.swing = (swing,hip)
    mesh.box((x,(hip+.03*s+knee-.02*s)/2,0),(.14*s,hip+.05*s-knee,.15*s),trousers)
    mesh.knee = (1 if swing else 0,knee if swing else 0)
    shin = bare or trousers
    mesh.box((x,(knee+.085*s)/2,0),(.125*s,knee-.085*s,.135*s),shin)
    mesh.box((x,.045*s,.03*s),(.14*s,.09*s,.25*s),shoe,bottom=True)
    mesh.knee = (0,0)
    mesh.swing = (0,0)


def block_arm(mesh, s, x, shoulder, swing, skin, top, sleeve=SLEEVE):
    mesh.swing = (swing,shoulder)
    mesh.box((x,shoulder-.20*s,0),(.105*s,.48*s,.12*s),sleeve)
    mesh.box((x,shoulder-.49*s,0),(.09*s,.11*s,.10*s),skin,bottom=True)
    mesh.swing = (0,0)


def pedestrian(mesh, variant):
    kind = KINDS[variant]
    s = SCALES[variant]
    skin = SKINS[variant%3]
    hair = HAIR[(variant*3+1)%4]
    shoe = SHOES[variant%3]
    hip = .90*s
    if kind == 'child':
        # Child proportions: shorter limbs, broader cube head, bright backpack.
        hip = .92*s
        trousers = TROUSERS[(variant//2)%4]
        for side in [-1,1]:
            block_leg(mesh,s,side*.09*s,hip,side*.30,trousers,shoe)
        mesh.box((0,hip+.03*s,0),(.32*s,.10*s,.21*s),trousers,bottom=True)
        shoulder = 1.36*s
        mesh.box((0,(hip+shoulder+.04*s)/2,0),(.38*s,shoulder+.04*s-hip,.22*s),PAINT)
        for side in [-1,1]:
            block_arm(mesh,s,side*.245*s,shoulder,-side*.20,skin,PAINT)
        mesh.box((0,shoulder-.17*s,-.165*s),(.30*s,.34*s,.12*s),BAGS[variant%3])
        block_head(mesh,s*1.42,shoulder+.03*s,skin,hair,'cap' if variant == 9 else 'short')
        return
    if kind == 'woman':
        shoulder = 1.40*s
        legs = TROUSERS[variant%4]
        skirt = SKIRTS[(variant//2)%4]
        for side in [-1,1]:
            block_leg(mesh,s,side*.085*s,hip,side*.23,legs,shoe,
                      bare=skin if variant in (3,8) else None)
        # The flared skirt clears the thighs at full stride.
        frustum(mesh,.58*s,hip+.08*s,.42*s,.34*s,.34*s,.22*s,skirt)
        frustum(mesh,hip+.06*s,shoulder+.04*s,.32*s,.20*s,.38*s,.22*s,PAINT)
        for side in [-1,1]:
            block_arm(mesh,s,side*.235*s,shoulder,-side*.17,skin,PAINT)
        if variant == 6:
            mesh.box((.31*s,.98*s,0),(.06*s,.20*s,.16*s),BAGS[1])
        block_head(mesh,s*1.15,shoulder+.04*s,skin,hair,'bun' if variant in (6,11) else 'long')
        return
    shoulder = 1.38*s
    trousers = TROUSERS[variant%4]
    for side in [-1,1]:
        block_leg(mesh,s,side*.10*s,hip,side*.29,trousers,shoe)
    mesh.box((0,hip+.03*s,0),(.36*s,.12*s,.23*s),trousers,bottom=True)
    frustum(mesh,hip+.08*s,shoulder+.05*s,.38*s,.23*s,.46*s,.25*s,PAINT)
    # Collar and zip on the jacket front take the instance paint too.
    mesh.panel(0,(hip+shoulder)/2+.08*s,.126*s,.02*s,.40*s,(.70,.70,.70,1))
    for side in [-1,1]:
        block_arm(mesh,s,side*.285*s,shoulder,-side*.18,skin,PAINT)
    if variant == 2:
        mesh.box((0,shoulder-.20*s,-.17*s),(.32*s,.38*s,.12*s),(.28,.31,.34,0))
    style = 'short' if variant not in (7,) else None
    top = block_head(mesh,s*1.15,shoulder+.03*s,skin,hair,style)
    if style is None:  # bald: just a short dark stubble cap
        mesh.box((0,top-.02*s*1.15,-.03*s*1.15),(.245*s*1.15,.05*s*1.15,.19*s*1.15),HAIR[3])


def officer_body(mesh):
    s = 1.04
    hip = .97
    for side in [-1,1]:
        x = side*.115
        block_leg(mesh,s,x,hip,0,OFFICER_NAVY,OFFICER_BLACK)
        # Red DPS stripe along the outer side of each trouser leg.
        mesh.box((x+side*.075,.52,0),(.012,.80,.03),OFFICER_RED)
    mesh.box((0,hip+.03,0),(.40,.12,.24),OFFICER_NAVY,bottom=True)
    top = 1.53
    frustum(mesh,hip+.06,top,.42,.25,.50,.26,OFFICER_NAVY)
    # Hi-vis vest over the jacket with two retroreflective bands.
    frustum(mesh,hip+.10,top-.07,.445,.275,.515,.285,OFFICER_VEST)
    for y in [1.17,1.33]:
        frustum(mesh,y,y+.05,.47,.282,.49,.286,OFFICER_SILVER)
    for x in [-.26,.26]:
        mesh.box((x,top-.02,0),(.09,.03,.17),OFFICER_SILVER)
    head_top = block_head(mesh,s*1.12,top-.02,SKINS[1],None,None)
    # Peaked cap: navy crown, black visor, gold badge.
    mesh.box((0,head_top+.04,0),(.29,.08,.28),OFFICER_NAVY,bottom=True)
    mesh.box((0,head_top+.095,-.01),(.31,.035,.30),OFFICER_NAVY)
    mesh.box((0,head_top+.005,.17),(.26,.022,.11),OFFICER_BLACK,bottom=True)
    mesh.panel(0,head_top+.05,.141,.045,.05,(.85,.68,.30,0))


def officer_arm(mesh, right=False):
    # Coordinates relative to the shoulder pivot (0,0,0); the arm hangs to -Y.
    mesh.box((0,-.22,0),(.12,.56,.13),OFFICER_NAVY)
    mesh.box((0,-.44,0),(.128,.05,.138),OFFICER_SILVER)
    mesh.box((0,-.56,0),(.10,.14,.11),OFFICER_WHITE,bottom=True)
    if right:
        for i in range(4):
            y = -.60-.11*i
            mesh.box((0,y-.055,.02),(.045,.11,.045),OFFICER_WHITE if i%2 else OFFICER_BLACK,
                     bottom=(i == 3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=MODELS)
    args = parser.parse_args()
    index = json.loads((MODELS/'index.json').read_text())
    for variant in range(len(KINDS)):
        mesh = PersonMesh()
        pedestrian(mesh,variant)
        name = f'walkers/walker_{variant}'
        path = args.output/(name+'.glb')
        path.parent.mkdir(parents=True,exist_ok=True)
        mesh.save(path)
        entry = index[name]
        entry['after'] = {'meshes':1,'tris':len(mesh.indices)//3}
        entry['source'] = 'tools/godot_export/build_people.py'
        print(f'{name}: {len(mesh.positions)} vertices, {len(mesh.indices)//3} triangles')
    for part in ['body','left_arm','right_arm']:
        mesh = PersonMesh()
        if part == 'body': officer_body(mesh)
        else: officer_arm(mesh,part == 'right_arm')
        path = args.output/'people'/f'officer_{part}.glb'
        path.parent.mkdir(parents=True,exist_ok=True)
        mesh.save(path)
        name = 'people/officer_'+part
        index[name] = {'after':{'meshes':1,'tris':len(mesh.indices)//3},'source':'tools/godot_export/build_people.py'}
        print(f'{name}: {len(mesh.positions)} vertices, {len(mesh.indices)//3} triangles')
    (args.output/'index.json').write_text(json.dumps(index,ensure_ascii=False,indent=1)+'\n')


if __name__ == '__main__':
    main()
