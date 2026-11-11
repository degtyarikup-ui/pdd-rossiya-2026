"""«Гонщик» (game): гоночная машинка в стиле коллекционной литой модели.
Уровень — краска «металлик» и диски, очки — номер на двери. Парит без стойки.

Оси детали: x — длина (перед справа), y — высота, z — ширина (к зрителю).
"""

import math

import bpy

VIEW = {"yaw": -34.0, "pitch": 0.0, "roll": 0.0, "cam_z": 0.55}   # чуть сверху, без крена
LEVELS = {1: "100", 2: "200", 3: "300", 4: "450"}

L = 0.68                          # полудлина кузова
HALF_W = 0.27                     # полуширина кузова
WHEEL_X, WHEEL_R, AXLE_Y = 0.37, 0.13, 0.13
ARCH_R = 0.15
BELT_Y = 0.40                     # линия окон


def corner_path(kit, pts):
    """Контур из (точка, радиус): радиус 0 — острая вершина (для дуг арок)."""
    out = []
    n = len(pts)
    for i, (p, r) in enumerate(pts):
        if r <= 0:
            out.append((p, p, p))
            continue
        out += kit.round_corner(pts[i - 1][0], p, pts[(i + 1) % n][0], r)
    return out


def body_profile(b):
    """Профиль с поправкой на фаску b: кривая раздувает контур на b наружу."""
    l, bottom = L - b, 0.085 + b
    pts = [((-l, 0.16), 0.05)]
    for cx in (-WHEEL_X, WHEEL_X):
        ar = ARCH_R + b
        pts.append(((cx - ar - 0.02, bottom), 0.02))
        for k in range(0, 13):
            a = math.pi - math.pi * k / 12
            pts.append(((cx + ar * math.cos(a), max(bottom, AXLE_Y + ar * math.sin(a) * 1.02)), 0.0))
        pts.append(((cx + ar + 0.02, bottom), 0.02))
    pts += [((l, 0.15), 0.05), ((l + 0.015, 0.26), 0.06), ((l - 0.08, BELT_Y - b), 0.08),
            ((0.10, BELT_Y + 0.025 - b), 0.12), ((-0.30, BELT_Y + 0.02 - b), 0.12), ((-l + 0.04, BELT_Y - 0.01 - b), 0.07)]
    return pts


def cabin_profile():
    return [((0.21, BELT_Y - 0.02), 0.02), ((0.03, 0.58), 0.06), ((-0.26, 0.58), 0.07), ((-0.43, BELT_Y - 0.02), 0.02)]


def taper(obj, k, power=4.0, half=L):
    """Скругление в плане: ширина плавно уменьшается к переду и корме."""
    for v in obj.data.vertices:
        t = min(1.0, abs(v.co.x) / half)
        v.co.z *= 1.0 - k * t ** power


def stripes_paint(kit, level):
    """Краска уровня с двумя белыми гоночными полосами вдоль машины."""
    mat = kit.paint_metallic("CarPaint", level)
    nb = kit.NB.__new__(kit.NB)
    nb.t = mat.node_tree
    p = next(n for n in nb.t.nodes if n.type == "BSDF_PRINCIPLED")
    base = p.inputs["Base Color"].links[0].from_socket
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.link(nb.coords(), sep.inputs[0])
    az = nb.math("ABSOLUTE", sep.outputs["Z"])
    band = nb.math("MULTIPLY", nb.math("GREATER_THAN", az, 0.028), nb.math("LESS_THAN", az, 0.082))
    nb.link(nb.mix_rgb(band, base, kit.srgb(244, 244, 240)), p.inputs["Base Color"])
    nb.link(nb.math("SUBTRACT", 0.85, nb.math("MULTIPLY", band, 0.85)), p.inputs["Metallic"])
    return mat


