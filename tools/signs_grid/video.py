#!/usr/bin/env python3
"""Ролик «Тест по знакам»: общий план → наезд на знак → 3 с → ответ.

Камера — это кроп из кадра общего плана, нарисованного в 3× (`overview.render`),
поэтому при наезде текст остаётся резким. Остальные клетки при наезде
притушены, время показывает полоса внутри клетки (цвет — как в «Успей узнать
знак»). Диктор: короткое интро, название верного знака на ответе и финальная
фраза. Длина фаз считается по реальной длине реплик; предел для этого
короткого формата — 58 секунд.

    /usr/bin/python3 -m tools.signs_grid.video                # выпуск 1
    /usr/bin/python3 -m tools.signs_grid.video --episode 3    # выпуск из episodes.json
    /usr/bin/python3 -m tools.signs_grid.video --all          # вся серия
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from tools.signs_reel import audio as A
from tools.signs_reel import config as C
from tools.signs_reel import verify
from tools.signs_reel.build import TTS_DIR, Voice, synthesize_all
from tools.signs_reel.frames import bar_color

from . import overview as O
from . import series

WORK = O.OUT / ".work"
MAX_SECONDS = 58.0
SYNTH_RETRIES = 3
SS = 3.0                     # во сколько раз крупнее рисуется исходный кадр

# ── Тайминги (сек) ─────────────────────────────────────────────────────────
T_INTRO = 1.5        # общий план до первого наезда (не меньше)
T_MOVE = 0.5         # перелёт камеры к следующей клетке
T_COUNT = 3.0        # отсчёт
T_REVEAL = 0.8       # ответ подсвечен, камера стоит (не меньше)
T_FADE = 0.25        # проявление подсветки ответа
T_BACK = 0.6         # отъезд на общий план в конце
T_OUTRO = 2.5        # общий план со всеми ответами (не меньше)
VOICE_DELAY = 0.18   # название звучит сразу после «дзынь», как в «Успей узнать знак»
VOICE_TAIL = -0.2    # камера трогается к следующему знаку на последнем слоге — экономит ~3 с на ролик
OUTRO_TAIL = 0.8     # финал держится после последней фразы — сверить ответы

# Стиль диктора — согласованная инструкция из game_reels/voice.py: короткий
# формат, поэтому быстро и живо. Стиль по умолчанию (VoiceConfig, «ровный
# темп») для теста из 9 знаков звучал медленно и тяжело.
VOICE_STYLE = (
    "Говори по-русски быстро, энергично и естественно, как молодой ведущий "
    "короткого видео. Короткие паузы. Без крика, без растягивания слов, "
    "без театральности. Произнеси только заданный текст."
)

COUNT_WORDS = {6: "Шесть", 7: "Семь", 8: "Восемь", 9: "Девять", 10: "Десять"}
OUTRO_TEXT = "Сколько угадали? Напишите в комментариях."


def voice_lines() -> list[Voice]:
    """Реплики диктора. Название знака — дословно из signs.json."""
    db = O.load_db()
    n = len(O.QUIZ)
    lines = [Voice("intro", f"Тест по дорожным знакам. {COUNT_WORDS[n]} знаков, "
                            f"три секунды на каждый.", Path())]
    for i, (number, _) in enumerate(O.QUIZ):
        lines.append(Voice(f"sign{i}", db[number]["title"].strip().rstrip(".") + ".", Path()))
    lines.append(Voice("outro", OUTRO_TEXT, Path()))
    return lines

# ── Камера ─────────────────────────────────────────────────────────────────
CELL_MARGIN = 30     # поля вокруг клетки при наезде, в пикселях кадра 1:1
CELL_SHIFT_Y = 0
DIM = 0.72           # насколько уводить соседние клетки в тёмно-синий при наезде
DIM_COLOR = (2, 30, 80)
BAR_H = 30
BAR_INSET = 110
BAR_BOTTOM = 52      # от низа клетки до низа полосы — полоса внутри клетки, под вариантами


def ease(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def frames(sec: float) -> int:
    return round(sec * C.FPS)


OVERVIEW = (C.W / 2, C.H / 2, float(C.W))     # центр x, центр y, ширина окна


def cell_cam(i: int) -> tuple[float, float, float]:
    x0, y0, x1, y1 = O.cell_rect(i)
    return (x0 + x1) / 2, (y0 + y1) / 2 + CELL_SHIFT_Y, float(x1 - x0 + 2 * CELL_MARGIN)


def lerp_cam(a, b, t):
    # Ширину — геометрически: так наезд воспринимается равномерным.
    w = a[2] * (b[2] / a[2]) ** t
    return a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, w


def lerp_rect(a, b, t):
    return tuple(p + (q - p) * t for p, q in zip(a, b))


def build_timeline(voice: dict[str, float], count: int = None) -> list[dict]:
    """Покадровый план: где камера, что притушено, что с полосой и ответами.

    voice — длительности реплик в секундах; по ним растягиваются интро,
    ответы и финал. Реплика ставится флагом `voice` на свой первый кадр.
    """
    n = len(O.QUIZ) if count is None else count
    plan: list[dict] = []

    def add(count, fn):
        for k in range(count):
            plan.append(fn(k / max(1, count - 1) if count > 1 else 1.0, k))

    # Интро может договариваться во время первого наезда, но не на отсчёте.
    add(frames(max(T_INTRO, voice["intro"] + 0.2 - T_MOVE)),
        lambda t, k: dict(cam=OVERVIEW, dim=0.0, rect=O.cell_rect(0)))
    plan[0]["voice"] = "intro"
    for i in range(n):
        prev_cam = OVERVIEW if i == 0 else cell_cam(i - 1)
        prev_rect = O.cell_rect(0 if i == 0 else i - 1)
        move = frames(T_MOVE)
        for k in range(move):
            e = ease((k + 1) / move)
            plan.append(dict(cam=lerp_cam(prev_cam, cell_cam(i), e),
                             dim=DIM * (e if i == 0 else 1.0),
                             rect=lerp_rect(prev_rect, O.cell_rect(i), e)))
        count = frames(T_COUNT)
        for k in range(count):
            plan.append(dict(cam=cell_cam(i), dim=DIM, rect=O.cell_rect(i),
                             bar=1.0 - k / count, count_start=(k == 0), sign=i))
        # Other answers may end during the next camera move; the final one
        # must finish before the outro starts so two voices never overlap.
        tail = 0.15 if i == n - 1 else VOICE_TAIL
        reveal = frames(max(T_REVEAL, VOICE_DELAY + voice[f"sign{i}"] + tail))
        fade = frames(T_FADE)
        for k in range(reveal):
            plan.append(dict(cam=cell_cam(i), dim=DIM, rect=O.cell_rect(i),
                             bar=0.0, bar_alpha=max(0.0, 1 - k / fade),
                             reveal=(i, min(1.0, (k + 1) / fade)), chime=(k == 0),
                             voice=f"sign{i}" if k == frames(VOICE_DELAY) else None))
    back = frames(T_BACK)
    outro_at = len(plan)
    for k in range(back):
        e = ease((k + 1) / back)
        plan.append(dict(cam=lerp_cam(cell_cam(n - 1), OVERVIEW, e), dim=DIM * (1 - e),
                         rect=O.cell_rect(n - 1)))
    add(frames(max(T_OUTRO, voice["outro"] + OUTRO_TAIL - T_BACK)),
        lambda t, k: dict(cam=OVERVIEW, dim=0.0, rect=O.cell_rect(0)))
    plan[outro_at]["voice"] = "outro"
    return plan


def camera_frame(src: Image.Image, cam) -> tuple[Image.Image, callable]:
    cx, cy, w = cam
    h = w * C.H / C.W
    x0, y0 = cx - w / 2, cy - h / 2
    box = tuple(round(v * SS) for v in (x0, y0, x0 + w, y0 + h))
    img = src.resize((C.W, C.H), Image.BICUBIC, box=box, reducing_gap=2.0)
    k = C.W / w

    def to_screen(x, y):
        return (x - x0) * k, (y - y0) * k

    return img, to_screen


def draw_dim(img: Image.Image, rect, to_screen, alpha: float, cell_count: int = None) -> None:
    if alpha <= 0.01:
        return
    ax, ay = to_screen(rect[0], rect[1])
    bx, by = to_screen(rect[2], rect[3])
    # Угловые клетки сетки скруглены вместе с карточкой — вырез повторяет
    # скругление, иначе в углу просвечивает непритушенный фон.
    gx0, gy0, _, _ = O.cell_rect(0)
    _, _, gx1, gy1 = O.cell_rect((len(O.QUIZ) if cell_count is None else cell_count) - 1)

    def near(a, b):
        return abs(a - b) < 1

    corners = (near(rect[0], gx0) and near(rect[1], gy0), near(rect[2], gx1) and near(rect[1], gy0),
               near(rect[2], gx1) and near(rect[3], gy1), near(rect[0], gx0) and near(rect[3], gy1))
    k = (bx - ax) / (rect[2] - rect[0])
    mask = Image.new("L", (C.W, C.H), round(255 * alpha))
    ImageDraw.Draw(mask).rounded_rectangle((ax, ay, bx, by), radius=max(1, round(C.CARD_RADIUS * k)),
                                           fill=0, corners=corners)
    img.paste(Image.new("RGB", (C.W, C.H), DIM_COLOR), (0, 0), mask)


def draw_bar(img: Image.Image, rect, to_screen, ratio: float, alpha: float) -> None:
    if alpha <= 0.01:
        return
    _, by = to_screen(rect[2], rect[3])
    y = round(by - BAR_BOTTOM - BAR_H)
    x0, x1 = BAR_INSET, C.W - BAR_INSET
    d = ImageDraw.Draw(img, "RGBA")
    a = round(255 * alpha)
    d.rounded_rectangle((x0, y, x1, y + BAR_H), radius=BAR_H // 2, fill=(*C.GRAY, a))
    fw = round((x1 - x0) * ratio)
    if fw >= BAR_H:
        d.rounded_rectangle((x0, y, x0 + fw, y + BAR_H), radius=BAR_H // 2,
                            fill=(*bar_color(ratio), a))


def gcloud_project() -> str:
    """Проект из ADC, а без ADC — из обычного входа gcloud (как в game_reels/voice.py).

    Без ADC клиент genai получает токен `gcloud auth print-access-token`:
    подменяем genai.Client, чтобы и синтез, и сверка в verify шли с ним.
    """
    try:
        return A.default_project()
    except SystemExit:
        pass
    from google import genai
    from google.oauth2.credentials import Credentials

    original = genai.Client

    def client(**kwargs):
        token = subprocess.check_output(["gcloud", "auth", "print-access-token"],
                                        stderr=subprocess.DEVNULL, text=True).strip()
        return original(**kwargs, credentials=Credentials(token=token))

    if not getattr(original, "_gcloud_token", False):   # подменяем один раз на процесс
        client._gcloud_token = True
        genai.Client = client
    return subprocess.check_output(["gcloud", "config", "get-value", "project"],
                                   stderr=subprocess.DEVNULL, text=True).strip()


def render_video(out: Path, voice_name: str, skip_verify: bool, *,
                 cells: list[O.Cell] = None, lines: list[Voice] = None,
                 header: str = O.HEADER, image_h: int = O.SIGN_BOX,
                 workdir: Path = WORK) -> Path:
    cells = O.sign_cells() if cells is None else cells
    out.parent.mkdir(parents=True, exist_ok=True)
    vc = A.VoiceConfig(voice=voice_name, style=VOICE_STYLE, project=gcloud_project())
    lines = voice_lines() if lines is None else lines
    print("Озвучка…")
    for v in lines:
        print(f"  {v.key:>6}  {v.text}")
    synthesize_all(lines, vc, TTS_DIR)

    if not skip_verify:
        print("Сверка озвучки с текстом…")
        # Брак синтеза на коротких названиях — обычное дело («Конец
        # велосипедной дорожки» вместо «…зоны»): проблемный клип удаляем
        # и синтезируем заново, и только после SYNTH_RETRIES неудач стоп.
        for attempt in range(SYNTH_RETRIES + 1):
            problems, skipped = verify.check_voice(lines, vc)
            if not problems:
                break
            for line in problems:
                print(f"  ✗ {line}")
            if attempt == SYNTH_RETRIES:
                raise SystemExit(f"синтез не удался за {SYNTH_RETRIES} повтора — удалите проблемные wav в {TTS_DIR}")
            bad = {line.split(":", 1)[0] for line in problems}
            for v in lines:
                if v.key in bad:
                    v.path.unlink(missing_ok=True)
            print(f"  повтор синтеза: {', '.join(sorted(bad))}")
            synthesize_all(lines, vc, TTS_DIR)
        if skipped:
            print(f"  ⚠ {len(skipped)} из {len(lines)} реплик не удалось расшифровать — "
                  "прослушайте ролик перед публикацией")
        else:
            print("  все реплики совпали с текстом")

    clips = {v.key: A.trim_silence(A.read_wav(v.path)) for v in lines}
    plan = build_timeline({k: len(c) / C.SR for k, c in clips.items()}, len(cells))
    total = len(plan)
    print(f"Хронометраж: {total / C.FPS:.1f} с ({total} кадров)")
    if total / C.FPS > MAX_SECONDS:
        raise SystemExit(f"ролик длиннее {MAX_SECONDS:.0f} с — сократите число вопросов или реплики")

    print("рисую общий план в 3×…")
    current = O.render(False, SS, cells=cells, header=header, image_h=image_h)
    answered = O.render(True, SS, cells=cells, header=header, image_h=image_h)

    def cell_box(i):
        return tuple(round(v * SS) for v in O.cell_rect(i))

    workdir.mkdir(parents=True, exist_ok=True)
    (workdir / "timeline.json").write_text(json.dumps({
        "fps": C.FPS, "frames": total, "plan": plan,
        "voice": [{"key": v.key, "text": v.text, "seconds": len(clips[v.key]) / C.SR,
                   "path": str(v.path)} for v in lines],
    }, ensure_ascii=False), encoding="utf-8")
    silent = workdir / "video.mp4"
    proc = subprocess.Popen(
        ["ffmpeg", "-y", "-v", "error",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{C.W}x{C.H}", "-r", str(C.FPS),
         "-i", "-",
         "-c:v", "libx264", "-preset", "medium", "-crf", "19",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(silent)],
        stdin=subprocess.PIPE,
    )
    sounds: list[tuple[float, np.ndarray]] = []
    try:
        for n, f in enumerate(plan):
            if "reveal" in f:
                i, a = f["reveal"]
                box = cell_box(i)
                patch = Image.blend(current.crop(box), answered.crop(box), a) if a < 1 else answered.crop(box)
                current.paste(patch, box[:2])
            if f.get("count_start"):
                sounds.append((n / C.FPS, A.tick_track(T_COUNT)))
            if f.get("chime"):
                sounds.append((n / C.FPS, A.reveal_chime()))
            if f.get("voice"):
                sounds.append((n / C.FPS, clips[f["voice"]]))

            img, to_screen = camera_frame(current, f["cam"])
            draw_dim(img, f["rect"], to_screen, f["dim"], len(cells))
            if "bar" in f:
                draw_bar(img, f["rect"], to_screen, f["bar"], f.get("bar_alpha", 1.0))
            proc.stdin.write(img.tobytes())
            if n % 90 == 0:
                print(f"\r  кадры: {n}/{total}", end="", flush=True)
    finally:
        proc.stdin.close()
        proc.wait()
    print(f"\r  кадры: {total}/{total}")
    if proc.returncode != 0:
        raise SystemExit("ffmpeg не смог собрать видео")

    # Звук — ровно той же длины, что и видео (в кадрах), без -shortest.
    wav = A.write_wav(workdir / "audio.wav", A.mix(sounds, total / C.FPS))
    verify.check_durations(silent, wav, total)
    A.mux(silent, wav, out)
    verify.check_result(out, total)
    return out


def main() -> None:
    p = argparse.ArgumentParser(description="Ролик «Тест по знакам» 1080×1920")
    p.add_argument("--episode", type=int, default=1, help="номер выпуска из episodes.json")
    p.add_argument("--all", action="store_true", help="собрать все выпуски серии")
    p.add_argument("--voice", default="Algenib", help="голос Gemini TTS")
    p.add_argument("--skip-verify", action="store_true", help="не расшифровывать озвучку обратно")
    args = p.parse_args()
    O.OUT.mkdir(parents=True, exist_ok=True)
    total = len(json.loads(series.PLAN.read_text(encoding="utf-8")))
    for e in (range(1, total + 1) if args.all else [args.episode]):
        print(f"\n══ Выпуск {e}/{total}")
        O.QUIZ = series.load(e)
        print(render_video(O.OUT / f"signs_grid_{e:02d}.mp4", args.voice, args.skip_verify))


if __name__ == "__main__":
    main()
