#!/usr/bin/env python3
"""Surface audit of the game's junctions (see tools/game_tests/game-surface-audit.cjs).

Reads the flat class renders (asphalt, pavement, lawn, markings; 8 px/m) and
reports what looks broken: pavement spikes and corners sticking out, thin
slivers of lawn, narrow pavement islands inside the carriageway, asphalt
notches in a pavement, holes with no ground at all. Writes an annotated copy
of every image with findings to <dir>/marked/ and prints a summary.
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

PX = 8  # pixels per metre
CLASSES = {  # rendered colour -> class
    'R': (60, 60, 60), 'P': (200, 180, 140), 'L': (120, 200, 80),
    'M': (255, 255, 255), 'O': (255, 0, 255), 'N': (0, 0, 0),
}


def classify(img):
    a = np.asarray(img.convert('RGB')).astype(int)
    best = np.full(a.shape[:2], 1e9)
    out = np.full(a.shape[:2], 'N', dtype='<U1')
    for k, c in CLASSES.items():
        d = ((a - np.array(c)) ** 2).sum(axis=2)
        m = d < best
        out[m] = k
        best = np.minimum(best, d)
    # Markings may come out light grey rather than white: any bright,
    # neutral pixel is paint.
    neutral = (a.max(axis=2) - a.min(axis=2) < 30) & (a.min(axis=2) > 150)
    out[neutral] = 'M'
    # Antialiased edges mix pavement and asphalt into a brownish grey that is
    # nearer to lawn than to either: lawn has to be clearly green.
    green = (a[..., 1] - a[..., 0] > 40) & (a[..., 1] - a[..., 2] > 60)
    fake_lawn = (out == 'L') & ~green
    mix = a[fake_lawn]
    if len(mix):
        to_p = ((mix - np.array(CLASSES['P'])) ** 2).sum(axis=1)
        to_r = ((mix - np.array(CLASSES['R'])) ** 2).sum(axis=1)
        out[fake_lawn] = np.where(to_p < to_r, 'P', 'R')
    return out


def erode(m, k):
    r = k // 2
    p = np.pad(m, r, constant_values=True)
    out = np.ones_like(m)
    for dy in range(k):
        for dx in range(k):
            out &= p[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out


def dilate(m, k):
    r = k // 2
    p = np.pad(m, r, constant_values=False)
    out = np.zeros_like(m)
    for dy in range(k):
        for dx in range(k):
            out |= p[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out


def opening(m, k):
    return dilate(erode(m, k), k)


def components(mask, min_area, with_pixels=False):
    seen = np.zeros_like(mask)
    h, w = mask.shape
    found = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        q = deque([(y, x)]); seen[y, x] = True; pts = []
        while q:
            cy, cx = q.popleft(); pts.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
        if len(pts) >= min_area:
            ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
            box = (min(xs), min(ys), max(xs), max(ys), len(pts))
            found.append((box, pts) if with_pixels else box)
    return found


def short_runs(cls, inside, flank, max_len):
    """Pixels of class `inside` in a row/column run shorter than max_len that
    is bounded on both ends by class set `flank`."""
    h, w = cls.shape
    out = np.zeros((h, w), bool)
    for axis in (0, 1):
        c = cls if axis == 1 else cls.T
        o = out if axis == 1 else out.T
        for i in range(c.shape[0]):
            row = c[i]
            j = 0
            n = len(row)
            while j < n:
                if row[j] != inside:
                    j += 1; continue
                k = j
                while k < n and row[k] == inside:
                    k += 1
                if k - j < max_len and j > 0 and k < n and row[j - 1] in flank and row[k] in flank:
                    o[i, j:k] = True
                j = k
    return out


def in_road_island(lawn, road, start, limit=25000):
    """True when the lawn area containing `start` is an island in the
    carriageway: closed, not touching the image edge, and with asphalt all
    round it just beyond its thin kerb."""
    h, w = lawn.shape
    seen = {start}
    q = deque([start])
    while q:
        y, x = q.popleft()
        if y in (0, h - 1) or x in (0, w - 1) or len(seen) > limit:
            return False
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if lawn[ny, nx] and (ny, nx) not in seen:
                seen.add((ny, nx)); q.append((ny, nx))
    comp = np.zeros_like(lawn)
    ys, xs = zip(*seen)
    comp[list(ys), list(xs)] = True
    ring = dilate(comp, 13) & ~dilate(comp, 5)
    return ring.any() and road[ring].mean() > 0.7


def audit(path):
    cls = classify(Image.open(path))
    road = (cls == 'R') | (cls == 'M')
    pave, lawn = cls == 'P', cls == 'L'
    road_cls = np.where(road, 'R', cls)
    # One-pixel pavement lines are antialiased kerb edges, not pavement.
    road_cls[pave & ~opening(pave, 3)] = 'X'
    findings = []
    # Pavement spikes / corners sticking out (thinner than ~0.9 m).
    spikes = pave & ~opening(pave, 7)
    near_lawn = dilate(lawn, 5)
    for b, pts in components(spikes, 24, with_pixels=True):
        if max(b[2] - b[0], b[3] - b[1]) < 5:
            continue
        # The kerb edging a lawn island (median, roundabout centre, a taper
        # tip) is thin by design.
        if sum(near_lawn[y, x] for y, x in pts) > 0.4 * len(pts):
            continue
        findings.append(('spike', b))
    # Steps in a pavement's outer edge (a corner piece standing out of a
    # narrower pavement): a closing of the pavement fills the notch of lawn
    # beside the step, square corners stay as they are.
    closed = erode(dilate(pave, 21), 21)
    for b, pts in components(closed & lawn, 60, with_pixels=True):
        if in_road_island(lawn, road, pts[0]):
            continue  # the pointed nose of a median: its kerb closes over it
        findings.append(('pavement step', b))
    # A pavement piece standing out of the pavement it belongs to (a corner
    # square beside a narrower pavement): gone after an opening with a
    # square a bit narrower than an ordinary pavement (3.2 m).
    bumps = pave & ~opening(pave, 17)
    lawn_near = dilate(lawn, 5)
    for b, pts in components(bumps & ~spikes, 60, with_pixels=True):
        # Kerbs round lawn islands are thin by design.
        touching = [(y, x) for y, x in pts if lawn_near[y, x]]
        if touching:
            ty, tx = touching[0]
            ys, xs = np.nonzero(lawn[max(0, ty - 5):ty + 6, max(0, tx - 5):tx + 6])
            if len(ys) and in_road_island(lawn, road, (max(0, ty - 5) + ys[0], max(0, tx - 5) + xs[0])):
                continue
        # The end of a pavement tapering to nothing (the edge of town) is
        # by design: past one end of it the pavement only gets thinner.
        x0, y0, x1, y1, _ = b
        h, w = pave.shape
        pad = 6
        if y1 - y0 >= x1 - x0:  # runs along the image's vertical
            span = pave[:, max(0, x0 - pad):x1 + pad + 1]
            widths = span.sum(axis=1)
            inside = widths[y0:y1 + 1].max()
            ends = [widths[max(0, y0 - 16):y0], widths[y1 + 1:min(h, y1 + 17)]]
        else:
            span = pave[max(0, y0 - pad):y1 + pad + 1, :]
            widths = span.sum(axis=0)
            inside = widths[x0:x1 + 1].max()
            ends = [widths[max(0, x0 - 16):x0], widths[x1 + 1:min(w, x1 + 17)]]
        if any(e.size and e.max() < 0.6 * inside for e in ends):
            continue
        findings.append(('pavement bump', b))
    # Thin lawn slivers (gaps between road and pavement, or in a pavement).
    slivers = lawn & ~opening(lawn, 7)
    # Tips of tapering lawn islands (medians) are thin by design: only a
    # sliver with pavement along it is a gap.
    near_pave = dilate(pave, 3)
    near_road = dilate(road, 5)
    for b, pts in components(slivers, 24, with_pixels=True):
        if sum(near_pave[y, x] for y, x in pts) < 0.3 * len(pts):
            continue
        # The pointed tip of a lawn island in the carriageway (a median's
        # nose) is its designed shape.
        if in_road_island(lawn, road, pts[0]):
            continue
        findings.append(('lawn sliver', b))
    # A pavement island narrower than 3 m with asphalt on both sides.
    islands = short_runs(road_cls, 'P', {'R'}, 3 * PX)
    for b in components(islands, 30):
        findings.append(('pavement in road', b))
    # An asphalt notch narrower than 2 m cutting into a pavement.
    notches = short_runs(road_cls, 'R', {'P'}, 2 * PX)
    for b in components(notches, 20):
        findings.append(('asphalt notch', b))
    # Holes with no ground at all, away from the image border.
    holes = cls == 'N'
    for b in components(holes, 6):
        x0, y0, x1, y1, _ = b
        if x0 > 0 and y0 > 0 and x1 < cls.shape[1] - 1 and y1 < cls.shape[0] - 1:
            findings.append(('hole', b))
    return findings


def main(folder):
    marked = os.path.join(folder, 'marked')
    os.makedirs(marked, exist_ok=True)
    total = 0
    for name in sorted(os.listdir(folder)):
        if not name.endswith('.png'):
            continue
        path = os.path.join(folder, name)
        found = audit(path)
        if not found:
            continue
        total += len(found)
        img = Image.open(path).convert('RGB')
        d = ImageDraw.Draw(img)
        for kind, (x0, y0, x1, y1, area) in found:
            d.rectangle((x0 - 6, y0 - 6, x1 + 6, y1 + 6), outline=(255, 0, 0), width=3)
        img.save(os.path.join(marked, name))
        w, h = img.size
        summary = ', '.join(f'{k}@({((b[0] + b[2]) / 2 - w / 2) / PX:.0f},{(h / 2 - (b[1] + b[3]) / 2) / PX:.0f}m) {b[4]}px' for k, b in found)
        print(f'{name}: {summary}')
    print('findings:', total)
    return total


if __name__ == '__main__':
    # Exit status 1 when anything was found (for use as a check).
    sys.exit(1 if main(sys.argv[1] if len(sys.argv) > 1 else 'build/game_ui/surface-audit') else 0)
