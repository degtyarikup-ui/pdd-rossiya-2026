#!/usr/bin/env python3
"""Звук ролика: голос диктора (Gemini TTS), тиканье и сборка дорожек.

Дорожек две — голос и тиканье, музыки нет (решение по формату).
Собираем всё в numpy на частоте `config.SR`, потому что так дорожка
получается ровно той длины, что и видео: ffmpeg-фильтры с adelay копят
ошибку округления, и к концу ролика голос уезжает от картинки.
"""

from __future__ import annotations

import hashlib
import subprocess
import wave
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import config as C


# ── Примитивы ──────────────────────────────────────────────────────────────

def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(round(seconds * C.SR)), dtype=np.float32)


def read_wav(path: Path) -> np.ndarray:
    """Читает WAV в моно float32 на C.SR, при необходимости пересэмплируя."""
    with wave.open(str(path), "rb") as w:
        n_channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())

    if sampwidth != 2:
        raise ValueError(f"{path.name}: ожидается 16-bit PCM, получено {sampwidth * 8}-bit")

    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if n_channels > 1:
        data = data.reshape(-1, n_channels).mean(axis=1)

    if rate != C.SR:
        n_out = int(round(len(data) * C.SR / rate))
        data = np.interp(
            np.linspace(0.0, len(data) - 1, n_out, dtype=np.float64),
            np.arange(len(data), dtype=np.float64),
            data.astype(np.float64),
        ).astype(np.float32)
    return data


def write_wav(path: Path, data: np.ndarray) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(data, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(C.SR)
        w.writeframes(pcm.tobytes())
    return path


def trim_silence(data: np.ndarray, threshold: float = 0.006, pad: float = 0.05) -> np.ndarray:
    """Срезает тишину по краям клипа TTS.

    Синтез отдаёт клип с разным по длине «дыханием» в начале и в конце;
    без обрезки паузы между фразами гуляют на полсекунды.
    """
    if data.size == 0:
        return data
    loud = np.abs(data) > threshold
    if not loud.any():
        return data
    first, last = int(np.argmax(loud)), int(len(loud) - np.argmax(loud[::-1]))
    pad_n = int(pad * C.SR)
    return data[max(0, first - pad_n):min(len(data), last + pad_n)]


# ── Тиканье ────────────────────────────────────────────────────────────────

def tick_click(freq: float) -> np.ndarray:
    """Один щелчок: синус, придавленный экспонентой."""
    n = int(C.TICK_LEN * C.SR)
    t = np.arange(n, dtype=np.float32) / C.SR
    env = np.exp(-t / C.TICK_DECAY)
    return (np.sin(2 * np.pi * freq * t) * env * C.TICK_GAIN).astype(np.float32)


def tick_track(duration: float) -> np.ndarray:
    """Дорожка «тик-так» на время отсчёта: чередование 1400 и 1100 Гц."""
    out = silence(duration)
    hi, lo = tick_click(C.TICK_FREQ_HI), tick_click(C.TICK_FREQ_LO)
    i = 0
    t = 0.0
    while t < duration:
        click = hi if i % 2 == 0 else lo
        start = int(round(t * C.SR))
        end = min(len(out), start + len(click))
        if end > start:
            out[start:end] += click[: end - start]
        i += 1
        t += C.TICK_PERIOD
    return out


def reveal_chime() -> np.ndarray:
    """Мягкий двухтоновый «дзынь» в момент раскрытия ответа."""
    dur = 0.32
    n = int(dur * C.SR)
    t = np.arange(n, dtype=np.float32) / C.SR
    env = np.exp(-t / 0.09)
    tone = np.sin(2 * np.pi * 880.0 * t) + 0.6 * np.sin(2 * np.pi * 1318.5 * t)
    return (tone * env * C.CHIME_GAIN / 1.6).astype(np.float32)


# ── TTS ────────────────────────────────────────────────────────────────────

def default_project() -> str:
    """Проект берём из ADC, а не хардкодим.

    Захардкоженный проект — ровно та поломка, из-за которой пайплайн однажды
    встал с 403: учётные данные пересоздали под другой проект, а константа
    в коде осталась прежней.
    """
    import os

    for env in ("GOOGLE_CLOUD_PROJECT", "VERTEX_PROJECT"):
        if os.environ.get(env):
            return os.environ[env]
    adc = Path.home() / ".config" / "gcloud" / "application_default_credentials.json"
    if adc.exists():
        import json

        project = json.loads(adc.read_text()).get("quota_project_id")
        if project:
            return project
    raise SystemExit(
        "не найден проект Google Cloud: задайте GOOGLE_CLOUD_PROJECT "
        "или выполните `gcloud auth application-default login`"
    )


@dataclass
class VoiceConfig:
    voice: str = "Charon"
    style: str = (
        "Читай спокойно и уверенно, как диктор обучающего ролика о правилах "
        "дорожного движения. Ровный темп, без наигранной бодрости. "
        "Произноси только заданный текст, ничего не добавляй."
    )
    model: str = "gemini-3.1-flash-tts-preview"
    project: str = field(default_factory=default_project)
    location: str = "global"


def tts_cache_key(text: str, vc: VoiceConfig) -> str:
    payload = f"{vc.model}|{vc.voice}|{vc.style}|{text}"
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:16]


