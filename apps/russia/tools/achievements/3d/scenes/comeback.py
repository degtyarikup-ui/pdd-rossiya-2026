"""«Возвращение» (comeback): знак «Место для разворота» (6.3.1) — вернулся
к учёбе. Без числа и таблички; уровень — металл знака и стойки."""

import math

LEVELS = {1: None, 2: None, 3: None, 4: None}

SIDE, CORNER, EDGE = 0.92, 0.07, 0.028
BAR, GAP_X, ARC_Y = 0.13, 0.17, 0.12        # толщина стрелки, полуразнос ветвей, центр дуги


def build(kit, level):
    mats = kit.Materials(level)
    white = kit.enamel_gradient("WhiteEnamel", kit.srgb(228, 228, 224), kit.srgb(250, 250, 246), -0.3, 0.3, rough=0.22)
    cy = 0.0
    parts = [kit.sign_body("SignBody", kit.rrect_path(SIDE - 2 * kit.T_B, SIDE - 2 * kit.T_B, CORNER - kit.T_B, 0, cy), mats)]
    e, b = 0.0022, 0.0038
    inner = SIDE - 2 * EDGE
    parts.append(kit.curve_mesh("SignBlue", [kit.rrect_path(inner - 2 * b, inner - 2 * b, CORNER - EDGE, 0, cy)],
                                e, b, kit.EMBOSS, [mats.film("blue")], res=16, bres=4))
    # Стрелка разворота одним контуром: левая ветвь вверх, дуга, правая ветвь вниз с наконечником.
    ro, ri = GAP_X + BAR / 2, GAP_X - BAR / 2
    pts = [(-ro, -0.3), (-ri, -0.3), (-ri, ARC_Y)]
    pts += [(ri * math.cos(a), ARC_Y + ri * math.sin(a)) for a in (math.pi - k * math.pi / 14 for k in range(1, 14))]
    pts += [(ri, ARC_Y), (ri, -0.07), (GAP_X - 0.15, -0.07), (GAP_X, -0.3), (GAP_X + 0.15, -0.07), (ro, -0.07), (ro, ARC_Y)]
    pts += [(ro * math.cos(a), ARC_Y + ro * math.sin(a)) for a in (k * math.pi / 14 for k in range(1, 14))]
    pts += [(-ro, ARC_Y)]
    parts.append(kit.curve_mesh("UTurn", [kit.polygon_path(pts)], 0.003, 0.004, kit.EMBOSS + 0.011, [white], res=4, bres=4))
    for i, yy in enumerate((cy + SIDE / 2 - 0.045, cy - SIDE / 2 + 0.045)):
        parts += kit.rivet(f"SignRivet{i}", 0.0, yy, kit.Z_FRONT + 0.0004, mats.rivet)
    parts += kit.pole(mats, mounts_y=(0.2, -0.2))
    return parts
