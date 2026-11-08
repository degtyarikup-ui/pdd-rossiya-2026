#!/usr/bin/env python3
"""Mast-free vehicle heads and a two-cell reversible signal; shared by both renderers."""
import argparse
import math
from pathlib import Path
from build_signals import SignalMesh, BLACK, STEEL, LENS, ROOT, write_model, build


def reversible(output):
    body = SignalMesh()
    for x in [-.46, .46]:
        body.rounded_box(x, 3.05, .25, .88, .9, .4, .045, BLACK)
        # A narrow rim keeps dark, switched-off cells legible.
        for a, b in [((-.43,-.44),(.43,-.44)),((.43,-.44),(.43,.44)),((.43,.44),(-.43,.44)),((-.43,.44),(-.43,-.44))]:
            body.line((x+a[0],3.05+a[1]),(x+b[0],3.05+b[1]),.018,STEEL,.453)
    parts = [('body', body, 'signal_body', None)]
    for name in ['red','green','yellow_left','yellow_right']:
        m = SignalMesh()
        if name == 'red':
            m.line((-.25,-.27),(.25,.27),.09,LENS)
            m.line((-.25,.27),(.25,-.27),.09,LENS)
        else:
            angle = -math.pi/4 if name == 'yellow_right' else math.pi/4 if name == 'yellow_left' else 0
            def point(p):
                x,y=p
                return (x*math.cos(angle)+y*math.sin(angle),-x*math.sin(angle)+y*math.cos(angle))
            m.line(point((0,.29)),point((0,-.25)),.1,LENS)
            for a,b in [((0,-.28),(-.22,-.06)),((0,-.28),(.22,-.06))]:
                m.line(point(a),point(b),.1,LENS)
            x,y=point((0,-.28))
            m.disk(x,y,.001,.05,LENS,12)
        parts.append(('aperture_reverse_'+name,m,'signal_lens',('lamp_reverse_'+name,[-.46 if name=='red' else .46,3.05,.465])))
    write_model(output/'traffic_head_reversible.glb',parts,{},'PDD reversible signal','tools/godot_export/build_signal_mounts.py')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game_godot/models/street')
    output=parser.parse_args().output
    build(output,head_only=True)
    reversible(output)
