#!/usr/bin/env python3
"""Compose final PDD Reel from 4 Veo clips + 4 TTS files + PIL-rendered text overlays."""

import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

V = Path("/Users/sergei/Documents/pdd/assets/videos")

CLIPS = [
    V / "reel_clipA_waiting.mp4",
    V / "reel_clipB_logan_passes.mp4",
    V / "reel_clipC_bus_passes.mp4",
    V / "reel_clipD_we_turn_left.mp4",
]
TTS = [
    V / "tts_01_question.wav",       # 3.2s
    V / "tts_02_explain_logan.wav",  # 12.3s
    V / "tts_03_explain_bus.wav",    # 10.2s
    V / "tts_04_answer.wav",         # 5.9s
]

FINAL = V / "REEL_ticket14_final.mp4"
TMP_CONCAT = V / "_tmp_concat.mp4"
TMP_AUDIO = V / "_tmp_audio.wav"
TMP_VIDEO_FULL = V / "_tmp_video_full.mp4"

FONT_BOLD = "/Users/sergei/Library/Fonts/helvetica_bold.otf"
FONT_REG  = "/System/Library/Fonts/Helvetica.ttc"

OUT_W, OUT_H = 1080, 1920
FPS = 30
EXT_SECONDS = 5.5
TOTAL = 37.5

TTS_STARTS = [0.5, 8.5, 21.0, 31.5]
YELLOW = (255, 216, 61, 255)
WHITE = (255, 255, 255, 255)


def run(cmd):
    print(f"\n$ {' '.join(str(c) for c in cmd[:6])} ... ({len(cmd)} args)")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("STDERR:", res.stderr[-2500:])
        raise subprocess.CalledProcessError(res.returncode, cmd)


# ---------- PIL HELPERS ----------

def font(size, bold=True):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)


def text_size(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def render_card(
    text_lines,                       # list of (text, font_size, color)
    out_path: Path,
    pad_x=60, pad_y=44, line_gap=20,
    bg=(0, 0, 0, 200),
    radius=24,
    align="center",
    max_w=None,
):
    """Render a card with multi-line text on transparent background, save PNG."""
    # Measure
    tmp = Image.new("RGBA", (1, 1))
    d = ImageDraw.Draw(tmp)
    sizes = []
    max_text_w = 0
    total_h = 0
    for txt, sz, col in text_lines:
        f = font(sz, True)
        w, h = text_size(d, txt, f)
        sizes.append((w, h, f, col, txt))
        max_text_w = max(max_text_w, w)
        total_h += h
    total_h += line_gap * (len(text_lines) - 1)
    card_w = max_text_w + pad_x * 2
    card_h = total_h + pad_y * 2
    if max_w:
        card_w = min(card_w, max_w)

    img = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, card_w, card_h], radius=radius, fill=bg)

    y = pad_y
    for w, h, f, col, txt in sizes:
        if align == "center":
            x = (card_w - w) // 2
        else:
            x = pad_x
        d.text((x, y), txt, font=f, fill=col)
        y += h + line_gap

    img.save(out_path)
    return out_path, card_w, card_h


def render_subtitle(text: str, out_path: Path, font_size=46):
    """TikTok-style word group: white text, semi-dark backdrop, rounded."""
    fnt = font(font_size, True)
    tmp = Image.new("RGBA", (1, 1))
    d = ImageDraw.Draw(tmp)
    w, h = text_size(d, text, fnt)
    pad_x, pad_y = 36, 22
    card_w = min(w + pad_x * 2, OUT_W - 80)
    card_h = h + pad_y * 2

    img = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, card_w, card_h], radius=20, fill=(0, 0, 0, 190))
    # Center text
    tw, th = text_size(d, text, fnt)
    d.text(((card_w - tw) // 2, (card_h - th) // 2 - 4), text, font=fnt, fill=WHITE)
    img.save(out_path)
    return out_path, card_w, card_h


# ---------- PIPELINE STEPS ----------

def step1_concat_clips():
    listfile = V / "_tmp_concat_list.txt"
    listfile.write_text("\n".join(f"file '{c}'" for c in CLIPS))
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(listfile),
        "-c", "copy", str(TMP_CONCAT),
    ])


