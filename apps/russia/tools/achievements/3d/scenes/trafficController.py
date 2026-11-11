"""«Мастер сигналов» (trafficController): российский светофор и табло
обратного отсчёта, очки горят на табло зелёным. Без таблички и экрана."""

import math

import bmesh
import bpy

LEVELS = {1: "150", 2: "300", 3: "600", 4: "900"}

HX, HY = -0.23, 0.10            # центр корпуса светофора
HW, HH, HD = 0.30, 0.86, 0.16   # корпус: ширина, высота, глубина
PITCH, LENS_R = 0.27, 0.105
DX, DY = 0.30, -0.06            # табло отсчёта
DW, DH, DD = 0.56, 0.40, 0.12
GREEN = (60, 240, 150)


def visor(name, x, y, z, mat):
    """Козырёк над линзой: верхняя половина трубы с толщиной стенки."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=64, radius1=LENS_R + 0.027, radius2=LENS_R + 0.027, depth=0.15)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.035], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (x, y, z + 0.075)
    obj.rotation_euler = (math.radians(-6), 0, 0)
    obj.modifiers.new("solid", "SOLIDIFY").thickness = 0.008
    obj.modifiers.new("bevel", "BEVEL").width = 0.002
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return obj


def lens(name, x, y, z, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=LENS_R, location=(x, y, z))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (1, 1, 0.3)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    paint = kit.ink_material("HousingPaint", color=kit.srgb(40, 43, 48), rough=0.42, dirt=0.25)
    bezel = kit.ink_material("Bezel", color=kit.srgb(16, 16, 18), rough=0.5, dirt=0.2)
    glass = kit.lens_material("PanelGlass", kit.srgb(8, 9, 10))
    off_red = kit.lens_material("LensRed", kit.srgb(92, 12, 14))
    off_yellow = kit.lens_material("LensYellow", kit.srgb(96, 62, 8))
    led_lamp = kit.led_material("LedLamp", kit.srgb(*GREEN), strength=5.0, dots=95.0)
    led_digits = kit.led_material("LedDigits", kit.srgb(*GREEN), strength=5.0, dots=150.0)

    zf = kit.Z_FRONT
    # Корпус светофора: металл уровня на торцах, окрашенная лицевая сторона.
    parts = [kit.curve_mesh("Housing", [kit.rrect_path(HW - 0.024, HH - 0.024, 0.06, HX, HY)], HD / 2 - 0.012, 0.012,
                            zf - HD, [paint, mats.metal_disc], side_index=1, res=16, bres=5)]
    for i, (ly, mat) in enumerate(((HY + PITCH, off_red), (HY, off_yellow), (HY - PITCH, led_lamp))):
        parts.append(kit.curve_mesh(f"Bezel{i}", [kit.circle_path(LENS_R + 0.02, HX, ly), kit.circle_path(LENS_R + 0.002, HX, ly)],
                                    0.004, 0.004, zf - 0.003, [bezel], res=24, bres=3))
        parts.append(lens(f"Lens{i}", HX, ly, zf + 0.002, mat))
        parts.append(visor(f"Visor{i}", HX, ly, zf, paint))
    # Табло отсчёта: корпус, стекло, светодиодные цифры.
    dz = zf - 0.04
    parts.append(kit.curve_mesh("Display", [kit.rrect_path(DW - 0.024, DH - 0.024, 0.05, DX, DY)], DD / 2 - 0.012, 0.012,
                                dz - DD, [paint, mats.metal_disc], side_index=1, res=16, bres=5))
    parts.append(kit.curve_mesh("DisplayGlass", [kit.rrect_path(DW - 0.08, DH - 0.08, 0.03, DX, DY)], 0.001, 0.002,
                                dz - 0.0005, [glass], res=16, bres=3))
    digits, _ = kit.text_mesh("Digits", number, kit.FONT_DIGITS, 0.24, 0.0008, 0.0012, dz + 0.004, [led_digits],
                              cx=DX, cy=DY, spacing=1.12)
    parts.append(digits)

    # Стойка между светофором и табло, по одному кронштейну к каждому.
    parts += kit.pole(mats, mounts_y=(), top=0.46)
    for i, (x0, x1, yy) in enumerate(((HX + HW / 2 - 0.02, 0, HY), (0, DX - DW / 2 + 0.03, DY))):
        parts.append(kit.box(f"Arm{i}", (abs(x1 - x0) + 0.02, 0.05, 0.03), ((x0 + x1) / 2, yy, kit.POLE_Z), mats.metal_pole))
        parts.append(kit.cylinder(f"ArmClamp{i}", kit.POLE_R + 0.006, yy - 0.03, yy + 0.03, kit.POLE_Z, [mats.metal_pole], verts=64))
    return parts
