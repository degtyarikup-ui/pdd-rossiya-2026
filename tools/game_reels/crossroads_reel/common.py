"""Shared paths; generated media always stays outside tracked sources."""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parents[3]
REFERENCE = Path(__file__).resolve().parent / "reference"


def validate_episode_format(episode):
    """Preserve archived recipes; require a direct question from episode 007."""
    match = re.fullmatch(r"crossroads-(\d+)", episode.get("id", ""))
    if not match or int(match[1]) < 7:
        return
    lines = episode.get("lines", [])
    opening = lines[0].get("text", "").strip() if lines else ""
    if (not episode.get("directQuestion") or not lines
            or lines[0].get("key") != "hook"
            or not opening.endswith("?") or opening.count("?") != 1
            or re.search(r"[.!…]", opening)
            or any(line.get("key") == "setup" for line in lines)):
        raise SystemExit("Episodes 007+ must start with one direct question, use directQuestion=true, and have no setup narration")

    if int(match[1]) >= 8:
        kinds = episode.get("participantTypes", {})
        models = episode.get("carModels", {})
        cars = [key for key, kind in kinds.items() if kind == "car"]
        shapes = [models.get(key) for key in cars]
        if not kinds or any(shape not in ("hatch", "sedan", "coupe", "wagon", "suv", "pickup") for shape in shapes) or len(set(shapes)) != len(shapes):
            raise SystemExit("Episodes 008+ must declare participantTypes and distinct carModels for passenger cars")


def output_dir():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--out", required=True, type=Path)
    args, _ = parser.parse_known_args()
    path = args.out.resolve()
    if not any(parent in path.parents for parent in (ROOT / "output", ROOT / "scratch")):
        raise SystemExit("--out must be a child of this checkout's output/ or scratch/")
    return path
