#!/usr/bin/env python3
"""Генерация иллюстраций для статей блога через Nano Banana 2 (Vertex AI).

    python3 tools/blog_admin/gen_images.py            # только недостающие (resume)
    python3 tools/blog_admin/gen_images.py --force k  # перегенерить ключ k

Модель/проект — те же, что в прошлых прогонах рестайла (см. память проекта).
Защиты: атомарное сохранение, resume, ретраи с backoff, стоп-кран по бюджету.
Важно про промты: НИКАКОГО текста на картинке — модели коверкают кириллицу.
"""
import io
import os
import sys
import time

from google import genai
from google.genai import types
from PIL import Image

PROJECT = "project-32adfd18-3dd6-4129-9be"
LOCATION = "global"
# gemini-3.1-flash-image-preview больше не отдаётся проекту (404) — превью-модель
# убрали. Рабочая на 2026-07: gemini-2.5-flash-image (Nano Banana).
MODEL = "gemini-2.5-flash-image"
ASPECT = "16:9"

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BLOG = os.path.join(REPO, "web_landing", "ru", "blog")

MAX_RETRIES = 5
PACE_SECONDS = 8
COST_PER_IMAGE_USD = 0.08
BUDGET_CAP_USD = 2.0

# Общий стилевой хвост: светлая, чистая, «живая» фотография под палитру сайта.
STYLE = (" Photorealistic editorial photograph, natural daylight, bright and airy, "
         "clean modern composition, shallow depth of field, soft neutral background "
         "in light grey-white tones, subtle blue accents. Sharp, high quality, "
         "professional stock-photo look. "
         "CRITICAL: absolutely no text, no letters, no words, no numbers, no writing, "
         "no captions, no watermarks, no logos anywhere in the image.")

