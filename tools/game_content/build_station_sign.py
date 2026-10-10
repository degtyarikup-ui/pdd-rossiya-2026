#!/usr/bin/env python3
"""Generate one low-poly station lettering mesh from bundled Onest ExtraBold.

Requires fonttools; run from the repository root. No font is loaded by the game.
"""
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from pathlib import Path
import json
font=TTFont('assets/fonts/Onest-ExtraBold.ttf'); glyphs=font.getGlyphSet(); cmap=font.getBestCmap(); scale=1/font['head'].unitsPerEm; commands=[]; offset=0
class Pen(BasePen):
 def point(self,p):return [round((p[0]+offset)*scale,5),round(p[1]*scale,5)]
 def _moveTo(self,p):commands.append(['moveTo',*self.point(p)])
 def _lineTo(self,p):commands.append(['lineTo',*self.point(p)])
 def _curveToOne(self,a,b,c):commands.append(['bezierCurveTo',*self.point(a),*self.point(b),*self.point(c)])
 def _qCurveToOne(self,a,b):commands.append(['quadraticCurveTo',*self.point(a),*self.point(b)])
 def _closePath(self):commands.append(['closePath'])
for letter in 'ГазЛукПук':
 name=cmap[ord(letter)]; glyphs[name].draw(Pen(glyphs));offset+=font['hmtx'][name][0]
out='''// Outlines from bundled Onest ExtraBold: one extruded mesh, no runtime font/texture.
(() => {
  'use strict';
  const outlines = OUTLINES;
  window.PDD_STATION_SIGN = () => {
    const path = new THREE.ShapePath();
    for (const [method, ...args] of outlines) {
      if (method === 'closePath') path.currentPath.closePath();
      else path[method](...args);
    }
    const geometry = new THREE.ExtrudeGeometry(path.toShapes(), {depth: .12, bevelEnabled: false, curveSegments: 3});
    geometry.computeBoundingBox();
    const bounds = geometry.boundingBox, width = bounds.max.x - bounds.min.x;
    geometry.translate(-(bounds.min.x + bounds.max.x) / 2, -bounds.min.y, 0);
    geometry.scale(10 / width, 10 / width, 1);
    const mesh = new THREE.Mesh(geometry, new THREE.MeshLambertMaterial({color: 0xFFFFFF}));
    mesh.userData.stationLettering = true;
    return mesh;
  };
})();
'''.replace('OUTLINES',json.dumps(commands,separators=(',',':')))
Path('assets/game/station-sign.js').write_text(out)
