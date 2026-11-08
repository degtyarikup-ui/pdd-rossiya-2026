#!/usr/bin/env python3
"""Compose quiz-style PDD TikTok reel: hook → question + timer → answer reveal → CTA.

Question: «Разрешено ли Вам обогнать мотоцикл?» (Ticket 2)
Answers:
  1. Разрешено
  2. Разрешено, если водитель мотоцикла снизил скорость
  3. Запрещено ✓
"""

import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

V = Path("/Users/sergei/Documents/pdd/assets/videos")

SCENE_IMG  = V / "quiz_scene_motorcycle_intersection.png"
VEO_CLIP   = V / "quiz_clip_motorcycle_riding.mp4"  # 8s animated
TTS_HOOK   = V / "quiz_tts_01_hook.wav"     # 2.4s
TTS_Q      = V / "quiz_tts_02_question.wav" # 2.9s
TTS_A      = V / "quiz_tts_03_answer.wav"   # 8.1s
TTS_CTA    = V / "quiz_tts_04_cta.wav"      # 2.6s

FINAL = V / "QUIZ_motorcycle_overtake.mp4"

FONT_BOLD = "/Users/sergei/Library/Fonts/helvetica_bold.otf"

OUT_W, OUT_H = 1080, 1920
FPS = 30

# Timeline (seconds)
T_HOOK_START   = 0.0
T_HOOK_END     = 2.5
T_QUESTION     = 2.7
T_TIMER_START  = 5.5
T_TIMER_END    = 10.5    # 5s countdown
T_ANSWER_START = 10.5
T_ANSWER_END   = 19.0
T_CTA_START    = 19.0
TOTAL          = 22.0

# Colors
WHITE = (255, 255, 255, 255)
YELLOW = (255, 216, 61, 255)
GREEN = (74, 222, 128, 255)
GREEN_BG = (32, 130, 70, 240)
RED = (239, 68, 68, 255)
DIM = (160, 160, 160, 200)
BLACK_85 = (0, 0, 0, 220)

QUESTION = "Разрешено ли Вам обогнать мотоцикл?"
OPTIONS = [
    "Разрешено",
    "Разрешено, если мотоциклист снизил скорость",
    "Запрещено",
]
CORRECT_IDX = 2  # 0-based


def run(cmd):
    print(f"$ {' '.join(str(c) for c in cmd[:6])} ... ({len(cmd)} args)")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("STDERR:", res.stderr[-2500:])
        raise subprocess.CalledProcessError(res.returncode, cmd)


def font(size): return ImageFont.truetype(FONT_BOLD, size)


def text_size(d, text, fnt):
    bbox = d.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def wrap_text(text, fnt, max_w, d):
    words, lines, cur = text.split(), [], []
    for w in words:
        test = " ".join(cur + [w])
        if text_size(d, test, fnt)[0] <= max_w or not cur:
            cur.append(w)
        else:
            lines.append(" ".join(cur)); cur = [w]
    if cur: lines.append(" ".join(cur))
    return lines


