"""«Марафонец» (marathon): знак «Конец зоны всех ограничений» (3.31) —
марафон без ограничений; число вопросов подряд на табличке."""

import math

FRAME = 1.15
LEVELS = {1: "50", 2: "150", 3: "400", 4: "800"}


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    r = kit.R_SIGN
    parts = [kit.sign_body("SignBody", kit.circle_path(r - kit.T_B), mats)]
    parts.append(kit.curve_mesh("SignEdge", [kit.circle_path(0.47), kit.circle_path(0.448)], 0.001, 0.0024, kit.EMBOSS,
                                [mats.ink], res=32, bres=3))
    # Диагональная полоса из пяти тонких линий.
    for i, d in enumerate((-0.088, -0.044, 0.0, 0.044, 0.088)):
        half = math.sqrt(0.43 ** 2 - d ** 2)
        bar = kit.rotate_path(kit.rrect_path(2 * half, 0.02, 0.008, 0, d), math.radians(45))
        parts.append(kit.curve_mesh(f"Stripe{i}", [bar], 0.0012, 0.0024, kit.EMBOSS, [mats.ink], res=8, bres=3))
    for i, yy in enumerate((0.39, -0.39)):
        parts += kit.rivet(f"SignRivet{i}", 0.0, yy, kit.Z_FRONT + 0.0004, mats.rivet)

    plate_y = -r - 0.04 - 0.315 / 2
    parts += kit.plate_number(mats, plate_y, number)
    parts += kit.pole(mats, mounts_y=(0.2, -0.2, plate_y), plate_rails=(plate_y,))
    return parts
