"""Copy a verified sign episode to Desktop without overwriting a different file."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--destination", type=Path, default=Path.home() / "Desktop")
    args = parser.parse_args()
    root = args.out.resolve()
    recipe = json.loads((root / "episode.json").read_text())
    proof = json.loads((root / "verification.json").read_text())
    for kind in ("voice", "video"):
        audit = json.loads((root / f"{kind}-audit.json").read_text())
        if not audit.get("passed"):
            raise ValueError(f"{kind} audit requires review")
    name = recipe["output_name"]
    if name != f"sign_{int(recipe['id']):03d}.mp4":
        raise ValueError("Unexpected delivery file name")
    source = root / name
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != proof["sha256"]:
        raise ValueError("Video changed after export verification")
    if abs(proof["audio_duration"] - proof["video_duration"]) > 1 / 30:
        raise ValueError("Audio/video duration mismatch")
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(source), "-f", "null", "-"], check=True)
    target = args.destination / name
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
        raise FileExistsError(f"A different file already exists: {target}")
    shutil.copy2(source, target)
    result = {"episode": recipe["id"], "candidate_id": recipe.get("candidate_id"),
              "file": str(target), "sha256": digest, "duration": proof["duration"],
              "resolution": [1080, 1920], "fps": 30}
    (root / "delivery.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
