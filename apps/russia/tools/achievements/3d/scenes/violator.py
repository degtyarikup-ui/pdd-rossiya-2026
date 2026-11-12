"""«Инспектор» (violator): полосатый жезл регулировщика. Без числа;
уровень — металл рукояти, гарды и наконечника. Парит без стойки."""

import math

import bpy

VIEW = {"yaw": -18.0, "pitch": 0.0, "roll": 42.0, "cam_z": 0.3}
LEVELS = {1: None, 2: None, 3: None, 4: None}

R = 0.085


def build(kit, level):
    mats = kit.Materials(level)
    white = kit.ink_material("BatonWhite", color=kit.srgb(236, 236, 230), rough=0.4, dirt=0.2)
    black = kit.ink_material("BatonBlack", color=kit.srgb(14, 14, 16), rough=0.4, dirt=0.15)

    parts = []
    # Полосатая часть: шесть секций.
    y, seg = -0.24, 0.15
    for i in range(6):
        parts.append(kit.cylinder(f"Stripe{i}", R, y, y + seg, 0, [black if i % 2 == 0 else white]))
        y += seg
    # Наконечник.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=R, location=(0, y, 0))
    tip = bpy.context.active_object
    tip.name = "Tip"
    tip.data.materials.append(mats.rivet)
    for p in tip.data.polygons:
        p.use_smooth = True
    parts.append(tip)
    # Гарда и рукоять с кольцами.
    parts.append(kit.cylinder("Guard", R * 1.32, -0.275, -0.24, 0, [mats.metal_pole], verts=64))
    parts.append(kit.cylinder("Handle", R * 0.8, -0.62, -0.275, 0, [black], verts=64))
    for i in range(4):
        yy = -0.56 + i * 0.075
        parts.append(kit.cylinder(f"Grip{i}", R * 0.86, yy, yy + 0.018, 0, [mats.metal_pole], verts=64))
    parts.append(kit.cylinder("Pommel", R * 0.98, -0.66, -0.62, 0, [mats.metal_pole], verts=64))
    return parts
