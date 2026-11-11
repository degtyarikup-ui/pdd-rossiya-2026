"""«Покоритель рейтинга» (rank): пьедестал почёта с клетчатым флагом.
На главной ступени — «ТОП 100 / 10 / 3» и «1» на высшем уровне.
Металл уровня — верхние плиты и древко. Парит без стойки."""

import math

import bmesh
import bpy

VIEW = {"yaw": -28.0, "pitch": 0.0, "roll": 0.0, "cam_z": 0.55}
LEVELS = {1: "100", 2: "10", 3: "3", 4: "1"}

BW, BD = 0.44, 0.44                       # ширина и глубина ступени
GROUND = -0.36
STEPS = ((-0.46, 0.30), (0.0, 0.46), (0.46, 0.22))   # (x, высота): 2-е, 1-е, 3-е место


def flag(kit, x, y, mat):
    """Клетчатый флаг с волной, крепится левым краем к древку."""
    me = bpy.data.meshes.new("Flag")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=28, y_segments=18, size=0.5)
    for v in bm.verts:
        u = v.co.x + 0.5                  # 0 у древка → 1 на свободном краю
        v.co.x = u * 0.40
        v.co.y = v.co.y * 0.27
        v.co.z = 0.035 * math.sin(u * 7.0) * u + 0.01 * math.sin(v.co.y * 18) * u
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat)
    obj = bpy.data.objects.new("Flag", me)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (x, y, 0)
    obj.modifiers.new("solid", "SOLIDIFY").thickness = 0.004
    return obj


def checker_material(kit):
    mat = bpy.data.materials.new("FlagCloth")
    nb = kit.NB(mat)
    p = nb.principled()
    ch = nb.n("ShaderNodeTexChecker")
    ch.inputs["Scale"].default_value = 1.0
    ch.inputs["Color1"].default_value = (*kit.srgb(245, 245, 240), 1)
    ch.inputs["Color2"].default_value = (*kit.srgb(22, 22, 24), 1)
    nb.link(nb.coords(scale=(15.0, 15.0, 0.0), loc=(0.0, 0.0, 0.0)), ch.inputs["Vector"])
    nb.link(ch.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.8
    p.inputs["Sheen Weight"].default_value = 0.5
    weave = nb.noise(nb.coords(), 220.0, detail=2)
    nb.link(nb.bump(weave.outputs["Fac"], 0.05, 0.001), p.inputs["Normal"])
    return mat


def build(kit, level):
    label = LEVELS[level]
    mats = kit.Materials(level)
    stone = kit.ink_material("PodiumWhite", color=kit.srgb(238, 238, 234), rough=0.45, dirt=0.2)

    parts = []
    for i, (x, h) in enumerate(STEPS):
        parts.append(kit.box(f"Step{i}", (BW, h, BD), (x, GROUND + h / 2, 0), stone, bevel=0.02))
        parts.append(kit.box(f"StepTop{i}", (BW + 0.02, 0.03, BD + 0.02), (x, GROUND + h + 0.012, 0), mats.metal_disc, bevel=0.008))

    # Надпись на главной ступени.
    center_h = STEPS[1][1]
    z = BD / 2 - 0.0006
    if label == "1":
        num, _ = kit.text_mesh("Place", "1", kit.FONT_DIGITS, 0.27, 0.003, 0.004, z, [mats.ink], cy=GROUND + center_h * 0.5)
        parts.append(num)
    else:
        top, _ = kit.text_mesh("Top", "ТОП", kit.font_plate(), 0.07, 0.002, 0.003, z, [mats.ink], cy=GROUND + center_h * 0.72)
        num, _ = kit.text_mesh("Place", label, kit.FONT_DIGITS, 0.17 if len(label) < 3 else 0.14, 0.003, 0.004, z, [mats.ink],
                               cy=GROUND + center_h * 0.38, spacing=1.05)
        parts += [top, num]

    # Древко с флагом на главной ступени.
    top_y = GROUND + center_h + 0.027
    pole = kit.cylinder("FlagPole", 0.012, top_y, top_y + 0.62, -0.1, [mats.metal_pole], verts=32)
    pole.location.x = -0.12
    parts.append(pole)
    parts.append(kit.cylinder("PoleKnob", 0.022, top_y + 0.62, top_y + 0.645, -0.1, [mats.rivet], verts=32))
    parts[-1].location.x = -0.12
    f = flag(kit, -0.11, top_y + 0.47, checker_material(kit))
    f.location.z = -0.1
    parts.append(f)
    return parts