def synthesize(text: str, out_path: Path, vc: VoiceConfig, attempts: int = 6) -> Path:
    """Синтезирует реплику в WAV 24 кГц моно. Кэш — по хэшу текста и голоса."""
    if out_path.exists() and out_path.stat().st_size > 1000:
        return out_path

    import time

    from google import genai
    from google.genai import types

    client = genai.Client(vertexai=True, project=vc.project, location=vc.location)
    prompt = f"{vc.style}\n\nТекст: {text}" if vc.style else text

    response = None
    for attempt in range(attempts):
        try:
            response = client.models.generate_content(
                model=vc.model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"],
                    speech_config=types.SpeechConfig(
                        voice_config=types.VoiceConfig(
                            prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=vc.voice)
                        )
                    ),
                ),
            )
            break
        except Exception as exc:
            # 429 и 500 на Vertex — обычная транзиентная история, ждём и повторяем.
            transient = any(code in str(exc) for code in ("429", "RESOURCE_EXHAUSTED", "500", "INTERNAL", "503"))
            if not transient or attempt == attempts - 1:
                raise
            time.sleep(2 ** attempt)

    if response is None:
        raise RuntimeError(f"озвучка не получена: {text[:40]}")

    # Модель отдаёт СЫРОЙ PCM (audio/l16), а не WAV: записать эти байты в .wav
    # напрямую — получить мусор. Частоту берём из mime, а не предполагаем.
    part = response.candidates[0].content.parts[0]
    mime = part.inline_data.mime_type or ""
    rate = int(mime.split("rate=")[1].split(";")[0]) if "rate=" in mime else C.SR
    pcm = np.frombuffer(part.inline_data.data, dtype="<i2").astype(np.float32) / 32768.0

    if rate != C.SR:
        n_out = int(round(len(pcm) * C.SR / rate))
        pcm = np.interp(
            np.linspace(0.0, len(pcm) - 1, n_out, dtype=np.float64),
            np.arange(len(pcm), dtype=np.float64),
            pcm.astype(np.float64),
        ).astype(np.float32)

    write_wav(out_path, pcm)
    return out_path


# ── Сведение ───────────────────────────────────────────────────────────────

def mix(tracks: list[tuple[float, np.ndarray]], total_seconds: float) -> np.ndarray:
    """Складывает дорожки по абсолютным позициям в общий буфер.

    Буфер создаётся под точную длину видео: подмешать что-то за его границей
    нельзя — такой клип молча обрезался бы при склейке.
    """
    out = silence(total_seconds)
    for at, data in tracks:
        start = int(round(at * C.SR))
        if start >= len(out):
            continue
        end = min(len(out), start + len(data))
        out[start:end] += data[: end - start]

    peak = float(np.max(np.abs(out))) if out.size else 0.0
    if peak > 0.99:
        out *= 0.99 / peak
    return out


def mux(video: Path, audio: Path, out: Path) -> Path:
    """Склеивает видео и звук. Без -shortest: длины уже сверены на входе."""
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-y", "-v", "error",
            "-i", str(video),
            "-i", str(audio),
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
            str(out),
        ],
        check=True,
    )
    return out
