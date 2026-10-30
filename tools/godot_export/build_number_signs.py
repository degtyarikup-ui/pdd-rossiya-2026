"""Generate shared vector templates for editable speed signs (requires fonttools)."""
import json
import re
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
for digit in '0123456789,':
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
# Regions are normalized to the catalogue SVG viewport, excluding units and arrows.
# x/y/width/height, default, unit, background, foreground, optional rotation.
specs = {
 '3.24':([27,33,46,34],50,'км/ч','#fff','#000',0),
 '3.25':([27,33,46,34],50,'км/ч','#fff','#7f7f7f',0),
 '3.11':([28,31,29,42],7,'т','#fff','#000',0),
 '3.12':([35,20,22,29],6,'т','#fff','#000',0),
 '3.13':([29,24,42,35],4.5,'м','#fff','#000',0),
 '3.14':([28,28,44,34],2.7,'м','#fff','#000',0),
 '3.15':([37,57,26,19],10,'м','#fff','#000',0),
 '3.16':([34,20,27,19],70,'м','#fff','#000',0),
 '4.6':([26,30,48,37],50,'км/ч','#0d69e1','#fff',0),
 '4.7':([26,30,48,37],50,'км/ч','#0d69e1','#fff',0),
 '6.2':([23,29,54,43],50,'км/ч','#0d69e1','#fff',0),
 '6.3.2':([20,38,18,17],15,'м','#0d69e1','#fff',0),
 '8.1.1':([12,29,55,42],300,'м','#fff','#000',0),
 '8.1.2':([13,52,54,32],250,'м','#fff','#000',0),
 '8.1.3':([7,29,37,43],100,'м','#fff','#000',0),
 '8.1.4':([36,27,41,46],300,'м','#fff','#000',0),
 '8.2.1':([23,25,36,46],100,'м','#fff','#000',0),
 '8.2.2':([22,50,57,24],10,'м','#fff','#000',0),
 '8.2.5':([6,27,29,46],30,'м','#fff','#000',0),
 '8.2.6':([50,27,28,46],25,'м','#fff','#000',0),
 '1.13':([35,47,22,18],12,'%', '#fff','#000',22),
 '1.14':([31,52,22,18],10,'%', '#fff','#000',-22),
}
result['specs']={}
for code,(rect,default,unit,bg,fg,angle) in specs.items():
 root=ET.parse(ROOT/f'game_godot/signs/{code}.svg').getroot()
 size=[float(root.get('width')),float(root.get('height'))]
 result['specs'][code]={'rect':rect,'default':default,'unit':unit,'size':size,'angle':angle}
 if code in ('3.24','3.25'): continue
 if code in ('1.13','1.14'):
  symbol=list(root.iter())[-1]
  parts=re.findall('M[^M]*',symbol.get('d'))
  symbol.set('d',parts[0]+''.join(parts[3:]))
 original=ET.tostring(root,encoding='unicode')
 x,y,w,h=rect
 rotation=f'rotate({angle} {x+w/2} {y+h/2})'
 overlay=f'<g transform="{rotation}"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{bg}"/><g fill="{fg}">{{{{number}}}}</g></g>'
 if code in ('1.13','1.14'):
  overlay=f'<g transform="{rotation}" fill="{fg}">{{{{number}}}}</g>'
 # Cancellation stripe remains above the replacement numeral.
 if code=='4.7': overlay+='<defs><clipPath id="disc"><ellipse cx="50" cy="50" rx="38" ry="44"/></clipPath></defs><path clip-path="url(#disc)" d="M20 80 L80 20" stroke="#ff0000" stroke-width="9"/>'
 # Godot's SVG loader does not apply nested SVG viewports like browsers do.
 # Keep the original root viewport and map only the numeric overlay into it.
 vx,vy,vw,vh=map(float,root.get('viewBox',f'0 0 {size[0]} {size[1]}').split())
 result['templates'][code]=f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{vx} {vy} {vw} {vh}">'+''.join(ET.tostring(c,encoding='unicode') for c in root)+f'<g transform="translate({vx} {vy}) scale({vw/100} {vh/100})">'+overlay+'</g></svg>'

js=ROOT/'tools/network/editor/sign_mount.js'
text=js.read_text()
import re
text=re.sub(r'  const NUMBER_SPECS = .*?;\n','',text)
text=text.replace('  const FACE_KEYS', '  const NUMBER_SPECS = '+json.dumps(result['specs'],ensure_ascii=False,separators=(',',':'))+';\n  const FACE_KEYS')
js.write_text(text)
(ROOT/'game_godot/signs/number_faces.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
