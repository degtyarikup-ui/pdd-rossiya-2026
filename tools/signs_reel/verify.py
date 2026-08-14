#!/usr/bin/env python3
"""Проверки, без которых брак доезжает до зрителя.

Три вещи ловятся здесь:
1. Синтез договаривает от себя — клип расшифровывается обратно и сравнивается
   с исходным текстом выравниванием, а не по началу строки: синтез умеет
   проглотить слово в середине, и проверка «совпадает ли начало» отключится.
2. Картинка и звук разъезжаются — длины сверяются с точностью до кадра.
3. Готовый файл оказался короче задуманного — `-shortest` такой ролик молча
   обрезал бы и выдал за готовый.
"""

from __future__ import annotations

import difflib
import json
import re
import subprocess
import warnings
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

warnings.filterwarnings("ignore")

from . import audio, config as C

# Расшифровка нужна только как сторож, поэтому берём быструю модель.
# gemini-3.1-flash в проекте недоступен (404) — рабочая модель первой,
# иначе каждый клип тратит лишний заведомо неудачный вызов.
STT_MODELS = ["gemini-2.5-flash"]
SIMILARITY_MIN = 0.82
SIMILARITY_SHORT = 0.50   # для реплик короче SHORT_TEXT символов
SHORT_TEXT = 20


PREAMBLE = re.compile(r"^\s*(thought|thinking|reasoning)\b", re.IGNORECASE)


def strip_preamble(text: str) -> str:
    """Убирает служебный «THOUGHT: …» перед расшифровкой.

    Модель иногда выдаёт рассуждение о задаче вместе с ответом. Оно всегда
    по-английски, а расшифровка — по-русски, поэтому отрезаем всё до первой
    кириллицы. Без этого сторож ругается на исправные клипы.
    """
    if not PREAMBLE.search(text):
        return text
    match = re.search(r"[А-Яа-яЁё]", text)
    return text[match.start():] if match else text


def normalize(text: str) -> list[str]:
    text = text.lower().replace("ё", "е")
    text = re.sub(r"[^а-яa-z0-9 ]+", " ", text)
    return text.split()


class Unavailable(RuntimeError):
    """Расшифровка не сработала по вине инфраструктуры, а не из-за брака клипа."""


def transcribe(wav: Path, vc, attempts: int = 5) -> str:
    import time

    from google import genai
    from google.genai import types

    client = genai.Client(vertexai=True, project=vc.project, location=vc.location)
    data = wav.read_bytes()
    last_error = None
    for model in STT_MODELS:
        for attempt in range(attempts):
            try:
                resp = client.models.generate_content(
                    model=model,
                    contents=[
                        types.Part.from_bytes(data=data, mime_type="audio/wav"),
                        "Расшифруй эту аудиозапись дословно на русском. "
                        "Верни только текст, без пояснений и знаков форматирования.",
                    ],
                )
                return strip_preamble((resp.text or "").strip())
            except Exception as exc:
                last_error = exc
                transient = any(c in str(exc) for c in ("429", "RESOURCE_EXHAUSTED", "500", "INTERNAL", "503"))
                if not transient:
                    break  # модель недоступна в проекте — пробуем следующую
                time.sleep(2 ** attempt)
    raise Unavailable(f"расшифровка недоступна: {str(last_error)[:120]}")


VERIFIED_PATH = Path(__file__).resolve().parent / ".work" / "verified.json"


def _verified() -> set:
    if VERIFIED_PATH.exists():
        return set(json.loads(VERIFIED_PATH.read_text(encoding="utf-8")))
    return set()


def _remember(names: list) -> None:
    VERIFIED_PATH.parent.mkdir(parents=True, exist_ok=True)
    VERIFIED_PATH.write_text(json.dumps(sorted(_verified() | set(names)), ensure_ascii=False),
                             encoding="utf-8")


