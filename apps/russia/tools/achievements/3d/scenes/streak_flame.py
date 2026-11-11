"""Flame silhouette as closed cubic Bezier paths, y up, normalized to 0..1.

Each path: list of (anchor, handle_in, handle_out). Shared by the 2D preview
and the Blender scene builder so both see exactly the same shape.
"""

OUTER = [
    ((0.50, 0.00), (0.74, 0.00), (0.26, 0.00)),
    ((0.09, 0.36), (0.07, 0.17), (0.11, 0.52)),
    ((0.21, 0.71), (0.15, 0.63), (0.25, 0.64)),   # left tongue tip (cusp)
    ((0.34, 0.57), (0.29, 0.57), (0.37, 0.79)),   # notch
    ((0.57, 1.00), (0.49, 0.91), (0.75, 0.83)),   # main tip (cusp)
    ((0.91, 0.42), (0.93, 0.63), (0.89, 0.18)),
]

INNER = [
    ((0.52, 0.09), (0.66, 0.09), (0.38, 0.09)),
    ((0.27, 0.33), (0.27, 0.20), (0.27, 0.47)),
    ((0.50, 0.66), (0.43, 0.56), (0.61, 0.57)),   # tip (cusp)
    ((0.76, 0.31), (0.77, 0.45), (0.75, 0.17)),
]


def sample(path, steps=24):
    pts = []
    n = len(path)
    for i in range(n):
        p0, _, h0 = path[i]
        p1, h1, _ = path[(i + 1) % n]
        for s in range(steps):
            t = s / steps
            u = 1 - t
            x = u**3 * p0[0] + 3 * u * u * t * h0[0] + 3 * u * t * t * h1[0] + t**3 * p1[0]
            y = u**3 * p0[1] + 3 * u * u * t * h0[1] + 3 * u * t * t * h1[1] + t**3 * p1[1]
            pts.append((x, y))
    return pts
