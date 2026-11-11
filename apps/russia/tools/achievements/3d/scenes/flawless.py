"""«Без единой ошибки» (flawless): ромб «Главная дорога» (2.1) — дорога без
ошибок; число на жёлтом поле. Без таблички."""

import math


LEVELS = {1: "1", 2: "3", 3: "5", 4: "10"}

R = 0.565            # полудиагональ ромба (сторона 0.8)
CORNER = 0.05
YELLOW_INSET = 0.085
S2 = math.sqrt(2)


def diamond(kit, half_diag, corner):
    return kit.rounded_polygon_path(kit.regular_points(4, half_diag), corner)


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)

    parts = [kit.sign_body("SignBody", diamond(kit, R - kit.T_B * S2, CORNER), mats)]
    e, b = 0.0022, 0.0038
    parts.append(kit.curve_mesh("SignYellow", [diamond(kit, R - (YELLOW_INSET + b) * S2, CORNER * 0.7)],
                                e, b, kit.EMBOSS, [mats.film("yellow")], res=32, bres=4))
    num, _ = kit.text_mesh("SignNumber", number, kit.FONT_DIGITS, 0.34, 0.0026, 0.0034, kit.EMBOSS + 0.011,
                           [mats.ink], spacing=1.04)
    parts.append(num)
    for i, yy in enumerate((R - 0.05, -(R - 0.05))):
        parts += kit.rivet(f"SignRivet{i}", 0.0, yy, kit.Z_FRONT + 0.0004, mats.rivet)

    parts += kit.pole(mats, mounts_y=(0.22, -0.22))
    return parts
