#!/usr/bin/env python3
"""Вертикальная адаптация иллюстрации вопроса через image-to-image.

    python3 -m tools.signs_reel.qimage --id <id вопроса>

Исходник — узкая лента 1208×450, в вертикальном ролике она смотрится
полоской. Модель достраивает кадр вверх и вниз (небо, дорога, капот) и
подтягивает качество съёмки, а всё, от чего зависит правильный ответ,
обязана оставить нетронутым.

ЭТО РИСКОВАННЫЙ ШАГ, и он проверяется руками. На пробе четырёх кадров модель
успевала стереть габаритную стрелку «4 м», дорисовать белую стрелку разметки
и лишний светофор, перерисовать пиктограмму знака. Поэтому:

* берём только `gemini-3-pro-image` — на быстрой модели галлюцинации того же
  класса, который меняет ответ;
* результат кладётся рядом с оригиналом в контактный лист, и кадр не идёт
  в ролик, пока человек не посмотрел на этот лист.
"""

from __future__ import annotations

import argparse
import hashlib
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

from PIL import Image, ImageDraw

from .audio import default_project
from . import locate as locate_mod
from . import frames

CACHE = Path(__file__).resolve().parent / ".cache" / "qimages"
MODEL = "gemini-3-pro-image"
REQUEST_TIMEOUT_MS = 180_000   # 3 минуты на запрос; без таймаута пакет виснет
ASPECT = "4:3"   # квадрат заставлял модель дорисовывать слишком много

PROMPT = """Это учебная иллюстрация к экзаменационному вопросу по правилам дорожного движения.

Задача: адаптировать кадр под формат 4:3, дорисовав недостающее сверху и снизу, и повысить техническое качество съёмки.

ЧТО НУЖНО СДЕЛАТЬ:
- Исходный кадр целиком, во всю ширину, остаётся в середине. По бокам НИЧЕГО не обрезать: левый и правый края исходника обязаны остаться в кадре.
- Дорисовать сверху естественное продолжение сцены (небо, верхушки деревьев, верхние этажи зданий) и снизу (продолжение капота, приборной панели или дорожного полотна) так, чтобы кадр стал 4:3.
- Ничего не растягивать и не сжимать. Круглое обязано остаться круглым: рулевое колесо, колёса, круглые дорожные знаки, циферблаты приборов — идеальные окружности, а не овалы. Новые пропорции получаются ТОЛЬКО за счёт дорисованного сверху и снизу, ширина сцены не меняется ни на процент.
- Повысить резкость и детализацию, сделать свет естественным и современным, убрать артефакты сжатия.

ЧТО КАТЕГОРИЧЕСКИ НЕЛЬЗЯ МЕНЯТЬ (от этого зависит правильный ответ):
- Количество, тип, цвет и положение всех транспортных средств и людей. Ничего не добавлять и не убирать.
- Какая секция светофора горит и каким цветом.
- Включённые указатели поворота и любые горящие фонари.
- Пиктограмму, цвет, форму, количество и место установки каждого дорожного знака. Пиктограмму знака воспроизвести в точности, это ГОСТовский символ.
- Тип линий разметки (сплошная, прерывистая, двойная), их количество и положение.
- Служебную графику, нанесённую поверх фотографии: белые двусторонние стрелки с засечками и подписи размеров, серые изогнутые стрелки траектории, жёлтые звёздочки, красные и синие стрелки, буквы и цифры. Сохранить их форму, толщину, цвет и положение пиксель в пиксель.
- Геометрию дороги, ракурс камеры и композицию центральной части кадра.

НИЧЕГО НЕ ДОБАВЛЯТЬ. Если в исходнике нет стрелок, букв, цифр, звёздочек, подписей или линий траектории — не рисуй их. Не помечай автомобили буквами A и B. Не рисуй стрелки направления движения. Не добавляй разметку, знаки, светофоры, машины и людей, которых нет в исходнике. Сверху и снизу дорисовывается только естественное продолжение сцены — небо, здания, дорожное полотно, салон автомобиля — и ничего больше.

Дорисованное обязано быть геометрически цельным. Если снизу продолжается салон автомобиля — у него замкнутая крыша, обе стойки лобового стекла сходятся вверху, зеркало и торпедо на месте. Стойка не может уходить вверх и обрываться, левая или правая часть салона не может отсутствовать: разваленная кабина сразу выдаёт подделку.

Исходная часть кадра должна остаться узнаваемо той же: новое рисуется только сверху и снизу."""


def path_for(question_id: str) -> Path:
    digest = hashlib.sha1(f"{question_id}|{MODEL}|{ASPECT}".encode()).hexdigest()[:12]
    return CACHE / f"{question_id[:8]}_{digest}.png"


