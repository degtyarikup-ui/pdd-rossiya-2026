#!/usr/bin/env python3
"""End-to-end YouTube Shorts / TikTok pipeline for a single PDD question.

Pilot config: Ticket 1, Question 1 ("вынужденная остановка").

Pipeline:
  1. Nano Banana Pro       -> scene image (9:16)
  2. Veo 3.1 Lite          -> 8s animated clip (image-to-video)
  3. Gemini 3.1 Flash TTS  -> 4 voice tracks (hook / question / answer / cta) in parallel
  4. ffmpeg + Pillow       -> assemble 22s vertical Short with overlays

Output: assets/videos/SHORT_<slug>.mp4
"""

import os
import sys
import time
import subprocess
import warnings
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

warnings.filterwarnings("ignore")

SCRIPTS_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPTS_DIR))

from nanobanana_generate import generate_image as nb_generate
from veo_generate import generate_video as veo_generate
from tts_generate import generate_speech as tts_generate

from PIL import Image, ImageDraw, ImageFont

ASSETS = Path(__file__).parent.parent / "assets" / "videos"
ASSETS.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# SHORT CONFIG — Ticket 1 / Question 1
# ---------------------------------------------------------------------------

SLUG = "ticket1_q1_forced_stop"

QUESTION = "В каком случае водитель совершит\nвынужденную остановку?"
OPTIONS = [
    "Перед пешеходным переходом,\nчтобы уступить пешеходу",
    "Из-за технической неисправности\nавтомобиля",
    "В обоих перечисленных случаях",
]
CORRECT_IDX = 1  # 0-based

# Texts for TTS — short, clear, conversational tone
TTS_HOOK_TEXT = "Сможешь ответить за пять секунд? Билет один, вопрос один."
TTS_QUESTION_TEXT = "В каком случае водитель совершит вынужденную остановку?"
TTS_ANSWER_TEXT = (
    "Правильный ответ — второй. "
    "Вынужденная остановка — это прекращение движения из-за неисправности, "
    "опасного груза, состояния водителя или препятствия на дороге. "
    "Остановка перед пешеходом — это обычная плановая остановка."
)
TTS_CTA_TEXT = "Подписывайся. Каждый день — новый билет ПДД."

# Banner shown over the green-highlighted answer
ANSWER_BANNER_TITLE = "ПРАВИЛЬНЫЙ ОТВЕТ"
ANSWER_BANNER_SUB = "Техническая неисправность"

# Image / Video prompts (English — Veo handles English best)
NB_PROMPT = (
    "A realistic cinematic photograph in 9:16 vertical orientation. "
    "A small dark-grey generic sedan stopped on the right paved shoulder of a two-lane asphalt road, "
    "front hood lifted halfway, amber hazard lights glowing on both sides of the car. "
    "A red triangular warning sign placed on the road about 15 meters behind the car. "
    "Overcast daytime, soft diffused light, slight light haze in the air. "
    "No brand logos, no license plate text, no people, no overlays, no HUD, no GPS, no timestamp. "
    "Mid-shot framing, the road extends into the background with empty lanes. "
    "Photorealistic style, sharp focus on the car."
)

VEO_PROMPT = (
    "Static cinematic vertical shot. The sedan remains stopped on the shoulder with hood lifted. "
    "Amber hazard lights gently blink on and off. A faint wisp of steam rises slowly from the engine bay. "
    "Very slow camera dolly forward, barely perceptible. "
    "A single distant car passes on the far lane in the background. "
    "Overcast daylight, realistic colors. Subtle ambient motion only. "
    "No on-screen text, no HUD, no timestamps, no GPS overlay, no brand logos."
)

VEO_NEGATIVE = "rain, snow, night, dark, brand logos, license plate text, people, pedestrians, HUD, GPS, timestamp, overlay, text"

# Asset paths
P_SCENE = ASSETS / f"_short_{SLUG}_scene.png"
P_VEO = ASSETS / f"_short_{SLUG}_veo.mp4"
P_TTS_HOOK = ASSETS / f"_short_{SLUG}_tts_hook.wav"
P_TTS_Q = ASSETS / f"_short_{SLUG}_tts_question.wav"
P_TTS_A = ASSETS / f"_short_{SLUG}_tts_answer.wav"
P_TTS_CTA = ASSETS / f"_short_{SLUG}_tts_cta.wav"
P_FINAL = ASSETS / f"SHORT_{SLUG}.mp4"

