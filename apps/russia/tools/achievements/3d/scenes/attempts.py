"""«Неутомимый» (attempts): километровый знак 6.13 — «намотал» столько
ответов, сколько километров. Число — само содержание знака, без таблички."""

LEVELS = {1: "100", 2: "500", 3: "1000", 4: "3000"}

W, H, R = 1.0, 0.56, 0.05


def build(kit, level):
    number = LEVELS[level]
    mats = kit.Materials(level)
    cy = 0.0
    parts = [kit.sign_body("SignBody", kit.rrect_path(W - 2 * kit.T_B, H - 2 * kit.T_B, R - kit.T_B, 0, cy), mats, res=16)]
    inset, bw, fb = 0.03, 0.016, 0.0024
    o_w, o_h = W - 2 * inset, H - 2 * inset
    parts.append(kit.curve_mesh("SignFrame", [kit.rrect_path(o_w - 2 * fb, o_h - 2 * fb, R - inset - fb, 0, cy),
                                              kit.rrect_path(o_w - 2 * bw + 2 * fb, o_h - 2 * bw + 2 * fb, max(0.004, R - inset - bw + fb), 0, cy)],
                                0.001, fb, kit.EMBOSS, [mats.ink], res=16, bres=3))
    num, _ = kit.text_mesh("SignNumber", number, kit.FONT_DIGITS, 0.32, 0.0026, 0.0034, kit.EMBOSS, [mats.ink],
                           cy=cy - 0.005, spacing=1.06)
    parts.append(num)
    for i, xx in enumerate((-1, 1)):
        parts += kit.rivet(f"SignRivet{i}", xx * (W / 2 - 0.055), cy, kit.Z_FRONT + 0.0004, mats.rivet)
    parts += kit.pole(mats, mounts_y=(cy + 0.12, cy - 0.12), top=cy + 0.2)
    return parts
