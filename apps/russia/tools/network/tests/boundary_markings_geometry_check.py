"""Exercise the same paint geometry exported to Godot, without saving any author scene."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build
from shapely.geometry import Point
for kind, second in [('solid','solid'),('dashed','dashed'),('solid','dashed'),('dashed','solid')]:
    marking = {'type': kind, 'double': second, 'side': 1, 'points': [[.14,0],[.14,40]]}
    geometry = build.marking_geometry(marking)
    assert geometry.is_valid and not geometry.is_empty
    for x in [-.14,.14]:
        assert geometry.covers(Point(x,1)), (kind,second,x)
    assert not geometry.covers(Point(0,1)), 'Pair retains a clear gap'
    assert geometry.covers(Point(.14,2.5)) == (kind=='solid')
    assert geometry.covers(Point(-.14,2.5)) == (second=='solid')
    paired = kind == second == 'dashed'
    assert geometry.covers(Point(.14,3.5)) == (kind == 'solid' or paired)
    assert geometry.covers(Point(-.14,3.5)) == (second == 'solid' or paired)
    assert build.marking_geometry({**marking,'points':[[0,0],[1,10],[5,20]]}).is_valid
print('Double and mixed markings: actual Godot-export paint geometry, paired strokes, gaps, orientation and curves PASS')
