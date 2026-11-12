"""«Знаток квиза» (quiz): красный восьмиугольник «СТОП», на котором вместо
слова — знак вопроса («стоп, подумай»); серия верных ответов на табличке."""

import math

FRAME = 1.15
LEVELS = {1: "10", 2: "25", 3: "50", 4: "100"}

R, EDGE = 0.54, 0.03


def octagon(kit, circum_r, corner):
    return kit.rounded_polygon_path(kit.regular_points(8, circum_r, start=math.pi / 8), corner)


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    white = kit.enamel_gradient("WhiteEnamel", kit.srgb(228, 228, 224), kit.srgb(250, 250, 246), -0.3, 0.3, rough=0.22)

    parts = [kit.sign_body("SignBody", octagon(kit, R - kit.T_B, 0.03), mats)]
    e, b = 0.0022, 0.0038
    parts.append(kit.curve_mesh("SignRed", [octagon(kit, R - EDGE - b, 0.02)], e, b, kit.EMBOSS, [mats.film("red")],
                                res=16, bres=4))
    q, _ = kit.text_mesh("Question", "?", kit.FONT_DIGITS, 0.56, 0.003, 0.004, kit.EMBOSS + 0.011, [white], cy=0.0)
    parts.append(q)
    for i, yy in enumerate((R * 0.82, -R * 0.82)):
        parts += kit.rivet(f"SignRivet{i}", 0.0, yy, kit.Z_FRONT + 0.0108, mats.rivet)

    inner = R * math.cos(math.pi / 8)
    plate_y = -inner - 0.04 - 0.315 / 2
    parts += kit.plate_number(mats, plate_y, number)
    parts += kit.pole(mats, mounts_y=(0.2, -0.2, plate_y), plate_rails=(plate_y,))
    return parts
