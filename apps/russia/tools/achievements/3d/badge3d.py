"""Общий набор для 3D-ачивок: материалы, металлы уровней, детали знаков, свет,
камера и рендер. Правила формата — docs/application/achievements-3d.md.

Сцена конкретной ачивки лежит в scenes/<id>.py и описывает только объект:
    LEVELS = {1: ..., 2: ..., 3: ..., 4: ...}
    def build(kit, level) -> list[bpy.types.Object]

Локальная система детали: x вправо, y вверх, z к зрителю (лицевая сторона).
Всё процедурное: геометрия из кривых, материалы из нод, без внешних текстур.
"""

import math
import os
import struct

import bpy
from mathutils import Vector

FONT_DIGITS = "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf"
PT_SANS_TTC = "/System/Library/Fonts/Supplemental/PTSans.ttc"
FONT_CACHE = os.path.expanduser("~/Library/Caches/pdd-achievements")
STUDIO_HDRI = os.path.join(
    os.path.dirname(bpy.app.binary_path), "..", "Resources",
    f"{bpy.app.version[0]}.{bpy.app.version[1]}", "datafiles", "studiolights", "world", "studio.exr",
)

# ------------------------------------------------------- стандарт знака
R_SIGN = 0.5             # круглый знак — диаметр 1.0, от него считаются все размеры
T_E, T_B = 0.012, 0.013  # extrude / bevel корпуса → толщина 2*(e+b) = 0.05
Z_FRONT = T_E + T_B      # лицевая плоскость корпуса
EMBOSS = Z_FRONT - 0.0006  # задняя грань выпуклых элементов (чуть утоплена)
POLE_R = 0.039
POLE_Z = -Z_FRONT - 0.05 - POLE_R

# Угол объекта и камера — одинаковые для всех ачивок.
YAW, PITCH, ROLL = -26.0, 7.0, -5.0


def srgb(r, g, b):
    def c(x):
        x /= 255.0
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return (c(r), c(g), c(b))


# Плёнки знаков. white/red утверждены; остальные — стартовые значения ГОСТ,
# проверить на тестовом рендере перед первой ачивкой с ними.
FILM = {
    "white": srgb(226, 226, 220),
    "red": srgb(206, 24, 30),
    "blue": srgb(16, 92, 180),
    "yellow": srgb(250, 190, 20),
    "green": srgb(0, 122, 72),
}

# Металл уровня: корпус, торцы, заклёпки, хомуты, стойка. Без фиолетового и
# радужных переливов: платина — синий анодированный титан в тон акценту.
TIERS = {
    1: {"name": "bronze", "color": srgb(196, 120, 72), "rough": 0.24, "rough_var": 0.14, "aniso": 0.5,
        "grime": srgb(70, 62, 48)},
    2: {"name": "galvanized", "color": srgb(200, 203, 208), "galvanized": True, "aniso": 0.2},
    3: {"name": "gold", "color": srgb(255, 196, 92), "rough": 0.16, "rough_var": 0.12, "aniso": 0.5,
        "grime": srgb(110, 88, 50)},
    4: {"name": "platinum", "color": srgb(110, 165, 250), "rough": 0.13, "rough_var": 0.1, "aniso": 0.5,
        "grime": srgb(90, 104, 124)},
}


# ------------------------------------------------------------- шрифты
def _extract_ttc_face(ttc_path, face_name, out_path):
    """Достаёт одно начертание из .ttc в отдельный .ttf (без fontTools)."""
    data = open(ttc_path, "rb").read()
    assert data[:4] == b"ttcf", ttc_path
    count = struct.unpack(">I", data[8:12])[0]
    offsets = struct.unpack(f">{count}I", data[12:12 + 4 * count])

    def tables(off):
        n = struct.unpack(">H", data[off + 4:off + 6])[0]
        return data[off:off + 4], [struct.unpack(">4sIII", data[off + 12 + 16 * i:off + 28 + 16 * i]) for i in range(n)]

    def full_name(recs):
        for tag, _, toff, _ in recs:
            if tag != b"name":
                continue
            _, n, soff = struct.unpack(">HHH", data[toff:toff + 6])
            for i in range(n):
                pid, _, _, nid, ln, so = struct.unpack(">6H", data[toff + 6 + 12 * i:toff + 18 + 12 * i])
                if nid == 4:
                    raw = data[toff + soff + so:toff + soff + so + ln]
                    return raw.decode("utf-16-be" if pid in (0, 3) else "mac_roman", "ignore")
        return ""

    for off in offsets:
        version, recs = tables(off)
        if full_name(recs) != face_name:
            continue
        head = struct.pack(">4sHHHH", version, len(recs), 0, 0, 0)
        body, dir_ = b"", b""
        pos = 12 + 16 * len(recs)
        for tag, chk, toff, ln in recs:
            chunk = data[toff:toff + ln]
            dir_ += struct.pack(">4sIII", tag, chk, pos + len(body), ln)
            body += chunk + b"\0" * (-len(chunk) % 4)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "wb") as f:
            f.write(head + dir_ + body)
        return out_path
    raise LookupError(f"{face_name} not found in {ttc_path}")


def font_plate():
    """PT Sans Narrow Bold — шрифт табличек 8.x (близок к ГОСТ)."""
    path = os.path.join(FONT_CACHE, "PTSansNarrowBold.ttf")
    if not os.path.exists(path):
        _extract_ttc_face(PT_SANS_TTC, "PT Sans Narrow Bold", path)
    return path


