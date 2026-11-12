"""«Мастер парковки» (parking): дорожный конус. Без числа; уровень —
металл основания и световозвращающих полос. Парит без стойки."""

import math

import bpy

VIEW = {"yaw": -25.0, "pitch": 0.0, "roll": 0.0, "cam_z": 0.5}
LEVELS = {1: None, 2: None, 3: None, 4: None}

Y0, Y1 = -0.72, 0.16           # низ и верх конуса
R_BOT, R_TOP = 0.25, 0.055


def radius(y):
    return R_BOT + (R_TOP - R_BOT) * (y - Y0) / (Y1 - Y0)


def frustum(name, y0, y1, mat, grow=0.0):
    # После поворота вокруг X вершина примитива (radius2) смотрит вниз, поэтому радиусы переставлены.
    bpy.ops.mesh.primitive_cone_add(vertices=96, radius1=radius(y1) + grow, radius2=radius(y0) + grow, depth=y1 - y0,
                                    location=(0, (y0 + y1) / 2, 0), rotation=(math.pi / 2, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.data.set_sharp_from_angle(angle=math.radians(40))
    return obj


def build(kit, level):
    mats = kit.Materials(level)
    orange = kit.ink_material("ConeOrange", color=kit.srgb(238, 84, 18), rough=0.42, dirt=0.3)

    parts = [frustum("Cone", Y0, Y1, orange)]
    for i, (a, b) in enumerate(((-0.42, -0.26), (-0.12, -0.01))):
        parts.append(frustum(f"Band{i}", a, b, mats.metal_disc, grow=0.004))
    # Основание: квадратная плита со скруглением, лежит в плоскости xz.
    base = kit.curve_mesh("Base", [kit.rrect_path(0.68, 0.68, 0.09)], 0.012, 0.014, 0, [mats.metal_disc, mats.metal_disc],
                          res=16, bres=5)
    base.rotation_euler = (-math.pi / 2, 0, 0)
    base.location = (0, Y0 - 0.052, 0)
    parts.append(base)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=R_TOP, location=(0, Y1, 0))
    cap = bpy.context.active_object
    cap.name = "Cap"
    cap.scale = (1, 0.35, 1)
    cap.data.materials.append(orange)
    for p in cap.data.polygons:
        p.use_smooth = True
    parts.append(cap)
    return parts
