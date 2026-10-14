#!/usr/bin/env python3
"""Share existing studio recordings with Godot, without another copy in its pack.

Godot cannot decode the canonical Ogg Opus recordings, so only questions used by
Living City are converted to MP3 in the shared Flutter asset folder. No speech
is synthesized. --check validates the content, cache and index without rebuilding;
--standalone links the shared MP3s temporarily for a game exported without Flutter.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
VERSION = 1
ENCODER = "libmp3lame-q2-mono-v1"
QUESTION_ID = re.compile(r"[a-f0-9]{32}")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scene_questions(root):
    """Resolve the original question, and reject changed game text/answer order."""
    tickets = read_json(root / "assets/countries/ru/questions/questions_ab.json")["tickets"]
    questions = {q["id"]: q for t in tickets for q in t["questions"]}
    out = {}

    def add(scene_id, question, title, options):
        raw_id = question["id"]
        if not QUESTION_ID.fullmatch(raw_id):
            raise ValueError(f"Invalid source question id: {scene_id}")
        if title != question["question"] or options != [a["text"] for a in question["answers"]]:
            raise ValueError(f"Studio recording does not match question/answers: {scene_id}")
        if scene_id in out:
            raise ValueError(f"Duplicate audio scene: {scene_id}")
        out[scene_id] = raw_id

    for scene_id in read_json(root / "game_godot/situations/index.json"):
        match = re.fullmatch(r"ticket_(\d+)_(\d+)", scene_id)
        if match is None:
            raise ValueError(f"No original studio question for scene: {scene_id}")
        ticket, number = map(int, match.groups())
        if ticket < 1 or number < 1:
            raise ValueError(f"Invalid ticket number: {scene_id}")
        question = tickets[ticket - 1]["questions"][number - 1]
        scene = read_json(root / f"game_godot/situations/{scene_id}/scene.json")
        text = scene["text"]["ru"]
        add(scene_id, question, text["title"], text["options"])
    for scene in read_json(root / "game_godot/roads/road_scenes.json")["scenes"]:
        if scene.get("category", "ab") != "ab":
            raise ValueError(f"Living City studio audio requires AB source: {scene['id']}")
        question = questions[scene["sourceQuestionId"]]
        add(scene["id"], question, scene["title"], scene["options"])
    return out


def encode(source, destination):
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(source), "-map_metadata", "-1", "-ac", "1", "-codec:a",
        "libmp3lame", "-q:a", "2", str(destination),
    ], check=True)
    result = subprocess.run([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(destination),
    ], check=True, capture_output=True, text=True)
    duration = round(float(result.stdout.strip()), 4)
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError(f"Invalid studio recording duration: {source.name}")
    return duration


def remove_links(root):
    folder = root / "game_godot/question_audio"
    if not folder.exists():
        return
    for pattern in ("*.mp3", "*.mp3.import"):
        for path in folder.glob(pattern):
            path.unlink()


def export(root=ROOT, *, check=False, standalone=False):
    scenes = scene_questions(root)
    output = root / "assets/audio/game_questions"
    cache_path = output / ".manifest.json"
    index_path = root / "game_godot/questions/audio.json"
    ids = sorted(set(scenes.values()))
    sources = {raw_id: root / f"assets/audio/feed/q_{raw_id}.opus" for raw_id in ids}
    for source in sources.values():
        if not source.is_file():
            raise FileNotFoundError(f"Missing studio recording: {source}")
    try:
        cache = read_json(cache_path)
    except (FileNotFoundError, ValueError):
        cache = {}
    if cache.get("encoder") != ENCODER:
        cache = {}
    previous = cache.get("clips", {})
    fresh = {}
    pending = []
    for raw_id, source in sources.items():
        file_name = f"q_{raw_id}.mp3"
        destination = output / file_name
        source_hash = digest(source)
        saved = previous.get(raw_id, {})
        duration = saved.get("duration", 0)
        valid = (
            saved.get("source_sha256") == source_hash
            and isinstance(duration, (int, float)) and math.isfinite(duration) and duration > 0
            and destination.is_file()
            and saved.get("mp3_sha256") == digest(destination)
        )
        if valid:
            fresh[raw_id] = saved
        elif check:
            raise ValueError(f"Missing or stale shared studio MP3: {file_name}; run export_question_audio.py")
        else:
            pending.append((raw_id, source, destination, source_hash))

    if pending:
        for tool in ("ffmpeg", "ffprobe"):
            if shutil.which(tool) is None:
                raise RuntimeError(f"{tool} is required to prepare studio audio (install FFmpeg)")
        output.mkdir(parents=True, exist_ok=True)
        scratch = root / "scratch"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="question-audio-", dir=scratch) as temporary:
            def convert(item):
                raw_id, source, destination, source_hash = item
                staged = Path(temporary) / destination.name
                duration = encode(source, staged)
                mp3_hash = digest(staged)
                os.replace(staged, destination)
                return raw_id, {"source_sha256": source_hash, "mp3_sha256": mp3_hash, "duration": duration}
            with ThreadPoolExecutor(max_workers=4) as pool:
                fresh.update(pool.map(convert, pending))

    index = {"version": VERSION, "language": "ru", "clips": {
        scene_id: {"file": f"q_{raw_id}.mp3", "duration": fresh[raw_id]["duration"], "sourceQuestionId": raw_id}
        for scene_id, raw_id in sorted(scenes.items())
    }}
    if check:
        if not index_path.is_file() or read_json(index_path) != index:
            raise ValueError("Missing or stale questions/audio.json; run export_question_audio.py")
    else:
        output.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps({"encoder": ENCODER, "clips": fresh}, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        wanted = {f"q_{raw_id}.mp3" for raw_id in ids}
        for old in output.glob("q_*.mp3"):
            if re.fullmatch(r"q_[a-f0-9]{32}\.mp3", old.name) and old.name not in wanted:
                old.unlink()
        index_path.parent.mkdir(parents=True, exist_ok=True)
        index_path.write_text(json.dumps(index, indent=1) + "\n", encoding="utf-8")
        remove_links(root)
        if standalone:
            links = root / "game_godot/question_audio"
            links.mkdir(parents=True, exist_ok=True)
            for raw_id in ids:
                source = output / f"q_{raw_id}.mp3"
                destination = links / source.name
                destination.symlink_to(os.path.relpath(source, links))
                destination.with_suffix(".mp3.import").write_text('[remap]\n\nimporter="keep"\n', encoding="utf-8")
    return index, len(pending), sum((output / f"q_{raw_id}.mp3").stat().st_size for raw_id in ids)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="verify existing audio and index without converting")
    mode.add_argument("--standalone", action="store_true", help="temporarily link MP3s for a game without Flutter")
    mode.add_argument("--clean-links", action="store_true", help="remove temporary standalone links only")
    args = parser.parse_args()
    if args.clean_links:
        remove_links(ROOT)
        return
    index, converted, total_bytes = export(check=args.check, standalone=args.standalone)
    print(f"{len(index['clips'])} scenes, {len(set(c['file'] for c in index['clips'].values()))} shared studio clips, "
          f"{converted} converted, {total_bytes / 1_000_000:.2f} MB" + (" (temporary standalone links)" if args.standalone else " (no game-pack copies)"))


if __name__ == "__main__":
    main()
