"""Authored road elevation and tessellation of the derived surface meshes."""
import math


def height(data, x, z):
    points = data.get("profile", [])
    y = 0.0
    if points:
        y = points[0][1] if z <= points[0][0] else points[-1][1]
        for (start, low), (end, high) in zip(points, points[1:]):
            if start <= z <= end:
                t = (z - start) / (end - start)
                y = low + (high - low) * t * t * (3 - 2*t)
                break
        # Blend back to the level of connecting streets at the side boundaries.
        crop = points[-1][0]
        t = min(1.0, max(0.0, (crop - abs(x)) / min(12.0, crop)))
        y *= t * t * (3 - 2*t)

    for bump in data.get("bumps", []):
        bx, bz = bump["centre"]
        side = max(0, min(1, (bump["width"]/2 - abs(x-bx)) / .15))
        u = abs(z-bz) / (bump["length"]/2)
        if u < 1:
            y += bump["height"] * (1 + math.cos(math.pi*u)) * .5 * side
    return y


def validation_error(scene):
    data = scene.get("terrain")
    if data is None:
        return None
    if not isinstance(data, dict):
        return "Некорректный формат рельефа."
    crop = scene.get("crop", 90)
    def finite(value):
        return type(value) in (int, float) and math.isfinite(value)

    if not finite(crop) or crop <= 0:
        return "Размер сцены должен быть больше нуля."
    points = data.get("profile", [])
    if not isinstance(points, list) or len(points) == 1 or len(points) > 64:
        return "Профиль должен содержать от 2 до 64 точек."
    for point in points:
        if not isinstance(point, list) or len(point) != 2 or not all(map(finite, point)):
            return "У каждой точки должны быть указаны положение и высота."
        if abs(point[0]) > crop or not 0 <= point[1] <= 30:
            return "Поместите точки внутри сцены на высоте от 0 до 30 м."
    if any(b[0] - a[0] <= .1 for a, b in zip(points, points[1:])):
        return "Между соседними точками должно быть больше 10 см."
    if points and (points[0] != [-crop, 0] or points[-1] != [crop, 0]):
        return "Крайние точки профиля должны лежать на границах сцены на высоте 0 м."
    bumps = data.get("bumps", [])
    if not isinstance(bumps, list) or len(bumps) > 16:
        return "В сцене может быть до 16 неровностей."
    for bump in bumps:
        centre = bump.get("centre") if isinstance(bump, dict) else None
        if not isinstance(centre, list) or len(centre) != 2 or not all(map(finite, centre)):
            return "Укажите положение неровности внутри сцены."
        if not all(finite(bump.get(k)) for k in ("width", "length", "height")):
            return "Укажите ширину, длину и высоту неровности."
        if not (.5 <= bump["width"] <= 30 and .5 <= bump["length"] <= 30 and .01 <= bump["height"] <= .2):
            return "Ширина и длина неровности должны быть от 0,5 до 30 м, высота — от 1 до 20 см."
        if abs(centre[0]) > crop or abs(centre[1]) + bump["length"]/2 >= crop:
            return "Переместите неровность внутрь сцены."
    for node in (scene.get("layout") or {}).get("nodes", []):
        x, z = node.get("x"), node.get("z")
        if finite(x) and finite(z) and max(abs(x), abs(z)) >= crop-.01 and abs(height(data, x, z)) >= .001:
            return "Переместите неровность дальше от выезда. Высота на стыке дорог должна быть 0 м."
    return None


def clip(poly, axis, at, above):
    """Clip a convex polygon, interpolating base elevation and surface colours."""
    result = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        a_inside = a[axis] >= at if above else a[axis] <= at
        b_inside = b[axis] >= at if above else b[axis] <= at
        if a_inside:
            result.append(a)
        if a_inside != b_inside:
            t = (at - a[axis]) / (b[axis] - a[axis])
            vertex = [u + (v-u)*t for u, v in zip(a, b)]
            vertex[axis] = at
            result.append(vertex)
    return result


def strips(poly, axis, cuts):
    low = min(p[axis] for p in poly)
    high = max(p[axis] for p in poly)
    inside = [v for v in cuts if low+1e-7 < v < high-1e-7]
    if not inside:
        yield poly
        return
    for start, end in zip([low, *inside], [*inside, high]):
        part = clip(clip(poly, axis, start, True), axis, end, False)
        if len(part) >= 3:
            yield part


def deform(scene, result):
    data = scene.get("terrain")
    if not data:
        return result
    crop = float(scene.get("crop", 90))
    points = data.get("profile", [])
    zcuts, xcuts = set(), set()
    if any(h for _, h in points):
        zcuts.update(z for z, _ in points)
        zcuts.update(range(math.floor(-crop), math.ceil(crop)+1))
        width = min(12, crop)
        xcuts.update(side*(crop-width*i/6) for side in (-1, 1) for i in range(7))
    for bump in data.get("bumps", []):
        x, z = bump["centre"]
        length, half_width = bump["length"], bump["width"]/2
        zcuts.update(z-length/2+length*i/24 for i in range(25))
        xcuts.update((x-half_width, x-half_width+.15, x+half_width-.15, x+half_width))
    if not zcuts:
        return result
    zcuts, xcuts = sorted(zcuts), sorted(xcuts)
    for surface in result["surfaces"]:
        verts, heights, indices, shares = [], [], [], []
        base_heights = surface.get("heights")
        vertex_ids = {}
        for k in range(0, len(surface["idx"]), 3):
            tri = []
            for i in surface["idx"][k:k+3]:
                x, z = surface["verts"][2*i:2*i+2]
                vertex = [x, z, base_heights[i] if base_heights is not None else surface["y"]]
                if "shares" in surface:
                    vertex.extend(surface["shares"][3*i:3*i+3])
                tri.append(vertex)
            for row in strips(tri, 1, zcuts):
                for piece in strips(row, 0, xcuts):
                    a = piece[0]
                    for b, c in zip(piece[1:], piece[2:]):
                        if abs((b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])) < 1e-10:
                            continue
                        for vertex in (a, b, c):
                            key = tuple(vertex)
                            if key not in vertex_ids:
                                vertex_ids[key] = len(heights)
                                verts.extend(vertex[:2])
                                heights.append(vertex[2] + height(data, *vertex[:2]))
                                shares.extend(vertex[3:])
                            indices.append(vertex_ids[key])
        surface.update(verts=verts, heights=heights, idx=indices)
        if "shares" in surface:
            surface["shares"] = shares

    kerbs = result["kerbs"]
    segments, heights = [], []
    for i in range(0, len(kerbs["segs"]), 4):
        ax, az, bx, bz = kerbs["segs"][i:i+4]
        n = max(1, math.ceil(math.hypot(bx-ax, bz-az)))
        for j in range(n):
            for k in (j, j+1):
                x, z = ax+(bx-ax)*k/n, az+(bz-az)*k/n
                segments.extend((x, z))
                heights.append(height(data, x, z))
    kerbs.update(segs=segments, heights=heights)
    return result