# ---------------------------------------------------------------- ноды
def sock(sockets, name):
    for s in sockets:
        if s.name == name and getattr(s, "enabled", True):
            return s
    raise KeyError(name)


class NB:
    """Короткий конструктор нод материала."""

    def __init__(self, mat):
        mat.use_nodes = True
        self.t = mat.node_tree
        self.t.nodes.clear()
        self.out = self.n("ShaderNodeOutputMaterial")

    def n(self, kind, **props):
        node = self.t.nodes.new(kind)
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def link(self, a, b):
        self.t.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        node = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                node.inputs[i].default_value = x
            else:
                self.link(x, node.inputs[i])
        return node.outputs[0]

    def mix_rgb(self, fac, a, b, blend="MIX"):
        node = self.n("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        for target, x in ((sock(node.inputs, "Factor"), fac), (node.inputs[6], a), (node.inputs[7], b)):
            if isinstance(x, (int, float)):
                target.default_value = x
            elif isinstance(x, tuple):
                target.default_value = (*x, 1.0) if len(x) == 3 else x
            else:
                self.link(x, target)
        return node.outputs[2]

    def ramp(self, fac, stops):
        node = self.n("ShaderNodeValToRGB")
        el = node.color_ramp.elements
        while len(el) > 1:
            el.remove(el[-1])
        for i, (pos, col) in enumerate(stops):
            e = el[0] if i == 0 else el.new(pos)
            e.position = pos
            e.color = (*col, 1.0) if len(col) == 3 else col
        self.link(fac, node.inputs[0])
        return node.outputs[0]

    def coords(self, kind="Object", scale=(1, 1, 1), rot=(0, 0, 0), loc=(0, 0, 0)):
        tc = self.n("ShaderNodeTexCoord")
        mp = self.n("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = scale
        mp.inputs["Rotation"].default_value = rot
        mp.inputs["Location"].default_value = loc
        self.link(tc.outputs[kind], mp.inputs["Vector"])
        return mp.outputs[0]

    def noise(self, vec, scale, detail=4.0, rough=0.5, dist=0.0):
        node = self.n("ShaderNodeTexNoise", noise_dimensions="3D")
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        node.inputs["Distortion"].default_value = dist
        self.link(vec, node.inputs["Vector"])
        return node

    def voronoi(self, vec, scale, feature="F1", rnd=1.0):
        node = self.n("ShaderNodeTexVoronoi", feature=feature)
        node.inputs["Scale"].default_value = scale
        node.inputs["Randomness"].default_value = rnd
        self.link(vec, node.inputs["Vector"])
        return node

    def principled(self):
        p = self.n("ShaderNodeBsdfPrincipled")
        self.link(p.outputs[0], self.out.inputs["Surface"])
        return p

    def bump(self, height, strength, distance=0.001, normal=None):
        node = self.n("ShaderNodeBump")
        node.inputs["Strength"].default_value = strength
        node.inputs["Distance"].default_value = distance
        self.link(height, node.inputs["Height"])
        if normal is not None:
            self.link(normal, node.inputs["Normal"])
        return node.outputs[0]

    def ao(self, distance):
        node = self.n("ShaderNodeAmbientOcclusion", only_local=True)
        node.inputs["Distance"].default_value = distance
        node.samples = 12
        return node.outputs["AO"]


def grime_mask(nb, strength=1.0, ao_dist=0.04):
    """Маска загрязнения: щели (AO) + пятна + потёки сверху вниз."""
    ao = nb.ao(ao_dist)
    crevice = nb.math("POWER", nb.math("SUBTRACT", 1.0, ao, clamp=True), 1.6)
    smudge_n = nb.noise(nb.coords(), 3.5, detail=10, rough=0.62, dist=0.4)
    smudge = nb.ramp(smudge_n.outputs["Fac"], [(0.48, (0, 0, 0)), (0.78, (1, 1, 1))])
    streak_n = nb.noise(nb.coords(scale=(26.0, 1.4, 26.0)), 1.0, detail=6, rough=0.55)
    streak = nb.ramp(streak_n.outputs["Fac"], [(0.55, (0, 0, 0)), (0.85, (0.6, 0.6, 0.6))])
    m = nb.math("MAXIMUM", nb.math("MULTIPLY", smudge, 0.55), nb.math("MULTIPLY", streak, 0.45))
    m = nb.math("ADD", m, crevice)
    return nb.math("MULTIPLY", m, strength, clamp=True)


def scratches(nb, scale=1.0):
    """Тонкие редкие царапины: три сетки вытянутого шума под разными углами."""
    out = None
    for rot, sc in (((0, 0, 0.35), (1.0, 90.0, 1.0)), ((0, 0, -0.9), (1.0, 70.0, 1.0)), ((0, 0, 1.4), (1.0, 120.0, 1.0))):
        n = nb.noise(nb.coords(scale=(sc[0] * scale, sc[1] * scale, 1.0 * scale), rot=rot), 6.0, detail=2, rough=0.4)
        line = nb.ramp(n.outputs["Fac"], [(0.715, (0, 0, 0)), (0.735, (1, 1, 1)), (0.755, (0, 0, 0))])
        sparse = nb.noise(nb.coords(loc=(rot[2], 0, 0)), 4.0, detail=2)
        gate = nb.ramp(sparse.outputs["Fac"], [(0.5, (0, 0, 0)), (0.62, (1, 1, 1))])
        piece = nb.math("MULTIPLY", line, gate)
        out = piece if out is None else nb.math("MAXIMUM", out, piece)
    return out


# ---------------------------------------------------------------- материалы
def film_material(name, color, dirt=0.22):
    """Световозвращающая плёнка: микропризмы, апельсиновая корка, лак, пыль, царапины."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    grime = grime_mask(nb, dirt)
    scr = scratches(nb)
    dirty = nb.mix_rgb(grime, color, srgb(118, 108, 92), "MULTIPLY")
    age = nb.noise(nb.coords(), 1.6, detail=6, rough=0.6)
    age_m = nb.ramp(age.outputs["Fac"], [(0.4, (0, 0, 0)), (0.7, (1, 1, 1))])
    dirty = nb.mix_rgb(nb.math("MULTIPLY", age_m, 0.35), dirty, srgb(232, 220, 190), "MULTIPLY")
    dust = nb.noise(nb.coords(), 260.0, detail=1, rough=0.5)
    dust_m = nb.ramp(dust.outputs["Fac"], [(0.70, (0, 0, 0)), (0.76, (1, 1, 1))])
    dust_gate = nb.noise(nb.coords(), 6.0, detail=2)
    dust_m = nb.math("MULTIPLY", dust_m, nb.ramp(dust_gate.outputs["Fac"], [(0.45, (0, 0, 0)), (0.6, (1, 1, 1))]))
    dirty = nb.mix_rgb(nb.math("MULTIPLY", dust_m, 0.55), dirty, srgb(96, 88, 76))
    col = nb.mix_rgb(nb.math("MULTIPLY", scr, 0.35), dirty, (0.92, 0.92, 0.9))
    nb.link(col, p.inputs["Base Color"])
    rough_n = nb.noise(nb.coords(), 18.0, detail=3)
    rough = nb.math("ADD", nb.math("MULTIPLY", rough_n.outputs["Fac"], 0.16), 0.30)
    rough = nb.math("ADD", rough, nb.math("MULTIPLY", grime, 0.35))
    rough = nb.math("ADD", rough, nb.math("MULTIPLY", scr, 0.3), clamp=True)
    nb.link(rough, p.inputs["Roughness"])
    p.inputs["Specular IOR Level"].default_value = 0.5
    prism = nb.voronoi(nb.coords(), 260.0, rnd=0.0)
    peel = nb.noise(nb.coords(), 70.0, detail=2)
    wave = nb.noise(nb.coords(), 2.2, detail=2)
    h = nb.math("ADD", nb.math("MULTIPLY", prism.outputs["Distance"], 0.25), nb.math("MULTIPLY", peel.outputs["Fac"], 0.6))
    h = nb.math("ADD", h, nb.math("MULTIPLY", scr, -0.8))
    n_fine = nb.bump(h, 0.05, 0.0015)
    nb.link(nb.bump(wave.outputs["Fac"], 0.06, 0.02, normal=n_fine), p.inputs["Normal"])
    p.inputs["Coat Weight"].default_value = 0.35
    p.inputs["Coat Roughness"].default_value = 0.08
    nb.link(nb.bump(wave.outputs["Fac"], 0.08, 0.02), p.inputs["Coat Normal"])
    return mat


def ink_material(name, color=(0.008, 0.008, 0.009), rough=0.34, dirt=0.15):
    """Выпуклая эмаль цифр, букв и окантовки."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    grime = grime_mask(nb, dirt, 0.02)
    scr = scratches(nb, 1.3)
    col = nb.mix_rgb(nb.math("MULTIPLY", scr, 0.25), color, (0.28, 0.28, 0.28))
    col = nb.mix_rgb(nb.math("MULTIPLY", grime, 0.6), col, srgb(70, 64, 54))
    nb.link(col, p.inputs["Base Color"])
    rn = nb.noise(nb.coords(), 24.0, detail=3)
    r = nb.math("ADD", nb.math("MULTIPLY", rn.outputs["Fac"], 0.12), rough)
    r = nb.math("ADD", r, nb.math("MULTIPLY", scr, 0.35), clamp=True)
    nb.link(r, p.inputs["Roughness"])
    peel = nb.noise(nb.coords(), 90.0, detail=2)
    nb.link(nb.bump(peel.outputs["Fac"], 0.03, 0.001), p.inputs["Normal"])
    p.inputs["Coat Weight"].default_value = 0.25
    p.inputs["Coat Roughness"].default_value = 0.12
    return mat


def enamel_gradient(name, bottom, top, y0, y1, rough=0.2):
    """Цветная эмаль пиктограммы с вертикальным градиентом (объектные координаты)."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.link(nb.coords(), sep.inputs[0])
    t = nb.n("ShaderNodeMapRange", clamp=True)
    t.inputs["From Min"].default_value = y0
    t.inputs["From Max"].default_value = y1
    nb.link(sep.outputs["Y"], t.inputs["Value"])
    col = nb.ramp(t.outputs[0], [(0.0, bottom), (1.0, top)])
    grime = grime_mask(nb, 0.12, 0.02)
    col = nb.mix_rgb(grime, col, srgb(120, 100, 80), "MULTIPLY")
    nb.link(col, p.inputs["Base Color"])
    rn = nb.noise(nb.coords(), 30.0, detail=3)
    nb.link(nb.math("ADD", nb.math("MULTIPLY", rn.outputs["Fac"], 0.1), rough), p.inputs["Roughness"])
    p.inputs["Coat Weight"].default_value = 0.7
    p.inputs["Coat Roughness"].default_value = 0.04
    peel = nb.noise(nb.coords(), 90.0, detail=2)
    nb.link(nb.bump(peel.outputs["Fac"], 0.03, 0.001), p.inputs["Normal"])
    return mat


def led_material(name, color, strength=7.0, dots=90.0):
    """Светодиодное поле: светящиеся точки сеткой на тёмной подложке."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    grid = nb.voronoi(nb.coords(), dots, rnd=0.0)
    mask = nb.ramp(grid.outputs["Distance"], [(0.18, (1, 1, 1)), (0.34, (0, 0, 0))])
    p.inputs["Base Color"].default_value = (*[c * 0.25 for c in color], 1.0)
    p.inputs["Emission Color"].default_value = (*color, 1.0)
    nb.link(nb.math("MULTIPLY", mask, strength), p.inputs["Emission Strength"])
    p.inputs["Roughness"].default_value = 0.2
    p.inputs["Coat Weight"].default_value = 1.0
    p.inputs["Coat Roughness"].default_value = 0.03
    return mat


def lens_material(name, color):
    """Выключенная линза: тёмное цветное стекло с кольцами френеля."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = 0.12
    p.inputs["Coat Weight"].default_value = 1.0
    p.inputs["Coat Roughness"].default_value = 0.02
    rings = nb.n("ShaderNodeTexWave", wave_type="RINGS")
    rings.inputs["Scale"].default_value = 28.0
    nb.link(nb.coords(), rings.inputs["Vector"])
    nb.link(nb.bump(rings.outputs["Fac"], 0.12, 0.002), p.inputs["Normal"])
    return mat


def paint_metallic(name, level):
    """Автомобильная краска «металлик» цвета уровня под толстым лаком."""
    color = srgb(205, 210, 218) if TIERS[level].get("galvanized") else TIERS[level]["color"]
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    flakes = nb.voronoi(nb.coords(), 900.0, rnd=1.0)
    tone = nb.ramp(flakes.outputs["Distance"], [(0.0, tuple(c * 1.05 for c in color)), (0.5, tuple(c * 0.86 for c in color))])
    grime = grime_mask(nb, 0.2, 0.03)
    nb.link(nb.mix_rgb(grime, tone, srgb(90, 84, 72), "MULTIPLY"), p.inputs["Base Color"])
    p.inputs["Metallic"].default_value = 0.85
    p.inputs["Roughness"].default_value = 0.32
    p.inputs["Coat Weight"].default_value = 1.0
    p.inputs["Coat Roughness"].default_value = 0.03
    wave = nb.noise(nb.coords(), 3.0, detail=2)
    nb.link(nb.bump(wave.outputs["Fac"], 0.03, 0.02), p.inputs["Coat Normal"])
    return mat


def plain_material(name, color, rough=0.5, metallic=0.0, coat=0.0):
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Coat Weight"].default_value = coat
    return mat


def metal_material(name, tier, axis="Z"):
    """Металл уровня. axis: Z — шлифовка вдоль стойки, R — круговая (корпус)."""
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    p = nb.principled()
    p.inputs["Metallic"].default_value = 1.0
    stretch = {"Z": (90.0, 90.0, 1.2), "X": (1.2, 90.0, 90.0), "R": (60.0, 60.0, 60.0)}[axis]
    brush = nb.noise(nb.coords(scale=stretch), 1.0, detail=8, rough=0.6)
    scr = scratches(nb, 0.8)
    grime = grime_mask(nb, 0.5, 0.05)
    base = tier["color"]
    if tier.get("galvanized"):
        # Оцинковка: кристаллы цинка разного блеска с тонкими границами.
        cells = nb.voronoi(nb.coords(scale=(1, 1, 0.7)), 9.0, rnd=1.0)
        cell_val = nb.n("ShaderNodeSeparateColor")
        nb.link(cells.outputs["Color"], cell_val.inputs[0])
        tone = nb.ramp(cell_val.outputs[0], [(0.0, srgb(150, 154, 160)), (0.5, srgb(196, 199, 204)), (1.0, srgb(222, 224, 228))])
        edges = nb.voronoi(nb.coords(scale=(1, 1, 0.7)), 9.0, "DISTANCE_TO_EDGE", 1.0)
        edge_line = nb.ramp(edges.outputs["Distance"], [(0.0, (0.55, 0.55, 0.55)), (0.025, (1, 1, 1))])
        col = nb.mix_rgb(1.0, tone, edge_line, "MULTIPLY")
        white_rust = nb.noise(nb.coords(), 5.0, detail=8, rough=0.7)
        wr = nb.ramp(white_rust.outputs["Fac"], [(0.6, (0, 0, 0)), (0.75, (1, 1, 1))])
        col = nb.mix_rgb(nb.math("MULTIPLY", wr, 0.35), col, srgb(232, 232, 228))
        rough = nb.ramp(cell_val.outputs[1], [(0.0, (0.22, 0.22, 0.22)), (1.0, (0.42, 0.42, 0.42))])
        rough = nb.math("ADD", rough, nb.math("MULTIPLY", wr, 0.3))
    else:
        col = nb.ramp(brush.outputs["Fac"], [(0.35, tuple(c * 0.9 for c in base)), (0.65, base)])
        rough = nb.math("ADD", nb.math("MULTIPLY", brush.outputs["Fac"], tier["rough_var"]), tier["rough"])
    col = nb.mix_rgb(grime, col, tier.get("grime", srgb(90, 80, 66)), "MULTIPLY")
    col = nb.mix_rgb(nb.math("MULTIPLY", scr, 0.25), col, (0.95, 0.95, 0.95))
    nb.link(col, p.inputs["Base Color"])
    rough = nb.math("ADD", rough, nb.math("MULTIPLY", grime, 0.25))
    rough = nb.math("ADD", rough, nb.math("MULTIPLY", scr, 0.25), clamp=True)
    nb.link(rough, p.inputs["Roughness"])
    p.inputs["Anisotropic"].default_value = tier.get("aniso", 0.4)
    h = nb.math("ADD", nb.math("MULTIPLY", brush.outputs["Fac"], 0.5), nb.math("MULTIPLY", scr, -0.6))
    nb.link(nb.bump(h, 0.04, 0.001), p.inputs["Normal"])
    return mat


class Materials:
    """Стандартные материалы уровня: плёнки, эмаль и металл."""

    def __init__(self, level):
        tier = TIERS[level]
        self.white = film_material("FilmWhite", FILM["white"], dirt=0.3)
        self.ink = ink_material("InkBlack")
        self.metal_disc = metal_material("MetalDisc", tier, "R")
        self.metal_pole = metal_material("MetalPole", tier, "Z")
        self.rivet = metal_material("MetalRivet", dict(tier, rough=tier.get("rough", 0.25) * 0.8), "R")
        self._films = {"white": self.white}

    def film(self, color_name, dirt=0.18):
        if color_name not in self._films:
            self._films[color_name] = film_material(f"Film_{color_name}", FILM[color_name], dirt=dirt)
        return self._films[color_name]


# ---------------------------------------------------------------- геометрия
def bezier_spline(cu, path):
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(path) - 1)
    for bp, (a, hi, ho) in zip(sp.bezier_points, path):
        bp.co = (a[0], a[1], 0)
        bp.handle_left = (hi[0], hi[1], 0)
        bp.handle_right = (ho[0], ho[1], 0)
        bp.handle_left_type = bp.handle_right_type = "FREE"
    sp.use_cyclic_u = True
    return sp


def scale_path(path, w, ox, oy):
    """Путь из нормированных координат 0..1 → размер w, сдвиг (ox, oy)."""
    return [((a[0] * w + ox, a[1] * w + oy), (hi[0] * w + ox, hi[1] * w + oy), (ho[0] * w + ox, ho[1] * w + oy))
            for a, hi, ho in path]


def circle_path(r, cx=0.0, cy=0.0, n=8):
    """Окружность из n кубических Безье."""
    k = 4.0 / 3.0 * math.tan(math.pi / (2 * n)) * r
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        px, py = cx + r * math.cos(a), cy + r * math.sin(a)
        tx, ty = -math.sin(a), math.cos(a)
        pts.append(((px, py), (px - k * tx, py - k * ty), (px + k * tx, py + k * ty)))
    return pts


def polygon_path(points):
    """Многоугольник с прямыми рёбрами (скругление даёт фаска кривой)."""
    return [(p, p, p) for p in points]


def rounded_polygon_path(points, r):
    """Многоугольник со скруглёнными углами радиуса r (дуги — кубические Безье)."""
    n = len(points)
    out = []
    for i in range(n):
        p = Vector((*points[i], 0))
        a = Vector((*points[i - 1], 0))
        b = Vector((*points[(i + 1) % n], 0))
        la, lb = (a - p).length, (b - p).length
        if la < 1e-9 or lb < 1e-9:
            continue
        u, v = (a - p) / la, (b - p) / lb
        theta = u.angle(v)
        if theta < 1e-4 or theta > math.pi - 1e-4:
            out.append(((p.x, p.y), (p.x, p.y), (p.x, p.y)))
            continue
        # Радиус не больше, чем позволяют соседние рёбра: иначе контур
        # перехлёстывается и даёт выбросы.
        d = min(r / math.tan(theta / 2), 0.45 * min(la, lb))
        r = d * math.tan(theta / 2)
        h = 4 / 3 * math.tan((math.pi - theta) / 4) * r
        p1, p2 = p + u * d, p + v * d
        out.append(((p1.x, p1.y), (p1.x, p1.y), ((p1 - u * h).x, (p1 - u * h).y)))
        out.append(((p2.x, p2.y), ((p2 - v * h).x, (p2 - v * h).y), (p2.x, p2.y)))
    return out


def round_corner(a, p, b, r):
    """Скругление одной вершины p между соседями a и b: 1–2 точки пути."""
    return _corner_points(a, p, b, r)


def _corner_points(a, p, b, r):
    pa, pp, pb = Vector((*a, 0)), Vector((*p, 0)), Vector((*b, 0))
    la, lb = (pa - pp).length, (pb - pp).length
    if la < 1e-9 or lb < 1e-9:
        return [(p, p, p)]
    u, v = (pa - pp) / la, (pb - pp) / lb
    theta = u.angle(v)
    if theta < 1e-4 or theta > math.pi - 1e-4:
        return [(p, p, p)]
    d = min(r / math.tan(theta / 2), 0.45 * min(la, lb))
    r = d * math.tan(theta / 2)
    h = 4 / 3 * math.tan((math.pi - theta) / 4) * r
    p1, p2 = pp + u * d, pp + v * d
    return [((p1.x, p1.y), (p1.x, p1.y), ((p1 - u * h).x, (p1 - u * h).y)),
            ((p2.x, p2.y), ((p2 - v * h).x, (p2 - v * h).y), (p2.x, p2.y))]


def regular_points(n, circum_r, cx=0.0, cy=0.0, start=math.pi / 2):
    return [(cx + circum_r * math.cos(start + 2 * math.pi * i / n), cy + circum_r * math.sin(start + 2 * math.pi * i / n))
            for i in range(n)]


def rotate_path(path, ang, cx=0.0, cy=0.0):
    c, s_ = math.cos(ang), math.sin(ang)

    def rot(q):
        x, y = q[0] - cx, q[1] - cy
        return (cx + x * c - y * s_, cy + x * s_ + y * c)
    return [(rot(a), rot(hi), rot(ho)) for a, hi, ho in path]


def rrect_path(w, h, r, cx=0.0, cy=0.0):
    """Скруглённый прямоугольник: 8 точек, дуги — кубические Безье."""
    k = 0.5523 * r
    x0, x1, y0, y1 = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
    arcs = [
        ((x1 - r, y0), (x1 - r + k, y0), (x1, y0 + r - k), (x1, y0 + r)),
        ((x1, y1 - r), (x1, y1 - r + k), (x1 - r + k, y1), (x1 - r, y1)),
        ((x0 + r, y1), (x0 + r - k, y1), (x0, y1 - r + k), (x0, y1 - r)),
        ((x0, y0 + r), (x0, y0 + r - k), (x0 + r - k, y0), (x0 + r, y0)),
    ]
    pts = []
    for a, ha, hb, b in arcs:
        pts.append((a, a, ha))
        pts.append((b, hb, b))
    return pts


def curve_mesh(name, paths, extrude, bevel, z_back, mats, side_index=0, res=48, bres=4):
    """2D-кривая → залитая, выдавленная, скруглённая сетка. Задняя грань на z_back.
    Фаска раздувает контур на bevel — уменьшайте контур заранее."""
    cu = bpy.data.curves.new(name + "_cu", "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.resolution_u = res
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = bres
    for path in paths:
        bezier_spline(cu, path)
    return _finish_curve(name, cu, extrude + bevel, z_back, mats, side_index)


def _finish_curve(name, cu, half, z_back, mats, side_index):
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    bpy.context.scene.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    me.name = name
    for v in me.vertices:
        v.co.z += z_back + half
    for m in mats:
        me.materials.append(m)
    for poly in me.polygons:
        nz = poly.normal.z
        poly.material_index = 0 if nz > 0.9999 else (min(1, len(mats) - 1) if nz < -0.9999 else side_index)
        poly.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(35))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def text_mesh(name, body, font_path, cap_height, extrude, bevel, z_back, mats, cx=0.0, cy=0.0, spacing=1.0):
    """Выпуклый текст высотой cap_height по габариту. Возвращает (объект, ширина)."""
    cu = bpy.data.curves.new(name + "_cu", "FONT")
    cu.body = body
    cu.font = bpy.data.fonts.load(font_path, check_existing=True)
    cu.size = 1.0
    cu.space_character = spacing
    cu.align_x = "CENTER"
    cu.align_y = "BOTTOM_BASELINE"
    cu.resolution_u = 24
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 3
    cu.offset = -bevel * 0.6  # компенсация «распухания» от фаски
    obj = _finish_curve(name, cu, extrude + bevel, z_back, mats, 0)
    me = obj.data
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    s = cap_height / (max(ys) - min(ys))
    mx, my = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    for v in me.vertices:
        v.co.x = (v.co.x - mx) * s
        v.co.y = (v.co.y - my) * s
    obj.location = (cx, cy, 0)
    return obj, (max(xs) - min(xs)) * s


def cylinder(name, r, y0, y1, z, mats, verts=96):
    """Цилиндр вдоль оси y (стойка, хомут)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=y1 - y0, location=(0, (y0 + y1) / 2, z),
                                        rotation=(math.pi / 2, 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    for m in mats:
        obj.data.materials.append(m)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.set_sharp_from_angle(angle=math.radians(40))
    return obj


def box(name, size, loc, mat, bevel=0.003):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.set_sharp_from_angle(angle=math.radians(40))
    return obj


def rivet(name, x, y, z_back, mat, r=0.0115):
    """Куполообразная заклёпка с шайбой."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r, location=(x, y, z_back))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (1, 1, 0.42)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r * 1.45, depth=0.0016, location=(x, y, z_back + 0.0008))
    washer = bpy.context.active_object
    washer.name = name + "_washer"
    washer.data.materials.append(mat)
    return [obj, washer]


# --------------------------------------------------------- детали знаков
def sign_body(name, outline, mats, res=32):
    """Корпус знака/таблички: плёнка спереди, металл уровня на торце и сзади.
    outline — контур, уже уменьшенный на T_B (фаска его раздует)."""
    return curve_mesh(name, [outline], T_E, T_B, -Z_FRONT, [mats.white, mats.metal_disc], side_index=1, res=res, bres=6)


def round_sign(mats, ring_color="red", r=R_SIGN):
    """Круглый знак с выпуклым цветным кольцом (как 3.24) и двумя заклёпками."""
    ring_out, ring_in = 0.468 * r / R_SIGN, 0.372 * r / R_SIGN
    ring_e, ring_b = 0.0022, 0.0038
    parts = [
        sign_body("SignBody", circle_path(r - T_B), mats),
        curve_mesh("SignRing", [circle_path(ring_out - ring_b), circle_path(ring_in + ring_b)],
                   ring_e, ring_b, EMBOSS, [mats.film(ring_color)], res=32, bres=4),
    ]
    for i, yy in enumerate((ring_out + ring_in) / 2 * s for s in (1, -1)):
        parts += rivet(f"SignRivet{i}", 0.0, yy, Z_FRONT + 0.0108, mats.rivet)
    return parts


def sign_number(mats, number, cy=0.0):
    """Число на знаке: DIN Condensed Bold, 0.45 диаметра (2 цифры) или 0.36 (3+)."""
    obj, _ = text_mesh("SignNumber", number, FONT_DIGITS, 0.45 if len(number) < 3 else 0.36,
                       0.0026, 0.0034, EMBOSS, [mats.ink], cy=cy, spacing=1.04)
    return obj


def plate_8x(mats, y, w=0.90, h=0.315, r=0.042):
    """Табличка 8.x под знаком: белая плёнка, чёрная окантовка, две заклёпки."""
    inset, bw, fb = 0.02, 0.013, 0.0024
    o_w, o_h = w - 2 * inset, h - 2 * inset
    parts = [
        sign_body("PlateBody", rrect_path(w - 2 * T_B, h - 2 * T_B, r - T_B, 0, y), mats, res=16),
        curve_mesh("PlateFrame", [rrect_path(o_w - 2 * fb, o_h - 2 * fb, r - inset - fb, 0, y),
                                  rrect_path(o_w - 2 * bw + 2 * fb, o_h - 2 * bw + 2 * fb, max(0.004, r - inset - bw + fb), 0, y)],
                   0.001, fb, EMBOSS, [mats.ink], res=16, bres=3),
    ]
    for i, xx in enumerate((-1, 1)):
        parts += rivet(f"PlateRivet{i}", xx * (w / 2 - 0.05), y, Z_FRONT + 0.0004, mats.rivet, r=0.0105)
    return parts


def plate_text(mats, text, y, x=0.0, max_w=None):
    """Подпись таблички: PT Sans Narrow Bold, высота 0.142; длинное слово
    уменьшается до max_w. Возвращает (объект, ширина)."""
    obj, w = text_mesh("PlateWord", text, font_plate(), 0.142, 0.0018, 0.0026, EMBOSS, [mats.ink], cx=x, cy=y, spacing=1.06)
    if max_w and w > max_w:
        k = max_w / w
        obj.scale = (k, k, 1)
        w = max_w
    return obj, w


def plate_icon_word(mats, y, word, icon_w, build_icon, w=0.90):
    """Пиктограмма слева + слово справа, вместе по центру таблички.
    build_icon(cx) возвращает детали пиктограммы с центром в x=cx."""
    gap = 0.035
    word_obj, ww = plate_text(mats, word, y, max_w=w - 0.17 - icon_w - gap)
    x0 = -(icon_w + gap + ww) / 2
    parts = build_icon(x0 + icon_w / 2)
    word_obj.location.x = x0 + icon_w + gap + ww / 2
    return parts + [word_obj]


def plate_number(mats, y, number, w=0.62, h=0.315):
    """Табличка 8.x только с числом (DIN Condensed Bold)."""
    parts = plate_8x(mats, y, w=w, h=h)
    num, _ = text_mesh("PlateNumber", number, FONT_DIGITS, 0.19, 0.0022, 0.003, EMBOSS, [mats.ink], cy=y, spacing=1.06)
    return parts + [num]


def exclamation(mats, cx, cy, h):
    """Восклицательный знак высотой h: скруглённая черта и точка."""
    bar_h, dot_r = h * 0.68, h * 0.125
    return [
        curve_mesh("ExclBar", [rrect_path(h * 0.2, bar_h, h * 0.09, cx, cy + h / 2 - bar_h / 2)],
                   0.002, 0.003, EMBOSS, [mats.ink], res=12, bres=3),
        curve_mesh("ExclDot", [circle_path(dot_r, cx, cy - h / 2 + dot_r)], 0.002, 0.003, EMBOSS, [mats.ink], res=12, bres=3),
    ]


def pole(mats, mounts_y, top=0.32, plate_rails=()):
    """Стойка с кронштейнами и хомутами. mounts_y — высоты креплений."""
    parts = [cylinder("Pole", POLE_R, -2.6, top, POLE_Z, [mats.metal_pole]),
             cylinder("PoleCap", POLE_R * 1.08, top, top + 0.025, POLE_Z, [mats.ink], verts=64)]
    depth = abs(POLE_Z) - Z_FRONT - POLE_R * 0.6
    for i, yy in enumerate(mounts_y):
        rail = 0.5 if yy in plate_rails else 0.34
        parts.append(box(f"Standoff{i}", (0.07, 0.035, depth), (0, yy, -Z_FRONT - depth / 2), mats.metal_pole))
        parts.append(box(f"Rail{i}", (rail, 0.04, 0.008), (0, yy, -Z_FRONT - 0.004), mats.metal_pole))
        parts.append(cylinder(f"Clamp{i}", POLE_R + 0.006, yy - 0.02, yy + 0.02, POLE_Z, [mats.metal_pole], verts=64))
        for sx in (-1, 1):
            parts.append(box(f"ClampEar{i}{sx}", (0.012, 0.04, 0.03), (sx * (POLE_R + 0.012), yy, POLE_Z - POLE_R * 0.2),
                             mats.metal_pole, 0.002))
    return parts


# ---------------------------------------------------------- сборка и рендер
def assemble(parts, yaw=YAW, pitch=PITCH, roll=ROLL):
    """Локальная система детали → мир (лицо к камере), стандартный угол 3/4."""
    root = bpy.data.objects.new("Badge", None)
    bpy.context.scene.collection.objects.link(root)
    frame = bpy.data.objects.new("SignFrame", None)
    bpy.context.scene.collection.objects.link(frame)
    frame.parent = root
    frame.rotation_euler = (math.pi / 2, 0, 0)
    for p in parts:
        p.parent = frame
    root.rotation_mode = "XYZ"
    root.rotation_euler = (math.radians(pitch), math.radians(roll), math.radians(yaw))
    return root


def setup_world_and_lights():
    """Студия: мягкий ключ слева сверху, заполняющий справа, два контровых,
    верхний и отражающие панели — их видно только в бликах металла."""
    sc = bpy.context.scene
    world = bpy.data.worlds.new("Studio")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.4
    hdri = os.path.normpath(STUDIO_HDRI)
    if os.path.exists(hdri):
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(hdri)
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, math.radians(200))
        nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
        nt.links.new(mp.outputs[0], env.inputs["Vector"])
        nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    else:
        print("WARNING: studio.exr not found, metal reflections will be flat:", hdri)
    nt.links.new(bg.outputs[0], out.inputs["Surface"])

    def area(name, loc, size, energy, color, size_y=None, target=(0, 0, -0.25)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.color = color
        ld.shape = "RECTANGLE"  # по умолчанию SQUARE и size_y игнорируется
        ld.size = size
        if size_y:
            ld.size_y = size_y
        ob = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(ob)
        ob.location = loc
        ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

    area("Key", (-2.6, -3.2, 2.8), 1.6, 560, (1.0, 0.97, 0.93))
    area("Fill", (3.4, -2.4, 0.2), 3.5, 90, (0.92, 0.96, 1.0))
    area("Rim", (1.8, 2.6, 1.6), 0.6, 260, (1.0, 1.0, 1.0), size_y=3.0)
    area("RimL", (-2.4, 2.2, -0.6), 0.6, 120, (1.0, 0.98, 0.95), size_y=3.0)
    area("Top", (0.0, -0.6, 3.8), 4.0, 70, (1.0, 1.0, 1.0))

    def card(name, loc, size, strength, target=(0, 0, -0.3)):
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc)
        ob = bpy.context.active_object
        ob.name = name
        ob.scale = (size[0], size[1], 1)
        ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("Z", "Y").to_euler()
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        mt = m.node_tree
        mt.nodes.clear()
        em = mt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = strength
        mo = mt.nodes.new("ShaderNodeOutputMaterial")
        mt.links.new(em.outputs[0], mo.inputs["Surface"])
        ob.data.materials.append(m)
        ob.visible_camera = False
        ob.visible_diffuse = False
        ob.visible_shadow = False

    card("CardLeft", (-2.2, -1.6, -0.2), (1.2, 4.0), 2.2)
    card("CardRight", (2.4, -0.4, 0.2), (0.8, 4.0), 1.4)
    card("CardTop", (0.0, 0.4, 2.6), (3.0, 1.2), 1.2)


def setup_camera_and_render(out, res=2048, samples=384, cpu=False, frame=1.0, cam_z=-0.72):
    sc = bpy.context.scene
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = 85
    cam_d.sensor_width = 36
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    target = Vector((0.0, 0.0, -0.33))
    # Чуть снизу: знак смотрит на зрителя. frame > 1 отодвигает камеру для высоких объектов.
    cam.location = target + (Vector((0.0, -4.55, cam_z)) - target) * frame
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

    sc.render.engine = "CYCLES"
    cy = sc.cycles
    if not cpu:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "METAL"
        cy.device = "GPU"
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.006
    cy.use_denoising = True
    try:
        cy.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    cy.max_bounces = 12
    cy.glossy_bounces = 6
    cy.caustics_reflective = False
    cy.caustics_refractive = False
    cy.blur_glossy = 0.5
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.filter_size = 1.2
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    # Khronos PBR Neutral сохраняет насыщенность плёнок; AgX уводит красный в розовый.
    sc.view_settings.view_transform = "Khronos PBR Neutral"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = -0.4
    sc.render.filepath = out


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
