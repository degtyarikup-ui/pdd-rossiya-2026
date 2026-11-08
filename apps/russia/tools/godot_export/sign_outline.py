"""Game faces for the app's sign SVGs: no catalogue outline, and the silhouette the shader clips to.

The app draws a thin black line around every sign so that it stays visible on a white screen. Real
signs have no such line, so in the game it becomes part of the white rim. A white plate without a
border of its own (8.x, 5.23.1, the end-of-restriction circles) keeps it as its black frame.

The shader cuts each face with an analytic contour. Its shape and corner radius are fitted here to
the rendered drawing, so corners neither protrude past the rim nor cut into it.

Requires `rsvg-convert` (Homebrew `librsvg`), numpy and Pillow.
"""
import io
import math
import re
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 360  # analysis pixels along the longer side of the canvas
MARGIN = 4
BAND = .045  # the catalogue outline lies within this share of the sign's size from its outer edge
DARK = re.compile(r'^(#000|#000000|black|#0c0e0f|#1d1d1b|#111|#111111|#151515|#181818|#1a1a1a|#222|#231f20)$', re.I)
SANDWICH = '#181818'  # newer sources: a dark band between the outer white rim and an inner white one
MAX_FIT_ERROR = .01  # above this share of mismatched area the shader follows the picture's alpha
DRAWABLE = ('path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'line')


def render(svg, size=SIZE):
    """RGBA floats with the canvas's longer side at `size` pixels."""
    png = subprocess.run(['rsvg-convert', '-f', 'png'], input=svg.encode(), capture_output=True, check=True).stdout
    w, h = Image.open(io.BytesIO(png)).size
    zoom = size / max(w, h)
    png = subprocess.run(['rsvg-convert', '-z', f'{zoom:.6f}', '-f', 'png'], input=svg.encode(),
                         capture_output=True, check=True).stdout
    image = np.asarray(Image.open(io.BytesIO(png)).convert('RGBA')).astype(np.float32) / 255
    # Panels cut from a sheet fill their canvas: a transparent margin keeps the outer edge visible.
    return np.pad(image, ((MARGIN, MARGIN), (MARGIN, MARGIN), (0, 0)))


def _exterior(mask):
    image = Image.fromarray(np.pad(mask, 1).astype(np.uint8) * 255).copy()
    ImageDraw.floodfill(image, (0, 0), 128)
    return (np.asarray(image) == 128)[1:-1, 1:-1]


def _dilate(mask, radius):
    image = Image.fromarray(mask.astype(np.uint8) * 255)
    return np.asarray(image.filter(ImageFilter.MaxFilter(2 * max(1, round(radius)) + 1))) > 0


def _attr(attrs, name):
    m = re.search(rf'(?:^|\s){name}\s*=\s*["\']([^"\']*)["\']', attrs) \
        or re.search(rf'(?:^|[;"\'\s]){name}\s*:\s*([^;"\']+)', attrs)
    return m.group(1).strip() if m else None


def _elements(svg):
    """Drawable tags in document order: (start, end, stroke, fill, parent_content_start)."""
    found, stack = [], []  # (stroke, fill, content_start) of open containers
    for m in re.finditer(r'<(/?)([\w:]+)\b([^>]*?)(/?)>', svg, re.S):
        closing, tag, attrs, selfclose = m.groups()
        if closing:
            if stack:
                stack.pop()
            continue
        stroke, fill = _attr(attrs, 'stroke'), _attr(attrs, 'fill')
        inherited = lambda i: next((s[i] for s in reversed(stack) if s[i] is not None), None)
        if tag in DRAWABLE:
            # SVG paints an unspecified fill black.
            found.append((m.start(), m.end(), stroke or inherited(0), fill or inherited(1) or '#000',
                          stack[-1][2] if stack else 0))
        if not selfclose:
            stack.append((stroke, fill, m.end()))
    return found


def _set(tag, attr, value):
    tag = re.sub(rf'(\s){attr}\s*=\s*["\'][^"\']*["\']', r'\1', tag)
    tag = re.sub(rf'(style\s*=\s*["\'][^"\']*?)(?<![\w-]){attr}\s*:\s*[^;"\']+;?', r'\1', tag)
    return re.sub(r'^<([\w:]+)', rf'<\1 {attr}="{value}"', tag)


def _edit(svg, edits):
    """edits: (start, end, replacement); inserts have start == end."""
    out, last = [], 0
    for start, end, text in sorted(edits, key=lambda e: (e[0], e[1])):
        out += [svg[last:start], text]
        last = end
    return ''.join(out + [svg[last:]])


def _magenta(image):
    return (image[..., 0] > .7) & (image[..., 1] < .35) & (image[..., 2] > .7) & (image[..., 3] > .5)


def outline(svg):
    """The catalogue outline: [(start, end, attr, parent)], its pixel mask, the render and exterior."""
    base = render(svg)
    exterior = _exterior(base[..., 3] > .5)
    ys, xs = np.nonzero(~exterior)
    band = BAND * max(np.ptp(ys), np.ptp(xs))
    near = _dilate(exterior, band) & ~exterior
    edge = _dilate(exterior, 1.5) & ~exterior
    candidates = []
    for start, end, stroke, fill, parent in _elements(svg):
        if stroke and DARK.match(stroke):
            candidates.append((start, end, 'stroke', parent))
        elif fill and DARK.match(fill):
            candidates.append((start, end, 'fill', parent))
    # One render tags every candidate with its own colour; only those reaching the edge band are
    # confirmed one at a time (lettering adds dozens of dark shapes).
    tags = lambda i: '#%02X%02X%02X' % (0x31, 0x52 + i // 64, 0x73 + i % 64 * 2)
    tagged = render(_edit(svg, [(a, b, _set(svg[a:b], attr, tags(i))) for i, (a, b, attr, _) in enumerate(candidates)]))
    code = np.round(tagged[..., :3] * 255).astype(int)
    parts, mask = [], np.zeros(exterior.shape, bool)
    for i, (start, end, attr, parent) in enumerate(candidates):
        r, g, b = (int(tags(i)[k:k + 2], 16) for k in (1, 3, 5))
        if not ((code[..., 0] == r) & (code[..., 1] == g) & (code[..., 2] == b) & near).any():
            continue
        lit = _magenta(render(_edit(svg, [(start, end, _set(svg[start:end], attr, '#F0F'))])))
        if lit.sum() < 20 or (lit & near).sum() / lit.sum() < .9:
            continue
        # A filled ring is the outline only on the very edge (2.1 and 1.4.x draw real inner borders).
        fill = _attr(svg[start:end], 'fill') or ''
        if attr == 'fill' and fill.lower() != SANDWICH and (lit & edge).sum() < .5 * edge.sum():
            continue
        # A line around a panel (one of a composite sign included): closed (a concave chevron too)
        # or running all the way around its centre (5.40's red bar crosses it).
        closed = _dilate(lit, 1)
        yy, xx = np.nonzero(lit)
        around = np.unique(((np.arctan2(yy - yy.mean(), xx - xx.mean()) + math.pi) / (2 * math.pi) * 72).astype(int) % 72)
        if (~_exterior(closed) & ~closed).sum() > lit.sum() or len(around) >= 50:
            parts.append((start, end, attr, parent))
            mask |= lit
    return parts, mask, base, exterior


def _plate_frame(base, exterior, mask):
    """True when the app's line is the only black border of a white plate (8.x, 5.23.1, 3.31)."""
    scale = max(base.shape) / 100
    inner = _dilate(mask, 6 * scale) & ~_dilate(mask, .8 * scale) & ~exterior
    if not inner.any():
        return False
    rgb, alpha = base[..., :3], base[..., 3]
    coloured = ((rgb.max(-1) - rgb.min(-1)) > .3) | (alpha < .5)
    if coloured[inner].mean() > .25:
        return False  # a coloured field or a transparent gap: the line is only the app's outline
    # 2.1, 1.4.x and 6.16 draw their own black border just inside: that one stays.
    yy, xx = np.nonzero(inner & (rgb.max(-1) < .3) & (alpha > .5))
    cy, cx = (np.nonzero(mask)[k].mean() for k in (0, 1))
    around = np.unique(((np.arctan2(yy - cy, xx - cx) + math.pi) / (2 * math.pi) * 72).astype(int) % 72)
    return len(around) < 60


def game_svg(svg, plate=False):
    """The SVG without the catalogue outline; plates, white boards and outline-free art stay as drawn."""
    if plate:
        return svg
    parts, mask, base, exterior = outline(svg)
    if not parts or _plate_frame(base, exterior, mask):
        return svg
    edits = []
    for start, end, attr, parent in parts:
        tag = svg[start:end]
        edits.append((start, end, _set(tag, attr, '#FFF')))
        # A white underlay beneath the drawing closes the gap the line used to frame
        # (Sprite3D faces show the raw alpha, without the shader's contour).
        under = _set(_set(_set(tag, 'stroke', '#FFF' if attr == 'stroke' else 'none'), 'fill', '#FFF'), 'fill-rule', 'nonzero')
        under = re.sub(r'\sid\s*=\s*["\'][^"\']*["\']', '', under)
        edits.append((parent, parent, under if under.endswith('/>') else under[:-1].rstrip() + '/>'))
    game = _edit(svg, edits)
    # Newer sources draw the outer rim at 87 % opacity; on a real sign it is solid.
    game = game.replace('fill-opacity=".87" fill="#FFF"', 'fill="#FFF"')
    after = render(game)
    if after.shape != base.shape:
        raise ValueError('outline removal changed the canvas')
    # Antialiased edges that bordered the transparent gap now blend with white: only solid pixels count.
    scale = max(base.shape) / 100
    changed = (np.abs(after - base).max(-1) > .2) & ~_dilate(mask, scale) & (base[..., 3] > .98)
    if changed.sum() > 4 * scale * scale:
        raise ValueError(f'outline removal changed {changed.sum()} picture pixels')
    return game


# ---- silhouette fitting --------------------------------------------------------------------------
def _box(qx, qy, bx, by, r):
    dx, dy = np.abs(qx) - bx + r, np.abs(qy) - by + r
    return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0) - r


def _triangle(px, py, k, r):
    """Mirror of triangle_distance() in sign_face.gdshader."""
    a, b, c = (-k + r, 1 - r), (k - r, 1 - r), (0, -1 + r)
    dot = lambda u, v: u[0] * v[0] + u[1] * v[1]
    es = [(b[0] - a[0], b[1] - a[1]), (c[0] - b[0], c[1] - b[1]), (a[0] - c[0], a[1] - c[1])]
    vs = [(px - a[0], py - a[1]), (px - b[0], py - b[1]), (px - c[0], py - c[1])]
    s = np.sign(es[0][0] * es[2][1] - es[0][1] * es[2][0])
    dist, side = None, None
    for e, v in zip(es, vs):
        t = np.clip(dot(v, e) / dot(e, e), 0, 1)
        q = (v[0] - e[0] * t, v[1] - e[1] * t)
        d, w = dot(q, q), s * (v[0] * e[1] - v[1] * e[0])
        dist, side = (d, w) if dist is None else (np.minimum(dist, d), np.minimum(side, w))
    return -np.sqrt(dist) * np.sign(side) - r


def distance(shape, px, py, aspect, r):
    """Mirror of sign_face.gdshader: p spans the visible box, y down; units are half-heights."""
    if shape == 1:
        return np.hypot(px, py) - 1
    if shape == 2:
        h = (1 + r * .41421356) * .70710678 - r
        return _box(np.abs(px + py) * .70710678, np.abs(py - px) * .70710678, h + r, h + r, r)
    if shape == 3:
        return _box(px * aspect, py, aspect, 1, r)
    if shape in (4, 5):
        return _triangle(px * aspect, py if shape == 4 else -py, aspect, r)
    return np.maximum(np.maximum(np.abs(px), np.abs(py)), (np.abs(px) + np.abs(py)) * .70710678) - 1


def silhouette(svg):
    """{'shape', 'radius'} that best match the drawing; alpha (0) when no analytic shape fits."""
    filled = ~_exterior(render(svg)[..., 3] > .5)
    ys, xs = np.nonzero(filled)
    crop = filled[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = crop.shape
    gy, gx = np.mgrid[0:h, 0:w]
    py, px = (gy + .5) / h * 2 - 1, (gx + .5) / w * 2 - 1
    area = crop.sum()
    error = lambda shape, r: ((distance(shape, px, py, w / h, r) < 0) != crop).sum() / area
    best = (1.0, 0, 0.0)
    for shape in range(1, 7):
        if shape in (2, 3, 4, 5):
            top = .45 if shape in (4, 5) else .6
            _, coarse = min((error(shape, r), r) for r in np.arange(0, top + 1e-9, .02))
            fine = np.arange(max(0, coarse - .02), min(top, coarse + .02) + 1e-9, .0025)
            err, r = min((error(shape, r), r) for r in fine)
        else:
            err, r = error(shape, 0), 0.0
        best = min(best, (err, shape, float(r)))
    err, shape, r = best
    return {'shape': shape, 'radius': round(r, 4)} if err <= MAX_FIT_ERROR else {'shape': 0, 'radius': 0}