def generate(source: Path, question_id: str, force: bool = False, attempts: int = 4) -> Path:
    out = path_for(question_id)
    if out.exists() and not force:
        return out

    import time

    from google import genai
    from google.genai import types

    CACHE.mkdir(parents=True, exist_ok=True)
    # Таймаут обязателен: без него зависший запрос блокирует пакет навсегда —
    # на пробе один кадр висел 13 минут, и цикл повтора не срабатывал,
    # потому что процесс не завершался ни успехом, ни ошибкой.
    client = genai.Client(vertexai=True, project=default_project(), location="global",
                          http_options=types.HttpOptions(timeout=REQUEST_TIMEOUT_MS))
    parts = [
        types.Part(text=PROMPT),
        types.Part(inline_data=types.Blob(mime_type="image/jpeg", data=source.read_bytes())),
    ]

    last = None
    for attempt in range(attempts):
        try:
            response = client.models.generate_content(
                model=MODEL,
                contents=[types.Content(role="user", parts=parts)],
                config=types.GenerateContentConfig(
                    response_modalities=["TEXT", "IMAGE"],
                    image_config=types.ImageConfig(aspect_ratio=ASPECT),
                ),
            )
            for part in response.candidates[0].content.parts:
                if part.inline_data and part.inline_data.data:
                    out.write_bytes(part.inline_data.data)
                    return out
            last = "модель вернула ответ без картинки"
        except Exception as exc:
            last = exc
            if not any(c in str(exc) for c in ("429", "RESOURCE_EXHAUSTED", "500", "INTERNAL", "503")):
                break
        time.sleep(2 ** attempt)
    raise SystemExit(f"кадр не сгенерился: {str(last)[:160]}")


# gemini-3.1-flash в этом проекте отдаёт 404 — берём доступную модель.
LOCATE_MODEL = "gemini-2.5-flash"
LOCATE_MIN_STD = 26          # ниже — область почти однотонная, это не знак
LOCATE_TRIES = 3             # столько раз переспрашиваем локатор
LOCATE_MIN_IOU = 0.30        # рамки считаются согласными при таком перекрытии
VERIFY_MIN_SCORE = 0.35      # ниже — эталон знака в этом месте не опознан

LOCATE_PROMPT = (
    "На изображении найди объект: {what}. Верни ТОЛЬКО JSON-массив вида "
    '[{{"box_2d": [ymin, xmin, ymax, xmax]}}] с координатами в диапазоне 0-1000 '
    "относительно размеров изображения, без пояснений. Если объекта нет, верни []."
)


def locate(image: Path, what: str, attempts: int = 3):
    """Рамка вокруг названного объекта в нормализованных координатах 0..1.

    Нужна, чтобы обвести на кадре именно тот знак, о котором говорит разбор.
    Возвращает None, если модель объект не нашла — тогда обводки просто не
    будет: лучше без неё, чем красный круг вокруг случайного куста.
    """
    import json
    import re
    import time

    from google import genai
    from google.genai import types

    client = genai.Client(vertexai=True, project=default_project(), location="global")
    parts = [
        types.Part(text=LOCATE_PROMPT.format(what=what)),
        types.Part(inline_data=types.Blob(mime_type="image/png" if image.suffix == ".png"
                                          else "image/jpeg", data=image.read_bytes())),
    ]
    for attempt in range(attempts):
        try:
            resp = client.models.generate_content(
                model=LOCATE_MODEL,
                contents=[types.Content(role="user", parts=parts)],
            )
            match = re.search(r"\[.*\]", (resp.text or ""), re.S)
            if not match:
                return None
            boxes = json.loads(match.group(0))
            if not boxes:
                return None
            y0, x0, y1, x1 = boxes[0]["box_2d"]
            return (x0 / 1000, y0 / 1000, x1 / 1000, y1 / 1000)
        except Exception as exc:
            if not any(c in str(exc) for c in ("429", "RESOURCE_EXHAUSTED", "500", "INTERNAL", "503")):
                return None
            time.sleep(2 ** attempt)
    return None


SEAM = 14                    # мягкая склейка на стыке с дорисованным


def _iou(a: tuple, b: tuple) -> float:
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    if ix1 <= ix0 or iy1 <= iy0:
        return 0.0
    inter = (ix1 - ix0) * (iy1 - iy0)
    area = (ax1 - ax0) * (ay1 - ay0) + (bx1 - bx0) * (by1 - by0) - inter
    return inter / area if area > 0 else 0.0


def locate_sign(image: Path, what: str, number: str = ""):
    """Ищет знак на кадре и отвечает только за уверенное попадание.

    Локатор недетерминирован: на одном и том же кадре он то показывает на
    знак, то на дорогу рядом. Поэтому спрашиваем трижды и берём ответ,
    который повторился: две рамки, накрывающие друг друга, — это находка,
    три разных — это угадывание, и тогда подсветки не будет.

    Отдельно отбрасываем почти однотонные области: небо и асфальт знаком
    быть не могут.
    """
    import numpy as np

    img = Image.open(image).convert("RGB")

    def solid(box):
        x0, y0, x1, y1 = box
        crop = img.crop((int(x0 * img.width), int(y0 * img.height),
                         max(int(x1 * img.width), int(x0 * img.width) + 2),
                         max(int(y1 * img.height), int(y0 * img.height) + 2)))
        return np.asarray(crop, dtype=np.float32).std() < LOCATE_MIN_STD

    boxes = []
    for _ in range(LOCATE_TRIES):
        box = locate(image, what)
        if box and not solid(box) and box not in boxes:
            boxes.append(box)
    if not boxes:
        return None

    # Из предложенных мест выбираем то, где эталон знака действительно
    # опознаётся. Само по себе предложение модели ничего не гарантирует:
    # на одном кадре она показывает то на знак, то на дорогу рядом.
    if number:
        scored = [(locate_mod.verify_near(image, number, b), b) for b in boxes]
        scored.sort(reverse=True, key=lambda x: x[0])
        if scored and scored[0][0] >= VERIFY_MIN_SCORE:
            return scored[0][1]
        return None

    for i, a in enumerate(boxes):
        agree = [b for b in boxes[i + 1:] if _iou(a, b) >= LOCATE_MIN_IOU]
        if agree:
            group = [a] + agree
            return tuple(sum(v[k] for v in group) / len(group) for k in range(4))
    return None


