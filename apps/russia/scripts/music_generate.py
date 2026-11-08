#!/usr/bin/env python3
"""Background music generation via Lyria 2 (Vertex AI predict endpoint)."""

import sys
import os
import json
import base64
import urllib.request
import warnings
warnings.filterwarnings("ignore")

from pathlib import Path
from datetime import datetime

import google.auth
import google.auth.transport.requests

PROJECT_ID = "project-f255bf9a-3e64-4fff-a59"
LOCATION = "us-central1"
MODEL = os.environ.get("LYRIA_MODEL", "lyria-002")
OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "videos"


def get_access_token() -> str:
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    creds.refresh(google.auth.transport.requests.Request())
    return creds.token


def generate_music(
    prompt: str,
    negative_prompt: str = "",
    output_name: str = "",
    seed: int = 0,
) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not output_name:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe = prompt[:30].replace(" ", "_").replace("/", "-").replace(",", "")
        output_name = f"music_{ts}_{safe}"
    output_path = OUTPUT_DIR / f"{output_name}.wav"

    print(f"\n{'='*60}")
    print(f"Model  : {MODEL}")
    print(f"Prompt : {prompt}")
    if negative_prompt:
        print(f"Neg.   : {negative_prompt}")
    print(f"Output : {output_path}")
    print(f"{'='*60}")
    print("Generating...", flush=True)

    url = (
        f"https://{LOCATION}-aiplatform.googleapis.com/v1/projects/"
        f"{PROJECT_ID}/locations/{LOCATION}/publishers/google/models/{MODEL}:predict"
    )

    instance = {"prompt": prompt, "sample_count": 1}
    if negative_prompt:
        instance["negative_prompt"] = negative_prompt
    if seed:
        instance["seed"] = seed

    body = json.dumps({"instances": [instance], "parameters": {}}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {get_access_token()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=180) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    predictions = result.get("predictions", [])
    if not predictions:
        raise RuntimeError("No predictions in response: " + json.dumps(result)[:500])

    # Lyria-002 returns base64-encoded WAV in 'bytesBase64Encoded'
    pred = predictions[0]
    audio_b64 = pred.get("bytesBase64Encoded") or pred.get("audioContent")
    if not audio_b64:
        raise RuntimeError("No audio bytes in prediction: " + json.dumps(pred)[:500])

    audio_bytes = base64.b64decode(audio_b64)
    output_path.write_bytes(audio_bytes)

    size_kb = output_path.stat().st_size / 1024
    print(f"Saved  : {output_path}  ({size_kb:.0f} KB)")
    return output_path


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("Usage: python3 music_generate.py '<prompt>' [--neg '<negative>'] [--seed N] [--name <name>]")
        sys.exit(0 if args else 1)

    prompt = args[0]
    neg = ""
    seed = 0
    name = ""

    i = 1
    while i < len(args):
        a = args[i]
        if a == "--neg" and i + 1 < len(args):
            neg = args[i + 1]; i += 2
        elif a == "--seed" and i + 1 < len(args):
            seed = int(args[i + 1]); i += 2
        elif a == "--name" and i + 1 < len(args):
            name = args[i + 1]; i += 2
        else:
            i += 1

    generate_music(prompt, neg, name, seed)
