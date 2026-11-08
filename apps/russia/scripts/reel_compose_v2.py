#!/usr/bin/env python3
"""Compose final PDD Reel v2:
- Reuse Clip A (waiting, 8s)
- New Clip B (bus passes, 6s)
- New Clip C (we turn left, 6s)
- 5s final still with green-highlighted correct answer
- Permanent bottom block: question + 3 answer options
- No subtitles, just voice-over
- Total: ~25s
"""

import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

V = Path("/Users/sergei/Documents/pdd/assets/videos")

CLIPS = [
    (V / "reel_clipA_waiting.mp4",        6.0),  # reuse, trim to 6s
    (V / "reel_v2_clipB_bus_passes.mp4",  6.0),  # new, 6s
    (V / "reel_v2_clipC_we_turn.mp4",     6.0),  # new, 6s
]
TTS = [
    V / "tts_v2_01_question.wav",         # ~3.5s
    V / "tts_v2_02_explain_short.wav",    # ~7.8s (shortened)
    V / "tts_v2_03_answer.wav",           # ~3.4s
]

FINAL = V / "REEL_ticket14_v2_final.mp4"
TMP_CONCAT = V / "_tmp_concat.mp4"
TMP_AUDIO = V / "_tmp_audio.wav"
TMP_VIDEO_FULL = V / "_tmp_video_full.mp4"

FONT_BOLD = "/Users/sergei/Library/Fonts/helvetica_bold.otf"

OUT_W, OUT_H = 1080, 1920
FPS = 30
EXT_SECONDS = 5.0    # final still frame for answer card
TOTAL_VIDEO = 6 + 6 + 6 + EXT_SECONDS  # 23.0s

WHITE = (255, 255, 255, 255)
YELLOW = (255, 216, 61, 255)
GREEN = (74, 222, 128, 255)
GREEN_BG = (32, 130, 70, 240)
DIM = (180, 180, 180, 200)

QUESTION = "При повороте налево Вы:"
OPTIONS = [
    "Имеете преимущество",
    "Должны уступить дорогу только автобусу",
    "Должны уступить дорогу легковому автомобилю и автобусу",
]
CORRECT_IDX = 1  # 0-based

# Timing (TOTAL = 23s)
# Clip A: 0-6   (waiting + question + think)
# Clip B: 6-12  (bus passes)
# Clip C: 12-18 (we turn left)
# Final still: 18-23 (answer banner + green highlight)
TTS_STARTS = [0.5, 6.2, 18.7]  # question, explain, answer
ANSWER_HIGHLIGHT_START = 18.0   # when option 2 turns green


def run(cmd):
    print(f"$ {' '.join(str(c) for c in cmd[:6])} ... ({len(cmd)} args)")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("STDERR:", res.stderr[-2500:])
        raise subprocess.CalledProcessError(res.returncode, cmd)


def font(size, bold=True):
    return ImageFont.truetype(FONT_BOLD, size)


def text_size(draw, text, fnt):
    bbox = draw.textbbox((0, 0), text, font=fnt)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def wrap_text(text: str, fnt, max_width: int, draw):
    """Wrap text to fit max_width, return list of lines."""
    words = text.split()
    lines, current = [], []
    for w in words:
        test = " ".join(current + [w])
        tw, _ = text_size(draw, test, fnt)
        if tw <= max_width or not current:
            current.append(w)
        else:
            lines.append(" ".join(current))
            current = [w]
    if current:
        lines.append(" ".join(current))
    return lines


