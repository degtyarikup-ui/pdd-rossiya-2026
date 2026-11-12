"""Обложка книжки ПДД для ачивки «Знаток знаков ПДД».

python3 rulebook_print.py → ~/Library/Caches/pdd-achievements/rulebook_print.png и rulebook_mask.png
Как у настоящих изданий: цветная плашка с крупным «ПДД», полное название
и ряд дорожных знаков. Плашку (по маске) в 3D красит цвет уровня.
"""

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
W, H, BAND = 1480, 2000, 900
OUT = Path(os.path.expanduser("~/Library/Caches/pdd-achievements"))
RED, BLUE, YELLOW, INK, WHITE = (206, 24, 30), (16, 92, 180), (250, 190, 20), (34, 36, 44), (255, 255, 255)


def font(size, weight="Bold"):
    return ImageFont.truetype(str(ROOT / f"assets/fonts/Onest-{weight}.ttf"), size)


def signs(d, y):
    r = 150
    xs = [W * k / 8 for k in (1, 3, 5, 7)]
    # Ограничение скорости.
    x = xs[0]
    d.ellipse([x - r, y - r, x + r, y + r], fill=RED)
    d.ellipse([x - r + 34, y - r + 34, x + r - 34, y + r - 34], fill=WHITE)
    d.text((x, y + 4), "60", font=font(150), fill=INK, anchor="mm")
    # Прочие опасности.
    x = xs[1]
    d.polygon([(x, y - r - 10), (x + r + 22, y + r), (x - r - 22, y + r)], fill=RED)
    d.polygon([(x, y - r + 62), (x + r - 42, y + r - 34), (x - r + 42, y + r - 34)], fill=WHITE)
    d.rounded_rectangle([x - 15, y - 40, x + 15, y + 55], radius=14, fill=INK)
    d.ellipse([x - 18, y + 72, x + 18, y + 108], fill=INK)
    # Движение прямо.
    x = xs[2]
    d.ellipse([x - r, y - r, x + r, y + r], fill=BLUE)
    d.rectangle([x - 24, y - 30, x + 24, y + 100], fill=WHITE)
    d.polygon([(x, y - 110), (x + 78, y - 10), (x - 78, y - 10)], fill=WHITE)
    # Главная дорога.
    x = xs[3]
    d.polygon([(x, y - r - 12), (x + r + 12, y), (x, y + r + 12), (x - r - 12, y)], fill=WHITE, outline=INK, width=6)
    d.polygon([(x, y - r + 42), (x + r - 42, y), (x, y + r - 42), (x - r + 42, y)], fill=YELLOW)


def main():
    img = Image.new("RGB", (W, H), (250, 249, 244))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, BAND], fill=(110, 110, 110))
    d.text((W / 2, 400), "ПДД", font=font(520), fill=WHITE, anchor="mm")
    d.text((W / 2, 740), "официальный текст", font=font(84, "Medium"), fill=WHITE, anchor="mm")
    d.text((W / 2, 1060), "ПРАВИЛА", font=font(150), fill=INK, anchor="mm")
    d.text((W / 2, 1220), "ДОРОЖНОГО ДВИЖЕНИЯ", font=font(104), fill=INK, anchor="mm")
    d.text((W / 2, 1350), "Российской Федерации", font=font(76, "Medium"), fill=(96, 98, 110), anchor="mm")
    signs(d, 1690)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "rulebook_print.png")
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rectangle([0, 0, W, BAND], fill=255)
    m.save(OUT / "rulebook_mask.png")
    print("ok", OUT)


main()
