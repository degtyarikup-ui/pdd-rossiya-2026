"""«Готов к экзамену» (examReady): ключ от машины — готов сесть за руль.
Без числа; уровень — металл лезвия, эмблемы и кольца. Парит без стойки."""

import bpy

VIEW = {"yaw": -20.0, "pitch": 0.0, "roll": 38.0, "cam_z": 0.3}
LEVELS = {1: None, 2: None, 3: None, 4: None}

FOB_Y = -0.3


def build(kit, level):
    mats = kit.Materials(level)
    plastic = kit.ink_material("FobPlastic", color=kit.srgb(22, 22, 25), rough=0.5, dirt=0.2)
    button = kit.plain_material("FobButton", kit.srgb(60, 62, 68), rough=0.6)

    blade_pts = [(-0.06, -0.06), (0.06, -0.06), (0.06, 0.2), (0.03, 0.235), (0.06, 0.27), (0.06, 0.34), (0.025, 0.38),
                 (0.06, 0.42), (0.06, 0.52), (0.0, 0.62), (-0.06, 0.54)]
    parts = [kit.curve_mesh("Blade", [kit.rounded_polygon_path(blade_pts, 0.01)], 0.008, 0.007, -0.015,
                            [mats.metal_disc, mats.metal_disc], res=8, bres=3),
             kit.box("Groove", (0.018, 0.5, 0.004), (-0.02, 0.22, 0.016), plastic, bevel=0.001),
             kit.curve_mesh("Fob", [kit.rrect_path(0.4, 0.5, 0.11, 0, FOB_Y)], 0.03, 0.028, -0.058, [plastic, plastic],
                            res=16, bres=6),
             kit.curve_mesh("Emblem", [kit.circle_path(0.095, 0, FOB_Y + 0.09), kit.circle_path(0.065, 0, FOB_Y + 0.09)],
                            0.003, 0.005, 0.056, [mats.rivet], res=24, bres=3),
             kit.curve_mesh("Button", [kit.rrect_path(0.2, 0.075, 0.035, 0, FOB_Y - 0.11)], 0.002, 0.004, 0.056, [button],
                            res=12, bres=3)]
    bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.014, major_segments=64, minor_segments=16,
                                     location=(0, FOB_Y - 0.33, 0))
    ring = bpy.context.active_object
    ring.name = "KeyRing"
    ring.data.materials.append(mats.rivet)
    for p in ring.data.polygons:
        p.use_smooth = True
    parts.append(ring)
    return parts