def render_bottom_block(out_path: Path, highlight_idx: int = -1):
    """Render permanent bottom block: question + 3 options.
    If highlight_idx >= 0, that option is shown in green with checkmark.
    Returns (path, w, h) — block is full-width 1080, height variable.
    """
    block_w = OUT_W
    pad_x = 50
    pad_y_top = 40
    pad_y_bot = 50
    q_font = font(46)
    opt_font = font(38)
    opt_num_font = font(38)
    line_gap = 22
    q_opt_gap = 30
    opt_inner_pad_y = 18
    opt_inner_pad_x = 24
    opt_gap = 14

    # Measure
    tmp = Image.new("RGBA", (1, 1))
    d = ImageDraw.Draw(tmp)
    q_lines = wrap_text(QUESTION, q_font, block_w - 2 * pad_x, d)
    q_line_h = text_size(d, "Ay", q_font)[1] + 6
    q_block_h = q_line_h * len(q_lines)

    # Option rows: number-circle + text (wrapped)
    opt_meta = []
    opt_text_max_w = block_w - 2 * pad_x - 70  # 70 for number circle + gap
    for i, txt in enumerate(OPTIONS):
        lines = wrap_text(txt, opt_font, opt_text_max_w, d)
        line_h = text_size(d, "Ay", opt_font)[1] + 4
        h = line_h * len(lines) + 2 * opt_inner_pad_y
        opt_meta.append((lines, line_h, h))

    total_opts_h = sum(m[2] for m in opt_meta) + opt_gap * (len(OPTIONS) - 1)
    block_h = pad_y_top + q_block_h + q_opt_gap + total_opts_h + pad_y_bot

    img = Image.new("RGBA", (block_w, block_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Solid block backdrop with subtle top fade
    d.rounded_rectangle([0, 0, block_w, block_h], radius=0, fill=(0, 0, 0, 220))
    # Subtle top accent line
    d.rectangle([0, 0, block_w, 4], fill=(255, 216, 61, 255))

    # Question
    y = pad_y_top
    for line in q_lines:
        tw, th = text_size(d, line, q_font)
        d.text(((block_w - tw) // 2, y), line, font=q_font, fill=WHITE)
        y += q_line_h
    y += q_opt_gap

    # Options
    for i, (lines, line_h, h) in enumerate(opt_meta):
        is_correct_highlight = (i == highlight_idx)
        # Option background row
        row_x = pad_x
        row_w = block_w - 2 * pad_x
        row_y = y
        if is_correct_highlight:
            d.rounded_rectangle([row_x, row_y, row_x + row_w, row_y + h],
                                radius=16, fill=GREEN_BG)
        else:
            # subtle divider for non-correct
            pass

        # Number circle
        circ_d = 44
        circ_x = row_x + opt_inner_pad_x
        circ_y = row_y + (h - circ_d) // 2
        if is_correct_highlight:
            d.ellipse([circ_x, circ_y, circ_x + circ_d, circ_y + circ_d],
                      fill=WHITE)
            # checkmark
            d.line([(circ_x + 12, circ_y + 22),
                    (circ_x + 20, circ_y + 30),
                    (circ_x + 33, circ_y + 14)],
                   fill=GREEN, width=5)
        else:
            d.ellipse([circ_x, circ_y, circ_x + circ_d, circ_y + circ_d],
                      outline=WHITE, width=2)
            num_txt = str(i + 1)
            ntw, nth = text_size(d, num_txt, opt_num_font)
            d.text((circ_x + (circ_d - ntw) // 2,
                    circ_y + (circ_d - nth) // 2 - 4),
                   num_txt, font=opt_num_font, fill=WHITE)

        # Text
        tx = circ_x + circ_d + 18
        ty = row_y + opt_inner_pad_y
        col = WHITE if is_correct_highlight else (WHITE if highlight_idx < 0 else DIM)
        for line in lines:
            d.text((tx, ty), line, font=opt_font, fill=col)
            ty += line_h

        y += h + opt_gap

    img.save(out_path)
    return out_path, block_w, block_h


def render_answer_banner(out_path: Path):
    """Big centered banner: ПРАВИЛЬНЫЙ ОТВЕТ ✓"""
    w = 800
    h = 140
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w, h], radius=30, fill=(0, 0, 0, 235))
    d.rounded_rectangle([0, 0, w, h], radius=30, outline=GREEN, width=4)
    f1 = font(36)
    f2 = font(54)
    line1 = "ПРАВИЛЬНЫЙ ОТВЕТ"
    line2 = "Уступить только автобусу"
    tw1, th1 = text_size(d, line1, f1)
    d.text(((w - tw1) // 2, 20), line1, font=f1, fill=GREEN)
    tw2, th2 = text_size(d, line2, f2)
    # if too wide reduce font
    if tw2 > w - 40:
        f2 = font(42)
        tw2, th2 = text_size(d, line2, f2)
    d.text(((w - tw2) // 2, 70), line2, font=f2, fill=WHITE)
    img.save(out_path)
    return out_path, w, h


# ---------- PIPELINE ----------

def step1_concat_clips():
    """Trim each clip to its target length and concat."""
    trimmed = []
    for i, (src, dur) in enumerate(CLIPS):
        out = V / f"_tmp_trim_{i}.mp4"
        run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", str(src), "-t", str(dur),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-an", str(out),
        ])
        trimmed.append(out)
    listfile = V / "_tmp_concat_list.txt"
    listfile.write_text("\n".join(f"file '{c}'" for c in trimmed))
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
    for t in TTS:
        cmd += ["-i", str(t)]
    parts = []
    for i, d in enumerate(delays_ms):
        parts.append(f"[{i}:a]aresample=44100,adelay={d}|{d},apad=whole_dur={TOTAL_VIDEO}[a{i}]")
    parts.append("".join(f"[a{i}]" for i in range(len(TTS))) +
                 f"amix=inputs={len(TTS)}:duration=longest:dropout_transition=0:normalize=0,"
                 f"atrim=duration={TOTAL_VIDEO},dynaudnorm[aout]")
    cmd += ["-filter_complex", ";".join(parts),
            "-map", "[aout]", "-ac", "2", "-ar", "44100", str(TMP_AUDIO)]
    run(cmd)


def step4_render_overlays():
    overlay_dir = V / "_tmp_overlays"
    overlay_dir.mkdir(exist_ok=True)

    # 1. Bottom block — NEUTRAL state (visible 0 → 19.95s)
    p_neutral, bw, bh = render_bottom_block(overlay_dir / "block_neutral.png",
                                            highlight_idx=-1)
    # 2. Bottom block — HIGHLIGHT (visible 19.95s → end)
    p_hi, _, _ = render_bottom_block(overlay_dir / "block_highlight.png",
                                     highlight_idx=CORRECT_IDX)
    block_y = OUT_H - bh - 20  # 20px from bottom

    # 3. Answer banner — appears at 20.5s near top of frame
    p_ans, aw, ah = render_answer_banner(overlay_dir / "answer_banner.png")
    answer_x = (OUT_W - aw) // 2
    answer_y = 130

    overlays = [
        (p_neutral, 0.0, ANSWER_HIGHLIGHT_START, 0, block_y),
        (p_hi, ANSWER_HIGHLIGHT_START, TOTAL_VIDEO, 0, block_y),
        (p_ans, 20.5, TOTAL_VIDEO, answer_x, answer_y),
    ]
    return overlays


def step5_compose_final(overlays):
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-stats",
           "-i", str(TMP_VIDEO_FULL), "-i", str(TMP_AUDIO)]
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
        "-r", str(FPS),
        "-t", str(TOTAL_VIDEO),
        str(FINAL),
    ]
    run(cmd)


if __name__ == "__main__":
    # Sanity check inputs
    for src, _ in CLIPS:
        if not src.exists():
            raise SystemExit(f"Missing clip: {src}")
    for f in TTS:
        if not f.exists():
            raise SystemExit(f"Missing TTS: {f}")

    print("Step 1: concat clips")
    step1_concat_clips()
    print("Step 2: extend with final frame")
    step2_extend_with_final_frame()
    print("Step 3: build audio timeline")
    step3_build_audio()
    print("Step 4: render text overlays")
    overlays = step4_render_overlays()
    print(f"  {len(overlays)} overlays")
    print("Step 5: compose final")
    step5_compose_final(overlays)
    size_mb = FINAL.stat().st_size / 1_000_000
    print(f"\n✓ Done: {FINAL}  ({size_mb:.1f} MB)")
    for f in V.glob("_tmp_*"):
        if f.is_file():
            f.unlink(missing_ok=True)
