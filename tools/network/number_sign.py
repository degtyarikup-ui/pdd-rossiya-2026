"""Shared vector outlines; numbers never depend on installed browser or device fonts."""
import json
from pathlib import Path

DATA = json.loads((Path(__file__).resolve().parents[2]/'game_godot/signs/number_faces.json').read_text())
CODES = tuple(DATA['specs'])

def valid(code, value):
    if code not in CODES or type(value) not in (int,float): return False
    speed = code in ('3.24','3.25','4.6','4.7','6.2')
    return 0 < value <= (150 if speed else 99999) and (value == int(value) if speed else abs(value*100-round(value*100))<1e-6)

def svg(code, value):
    if not valid(code, value):
        raise ValueError('Скорость должна быть целым числом от 1 до 150')
    glyphs = [DATA['glyphs'][digit] for digit in format(value, 'g').replace('.', ',')]
    width = sum(g['advance'] for g in glyphs)
    x0,y0,w,h=DATA['specs'][code]['rect']
    if code in ('3.24','3.25'): x0,y0,w,h=27,28.5,46,29
    sx,sy = (1,1) if code in ('3.24','3.25') else (DATA['specs'][code]['size'][0]/100,DATA['specs'][code]['size'][1]/100)
    scale = min(h*sy/(DATA['top']-DATA['bottom']), w*sx/width)
    x, y = x0+w/2-width*scale/sx/2, y0+h/2+(DATA['top']+DATA['bottom'])*scale/sy/2
    y = DATA['specs'][code].get('baseline', y)
    paths, offset = [], 0
    for glyph in glyphs:
        paths.append(f'<path transform="translate({offset:.9f} 0)" d="{glyph["path"]}"/>')
        offset += glyph['advance']
    number = f'<g transform="translate({x:.9f} {y:.9f}) scale({scale/sx:.9f} {-scale/sy:.9f})">'+''.join(paths)+'</g>'
    return DATA['templates'][code].replace('{{number}}',number)