def facing(obj, axis):
    """Деталь, построенная лицом к +z, поворачивается лицом к +x (перед) или −x (корма)."""
    obj.rotation_euler = (0, math.pi / 2 if axis > 0 else -math.pi / 2, 0)
    return obj


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    paint = stripes_paint(kit, level)
    glass = kit.plain_material("Glass", kit.srgb(46, 62, 80), rough=0.03, coat=1.0)
    rubber = kit.plain_material("Rubber", kit.srgb(26, 26, 28), rough=0.82)
    trim = kit.plain_material("Trim", kit.srgb(30, 31, 34), rough=0.5)
    chrome = kit.plain_material("Chrome", kit.srgb(235, 238, 242), rough=0.08, metallic=1.0)
    lens = kit.plain_material("LampLens", kit.srgb(250, 250, 244), rough=0.03, coat=1.0)
    tail = kit.plain_material("TailLens", kit.srgb(190, 16, 22), rough=0.06, coat=1.0)
    disc = kit.plain_material("BrakeDisc", kit.srgb(90, 92, 96), rough=0.35, metallic=1.0)
    white = kit.enamel_gradient("Roundel", kit.srgb(238, 238, 234), kit.srgb(252, 252, 248), -0.1, 0.1, rough=0.25)

    parts = []
    # Кузов: боковой профиль, выдавленный по ширине, со скруглением в плане.
    b = 0.045
    body = kit.curve_mesh("Body", [corner_path(kit, body_profile(b))], HALF_W - b, b, -HALF_W, [paint, paint], res=24, bres=6)
    taper(body, 0.16)
    parts.append(body)

    # Кабина: стекло уже кузова, сверху окрашенная крыша, стойки по краям.
    cw = 0.205
    cab = kit.curve_mesh("Cabin", [corner_path(kit, cabin_profile())], cw - 0.04, 0.04, -cw, [glass, glass], res=24, bres=5)
    parts.append(cab)
    roof = kit.curve_mesh("Roof", [corner_path(kit, [((0.02, 0.598), 0.0), ((0.0, 0.612), 0.012), ((-0.24, 0.612), 0.012),
                                                     ((-0.262, 0.598), 0.0)])], cw - 0.012, 0.016, -cw - 0.004, [paint, paint], res=16, bres=4)
    parts.append(roof)
    for side in (1, -1):
        for name, (x0, y0), (x1, y1), w in (("APillar", (0.25, BELT_Y - 0.02), (0.05, 0.594), 0.03),
                                            ("BPillar", (-0.09, BELT_Y - 0.02), (-0.09, 0.598), 0.035),
                                            ("CPillar", (-0.46, BELT_Y - 0.02), (-0.255, 0.594), 0.05)):
            length = math.hypot(x1 - x0, y1 - y0)
            ang = math.atan2(y1 - y0, x1 - x0)
            pil = kit.box(f"{name}{side:+d}", (length, w, 0.012), ((x0 + x1) / 2, (y0 + y1) / 2, side * (cw + 0.004)),
                          paint, bevel=0.004)
            pil.rotation_euler = (0, 0, ang)
            parts.append(pil)

    # Перед: фары, решётка, бампер. Корма: фонари, бампер.
    zf = L + 0.033   # лицевая плоскость переда (после фаски)
    for side in (1, -1):
        zc = side * 0.175
        lamp = facing(kit.curve_mesh(f"Headlamp{side:+d}", [kit.rrect_path(0.11, 0.055, 0.026, -zc, 0.27)], 0.003, 0.006, 0,
                                     [lens], res=12, bres=3), 1)
        lamp.location = (zf - 0.03, 0, 0)
        parts.append(lamp)
        refl = facing(kit.curve_mesh(f"Reflector{side:+d}", [kit.circle_path(0.02, -zc - 0.02, 0.27), kit.circle_path(0.02, -zc + 0.025, 0.27)],
                                     0.001, 0.003, 0, [chrome], res=12, bres=2), 1)
        refl.location = (zf - 0.017, 0, 0)
        parts.append(refl)
        tl = facing(kit.curve_mesh(f"Taillamp{side:+d}", [kit.rrect_path(0.12, 0.05, 0.02, zc, 0.29)], 0.003, 0.006, 0,
                                   [tail], res=12, bres=3), -1)
        tl.location = (-L + 0.012, 0, 0)
        parts.append(tl)
        mirror = kit.box(f"Mirror{side:+d}", (0.06, 0.035, 0.05), (0.19, BELT_Y + 0.04, side * (HALF_W - 0.01)), paint, bevel=0.012)
        parts.append(mirror)
    grille = facing(kit.curve_mesh("Grille", [kit.rrect_path(0.2, 0.05, 0.02, 0, 0.27)], 0.003, 0.005, 0, [trim], res=12, bres=3), 1)
    grille.location = (zf - 0.028, 0, 0)
    parts.append(grille)
    for name, x in (("FrontBumper", L + 0.005), ("RearBumper", -L - 0.005)):
        parts.append(kit.box(name, (0.06, 0.05, 2 * HALF_W - 0.08), (x, 0.16, 0), trim, bevel=0.018))
    parts.append(kit.box("Sill", (0.42, 0.03, 2 * HALF_W - 0.02), (0, 0.12, 0), trim, bevel=0.01))

    # Номер на двери.
    door_z = HALF_W - 0.0006
    parts.append(kit.curve_mesh("Roundel", [kit.circle_path(0.09, -0.02, 0.25)], 0.0008, 0.0015, door_z, [white], res=16, bres=2))
    num, _ = kit.text_mesh("RaceNumber", number, kit.FONT_DIGITS, 0.09, 0.0008, 0.0012, door_z + 0.004, [mats.ink],
                           cx=-0.02, cy=0.25, spacing=1.04)
    parts.append(num)
    parts.append(kit.box("DoorHandle", (0.045, 0.012, 0.01), (-0.15, BELT_Y - 0.085, HALF_W - 0.004), chrome, bevel=0.004))

    # Колёса: шина со скруглённой боковиной, тормозной диск, диск из металла уровня со спицами.
    for wx in (-WHEEL_X, WHEEL_X):
        for side in (1, -1):
            zc = side * (HALF_W - 0.045)
            parts.append(kit.curve_mesh(f"Tire{wx:+.2f}{side}", [kit.circle_path(WHEEL_R - 0.035, wx, AXLE_Y),
                                                                 kit.circle_path(0.085, wx, AXLE_Y)],
                                        0.015, 0.035, zc - 0.05, [rubber], res=32, bres=6))
            if side < 0:
                continue
            face = zc + 0.05 - 0.018
            parts.append(kit.curve_mesh(f"Disc{wx:+.2f}", [kit.circle_path(0.072, wx, AXLE_Y)], 0.003, 0.002, face - 0.03, [disc], res=24, bres=2))
            parts.append(kit.curve_mesh(f"RimLip{wx:+.2f}", [kit.circle_path(0.09, wx, AXLE_Y), kit.circle_path(0.076, wx, AXLE_Y)],
                                        0.006, 0.006, face - 0.004, [mats.rivet], res=32, bres=3))
            for k in range(6):
                a = math.pi / 2 + k * math.pi / 3
                spoke = kit.rotate_path(kit.rrect_path(0.071, 0.021, 0.01, wx + 0.041, AXLE_Y), a, wx, AXLE_Y)
                parts.append(kit.curve_mesh(f"Spoke{wx:+.2f}{k}", [spoke], 0.004, 0.005, face - 0.006, [mats.rivet], res=8, bres=3))
            parts.append(kit.curve_mesh(f"Hub{wx:+.2f}", [kit.circle_path(0.026, wx, AXLE_Y)], 0.005, 0.006, face - 0.002, [mats.rivet],
                                        res=16, bres=3))
            parts.append(kit.curve_mesh(f"HubCap{wx:+.2f}", [kit.circle_path(0.012, wx, AXLE_Y)], 0.002, 0.003, face + 0.016, [chrome],
                                        res=12, bres=2))
    return parts
