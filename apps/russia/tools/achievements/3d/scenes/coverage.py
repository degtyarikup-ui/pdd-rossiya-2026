"""«Эрудит» (coverage): синий квадратный знак с белой «i» — «информация»;
число решённых вопросов на табличке под знаком."""

LEVELS = {1: "100", 2: "300", 3: "500", 4: "800"}

SIDE, CORNER, EDGE = 0.92, 0.07, 0.028


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    white = kit.enamel_gradient("WhiteEnamel", kit.srgb(228, 228, 224), kit.srgb(250, 250, 246), -0.3, 0.3, rough=0.22)

    cy = 0.04
    parts = [kit.sign_body("SignBody", kit.rrect_path(SIDE - 2 * kit.T_B, SIDE - 2 * kit.T_B, CORNER - kit.T_B, 0, cy), mats)]
    e, b = 0.0022, 0.0038
    inner = SIDE - 2 * EDGE
    parts.append(kit.curve_mesh("SignBlue", [kit.rrect_path(inner - 2 * b, inner - 2 * b, CORNER - EDGE, 0, cy)],
                                e, b, kit.EMBOSS, [mats.film("blue")], res=16, bres=4))
    z = kit.EMBOSS + 0.011
    parts.append(kit.curve_mesh("InfoDot", [kit.circle_path(0.068, 0, cy + 0.205)], 0.003, 0.004, z, [white], res=16, bres=4))
    parts.append(kit.curve_mesh("InfoBar", [kit.rrect_path(0.128, 0.37, 0.03, 0, cy - 0.075)], 0.003, 0.004, z, [white], res=12, bres=4))
    for i, yy in enumerate((cy + SIDE / 2 - 0.045, cy - SIDE / 2 + 0.045)):
        parts += kit.rivet(f"SignRivet{i}", 0.0, yy, kit.Z_FRONT + 0.0004, mats.rivet)

    plate_y = cy - SIDE / 2 - 0.04 - 0.315 / 2
    parts += kit.plate_number(mats, plate_y, number)
    parts += kit.pole(mats, mounts_y=(cy + 0.22, cy - 0.22, plate_y), plate_rails=(plate_y,))
    return parts
