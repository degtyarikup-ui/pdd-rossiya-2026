#!/usr/bin/env python3
"""Reproduce the approved crossroads pilot; see docs/video/reels_3d.md."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys

from common import ROOT, REFERENCE, output_dir

TOOLS = Path(__file__).resolve().parent
SCENE = "res://videos/crossroads_reel/"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("step", choices=["init", "voice", "plan", "align", "validate", "render", "preview", "finish", "check"])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--at", default="0,6,14.8,19.7,26.9,30.4")
    parser.add_argument("--model", type=Path, default=ROOT / "scratch/whisper/ggml-large-v3-turbo.bin")
    args = parser.parse_args()
    dest = output_dir()
    if args.step == "init":
        dest.mkdir(parents=True, exist_ok=True)
        # Never overwrite the timeline or reviewed captions of an existing run.
        for name in ["episode.json", "voice.json", "timeline.json", "subtitles.json"]:
            if (dest / name).exists():
                raise SystemExit(f"Already initialised: {dest / name}")
        for name in ["episode.json", "voice.json", "timeline.json", "subtitles.json"]:
            shutil.copyfile(REFERENCE / name, dest / name)
        print(f"INIT_OK {dest}")
        return
    if not (dest / "timeline.json").is_file():
        raise SystemExit("Run init first")
    if args.step in ("voice", "plan", "finish", "check"):
        file = "check_export.py" if args.step == "check" else f"{args.step}.py"
        cmd = [sys.executable, str(TOOLS / file), "--out", str(dest)]
        if args.step == "finish":
            cmd += ["--audio", "--encode"]
        subprocess.run(cmd, check=True)
    elif args.step == "align":
        if not args.model.is_file():
            raise SystemExit(f"Whisper model not found: {args.model}")
        for line in json.loads((dest / "voice.json").read_text()):
            subprocess.run(["whisper-cli", "-m", str(args.model), "-f", str(dest / line["path"]),
                            "-l", "ru", "-ojf", "-of", str(dest / "audio" / f"{line['key']}-align"),
                            "-ml", "1", "-sow", "-t", "4"], check=True)
    elif args.step in ("validate", "render", "preview"):
        script = "validate.gd" if args.step == "validate" else "render.gd"
        cmd = ["godot", "--rendering-method", "forward_plus"]
        if args.step == "validate":
            cmd += ["--headless"]
        cmd += ["--path", str(ROOT / "game_godot"), "--script", SCENE + script, "--", f"--data={dest}"]
        if args.step == "preview":
            cmd += [f"--at={args.at}", f"--out={dest / 'preview-frames'}"]
        if args.step == "validate":
            result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (dest / "validation.log").write_text(result.stdout)
            print(result.stdout)
            result.check_returncode()
        else:
            subprocess.run(cmd, check=True)
        if args.step == "preview":
            # Only the reference timing is used for this silent visual check.
            subprocess.run([sys.executable, str(TOOLS / "finish.py"), "--out", str(dest),
                            "--reference-captions", "--preview-dir", "preview-frames"], check=True)


if __name__ == "__main__":
    main()
