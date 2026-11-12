"""«Отличник ПДД» (perfect): рулевое колесо — все билеты без ошибок, можно
за руль. Без числа; уровень — металл спиц и ступицы. Парит без стойки."""

import math

import bpy

VIEW = {"yaw": -24.0, "pitch": -12.0, "roll": 0.0, "cam_z": 0.3}
LEVELS = {1: None, 2: None, 3: None, 4: None}

R, TUBE, CY = 0.5, 0.062, -0.3


def build(kit, level):
    mats = kit.Materials(level)
    leather = kit.ink_material("Leather", color=kit.srgb(24, 24, 26), rough=0.55, dirt=0.2)

    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=TUBE, major_segments=128, minor_segments=32,
                                     location=(0, CY, 0))
    rim = bpy.context.active_object
    rim.name = "Rim"
    rim.data.materials.append(leather)
    for p in rim.data.polygons:
        p.use_smooth = True
    parts = [rim]
    # Три спицы: влево, вправо и вниз.
    for i, ang in enumerate((0, 180, 270)):
        a = math.radians(ang)
        spoke = kit.box(f"Spoke{i}", (R - 0.1, 0.11 if ang != 270 else 0.13, 0.035),
                        (math.cos(a) * (R + 0.08) / 2, CY + math.sin(a) * (R + 0.08) / 2, -0.01), mats.metal_disc, bevel=0.014)
        spoke.rotation_euler = (0, 0, a)
        parts.append(spoke)
    parts.append(kit.curve_mesh("Hub", [kit.circle_path(0.17, 0, CY)], 0.02, 0.02, -0.04, [mats.metal_disc, mats.metal_disc],
                                res=32, bres=5))
    parts.append(kit.curve_mesh("Horn", [kit.circle_path(0.095, 0, CY)], 0.004, 0.008, 0.035, [leather], res=32, bres=4))
    return parts
