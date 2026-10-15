#!/usr/bin/env python3
"""Shared opaque signal bodies and independently controllable one-sided apertures.

Named lamp centres and the mast origin match archived junction exports. This
does not write network/scene JSON or official sign artwork. No textures/LED dots.
"""
import argparse
import math
from pathlib import Path

from build_buildings import ROOT
from build_environment import PropMesh
from build_vehicles import write_model

BLACK=(.10,.12,.14,1)
STEEL=(.43,.47,.50,1)
WHITE=(.87,.90,.92,1)
INK=(0,0,0,1)
LENS=(1,1,1,1)


class SignalMesh(PropMesh):
    def __init__(self):
        super().__init__([])
        self.role=0

    def face(self,points,color,kind=None,uv=None):
        start=len(self.positions)
        super().face(points,color,kind,uv)
        self.uv2[start:]=[(self.role,0)]*len(points)

    def disk(self, x, y, z, r, color, sides=20):
        for i in range(sides):
            a,b=i*math.tau/sides,(i+1)*math.tau/sides
            self.face([(x,y,z),(x+r*math.cos(a),y+r*math.sin(a),z),(x+r*math.cos(b),y+r*math.sin(b),z)],color)

    def rounded_box(self,x,y,z,w,h,d,corner,color):
        ring=[(-w/2+corner,-h/2),(w/2-corner,-h/2),(w/2,-h/2+corner),(w/2,h/2-corner),(w/2-corner,h/2),(-w/2+corner,h/2),(-w/2,h/2-corner),(-w/2,-h/2+corner)]
        front=[(x+a,y+b,z+d/2)for a,b in ring]
        back=[(x+a,y+b,z-d/2)for a,b in ring]
        for i in range(1,7):
            self.face([front[0],front[i],front[i+1]],color)
            self.face([back[0],back[i+1],back[i]],color)
        for i in range(8):
            j=(i+1)%8
            self.face([back[i],back[j],front[j],front[i]],color)

    def line(self,a,b,width,color,z=.001):
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
        nx,ny=-dy/length*width/2,dx/length*width/2
        self.face([(a[0]+nx,a[1]+ny,z),(a[0]-nx,a[1]-ny,z),(b[0]-nx,b[1]-ny,z),(b[0]+nx,b[1]+ny,z)],color)

    def arrow(self,direction,outlined=False):
        # Normative directions in the driver's view, looking at the +Z face.
        transform=lambda p:p if direction=='straight' else (p[1],-p[0]) if direction=='right' else (-p[1],p[0])
        head=[transform(p)for p in [(0,.15),(-.09,.055),(.09,.055)]]
        if outlined:
            for a,b in zip(head,head[1:]+head[:1]): self.line(a,b,.014,INK)
            for x in [-.029,.029]: self.line(transform((x,-.14)),transform((x,.055)),.012,INK)
            self.line(transform((-.029,-.14)),transform((.029,-.14)),.012,INK)
        else:
            self.line(transform((0,-.14)),transform((0,.055)),.06,LENS)
            # Ensure the 2D triangle always faces +Z after rotation/reflection.
            self.face([(x,y,.001)for x,y in head],LENS)


def body(tram=False,arrow=''):
    m=SignalMesh()
    m.role=1 # mast: lets the smaller mini-game preserve its own mounting profile
    m.stem((0,0,0),(0,5.4 if tram else 4.2,0),.08,.08,STEEL,None,8)
    m.role=2 # main housing/shield, without visors for the overhead camera
    m.rounded_box(0,3.4,.25,.65,1.6,.4,.055,BLACK)
    m.box((0,3.4,.01),(1.01,1.96,.02),BLACK,bottom=True)
    m.box((0,3.4,.03),(.95,1.9,.03),BLACK,bottom=True)
    for side in [-1,1]:
        m.box((side*.49,3.4,.024),(.03,1.96,.008),WHITE,bottom=True)
        m.box((0,3.4+side*.965,.024),(.95,.03,.008),WHITE,bottom=True)
    if arrow:
        m.role=3 # supplementary section
        x=-.70 if arrow=='left' else .70
        m.rounded_box(x,2.95,.25,.64,.64,.4,.055,BLACK)
        m.disk(x,2.95,.451,.29,BLACK)
    if tram:
        m.role=4
        m.box((0,2.05,.16),(.24,.28,.22),BLACK,bottom=True)
        m.rounded_box(0,4.6,.25,.65,.44,.4,.035,BLACK)
        m.rounded_box(0,5.06,.25,1.40,.48,.4,.04,BLACK)
        m.box((0,5.06,.03),(1.52,.56,.03),BLACK,bottom=True)
    return m


def build(output):
    for kind in ['standard','right','left','straight','tram']:
        tram=kind=='tram';arrow=kind if kind in ['right','left','straight']else ''
        parts=[('body',body(tram,arrow),'signal_body',None)]
        for name,y in [('red',3.85),('yellow',3.4),('green',2.95)]:
            m=SignalMesh();m.disk(0,0,0,.21,LENS)
            if name=='green' and arrow:
                for direction in ['left','straight','right']:
                    if direction!=arrow:m.arrow(direction,True)
            parts.append(('aperture_'+name,m,'signal_lens',('lamp_'+name,[0,y,.46])))
        if arrow:
            m=SignalMesh();m.disk(0,0,0,.21,INK);m.arrow(arrow)
            parts.append(('aperture_arrow',m,'signal_lens',('lamp_arrow',[-.70 if arrow=='left' else .70,2.95,.46])))
        if tram:
            for name,x,y in [('bottom',0,4.6),('mid',0,5.06),('left',-.42,5.06),('right',.42,5.06)]:
                m=SignalMesh();m.disk(0,0,0,.18,LENS)
                parts.append(('aperture_tram_'+name,m,'signal_lens',('lamp_tram_'+name,[x,y,.46])))
        write_model(output/('traffic_light_'+kind+'.glb'),parts,{},'PDD shared traffic signals','tools/godot_export/build_signals.py')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game_godot/models/street')
    build(parser.parse_args().output)
