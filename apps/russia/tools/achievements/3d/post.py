"""Постобработка рендера 3D-ачивки.

python3 post.py <raw.png> <out_prefix>
  → <out_prefix>_1024.png, <out_prefix>_512.png — прозрачные, объект ~90% кадра,
    стойка мягко растворяется книзу;
  → <out_prefix>_guide.png — контроль композиции на сетке 68 pt: крестик там,
    где приложение рисует центр лучей (_signCenter), и рамка 90%.

512 px — файл для apps/russia/assets/images/achievements/<id>_<level>.png.
"""

import sys

import numpy as np
from PIL import Image, ImageDraw

FILL = 0.90
# Центр фокуса (круг знака) в долях стороны. То же значение — _signCenter
# в achievement_tier_style.dart: по нему рисуются лучи и сияние.
FOCUS = (0.483, 0.31)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def process(src):
    a = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255.0
    alpha = a[..., 3]
    cover = (alpha > 0.5).sum(axis=1)
    rows = np.nonzero(cover)[0]
    top, bottom = rows[0], rows[-1]
    # Ширина стойки — по нижним строкам; всё, что втрое шире, — знак или табличка.
    pole_w = np.median(cover[bottom - 20:bottom - 2])
    if pole_w > 0.3 * cover.max():
        # Парящий предмет без стойки (машинка, права): только кадрирование.
        return frame(Image.fromarray((a * 255 + 0.5).astype(np.uint8)))
    wide = cover > pole_w * 3.0
    wide_bottom = np.nonzero(wide)[0][-1]
    obj_h = wide_bottom - top
    # Первый сплошной блок широких строк — главный элемент (знак, светофор).
    main_end = np.nonzero(wide)[0][0]
    while main_end + 1 < len(wide) and wide[main_end + 1]:
        main_end += 1
    if main_end >= wide_bottom - 2:
        # Без таблички: стойка видна дольше, чтобы центр главного элемента
        # оставался в FOCUS, как у знаков с табличкой.
        main_h = main_end - top
        f0, f1 = top + 1.38 * main_h, top + 1.73 * main_h
    else:
        f0, f1 = wide_bottom + 0.015 * obj_h, wide_bottom + 0.20 * obj_h
    # Если стойка уходит за край рендера, растворение заканчивается у края.
    f1 = min(f1, alpha.shape[0] - 3)
    f0 = min(f0, f1 - 0.12 * obj_h)
    y = np.arange(alpha.shape[0], dtype=np.float32)[:, None]
    a[..., 3] = alpha * (1.0 - smoothstep(f0, f1, y))
    return frame(Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)))


def frame(out):
    out = out.crop(out.getchannel("A").point(lambda v: 255 if v > 3 else 0).getbbox())
    w, h = out.size
    side = int(round(max(w, h) / FILL))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(out, ((side - w) // 2, (side - h) // 2))
    return canvas


def guide(img):
    size = 680
    g = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    g.alpha_composite(img.resize((size, size), Image.LANCZOS))
    d = ImageDraw.Draw(g)
    m = size * (1 - FILL) / 2
    d.rectangle([m, m, size - m, size - m], outline=(0, 160, 255, 255), width=2)
    fx, fy = FOCUS[0] * size, FOCUS[1] * size
    d.line([fx - 24, fy, fx + 24, fy], fill=(255, 0, 140, 255), width=3)
    d.line([fx, fy - 24, fx, fy + 24], fill=(255, 0, 140, 255), width=3)
    small = img.resize((136, 136), Image.LANCZOS)  # 68 pt @2x — так значок виден в сетке
    g.alpha_composite(small, (size - 150, size - 150))
    return g


def main():
    src, prefix = sys.argv[1], sys.argv[2]
    img = process(src)
    img.resize((1024, 1024), Image.LANCZOS).save(prefix + "_1024.png")
    img.resize((512, 512), Image.LANCZOS).save(prefix + "_512.png", optimize=True)
    guide(img).convert("RGB").save(prefix + "_guide.png")
    print("ok", prefix)


main()