IMAGES = {
    # ---- Спринт №6 ----
    "obgon-cover": {
        "path": "obgon-i-operezhenie-pdd/cover.jpg",
        "prompt": (
            "Aerial view of a two-lane road with a dashed white centre line: one car "
            "is moving into the opposite lane to overtake a slower car ahead, a third "
            "car visible further back in its own lane. Bright daylight, clean asphalt, "
            "clear graphic composition showing the overtaking manoeuvre. All cars must "
            "be simple, generic, anonymous car shapes with no resemblance to any real "
            "car manufacturer's design language, grille shape, or badge — no visible "
            "logos or emblems anywhere." + STYLE),
    },
    "manevr-cover": {
        "path": "manevrirovanie-pdd/cover.jpg",
        "prompt": (
            "Top-down aerial view of a car performing a U-turn on an empty road, with "
            "a curved motion-blur light trail showing the turning path. Clean asphalt, "
            "bright daylight, minimal graphic composition, no text or arrows drawn on "
            "the road." + STYLE),
    },
    "ostanovka-cover": {
        "path": "ostanovka-i-stoyanka-pdd/cover.jpg",
        "prompt": (
            "A real standard European 'No Parking' road sign: a round sign with blue "
            "background and a red circle with a single red diagonal line through it, "
            "mounted on a pole beside an empty kerb on a quiet city street. Reproduce "
            "the sign exactly as standardised — do not invent or modify it. Bright, "
            "clean, minimal." + STYLE),
    },
    "bezopasnost-cover": {
        "path": "bezopasnost-i-tehnika-vozhdeniya/cover.jpg",
        "prompt": (
            "Close-up from inside a car of a driver's hands gripping the sides of the "
            "steering wheel at the 9-and-3 position, light rain droplets on the "
            "windshield outside, wipers mid-motion, blurred road ahead. Frame the "
            "shot so the centre hub of the steering wheel is out of frame or fully "
            "hidden behind the hands — no steering wheel badge, emblem, ring, or logo "
            "of any kind should be visible, and no text or lettering anywhere on the "
            "wheel or dashboard." + STYLE),
    },
    "neispravnosti-cover": {
        "path": "neispravnosti-dopusk-ekspluatatsii/cover.jpg",
        "prompt": (
            "A person in casual clothes checking the engine bay of a car with the "
            "hood open, holding a flashlight, focused inspecting expression. Bright "
            "daylight, clean garage or roadside setting, generic unbranded engine "
            "parts, no visible manufacturer logo anywhere." + STYLE),
    },
    "raspolozhenie-cover": {
        "path": "raspolozhenie-tc-na-doroge/cover.jpg",
        "prompt": (
            "Aerial top-down view of a wide multi-lane road with crisp white lane "
            "divider markings, a few cars each driving in their own lane. Fresh dark "
            "asphalt, bright daylight, clean graphic composition emphasising the "
            "painted lane lines." + STYLE),
    },
    "svetovye-cover": {
        "path": "svetovye-pribory-i-signaly/cover.jpg",
        "prompt": (
            "Close-up of a car's front headlight glowing brightly at dusk, warm "
            "golden-blue twilight sky behind, soft bokeh. Generic unbranded car "
            "front end, no visible manufacturer logo or badge anywhere." + STYLE),
    },
    "pervaya-pomosch-cover": {
        "path": "pervaya-pomosch-pri-dtp/cover.jpg",
        "prompt": (
            "An open car first-aid kit box on the passenger seat, showing a roll of "
            "gauze bandage and a few sterile adhesive plasters neatly arranged inside, "
            "calm and procedural, no injury or blood shown. Bright daylight, clean, "
            "reassuring mood." + STYLE),
    },
    "obyazannosti-cover": {
        "path": "obyazannosti-voditeley-pdd/cover.jpg",
        "prompt": (
            "A driver's hand resting on a folded blank paper document on the "
            "passenger seat of a car, sunlight streaming through the windshield. "
            "Calm, orderly mood. The paper must stay completely blank — no readable "
            "text, numbers, or photos on it, and no ID-card or badge shapes anywhere." + STYLE),
    },
    "otvetstvennost-cover": {
        "path": "otvetstvennost-voditelya-pdd/cover.jpg",
        "prompt": (
            "A raised open hand gesturing 'stop' in the foreground with a soft-focus "
            "city street and car headlights blurred behind at dusk. Generic silhouette "
            "gesture, no uniform, no badge, no vehicle branding, no visible text "
            "anywhere in frame." + STYLE),
    },
    "avtomagistral-cover": {
        "path": "avtomagistral-i-zhilaya-zona/cover.jpg",
        "prompt": (
            "A few cars driving at speed along a wide three-lane highway through "
            "green countryside on a sunny day, shot from a bridge overpass looking "
            "down the road. Bright, clean, ordinary daytime traffic photo." + STYLE),
    },
    "zhd-pereezd-cover": {
        "path": "zheleznodorozhnye-perezdy-pdd/cover.jpg",
        "prompt": (
            "A real level railway crossing with black-and-white striped barrier gates "
            "lowered across the road, red warning lights, no train visible, calm "
            "daylight, clean asphalt in the foreground. Reproduce the barrier exactly "
            "as standardised — no invented text or symbols on it." + STYLE),
    },
    "avariynaya-cover": {
        "path": "avariynaya-signalizatsiya-specsignaly/cover.jpg",
        "prompt": (
            "A car pulled over on the road shoulder with its amber hazard lights "
            "visibly blinking, a red-and-white warning triangle placed on the asphalt "
            "behind it. Overcast daylight, generic unbranded car, no visible "
            "manufacturer logo anywhere." + STYLE),
    },
    "buksirovka-cover": {
        "path": "buksirovka-i-perevozka-gruzov/cover.jpg",
        "prompt": (
            "One car towing another car ahead of it via a visible rigid metal tow "
            "bar, driving together along an open road in daylight. Generic unbranded "
            "cars, no visible manufacturer logos anywhere." + STYLE),
    },
    "prioritet-transport-cover": {
        "path": "prioritet-obschestvennogo-transporta/cover.jpg",
        "prompt": (
            "A city bus stopped at a bus stop with a few passengers waiting on the "
            "pavement beside it, a car waiting patiently behind the bus on the road. "
            "Bright daylight, clean street, generic unbranded bus with no readable "
            "route text or logos." + STYLE),
    },
    "uchebnaya-ezda-cover": {
        "path": "uchebnaya-ezda-i-velosipedisty/cover.jpg",
        "prompt": (
            "A generic unbranded car with a plain yellow triangular 'student driver' "
            "placard mounted on its rear window (a solid yellow triangle shape only, "
            "no letters or symbols on it) driving on a quiet street, a cyclist riding "
            "in a marked bike lane alongside in the same frame. Bright daylight, "
            "clean, calm. No visible manufacturer logo, badge, or emblem anywhere on "
            "the car." + STYLE),
    },
    # ---- Спринт №5 ----
    "peresdacha-cover": {
        "path": "peresdacha-teorii-pdd/cover.jpg",
        "prompt": (
            "A calm young man sitting on a bench in a bright waiting area of a "
            "government service office, looking at a smartphone with a light, "
            "hopeful expression, a wall calendar-style clock softly blurred in the "
            "background. Clean modern interior, neutral colours, second-chance "
            "optimistic mood rather than stressful." + STYLE),
    },
    "skorost-cover": {
        "path": "skorostnye-rezhimy-pdd/cover.jpg",
        "prompt": (
            "A real standard European road speed-limit sign: a round white sign "
            "with a thick red border and the black number '90' in the centre, "
            "mounted on a metal pole against a clear sky with a blurred straight "
            "open road behind it. Reproduce the sign exactly as standardised — do "
            "not invent or modify its shape or colours. Sharp, bright, minimal." + STYLE),
    },
    # ---- Спринт №4 ----
    "slozhnye-temy-cover": {
        "path": "slozhnye-temy-bileotv-pdd/cover.jpg",
        "prompt": (
            "Close-up of a person's hands sorting a small stack of paper flashcards on a "
            "wooden desk, one card held up for closer inspection, a slightly puzzled but "
            "focused expression suggested by posture. Soft daylight from a window, "
            "notebook and pen nearby, calm study atmosphere. The flashcards must stay "
            "blank — no readable text." + STYLE),
    },
    "podgotovka-nedelya-cover": {
        "path": "podgotovka-za-nedelyu-pdd/cover.jpg",
        "prompt": (
            "A focused young person at a home desk checking off items with a pen on a "
            "plain blank paper checklist with a few empty checkbox squares down the left "
            "edge and simple horizontal lines, no headers, no grid, no calendar, no day "
            "names. A smartphone and a cup of tea beside the paper, warm morning light "
            "from a window. The paper must show ONLY empty checkbox squares and blank "
            "lines — absolutely no letters, no words, no numbers anywhere on it or in the "
            "scene." + STYLE),
    },
    # ---- Спринт №3 ----
    "prakt-ekzamen-cover": {
        "path": "prakticheskiy-ekzamen-gibdd/cover.jpg",
        "prompt": (
            "Interior view from the back seat of a car during a driving test: a calm "
            "driving examiner in the front passenger seat holding a clipboard, looking "
            "ahead through the windshield at a city street with an intersection, a "
            "learner driver's hands visible on the steering wheel. Bright daylight, "
            "clean modern car interior, generic unbranded steering wheel and dashboard "
            "with no visible manufacturer logo, badge, or emblem anywhere." + STYLE),
    },
    "perekrestok-cover": {
        "path": "proezd-perekrestkov-pdd/cover.jpg",
        "prompt": (
            "An aerial drone view straight down on a clean four-way city road "
            "intersection with white lane markings and a few cars positioned at the "
            "crossing, waiting or crossing. Bright daylight, sharp, minimal, no traffic "
            "lights or signs prominent in frame — just the crossroads shape and cars." + STYLE),
    },
    # ---- Спринт №2 ----
    "svetofor-cover": {
        "path": "signaly-svetofora-regulirovshchik/cover.jpg",
        "prompt": (
            "A standard three-section traffic light on a pole against a clear blue sky, "
            "the green light glowing, city street softly blurred behind. Clean, bright, "
            "shot from slightly below. Ordinary round red-yellow-green traffic signal, "
            "nothing unusual." + STYLE),
    },
    "medspravka-cover": {
        "path": "medspravka-voditelskaya-2026/cover.jpg",
        "prompt": (
            "A friendly doctor in a white coat with a stethoscope sitting at a desk in a "
            "bright modern clinic, an eye-test chart softly blurred on the wall behind, "
            "a blank clipboard and pen on the desk. Warm, clean, reassuring medical office. "
            "The eye chart and any papers must stay blank — no readable letters." + STYLE),
    },
    # ---- Статья 1: как сдать теорию ----
    "exam-cover": {
        "path": "kak-sdat-teoriyu-pdd-2026/cover.jpg",
        "prompt": (
            "A calm young woman in her early twenties sitting at a computer workstation "
            "in a bright modern testing room, taking a written driving theory test on the "
            "monitor. Seen from a three-quarter angle slightly behind her shoulder, "
            "screen glow on her focused face, other empty workstations blurred in the "
            "background. Neutral light grey office interior." + STYLE),
    },
    "exam-day": {
        "path": "kak-sdat-teoriyu-pdd-2026/exam-day.jpg",
        "prompt": (
            "Close-up of a person's hands resting on a desk next to a passport-sized "
            "document folder and a set of car keys, waiting before an exam. A simple "
            "round wall clock softly out of focus in the background. Bright, minimal, "
            "calm morning light." + STYLE),
    },
    # ---- Статья 2: как быстро выучить билеты ----
    "study-cover": {
        "path": "kak-bystro-vyuchit-bilety-pdd/cover.jpg",
        "prompt": (
            "A young man sitting at a light wooden desk at home, studying on a smartphone "
            "held in one hand, a notebook and a cup of coffee beside him. Relaxed focused "
            "expression, warm daylight from a window, plant and bookshelf softly blurred "
            "behind. Modern minimal interior." + STYLE),
    },
    "signs": {
        "path": "kak-bystro-vyuchit-bilety-pdd/signs.jpg",
        # Знаки должны быть РЕАЛЬНЫМИ (сайт про ПДД): выдуманный знак = дезинформация.
        # Берём три предельно узнаваемых знака Венской конвенции, разных по форме.
        "prompt": (
            "Three real standard European road signs mounted on clean metal poles against "
            "a clear blue sky, side by side. Left: a white triangular sign with a thick red "
            "border containing a single black exclamation mark. Middle: a round sign with a "
            "solid red background and one wide white horizontal bar across its centre (the "
            "standard international 'no entry' sign). Right: a round sign with a solid blue "
            "background and a single white arrow curving to the right. Reproduce these three "
            "signs exactly as they are standardised — do not invent or modify any symbol. "
            "Shot from slightly below, crisp and colourful." + STYLE),
    },
    # ---- Статья 3: дорожные знаки ----
    "znaki-cover": {
        "path": "dorozhnye-znaki-2026/cover.jpg",
        "prompt": (
            "Two real standard European road signs on one metal post against a bright sky "
            "with soft clouds, city buildings softly blurred behind: on top a triangular "
            "sign with a thick red border and a black walking-pedestrian pictogram "
            "(standard pedestrian warning sign), below it a round sign with solid blue "
            "background and a single straight white arrow pointing up (standard 'straight "
            "ahead only' mandatory sign). Reproduce these signs exactly as standardised — "
            "do not invent, add or modify any symbol. No other signs." + STYLE),
    },
    # ---- Статья 4: дорожная разметка ----
    "razmetka-cover": {
        "path": "dorozhnaya-razmetka-2026/cover.jpg",
        "prompt": (
            "Top-down aerial view of a clean asphalt road with crisp white road markings: "
            "a solid centre line transitioning into a dashed line, a zebra pedestrian "
            "crossing, and directional arrows painted on the lanes. One red car driving in "
            "its lane. Fresh dark asphalt, bright daylight, graphic and geometric "
            "composition." + STYLE),
    },
    # ---- Статья 5: как получить права ----
    "prava-cover": {
        "path": "kak-poluchit-voditelskie-prava/cover.jpg",
        "prompt": (
            "A happy young woman sitting in the driver's seat of a modern car with the "
            "door open, holding up a car key with a small key fob, smiling. Driving school "
            "instructor standing beside the car softly blurred. Sunny day, fresh and "
            "optimistic mood." + STYLE),
    },
}


