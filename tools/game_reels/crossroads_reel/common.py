"""Shared paths; generated media always stays outside tracked sources."""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[3]
REFERENCE = Path(__file__).resolve().parent / "reference"


def output_dir():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--out", required=True, type=Path)
    args, _ = parser.parse_known_args()
    path = args.out.resolve()
    if not any(parent in path.parents for parent in (ROOT / "output", ROOT / "scratch")):
        raise SystemExit("--out must be a child of this checkout's output/ or scratch/")
    return path
