#!/usr/bin/env python3
"""Russian TTS via Gemini 3.1 Flash TTS (Vertex AI).

Available Gemini prebuilt voices that work for ru-RU (sampled from Google docs):
  male calm:    Charon, Achernar, Algenib, Iapetus, Rasalgethi
  male energetic: Puck, Fenrir, Orus
  female calm:  Aoede, Vindemiatrix, Kore, Leda
  female friendly: Zephyr, Sulafat, Achird

Output: 24kHz mono PCM wav by default (Gemini TTS returns audio/L16 24kHz).
"""

import sys
import os
import struct
import wave
import warnings
warnings.filterwarnings("ignore")

from pathlib import Path
from datetime import datetime
from google import genai
from google.genai import types

PROJECT_ID = "project-f255bf9a-3e64-4fff-a59"
LOCATION = "global"
MODEL = os.environ.get("TTS_MODEL", "gemini-3.1-flash-tts-preview")
OUTPUT_DIR = Path(__file__).parent.parent / "assets" / "videos"

# Calm male default
DEFAULT_VOICE = "Charon"


def generate_speech(
    text: str,
    voice: str = DEFAULT_VOICE,
    output_name: str = "",
    style_instruction: str = "",
) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    if not output_name:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe = text[:30].replace(" ", "_").replace("/", "-").replace(",", "")
        output_name = f"tts_{ts}_{safe}"
    output_path = OUTPUT_DIR / f"{output_name}.wav"

    print(f"\n{'='*60}")
    print(f"Model  : {MODEL}")
    print(f"Voice  : {voice}")
    print(f"Text   : {text[:120]}{'...' if len(text) > 120 else ''}")
    print(f"Output : {output_path}")
    print(f"{'='*60}")
    print("Generating...", flush=True)

    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)

    # Build prompt — optional style instruction prepended
    full_prompt = text
    if style_instruction:
        full_prompt = f"{style_instruction}\n\n{text}"

    response = client.models.generate_content(
        model=MODEL,
        contents=[types.Content(role="user", parts=[types.Part(text=full_prompt)])],
        config=types.GenerateContentConfig(
            response_modalities=["AUDIO"],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice),
                ),
            ),
        ),
    )

    # Extract audio bytes
    audio_bytes = None
    mime = None
    for cand in response.candidates or []:
        for part in cand.content.parts or []:
            if part.inline_data and part.inline_data.data:
                audio_bytes = part.inline_data.data
                mime = part.inline_data.mime_type
                break
        if audio_bytes:
            break

    if not audio_bytes:
        raise RuntimeError("No audio in response: " + str(response))

    # Gemini returns raw PCM (audio/L16;rate=24000). Wrap into WAV.
    # Parse mime for sample rate
    sample_rate = 24000
    if mime and "rate=" in mime:
        try:
            sample_rate = int(mime.split("rate=")[1].split(";")[0])
        except Exception:
            pass

    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(sample_rate)
        wf.writeframes(audio_bytes)

    size_kb = output_path.stat().st_size / 1024
    duration_sec = len(audio_bytes) / (sample_rate * 2)
    print(f"Saved  : {output_path}  ({size_kb:.0f} KB, ~{duration_sec:.1f}s)")
    return output_path


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print("Usage: python3 tts_generate.py '<text>' [--voice <name>] [--style '<style>'] [--name <name>]")
        print("Voices: Charon (default calm male), Aoede, Puck, Zephyr, Fenrir, etc.")
        sys.exit(0 if args else 1)

    text = args[0]
    voice = DEFAULT_VOICE
    style = ""
    name = ""

    i = 1
    while i < len(args):
        a = args[i]
        if a == "--voice" and i + 1 < len(args):
            voice = args[i + 1]; i += 2
        elif a == "--style" and i + 1 < len(args):
            style = args[i + 1]; i += 2
        elif a == "--name" and i + 1 < len(args):
            name = args[i + 1]; i += 2
        else:
            i += 1

    generate_speech(text, voice, name, style)
