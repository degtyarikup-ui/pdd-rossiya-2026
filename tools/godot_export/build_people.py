#!/usr/bin/env python3
"""Build indexed, vertex-coloured pedestrians and a three-piece traffic officer.

One surface per mesh, no textures, bones or runtime primitive tessellation.
Walker UV2 carries hip/shoulder swing; UV0 carries the lower-leg knee pivot.
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


def shoes(mesh, x, swing=0, hip=.91, knee=.45, officer=False):
    mesh.swing = (swing,hip)
    mesh.knee = (1 if swing else 0,knee if swing else 0)
    col = OFFICER_BLACK if officer else (.22,.24,.25,0)
    mesh.profile([(0,.071,.137,x,.034),(.06,.076,.140,x,.034),
                  (.115,.065,.110,x,.020)],col,6)
    mesh.knee = (0,0)


def legs(mesh, color, hip=.91, officer=False):
    for side in [-1,1]:
        x = side*(.13 if officer else .105)
        swing = 0 if officer else side*.29
        mesh.swing = (swing,hip)
        mesh.profile([(.45,.070,.075,x,0),(.69,.088,.086,x,0),
                      (hip+.015,.093,.094,x,0)],color,6,caps=False)
        mesh.knee = (1 if swing else 0,.45 if swing else 0)
        mesh.profile([(.085,.048,.051,x,0),(.29,.062,.064,x,-.005),
                      (.45,.070,.075,x,0)],color,6,caps=False)
        if officer:
            # Red DPS police side stripes down the outer sides of trousers
            mesh.panel(x+side*.076,.50,0,.018,.82,OFFICER_RED)
        shoes(mesh,x,swing,hip,.45,officer)
    mesh.swing = mesh.knee = (0,0)


def pedestrian(mesh, variant):
    skin = SKINS[variant%3]
    hair = HAIR[(variant//2)%4]
    slim = variant%3 == 1
    waist = .15 if slim else .177
    shoulder = .21 if slim else .234
    hip = .91
    trousers = [(.23,.29,.35,0),(.26,.26,.27,0),(.33,.30,.28,0)][variant%3]
    legs(mesh,trousers)
    mesh.profile([(.88,waist+.01,.103,0,0),(1.12,waist,.109,0,0),
                  (1.38,shoulder,.125,0,0),(1.435,.15,.085,0,0)],JACKET,8)
    # Shirt opening, zip, hem and collars share the torso's vertex colours.
    mesh.face([(-.085,1.427,.102),(0,1.335,.14),(.085,1.427,.102)],SHIRT)
    mesh.panel(0,1.16,.123,.016,.36,(.52,.52,.52,1))
    mesh.panel(-.10,.968,.112,.065,.014,(.70,.70,.70,1))
    mesh.panel(.10,.968,.112,.065,.014,(.70,.70,.70,1))
    mesh.profile([(1.423,.060,.059,0,0),(1.505,.056,.054,0,0)],skin,6,caps=False)
    for side in [-1,1]:
        x = side*(shoulder+.047)
        mesh.swing = (-side*.18,1.40)
        mesh.profile([(.952,.051,.057,x,.018),(1.17,.062,.065,x,-.014),
                      (1.395,.074,.074,x,0),(1.445,.036,.045,x,0)],(.86,.86,.86,1),6,caps=False)
        mesh.profile([(.943,.054,.059,x,.018),(.985,.054,.060,x,.014)],(.69,.69,.69,1),6,caps=False)
        mesh.profile([(.843,.033,.045,x,.025),(.952,.039,.044,x,.020)],skin,6)
    mesh.swing = (0,0)
    head(mesh,1.615,skin,hair,variant%4)
    if variant in (2,6,10):
        # Compact backpack with a shaped bottom, not a box floating behind the body.
        mesh.profile([(1.01,.105,.045,0,-.121),(1.12,.133,.058,0,-.133),
                      (1.35,.115,.051,0,-.121)],(.25,.28,.30,0),6)
        for x in [-.11,.11]: mesh.panel(x,1.28,.117,.025,.20,(.30,.31,.31,0))
    if variant in (4,8):
        for x in [-.046,.046]: mesh.panel(x,1.617,.107,.047,.025,(.17,.22,.24,0))
        mesh.panel(0,1.622,.108,.033,.008,BLACK)


def officer_body(mesh):
    legs(mesh,OFFICER_NAVY,1.01,True)
    mesh.profile([(.97,.198,.125,0,0),(1.18,.224,.144,0,0),
                  (1.465,.27,.143,0,0),(1.55,.145,.088,0,0)],OFFICER_NAVY,8)
    mesh.profile([(1.015,.211,.135,0,0),(1.20,.236,.153,0,0),
                  (1.47,.274,.149,0,0)],OFFICER_VEST,8,caps=False)
    mesh.profile([(1.19,.237,.154,0,0),(1.25,.247,.155,0,0)],OFFICER_SILVER,8,caps=False)
    for back in [False,True]:
        z = -.145 if back else .145
        for x in [-.125,.125]: mesh.panel(x,1.365,z,.037,.225,OFFICER_SILVER,back)
        mesh.panel(0,1.35,-.158 if back else .158,.018,.265,OFFICER_NAVY,back)
    mesh.profile([(1.525,.068,.065,0,0),(1.635,.062,.059,0,0)],SKINS[1],6,caps=False)
    for x in [-.056,.056]:
        mesh.face([(x-.037,1.545,.109),(x+.037,1.545,.109),(x,1.48,.126)],OFFICER_WHITE)
    mesh.panel(0,1.50,.126,.032,.092,OFFICER_NAVY)
    for x in [-.248,.248]: mesh.box((x,1.497,0),(.064,.025,.17),OFFICER_SILVER,bottom=True)
    head(mesh,1.735,SKINS[1],HAIR[0],officer=True)


def officer_arm(mesh, right=False):
    # All positions relative to the existing shoulder pivot: gestures keep their anatomy.
    mesh.profile([(-.485,.049,.052,0,0),(-.265,.066,.066,0,-.008),
                  (.028,.080,.080,0,0)],OFFICER_NAVY,6)
    mesh.profile([(-.49,.054,.057,0,0),(-.442,.057,.060,0,0)],OFFICER_SILVER,6,caps=False)
    mesh.profile([(-.603,.032,.042,0,.012),(-.49,.039,.045,0,.006)],OFFICER_WHITE,6)
    if right:
        rings = [(-1.025,.022,.022,0,.013),(-.94,.022,.022,0,.013),
                 (-.86,.022,.022,0,.013),(-.78,.022,.022,0,.013),
                 (-.70,.022,.022,0,.013),(-.58,.022,.022,0,.013)]
        for i in range(len(rings)-1):
            mesh.profile(rings[i:i+2],OFFICER_WHITE if i%2 == 0 else OFFICER_BLACK,6,caps=False)
        # Only end caps: avoid five overlapping cylinders for baton bands.
        for y,col in [(rings[0][0],OFFICER_WHITE),(rings[-1][0],OFFICER_BLACK)]:
            pts = [(.022*math.cos(i*math.tau/6),y,.013+.022*math.sin(i*math.tau/6)) for i in range(6)]
            if y==rings[-1][0]: pts.reverse()
            for i in range(1,5): mesh.face([pts[0],pts[i],pts[i+1]],col)



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=MODELS)
    args = parser.parse_args()
    index = json.loads((MODELS/'index.json').read_text())
    heights = [1.72,1.66,1.79,1.70,1.75,1.65,1.77,1.69,1.73,1.67,1.81,1.71]
    for variant,height in enumerate(heights):
        mesh = PersonMesh(height/1.805)
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