def crop_to(im, tw, th):
    """Вписать по короткой стороне и обрезать по центру."""
    sw, sh = im.size
    s = max(tw / sw, th / sh)
    nw, nh = max(tw, int(round(sw * s))), max(th, int(round(sh * s)))
    im = im.resize((nw, nh), Image.LANCZOS)
    l, t = (nw - tw) // 2, (nh - th) // 2
    return im.crop((l, t, l + tw, t + th))


def generate(client, prompt):
    delay = 20
    last = None
    for attempt in range(MAX_RETRIES):
        try:
            r = client.models.generate_content(
                model=MODEL, contents=[prompt],
                config=types.GenerateContentConfig(
                    response_modalities=["TEXT", "IMAGE"],
                    image_config=types.ImageConfig(aspect_ratio=ASPECT),
                    temperature=0.8),
            )
            return r
        except Exception as e:  # noqa: BLE001
            last = (str(e) + " " + type(e).__name__).lower()
            retriable = any(s in last for s in (
                "429", "resource_exhausted", "500", "503", "unavailable", "deadline",
                "timeout", "timed out", "connection", "reset", "servererror", "temporarily"))
            if retriable and attempt < MAX_RETRIES - 1:
                print("   retry in %ds (%s)" % (delay, last[:60]), flush=True)
                time.sleep(delay)
                delay = min(int(delay * 1.6), 120)
                continue
            raise
    raise RuntimeError("retries exhausted: %s" % last)


