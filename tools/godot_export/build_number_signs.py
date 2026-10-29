"""Generate shared vector templates for editable speed signs (requires fonttools)."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen

ROOT = Path(__file__).resolve().parents[2]
font = TTFont(ROOT/'assets/fonts/Onest-Bold.ttf')
glyphs = font.getGlyphSet()
result = {'glyphs': {}, 'templates': {}}
ys = []
for digit in '0123456789':
    glyph = glyphs[font.getBestCmap()[ord(digit)]]
    pen = SVGPathPen(glyphs); glyph.draw(pen)
    bounds = BoundsPen(glyphs); glyph.draw(bounds)
    ys.extend([bounds.bounds[1], bounds.bounds[3]])
    result['glyphs'][digit] = {'path': pen.getCommands(), 'advance': glyph.width}
result.update(top=max(ys), bottom=min(ys))
ET.register_namespace('', 'http://www.w3.org/2000/svg')
for code, colour in [('3.24','#000000'), ('3.25','#7F7F7F')]:
    root = ET.parse(ROOT/f'game_godot/signs/{code}.svg').getroot()
    parent = root[0]
    # The catalogue's number is the only nested group, after its border and before cancellation stripes.
    for i, child in enumerate(parent):
        if child.tag.endswith('}g'):
            parent.remove(child)
            placeholder = ET.Element('NUMBER'); parent.insert(i,placeholder)
            break
    result['templates'][code] = ET.tostring(root,encoding='unicode').replace('<NUMBER />','{{number}}')
    result['templates'][code] = result['templates'][code].replace('{{number}}', '<g fill="'+colour+'" fill-rule="nonzero">{{number}}</g>')
(ROOT/'game_godot/signs/number_faces.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