def step2_extend_with_final_frame():
    last_frame = V / "_tmp_last_frame.png"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-sseof", "-0.5", "-i", str(TMP_CONCAT),
        "-update", "1", "-q:v", "2", str(last_frame),
    ])
    still_video = V / "_tmp_still.mp4"
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-i", str(last_frame),
        "-c:v", "libx264", "-t", str(EXT_SECONDS), "-pix_fmt", "yuv420p",
        "-r", str(FPS), "-vf", "scale=720:1280", str(still_video),
    ])
    listfile = V / "_tmp_extend_list.txt"
    listfile.write_text(f"file '{TMP_CONCAT}'\nfile '{still_video}'")
    run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0", "-i", str(listfile),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-an", str(TMP_VIDEO_FULL),
    ])


def step3_build_audio():
    delays_ms = [int(t * 1000) for t in TTS_STARTS]
    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    for tts in TTS:
        cmd += ["-i", str(tts)]
    parts = []
    for i, d in enumerate(delays_ms):
        parts.append(f"[{i}:a]aresample=44100,adelay={d}|{d},apad=whole_dur={TOTAL}[a{i}]")
    parts.append("".join(f"[a{i}]" for i in range(len(TTS))) +
                 f"amix=inputs={len(TTS)}:duration=longest:dropout_transition=0:normalize=0,"
                 f"atrim=duration={TOTAL},dynaudnorm[aout]")
    fc = ";".join(parts)
    cmd += ["-filter_complex", fc, "-map", "[aout]",
            "-ac", "2", "-ar", "44100", str(TMP_AUDIO)]
    run(cmd)


