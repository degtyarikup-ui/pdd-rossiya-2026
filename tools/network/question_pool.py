"""Unbuilt A/B exam questions and the author's first-pass decisions.

Reading the pool never creates hundreds of editable scenes or game assets. A scene is
generated in memory when opened and materialised by the editor's ordinary Save action.
The ``questionPool`` marker keeps that saved draft in the pool until explicit promotion.
"""
from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import tempfile
import threading
from functools import lru_cache
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DECISION_LOCK = threading.RLock()


def scene_id(category: str, ticket: int, number: int) -> str:
    if category != "ab":
        raise ValueError("В редакторе используются только вопросы A/B")
    return f"ticket_{ticket}_{number}"


def _words(value: str) -> tuple:
    # Ignore typography and hyphenation while preserving word/number boundaries.
    # The illustration distinguishes different tasks with a generic title.
    return tuple(re.findall(r"[a-zа-я0-9]+", value.casefold().replace("ё", "е")))


def _fingerprint(question: dict) -> tuple:
    return (_words(question["question"]),
            tuple((_words(a["text"]), a["correct"] is True) for a in question["answers"]),
            question.get("image"))


@lru_cache(maxsize=1)
def _geometry_template() -> dict:
    """Use the real road-plan generator, with none of the legacy baked scenery."""
    script = """
const Layout = require(process.argv[1]);
const scene = {schema:1,id:'question_template',crop:90,roads:[],markings:[],lawns:[],
  routes:[],actors:[],lights:[],decor:[],question:{maneuver:'straight'}};
scene.layout = Layout.template('cross', 90);
for (const street of scene.layout.streets) {
  Object.assign(street,{kind:'avenue',edge:false,centre:'solid',ends:{}});
}
Layout.apply(scene);
process.stdout.write(JSON.stringify(scene));
"""
    result = subprocess.run(["node", "-e", script, str(HERE / "editor" / "layout.js")],
                            check=True, capture_output=True, text=True, timeout=30)
    return json.loads(result.stdout)


