"""«Знаток знаков» (signSwiper): веер из трёх знаков на одной стойке, как
карты в руке (игра-свайпер); очки на табличке под веером."""

import math

import bpy

FRAME = 1.1
LEVELS = {1: "100", 2: "200", 3: "300", 4: "450"}

PIVOT_Y = -0.18
DIST = 0.40          # от оси веера до центра знака
R = 0.34             # радиус круглых знаков


def card(kit, name, angle, z, parts):
    """Знак-карта: детали строятся вокруг (0, DIST), затем веер поворачивает их."""
    empty = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = (0, PIVOT_Y, z)
    empty.rotation_euler = (0, 0, math.radians(angle))
    for p in parts:
        p.location.y += -PIVOT_Y + 0.0  # детали построены в координатах веера
        p.parent = empty
    return empty


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    white = kit.enamel_gradient("WhiteEnamel", kit.srgb(228, 228, 224), kit.srgb(250, 250, 246), -0.3, 0.3, rough=0.22)
    e, b = 0.0022, 0.0038
    c = DIST  # центр знака в координатах карты (ось веера — начало координат)

    # Левая карта: «Прочие опасности».
    tri_ri = 0.2
    tri = lambda ri, r: kit.rounded_polygon_path(kit.regular_points(3, 2 * ri, 0, c - 0.03), r)  # noqa: E731
    left = [kit.sign_body("TriBody", tri(tri_ri + 0.02 - kit.T_B, 0.05), mats),
            kit.curve_mesh("TriBand", [tri(tri_ri + 0.02 - 0.015 - b, 0.04), tri(tri_ri + 0.02 - 0.085 + b, 0.02)],
                           e, b, kit.EMBOSS, [mats.film("red")], res=24, bres=4)]
    left += kit.exclamation(mats, 0, c - 0.045, 0.17)

    # Центральная карта: «Въезд запрещён».
    mid = [kit.sign_body("NoEntryBody", kit.circle_path(R - kit.T_B, 0, c), mats),
           kit.curve_mesh("NoEntryRed", [kit.circle_path(R - 0.02 - b, 0, c)], e, b, kit.EMBOSS, [mats.film("red")], res=32, bres=4),
           kit.curve_mesh("NoEntryBar", [kit.rrect_path(0.42, 0.11, 0.012, 0, c)], 0.002, 0.003, kit.EMBOSS + 0.011, [mats.white],
                          res=8, bres=3)]

    # Правая карта: «Движение прямо».
    arrow = [(0, 0.2), (0.12, 0.06), (0.045, 0.06), (0.045, -0.2), (-0.045, -0.2), (-0.045, 0.06), (-0.12, 0.06)]
    right = [kit.sign_body("AheadBody", kit.circle_path(R - kit.T_B, 0, c), mats),
             kit.curve_mesh("AheadBlue", [kit.circle_path(R - 0.02 - b, 0, c)], e, b, kit.EMBOSS, [mats.film("blue")], res=32, bres=4),
             kit.curve_mesh("AheadArrow", [kit.rounded_polygon_path([(x, y + c) for x, y in arrow], 0.012)],
                            0.003, 0.004, kit.EMBOSS + 0.011, [white], res=8, bres=4)]

    parts = [card(kit, "CardLeft", 40, 0.0, left), card(kit, "CardRight", -40, 0.0, right), card(kit, "CardMid", 0, 0.045, mid)]
    # Детали карт заданы от оси веера, а card() сдвигает их на -PIVOT_Y: вернуть.
    for empty in parts:
        for ch in empty.children:
            ch.location.y += PIVOT_Y

    plate_y = PIVOT_Y - 0.21 - 0.04 - 0.315 / 2
    parts += kit.plate_number(mats, plate_y, number)
    parts += kit.pole(mats, mounts_y=(PIVOT_Y + 0.25, plate_y), top=PIVOT_Y + 0.35, plate_rails=(plate_y,))
    return parts