# ---------------------------------------------------------------------------
# COMPOSITION — adapted from quiz_compose.py
# ---------------------------------------------------------------------------

OUT_W, OUT_H = 1080, 1920
FPS = 30
FONT_BOLD = "/Users/sergei/Library/Fonts/helvetica_bold.otf"

# Timeline (seconds)
T_HOOK_START = 0.0
T_HOOK_END = 2.5
T_QUESTION = 2.7
T_TIMER_START = 5.5
T_TIMER_END = 10.5     # 5s countdown
T_ANSWER_START = 10.5
T_ANSWER_END = 19.0
T_CTA_START = 19.0
TOTAL = 22.0

# Colors
WHITE = (255, 255, 255, 255)
YELLOW = (255, 216, 61, 255)
GREEN = (74, 222, 128, 255)
GREEN_BG = (32, 130, 70, 240)
RED = (239, 68, 68, 255)
DIM = (160, 160, 160, 200)
BLACK_85 = (0, 0, 0, 220)


def run(cmd):
    """Run an ffmpeg command, print compact log, raise on error."""
    print(f"$ {' '.join(str(c) for c in cmd[:6])} ... ({len(cmd)} args)")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("STDERR:", res.stderr[-2500:])
        raise subprocess.CalledProcessError(res.returncode, cmd)


def font(size):
    return ImageFont.truetype(FONT_BOLD, size)


def text_size(d, text, fnt):
    bbox = d.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def wrap_text(text, fnt, max_w, d):
    """Word-wrap; preserves explicit \\n line breaks."""
    out = []
    for raw_line in text.split("\n"):
        words, cur = raw_line.split(), []
        for w in words:
            test = " ".join(cur + [w])
            if text_size(d, test, fnt)[0] <= max_w or not cur:
                cur.append(w)
            else:
                out.append(" ".join(cur))
                cur = [w]
        if cur:
            out.append(" ".join(cur))
        elif not words:
            out.append("")
    return out


