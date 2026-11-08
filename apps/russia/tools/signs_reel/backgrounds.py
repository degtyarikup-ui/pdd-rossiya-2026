#!/usr/bin/env python3
"""Фоны для роликов: сюрреалистичные сцены с дорожными знаками.

Генерятся один раз (Nano Banana Pro) и потом просто лежат в репозитории —
каждый выпуск берёт свой фон, чтобы лента не выглядела одинаковой.

    python3 -m tools.signs_reel.backgrounds          # догенерить недостающие
    python3 -m tools.signs_reel.backgrounds --force  # перегенерить все

На фоне — узнаваемые российские знаки, но нарисованные нейросетью, поэтому
фон остаётся **только декорацией**: мелкие неточности в нём возможны и на
обучение не влияют. Знаки, которые ролик действительно загадывает, берутся
исключительно из `assets/countries/*/images/signs/`.
"""

from __future__ import annotations

import hashlib
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

DIR = Path(__file__).resolve().parent / "backgrounds"
# Сначала пробуем старшую модель, при 429 откатываемся на быструю: фон
# декоративный, ждать освободившуюся квоту ради него не стоит.
MODELS = ["gemini-3-pro-image", "gemini-2.5-flash-image"]

COMMON = (
    "Vertical 9:16 photograph, cinematic, high detail, sharp, rich colour. "
    "Show real, instantly recognisable RUSSIAN (GOST) road signs: the red "
    "circle with a white horizontal bar (no entry), the blue square with a "
    "white pedestrian on a crossing, the yellow diamond with white border "
    "(priority road), red-bordered white circles with speed limits like 40, "
    "60, 20, the red octagonal STOP sign, the red-bordered white triangle with "
    "an exclamation mark, the blue circle with a white arrow, the blue square "
    "with a white P. Signs are clean and correctly drawn, no invented symbols, "
    "no Cyrillic paragraphs of text beyond the word STOP. Composition leaves "
    "the middle of the frame calmer than the edges, so an interface card can "
    "sit on top."
)

SCENES = {
    "tower": "An absurdly tall pole carrying dozens of Russian road signs stacked on top of each other like a totem, shot from below against a dramatic evening sky.",
    "forest": "A dense forest of road-sign poles growing out of asphalt like trees, Russian sign faces at every height, morning fog, wide angle.",
    "meadow": "Russian road signs growing out of a summer meadow like giant flowers on thin stems, soft dawn light, dew, shallow depth of field.",
    "wall": "A brutalist concrete wall completely tiled with Russian road signs of every shape, flat frontal light, strong graphic pattern.",
    "float": "Russian road signs floating weightless in the air in a studio with a smooth grey gradient background, poles detached, subtle shadows.",
    "giant": "One enormous Russian no-entry sign leaning over a tiny empty country road, extreme scale contrast, long shadows at golden hour.",
    "scrapyard": "A scrapyard stacked with hundreds of dented Russian road signs leaning against each other, warm rusty light, gritty texture.",
    "spiral": "Russian road signs arranged in a spiral tunnel receding into the distance, hypnotic perspective, cool blue light.",
    "sea": "Russian road signs standing in shallow sea water at sunset, poles reflected in still water, surreal and calm.",
    "snow": "Russian road signs buried up to their middles in deep snow in an empty field, overcast winter light, muted palette.",
    "night_rain": "Russian road signs at a wet night crossroads, neon reflections on black asphalt, rain streaks, cinematic.",
    "garage": "Russian road signs stacked floor to ceiling inside a cluttered concrete garage, single bare lamp, deep shadows.",
    "dunes": "Russian road signs half buried in golden sand dunes under a hard midday sun, long sharp shadows.",
    "carousel": "Russian road signs mounted on a fairground carousel instead of horses, motion blur at the edges, evening lights.",
    "shelf": "Russian road signs stored upright on tall warehouse shelving like books in a library, symmetrical perspective.",
    "crane": "One giant Russian road sign lifted by a construction crane above an empty city square, overcast sky, extreme scale.",
    "rooftop": "Russian road signs installed in rows on a city rooftop against a skyline at blue hour.",
    "puddle": "Russian road signs reflected in a huge still puddle after rain, upside-down reflection fills the lower half.",
    "bridge_fog": "Russian road signs lining a long bridge swallowed by thick fog, receding into white, cold light.",
    "autumn": "Russian road signs among swirling autumn leaves in a park alley, warm golden light, shallow depth of field.",
    "market": "Russian road signs leaning in stacks at a flea market stall, crowded and colourful, overcast daylight.",
    "ice": "Russian road signs frozen inside thick blue ice, cracks and bubbles in the ice, cold studio light.",
    "sunflowers": "Russian road signs standing in a vast sunflower field at sunrise, signs taller than the flowers.",
    "tunnel": "Russian road signs mounted along the walls of a long road tunnel, orange sodium light streaks, strong perspective.",
    "stairs": "Russian road signs standing on every step of a long outdoor concrete staircase, low sun, graphic shadows.",
    "balloons": "Russian road signs hanging from colourful helium balloons floating in a clear blue sky, surreal and light.",
    "domino": "Russian road signs standing in a long curving line like dominoes mid-fall, studio floor, dramatic side light.",
    "pyramid": "Russian road signs stacked into a tall pyramid on an empty parking lot, symmetrical, hard afternoon light.",
    "windshield": "Russian road signs seen through a rain-covered windshield from inside a car, bokeh droplets, evening city light.",
    "neon": "Russian road signs floating in a dark studio lit by magenta and cyan neon tubes, glossy reflections, high contrast.",
}