class QuestionPool:
    def __init__(self, questions: Path | None = None, network: Path | None = None,
                 images: Path | None = None):
        self.questions = questions or ROOT / "assets" / "countries" / "ru" / "questions"
        self.network = network or ROOT / "game_godot" / "network"
        self.images = images or ROOT / "assets" / "countries" / "ru" / "images"
        self.decisions_path = self.network / "question_review" / "decisions.json"
        self._source_stamp = None
        self._sources = {}
        self._groups = []

    def _load_sources(self) -> None:
        # The author reviews only the A/B collection. In particular, old saved
        # C/D decisions must never bring C/D questions back into this list.
        paths = [self.questions / "questions_ab.json"]
        stamp = tuple((p.stat().st_mtime_ns, p.stat().st_size) if p.exists() else None for p in paths)
        if stamp == self._source_stamp:
            return
        sources, records = {}, []
        for category, path in zip(("ab",), paths):
            if not path.exists():
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            for ti, ticket in enumerate(data["tickets"], 1):
                ticket_number = int(ticket.get("number", ti))
                for number, question in enumerate(ticket["questions"], 1):
                    sid = scene_id(category, ticket_number, number)
                    image = question.get("image")
                    record = {"id": sid, "ticket": ticket_number, "number": number,
                              "category": category, "categories": [category],
                              "question": question["question"], "answers": question["answers"],
                              "comment": question.get("comment", ""), "image": image,
                              "imageUrl": f"/asset/source/{category}/{image}.webp" if image else None,
                              "sourceQuestionId": question["id"], "topic": question.get("topic", []),
                              "pddPoints": question.get("pddPoints", [])}
                    sources[sid] = record
                    records.append(record)
        # Only merge the same full task AND illustration. Source IDs alone are
        # not unique: AB 5/12 and 24/12 share one but show different parking.
        # Removing C/D also removes its transitive links between distinct A/B
        # illustrations; existing A/B representatives keep their decision keys.
        grouped = {}
        for record in records:
            key = _fingerprint(record)
            if key not in grouped:
                grouped[key] = {**record, "categories": ["ab"], "occurrences": []}
            group = grouped[key]
            group["occurrences"].append({k: record[k] for k in ("id", "ticket", "number", "category", "sourceQuestionId")})
        groups = list(grouped.values())
        self._sources, self._groups, self._source_stamp = sources, groups, stamp

    def source(self, sid: str) -> dict | None:
        self._load_sources()
        source = self._sources.get(sid)
        return copy.deepcopy(source) if source else None

    def decisions(self) -> dict:
        with DECISION_LOCK:
            if not self.decisions_path.exists():
                return {}
            data = json.loads(self.decisions_path.read_text(encoding="utf-8"))
            if data.get("schema") != 1 or not isinstance(data.get("decisions"), dict):
                raise ValueError("Неизвестный формат сохранённых решений по вопросам")
            return data["decisions"]

    def list(self) -> dict:
        self._load_sources()
        implemented, drafts = set(), set()
        for path in self.network.glob("ticket_*.json"):
            if not re.fullmatch(r"ticket_\d+_\d+", path.stem):
                continue
            scene = json.loads(path.read_text(encoding="utf-8"))
            # Authored assistant scenes have their own review queue, including
            # before approval. They must not appear again as unbuilt questions.
            assistant = (scene.get("assistantReview") or {}).get("author") == "codex"
            (drafts if scene.get("questionPool") and not assistant else implemented).add(path.stem)
        roads_path = self.network.parent / "roads" / "road_scenes.json"
        if roads_path.exists():
            roads = json.loads(roads_path.read_text(encoding="utf-8"))
            for scene in roads.get("scenes", []):
                if scene.get("category", "ab") != "ab":
                    continue
                match = re.fullmatch(r"road_(\d+)_(\d+)", scene.get("id", ""))
                if match:
                    implemented.add(scene_id(scene.get("category", "ab"), int(match[1]), int(match[2])))
                elif scene.get("sourceQuestionId"):
                    # Legacy road exports without coordinates can still be
                    # matched safely by their source identity AND illustration.
                    implemented.update(sid for sid, source in self._sources.items()
                                       if source["category"] == scene.get("category", "ab")
                                       and source["sourceQuestionId"] == scene["sourceQuestionId"]
                                       and source["image"] == scene.get("sourceImage"))
        decisions = self.decisions()
        records = []
        for group in self._groups:
            ids = {item["id"] for item in group["occurrences"]}
            if ids & implemented:
                continue
            records.append({**copy.deepcopy(group), "decision": decisions.get(group["id"]),
                            "sceneExists": group["id"] in drafts})
        counts = {"total": len(records), "unreviewed": sum(q["decision"] is None for q in records),
                  "yes": sum(q["decision"] == "yes" for q in records),
                  "no": sum(q["decision"] == "no" for q in records)}
        return {"questions": records, "counts": counts}

    def get(self, sid: str) -> dict | None:
        return next((q for q in self.list()["questions"] if q["id"] == sid), None)

    def decide(self, sid: str, decision) -> dict:
        if decision not in (None, "yes", "no"):
            raise ValueError("Решение должно быть yes, no или null")
        record = self.get(sid)
        if record is None:
            raise KeyError(sid)
        with DECISION_LOCK:
            decisions = self.decisions()
            if decision is None:
                decisions.pop(sid, None)
            else:
                decisions[sid] = decision
            self.decisions_path.parent.mkdir(parents=True, exist_ok=True)
            data = {"schema": 1, "decisions": decisions}
            fd, temporary = tempfile.mkstemp(prefix=".decisions-", suffix=".json", dir=self.decisions_path.parent)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    json.dump(data, handle, ensure_ascii=False, indent=1, sort_keys=True)
                    handle.write("\n")
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary, self.decisions_path)
            finally:
                Path(temporary).unlink(missing_ok=True)
        return {**record, "decision": decision}

    def template(self, sid: str) -> dict:
        source = self.get(sid)
        if source is None:
            raise KeyError(sid)
        scene = copy.deepcopy(_geometry_template())
        scene.update({"id": sid, "frame": "junction centre (0, 0); +z = direction of travel; +x = driver's left",
                      "geometry": None, "type": "crossroad", "procedural": True,
                      "reviewed": False, "regulator": False, "staticScene": False,
                      "signs": [], "officers": [], "tracks": [], "questionCamera": [],
                      "compliance": {"status": "unverified"},
                      "questionPool": {k: source[k] for k in ("sourceQuestionId", "category", "ticket", "number")}})
        text = {}
        for language in ("ru", "en", "kk"):
            translated = self._translated(source, language)
            title = {"ru": f"Билет {source['ticket']} · Вопрос {source['number']}",
                     "en": f"Ticket {source['ticket']} · Question {source['number']}",
                     "kk": f"{source['ticket']}-билет · {source['number']}-сұрақ"}[language]
            text[language] = {"ticket": title, "title": translated["question"],
                              "options": [a["text"] for a in translated["answers"]],
                              "explanation": translated.get("comment", ""), "pddRule": ""}
        scene["question"] = {"text": text,
                             "correct": next(i for i, a in enumerate(source["answers"]) if a["correct"]),
                             "maneuver": "straight", "yieldTo": [], "showPlayerGuide": False,
                             "sourceQuestionId": source["sourceQuestionId"], "sourceCategory": source["category"],
                             "sourceImage": source["image"]}
        return scene

    def _translated(self, source: dict, language: str) -> dict:
        if language == "ru":
            return source
        path = self.questions / f"questions_{source['category']}_{language}.json"
        if path.exists():
            tickets = json.loads(path.read_text(encoding="utf-8"))["tickets"]
            question = tickets[source["ticket"] - 1]["questions"][source["number"] - 1]
            if question["id"] == source["sourceQuestionId"] and len(question["answers"]) == len(source["answers"]):
                return question
        return source


