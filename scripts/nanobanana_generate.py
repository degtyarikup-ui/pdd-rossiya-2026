#!/usr/bin/env python3
"""Image generation via Google Nano Banana Pro (gemini-3-pro-image-preview, Vertex AI)."""

import sys
import os
import base64
import warnings
warnings.filterwarnings("ignore")

from pathlib import Path
from datetime import datetime
from google import genai
from google.genai import types

PROJECT_ID = "project-f255bf9a-3e64-4fff-a59"
LOCATION = "global"  # gemini-3 image preview is served from global
MODEL = os.environ.get("NB_MODEL", "gemini-3-pro-image-preview")
OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "videos"


def generate_image(
    prompt: str,
    aspect_ratio: str = "9:16",
    output_name: str = "",
    reference_image_paths: list = None,
) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not output_name:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe = prompt[:40].replace(" ", "_").replace("/", "-").replace(",", "")
        output_name = f"{ts}_{safe}"
    output_path = OUTPUT_DIR / f"{output_name}.png"

    print(f"\n{'='*60}")
    print(f"Model  : {MODEL}")
    print(f"Prompt : {prompt[:120]}{'...' if len(prompt) > 120 else ''}")
    print(f"Ratio  : {aspect_ratio}")
    if reference_image_paths:
        print(f"Refs   : {reference_image_paths}")
    print(f"Output : {output_path}")
    print(f"{'='*60}")
    print("Generating...", flush=True)

    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)

    # Build contents: text + optional reference images
    parts = [types.Part(text=prompt)]
    if reference_image_paths:
        for p in reference_image_paths:
            with open(p, "rb") as f:
                data = f.read()
            ext = Path(p).suffix.lower().lstrip(".")
            mime = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}.get(ext, "image/png")
            parts.append(types.Part(inline_data=types.Blob(mime_type=mime, data=data)))

    response = client.models.generate_content(
        model=MODEL,
        contents=[types.Content(role="user", parts=parts)],
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(aspect_ratio=aspect_ratio),
        ),
    )

    # Extract image bytes from response
    img_bytes = None
    for cand in response.candidates or []:
        for part in cand.content.parts or []:
            if part.inline_data and part.inline_data.data:
                img_bytes = part.inline_data.data
                break
        if img_bytes:
            break

    if not img_bytes:
        raise RuntimeError("No image in response: " + str(response))

    output_path.write_bytes(img_bytes)
    size_kb = output_path.stat().st_size / 1024
    print(f"Saved  : {output_path}  ({size_kb:.0f} KB)")
    return output_path


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("Usage: python3 nanobanana_generate.py '<prompt>' [--ratio 9:16] [--name <name>] [--ref <path>]...")
        sys.exit(0 if args else 1)

    prompt = args[0]
    aspect = "9:16"
    name = ""
    refs = []
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--ratio" and i + 1 < len(args):
            aspect = args[i + 1]; i += 2
        elif a == "--name" and i + 1 < len(args):
            name = args[i + 1]; i += 2
        elif a == "--ref" and i + 1 < len(args):
            refs.append(args[i + 1]); i += 2
        else:
            i += 1

    generate_image(prompt, aspect, name, refs or None)
