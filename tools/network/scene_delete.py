"""Remove a game question, keeping its originals and shared model resources.

The server serializes describe/delete with BUILD_LOCK. Exam questions and images
are read only; the plan decision and tombstones prevent a stale editor from
creating the deleted question again.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import uuid

from question_pool import DECISION_LOCK


class SceneDeleteConflict(ValueError):
    pass


class SceneDeleteNotFound(LookupError):
    pass


def _json(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def _tombstones_path(history: Path, network: Path | None = None) -> Path:
    # Unlike the local recovery archive, this registry must travel with the game
    # sources in Git so a different machine cannot recreate a deleted question.
    return Path(network or Path(history).parent) / "question_review" / "deleted.json"


def _tombstones(history: Path, network: Path | None = None) -> dict:
    data = _json(_tombstones_path(history, network), {"schema": 1, "deleted": {}})
    if data.get("schema") != 1 or not isinstance(data.get("deleted"), dict):
        raise ValueError("Неизвестный формат истории удаления")
    return data


def is_deleted(sid: str, history: Path, network: Path | None = None) -> bool:
    return sid in _tombstones(history, network)["deleted"]


def _road_matches(road: dict, ids: set[str], sources: list[dict]) -> bool:
    if road.get("category", "ab") != "ab":
        return False
    match = re.fullmatch(r"road_(\d+)_(\d+)", road.get("id", ""))
    if match:
        return f"ticket_{match[1]}_{match[2]}" in ids
    return bool(road.get("sourceQuestionId")) and any(
        road["sourceQuestionId"] == source["sourceQuestionId"]
        and road.get("sourceImage") == source.get("image") for source in sources)


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _shared_references(ids: set[str], network: Path, situations: Path) -> dict:
    references = {sid: [] for sid in ids}
    files = [(p, f"network/{p.name}") for p in sorted(network.glob("*.json")) if p.stem not in ids]
    for name in ("engine.json", "scene.json"):
        files += [(p, f"situations/{p.parent.name}/{name}")
                  for p in sorted(situations.glob(f"*/{name}")) if p.parent.name not in ids]
    for path, label in files:
        values = tuple(_strings(_json(path, {})))
        for sid in ids:
            if any(value.startswith(sid + "/") or f"/{sid}/" in value for value in values):
                references[sid].append(label)
    return {sid: paths for sid, paths in sorted(references.items()) if paths}


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    if path.is_symlink():
        digest.update(b"symlink:" + os.fsencode(os.readlink(path)))
    elif path.is_dir():
        digest.update(b"directory:")
        for child in sorted(path.iterdir()):
            digest.update(child.name.encode() + b"\0" + _digest(child).encode() + b"\0")
    elif path.exists():
        digest.update(b"file:")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    else:
        digest.update(b"missing")
    return digest.hexdigest()


def _inspect(sid: str, pool, situations: Path, history: Path):
    if not isinstance(sid, str) or not re.fullmatch(r"ticket_\d+_\d+", sid) or is_deleted(sid, history, pool.network):
        raise SceneDeleteNotFound("Сцена уже удалена или не найдена")
    network, situations, history = Path(pool.network), Path(situations), Path(history)
    group = next((q for q in pool.list()["questions"]
                  if any(item["id"] == sid for item in q["occurrences"])), None)
    ids = [item["id"] for item in group["occurrences"]] if group else [sid]
    canonical = group["id"] if group else sid
    sources = [source for item in ids if (source := pool.source(item))]
    roads_path = network.parent / "roads" / "road_scenes.json"
    roads = _json(roads_path, {"scenes": []})
    if not isinstance(roads.get("scenes"), list):
        raise ValueError("Неизвестный формат дорожных вопросов")
    road_entries = [road for road in roads["scenes"] if _road_matches(road, set(ids), sources)]
    copies = []
    for item in ids:
        source = pool.source(item) or {}
        copies.append({"id": item, "ticket": source.get("ticket"), "number": source.get("number"),
                       "hasScene": (network / f"{item}.json").exists() or (situations / item / "scene.json").exists(),
                       "hasRoadQuestion": any(_road_matches(road, {item}, [source] if source else []) for road in road_entries)})
    if group is None and not any(copy["hasScene"] for copy in copies):
        raise SceneDeleteNotFound("Сцена не найдена")
    references = _shared_references(set(ids), network, situations)
    paths = []
    for item in ids:
        paths += [(network / f"{item}.json", f"network/{item}.json"),
                  (network / "build" / f"{item}.json", f"network/build/{item}.json"),
                  (network / "preview" / f"{item}.png", f"network/preview/{item}.png"),
                  (situations / item, f"situations/{item}")]
    paths += [(situations / "index.json", "situations/index.json"),
              (roads_path, "roads/road_scenes.json"),
              (pool.decisions_path, "network/question_review/decisions.json"),
              (_tombstones_path(history, network), "network/question_review/deleted.json"),
              (history / ".gdignore", "history/.gdignore")]
    fingerprint = {"id": canonical, "ids": ids, "group": group, "references": references,
                   "files": [(label, _digest(path)) for path, label in paths]}
    revision = hashlib.sha256(json.dumps(fingerprint, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    info = {"id": canonical, "ids": ids, "copies": copies,
            "hasScene": any(copy["hasScene"] for copy in copies),
            "hasRoadQuestion": bool(road_entries), "roadIds": [road.get("id") for road in road_entries],
            "hasSharedAssets": bool(references), "sharedAssetIds": list(references), "revision": revision}
    return info, paths, group, roads, road_entries


def describe(sid: str, pool, situations: Path, history: Path) -> dict:
    """Read-only deletion scope. IDs include every occurrence of the exact task."""
    with DECISION_LOCK:
        return _inspect(sid, pool, situations, history)[0]


def _atomic_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".delete-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def _remove(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def _copy(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir() and not source.is_symlink():
        shutil.copytree(source, target, symlinks=True)
    else:
        shutil.copy2(source, target, follow_symlinks=False)


def delete(sid: str, revision: str, pool, situations: Path, history: Path) -> dict:
    """Archive, then remove exactly the confirmed question; roll back on failure."""
    with DECISION_LOCK:
        info, paths, group, roads, road_entries = _inspect(sid, pool, situations, history)
        if not revision or revision != info["revision"]:
            raise SceneDeleteConflict("Сцена изменилась. Подтвердите удаление ещё раз")
        network, situations, history = Path(pool.network), Path(situations), Path(history)
        index_path = situations / "index.json"
        index = _json(index_path, [])
        if not isinstance(index, list) or not all(isinstance(item, str) for item in index):
            raise ValueError("Неизвестный формат списка сцен")
        decisions = _json(pool.decisions_path, {"schema": 1, "decisions": {}})
        pool.decisions()  # Validate without discarding any extra metadata.
        tombstones = _tombstones(history, network)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        archive = history / "deleted" / f"{stamp}-{info['id']}-{uuid.uuid4().hex[:8]}"
        pending = archive.with_name(".pending-" + archive.name)
        pending.mkdir(parents=True)
        originals = [(path, label) for path, label in paths if path.exists() or path.is_symlink()]
        mutated = False
        try:
            for path, label in originals:
                _copy(path, pending / label)
            # Also catch outside edits made while a large asset directory was copied.
            if _inspect(sid, pool, situations, history)[0]["revision"] != revision:
                raise SceneDeleteConflict("Сцена изменилась. Подтвердите удаление ещё раз")
            _atomic_json(pending / "manifest.json", {"schema": 1, **info, "deletedAt": stamp,
                                                     "originals": [label for _, label in originals]})
            os.replace(pending, archive)
            mutated = True
            for item in info["ids"]:
                for path in (network / f"{item}.json", network / "build" / f"{item}.json",
                             network / "preview" / f"{item}.png"):
                    _remove(path)
                # Other questions may still use this export's actor/light models.
                _remove(situations / item / "scene.json" if item in info["sharedAssetIds"] else situations / item)
            if index_path.exists():
                _atomic_json(index_path, [item for item in index if item not in info["ids"]])
            if road_entries:
                remaining = [road for road in roads["scenes"] if road not in road_entries]
                _atomic_json(network.parent / "roads" / "road_scenes.json", {**roads, "scenes": remaining, "count": len(remaining)})
            if group:
                decisions["decisions"][info["id"]] = "no"
                _atomic_json(pool.decisions_path, decisions)
            for item in info["ids"]:
                tombstones["deleted"][item] = {"id": info["id"], "archive": archive.name}
            if not (history / ".gdignore").exists():
                (history / ".gdignore").touch()
            _atomic_json(_tombstones_path(history, network), tombstones)
        except Exception:
            if mutated:
                # The full original directory is available even when only scene.json
                # was removed, so failed shared-model deletions restore exactly too.
                for path, label in paths:
                    _remove(path)
                    if (archive / label).exists() or (archive / label).is_symlink():
                        _copy(archive / label, path)
            _remove(pending)
            _remove(archive)
            raise
        return {**info, "archive": str(archive)}
