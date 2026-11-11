"""«Работа над ошибками» (mistakes): треугольник «Прочие опасности» (1.33),
классический «!», число исправленных — на табличке под знаком."""

import math


FRAME = 1.2   # высокий объект: отодвинуть камеру, чтобы стойка успела раствориться
LEVELS = {1: "10", 2: "50", 3: "100", 4: "200"}

SIDE = 1.22
RI = SIDE / (2 * math.sqrt(3))   # радиус вписанной окружности
CY = -0.42 + RI                  # центр: низ треугольника на y = -0.42
EDGE, BAND = 0.025, 0.105        # белая кромка и красная полоса


def tri(kit, inradius, corner):
    return kit.rounded_polygon_path(kit.regular_points(3, 2 * inradius, 0.0, CY), corner)


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)

    parts = [kit.sign_body("SignBody", tri(kit, RI - kit.T_B, 0.08), mats)]
    e, b = 0.0022, 0.0038
    parts.append(kit.curve_mesh("SignBand", [tri(kit, RI - EDGE - b, 0.065), tri(kit, RI - EDGE - BAND + b, 0.03)],
                                e, b, kit.EMBOSS, [mats.film("red")], res=32, bres=4))
    parts += kit.exclamation(mats, 0.0, CY - 0.02, 0.30)
    band_mid = EDGE + BAND / 2
    parts += kit.rivet("SignRivet0", 0.0, CY + 2 * RI - 2 * band_mid - 0.03, kit.Z_FRONT + 0.0108, mats.rivet)
    parts += kit.rivet("SignRivet1", 0.0, CY - RI + band_mid, kit.Z_FRONT + 0.0108, mats.rivet)

    plate_y = CY - RI - 0.04 - 0.315 / 2
    parts += kit.plate_number(mats, plate_y, number)
    parts += kit.pole(mats, mounts_y=(0.18, -0.25, plate_y), plate_rails=(plate_y,))
    return parts
