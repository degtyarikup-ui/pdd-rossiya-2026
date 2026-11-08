"""Smooth outlines of roads, islands and lawns (the scene's source data, game_godot/network/<id>.json).

The outlines are traced from the baked junction scenes, and the trace is a staircase: neighbouring points
0.2-0.5 m apart step by a few tenths of a metre, so the kerb and the edge line wobble on screen. The
smoothing is a Gaussian along the outline's length (SIGMA metres), resampled every STEP metres.

The outline's points on the crop square's edge are pinned: a road is cut there and must meet the
neighbouring scene (stitching), so the cut stays exactly where it is.
"""
import numpy as np

SIGMA = 1.0     # the length of the smoothing (m): the staircase is 0.2-0.5 m, real bends are longer
STEP = 0.25     # resampling step of the smoothed outline (m)
PIN = 0.05      # a point this close to the crop square's edge is part of the cut, and is kept


def _on_crop_edge(p, crop: float) -> bool:
    return abs(abs(p[0]) - crop) < PIN or abs(abs(p[1]) - crop) < PIN


def _resample(pts: np.ndarray, step: float) -> np.ndarray:
    """The polyline pts (open) at equal spacing `step`, both ends kept."""
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    total = cum[-1]
    if total <= step:
        return pts
    n = max(2, int(round(total / step)) + 1)
    at = np.linspace(0.0, total, n)
    return np.column_stack([np.interp(at, cum, pts[:, 0]), np.interp(at, cum, pts[:, 1])])


def _gauss(n_samples: int) -> np.ndarray:
    half = max(1, int(round(3 * SIGMA / STEP)))
    x = np.arange(-half, half + 1)
    k = np.exp(-0.5 * (x / (SIGMA / STEP)) ** 2)
    return k / k.sum()


def _smooth_open(pts: np.ndarray) -> np.ndarray:
    """An open chain: its two ends stay put, the middle is smoothed (ends repeated as padding)."""
    if len(pts) < 3:
        return pts
    res = _resample(pts, STEP)
    k = _gauss(len(res))
    half = len(k) // 2
    padded = np.vstack([np.repeat(res[:1], half, axis=0), res, np.repeat(res[-1:], half, axis=0)])
    out = np.column_stack([np.convolve(padded[:, 0], k, mode="valid"), np.convolve(padded[:, 1], k, mode="valid")])
    out[0], out[-1] = res[0], res[-1]
    return out


def _smooth_closed(pts: np.ndarray) -> np.ndarray:
    """A closed ring without pinned points: smoothed all round."""
    closed = np.vstack([pts, pts[:1]])
    res = _resample(closed, STEP)[:-1]
    k = _gauss(len(res))
    half = len(k) // 2
    idx = (np.arange(len(res))[:, None] + np.arange(-half, half + 1)[None, :]) % len(res)
    return np.column_stack([(res[idx, 0] * k).sum(axis=1), (res[idx, 1] * k).sum(axis=1)])


def smooth_ring(ring, crop: float = 90.0) -> list:
    """A ring [[x, z], ...] (closed by its first point, or not), smoothed; the pinned points are kept."""
    pts = np.array([[float(p[0]), float(p[1])] for p in ring])
    if len(pts) > 1 and np.allclose(pts[0], pts[-1]):
        pts = pts[:-1]
    if len(pts) < 4:
        return [[round(x, 3), round(z, 3)] for x, z in pts]
    pinned = [i for i, p in enumerate(pts) if _on_crop_edge(p, crop)]
    if not pinned:
        out = _smooth_closed(pts)
    else:
        # Chains between pinned points, each smoothed with its ends fixed.
        parts = []
        n = len(pts)
        for a_i, a in enumerate(pinned):
            b = pinned[(a_i + 1) % len(pinned)]
            idx = [a]
            j = a
            while j != b:
                j = (j + 1) % n
                idx.append(j)
            parts.append(_smooth_open(pts[idx]))
        out = np.vstack([p[:-1] for p in parts])
    # The resampled outline has far more points than the shape needs: 2 cm is below anything the game shows.
    from shapely.geometry import Polygon
    simple = Polygon(out).simplify(0.02, preserve_topology=True)
    if simple.is_empty or simple.geom_type != "Polygon":
        return [[round(float(x), 3), round(float(z), 3)] for x, z in out]
    ring = list(simple.exterior.coords)[:-1]
    return [[round(float(x), 3), round(float(z), 3)] for x, z in ring]