def compose_square(source: Path, generated: Path) -> int:
    """Возвращает в квадратный кадр подлинные пиксели исходника.

    Достраивая квадрат, модель заодно перерисовывает и середину: сцена
    подсжимается по горизонтали (руль становится овальным), детали слегка
    уезжают. Поэтому берём у генерации только дорисованное сверху и снизу,
    а полосу исходника вставляем как есть — в её собственных пропорциях.

    Куда вставлять, ищем сопоставлением: полоса ставится на ту высоту, где
    она меньше всего расходится с генерацией. Возвращает найденный отступ
    сверху в пикселях.
    """
    import numpy as np

    gen = Image.open(generated).convert("RGB")
    orig = Image.open(source).convert("RGB")
    band = orig.resize((gen.width, round(gen.width * orig.height / orig.width)),
                       Image.LANCZOS)
    if band.height >= gen.height:
        return 0

    # Поиск по уменьшенным копиям: точность в пиксель тут не нужна, а полный
    # перебор по оригиналу считался бы секундами.
    scale = 160 / gen.width
    g_small = np.asarray(gen.resize((160, max(1, round(gen.height * scale)))), dtype=np.float32)
    b_small = np.asarray(band.resize((160, max(1, round(band.height * scale)))), dtype=np.float32)

    best, best_offset = None, 0
    for y in range(0, g_small.shape[0] - b_small.shape[0] + 1):
        diff = np.abs(g_small[y:y + b_small.shape[0]] - b_small).mean()
        if best is None or diff < best:
            best, best_offset = diff, y
    offset = round(best_offset / scale)
    offset = min(offset, gen.height - band.height)

    # Мягкий стык: резкая граница между подлинной полосой и дорисованным
    # читается как склейка.
    mask = Image.new("L", band.size, 255)
    md = ImageDraw.Draw(mask)
    for i in range(SEAM):
        value = int(255 * (i + 1) / SEAM)
        md.line([(0, i), (band.width, i)], fill=value)
        md.line([(0, band.height - 1 - i), (band.width, band.height - 1 - i)], fill=value)

    gen.paste(band, (0, offset), mask)
    gen.save(generated)
    return offset


def contact_sheet(source: Path, generated: Path, out: Path) -> Path:
    """Оригинал и результат рядом — лист, по которому кадр принимается глазами."""
    a = Image.open(source).convert("RGB")
    b = Image.open(generated).convert("RGB")
    width = 1100
    a = a.resize((width, round(a.height * width / a.width)), Image.LANCZOS)
    b = b.resize((width, round(b.height * width / b.width)), Image.LANCZOS)
    label = 46
    sheet = Image.new("RGB", (width, a.height + b.height + 2 * label), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    f = frames.font("bold", 28)
    d.text((16, 10), "ОРИГИНАЛ", font=f, fill=(255, 214, 90))
    sheet.paste(a, (0, label))
    d.text((16, label + a.height + 10), f"ПОСЛЕ ГЕНЕРАЦИИ ({MODEL}, {ASPECT})",
           font=f, fill=(255, 214, 90))
    sheet.paste(b, (0, 2 * label + a.height))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, quality=92)
    return out


def main() -> None:
    from .question import load_questions

    p = argparse.ArgumentParser(description="Вертикальная адаптация картинки вопроса")
    p.add_argument("--id", required=True)
    p.add_argument("--country", default="ru")
    p.add_argument("--force", action="store_true")
    p.add_argument("--sheet", help="куда положить контактный лист")
    args = p.parse_args()

    q = next((x for x in load_questions(args.country) if x.id == args.id), None)
    if q is None:
        raise SystemExit(f"нет вопроса с id {args.id}")

    print(f"Билет {q.ticket}: {q.text}")
    generated = generate(q.image, q.id, force=args.force)
    offset = compose_square(q.image, generated)
    print("картинка:", generated, Image.open(generated).size,
          f"(исходная полоса вставлена на {offset} px сверху)")
    sheet = contact_sheet(q.image, generated,
                          Path(args.sheet) if args.sheet else generated.with_name(
                              generated.stem + "_sheet.jpg"))
    print("лист для проверки:", sheet)


if __name__ == "__main__":
    main()