def render_hook_card(out_path):
    """Big bold hook text 'СМОЖЕШЬ?' centered."""
    img = Image.new("RGBA", (OUT_W, OUT_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Full dark backdrop with vignette
    d.rectangle([0, 0, OUT_W, OUT_H], fill=(0, 0, 0, 200))
    # Top line
    f1 = font(70)
    f2 = font(140)
    f3 = font(50)
    line1 = "СМОЖЕШЬ ОТВЕТИТЬ"
    line2 = "ЗА 5 СЕКУНД?"
    line3 = "Правила ПДД"
    tw, th = text_size(d, line1, f1)
    d.text(((OUT_W - tw) // 2, 760), line1, font=f1, fill=WHITE)
    tw, th = text_size(d, line2, f2)
    d.text(((OUT_W - tw) // 2, 850), line2, font=f2, fill=YELLOW)
    tw, th = text_size(d, line3, f3)
    d.text(((OUT_W - tw) // 2, 1020), line3, font=f3, fill=WHITE)
    img.save(out_path)
    return out_path


def render_question_options_block(out_path, highlight_idx=-1, dim_others=False):
    """Top panel: question + 3 options."""
    pad_x = 50
    q_font = font(50)
    opt_font = font(38)
    num_font = font(34)
    img = Image.new("RGBA", (OUT_W, 1), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

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
        tw, th = text_size(d, line, q_font)
        d.text(((OUT_W - tw) // 2, y), line, font=q_font, fill=WHITE)
        y += q_line_h
    y += q_opt_gap

    for i, (lines, lh, h) in enumerate(opt_meta):
        is_hi = (i == highlight_idx)
        is_dim = dim_others and not is_hi
        # Row background
        row_x = pad_x
        row_w = OUT_W - 2 * pad_x
        if is_hi:
            d.rounded_rectangle([row_x, y, row_x + row_w, y + h],
                                radius=16, fill=GREEN_BG)
        # Number circle
        circ_d = 50
        circ_x = row_x + 18
        circ_y = y + (h - circ_d) // 2
        if is_hi:
            d.ellipse([circ_x, circ_y, circ_x + circ_d, circ_y + circ_d], fill=WHITE)
            # checkmark
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
        # Text
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
    """Big timer digit centered, with circular backdrop."""
    size = 600
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([20, 20, size - 20, size - 20], fill=(0, 0, 0, 215))
    d.ellipse([20, 20, size - 20, size - 20], outline=color, width=8)
    f = font(380)
    # Anchor mm + small upward bias for optical center of digit glyph
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


def render_answer_banner(out_path):
    w, h = 920, 150
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w, h], radius=24, fill=(0, 0, 0, 235))
    d.rounded_rectangle([0, 0, w, h], radius=24, outline=GREEN, width=5)
    f1 = font(38)
    f2 = font(58)
    l1 = "ПРАВИЛЬНЫЙ ОТВЕТ"
    l2 = "Запрещено"
    tw, th = text_size(d, l1, f1)
    d.text(((w - tw) // 2, 22), l1, font=f1, fill=GREEN)
    tw, th = text_size(d, l2, f2)
    d.text(((w - tw) // 2, 75), l2, font=f2, fill=WHITE)
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
    l2 = "Каждый день новый вопрос ПДД"
    tw, th = text_size(d, l1, f1)
    d.text(((w - tw) // 2, 28), l1, font=f1, fill=YELLOW)
    tw, th = text_size(d, l2, f2)
    d.text(((w - tw) // 2, 105), l2, font=f2, fill=WHITE)
    img.save(out_path)
    return out_path, w, h


# ---------- PIPELINE ----------

def step1_build_video_track():
    """Build video timeline: hook BG + animated scene + freeze frame."""
    # 0-2.5s: hook background (just the scene image, blurred + darkened — we overlay text)
    # 2.5-10.5s: 8s Veo clip
    # 10.5-22.0s: freeze last frame of Veo clip

    # Extract last frame of Veo clip
    last_frame = V / "_tmp_quiz_lastframe.png"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-sseof", "-0.3", "-i", str(VEO_CLIP),
        "-update", "1", "-q:v", "2", str(last_frame),
    ])

    # Hook BG: just use the scene image, scaled to 720x1280 (matches Veo output)
    hook_bg = V / "_tmp_quiz_hook_bg.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-i", str(SCENE_IMG),
        "-t", str(T_HOOK_END),
        "-vf", "scale=720:1280",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-an", str(hook_bg),
    ])

    # Freeze tail
    tail = V / "_tmp_quiz_tail.mp4"
    tail_dur = TOTAL - 10.5
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-i", str(last_frame),
        "-t", str(tail_dur),
        "-vf", "scale=720:1280",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-an", str(tail),
    ])

    # Re-encode Veo clip (sanity, ensure same params, drop audio)
    veo_clean = V / "_tmp_quiz_veo_clean.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(VEO_CLIP),
        "-vf", "scale=720:1280", "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-r", str(FPS), "-an", str(veo_clean),
    ])

    # Concat
    listfile = V / "_tmp_quiz_concat.txt"
    listfile.write_text(f"file '{hook_bg}'\nfile '{veo_clean}'\nfile '{tail}'")
    out = V / "_tmp_quiz_video_full.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(listfile),
        "-c", "copy", str(out),
    ])
    return out


def step2_build_audio():
    """Build audio timeline: TTS placement + simple tick sounds during timer."""
    out_audio = V / "_tmp_quiz_audio.wav"
    # TTS timings (sec)
    tts = [
        (TTS_HOOK, 0.0),
        (TTS_Q,    2.7),
        (TTS_A,    10.7),
        (TTS_CTA,  19.2),
    ]

    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    # 5 ticks at 5.5, 6.5, 7.5, 8.5, 9.5 — short beeps via lavfi sine
    tick_times = [5.5, 6.5, 7.5, 8.5, 9.5]
    # Build inputs
    for t, _ in tts:
        cmd += ["-i", str(t)]
    # Ticks: short 100ms sine bursts
    for _ in tick_times:
        cmd += ["-f", "lavfi", "-i", "sine=frequency=880:duration=0.08:sample_rate=44100"]
    # Final time-up sound at 10.0
    cmd += ["-f", "lavfi", "-i", "sine=frequency=440:duration=0.4:sample_rate=44100"]

    # Filter parts
    parts = []
    # TTS streams
    for i, (_, start) in enumerate(tts):
        delay = int(start * 1000)
        parts.append(f"[{i}:a]aresample=44100,adelay={delay}|{delay},apad=whole_dur={TOTAL}[t{i}]")
    # Ticks
    tts_n = len(tts)
    for j, tt in enumerate(tick_times):
        in_idx = tts_n + j
        delay = int(tt * 1000)
        parts.append(f"[{in_idx}:a]volume=0.35,aresample=44100,adelay={delay}|{delay},apad=whole_dur={TOTAL}[k{j}]")
    # Time-up
    time_up_idx = tts_n + len(tick_times)
    parts.append(f"[{time_up_idx}:a]volume=0.5,aresample=44100,adelay=10000|10000,apad=whole_dur={TOTAL}[tu]")

    # Mix all
    mix_inputs = "".join(f"[t{i}]" for i in range(tts_n)) + \
                 "".join(f"[k{j}]" for j in range(len(tick_times))) + "[tu]"
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


def step3_render_overlays():
    od = V / "_tmp_quiz_overlays"
    od.mkdir(exist_ok=True)
    overlays = []  # (path, start, end, x, y)

    # 1) Hook 0-2.5s: full-screen text
    p_hook = render_hook_card(od / "hook.png")
    overlays.append((p_hook, T_HOOK_START, T_HOOK_END, 0, 0))

    # 2) Question + options NEUTRAL (visible 2.5-10.5)
    p_qn, qw, qh = render_question_options_block(od / "q_neutral.png", highlight_idx=-1)
    overlays.append((p_qn, T_HOOK_END, T_TIMER_END, 0, 0))

    # 3) Timer digits 5,4,3,2,1 — each shown 1s
    digits = ["5", "4", "3", "2", "1"]
    timer_size = 600
    timer_x = (OUT_W - timer_size) // 2
    timer_y = (OUT_H - timer_size) // 2 + 80
    for i, dg in enumerate(digits):
        col = RED if i >= 3 else (YELLOW if i >= 1 else WHITE)
        p, w, h = render_timer_digit(dg, od / f"timer_{dg}.png", color=col)
        overlays.append((p, T_TIMER_START + i, T_TIMER_START + i + 1, timer_x, timer_y))

    # 4) ВРЕМЯ! flash at T_TIMER_END for 0.4s
    p_tu, tw_, th_ = render_time_up(od / "time_up.png")
    tu_x = (OUT_W - tw_) // 2
    tu_y = (OUT_H - th_) // 2
    overlays.append((p_tu, T_TIMER_END - 0.05, T_TIMER_END + 0.6, tu_x, tu_y))

    # 5) Question + options HIGHLIGHT (visible 10.5-19.0s, correct option green)
    p_qh, _, qhh = render_question_options_block(od / "q_highlight.png",
                                                 highlight_idx=CORRECT_IDX,
                                                 dim_others=True)
    overlays.append((p_qh, T_ANSWER_START, T_ANSWER_END, 0, 0))

    # 6) (Answer banner removed — green highlight on option 3 already conveys it)

    # 7) CTA at 19-22 bottom
    p_cta, cw, ch = render_cta(od / "cta.png")
    cta_x = (OUT_W - cw) // 2
    cta_y = OUT_H - ch - 100
    overlays.append((p_cta, T_CTA_START, TOTAL, cta_x, cta_y))

    return overlays


def step4_compose_final(video_path, audio_path, overlays):
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
        str(FINAL),
    ]
    run(cmd)


if __name__ == "__main__":
    print("Step 1: build video track")
    vid = step1_build_video_track()
    print("Step 2: build audio")
    aud = step2_build_audio()
    print("Step 3: render overlays")
    overlays = step3_render_overlays()
    print(f"  {len(overlays)} overlays")
    print("Step 4: compose")
    step4_compose_final(vid, aud, overlays)
    size_mb = FINAL.stat().st_size / 1_000_000
    print(f"\n✓ Done: {FINAL}  ({size_mb:.1f} MB)")
    for f in V.glob("_tmp_quiz_*"):
        if f.is_file():
            f.unlink(missing_ok=True)
