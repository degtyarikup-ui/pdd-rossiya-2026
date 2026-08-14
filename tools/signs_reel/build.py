#!/usr/bin/env python3
"""Сборка ролика «Успей узнать знак».

Порядок жёсткий и менять его нельзя: сначала считается таймлайн В КАДРАХ,
потом под него генерится озвучка, потом озвучка проверяется, и только затем
рисуются кадры. Таймлайн в кадрах — потому что расхождение картинки и звука
не «на полсекунды длиннее», а накопленный сдвиг: к концу под карточкой звучит
уже следующая фраза.

    python3 -m tools.signs_reel.build --category "Запрещающие знаки"
    python3 -m tools.signs_reel.build --list
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import warnings
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

warnings.filterwarnings("ignore")

import numpy as np

from . import audio, backgrounds, config as C, content, frames, raster, verify

OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "videos" / "signs_reel"
WORK_DIR = Path(__file__).resolve().parent / ".work"
# Кэш озвучки общий на все выпуски: имя файла уже содержит хэш текста и
# голоса, поэтому одна и та же реплика не синтезируется дважды.
TTS_DIR = WORK_DIR / "tts"
BRAND = "ПДД РОССИЯ 2026"


def sec_to_frames(seconds: float) -> int:
    return max(1, int(round(seconds * C.FPS)))


@dataclass
class Segment:
    kind: str        # intro | show | count | reveal | swipe | outro
    start: int       # кадр начала (включительно)
    length: int      # длительность в кадрах
    index: int = -1  # индекс знака

    @property
    def end(self) -> int:
        return self.start + self.length


@dataclass
class Voice:
    key: str
    text: str
    path: Path
    samples: int = 0

    @property
    def seconds(self) -> float:
        return self.samples / C.SR


MAX_SECONDS = 58.0  # после минуты Shorts перестают показываться лентой


def intro_text(category: str) -> str:
    return f"Успеете узнать дорожный знак за 3 секунды? Сегодня — {category.lower()}."


OUTRO_TEXT = "Сколько угадали? Напишите в комментариях."


def voice_lines(category: str, signs: list, with_notes: bool) -> list[Voice]:
    """Реплики диктора. Название знака — дословно из signs.json."""
    lines = [Voice("intro", intro_text(category), Path())]
    for i, sign in enumerate(signs):
        text = f"{sign.title}."
        if with_notes and sign.note:
            text = f"{sign.title}. {sign.note}."
        lines.append(Voice(f"sign{i}", text, Path()))
    lines.append(Voice("outro", OUTRO_TEXT, Path()))
    return lines


def synthesize_all(lines: list[Voice], vc: audio.VoiceConfig, workdir: Path) -> None:
    """Генерит все реплики параллельно и измеряет их реальную длительность."""
    workdir.mkdir(parents=True, exist_ok=True)

    def one(v: Voice) -> Voice:
        v.path = workdir / f"tts_{v.key}_{audio.tts_cache_key(v.text, vc)}.wav"
        audio.synthesize(v.text, v.path, vc)
        v.samples = len(audio.trim_silence(audio.read_wav(v.path)))
        return v

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(one, lines))

    # Пропущенный клип не должен «стоить ноль секунд»: такой ролик выглядит
    # собранным, а звук в нём разъезжается с картинкой.
    missing = [v.key for v in lines if not v.path.exists() or v.samples == 0]
    if missing:
        raise SystemExit(f"озвучка не собралась: {', '.join(missing)} — сборка остановлена")


def build_timeline(lines: list[Voice], count: int) -> list[Segment]:
    """Таймлайн в кадрах. Длина фазы ответа — по реальной длине озвучки."""
    by_key = {v.key: v for v in lines}
    segments: list[Segment] = []
    cursor = 0

    def add(kind: str, seconds: float, index: int = -1) -> None:
        nonlocal cursor
        seg = Segment(kind, cursor, sec_to_frames(seconds), index)
        segments.append(seg)
        cursor = seg.end

    add("intro", by_key["intro"].seconds + C.INTRO_TAIL)
    for i in range(count):
        add("show", C.T_SHOW, i)
        add("count", C.T_COUNTDOWN, i)
        add("reveal", max(by_key[f"sign{i}"].seconds + C.T_REVEAL_TAIL, C.T_REVEAL_MIN), i)
        if i < count - 1:
            add("swipe", C.T_SWIPE, i)
    add("outro", max(by_key["outro"].seconds + C.OUTRO_TAIL, C.OUTRO_MIN))
    return segments


def build_audio(segments: list[Segment], lines: list[Voice], total_frames: int) -> np.ndarray:
    """Голос и тиканье, разложенные по абсолютным позициям таймлайна."""
    by_key = {v.key: v for v in lines}
    total_seconds = total_frames / C.FPS
    tracks: list = []

    for seg in segments:
        at = seg.start / C.FPS
        if seg.kind == "intro":
            tracks.append((at, audio.trim_silence(audio.read_wav(by_key["intro"].path))))
        elif seg.kind == "count":
            tracks.append((at, audio.tick_track(seg.length / C.FPS)))
        elif seg.kind == "reveal":
            tracks.append((at, audio.reveal_chime()))
            tracks.append((at + 0.18, audio.trim_silence(audio.read_wav(by_key[f"sign{seg.index}"].path))))
        elif seg.kind == "outro":
            tracks.append((at, audio.trim_silence(audio.read_wav(by_key["outro"].path))))

    return audio.mix(tracks, total_seconds)


def chunk_at(chunks: list, k: float, voiced: float = 0.85) -> str:
    """Какой кусок субтитров показывать в момент k (0..1) внутри фазы.

    Куски идут равномерно по той части фазы, где звучит голос: хвост фазы —
    это пауза после реплики, и на ней держится последний кусок.
    """
    if not chunks:
        return ""
    position = min(1.0, max(0.0, k / voiced))
    index = min(len(chunks) - 1, int(position * len(chunks)))
    return chunks[index]


def ease_out(k: float) -> float:
    """Замедление к концу: при ease-in-out свайп читается рывком."""
    return 1 - (1 - k) ** 3


def make_cards(signs: list, workdir: Path) -> list[frames.SignCard]:
    cards = []
    for sign in signs:
        img = raster.fit(raster.rasterize(sign.image, 640), C.SIGN_BOX)
        cards.append(frames.SignCard(number=sign.number, title=sign.title,
                                     note=sign.note, image=img))
    return cards


def frame_at(n: int, segments: list[Segment], cards: list[frames.SignCard],
             header: str, category: str) -> frames.Frame:
    seg = next(s for s in segments if s.start <= n < s.end)
    k = (n - seg.start) / seg.length
    total = len(cards)

    if seg.kind == "intro":
        return frames.Frame(header=header, intro={
            "subtitle": chunk_at(frames.split_subtitles(intro_text(category)), k),
        })

    if seg.kind == "outro":
        return frames.Frame(header=header, outro={
            "signs": [(c.number, c.title, c.image) for c in cards],
            "banner_frame": n - seg.start,
        })

    i = seg.index
    card = cards[i]

    if seg.kind == "show":
        card.revealed, card.progress, card.reveal_k = False, 1.0, 0.0
        return frames.Frame(header=header, cards=[(card, 0.0, 1.0, 1.0)],
                            timer_text="3", timer_ratio=1.0,
                            step=i + 1, steps_total=total)

    if seg.kind == "count":
        left = 1.0 - k
        card.revealed, card.progress, card.reveal_k = False, left, 0.0
        seconds_left = max(1, int(-(-C.T_COUNTDOWN * left // 1)))  # округление вверх
        return frames.Frame(header=header, cards=[(card, 0.0, 1.0, 1.0)],
                            timer_text=str(seconds_left), timer_ratio=left,
                            step=i + 1, steps_total=total)

    if seg.kind == "reveal":
        # Чипа в этой фазе нет: слово «Ответ» ничего не сообщает — ответ и так
        # на карточке. Ничего под чипом не двигается, поэтому вёрстка не едет.
        card.revealed, card.progress = True, 0.0
        card.reveal_k = min(1.0, k * 6)
        return frames.Frame(header=header, cards=[(card, 0.0, 1.0, 1.0)],
                            step=i + 1, steps_total=total)

    # swipe: карточки едут как страницы PageView в приложении — обе живут
    # в кадре одновременно, поэтому рисуем обе.
    e = ease_out(k)
    out_card = card
    out_card.revealed, out_card.progress, out_card.reveal_k = True, 0.0, 1.0
    in_card = cards[i + 1]
    in_card.revealed, in_card.progress, in_card.reveal_k = False, 1.0, 0.0
    return frames.Frame(
        header=header,
        cards=[(out_card, -e, 1.0, 1.0), (in_card, 1.0 - e, 1.0, 1.0)],
        timer_text="3", timer_ratio=1.0,
        step=i + 2, steps_total=total,
    )


def render_video(segments: list[Segment], cards: list[frames.SignCard], header: str,
                 category: str, background, out_path: Path) -> int:
    total_frames = segments[-1].end
    out_path.parent.mkdir(parents=True, exist_ok=True)

    proc = subprocess.Popen(
        ["ffmpeg", "-y", "-v", "error",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{C.W}x{C.H}", "-r", str(C.FPS),
         "-i", "-",
         "-c:v", "libx264", "-preset", "medium", "-crf", "19",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart",
         str(out_path)],
        stdin=subprocess.PIPE,
    )
    try:
        for n in range(total_frames):
            frame = frame_at(n, segments, cards, header, category)
            proc.stdin.write(frames.render_frame(frame, background).tobytes())
            if n % 90 == 0:
                pct = 100 * n // total_frames
                print(f"\r  кадры: {n}/{total_frames} ({pct}%)", end="", flush=True)
    finally:
        proc.stdin.close()
        proc.wait()
    print(f"\r  кадры: {total_frames}/{total_frames} (100%)")
    if proc.returncode != 0:
        raise SystemExit("ffmpeg не смог собрать видео")
    return total_frames


def main() -> None:
    p = argparse.ArgumentParser(description="Ролик «Успей узнать знак» 1080×1920")
    p.add_argument("--category", help="категория знаков, например «Запрещающие знаки»")
    p.add_argument("--country", default="ru")
    p.add_argument("--count", type=int, default=6, help="сколько знаков в выпуске")
    p.add_argument("--voice", default="Algenib", help="голос Gemini TTS")
    p.add_argument("--numbers", nargs="*", help="взять именно эти знаки по номеру")
    p.add_argument("--reuse", action="store_true", help="разрешить знаки, которые уже выходили")
    p.add_argument("--no-notes", action="store_true", help="диктор читает только название знака")
    p.add_argument("--list", action="store_true", help="показать категории и остаток знаков")
    p.add_argument("--out", help="путь к готовому mp4")
    p.add_argument("--background", help="имя фона из tools/signs_reel/backgrounds")
    p.add_argument("--skip-verify", action="store_true", help="не расшифровывать озвучку обратно")
    args = p.parse_args()

    if args.list or not args.category:
        state = content.load_state()
        pool = content.load_signs(args.country)
        print(f"{'годных':>7} {'осталось':>9}  категория")
        for cat, signs in pool.items():
            used = set(state["used"].get(f"{args.country}:{cat}", []))
            left = len([s for s in signs if s.number not in used])
            mark = "" if left >= args.count else "   ← на выпуск не хватает"
            print(f"{len(signs):>7} {left:>9}  {cat}{mark}")
        if not args.category:
            sys.exit(0)

    category = args.category
    signs = content.pick_episode(category, args.count, args.country,
                                reuse=args.reuse, numbers=args.numbers)
    # Слаг детерминированный: встроенный hash() у строк солится на каждый
    # запуск, и один и тот же выпуск каждый раз уезжал бы в новый файл.
    episode = hashlib.sha1(
        f"{args.country}|{category}|{','.join(s.number for s in signs)}".encode("utf-8")
    ).hexdigest()[:8]
    slug = f"{args.country}_{episode}"
    workdir = WORK_DIR / slug
    out_path = Path(args.out) if args.out else OUT_DIR / f"signs_{slug}.mp4"

    print(f"Выпуск: {category} · {len(signs)} знаков · голос {args.voice}")
    for s in signs:
        print(f"  {s.number:>7}  {s.title}" + (f"   — {s.note}" if s.note else ""))

    vc = audio.VoiceConfig(voice=args.voice)
    print("Озвучка…")

    # Пояснение диктор читает, только если ролик после этого остаётся
    # в пределах минуты. Пояснение на экране остаётся в любом случае.
    lines = voice_lines(category, signs, with_notes=False)
    synthesize_all(lines, vc, TTS_DIR)
    segments = build_timeline(lines, len(signs))

    if not args.no_notes and any(s.note for s in signs):
        rich = voice_lines(category, signs, with_notes=True)
        # Сначала прикидываем длину по тексту и синтезируем вариант с
        # пояснениями, только если он в принципе может влезть: иначе на серии
        # из 30 роликов впустую уходит половина обращений к синтезу.
        estimate = sum(0.32 + len(v.text) * 0.075 for v in rich) + \
            len(signs) * (C.T_SHOW + C.T_COUNTDOWN + C.T_REVEAL_TAIL + C.T_SWIPE) + \
            C.INTRO_TAIL + C.OUTRO_TAIL
        if estimate <= MAX_SECONDS:
            synthesize_all(rich, vc, TTS_DIR)
            rich_segments = build_timeline(rich, len(signs))
            if rich_segments[-1].end / C.FPS <= MAX_SECONDS:
                lines, segments = rich, rich_segments
            else:
                print("  пояснения не влезают в минуту — диктор читает только названия")
        else:
            print(f"  пояснения не влезают (~{estimate:.0f} с) — диктор читает только названия")

    total_frames = segments[-1].end
    total_seconds = total_frames / C.FPS
    print(f"Хронометраж: {total_seconds:.1f} с ({total_frames} кадров)")
    if total_seconds > MAX_SECONDS:
        raise SystemExit(
            f"ролик длиннее минуты ({total_seconds:.1f} с) даже без пояснений. "
            f"Возьмите --count {len(signs) - 1}."
        )

    if not args.skip_verify:
        print("Сверка озвучки с текстом…")
        problems, skipped = verify.check_voice(lines, vc)
        if problems:
            for line in problems:
                print(f"  ✗ {line}")
            raise SystemExit(
                "синтез договорил от себя — удалите проблемные wav в "
                f"{TTS_DIR} и запустите сборку заново"
            )
        if skipped:
            print(f"  ⚠ {len(skipped)} из {len(lines)} реплик не удалось расшифровать:")
            for line in skipped[:3]:
                print(f"    {line}")
            print("    озвучка НЕ проверена — прослушайте готовый ролик перед публикацией")
        else:
            print("  все реплики совпали с текстом")

    print("Кадры…")
    cards = make_cards(signs, workdir)
    silent = workdir / "video.mp4"
    background = backgrounds.load(args.background) if args.background else backgrounds.pick(slug)
    if background is None:
        print("  ⚠ нет фонов: запустите python3 -m tools.signs_reel.backgrounds")
    render_video(segments, cards, category, category, background, silent)

    track = build_audio(segments, lines, total_frames)
    wav = audio.write_wav(workdir / "audio.wav", track)

    verify.check_durations(silent, wav, total_frames)
    audio.mux(silent, wav, out_path)
    verify.check_result(out_path, total_frames)

    if not args.numbers:
        content.mark_used(category, signs, args.country)

    size_mb = out_path.stat().st_size / 1024 / 1024
    print(f"\nГотово: {out_path}  ({total_seconds:.1f} с, {size_mb:.1f} МБ)")


if __name__ == "__main__":
    main()
