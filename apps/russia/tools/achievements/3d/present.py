"""Лист приёмки: четыре уровня ачивки крупно и в сетке 68 pt (светлая/тёмная
тема, неполученный — серый, как в приложении).

python3 present.py <id> <dir_with_post_outputs> [<title>]
Ожидает <dir>/<id>_<1..4>_1024.png, пишет <dir>/<id>_sheet.png.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]  # apps/russia
FONT = ROOT / "assets/fonts/Onest-Bold.ttf"
FONT_M = ROOT / "assets/fonts/Onest-Medium.ttf"
METALS = ["бронза", "серебро", "золото", "платина"]
# Матрица неполученного значка из achievement_badge.dart (75% серого).
GRAY = (0.4095, 0.5364, 0.0542, 0, 0.1595, 0.7864, 0.0542, 0, 0.1595, 0.5364, 0.3042, 0)


def font(size, medium=False):
    return ImageFont.truetype(str(FONT_M if medium else FONT), size)


def main():
    aid, folder = sys.argv[1], Path(sys.argv[2])
    title = sys.argv[3] if len(sys.argv) > 3 else aid
    badges = [Image.open(folder / f"{aid}_{i}_1024.png").convert("RGBA") for i in range(1, 5)]
    W, H = 2200, 1180
    s = Image.new("RGBA", (W, H), (236, 234, 231, 255))
    d = ImageDraw.Draw(s)
    d.text((80, 60), title, font=font(60), fill=(28, 28, 30))
    for i, b in enumerate(badges):
        x = 80 + i * 520
        d.rounded_rectangle([x, 170, x + 480, 650], 36, fill=(217, 214, 211))
        s.alpha_composite(b.resize((460, 460), Image.LANCZOS), (x + 10, 180))
        d.text((x + 240, 672), f"Уровень {i + 1} · {METALS[i]}", font=font(30, True), fill=(80, 78, 74), anchor="mt")
    for t, (bg, cell, op) in enumerate((((255, 255, 255), (243, 243, 245), .38), ((28, 28, 30), (44, 44, 48), .30))):
        x0 = 80 + t * 1040
        d.rounded_rectangle([x0, 760, x0 + 1000, 1100], 32, fill=bg)
        for i, b in enumerate(badges):
            cx = x0 + 40 + i * 240
            d.rounded_rectangle([cx, 800, cx + 200, 1060], 24, fill=cell)
            small = b.resize((136, 136), Image.LANCZOS)
            if i == 3:
                a = small.getchannel("A")
                small = small.convert("RGB").convert("RGB", GRAY).convert("RGBA")
                small.putalpha(a.point(lambda v: int(v * op)))
            s.alpha_composite(small, (cx + 32, 830))
    out = folder / f"{aid}_sheet.png"
    s.convert("RGB").save(out, quality=94)
    print("ok", out)


main()
