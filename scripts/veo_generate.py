#!/usr/bin/env python3
"""Video generation via Google Veo 3.1 Lite (Vertex AI)."""

import sys
import time
import os
import subprocess
import warnings
warnings.filterwarnings("ignore")

from pathlib import Path
from datetime import datetime
from google import genai
from google.genai import types

PROJECT_ID = "project-f255bf9a-3e64-4fff-a59"
LOCATION = "us-central1"
MODEL = "veo-3.1-lite-generate-001"
OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "videos"


def generate_video(
    prompt: str,
    duration: int = 6,  # supported: 4, 6, 8
    aspect_ratio: str = "16:9",
    with_audio: bool = False,
    negative_prompt: str = "",
    output_name: str = "",
    low_quality: bool = False,
    image_path: str = "",
) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not output_name:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe = prompt[:40].replace(" ", "_").replace("/", "-").replace(",", "")
        output_name = f"{ts}_{safe}"
    output_path = OUTPUT_DIR / f"{output_name}.mp4"

    print(f"\n{'='*60}")
    print(f"Model  : {MODEL}")
    print(f"Prompt : {prompt[:120]}{'...' if len(prompt) > 120 else ''}")
    if image_path:
        print(f"Image  : {image_path}")
    if negative_prompt:
        print(f"Neg.   : {negative_prompt}")
    print(f"Audio  : {'yes' if with_audio else 'no'}")
    print(f"Output : {output_path}")
    print(f"{'='*60}")
    print("Sending request...", flush=True)

    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)

    config = types.GenerateVideosConfig(
        aspect_ratio=aspect_ratio,
        duration_seconds=duration,
        number_of_videos=1,
        generate_audio=with_audio,
        enhance_prompt=True,
        person_generation="allow_adult",
    )
    if negative_prompt:
        config.negative_prompt = negative_prompt

    image_arg = None
    if image_path:
        p = Path(image_path)
        ext = p.suffix.lower().lstrip(".")
        mime = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}.get(ext, "image/png")
        image_arg = types.Image(image_bytes=p.read_bytes(), mime_type=mime)

    operation = client.models.generate_videos(
        model=MODEL,
        prompt=prompt,
        image=image_arg,
        config=config,
    )

    print("Processing", end="", flush=True)
    while not operation.done:
        time.sleep(5)
        operation = client.operations.get(operation)
        print(".", end="", flush=True)
    print(" done!\n")

    if not operation.response or not operation.response.generated_videos:
        raise RuntimeError("No videos in response: " + str(operation))

    video = operation.response.generated_videos[0]
    output_path.write_bytes(video.video.video_bytes)

    size_mb = output_path.stat().st_size / 1_000_000
    print(f"Saved  : {output_path}  ({size_mb:.1f} MB)")

    if low_quality:
        lq_path = output_path.with_name(output_path.stem + "_lq.mp4")
        print("Downscaling to 480p with dashcam-style compression...", flush=True)
        # 480p shortest side, ~400k video bitrate, 64k audio, h264 baseline
        # Aspect-preserving: scale shorter side to 480
        scale_filter = "scale='if(gt(iw,ih),-2,480)':'if(gt(iw,ih),480,-2)'"
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(output_path),
            "-vf", scale_filter,
            "-c:v", "libx264", "-profile:v", "baseline", "-preset", "veryfast",
            "-b:v", "400k", "-maxrate", "500k", "-bufsize", "800k",
            "-c:a", "aac", "-b:a", "64k", "-ac", "1",
            "-movflags", "+faststart",
            str(lq_path),
        ]
        subprocess.run(cmd, check=True)
        lq_mb = lq_path.stat().st_size / 1_000_000
        print(f"LQ     : {lq_path}  ({lq_mb:.1f} MB)")
        return lq_path
    return output_path


def print_help():
    print("""
Usage:
  python3 veo_generate.py '<prompt>' [options]

Options:
  --duration N       Duration in seconds (default: 5)
  --ratio R          Aspect ratio: 16:9 or 9:16 (default: 16:9)
  --audio            Enable audio generation
  --no '<text>'      Negative prompt
  --name '<name>'    Output filename (without .mp4)
  --lq               Downscale to 480p + heavy compression (dashcam style)
  --image <path>     Use image as first frame (image-to-video)

Examples:
  python3 veo_generate.py 'Car approaching intersection at night'
  python3 veo_generate.py 'Road sign 40 km/h' --duration 8 --audio
  python3 veo_generate.py 'Highway driving' --ratio 9:16 --no 'rain, fog'
""")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print_help()
        sys.exit(0 if args else 1)

    prompt = args[0]
    duration = 6
    aspect = "16:9"
    audio = False
    negative = ""
    name = ""
    lq = False
    image_path = ""

    i = 1
    while i < len(args):
        a = args[i]
        if a == "--duration" and i + 1 < len(args):
            duration = int(args[i + 1]); i += 2
        elif a == "--ratio" and i + 1 < len(args):
            aspect = args[i + 1]; i += 2
        elif a == "--audio":
            audio = True; i += 1
        elif a == "--no" and i + 1 < len(args):
            negative = args[i + 1]; i += 2
        elif a == "--name" and i + 1 < len(args):
            name = args[i + 1]; i += 2
        elif a == "--lq":
            lq = True; i += 1
        elif a == "--image" and i + 1 < len(args):
            image_path = args[i + 1]; i += 2
        else:
            i += 1

    generate_video(prompt, duration, aspect, audio, negative, name, lq, image_path)
