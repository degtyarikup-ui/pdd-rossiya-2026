"""Sparse shoulder meshing: same triangles/blends, fewer allocations, safe bounded reuse.

An optional scene JSON argument profiles a copy of an authored draft. Nothing is saved.
"""
import copy
import json
import math
from pathlib import Path
import sys
import time
from unittest.mock import patch

from shapely.geometry import GeometryCollection, LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.prepared import prep
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build


def exhaustive(region, weights, _weights_many=None):
    """Pre-optimization reference: every .4 m cell in the full bounding rectangle."""
    covered = prep(region)
    verts, indices, shares, lookup = [], [], [], {}
    x0, z0, x1, z1 = region.bounds
    step = .4
    def vertex(x, z):
        key = (round(x, 3), round(z, 3))
        if key not in lookup:
            lookup[key] = len(verts) // 2
            verts.extend(key)
            shares.extend(weights(Point(*key)))
        return lookup[key]
    for ix in range(math.ceil((x1-x0)/step)):
        for iz in range(math.ceil((z1-z0)/step)):
            x, z = x0+ix*step, z0+iz*step
            cell = build.Polygon([(x,z),(x+step,z),(x+step,z+step),(x,z+step)])
            if not covered.intersects(cell):
                continue
            v, t = build.triangulate(cell if covered.contains(cell) else cell.intersection(region))
            ids = [vertex(v[i], v[i+1]) for i in range(0, len(v), 2)]
            indices.extend(ids[i] for i in t)
    return dict(id='rural_shoulder', y=build.ROAD_Y, layer='field', soil_colour='#96846b',
                soil_kind='gravel', colour='#96846b', verts=verts, idx=indices, shares=shares)


def canonical(surface):
    """Vertex numbering is immaterial; exact triangle positions and blends are not."""
    points = list(zip(surface['verts'][::2], surface['verts'][1::2]))
    vertices = [(p, tuple(surface['shares'][i*3:i*3+3])) for i, p in enumerate(points)]
    triangles = sorted(tuple(sorted(vertices[j] for j in surface['idx'][i:i+3]))
                       for i in range(0, len(surface['idx']), 3))
    return {k:v for k,v in surface.items() if k not in ('verts','idx','shares')}, triangles


def measure(fn):
    cells = 0
    polygon, batch_polygons = build.Polygon, build.geometry_polygons
    def count_polygon(*args, **kwargs):
        nonlocal cells
        cells += 1
        return polygon(*args, **kwargs)
    def count_polygons(coordinates):
        nonlocal cells
        cells += len(coordinates)
        return batch_polygons(coordinates)
    start = time.perf_counter()
    with patch.object(build, 'Polygon', count_polygon), patch.object(build, 'geometry_polygons', count_polygons):
        result = fn()
    return result, time.perf_counter()-start, cells


# Holes, disconnected patches, thin strips and lower-dimensional remnants must
# retain the original grid origin, clipped boundary detail and interpolation.
weights = lambda p: (p.x*.001, p.y*.001, 1-p.x*.001-p.y*.001)
cases = {
    'sparse cross': unary_union([box(-40,-1,40,1), box(-1,-40,1,40)]).difference(box(-.2,-.2,.2,.2)),
    'curved ring': Point(.123,-.257).buffer(5, quad_segs=12).difference(Point(.123,-.257).buffer(4.1, quad_segs=12)),
    'diagonal': LineString([(-14,-11),(-7,8),(13,4)]).buffer(.32),
    'separate': unary_union([box(-9.831,-7.224,-8.183,-6.944), box(11.432,9.001,11.499,9.304)]),
    'mixed dimensions': GeometryCollection([box(-5,-2,5,2).difference(box(-4,-1,4,1)), LineString([(-8,-6),(8,-6)])]),
}
for name, region in cases.items():
    expected, before, old_cells = measure(lambda: exhaustive(region, weights))
    actual, after, new_cells = measure(lambda: build.blended_shoulder(region, weights))
    assert canonical(actual) == canonical(expected), name+' changed triangles or blend weights'
    if name == 'sparse cross':
        assert new_cells < old_cells*.2, (new_cells, old_cells)
    print(f'PASS {name}: {before:.3f}s → {after:.3f}s, cells {old_cells} → {new_cells}', flush=True)


