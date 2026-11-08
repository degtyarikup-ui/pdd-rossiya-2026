"""Builds assets/audio/swipe.wav: the soft whoosh of a sign card leaving the deck
in «Это знак». Band-passed noise whose centre glides down while it fades —
quiet, short, no tone. Reproducible (fixed seed):

    python3 tools/audio/make_swipe_sound.py
"""
import math
import wave
from pathlib import Path

import numpy as np

RATE = 44100
LENGTH = 0.24  # seconds
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "swipe.wav"


def bandpass(signal, centres, q):
    """RBJ band-pass (0 dB peak) with a per-sample centre frequency."""
    out = np.zeros_like(signal)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(signal):
        w0 = 2 * math.pi * centres[i] / RATE
        alpha = math.sin(w0) / (2 * q)
        a0 = 1 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2 * math.cos(w0) / a0, (1 - alpha) / a0
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x
        y2, y1 = y1, y
        out[i] = y
    return out


def main():
    rng = np.random.default_rng(20261103)
    n = int(RATE * LENGTH)
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n)
    # The air moves fast at first, then lower as the card slows into the side.
    glide = (t / LENGTH) ** 0.7
    centres = 1900 * (1 - glide) + 520 * glide
    # Two passes give gentle 12 dB/octave skirts: air, not hiss.
    swish = bandpass(bandpass(noise, centres, q=0.9), centres, q=0.9)
    body = bandpass(noise, np.full(n, 380.0), q=0.7) * 0.25
    sound = swish + body
    attack = 0.02
    envelope = np.where(
        t < attack,
        0.5 - 0.5 * np.cos(math.pi * t / attack),
        (1 - (t - attack) / (LENGTH - attack)).clip(0, 1) ** 2.2,
    )
    sound *= envelope
    sound /= np.max(np.abs(sound))
    sound *= 10 ** (-6 / 20)  # −6 dBFS peak; the app plays it quietly on top.
    pcm = (sound * 32767).astype("<i2")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{OUT} {n / RATE:.3f} s")


if __name__ == "__main__":
    main()