def render_hook_card(out_path):
    img = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, OUT_W, OUT_H], fill=(0, 0, 0, 200))
    f1 = font(70)
    f2 = font(140)
    f3 = font(50)
    line1 = "СМОЖЕШЬ ОТВЕТИТЬ"
    line2 = "ЗА 5 СЕКУНД?"
    line3 = "Билет 1 — Вопрос 1"
    tw, _ = text_size(d, line1, f1)
    d.text(((OUT_W - tw) // 2, 760), line1, font=f1, fill=WHITE)
    tw, _ = text_size(d, line2, f2)
    d.text(((OUT_W - tw) // 2, 850), line2, font=f2, fill=YELLOW)
    tw, _ = text_size(d, line3, f3)
    d.text(((OUT_W - tw) // 2, 1020), line3, font=f3, fill=WHITE)
    img.save(out_path)
    return out_path


def render_question_options_block(out_path, highlight_idx=-1, dim_others=False):
    pad_x = 50
    q_font = font(50)
    opt_font = font(38)
    num_font = font(34)

    tmp = Image.new("RGBA", (1, 1))
    d = ImageDraw.Draw(tmp)

    q_lines = wrap_text(QUESTION, q_font, OUT_W - 2 * pad_x, d)
    q_line_h = text_size(d, "Ay", q_font)[1] + 8

    opt_meta = []
    opt_text_max_w = OUT_W - 2 * pad_x - 80
    for txt in OPTIONS:
        lines = wrap_text(txt, opt_font, opt_text_max_w, d)
        line_h = text_size(d, "Ay", opt_font)[1] + 4
        opt_meta.append((lines, line_h, line_h * len(lines) + 32))

    pad_y_top = 50
    q_opt_gap = 36
    opt_gap = 14
    block_h = (pad_y_top + q_line_h * len(q_lines) + q_opt_gap
               + sum(m[2] for m in opt_meta) + opt_gap * (len(OPTIONS) - 1) + 50)

    img = Image.new("RGBA", (OUT_W, block_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, OUT_W, block_h], fill=BLACK_85)
    d.rectangle([0, block_h - 4, OUT_W, block_h], fill=YELLOW)

    y = pad_y_top
    for line in q_lines:
        tw, _ = text_size(d, line, q_font)
        d.text(((OUT_W - tw) // 2, y), line, font=q_font, fill=WHITE)
        y += q_line_h
    y += q_opt_gap

    for i, (lines, lh, h) in enumerate(opt_meta):
        is_hi = (i == highlight_idx)
        is_dim = dim_others and not is_hi
        row_x = pad_x
        row_w = OUT_W - 2 * pad_x
        if is_hi:
            d.rounded_rectangle([row_x, y, row_x + row_w, y + h],
                                radius=16, fill=GREEN_BG)
        circ_d = 50
        circ_x = row_x + 18
        circ_y = y + (h - circ_d) // 2
        if is_hi:
            d.ellipse([circ_x, circ_y, circ_x + circ_d, circ_y + circ_d], fill=WHITE)
            d.line([(circ_x + 14, circ_y + 25),
                    (circ_x + 22, circ_y + 34),
                    (circ_x + 38, circ_y + 16)],
                   fill=GREEN, width=6)
        else:
            outline_col = DIM if is_dim else WHITE
            d.ellipse([circ_x, circ_y, circ_x + circ_d, circ_y + circ_d],
                      outline=outline_col, width=2)
            num_txt = str(i + 1)
            d.text((circ_x + circ_d // 2, circ_y + circ_d // 2),
                   num_txt, font=num_font, fill=outline_col, anchor="mm")
        tx = circ_x + circ_d + 18
        ty = y + 16
        col = WHITE if is_hi else (DIM if is_dim else WHITE)
        for line in lines:
            d.text((tx, ty), line, font=opt_font, fill=col)
            ty += lh
        y += h + opt_gap

    img.save(out_path)
    return out_path, OUT_W, block_h


def render_timer_digit(digit_text, out_path, color=WHITE):
    size = 600
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([20, 20, size - 20, size - 20], fill=(0, 0, 0, 215))
    d.ellipse([20, 20, size - 20, size - 20], outline=color, width=8)
    f = font(380)
    d.text((size // 2, size // 2 - 30), digit_text, font=f, fill=color, anchor="mm")
    img.save(out_path)
    return out_path, size, size


def render_time_up(out_path):
    w, h = 700, 200
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w, h], radius=24, fill=(220, 38, 38, 240))
    f = font(110)
    d.text((w // 2, h // 2), "ВРЕМЯ!", font=f, fill=WHITE, anchor="mm")
    img.save(out_path)
    return out_path, w, h


def render_cta(out_path):
    w, h = 980, 200
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w, h], radius=28, fill=(0, 0, 0, 240))
    d.rounded_rectangle([0, 0, w, h], radius=28, outline=YELLOW, width=5)
    f1 = font(50)
    f2 = font(40)
    l1 = "Подпишись"
    l2 = "Каждый день новый билет ПДД"
    tw, _ = text_size(d, l1, f1)
    d.text(((w - tw) // 2, 28), l1, font=f1, fill=YELLOW)
    tw, _ = text_size(d, l2, f2)
    d.text(((w - tw) // 2, 105), l2, font=f2, fill=WHITE)
    img.save(out_path)
    return out_path, w, h


# ---------------------------------------------------------------------------
# PIPELINE STEPS
# ---------------------------------------------------------------------------

def step_generate_scene():
    if P_SCENE.exists():
        print(f"✓ Scene exists: {P_SCENE.name}")
        return
    print("\n>>> [1/4] Nano Banana Pro — scene image")
    out = nb_generate(NB_PROMPT, aspect_ratio="9:16",
                      output_name=f"_short_{SLUG}_scene")
    # nanobanana writes to ASSETS already; ensure final path
    if Path(out) != P_SCENE:
        Path(out).rename(P_SCENE)
    print(f"✓ Scene saved: {P_SCENE.name}")


def step_generate_veo():
    if P_VEO.exists():
        print(f"✓ Veo clip exists: {P_VEO.name}")
        return
    print("\n>>> [2/4] Veo 3.1 Lite — image-to-video (8s, 9:16)")
    out = veo_generate(
        prompt=VEO_PROMPT,
        duration=8,
        aspect_ratio="9:16",
        with_audio=False,
        negative_prompt=VEO_NEGATIVE,
        output_name=f"_short_{SLUG}_veo",
        image_path=str(P_SCENE),
    )
    if Path(out) != P_VEO:
        Path(out).rename(P_VEO)
    print(f"✓ Veo saved: {P_VEO.name}")


def step_generate_tts_all():
    print("\n>>> [3/4] TTS — 4 voice tracks (parallel, Gemini 3.1 Flash TTS, Charon)")
    jobs = [
        (TTS_HOOK_TEXT, f"_short_{SLUG}_tts_hook", P_TTS_HOOK),
        (TTS_QUESTION_TEXT, f"_short_{SLUG}_tts_question", P_TTS_Q),
        (TTS_ANSWER_TEXT, f"_short_{SLUG}_tts_answer", P_TTS_A),
        (TTS_CTA_TEXT, f"_short_{SLUG}_tts_cta", P_TTS_CTA),
    ]
    # Skip jobs whose output already exists
    pending = [(t, n, p) for (t, n, p) in jobs if not p.exists()]
    if not pending:
        print("✓ All TTS files exist, skipping")
        return
    with ThreadPoolExecutor(max_workers=4) as ex:
        futs = {ex.submit(tts_generate, text, "Charon", name, ""): (text, name, p)
                for (text, name, p) in pending}
        for fut in as_completed(futs):
            text, name, p = futs[fut]
            out = fut.result()
            if Path(out) != p:
                Path(out).rename(p)
            print(f"  ✓ {p.name}  ({p.stat().st_size // 1024} KB)")
    print("✓ All TTS done")


def step_build_video_track():
    """Hook bg (2.5s) → Veo clip (8s) → frozen last frame (11.5s) = 22s."""
    # extract last frame
    last_frame = ASSETS / f"_tmp_{SLUG}_lastframe.png"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-sseof", "-0.3", "-i", str(P_VEO),
        "-update", "1", "-q:v", "2", str(last_frame),
    ])

    # hook bg = scene image (no Veo motion needed in hook)
    hook_bg = ASSETS / f"_tmp_{SLUG}_hook_bg.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-i", str(P_SCENE),
        "-t", str(T_HOOK_END),
        "-vf", "scale=720:1280",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-an", str(hook_bg),
    ])

    # frozen tail
    tail = ASSETS / f"_tmp_{SLUG}_tail.mp4"
    tail_dur = TOTAL - 10.5
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-i", str(last_frame),
        "-t", str(tail_dur),
        "-vf", "scale=720:1280",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-an", str(tail),
    ])

    # Re-encode Veo clip (drop audio, normalize)
    veo_clean = ASSETS / f"_tmp_{SLUG}_veo_clean.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(P_VEO),
        "-vf", "scale=720:1280", "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-r", str(FPS), "-an", str(veo_clean),
    ])

    listfile = ASSETS / f"_tmp_{SLUG}_concat.txt"
    listfile.write_text(f"file '{hook_bg}'\nfile '{veo_clean}'\nfile '{tail}'")
    out = ASSETS / f"_tmp_{SLUG}_video_full.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(listfile),
        "-c", "copy", str(out),
    ])
    return out


def step_build_audio():
    out_audio = ASSETS / f"_tmp_{SLUG}_audio.wav"
    tts = [
        (P_TTS_HOOK, 0.0),
        (P_TTS_Q, 2.7),
        (P_TTS_A, 10.7),
        (P_TTS_CTA, 19.2),
    ]
    tick_times = [5.5, 6.5, 7.5, 8.5, 9.5]

    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    for t, _ in tts:
        cmd += ["-i", str(t)]
    for _ in tick_times:
        cmd += ["-f", "lavfi", "-i", "sine=frequency=880:duration=0.08:sample_rate=44100"]
    cmd += ["-f", "lavfi", "-i", "sine=frequency=440:duration=0.4:sample_rate=44100"]

    parts = []
    for i, (_, start) in enumerate(tts):
        delay = int(start * 1000)
        parts.append(f"[{i}:a]aresample=44100,adelay={delay}|{delay},apad=whole_dur={TOTAL}[t{i}]")
    tts_n = len(tts)
    for j, tt in enumerate(tick_times):
        in_idx = tts_n + j
        delay = int(tt * 1000)
        parts.append(f"[{in_idx}:a]volume=0.35,aresample=44100,adelay={delay}|{delay},apad=whole_dur={TOTAL}[k{j}]")
    time_up_idx = tts_n + len(tick_times)
    parts.append(f"[{time_up_idx}:a]volume=0.5,aresample=44100,adelay=10000|10000,apad=whole_dur={TOTAL}[tu]")

    mix_inputs = ("".join(f"[t{i}]" for i in range(tts_n))
                  + "".join(f"[k{j}]" for j in range(len(tick_times))) + "[tu]")
    n_total = tts_n + len(tick_times) + 1
    parts.append(
        mix_inputs +
        f"amix=inputs={n_total}:duration=longest:dropout_transition=0:normalize=0,"
        f"atrim=duration={TOTAL},dynaudnorm[aout]"
    )
    cmd += ["-filter_complex", ";".join(parts),
            "-map", "[aout]", "-ac", "2", "-ar", "44100", str(out_audio)]
    run(cmd)
    return out_audio


def step_render_overlays():
    od = ASSETS / f"_tmp_{SLUG}_overlays"
    od.mkdir(exist_ok=True)
    overlays = []

    p_hook = render_hook_card(od / "hook.png")
    overlays.append((p_hook, T_HOOK_START, T_HOOK_END, 0, 0))

    p_qn, qw, qh = render_question_options_block(od / "q_neutral.png", highlight_idx=-1)
    overlays.append((p_qn, T_HOOK_END, T_TIMER_END, 0, 0))

    digits = ["5", "4", "3", "2", "1"]
    timer_size = 600
    timer_x = (OUT_W - timer_size) // 2
    timer_y = (OUT_H - timer_size) // 2 + 80
    for i, dg in enumerate(digits):
        col = RED if i >= 3 else (YELLOW if i >= 1 else WHITE)
        p, w, h = render_timer_digit(dg, od / f"timer_{dg}.png", color=col)
        overlays.append((p, T_TIMER_START + i, T_TIMER_START + i + 1, timer_x, timer_y))

    p_tu, tw_, th_ = render_time_up(od / "time_up.png")
    tu_x = (OUT_W - tw_) // 2
    tu_y = (OUT_H - th_) // 2
    overlays.append((p_tu, T_TIMER_END - 0.05, T_TIMER_END + 0.6, tu_x, tu_y))

    p_qh, _, _ = render_question_options_block(
        od / "q_highlight.png",
        highlight_idx=CORRECT_IDX,
        dim_others=True,
    )
    overlays.append((p_qh, T_ANSWER_START, T_ANSWER_END, 0, 0))

    p_cta, cw, ch = render_cta(od / "cta.png")
    cta_x = (OUT_W - cw) // 2
    cta_y = OUT_H - ch - 100
    overlays.append((p_cta, T_CTA_START, TOTAL, cta_x, cta_y))

    return overlays


def step_compose_final(video_path, audio_path, overlays):
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-stats",
           "-i", str(video_path), "-i", str(audio_path)]
    for ov in overlays:
        cmd += ["-loop", "1", "-i", str(ov[0])]

    fc_parts = [f"[0:v]scale={OUT_W}:{OUT_H}:flags=lanczos,format=yuva420p[v0]"]
    prev = "v0"
    for i, (path, s, e, x, y) in enumerate(overlays):
        in_idx = i + 2
        out_lbl = f"v{i+1}"
        fc_parts.append(
            f"[{prev}][{in_idx}:v]overlay=x={x}:y={y}:enable='between(t,{s},{e})':format=auto[{out_lbl}]"
        )
        prev = out_lbl

    cmd += [
        "-filter_complex", ";".join(fc_parts),
        "-map", f"[{prev}]", "-map", "1:a",
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100",
        "-movflags", "+faststart",
        "-r", str(FPS), "-t", str(TOTAL),
        str(P_FINAL),
    ]
    run(cmd)


def cleanup_tmp():
    for f in ASSETS.glob(f"_tmp_{SLUG}_*"):
        if f.is_file():
            f.unlink(missing_ok=True)
    od = ASSETS / f"_tmp_{SLUG}_overlays"
    if od.exists():
        for f in od.iterdir():
            f.unlink(missing_ok=True)
        od.rmdir()


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main():
    t0 = time.time()

    # Stage A: image (must run before Veo)
    step_generate_scene()

    # Stage B: Veo + TTS in parallel (Veo needs image, but is independent of TTS)
    with ThreadPoolExecutor(max_workers=2) as ex:
        f_veo = ex.submit(step_generate_veo)
        f_tts = ex.submit(step_generate_tts_all)
        for f in as_completed([f_veo, f_tts]):
            f.result()  # propagate exceptions

    # Stage C: compose
    print("\n>>> [4/4] Compose final Short")
    vid = step_build_video_track()
    aud = step_build_audio()
    overlays = step_render_overlays()
    print(f"  {len(overlays)} overlays")
    step_compose_final(vid, aud, overlays)
    cleanup_tmp()

    size_mb = P_FINAL.stat().st_size / 1_000_000
    print(f"\n{'='*60}")
    print(f"✓ DONE in {time.time() - t0:.0f}s")
    print(f"  Final : {P_FINAL}")
    print(f"  Size  : {size_mb:.1f} MB")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
