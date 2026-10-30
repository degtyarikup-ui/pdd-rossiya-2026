"""Authored railway beds and level crossings, shared by the editor and Godot.

All details are batched by material. No random state, extra models or per-sleeper
draw calls. The source roads/routes are untouched; only derived surfaces are cut.
"""
import math

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

HALF_BED = 1.8
RAMP = 1.2
GAUGE = 1.524


def lines(scene, sample):
    result = []
    for track in scene.get("tracks", []):
        if track.get("render") is not True or track.get("railType") != "railway":
            continue
        points = track.get("points", [])
        if len(points) < 2:
            continue
        line = LineString(sample(points))
        if line.length > .01:
            result.append(line)
    return result


def geometry(scene, road, raised, triangulate, sample):
    paths = lines(scene, sample)
    if not paths:
        return {"surfaces": [], "bed": Polygon(), "opening": Polygon()}
    crop = float(scene.get("crop", 90))
    box = Polygon([(-crop, -crop), (crop, -crop), (crop, crop), (-crop, crop)])
    axis = unary_union(paths)
    bed = unary_union([p.buffer(HALF_BED, cap_style=2, join_style=1) for p in paths]).intersection(box)
    opening = bed.buffer(RAMP, join_style=1).intersection(box)
    crossing = bed.intersection(road.union(raised))
    open_bed = bed.difference(crossing)
    sleeper_clearance = crossing.buffer(.16)
    surfaces = []

    def emit(name, shape, y, colour, layer="", height=None):
        shape = shape.intersection(box)
        if shape.is_empty or shape.area < .000001:
            return
        verts, idx = triangulate(shape)
        # The shared exporter rounds coordinates to millimetres. Thin curved
        # details can collapse or flip at that precision; remove those triangles.
        clean = []
        for k in range(0, len(idx), 3):
            a, b, c = idx[k:k + 3]
            signed = ((verts[b*2]-verts[a*2])*(verts[c*2+1]-verts[a*2+1])
                      - (verts[c*2]-verts[a*2])*(verts[b*2+1]-verts[a*2+1]))
            if abs(signed) > 1e-8:
                clean.extend([a, b, c] if signed > 0 else [a, c, b])
        idx = clean
        if not idx:
            return
        surface = dict(id="railway_" + name, y=y, colour=colour, layer=layer, verts=verts, idx=idx)
        if name.startswith("ballast"):
            surface["detail"] = "ballast"
        elif name.startswith("sleepers"):
            surface["detail"] = "sleeper"
        if name == "crossing":
            surface["support"] = True
        if height:
            surface["heights"] = [round(height(Point(verts[i], verts[i + 1])), 5) for i in range(0, len(verts), 2)]
        surfaces.append(surface)

    # A low, bevelled ballast shoulder: muted stone tones match the game's palette.
    inner = unary_union([p.buffer(1.45, cap_style=2) for p in paths])
    emit("ballast_edge", open_bed.difference(inner), -.02, "#777970",
         height=lambda p: -.02 + .04 * max(0, min(1, (HALF_BED - axis.distance(p)) / .35)))
    emit("ballast", open_bed.intersection(inner), .02, "#8d8c7d")

    sleepers, fixings, joints = [[], []], [], []
    for line in paths:
        def rectangle(at, half_width, half_length, lateral=0):
            p = line.interpolate(at)
            a, b = line.interpolate(max(0, at - .04)), line.interpolate(min(line.length, at + .04))
            dx, dz = b.x - a.x, b.y - a.y
            size = math.hypot(dx, dz) or 1
            tx, tz, nx, nz = dx / size, dz / size, -dz / size, dx / size
            return Polygon([(p.x + nx * (lateral + w) + tx * l, p.y + nz * (lateral + w) + tz * l)
                            for w, l in [(-half_width, -half_length), (half_width, -half_length),
                                         (half_width, half_length), (-half_width, half_length)]])

        # Even spacing along arc length also works around curves and reversed paths.
        for n in range(max(1, math.floor(line.length / .68))):
            at = .34 + n * .68
            if at > line.length - .12:
                break
            sleeper = rectangle(at, 1.26, .12)
            # Keep whole sleepers clear of paved crossings, including oblique ones.
            if not sleeper_clearance.intersects(sleeper):
                sleepers[n % 2].append(sleeper.intersection(open_bed))
                for side in (-1, 1):
                    fixings.append(rectangle(at, .14, .075, side * GAUGE / 2).intersection(open_bed))
        for n in range(math.ceil(line.length / 1.2)):
            joints.append(rectangle(n * 1.2, HALF_BED, .014).intersection(crossing))

    for i in range(2):
        emit("sleepers_" + str(i), unary_union(sleepers[i]), .045, ["#665b4d", "#756957"][i])
    emit("fasteners", unary_union(fixings), .05, "#474c4b")

    rails = [line.offset_curve(side * GAUGE / 2) for line in paths for side in (-1, 1)]
    grooves = unary_union([r.buffer(.13, cap_style=2) for r in rails])
    heads = unary_union([r.buffer(.048, cap_style=2) for r in rails])
    # Slabs replace the road/pavement, leaving dark flange grooves beside each rail.
    emit("crossing", crossing, .015, "#777d79")
    emit("joints", unary_union(joints).difference(grooves), .019, "#515956")
    emit("grooves", grooves.intersection(crossing).difference(heads), .025, "#303738")
    web = unary_union([r.buffer(.085, cap_style=2) for r in rails])
    emit("rail_web", web.difference(heads), .04, "#616867")
    emit("rail_heads", heads, .065, "#bdc6c5")

    # Partition the ramp into narrow contour bands so curved approaches cannot
    # be triangulated as a single flat bridge across the entire rail corridor.
    for n in range(6):
        lo, hi = n * RAMP / 6, (n + 1) * RAMP / 6
        band = bed.buffer(hi).difference(bed.buffer(lo)).intersection(raised)
        emit("ramp_" + str(n), band, .18, "#747970", "pavement",
             height=lambda p: .015 + .165 * min(1, bed.distance(p) / RAMP))
    return {"surfaces": surfaces, "bed": bed, "opening": opening}


def cut_kerbs(segments, opening):
    """Exact intersections, including tracks at an angle to long kerb segments."""
    if opening.is_empty:
        return segments
    result = []
    for i in range(0, len(segments), 4):
        line = LineString([segments[i:i + 2], segments[i + 2:i + 4]]).difference(opening)
        for piece in getattr(line, "geoms", [line]):
            if piece.geom_type != "LineString":
                continue
            coords = list(piece.coords)
            for a, b in zip(coords, coords[1:]):
                result.extend([*a, *b])
    return result