def step4_render_overlays():
    """Render all overlay PNGs and return a list of (png_path, start, end, x, y)."""
    overlays = []  # (path, start, end, x, y)
    overlay_dir = V / "_tmp_overlays"
    overlay_dir.mkdir(exist_ok=True)

    # 1. Question card top, t=0 .. 7.6
    path, w, h = render_card(
        [("ПРИ ПОВОРОТЕ НАЛЕВО", 56, WHITE),
         ("Кто проедет первым?", 52, YELLOW)],
        overlay_dir / "q_card.png",
        pad_x=50, pad_y=44, line_gap=22, bg=(0, 0, 0, 200), radius=28,
    )
    overlays.append((path, 0.0, 7.6, (OUT_W - w) // 2, 130))

    # 2. Pointer "ГЛАВНАЯ ДОРОГА" 9.5..15.5, right side
    path, w, h = render_card(
        [("→ ГЛАВНАЯ ДОРОГА", 40, YELLOW)],
        overlay_dir / "p_main_road.png",
        pad_x=30, pad_y=18, bg=(0, 0, 0, 200), radius=16,
    )
    overlays.append((path, 9.5, 15.5, OUT_W - w - 40, 540))

    # 3. Pointer "ВСТРЕЧНЫЙ ПРЯМО" 22..27.5, upper center
    path, w, h = render_card(
        [("ВСТРЕЧНЫЙ ПРЯМО", 40, YELLOW)],
        overlay_dir / "p_bus.png",
        pad_x=30, pad_y=18, bg=(0, 0, 0, 200), radius=16,
    )
    overlays.append((path, 22.0, 27.5, (OUT_W - w) // 2, 400))

    # 4. Final answer card 32..37.5, center
    path, w, h = render_card(
        [("ПРАВИЛЬНЫЙ ОТВЕТ", 44, YELLOW),
         ("Уступить автобусу", 70, WHITE),
         ("и легковому", 70, WHITE)],
        overlay_dir / "answer_card.png",
        pad_x=60, pad_y=44, line_gap=18, bg=(0, 0, 0, 225), radius=32,
    )
    overlays.append((path, 32.0, 37.5, (OUT_W - w) // 2, (OUT_H - h) // 2))

    # 5. Subtitles per TTS line, word-groups of 4 words
    tts_texts = [
        ("При повороте налево... кто проедет первым?", 0),
        ("Жёлтые знаки — это главная дорога. Она пересекает наш путь. По ней едет легковой автомобиль — у него приоритет.", 1),
        ("Автобус навстречу — на второстепенной, как и мы. Но он движется прямо, а мы поворачиваем налево. Значит, уступаем и автобусу.", 2),
        # answer text is rendered as final big card, no subtitle for TTS#4
    ]
    tts_durs = []
    for f in TTS:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", str(f)]
        ).decode().strip()
        tts_durs.append(float(out))

    sub_y = 1450  # lower third
    sub_idx = 0
    for txt, idx in tts_texts:
        start = TTS_STARTS[idx]
        dur = tts_durs[idx]
        words = txt.split()
        chunk_size = 4
        chunks = [" ".join(words[i:i+chunk_size]) for i in range(0, len(words), chunk_size)]
        per_chunk = dur / max(1, len(chunks))
        for i, chunk in enumerate(chunks):
            s = start + i * per_chunk
            e = start + (i + 1) * per_chunk - 0.05
            sub_path = overlay_dir / f"sub_{sub_idx:02d}.png"
            p, w, h = render_subtitle(chunk, sub_path, font_size=46)
            overlays.append((p, s, e, (OUT_W - w) // 2, sub_y))
            sub_idx += 1

    return overlays


def step5_compose_final(overlays):
    """Use ffmpeg overlay filter for each pre-rendered PNG."""
    # Build inputs: video + audio + N overlay PNGs
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-stats",
           "-i", str(TMP_VIDEO_FULL), "-i", str(TMP_AUDIO)]
    for ov in overlays:
        cmd += ["-loop", "1", "-i", str(ov[0])]

    # Filter graph: scale video to 1080x1920, then overlay each PNG with enable timing
    fc_parts = [f"[0:v]scale={OUT_W}:{OUT_H}:flags=lanczos,format=yuva420p[v0]"]
    prev = "v0"
    for i, (path, s, e, x, y) in enumerate(overlays):
        in_idx = i + 2  # 0=video, 1=audio, 2+ = overlays
        out_lbl = f"v{i+1}"
        fc_parts.append(
            f"[{prev}][{in_idx}:v]overlay=x={x}:y={y}:enable='between(t,{s},{e})':format=auto[{out_lbl}]"
        )
        prev = out_lbl
    fc = ";".join(fc_parts)

    cmd += [
        "-filter_complex", fc,
        "-map", f"[{prev}]", "-map", "1:a",
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "44100",
        "-movflags", "+faststart",
        "-r", str(FPS),
        "-t", str(TOTAL),
        str(FINAL),
    ]
    run(cmd)


def cleanup():
    for f in V.glob("_tmp_*"):
        if f.is_file():
            f.unlink(missing_ok=True)
        elif f.is_dir():
            for sub in f.iterdir():
                sub.unlink(missing_ok=True)
            f.rmdir()


if __name__ == "__main__":
    print("Step 1: concat clips")
    step1_concat_clips()
    print("Step 2: extend with final frame")
    step2_extend_with_final_frame()
    print("Step 3: build audio timeline")
    step3_build_audio()
    print("Step 4: render text overlays as PNG")
    overlays = step4_render_overlays()
    print(f"  Rendered {len(overlays)} overlays")
    print("Step 5: compose final with PNG overlays + audio")
    step5_compose_final(overlays)
    size_mb = FINAL.stat().st_size / 1_000_000
    print(f"\n✓ Done: {FINAL}  ({size_mb:.1f} MB)")
    # Keep _tmp_overlays for now, cleanup other temps
    for f in V.glob("_tmp_*"):
        if f.is_file():
            f.unlink(missing_ok=True)