def engine_template(scene: dict) -> dict:
    """The smallest procedural game base; never inherit a different ticket's rules or models."""
    crop = float(scene.get("crop", 90))
    stop = scene["stop"]
    question = scene["question"]
    russian = question["text"].get("ru", {})
    # World warms the question card before the first approach and requires this
    # value even for a brand-new procedural scene with no legacy engine base.
    source_text_length = len(russian.get("title", "")) + sum(len(option) for option in russian.get("options", []))
    return {"id": scene["id"], "procedural": True, "geometry": None, "type": scene.get("type", "crossroad"),
            "reviewed": False, "regulator": False, "crop": crop,
            "centerZ": 0, "startZ": -crop, "stopZ": stop["z"], "playerStartX": stop["x"],
            "playerStartRotY": stop.get("yaw", 0), "leftLane": 1.75, "rightLane": 1.75,
            "kerbZ": 7, "kerbX": 7, "approachW": scene.get("approachWidth", 14),
            "exitWidths": scene.get("exitWidths", {}), "segmentLength": 0,
            "roadMask": {"cell": 0.25, "x": -crop, "z": -crop, "width": int(crop * 8), "height": int(crop * 8)},
            "spec": {"maneuver": question.get("maneuver", "straight"), "yieldTo": [], "paths": None, "pathRules": None},
            "exits": {}, "props": [], "actors": [], "lights": [], "officers": [],
            "labels": [], "trajectories": [], "legend": [], "trafficLights": None,
            "stopPositions": None, "requiredStop": None, "redWait": None, "speedLimit": None,
            "questionCamera": [], "text": copy.deepcopy(question["text"]),
            "sourceTextLength": source_text_length,
            "correctAnswerIndex": question["correct"], "showPlayerGuide": question.get("showPlayerGuide", True),
            "sourceQuestionId": question.get("sourceQuestionId"), "sourceCategory": question.get("sourceCategory"),
            "sourceImage": question.get("sourceImage")}