def path_for(name: str) -> Path:
    return DIR / f"{name}.png"


def generate(name: str, force: bool = False) -> Path:
    out = path_for(name)
    if out.exists() and not force:
        return out

    import time

    from google import genai
    from google.genai import types

    from .audio import default_project

    DIR.mkdir(parents=True, exist_ok=True)
    client = genai.Client(vertexai=True, project=default_project(), location="global")
    prompt = f"{SCENES[name]} {COMMON}"
    last_error = None

    for model in MODELS:
        for attempt in range(3):
            try:
                response = client.models.generate_content(
                    model=model,
                    contents=[types.Content(role="user", parts=[types.Part(text=prompt)])],
                    config=types.GenerateContentConfig(
                        response_modalities=["TEXT", "IMAGE"],
                        image_config=types.ImageConfig(aspect_ratio="9:16"),
                    ),
                )
                for part in response.candidates[0].content.parts:
                    if part.inline_data and part.inline_data.data:
                        out.write_bytes(part.inline_data.data)
                        return out
                last_error = "модель вернула ответ без картинки"
                break
            except Exception as exc:
                last_error = exc
                if not any(c in str(exc) for c in ("429", "RESOURCE_EXHAUSTED", "500", "INTERNAL", "503")):
                    break  # модели нет в проекте — пробуем следующую
                time.sleep(2 ** attempt)

    raise RuntimeError(f"фон «{name}» не сгенерился: {str(last_error)[:120]}")


def available() -> list[Path]:
    return sorted(p for p in DIR.glob("*.png")) if DIR.exists() else []


def load(name: str):
    """Загружает конкретный фон по имени сцены."""
    from PIL import Image

    path = path_for(name)
    if not path.exists():
        raise SystemExit(f"нет фона «{name}»: {path}")
    return Image.open(path).convert("RGB")


def pick(seed: str):
    """Выбирает фон по выпуску: один и тот же выпуск — всегда один фон."""
    from PIL import Image

    files = available()
    if not files:
        return None
    index = int(hashlib.sha1(seed.encode("utf-8")).hexdigest(), 16) % len(files)
    return Image.open(files[index]).convert("RGB")


if __name__ == "__main__":
    force = "--force" in sys.argv
    for name in SCENES:
        try:
            print(f"{name:>10}: {generate(name, force)}")
        except Exception as exc:
            print(f"{name:>10}: ОШИБКА {str(exc)[:120]}")
