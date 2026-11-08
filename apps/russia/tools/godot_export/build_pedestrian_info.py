#!/usr/bin/env python3
"""Optional lower pedestrian information panels, shared by the editor and Godot."""
import argparse
from pathlib import Path
from build_signals import SignalMesh, BLACK, STEEL, LENS, ROOT, write_model


def build(output):
    parts = []
    for side, sign in [('left', -1), ('right', 1)]:
        x, y = sign * .405, 2.14
        body = SignalMesh()
        body.rounded_box(x,y,.25,.79,.79,.4,.05,BLACK)
        # Thin frame and a recessed black face, without a visor hiding it from above.
        for a,b in [((-.36,-.36),(.36,-.36)),((.36,-.36),(.36,.36)),((.36,.36),(-.36,.36)),((-.36,.36),(-.36,-.36))]:
            body.line((x+a[0],y+a[1]),(x+b[0],y+b[1]),.015,STEEL,.455)
        parts.append(('info_body_'+side,body,'signal_body',None))
        glyph = SignalMesh()
        def point(p): return (sign*p[0],p[1])
        def stroke(points, width):
            for a,b in zip(points,points[1:]): glyph.line(point(a),point(b),width,LENS)
            for p in points[1:-1]: glyph.disk(*point(p),.001,width/2,LENS,12)
        # Walking figure, with a distinct bent arm and separated legs.
        glyph.disk(sign*.175,.225,.001,.044,LENS,16)
        stroke([(.175,.155),(.145,-.025)],.065)
        stroke([(.16,.12),(.09,.045),(.075,-.045)],.04)
        stroke([(.18,.12),(.225,.035),(.29,-.005)],.04)
        stroke([(.15,-.015),(.095,-.13),(.045,-.245)],.048)
        stroke([(.15,-.02),(.215,-.13),(.265,-.23)],.048)
        # Bent turn arrow beside the pedestrian; the entire left panel is mirrored.
        stroke([(-.235,-.19),(-.235,-.005),(-.225,.045),(-.195,.085),(-.15,.105),(-.075,.105)],.06)
        head=[(-.12,.19),(-.025,.105),(-.12,.02)]
        pts=[(*point(p),.002) for p in head]
        # Clockwise right-hand arrow becomes CCW after reflection.
        glyph.face(pts[::-1] if sign > 0 else pts,LENS)
        parts.append(('aperture_info_'+side,glyph,'signal_lens',('lamp_info_'+side,[x,y,.465])))
    write_model(output/'traffic_pedestrian_info.glb',parts,{},'PDD pedestrian information panels','tools/godot_export/build_pedestrian_info.py')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'game_godot/models/street')
    build(parser.parse_args().output)
