"""Pointed yellow zigzags with independent depth, spacing and paint thickness."""
import math
from shapely.geometry import Polygon

DEFAULTS = {'depth':1.2, 'step':1.5, 'width':.12, 'side':1}
LIMITS = {'length':(2,60), 'depth':(.4,3), 'step':(.6,4), 'width':(.06,.3)}

def error(m):
    number = lambda v: isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v)
    pts = m.get('points')
    if not isinstance(pts,list) or len(pts)!=2 or any(not isinstance(p,(list,tuple)) or len(p)!=2 or not all(number(v) for v in p) for p in pts):
        return 'задайте начало и конец остановки вдоль бордюра'
    if not 2-1e-6 <= math.dist(*pts) <= 60+1e-6: return 'длина остановки должна быть от 2 до 60 м'
    for key in ('depth','step','width'):
        value=m.get(key,DEFAULTS[key])
        lo,hi=LIMITS[key]
        if not number(value) or not lo<=value<=hi:
            title={'depth':'глубина зубцов','step':'шаг зубцов','width':'толщина линии'}[key]
            return f'{title}: задайте значение от {lo} до {hi} м'
    if type(m.get('side',1)) is not int or m.get('side',1) not in (-1,1): return 'выберите сторону зубцов'
    if m.get('colour','yellow') != 'yellow': return 'разметка остановки должна быть жёлтой'
    return None

def line(m):
    if error(m): return []
    a,b=m['points']; length=math.dist(a,b)
    dx,dz=(b[0]-a[0])/length,(b[1]-a[1])/length
    count=max(1,math.floor(length/m.get('step',1.5)+.5))
    depth,side=m.get('depth',1.2),m.get('side',1)
    at=lambda t,v: [a[0]+dx*t-dz*v*side,a[1]+dz*t+dx*v*side]
    out=[at(0,0)]
    for i in range(count): out.extend([at((i+.5)*length/count,depth),at((i+1)*length/count,0)])
    return out

def polygons(m):
    points=line(m)
    if not points:return []
    half=m.get('width',.12)/2
    normals=[]
    for a,b in zip(points,points[1:]):
        n=math.dist(a,b);normals.append([-(b[1]-a[1])/n,(b[0]-a[0])/n])
    offsets=[]
    for i,p in enumerate(points):
        if i==0:offsets.append([v*half for v in normals[0]])
        elif i==len(points)-1:offsets.append([v*half for v in normals[-1]])
        else:
            a,b=normals[i-1],normals[i];s=[a[0]+b[0],a[1]+b[1]];den=s[0]*b[0]+s[1]*b[1]
            offsets.append([v*half/den for v in s])
    edge=lambda side: [[v+offsets[i][k]*side for k,v in enumerate(p)] for i,p in enumerate(points)]
    return [edge(1)+list(reversed(edge(-1)))]

def geometry(m):
    rings=polygons(m)
    return Polygon(rings[0]).buffer(0) if rings else Polygon()
