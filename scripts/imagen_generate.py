#!/usr/bin/env python3
"""Static image generation via Google Imagen 4 (Vertex AI)."""

import sys
import os
import warnings
warnings.filterwarnings("ignore")

from pathlib import Path
from datetime import datetime
from google import genai
from google.genai import types

PROJECT_ID = "project-f255bf9a-3e64-4fff-a59"
LOCATION = "us-central1"
MODEL = "imagen-4.0-generate-001"
OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "videos"


def generate_image(
    prompt: str,
    aspect_ratio: str = "9:16",
    output_name: str = "",
) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not output_name:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe = prompt[:40].replace(" ", "_").replace("/", "-").replace(",", "")
        output_name = f"{ts}_{safe}"
    output_path = OUTPUT_DIR / f"{output_name}.png"

    print(f"\n{'='*60}")
    print(f"Model  : {MODEL}")
    print(f"Prompt : {prompt}")
    print(f"Ratio  : {aspect_ratio}")
    print(f"Output : {output_path}")
    print(f"{'='*60}")
    print("Generating...", flush=True)

    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)

    result = client.models.generate_images(
        model=MODEL,
        prompt=prompt,
        config=types.GenerateImagesConfig(
            number_of_images=1,
            aspect_ratio=aspect_ratio,
            person_generation="allow_adult",
        ),
    )

    if not result.generated_images:
        raise RuntimeError("No images in response: " + str(result))

    img = result.generated_images[0].image
    output_path.write_bytes(img.image_bytes)

    size_kb = output_path.stat().st_size / 1024
    print(f"Saved  : {output_path}  ({size_kb:.0f} KB)")
    return output_path


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("Usage: python3 imagen_generate.py '<prompt>' [--ratio 9:16|16:9|1:1] [--name <name>]")
        sys.exit(0 if args else 1)

    prompt = args[0]
    aspect = "9:16"
    name = ""
    i = 1
    while i < len(args):
        a = args[i]
        if a == "--ratio" and i + 1 < len(args):
            aspect = args[i + 1]; i += 2
        elif a == "--name" and i + 1 < len(args):
            name = args[i + 1]; i += 2
        else:
            i += 1

    generate_image(prompt, aspect, name)
