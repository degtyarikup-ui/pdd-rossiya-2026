#!/usr/bin/env python3
"""Shared car geometry and lightweight NPC transport (indexed, vertex colours).

Cars are authored once in models/vehicles. Runtime caches an instanced mesh from
these same parts; no second set of traffic GLBs is needed. NPC-only models have
one surface, with wheel pivots and lamp roles encoded in existing UV channels.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import struct
import tempfile

from build_buildings import ROOT
from build_people import PersonMesh, head, SKINS, HAIR

MODELS = ROOT/'game_godot/models'
PAINT = (.95,.95,.95,1)
CAB = (.95,.95,.95,.5)
DARK = (.12,.15,.18,0)
RUBBER = (.09,.105,.12,0)
METAL = (.57,.62,.65,0)
GLASS = (.20,.29,.36,0)
FRONT = (.875,.842,.712,0)
REAR = (.724,.211,.196,0)
AMBER = (.95,.57,.11,0)
WHITE = (.84,.85,.82,0)

class VehicleMesh(PersonMesh):
    generator = 'PDD shared vehicles'
    def __init__(self):
        super().__init__()
        self.wheel_pivot = None
        self.lamp = 0
    def face(self, points, color, kind=None, uv=None):
        start = len(self.positions)
        super().face(points,color)
        if self.wheel_pivot is None:
            self.uv[start:] = [(0,0)]*len(points)
            self.uv2[start:] = [(0,self.lamp)]*len(points)
        else:
            z,y,r = self.wheel_pivot
            self.uv[start:] = [(z,y)]*len(points)
            self.uv2[start:] = [(1,r)]*len(points)
    def pane(self, points):
        start = len(self.positions)
        self.face(points,GLASS)
        ys = [p[1] for p in points]
        span = max(ys)-min(ys)
        for i,p in enumerate(points):
            t = (p[1]-min(ys))/span if span else .5
            self.colors[start+i] = (.13+.13*t,.21+.15*t,.28+.17*t,0)
    def loft(self, sections, color):
        # z, half-width, bottom, top, optional raised outer sill (wheel arch).
        rings=[]
        for section in sections:
            z,w,lo,hi = section[:4]
            sill = section[4] if len(section)>4 else lo+.06
            bevel = min(.06,(hi-lo)*.18)
            sill = min(sill,hi-bevel-.008)
            rings.append([(-w*.84,lo,z),(w*.84,lo,z),(w,sill,z),
                          (w,hi-bevel,z),(w*.91,hi,z),(-w*.91,hi,z),
                          (-w,hi-bevel,z),(-w,sill,z)])
        for row in range(len(rings)-1):
            for i in range(8):
                j=(i+1)%8
                self.face([rings[row][i],rings[row][j],rings[row+1][j],rings[row+1][i]],color)
        # End winding: clockwise at -Z, anticlockwise at +Z.
        for row, reverse in [(0,True),(-1,False)]:
            pts=list(reversed(rings[row])) if reverse else rings[row]
            for i in range(1,7): self.face([pts[0],pts[i],pts[i+1]],color)
    def bar(self, a, b, radius, color, n=6):
        direction=[b[i]-a[i] for i in range(3)]
        length=math.sqrt(sum(x*x for x in direction))
        axis=[v/length for v in direction]
        helper=[0,1,0] if abs(axis[1])<.9 else [1,0,0]
        u=[axis[1]*helper[2]-axis[2]*helper[1],axis[2]*helper[0]-axis[0]*helper[2],axis[0]*helper[1]-axis[1]*helper[0]]
        norm=math.sqrt(sum(v*v for v in u));u=[v/norm for v in u]
        v=[axis[1]*u[2]-axis[2]*u[1],axis[2]*u[0]-axis[0]*u[2],axis[0]*u[1]-axis[1]*u[0]]
        rings=[[(p[0]+radius*(math.cos(i*math.tau/n)*u[0]+math.sin(i*math.tau/n)*v[0]),
                 p[1]+radius*(math.cos(i*math.tau/n)*u[1]+math.sin(i*math.tau/n)*v[1]),
                 p[2]+radius*(math.cos(i*math.tau/n)*u[2]+math.sin(i*math.tau/n)*v[2])) for i in range(n)] for p in [a,b]]
        for i in range(n):
            j=(i+1)%n;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],color)
    def wheel(self,x,y,z,r,width,n=12,open_rim=False):
        self.wheel_pivot=(z,y,r)
        rings=[]
        for dx,factor in [(-width/2,.85),(-width*.34,1),(width*.34,1),(width/2,.85)]:
            rings.append([(x+dx,y+r*factor*math.cos(i*math.tau/n),z+r*factor*math.sin(i*math.tau/n))for i in range(n)])
        for row in range(3):
            for i in range(n):
                j=(i+1)%n;self.face([rings[row][i],rings[row][j],rings[row+1][j],rings[row+1][i]],RUBBER)
        for side in [-1,1]:
            outer=rings[0 if side<0 else -1]
            inner=[(x+side*width/2,y+r*(.78 if open_rim else .57)*math.cos(i*math.tau/n),z+r*(.78 if open_rim else .57)*math.sin(i*math.tau/n))for i in range(n)]
            for i in range(n):
                j=(i+1)%n;pts=[outer[i],outer[j],inner[j],inner[i]]
                self.face(list(reversed(pts)) if side<0 else pts,METAL if open_rim else RUBBER)
            for i in range(0 if open_rim else 1,0 if open_rim else n-1):
                pts=[inner[0],inner[i],inner[i+1]]
                self.face(list(reversed(pts)) if side<0 else pts,METAL)
            for i in range(0 if open_rim else 5):
                angle=i*math.tau/5
                pts=[]
                for radius,delta in [(r*.14,-.12),(r*.52,-.10),(r*.52,.10),(r*.14,.12)]:
                    pts.append((x+side*(width/2+.002),y+radius*math.cos(angle+delta),z+radius*math.sin(angle+delta)))
                self.face(list(reversed(pts)) if side<0 else pts,DARK)
        self.wheel_pivot=None
    def light(self,x,y,z,w,h,rear=False,turn=False):
        self.lamp=3 if turn else 2 if rear else 1
        pts=[(x-w/2,y-h/2,z),(x+w/2,y-h/2,z),(x+w/2,y+h/2,z),(x-w/2,y+h/2,z)]
        self.face(list(reversed(pts)) if rear else pts,AMBER if turn else REAR if rear else FRONT)
        self.lamp=0


def mirrors(mesh,w,y,z,color=PAINT,reach=.123):
    for side in [-1,1]:
        mesh.box((side*(w+reach*.25),y,z),(min(.09,reach),.035,.05),DARK,bottom=True)
        mesh.box((side*(w+reach-.059),y+.025,z),(.118,.10,.17),color,bottom=True)


def cab(mesh,w,lo,hi,zback,zfront,color=PAINT):
    mesh.loft([(zback,w*.95,lo,hi-.08),(zback+.22,w,lo,hi),
               (zfront-.30,w,lo,hi),(zfront,w*.88,lo,hi-.24)],color)
    mesh.pane([(-w*.78,hi-.80,zfront+.012),(w*.78,hi-.80,zfront+.012),
               (w*.77,hi-.29,zfront+.012),(-w*.77,hi-.29,zfront+.012)])
    for side in [-1,1]:
        x=side*(w+.009)
        pts=[(x,hi-.88,zback+.25),(x,hi-.88,zfront-.28),
             (x,hi-.25,zfront-.31),(x,hi-.18,zback+.25)]
        mesh.pane(pts if side<0 else list(reversed(pts)))
        mesh.box((x,hi-.95,zfront-.65),(.026,.027,.16),DARK)
    mirrors(mesh,w,hi-.65,zfront-.39,color)


def car_parts(kind,hw,hl,roof):
    body=VehicleMesh();wheel_z=[-hl*.64,hl*.64]
    radius=.36 if kind in ('suv','pickup') else .32
    shoulder=.94 if kind in ('suv','pickup') else .77
    stations={-hl-.09,hl+.09,-hl,hl}
    for wz in wheel_z:
        for dz in [-.40,-.28,0,.28,.40]:stations.add(wz+dz)
    sections=[]
    for z in sorted(stations):
        w=hw*(.90 if abs(z)>hl else 1)
        top=shoulder-(.10 if abs(z)>hl else 0)
        arch=.30
        for wz in wheel_z:
            if abs(z-wz)<radius+.055:arch=max(arch,radius+math.sqrt((radius+.055)**2-(z-wz)**2))
        sections.append((z,w,.26,top,arch))
    body.loft(sections,PAINT)
    rear_base=-hl*(.75 if kind in ('wagon','suv','hatch') else .55)
    front_base=hl*.49
    rear_roof=-hl*(.62 if kind in ('wagon','suv','hatch') else .34)
    front_roof=hl*.20
    if kind=='coupe':rear_roof=-hl*.19
    if kind=='pickup':rear_base=-.22;rear_roof=-.08
    rw=hw*.77
    # Sloping pillars, chamfered roof corners and actual front/rear glass openings.
    body.loft([(rear_base,hw*.88,shoulder-.02,shoulder+.05),
               (rear_roof,rw,shoulder-.02,roof),(front_roof,rw,shoulder-.02,roof),
               (front_base,hw*.88,shoulder-.02,shoulder+.05)],PAINT)
    for front,base,top in [(True,front_base,front_roof),(False,rear_base,rear_roof)]:
        direction=1 if front else -1
        upper_z=top+direction*.065
        lower_z=base-direction*.07
        def glass_y(z):return roof+(shoulder+.05-roof)*(z-top)/(base-top)
        upper_y,lower_y=glass_y(upper_z),glass_y(lower_z)
        points=[(-hw*.78,lower_y,lower_z+direction*.024),(hw*.78,lower_y,lower_z+direction*.024),
                (rw*.89,upper_y,upper_z+direction*.024),(-rw*.89,upper_y,upper_z+direction*.024)]
        body.pane(points if front else list(reversed(points)))
    for side in [-1,1]:
        lower_x=side*(hw*.91+.012);upper_x=side*(rw+.014)
        # Divide the glazing into panes with a visible B pillar.
        middle=(rear_roof+front_roof)*.38
        for low0,low1,top0,top1 in [(rear_base+.13,middle-.055,rear_roof+.055,middle-.055),
                                   (middle+.055,front_base-.12,middle+.055,front_roof-.035)]:
            pts=[(lower_x,shoulder+.10,low0),(lower_x,shoulder+.10,low1),
                 (upper_x,roof-.10,top1),(upper_x,roof-.10,top0)]
            body.pane(pts if side<0 else list(reversed(pts)))
        for dz in [hl*.09,-hl*.35] if kind not in ('coupe','pickup') else [hl*.08]:
            body.box((side*(hw+.009),shoulder-.075,dz),(.024,.027,.15),METAL)
        body.box((side*(hw+.008),.37,0),(.018,.032,hl*1.5),DARK)
    mirrors(body,hw,shoulder+.16,front_base-.12)
    # Narrow lenses and inset bumper/grille read at game-camera distance.
    body.box((0,.53,hl+.085),(hw*.72,.15,.018),DARK)
    for y in [.49,.53,.57]:body.box((0,y,hl+.098),(hw*.65,.018,.006),METAL)
    body.box((0,.34,hl+.087),(hw*.9,.09,.018),DARK)
    for z in [-hl-.102,hl+.102]:
        body.box((0,.35,z),(.38,.09,.012),WHITE)
        for x in [-.11,-.055,0,.055,.11]:body.box((x,.35,z+(.008 if z>0 else -.008)),(.023,.037,.004),DARK)
    for side in [-1,1]:body.light(side*hw*.68,.65,hl+.10,hw*.46,.11)
    if kind=='pickup':
        # Recessed load bed with side walls, rather than a tall solid rear cabin.
        body.box((0,shoulder+.008,-hl*.60),(hw*1.57,.018,hl*.67),DARK)
        for side in [-1,1]:body.box((side*hw*.88,shoulder+.07,-hl*.6),(.10,.15,hl*.72),PAINT)
    if kind in ('suv','wagon'):
        for side in [-1,1]:body.bar((side*rw*.78,roof+.012,rear_roof),(side*rw*.78,roof+.012,front_roof),.026,DARK)
    parts=[('body',body,'baked',None)]
    for i,(x,z) in enumerate([(hw-.05,wheel_z[1]),(-hw+.05,wheel_z[1]),(hw-.05,wheel_z[0]),(-hw+.05,wheel_z[0])]):
        wheel=VehicleMesh();wheel.wheel(0,0,0,radius,.19)
        parts.append((f'wheel_{i}',wheel,'baked',('axle_front_'+str(i) if i<2 else 'axle_'+str(i),[x,radius,z])))
    for side,label in [(1,'L'),(-1,'R')]:
        brake=VehicleMesh();brake.light(side*hw*.66,.65,-hl-.11,hw*.47,.14,True)
        parts.append(('brake_'+('0' if side>0 else '1'),brake,'lens',None))
        for rear in [False,True]:
            signal=VehicleMesh();signal.light(side*hw*.89,.65,(-hl-.12 if rear else hl+.12),.13,.105,rear,True)
            parts.append((f'blink_{label}_'+('rear' if rear else 'front'),signal,'lens',('blink_'+label,None)))
    return parts


def cargo_model(kind):
    m=VehicleMesh()
    if kind in ('truck','tanker'):
        cab(m,.995,.46,2.25,.75,3.12,CAB if kind=='tanker' else PAINT)
        if kind=='truck':
            m.loft([(-3.62,1.04,.72,2.47),(-3.45,1.04,.72,2.55),(.70,1.04,.72,2.55)],(.73,.76,.76,0))
            for side in [-1,1]:
                for z in [-3,-2.2,-1.4,-.6,.2]:m.box((side*1.047,1.55,z),(.01,1.62,.017),METAL)
        else:
            # The reservoir is a ten-sided cylinder, with rounded end transitions.
            start=len(m.positions)
            m.profile([(-3.55,.57,.57,0,0),(-3.3,.83,.83,0,0),(.25,.83,.83,0,0),(.55,.57,.57,0,0)],PAINT,10)
            # Profile's Y axis becomes reservoir Z; raise it onto the chassis.
            for i in range(start,len(m.positions)):
                x,y,z=m.positions[i];m.positions[i]=(x,1.75-z,y)
                nx,ny,nz=m.normals[i];m.normals[i]=(nx,-nz,ny)
            for z in [-2.6,-1.0]:m.box((0,2.66,z),(.45,.12,.48),METAL)
            for z in [-2.8,-.3]:m.bar((0,2.71,z),(0,2.71,z+.45),.025,METAL)
            m.lamp=6;m.box((0,2.37,2.17),(.16,.20,.16),AMBER,bottom=True);m.lamp=0
        m.box((0,.50,-.30),(1.74,.24,6.1),DARK)
        axles=[-2.9,-1.8,2.05];r=.42
    elif kind in ('bus','tram'):
        tram=kind=='tram';half=4.73 if tram else 3.49;top=2.94 if tram else 2.25;w=1.1 if tram else 1.04
        m.loft([(-half,w*.93,.42,top-.16),(-half+.30,w,.42,top),
                (half-.40,w,.42,top),(half,w*.88,.42,top-.16)],PAINT)
        m.pane([(-w*.77,1.04,half+.012),(w*.77,1.04,half+.012),(w*.77,top-.26,half+.012),(-w*.77,top-.26,half+.012)])
        for side in [-1,1]:
            for col in range(8 if tram else 6):
                z=-half+.64+col*(2*half-1.20)/(8 if tram else 6)
                pts=[(side*(w+.009),1.10,z-.39),(side*(w+.009),1.10,z+.39),
                     (side*(w+.009),top-.25,z+.39),(side*(w+.009),top-.25,z-.39)]
                m.pane(pts if side<0 else list(reversed(pts)))
            m.box((side*(w+.015),.63,0),(.018,.035,half*1.75),DARK)
        # Boarding door frames on the vehicle's anatomical right (-X).
        for z in [half-.78,-half*.30]:
            m.box((-w-.018,1.26,z),(.015,1.62,.75),DARK)
            for offset in [-.19,.19]:m.box((-w-.029,1.40,z+offset),(.008,1.28,.31),GLASS)
        m.pane([(w*.77,1.12,-half-.012),(-w*.77,1.12,-half-.012),(-w*.77,top-.24,-half-.012),(w*.77,top-.24,-half-.012)])
        if tram:
            for z in [-1.15,1.15]:
                m.bar((-.65,top+.04,z),(.0,top+.40,z),.028,METAL)
                m.bar((.65,top+.04,z),(.0,top+.40,z),.028,METAL)
            m.bar((0,top+.40,-1.15),(0,top+.40,1.15),.035,DARK)
        else:m.box((0,top+.045,-.45),(1.13,.10,1.0),(.68,.72,.73,0))
        if not tram:mirrors(m,w,top-.65,half-.28)
        axles=[-half*.65,half*.61];r=.40 if tram else .42
        for side in [-1,1]:m.light(side*w*.70,.79,half+.025,.28,.13);m.light(side*w*.7,.85,-half-.025,.25,.20,True)
        for side in [-1,1]:
            m.light(side*w*.86,.79,half+.033,.13,.10,False,True);m.light(side*w*.86,.85,-half-.033,.13,.10,True,True)
        for z in axles:
            for x in [-w+.05,w-.05]:m.wheel(x,r,z,r,.19,10)
        return m
    elif kind=='van':
        w=1.01;half=2.43;top=2.065
        m.loft([(-half,w*.92,.30,top-.15),(-half+.19,w,.30,top),
                (1.50,w,.30,top),(half,w*.85,.30,1.18)],PAINT)
        glass_top_z=1.58;glass_bottom_z=2.23
        def van_y(z):return top-(top-1.18)*(z-1.50)/(half-1.50)
        m.pane([(-.78,van_y(glass_bottom_z),glass_bottom_z+.025),(.78,van_y(glass_bottom_z),glass_bottom_z+.025),
                (.78,van_y(glass_top_z),glass_top_z+.025),(-.78,van_y(glass_top_z),glass_top_z+.025)])
        for side in [-1,1]:
            m.pane([(side*(w+.008),1.13,.65),(side*(w+.008),1.13,1.65),
                    (side*(w+.008),top-.18,1.47),(side*(w+.008),top-.16,.65)] if side<0 else
                   [(side*(w+.008),top-.16,.65),(side*(w+.008),top-.18,1.47),(side*(w+.008),1.13,1.65),(side*(w+.008),1.13,.65)])
            m.box((side*(w+.01),1.00,.9),(.014,.028,.20),DARK)
            m.box((side*(w+.009),1.13,-.8),(.009,.023,1.35),DARK)
        mirrors(m,w,1.34,1.51,reach=.08)
        axles=[-1.56,1.48];r=.36
    else:raise ValueError(kind)
    half=3.62 if kind in ('truck','tanker') else 2.43
    front=3.13 if kind in ('truck','tanker') else half
    w=.995 if kind in ('truck','tanker') else 1.01
    m.box((0,.51,front+.024),(w*.95,.23,.018),DARK)
    for side in [-1,1]:
        m.light(side*w*.68,.74,front+.039,.29,.13)
        m.light(side*w*.84,.74,front+.043,.12,.10,False,True)
        m.light(side*w*.69,.66,-half-.014,.26,.18,True)
        m.light(side*w*.85,.66,-half-.019,.12,.10,True,True)
    for z in axles:
        for x in [-w+.06,w-.06]:m.wheel(x,r,z,r,.24,10)
    return m


def rider(m,bike=False):
    skin=SKINS[1];m.lamp=0
    # Helmet, jacket, hands and bent limbs; no separate skin/skeleton or transparent visor.
    m.profile([(1.00,.13,.10,0,-.18),(1.38,.20,.12,0,-.025)],(.28,.35,.40,0),6)
    if bike:
        head(m,1.55,skin,HAIR[0],0)
        m.profile([(1.65,.129,.105,0,0),(1.76,.08,.066,0,0)],PAINT,8)
    else:
        m.profile([(1.43,.08,.074,0,0),(1.58,.105,.091,0,0)],skin,8)
        m.profile([(1.50,.127,.115,0,0),(1.66,.116,.105,0,0),(1.75,.067,.064,0,0)],PAINT,8)
        m.pane([(-.083,1.545,.121),(.083,1.545,.121),(.081,1.65,.112),(-.081,1.65,.112)])
    for side in [-1,1]:
        m.bar((side*.17,1.32,0),(side*.24,1.12,.29),.052,(.28,.35,.40,0))
        m.bar((side*.24,1.12,.29),(side*.23,1.10,.47),.038,skin)
        m.bar((side*.10,1.00,-.16),(side*.19,.67,.22),.069,DARK)
        m.bar((side*.19,.67,.22),(side*.20,.28,-.04),.046,DARK)
        m.box((side*.20,.24,.045),(.12,.10,.25),DARK,bottom=True)


def two_wheeler(kind):
    m=VehicleMesh();cycle=kind=='cyclist';r=.33;zfront=.72;zback=-.67
    for z in [zback,zfront]:m.wheel(0,r,z,r,.055 if cycle else .13,12,cycle)
    color=PAINT
    for a,b in [((0,.33,zback),(0,.72,-.24)),((0,.72,-.24),(0,.37,.10)),
                ((0,.37,.10),(0,.33,zback)),((0,.72,-.24),(0,.89,.49)),((0,.89,.49),(0,.37,.10)),
                ((0,.89,.49),(0,.33,zfront))]:m.bar(a,b,.022 if cycle else .04,color)
    m.bar((-.25,1.09,.47),(.25,1.09,.47),.022,METAL)
    m.bar((0,.89,.49),(0,1.09,.47),.025,METAL)
    m.box((0,.98,-.20),(.24,.09,.30),DARK,bottom=True)
    if not cycle:
        m.loft([(-.18,.18,.63,.75),(.17,.20,.63,.87),(.36,.12,.63,.79)],PAINT)
        m.box((0,.52,.00),(.28,.26,.30),METAL,bottom=True)
        m.bar((.19,.48,-.43),(.19,.40,.26),.045,METAL)
        m.light(0,1.00,.64,.16,.16)
        m.light(0,.86,-.81,.12,.10,True)
        for side in [-1,1]:
            m.light(side*.28,.97,.62,.07,.07,False,True)
            m.light(side*.20,.78,-.84,.07,.07,True,True)
    else:
        for z in [zfront,zback]:
            for side in [-1,1]:
                for i in range(8):
                    angle=i*math.tau/8
                    m.bar((side*.031,r,z),(side*.031,r+r*.87*math.cos(angle),z+r*.87*math.sin(angle)),.004,METAL,4)
    rider(m,cycle)
    return m


def sidecar():
    m=VehicleMesh();m.loft([(-.74,.23,.25,.43),(-.46,.31,.25,.71),(.44,.31,.25,.68),(.79,.20,.25,.42)],PAINT)
    m.box((0,.59,-.16),(.38,.022,.58),DARK)
    m.pane([(-.25,.68,.20),(.25,.68,.20),(.24,.83,.03),(-.24,.83,.03)])
    m.wheel(-.31,.29,-.02,.29,.12,10)
    return m


def tractor():
    m=VehicleMesh();m.loft([(-1.62,.48,.48,.78),(-.78,.58,.48,1.0),(1.53,.55,.48,1.05),(1.93,.43,.48,.88)],PAINT)
    cab(m,.52,.83,2.08,-1.35,-.09)
    m.bar((.35,1.08,.79),(.35,1.9,.79),.048,DARK)
    m.box((0,1.2,-.72),(1.30,.025,1.20),PAINT)
    for side in [-1,1]:
        m.wheel(side*.80,.68,-1.15,.68,.27,12);m.wheel(side*.64,.43,1.13,.43,.20,10)
        m.light(side*.37,.83,1.94,.17,.11)
    return m


def cart():
    m=VehicleMesh();wood=(.40,.28,.18,0)
    m.box((0,.73,-1.42),(1.40,.16,2.18),wood,bottom=True)
    for side in [-1,1]:
        for y in [.90,1.12]:m.box((side*.68,y,-1.42),(.085,.14,2.18),wood,bottom=True)
        m.wheel(side*.73,.59,-1.42,.59,.13,12)
        m.bar((side*.49,.77,-.29),(side*.26,.85,1.04),.045,wood)
    # Horse: shaped neck/muzzle, tapered legs and ears; a recognisable low-poly silhouette.
    start=len(m.positions)
    m.profile([(.68,.20,.42,0,0),(1.00,.31,.57,0,0),(1.34,.27,.49,0,0)],(.39,.27,.19,0),8)
    for i in range(start,len(m.positions)):
        x,y,z=m.positions[i];m.positions[i]=(x,y,z+1.51)
    m.bar((0,1.19,1.76),(0,1.82,2.00),.19,(.39,.27,.19,0),8)
    m.loft([(1.89,.13,1.76,2.03),(2.16,.17,1.69,1.97),(2.69,.14,1.56,1.77)],(.39,.27,.19,0))
    for x in [-.23,.23]:
        for z in [1.09,1.85]:
            m.bar((x,1.03,z),(x*.90,.47,z+.08),.059,(.32,.22,.16,0))
            m.bar((x*.90,.47,z+.08),(x*.88,.10,z-.025),.038,(.27,.21,.17,0))
            m.box((x*.88,.075,z),(.13,.15,.19),DARK,bottom=True)
    for side in [-1,1]:
        m.bar((side*.09,1.96,2.02),(side*.12,2.22,1.94),.035,(.32,.22,.16,0),4)
        m.box((side*.155,1.83,2.15),(.012,.022,.025),DARK)
    m.bar((0,1.21,.93),(0,.71,.65),.036,DARK)
    # Driver seated at the front of the cart, with the reins between the hands.
    m.profile([(1.08,.14,.11,0,-.66),(1.50,.19,.12,0,-.58)],(.29,.36,.42,0),6)
    start=len(m.positions)
    head(m,1.64,SKINS[1],HAIR[1],0)
    for i in range(start,len(m.positions)):
        x,y,z=m.positions[i];m.positions[i]=(x,y,z-.58)
    for side in [-1,1]:
        m.bar((side*.16,1.46,-.57),(side*.24,1.19,-.24),.052,(.29,.36,.42,0))
        m.bar((side*.24,1.19,-.24),(side*.18,1.14,.07),.035,SKINS[1])
        m.bar((side*.11,1.10,-.66),(side*.22,.80,-.32),.067,DARK)
        m.bar((side*.22,.80,-.32),(side*.22,.40,-.33),.046,DARK)
        m.bar((side*.18,1.14,.07),(side*.13,1.68,2.05),.006,DARK,4)
    return m


def train():
    m=VehicleMesh()
    for i,z in enumerate([22,6,-8,-22]):
        hl=8 if i==0 else 7;h=3.6 if i==0 else 3.4;w=1.45 if i==0 else 1.4
        col=CAB if i==0 else PAINT
        m.loft([(z-hl,w*.92,.30,h-.22),(z-hl+.4,w,.30,h),(z+hl-.8,w,.30,h),(z+hl,w*.83,.30,h-.40)],col)
        for side in [-1,1]:
            for k in range(7):
                at=z-hl+1.4+k*(2*hl-2.8)/7
                m.pane([(side*(w+.007),1.65,at-.58),(side*(w+.007),1.65,at+.58),
                        (side*(w+.007),2.72,at+.58),(side*(w+.007),2.72,at-.58)] if side<0 else
                       [(side*(w+.007),2.72,at-.58),(side*(w+.007),2.72,at+.58),(side*(w+.007),1.65,at+.58),(side*(w+.007),1.65,at-.58)])
        for at in [z-hl*.63,z+hl*.63]:
            m.box((0,.41,at),(2.4,.55,1.7),DARK)
            for x in [-1.15,1.15]:m.wheel(x,.36,at,.36,.18,8)
        if i==0:
            m.pane([(-1.0,2.15,z+hl+.012),(1.0,2.15,z+hl+.012),(1.0,3.07,z+hl+.012),(-1.0,3.07,z+hl+.012)])
            for side in [-1,1]:m.light(side*.91,1.20,z+hl+.027,.25,.18)
    return m


def write_model(path,parts,index):
    # Reuse the tested single-mesh packer; combine buffers and keep named pivots.
    binary=bytearray();views=[];accessors=[];meshes=[];nodes=[];materials=[];material_ids={};children=[];groups={}
    (ROOT/'scratch').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='vehicle-parts-',dir=ROOT/'scratch') as tmp:
        for name,mesh,material,parent in parts:
            temp=Path(tmp)/(name+'.glb');mesh.save(temp);data=temp.read_bytes()
            size=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+size]);blob=data[size+28:]
            offset=len(binary);view_offset=len(views);acc_offset=len(accessors)
            binary.extend(blob)
            for view in doc['bufferViews']:
                view=dict(view);view['byteOffset']=view.get('byteOffset',0)+offset;views.append(view)
            for acc in doc['accessors']:
                acc=dict(acc);acc['bufferView']+=view_offset;accessors.append(acc)
            if material not in material_ids:
                material_ids[material]=len(materials)
                materials.append({'name':material,'pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':.83}})
            primitive=doc['meshes'][0]['primitives'][0]
            primitive['attributes']={k:v+acc_offset for k,v in primitive['attributes'].items()}
            primitive['indices']+=acc_offset;primitive['material']=material_ids[material]
            meshes.append({'primitives':[primitive]})
            node={'name':name,'mesh':len(meshes)-1};node_id=len(nodes);nodes.append(node)
            if parent:
                group,translation=parent
                if group not in groups:
                    groups[group]=len(nodes);g={'name':group,'children':[]}
                    if translation:g['translation']=translation
                    nodes.append(g);children.append(groups[group])
                nodes[groups[group]]['children'].append(node_id)
            else:children.append(node_id)
    root=len(nodes);nodes.append({'name':path.stem,'children':children})
    doc={'asset':{'version':'2.0','generator':'PDD shared vehicles'},'scene':0,'scenes':[{'nodes':[root]}],
         'nodes':nodes,'meshes':meshes,'materials':materials,'bufferViews':views,'accessors':accessors,'buffers':[{'byteLength':len(binary)}]}
    data=json.dumps(doc,separators=(',',':')).encode();data+=b' '*(-len(data)%4)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(data)+len(binary))+struct.pack('<II',len(data),0x4e4f534a)+data+struct.pack('<II',len(binary),0x004e4942)+binary)
    tris=sum(len(p[1].indices)//3 for p in parts);verts=sum(len(p[1].positions) for p in parts)
    entry=index.setdefault(str(path.relative_to(path.parents[1])).removesuffix('.glb'),{})
    entry['after']={'meshes':len(parts),'tris':tris};entry['source']='tools/godot_export/build_vehicles.py'
    print(path.name,verts,'vertices',tris,'triangles',len(parts),'meshes')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,default=MODELS);args=parser.parse_args()
    index=json.loads((MODELS/'index.json').read_text())
    heights={'hatch':1.45,'sedan':1.40,'coupe':1.30,'wagon':1.50,'suv':1.90,'pickup':1.70}
    for kind,height in heights.items():
        meta=index['vehicles/'+kind]['meta']
        write_model(args.output/'vehicles'/(kind+'.glb'),car_parts(kind,meta['halfWidth'],meta['halfLength'],height),index)
    for kind in ['bus','truck','van','tanker','tram','motorcycle','cyclist','sidecar','tractor','cart','train']:
        if kind in ['bus','truck','van','tanker','tram']:mesh=cargo_model(kind)
        elif kind in ['motorcycle','cyclist']:mesh=two_wheeler(kind)
        else:mesh={'sidecar':sidecar,'tractor':tractor,'cart':cart,'train':train}[kind]()
        write_model(args.output/'road'/(kind+'.glb'),[('body',mesh,'baked',None)],index)
    # Historical 'traffic/*' statistics no longer describe a separate runtime asset.
    for key in list(index):
        if key.startswith('traffic/'):
            shared='vehicles/'+key.split('/')[1]
            index[key]['shared_model']=shared
            index[key]['after']={'meshes':1,'tris':index[shared]['after']['tris']}
    (args.output/'index.json').write_text(json.dumps(index,ensure_ascii=False,indent=1)+'\n')

if __name__=='__main__':main()
