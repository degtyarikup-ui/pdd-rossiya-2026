"""«Ранняя пташка» (earlyBird): часы, на них 7:00. Без числа;
уровень — металл массивного ободка. Парят без стойки."""

import math

VIEW = {"yaw": -24.0, "pitch": 0.0, "roll": 0.0, "cam_z": 0.3}
LEVELS = {1: None, 2: None, 3: None, 4: None}


def build(kit, level):
    mats = kit.Materials(level)
    r = kit.R_SIGN
    parts = [kit.sign_body("ClockBody", kit.circle_path(r - kit.T_B), mats),
             kit.curve_mesh("Bezel", [kit.circle_path(r - 0.012), kit.circle_path(0.425)], 0.01, 0.012, kit.EMBOSS,
                            [mats.metal_disc], res=32, bres=5)]
    for k in range(12):
        big = k % 3 == 0
        tick = kit.rotate_path(kit.rrect_path(0.03 if big else 0.018, 0.085 if big else 0.05, 0.006, 0, 0.35 if big else 0.365),
                               -math.radians(30 * k))
        parts.append(kit.curve_mesh(f"Tick{k}", [tick], 0.001, 0.002, kit.EMBOSS, [mats.ink], res=8, bres=2))
    hour = kit.rotate_path(kit.rrect_path(0.046, 0.25, 0.018, 0, 0.095), -math.radians(210))
    minute = kit.rrect_path(0.032, 0.36, 0.013, 0, 0.15)
    parts.append(kit.curve_mesh("HourHand", [hour], 0.002, 0.003, kit.EMBOSS, [mats.ink], res=8, bres=3))
    parts.append(kit.curve_mesh("MinuteHand", [minute], 0.002, 0.003, kit.EMBOSS + 0.008, [mats.ink], res=8, bres=3))
    parts += kit.rivet("Axis", 0.0, 0.0, kit.Z_FRONT + 0.016, mats.rivet, r=0.03)
    return parts
