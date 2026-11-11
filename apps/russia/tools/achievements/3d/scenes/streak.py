"""«Без пропусков» (streak): знак-ограничение с числом дней + табличка 8.x
с огоньком. Эталон формата, утверждён владельцем 11.11.2026."""

from scenes.streak_flame import INNER, OUTER

# Уровень → (число на знаке, подпись таблички). Пороги — AchievementThresholds.streak.
LEVELS = {
    1: ("3", "ДНЯ"),
    2: ("7", "ДНЕЙ"),
    3: ("14", "ДНЕЙ"),
    4: ("30", "ДНЕЙ"),
}

PLATE_W, PLATE_H, PLATE_GAP = 0.90, 0.315, 0.04


def build(kit, level):
    number, label = LEVELS[level]
    mats = kit.Materials(level)
    flame_outer = kit.enamel_gradient("FlameOuter", kit.srgb(255, 112, 26), kit.srgb(226, 36, 30), -0.1, 0.1)
    flame_inner = kit.enamel_gradient("FlameInner", kit.srgb(255, 214, 72), kit.srgb(255, 150, 30), -0.06, 0.06)

    parts = kit.round_sign(mats, ring_color="red")
    parts.append(kit.sign_number(mats, number))

    plate_y = -kit.R_SIGN - PLATE_GAP - PLATE_H / 2
    parts += kit.plate_8x(mats, plate_y, w=PLATE_W, h=PLATE_H)

    # Огонёк + слово, вместе по центру таблички.
    flame_h, gap = 0.205, 0.035
    word, word_w = kit.plate_text(mats, label, plate_y)
    total = flame_h * 0.84 + gap + word_w
    x0 = -total / 2
    ox, oy = x0 + flame_h * 0.42 - flame_h / 2, plate_y + 0.004 - flame_h / 2
    parts.append(kit.curve_mesh("FlameOuter", [kit.scale_path(OUTER, flame_h, ox, oy)],
                                0.0035, 0.0035, kit.EMBOSS, [flame_outer], res=24, bres=4))
    parts.append(kit.curve_mesh("FlameInner", [kit.scale_path(INNER, flame_h, ox, oy)],
                                0.002, 0.003, kit.EMBOSS + 0.012, [flame_inner], res=24, bres=4))
    word.location = (x0 + flame_h * 0.84 + gap + word_w / 2, plate_y, 0)
    parts.append(word)

    parts += kit.pole(mats, mounts_y=(0.2, -0.2, plate_y), plate_rails=(plate_y,))
    return parts
