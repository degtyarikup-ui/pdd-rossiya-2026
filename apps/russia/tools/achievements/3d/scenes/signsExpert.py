"""«Знаток знаков ПДД» (signsExpert): книжка правил дорожного движения.
Без числа; уровень — цвет плашки обложки и корешка. Парит без стойки.

Обложку генерирует textures/rulebook_print.py (запускать до рендера).
"""

import os

import bpy

VIEW = {"yaw": -30.0, "pitch": 4.0, "roll": -6.0, "cam_z": 0.3}
LEVELS = {1: None, 2: None, 3: None, 4: None}
PRINT = os.path.expanduser("~/Library/Caches/pdd-achievements/rulebook_print.png")
# Матовая краска уровня, как у шапки билетов.
COVER = {1: (148, 84, 48), 2: (112, 126, 148), 3: (238, 180, 40), 4: (5, 116, 248)}

W, H, CY, THICK = 0.74, 1.0, -0.3, 0.11


def cover_material(kit, level):
    """Печать обложки; плашка по маске — матовая краска уровня, белый текст на ней остаётся белым."""
    if not os.path.exists(PRINT):
        raise SystemExit("Нет обложки: python3 tools/achievements/3d/textures/rulebook_print.py")
    mat = bpy.data.materials.new("Cover")
    nb = kit.NB(mat)
    p = nb.principled()
    uv = nb.coords(scale=(1 / W, 1 / H, 1), loc=(0.5, 0.5 - CY / H, 0))
    tex = nb.n("ShaderNodeTexImage", extension="CLIP", interpolation="Cubic")
    tex.image = bpy.data.images.load(PRINT)
    nb.link(uv, tex.inputs["Vector"])
    msk = nb.n("ShaderNodeTexImage", extension="CLIP", interpolation="Linear")
    msk.image = bpy.data.images.load(PRINT.replace("_print", "_mask"))
    msk.image.colorspace_settings.name = "Non-Color"
    nb.link(uv, msk.inputs["Vector"])
    lum = nb.n("ShaderNodeRGBToBW")
    nb.link(tex.outputs["Color"], lum.inputs[0])
    text = nb.n("ShaderNodeMapRange", clamp=True)
    text.inputs["From Min"].default_value = 0.4
    text.inputs["From Max"].default_value = 0.8
    nb.link(lum.outputs[0], text.inputs["Value"])
    band = nb.mix_rgb(text.outputs[0], kit.srgb(*COVER[level]), (0.93, 0.93, 0.91))
    col = nb.mix_rgb(msk.outputs["Color"], tex.outputs["Color"], band)
    grime = kit.grime_mask(nb, 0.12, 0.02)
    nb.link(nb.mix_rgb(grime, col, kit.srgb(130, 120, 108), "MULTIPLY"), p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.42
    p.inputs["Coat Weight"].default_value = 0.5
    p.inputs["Coat Roughness"].default_value = 0.15
    return mat


def build(kit, level):
    side = kit.plain_material("CoverSide", kit.srgb(*[int(c * 0.82) for c in COVER[level]]), rough=0.55)
    pages = kit.plain_material("Pages", kit.srgb(238, 235, 226), rough=0.7)
    front = kit.curve_mesh("CoverFront", [kit.rrect_path(W - 0.01, H - 0.01, 0.025, 0, CY)], 0.003, 0.005, THICK / 2 - 0.016,
                           [cover_material(kit, level), side], side_index=1, res=12, bres=3)
    back = kit.curve_mesh("CoverBack", [kit.rrect_path(W - 0.01, H - 0.01, 0.025, 0, CY)], 0.003, 0.005, -THICK / 2,
                          [side, side], res=12, bres=3)
    block = kit.box("PagesBlock", (W - 0.05, H - 0.05, THICK - 0.03), (0.012, CY, 0), pages, bevel=0.004)
    spine = kit.box("Spine", (0.03, H, THICK), (-W / 2 + 0.012, CY, 0), side, bevel=0.012)
    return [front, back, block, spine]
