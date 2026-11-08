#!/usr/bin/env python3
"""
Import AB/CD tickets and topics from etspring/pdd_russia (GitHub) into app JSON
and download question images. Run from repo root: python3 scripts/import_pdd_russia.py
"""
from __future__ import annotations

import json
import re
import time
from pathlib import Path
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

BASE = "https://raw.githubusercontent.com/etspring/pdd_russia/master"
API = "https://api.github.com/repos/etspring/pdd_russia/contents"
ROOT = Path(__file__).resolve().parent.parent
ASSETS_Q = ROOT / "assets" / "questions"
IMG_AB = ROOT / "assets" / "images" / "questions_ab"
IMG_CD = ROOT / "assets" / "images" / "questions_cd"

UA = {"User-Agent": "pdd-app-import/1.0"}


def fetch_json(url: str, attempts: int = 5):
    last_err: Exception | None = None
    for attempt in range(attempts):
        try:
            req = Request(url, headers=UA)
            with urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode("utf-8"))
        except (URLError, OSError, TimeoutError, ValueError) as e:
            last_err = e
            time.sleep(1.5 * (attempt + 1))
    raise last_err  # type: ignore[misc]


def normalize_image(raw: str | None):
    if not raw:
        return None
    low = raw.lower()
    if "no_image" in low:
        return None
    m = re.search(r"/([0-9a-fA-F]{32})\.jpg", raw)
    return m.group(1).lower() if m else None


def q_from_raw(q: dict, ticket_num: int) -> dict:
    img = normalize_image(q.get("image"))
    answers = []
    for a in q.get("answers") or []:
        answers.append(
            {
                "text": (a.get("answer_text") or a.get("text") or "").strip(),
                "correct": bool(a.get("is_correct") or a.get("correct")),
            }
        )
    return {
        "id": q.get("id") or "",
        "question": (q.get("question") or "").strip(),
        "answers": answers,
        "comment": (q.get("answer_tip") or q.get("comment") or "").strip(),
        "pddPoints": q.get("pddPoints") or [],
        "image": img,
        "topic": q.get("topic") or [],
        "ticketNumber": ticket_num,
    }


def import_tickets(cat_path: str) -> dict:
    tickets_out = []
    for n in range(1, 41):
        path = f"{BASE}/questions/{cat_path}/tickets/{quote(f'Билет {n}.json')}"
        data = fetch_json(path)
        questions = [q_from_raw(q, n) for q in data]
        tickets_out.append({"number": n, "questions": questions})
        print(f"  ticket {n}/40")
        time.sleep(0.12)
    return {"tickets": tickets_out}


def import_topics(cat_path: str) -> dict:
    listing = fetch_json(f"{API}/questions/{cat_path}/topics?ref=master")
    topics_out = []
    for item in listing:
        if item["type"] != "file" or not str(item["name"]).endswith(".json"):
            continue
        fname = str(item["name"])
        name = fname.replace(".json", "")
        url = f"{BASE}/questions/{cat_path}/topics/{quote(fname)}"
        arr = fetch_json(url)
        questions = [q_from_raw(q, 0) for q in arr]
        topics_out.append({"name": name, "questions": questions})
        print(f"  topic {name}")
        time.sleep(0.12)
    topics_out.sort(key=lambda t: t["name"])
    return {"topics": topics_out}


def collect_images(obj, out: set):
    if isinstance(obj, dict):
        if "image" in obj and obj["image"]:
            out.add(obj["image"])
        for v in obj.values():
            collect_images(v, out)
    elif isinstance(obj, list):
        for x in obj:
            collect_images(x, out)


def download_image(subdir: str, h: str, dest_dir: Path) -> bool:
    dest = dest_dir / f"{h}.jpg"
    if dest.exists():
        return True
    url = f"{BASE}/images/{subdir}/{h}.jpg"
    for attempt in range(5):
        try:
            req = Request(url, headers=UA)
            with urlopen(req, timeout=120) as r:
                dest.write_bytes(r.read())
            return True
        except (URLError, OSError, TimeoutError) as e:
            if attempt == 4:
                print(f"  FAIL {h}: {e}")
                return False
            time.sleep(1.0 * (attempt + 1))
    return False


def main():
    ASSETS_Q.mkdir(parents=True, exist_ok=True)
    IMG_AB.mkdir(parents=True, exist_ok=True)
    IMG_CD.mkdir(parents=True, exist_ok=True)

    print("AB tickets...")
    ab_tickets = import_tickets("A_B")
    print("AB topics...")
    ab_topics = import_topics("A_B")
    print("CD tickets...")
    cd_tickets = import_tickets("C_D")
    print("CD topics...")
    cd_topics = import_topics("C_D")

    (ASSETS_Q / "questions_ab.json").write_text(
        json.dumps(ab_tickets, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (ASSETS_Q / "topics_ab.json").write_text(
        json.dumps(ab_topics, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (ASSETS_Q / "questions_cd.json").write_text(
        json.dumps(cd_tickets, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (ASSETS_Q / "topics_cd.json").write_text(
        json.dumps(cd_topics, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    ab_img: set[str] = set()
    cd_img: set[str] = set()
    collect_images(ab_tickets, ab_img)
    collect_images(ab_topics, ab_img)
    collect_images(cd_tickets, cd_img)
    collect_images(cd_topics, cd_img)

    print(f"Download AB images ({len(ab_img)})...")
    for i, h in enumerate(sorted(ab_img)):
        if download_image("A_B", h, IMG_AB):
            pass
        if (i + 1) % 50 == 0:
            print(f"  ... {i + 1}/{len(ab_img)}")
        time.sleep(0.02)

    print(f"Download CD images ({len(cd_img)})...")
    for i, h in enumerate(sorted(cd_img)):
        download_image("C_D", h, IMG_CD)
        if (i + 1) % 50 == 0:
            print(f"  ... {i + 1}/{len(cd_img)}")
        time.sleep(0.02)

    print("Done.")


if __name__ == "__main__":
    main()
