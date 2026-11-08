"""Save a verified episode to the user's Desktop as game_NNN.mp4."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import tempfile

from common import output_dir


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    dest = output_dir()
    episode = json.loads((dest / "episode.json").read_text())
    match = re.fullmatch(r"crossroads-(\d+)", episode["id"])
    if not match or int(match[1]) < 1:
        raise SystemExit("Episode id must contain a positive episode number")
    name = f"game_{int(match[1]):03d}.mp4"
    source = dest / "reel.mp4"
    checks = json.loads((dest / "export-checks.json").read_text())
    expected = checks["sha256"]
    if checks.get("decode") != "passed" or digest(source) != expected:
        raise SystemExit("Run check on this exact video before delivery")
    desktop = Path.home() / "Desktop"
    if not desktop.is_dir():
        raise SystemExit(f"Desktop directory not found: {desktop}")
    target = desktop / name
    if target.exists() and digest(target) != expected:
        # Preserve the previous delivery before replacing this episode's file.
        backup = dest / "previous-delivery" / f"{target.stem}_{digest(target)}.mp4"
        backup.parent.mkdir(exist_ok=True)
        shutil.copy2(target, backup)
    if not target.exists() or digest(target) != expected:
        with tempfile.NamedTemporaryFile(prefix=f".{target.stem}-", suffix=".mp4", dir=desktop, delete=False) as handle:
            temporary = Path(handle.name)
        try:
            shutil.copy2(source, temporary)
            if digest(temporary) != expected:
                raise RuntimeError("Delivery copy differs from the verified export")
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
    (dest / "delivery.json").write_text(json.dumps({"episode": episode["id"], "file": name, "path": str(target), "sha256": expected}, indent=2) + "\n")
    print(f"DELIVERY_OK {target}")


if __name__ == "__main__":
    main()
