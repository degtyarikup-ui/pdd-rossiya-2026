"""Generate and independently align the narration for a sign-choice reel."""
from __future__ import annotations

import argparse
import concurrent.futures
import difflib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import warnings

warnings.filterwarnings("ignore")
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.signs_reel import audio, verify

STYLE = (
    "Говори по-русски, живо и уверенно, как доброжелательный ведущий короткой "
    "викторины. Разговорная интонация, чёткая дикция, энергичный, но комфортный "
    "темп. Не растягивай слова. Вопрос произнеси с искренним интересом. "
    "ПДД произноси по буквам: пэ дэ дэ. Без смеха, вздохов, музыки и звуков. "
    "Произноси только заданный текст, ничего не добавляй."
)


def configure_google():
    from google import genai
    from google.oauth2.credentials import Credentials

    adc = Path.home() / ".config/gcloud/application_default_credentials.json"
    if adc.exists():
        return
    project = subprocess.check_output(
        ["gcloud", "config", "get-value", "project"],
        text=True, stderr=subprocess.DEVNULL,
    ).strip()
    if not project or project == "(unset)":
        raise RuntimeError("No active Google Cloud project")
    os.environ["GOOGLE_CLOUD_PROJECT"] = project
    token = subprocess.check_output(
        ["gcloud", "auth", "print-access-token"],
        text=True, stderr=subprocess.DEVNULL,
    ).strip()
    original = genai.Client

    def active_client(*args, **kwargs):
        kwargs["credentials"] = Credentials(token)
        kwargs.setdefault("http_options", {"timeout": 120000})
        return original(*args, **kwargs)

    genai.Client = active_client


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--recipe", type=Path, default=Path(__file__).with_name("episode_001.json"))
    p.add_argument("--model", type=Path, default=ROOT / "scratch/whisper/ggml-large-v3-turbo.bin")
    p.add_argument("--reuse-from", type=Path, help="Reuse identical cached takes from a prior run")
    args = p.parse_args()
    dest = args.out.resolve()
    (dest / "audio").mkdir(parents=True, exist_ok=True)
    recipe = json.loads(args.recipe.read_text())
    (dest / "episode.json").write_text(json.dumps(recipe, ensure_ascii=False, indent=2) + "\n")
    configure_google()
    vc = audio.VoiceConfig(voice=recipe["voice"], style=STYLE)

    def one(line):
        key, text = line["key"], line["text"]
        raw = dest / "audio" / f"{key}_{audio.tts_cache_key(text, vc)}.wav"
        target = dest / "audio" / f"{key}.wav"
        if args.reuse_from and not raw.exists():
            previous = args.reuse_from / "audio" / raw.name
            if previous.is_file():
                shutil.copy2(previous, raw)
        audio.synthesize(text, raw, vc, attempts=3)
        pcm = audio.trim_silence(audio.read_wav(raw), pad=0.075)
        audio.write_wav(target, pcm)
        print(f"SPEECH {key}: {len(pcm) / 24000:.3f}s", flush=True)
        return dict(line, path=f"audio/{key}.wav", duration=len(pcm) / 24000)

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        lines = list(pool.map(one, recipe["lines"]))
    (dest / "voice.json").write_text(json.dumps(lines, ensure_ascii=False, indent=2) + "\n")

    for line in lines:
        prefix = dest / "audio" / f"{line['key']}-align"
        log = prefix.with_suffix(".log")
        for take in range(3):
            with log.open("w") as handle:
                subprocess.run([
                    "whisper-cli", "-m", str(args.model), "-f", str(dest / line["path"]),
                    "-l", "ru", "-ojf", "-of", str(prefix), "-ml", "1", "-sow", "-t", "4",
                ], check=True, stdout=handle, stderr=subprocess.STDOUT)
            raw = json.loads(prefix.with_suffix(".json").read_text())
            segments = raw["transcription"]
            heard = " ".join(s["text"].strip() for s in segments)
            want_tokens = verify.normalize(line["text"])
            got_tokens = verify.normalize(heard)
            score = difflib.SequenceMatcher(None, want_tokens, got_tokens).ratio()
            spacing_only = "".join(want_tokens) == "".join(got_tokens)
            if spacing_only or (score >= 0.85 and len(want_tokens) == len(got_tokens)):
                break
            if take == 2:
                raise RuntimeError(f"Narration mismatch for {line['key']}: {heard} ({score:.2f})")
            print(f"RETAKE {line['key']}: {heard}", flush=True)
            cached = dest / "audio" / f"{line['key']}_{audio.tts_cache_key(line['text'], vc)}.wav"
            cached.unlink(missing_ok=True)
            fresh = one(line)
            line.update(duration=fresh["duration"])
        words = []
        for s in segments:
            if not verify.normalize(s["text"]):
                continue
            words.append({"text": s["text"].strip(), "start": s["offsets"]["from"] / 1000,
                          "end": s["offsets"]["to"] / 1000})
        if spacing_only and len(words) != len(want_tokens):
            # E.g. ASR writes "почетным" for the identically sounding "по чётным".
            # Accept only an exact normalized character match. Keep all ordinary
            # boundaries; split a merged segment proportionally within that word.
            clock = []
            for word in words:
                chars = "".join(verify.normalize(word["text"]))
                for i in range(len(chars)):
                    step = (word["end"] - word["start"]) / len(chars)
                    clock.append((word["start"] + i * step, word["start"] + (i + 1) * step))
            aligned, offset = [], 0
            expected = [w for w in line["text"].split() if verify.normalize(w)]
            for word in expected:
                size = len("".join(verify.normalize(word)))
                aligned.append({"text": word, "start": clock[offset][0], "end": clock[offset + size - 1][1]})
                offset += size
            words = aligned
            line["alignment_note"] = "Exact character match; repaired ASR word spacing inside merged segments."
            score = 1.0
        line.update(transcription=heard, similarity=score, words=words)
        print(f"ALIGN {line['key']}: {score:.3f} {heard}", flush=True)
    (dest / "voice.json").write_text(json.dumps(lines, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