scene = dict(id='shoulder_performance', crop=90, roads=[
    dict(id='vertical',outer=[[-4.2,-90],[4.2,-90],[4.2,90],[-4.2,90]],walk=False,shoulder=2.5),
    dict(id='horizontal',outer=[[-90,-4.2],[90,-4.2],[90,4.2],[-90,4.2]],walk=False,shoulder=2.5),
], tracks=[dict(id='rail',render=True,railType='railway',points=[[-90,25],[90,25]])],
    actors=[],routes=[],markings=[],lawns=[])
scenes = [scene]
if len(sys.argv) > 1:
    scenes.append(json.loads(Path(sys.argv[1]).read_text()))
for source in scenes:
    before_source = copy.deepcopy(source)
    build._rural_shoulder_mesh.cache_clear()
    with patch.object(build, 'blended_shoulder', exhaustive):
        start=time.perf_counter();old=build.build(source);before=time.perf_counter()-start
    build._rural_shoulder_mesh.cache_clear()
    start=time.perf_counter();new=build.build(source);cold=time.perf_counter()-start
    start=time.perf_counter();warm=build.build(source);cached=time.perf_counter()-start
    assert source == before_source, 'preview mutated source'
    assert warm == new, 'cache changed generated geometry'
    assert len(new['surfaces']) == len(old['surfaces'])
    for a,b in zip(old['surfaces'],new['surfaces']):
        assert a['id'] == b['id']
        assert canonical(a) == canonical(b) if a['id']=='rural_shoulder' else a == b, a['id']
    assert {k:v for k,v in old.items() if k!='surfaces'} == {k:v for k,v in new.items() if k!='surfaces'}
    new_shoulder=next(s for s in new['surfaces'] if s['id']=='rural_shoulder')
    new_shoulder['verts'][0] += 500
    assert build.build(source) == warm, 'caller changed a retained mesh through shared lists'
    # Railway strokes can reuse the unchanged shoulder; the railway itself still rebuilds.
    changed=copy.deepcopy(source);changed['tracks'][0]['points']=[[-80,28],[80,28]]
    hits=build._rural_shoulder_mesh.cache_info().hits
    result=build.build(changed)
    assert build._rural_shoulder_mesh.cache_info().hits > hits
    assert result != warm and changed != source
    print(f'PASS {source["id"]}: total {before:.3f}s → cold {cold:.3f}s / cached {cached:.3f}s; source and all rendered triangles preserved',flush=True)

# Every weight dependency is part of the key, even with identical shoulder polygons.
region=box(-5,-2,5,2);roads=box(-2,-1,2,1);ends=LineString([(0,-2),(0,2)]);bounds=box(-8,-6,8,6)
build._rural_shoulder_mesh.cache_clear()
first=build.rural_shoulder_mesh(region,roads,ends,bounds)
for args in [(region,box(-3,-1,3,1),ends,bounds), (region,roads,LineString([(4,-2),(4,2)]),bounds),
             (region,roads,ends,box(-6,-3,6,3)), (box(-5,-2,4.6,2),roads,ends,bounds)]:
    misses=build._rural_shoulder_mesh.cache_info().misses
    assert build.rural_shoulder_mesh(*args) != first
    assert build._rural_shoulder_mesh.cache_info().misses == misses+1
for n in range(10):
    build.rural_shoulder_mesh(box(0,0,.4,.4),roads,ends,box(-8,-6,8+n,6))
assert build._rural_shoulder_mesh.cache_info().currsize == 8
print('PASS cache key dependencies, isolated mutable results and eight-entry bound')
