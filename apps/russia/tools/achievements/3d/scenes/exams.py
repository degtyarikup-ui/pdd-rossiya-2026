"""«Экзаменатор» (exams): водительское удостоверение — сдал экзамен, получил
права. Без числа; уровень — металлическая голограмма. Парит без стойки.

Печать карты генерирует textures/license_print.py (запускать до рендера).
"""

import os

import bpy

LEVELS = {1: None, 2: None, 3: None, 4: None}
PRINT = os.path.expanduser("~/Library/Caches/pdd-achievements/license_print.png")

W, H, R = 1.0, 0.63, 0.045
T_E, T_B = 0.002, 0.006            # толщина карты 0.016


# Вариант «карта уровня»: металлизированный пластик цвета металла уровня,
# как у премиальных банковских карт. LICENSE_TINT=0 — обычные розовые права.
TINTED = os.environ.get("LICENSE_TINT", "1") != "0"
TINT = {1: (226, 160, 116), 2: (222, 228, 236), 3: (248, 206, 120), 4: (138, 182, 250)}


def card_material(kit, level=1):
    """Ламинированный пластик: печать, тонкая волнистость плёнки, глянец."""
    if not os.path.exists(PRINT):
        raise SystemExit("Нет печати карты: python3 tools/achievements/3d/textures/license_print.py")
    mat = bpy.data.materials.new("CardPrint")
    nb = kit.NB(mat)
    p = nb.principled()
    tex = nb.n("ShaderNodeTexImage", extension="CLIP", interpolation="Cubic")
    tex.image = bpy.data.images.load(PRINT)
    nb.link(nb.coords(scale=(1 / W, 1 / H, 1), loc=(0.5, 0.5, 0)), tex.inputs["Vector"])
    grime = kit.grime_mask(nb, 0.12, 0.02)
    col = tex.outputs["Color"]
    if TINTED:
        # Печать проступает сквозь металл: светлый фон берёт цвет уровня, текст остаётся тёмным.
        gray = nb.n("ShaderNodeRGBToBW")
        nb.link(col, gray.inputs[0])
        tinted = nb.mix_rgb(1.0, kit.srgb(*TINT[level]), gray.outputs[0], "MULTIPLY")
        col = nb.mix_rgb(0.93, col, tinted)
        p.inputs["Metallic"].default_value = 0.6
    nb.link(nb.mix_rgb(grime, col, kit.srgb(150, 140, 130), "MULTIPLY"), p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.3 if TINTED else 0.38
    p.inputs["Coat Weight"].default_value = 1.0
    p.inputs["Coat Roughness"].default_value = 0.05
    wave = nb.noise(nb.coords(), 4.0, detail=3)
    nb.link(nb.bump(wave.outputs["Fac"], 0.05, 0.01), p.inputs["Coat Normal"])
    return mat


def build(kit, level):
    mats = kit.Materials(level)
    edge = kit.plain_material("CardEdge", kit.srgb(236, 234, 232), rough=0.45)
    z_front = T_E + T_B
    parts = [kit.curve_mesh("Card", [kit.rrect_path(W - 2 * T_B, H - 2 * T_B, R - T_B)], T_E, T_B, -z_front,
                            [card_material(kit, level), mats.metal_disc if TINTED else edge], side_index=1, res=16, bres=4)]
    # Голограмма: металлическая плёнка уровня с концентрическим тиснением.
    hx, hy = 0.37, -0.18
    parts.append(kit.curve_mesh("Hologram", [kit.circle_path(0.092, hx, hy)], 0.0004, 0.0008, z_front - 0.0002,
                                [mats.rivet], res=32, bres=2))
    for i, r in enumerate((0.075, 0.055, 0.035)):
        parts.append(kit.curve_mesh(f"HoloRing{i}", [kit.circle_path(r, hx, hy), kit.circle_path(r - 0.006, hx, hy)],
                                    0.0003, 0.0005, z_front + 0.0012, [mats.metal_disc], res=32, bres=2))
    return parts
