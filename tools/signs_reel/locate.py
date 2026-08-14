#!/usr/bin/env python3
"""Поиск знака на кадре по эталону из нашей же базы.

Спрашивать у модели «где тут знак» оказалось нельзя: на одном и том же кадре
она то показывает на знак, то на дорогу рядом, и согласия между попытками
нет. Поэтому ищем детерминированно — сопоставлением с эталонной картинкой
знака из `assets/countries/{code}/images/signs/`, той самой, что показывает
приложение.

Метод — нормированная взаимная корреляция по яркости (ZNCC) на нескольких
масштабах. Нормировка нужна, чтобы яркое небо не перебивало совпадение по
форме: сравнивается рисунок, а не освещённость.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

from . import raster

REPO = Path(__file__).resolve().parents[2]

# Знак в кадре занимает единицы процентов ширины. Совсем мелкие шаблоны
# исключены: они уверенно «находятся» в любой текстуре.
SCALES = [round(0.035 + 0.008 * i, 3) for i in range(12)]
MIN_SCORE = 0.45          # ниже — совпадение недостоверно
MAX_COLOR_DIST = 46       # средний цвет области должен совпасть с эталоном
EDGE_MARGIN = 0.02        # у самого края кадра знак не ищем


def sign_image(number: str, country: str = "ru") -> Path | None:
    """Файл эталонной картинки знака по его номеру."""
    root = REPO / "assets" / "countries" / country
    raw = json.loads((root / "questions" / "signs.json").read_text(encoding="utf-8"))
    for items in raw.values():
        for key, item in items.items():
            if str(item.get("number", key)).strip() == number:
                path = root / str(item.get("image", "")).lstrip("./")
                return path if path.exists() else None
    return None


def _gray(img: Image.Image) -> np.ndarray:
    return np.asarray(img.convert("L"), dtype=np.float64)


def _integral(a: np.ndarray) -> np.ndarray:
    out = np.zeros((a.shape[0] + 1, a.shape[1] + 1), dtype=np.float64)
    out[1:, 1:] = a.cumsum(axis=0).cumsum(axis=1)
    return out


def _window_sums(integral: np.ndarray, h: int, w: int) -> np.ndarray:
    return (integral[h:, w:] - integral[:-h, w:] - integral[h:, :-w] + integral[:-h, :-w])


def _zncc(image: np.ndarray, template: np.ndarray) -> np.ndarray:
    """Карта нормированной корреляции шаблона по всему кадру."""
    th, tw = template.shape
    ih, iw = image.shape
    if th >= ih or tw >= iw:
        return np.full((1, 1), -1.0)

    t = template - template.mean()
    t_norm = np.sqrt((t ** 2).sum())
    if t_norm < 1e-6:
        return np.full((1, 1), -1.0)

    shape = (ih, iw)
    fft_image = np.fft.rfft2(image, shape)
    fft_t = np.fft.rfft2(t[::-1, ::-1], shape)
    corr = np.fft.irfft2(fft_image * fft_t, shape)[th - 1:, tw - 1:]

    s1 = _window_sums(_integral(image), th, tw)
    s2 = _window_sums(_integral(image ** 2), th, tw)
    count = th * tw
    var = np.maximum(s2 - s1 ** 2 / count, 1e-6)
    return corr / (np.sqrt(var) * t_norm)


def verify_near(photo: Path, number: str, box: tuple, country: str = "ru") -> float:
    """Насколько предложенное место похоже на эталон знака.

    Поиск по всему кадру даёт ложные пики: мелкий шаблон уверенно
    «находится» в любой листве. Поэтому модель предлагает место, а эталон
    проверяет только его окрестность — там ложным пикам взяться неоткуда.
    """
    template_path = sign_image(number, country)
    if template_path is None:
        return 0.0

    image = Image.open(photo).convert("RGB")
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    half_w = max((x1 - x0), 0.05) * 1.6
    half_h = max((y1 - y0), 0.05) * 1.6
    left = int(max(0, cx - half_w) * image.width)
    top = int(max(0, cy - half_h) * image.height)
    right = int(min(1, cx + half_w) * image.width)
    bottom = int(min(1, cy + half_h) * image.height)
    crop = image.crop((left, top, right, bottom))
    if crop.width < 24 or crop.height < 24:
        return 0.0

    sign = raster.rasterize(template_path, 256)
    flat = Image.new("RGB", sign.size, (255, 255, 255))
    flat.paste(sign, (0, 0), sign)

    gray = _gray(crop)
    best = 0.0
    base = max(12, int((x1 - x0) * image.width))
    for factor in (0.7, 0.85, 1.0, 1.2, 1.45):
        tw = max(10, round(base * factor))
        th = max(10, round(tw * flat.height / flat.width))
        if th >= gray.shape[0] - 2 or tw >= gray.shape[1] - 2:
            continue
        tmpl = _gray(flat.resize((tw, th), Image.LANCZOS))
        score_map = _zncc(gray, tmpl)
        if score_map.size:
            best = max(best, float(score_map.max()))
    return best


def find(photo: Path, number: str, country: str = "ru"):
    """Рамка знака в нормализованных координатах или None.

    Возвращает None честно: не найден — значит, подсветки не будет. Лучше
    ролик без подсветки, чем окно поверх случайного куста.
    """
    template_path = sign_image(number, country)
    if template_path is None:
        return None

    image = Image.open(photo).convert("RGB")
    # Считаем на уменьшенной копии: точность в пиксель тут не нужна, а
    # корреляция по полному кадру на каждом масштабе считалась бы минуту.
    work_w = 640
    scale = work_w / image.width
    work = image.resize((work_w, round(image.height * scale)), Image.LANCZOS)
    gray = _gray(work)

    sign = raster.rasterize(template_path, 256)
    flat = Image.new("RGB", sign.size, (255, 255, 255))
    flat.paste(sign, (0, 0), sign)

    # Корреляция считается по каждому каналу: знаки держатся на цвете, и по
    # одной яркости синий круг неотличим от тени под деревом.
    channels = [np.asarray(work, dtype=np.float64)[:, :, c] for c in range(3)]
    work_rgb = np.asarray(work, dtype=np.float64)

    best = (-1.0, None)
    for fraction in SCALES:
        tw = max(12, round(work_w * fraction))
        th = max(12, round(tw * flat.height / flat.width))
        if th >= gray.shape[0] - 4:
            continue
        piece = flat.resize((tw, th), Image.LANCZOS)
        t_rgb = np.asarray(piece, dtype=np.float64)
        maps = [_zncc(channels[c], t_rgb[:, :, c]) for c in range(3)]
        if min(m.size for m in maps) == 0:
            continue
        score_map = sum(maps) / 3.0

        # Цветовой фильтр: средний цвет окна должен быть близок к эталону,
        # иначе форма совпадает, а объект посторонний.
        s1 = [_window_sums(_integral(channels[c]), th, tw) / (th * tw) for c in range(3)]
        target = t_rgb.reshape(-1, 3).mean(axis=0)
        dist = sum((s1[c] - target[c]) ** 2 for c in range(3)) ** 0.5
        score_map = np.where(dist <= MAX_COLOR_DIST, score_map, -1.0)

        y, x = np.unravel_index(np.argmax(score_map), score_map.shape)
        score = float(score_map[y, x])
        if score > best[0]:
            best = (score, (x / gray.shape[1], y / gray.shape[0],
                            (x + tw) / gray.shape[1], (y + th) / gray.shape[0]))

    score, box = best
    if box is None or score < MIN_SCORE:
        return None
    if box[0] < EDGE_MARGIN and box[1] < EDGE_MARGIN:
        return None
    return box, score
