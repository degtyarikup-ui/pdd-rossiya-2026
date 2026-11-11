"""«Билет за билетом» (tickets): стопка экзаменационных билетов, сверху
«Билет № N» с настоящим фото вопроса. Стопка растёт с уровнем, шапки
билетов — металл уровня. Парит без стойки.

Печать билетов генерирует textures/ticket_print.py (запускать до рендера).
"""

import math
import os

import bpy

VIEW = {"yaw": -24.0, "pitch": -8.0, "roll": 0.0, "cam_z": 0.55}
LEVELS = {1: 1, 2: 10, 3: 20, 4: 40}
STACK = {1: 1, 2: 3, 3: 5, 4: 8}               # сколько билетов в стопке
CACHE = os.path.expanduser("~/Library/Caches/pdd-achievements")
W, H, R = 1.0, 0.7, 0.025
GAP = 0.009                                    # шаг стопки по толщине
ANGLES = (-6, 4, -3, 5, -4, 3, -2, 0)
# Шапка: матовая печатная краска цвета уровня (как фон экрана награды), не металл —
# металл и атлас выгорают в софтбоксе и съедают белый номер.
HEADER = {1: (148, 84, 48), 2: (112, 126, 148), 3: (238, 180, 40), 4: (5, 116, 248)}


def image(name):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        raise SystemExit("Нет печати билетов: python3 tools/achievements/3d/textures/ticket_print.py")
    return bpy.data.images.load(path, check_existing=True)


def paper(kit, name, print_name, level):
    """Бумага с печатью; шапка по маске — матовая краска цвета уровня, белый текст остаётся белым."""
    metal = kit.srgb(*HEADER[level])
    mat = bpy.data.materials.new(name)
    nb = kit.NB(mat)
    p = nb.principled()
    uv = nb.coords(scale=(1 / W, 1 / H, 1), loc=(0.5, 0.5, 0))
    tex = nb.n("ShaderNodeTexImage", extension="CLIP", interpolation="Cubic")
    tex.image = image(print_name)
    nb.link(uv, tex.inputs["Vector"])
    msk = nb.n("ShaderNodeTexImage", extension="CLIP", interpolation="Linear")
    msk.image = image("ticket_mask.png")
    msk.image.colorspace_settings.name = "Non-Color"
    nb.link(uv, msk.inputs["Vector"])
    header = msk.outputs["Color"]
    lum = nb.n("ShaderNodeRGBToBW")
    nb.link(tex.outputs["Color"], lum.inputs[0])
    text = nb.n("ShaderNodeMapRange", clamp=True)
    text.inputs["From Min"].default_value = 0.55
    text.inputs["From Max"].default_value = 0.85
    nb.link(lum.outputs[0], text.inputs["Value"])
    head_col = nb.mix_rgb(text.outputs[0], metal, (0.93, 0.93, 0.91))
    grime = kit.grime_mask(nb, 0.1, 0.02)
    paper_col = nb.mix_rgb(grime, tex.outputs["Color"], kit.srgb(150, 140, 125), "MULTIPLY")
    paper_col = nb.mix_rgb(1.0, paper_col, (0.9, 0.9, 0.89), "MULTIPLY")
    nb.link(nb.mix_rgb(header, paper_col, head_col), p.inputs["Base Color"])
    foil = nb.math("MULTIPLY", header, nb.math("SUBTRACT", 1.0, text.outputs[0]))
    nb.link(nb.math("MULTIPLY", foil, 0.12), p.inputs["Metallic"])
    nb.link(nb.math("ADD", 0.62, nb.math("MULTIPLY", foil, -0.12)), p.inputs["Roughness"])
    nb.link(nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, header), 0.2), p.inputs["Sheen Weight"])
    p.inputs["Specular IOR Level"].default_value = 0.35
    fibers = nb.noise(nb.coords(scale=(1, 5, 1)), 160.0, detail=3)
    warp = nb.noise(nb.coords(), 3.0, detail=2)
    n_fine = nb.bump(fibers.outputs["Fac"], 0.06, 0.001)
    nb.link(nb.bump(warp.outputs["Fac"], 0.08, 0.015, normal=n_fine), p.inputs["Normal"])
    return mat


def build(kit, level):
    number, count = LEVELS[level], STACK[level]
    edge = kit.plain_material("PaperEdge", kit.srgb(236, 234, 226), rough=0.7)
    top_print = paper(kit, "TicketTop", f"ticket_{number}.png", level)
    blank = paper(kit, "TicketBlank", "ticket_blank.png", level)

    parts = []
    for i in range(count):
        top = i == count - 1
        card = kit.curve_mesh(f"Ticket{i}", [kit.rrect_path(W - 0.004, H - 0.004, R)], 0.0015, 0.002, -0.0035,
                              [top_print if top else blank, edge], side_index=1, res=12, bres=2)
        if not top:
            card.rotation_euler = (0, 0, math.radians(ANGLES[(i + count) % len(ANGLES)]))
            card.location = (0.014 * ((i % 3) - 1), -0.01 * (i % 2), i * GAP)
        else:
            card.location = (0, 0, i * GAP)
        parts.append(card)
    return parts
