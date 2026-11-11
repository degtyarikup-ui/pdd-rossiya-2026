"""Печать лицевой стороны водительского удостоверения для ачивки «Экзаменатор».

python3 license_print.py [out.png]   (по умолчанию ~/Library/Caches/pdd-achievements/license_print.png)

Иллюстрация, а не документ: данные условные (полосы вместо текста), без
гербов и номеров. Пропорции карты 85.6×54 мм.
"""

import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[4]  # apps/russia
W, H = 2400, 1514
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Caches/pdd-achievements/license_print.png")


def font(size, weight="Bold"):
    return ImageFont.truetype(str(ROOT / f"assets/fonts/Onest-{weight}.ttf"), size)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    img = Image.new("RGB", (W, H))
    px = img.load()
    left, mid, right = (238, 190, 208), (226, 208, 232), (186, 212, 240)
    for x in range(W):
        t = x / (W - 1)
        c = lerp(left, mid, t / 0.55) if t < 0.55 else lerp(mid, right, (t - 0.55) / 0.45)
        for y in range(H):
            px[x, y] = c

    # Гильош: волнистые линии по всей карте и розетка справа.
    g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    for k in range(70):
        y0 = k * H / 70
        pts = [(x, y0 + 14 * math.sin(x / 90 + k * 0.5) + 6 * math.sin(x / 23)) for x in range(0, W + 20, 12)]
        d.line(pts, fill=(255, 255, 255, 70), width=2)
    cx, cy = int(W * 0.78), int(H * 0.52)
    for k in range(90):
        pts = []
        for i in range(0, 721):
            a = i * math.pi / 360
            r = 250 + 42 * math.sin(14 * a + k * 0.05) + 16 * math.sin(6 * a - k * 0.09)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        d.line(pts, fill=(196, 120, 160, 46) if k % 2 else (110, 150, 210, 46), width=1)
    img.paste(g, (0, 0), g)

    d = ImageDraw.Draw(img)
    # Шапка.
    d.rounded_rectangle([90, 70, 330, 190], radius=60, fill=(36, 88, 170))
    d.text((210, 130), "RUS", font=font(78), fill=(255, 255, 255), anchor="mm")
    d.text((380, 72), "ВОДИТЕЛЬСКОЕ УДОСТОВЕРЕНИЕ", font=font(92), fill=(156, 22, 42))
    d.text((384, 182), "DRIVING LICENCE  ·  PERMIS DE CONDUIRE", font=font(42, "Medium"), fill=(92, 84, 104))

    # Фото: мягкий фон и силуэт.
    photo = Image.new("RGB", (560, 720), (214, 220, 232))
    pd = ImageDraw.Draw(photo)
    for y in range(720):
        pd.line([(0, y), (560, y)], fill=lerp((226, 231, 240), (196, 204, 220), y / 719))
    sil = Image.new("L", (560, 720), 0)
    sd = ImageDraw.Draw(sil)
    sd.ellipse([175, 150, 385, 400], fill=255)
    sd.rounded_rectangle([70, 430, 490, 820], radius=200, fill=255)
    sil = sil.filter(ImageFilter.GaussianBlur(3))
    photo.paste(Image.new("RGB", (560, 720), (122, 132, 152)), (0, 0), sil)
    mask = Image.new("L", (560, 720), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 559, 719], radius=26, fill=255)
    img.paste(photo, (100, 290), mask)

    # Поля с номерами: номер + условная строка.
    fields = [("1.", 560), ("2.", 720), ("3.", 640), ("4a)", 360), ("4b)", 360), ("4c)", 520), ("5.", 600), ("8.", 760)]
    y = 300
    for i, (n, wl) in enumerate(fields):
        x = 760 if n not in ("4b)",) else 1300
        if n == "4b)":
            y -= 96
        d.text((x, y), n, font=font(46), fill=(48, 44, 60))
        d.rounded_rectangle([x + 110, y + 14, x + 110 + wl, y + 38], radius=8, fill=(58, 60, 78))
        y += 96

    # Подпись под фото.
    sig = [(150 + t * 4.2, 1100 + 26 * math.sin(t / 9) - t * 0.25 + 14 * math.sin(t / 3)) for t in range(0, 110)]
    d.text((100, 1060), "7.", font=font(46), fill=(48, 44, 60))
    d.line(sig, fill=(30, 50, 120), width=7, joint="curve")

    # Категории.
    d.text((760, 1180), "9.", font=font(46), fill=(48, 44, 60))
    for i, cat in enumerate(("A", "B", "C", "M")):
        x0 = 870 + i * 150
        on = cat in ("B", "M")
        d.rounded_rectangle([x0, 1160, x0 + 124, 1270], radius=22, fill=(36, 88, 170) if on else (255, 255, 255),
                            outline=(36, 88, 170), width=6)
        d.text((x0 + 62, 1215), cat, font=font(70), fill=(255, 255, 255) if on else (36, 88, 170), anchor="mm")

    # Место под голограмму (сама голограмма — 3D, металл уровня).
    hx, hy = int(W * 0.87), int(H * 0.785)
    d.ellipse([hx - 230, hy - 230, hx + 230, hy + 230], outline=(255, 255, 255), width=5)

    Path(OUT).parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("ok", OUT)


main()
