"""Shared vector outlines; numbers never depend on installed browser or device fonts."""
import json
from pathlib import Path

DATA = json.loads((Path(__file__).resolve().parents[2]/'game_godot/signs/number_faces.json').read_text())
CODES = ('3.24','3.25')

def valid(code, value):
    return code in CODES and type(value) is int and 1 <= value <= 150

def svg(code, value):
    if not valid(code, value):
        raise ValueError('Скорость должна быть целым числом от 1 до 150')
    glyphs = [DATA['glyphs'][digit] for digit in str(value)]
    width = sum(g['advance'] for g in glyphs)
    scale = min(29/(DATA['top']-DATA['bottom']), 46/width)
    x, y = 50-width*scale/2, 43+(DATA['top']+DATA['bottom'])*scale/2
    paths, offset = [], 0
    for glyph in glyphs:
        paths.append(f'<path transform="translate({offset} 0)" d="{glyph["path"]}"/>')
        offset += glyph['advance']
    number = f'<g transform="translate({x} {y}) scale({scale} {-scale})">'+''.join(paths)+'</g>'
    return DATA['templates'][code].replace('{{number}}',number)
