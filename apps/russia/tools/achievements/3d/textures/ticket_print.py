"""Печать экзаменационного билета для ачивки «Билет за билетом».

python3 ticket_print.py   → ~/Library/Caches/pdd-achievements/ticket_<N>.png (N = 1, 10, 20, 40),
                            ticket_blank.png и ticket_mask.png (маска шапки).

Просто и реалистично: шапка «БИЛЕТ № N», настоящее фото и текст вопроса
из билета 1 (контент приложения). Шапку в 3D красит металл уровня — здесь
она серая, текст на ней белый, а маска говорит, где шапка.
"""

import json
import os
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]  # apps/russia
CONTENT = ROOT / "assets/countries/ru"
W, H, HEADER = 2000, 1400, 300
OUT = Path(os.path.expanduser("~/Library/Caches/pdd-achievements"))
QUESTION_IMAGE = "eca08a0e2b5ffcd12bdd8ffee34afcc3"   # билет 1, вопрос 2


def font(size, weight="Bold"):
    return ImageFont.truetype(str(ROOT / f"assets/fonts/Onest-{weight}.ttf"), size)


def question_text():
    tickets = json.loads((CONTENT / "questions/questions_ab.json").read_text())["tickets"]
    for t in tickets:
        for q in t["questions"]:
            if q.get("image") == QUESTION_IMAGE:
                return q["question"]
    raise LookupError(QUESTION_IMAGE)


def ticket(number, question):
    img = Image.new("RGB", (W, H), (250, 249, 244))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, HEADER], fill=(128, 128, 128))
    d.text((90, HEADER // 2), "БИЛЕТ", font=font(120), fill=(255, 255, 255), anchor="lm")
    if number is not None:
        d.text((W - 90, HEADER // 2), f"№ {number}", font=font(200), fill=(255, 255, 255), anchor="rm")
    photo = Image.open(CONTENT / f"images/questions_ab/{QUESTION_IMAGE}.webp").convert("RGB")
    pw = W - 180
    ph = int(photo.height * pw / photo.width)
    photo = photo.resize((pw, ph), Image.LANCZOS)
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=22, fill=255)
    img.paste(photo, (90, HEADER + 70), mask)
    y = HEADER + 70 + ph + 60
    for line in textwrap.wrap(question, 40):
        d.text((90, y), line, font=font(64, "Medium"), fill=(40, 42, 52))
        y += 84
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    q = question_text()
    for n in (1, 10, 20, 40):
        ticket(n, q).save(OUT / f"ticket_{n}.png")
    ticket(None, q).save(OUT / "ticket_blank.png")
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rectangle([0, 0, W, HEADER], fill=255)
    m.save(OUT / "ticket_mask.png")
    print("ok", OUT)


main()