def main():
    force = set()
    if "--force" in sys.argv:
        force = set(sys.argv[sys.argv.index("--force") + 1:])

    client = genai.Client(vertexai=True, project=PROJECT, location=LOCATION,
                          http_options=types.HttpOptions(timeout=180000))
    spent = 0.0
    made = failed = 0

    for key, spec in IMAGES.items():
        out = os.path.join(BLOG, spec["path"])
        if os.path.exists(out) and os.path.getsize(out) > 0 and key not in force:
            print("skip (есть): %s" % spec["path"], flush=True)
            continue
        if spent + COST_PER_IMAGE_USD > BUDGET_CAP_USD:
            print("БЮДЖЕТ-СТОП на ~$%.2f (лимит $%.2f)" % (spent, BUDGET_CAP_USD), flush=True)
            break

        print("gen %-12s → %s" % (key, spec["path"]), flush=True)
        try:
            r = generate(client, spec["prompt"])
            if not r.candidates:
                br = getattr(getattr(r, "prompt_feedback", None), "block_reason", None)
                print("   BLOCKED: %s" % br, flush=True)
                failed += 1
                time.sleep(PACE_SECONDS)
                continue
            ib = next((p.inline_data.data for p in (r.candidates[0].content.parts or [])
                       if p.inline_data and p.inline_data.data), None)
            if not ib:
                print("   нет картинки в ответе", flush=True)
                failed += 1
                time.sleep(PACE_SECONDS)
                continue

            im = Image.open(io.BytesIO(ib)).convert("RGB")
            im = crop_to(im, 1200, 630)  # ровно под OG-формат
            os.makedirs(os.path.dirname(out), exist_ok=True)
            tmp = out + ".part"
            im.save(tmp, "JPEG", quality=86, optimize=True, progressive=True)
            os.replace(tmp, out)  # атомарно
            spent += COST_PER_IMAGE_USD
            made += 1
            print("   ok %s (%.0f КБ)" % (im.size, os.path.getsize(out) / 1024), flush=True)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("   ОШИБКА: %s" % e, flush=True)
        time.sleep(PACE_SECONDS)

    print("\nготово: %d создано, %d ошибок, ~$%.2f" % (made, failed, spent), flush=True)


if __name__ == "__main__":
    main()