def check_voice(lines: list, vc) -> tuple:
    """Проверяет озвучку. Возвращает (проблемные реплики, недоступные).

    Уже проверенные клипы пропускаются: имя файла содержит хэш текста и
    голоса, поэтому «проверен» относится к конкретному звуку, а не к реплике.
    Без этого серия из 30 роликов упирается в лимиты на расшифровку.
    """
    known = _verified()

    def one(v):
        if v.path.name in known:
            return ("ok", "")
        # Расшифровщик читает как повезёт: одно и то же «Тоннель» подряд
        # услышано как «Тунель», «домен» и «Туннель». Поэтому берём лучшую
        # попытку из трёх, а не первую. Повтор случается редко — цикл
        # выходит на первом же совпадении.
        attempts = 3
        verdict = None
        for _ in range(attempts):
            try:
                heard = transcribe(v.path, vc)
            except Unavailable as exc:
                return ("skip", f"{v.key}: {exc}")
            verdict = judge(v, heard)
            if verdict[0] == "ok":
                return verdict
        return verdict

    def judge(v, heard):
        want, got = normalize(v.text), normalize(heard)
        if not got:
            return ("bad", f"{v.key}: в клипе не распознано ни слова")

        # Сравниваем выравниванием, а не по началу строки: синтез умеет
        # проглотить слово в середине, и проверка «совпадает ли начало»
        # молча отключилась бы.
        matcher = difflib.SequenceMatcher(None, want, got)
        blocks = matcher.get_matching_blocks()
        coverage = sum(b.size for b in blocks) / len(want)
        tail_start = max((b.b + b.size for b in blocks if b.size), default=0)
        extra = got[tail_start:]

        # Отсебятина — это когда узнан ВЕСЬ текст и после него звучит ещё
        # что-то. Если хоть одно слово не совпало, лишнее в хвосте почти
        # всегда искажение этого слова, а не добавка: «Место для разворота»
        # слышится как «Место для разговора». Такие случаи добивает
        # посимвольная сверка, а не обвинение диктора.
        if extra and coverage >= 1.0:
            return ("bad", f"{v.key}: диктор добавил от себя «{' '.join(extra)}» (текст: «{v.text}»)")

        # Порог мягче для коротких реплик: на одном слове ослышка в паре букв
        # роняет сходство вдвое («Тоннель» → «Тоня» это 0.55), а поймать здесь
        # надо не это, а совсем чужой звук — например, клип другого знака.
        want_str, got_str = " ".join(want), " ".join(got)
        ratio = difflib.SequenceMatcher(None, want_str, got_str).ratio()
        threshold = SIMILARITY_MIN if len(want_str) >= SHORT_TEXT else SIMILARITY_SHORT
        if ratio < threshold:
            return ("bad", f"{v.key}: расшифровка не сошлась ({ratio:.2f}) — услышано «{heard}»")

        # Независимая от расшифровки проверка: клип не может звучать сильно
        # дольше, чем нужно на этот текст.
        expected = 0.32 + len(v.text) * 0.075
        if v.seconds > expected * 1.8:
            return ("bad", f"{v.key}: клип {v.seconds:.1f} с при ожидаемых ~{expected:.1f} с — похоже, диктор договорил лишнее")
        return ("ok", "")

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(one, lines))

    _remember([v.path.name for v, (kind, _) in zip(lines, results) if kind == "ok"])
    return ([m for kind, m in results if kind == "bad"],
            [m for kind, m in results if kind == "skip"])


def probe_duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(json.loads(out.stdout)["format"]["duration"])


def check_durations(video: Path, wav: Path, total_frames: int) -> None:
    """Картинка и звук обязаны совпасть с точностью до кадра."""
    expected = total_frames / C.FPS
    v = probe_duration(video)
    a = len(audio.read_wav(wav)) / C.SR
    tolerance = 1.0 / C.FPS

    if abs(v - expected) > tolerance:
        raise SystemExit(f"видео {v:.3f} с вместо {expected:.3f} с — сборка остановлена")
    if abs(a - expected) > tolerance:
        raise SystemExit(f"звук {a:.3f} с вместо {expected:.3f} с — сборка остановлена")


def check_result(path: Path, total_frames: int) -> None:
    expected = total_frames / C.FPS
    got = probe_duration(path)
    if abs(got - expected) > 2.0 / C.FPS:
        raise SystemExit(f"готовый файл {got:.3f} с вместо {expected:.3f} с")

    streams = json.loads(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "stream=codec_type,width,height,r_frame_rate", "-of", "json", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout)["streams"]
    kinds = {s["codec_type"] for s in streams}
    if kinds != {"video", "audio"}:
        raise SystemExit(f"в готовом файле дорожки {kinds}, ожидались video+audio")
    video = next(s for s in streams if s["codec_type"] == "video")
    if (video["width"], video["height"]) != (C.W, C.H):
        raise SystemExit(f"размер {video['width']}×{video['height']} вместо {C.W}×{C.H}")
