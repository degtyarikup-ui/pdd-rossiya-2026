#!/usr/bin/env python3
"""Apply the admin's authoritative publication dates before a production build.

Only scheduling fields in known source.json files are changed. The response is
validated in full before any source is written. Missing records disable their
articles; an unavailable or legacy endpoint stops the build instead of silently
publishing a stale local plan. Plain generator.py preview/regen stays offline.
"""

import argparse
from datetime import date
import json
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
BLOG = ROOT / "web_landing/ru/blog"
SCHEDULE_URL = "https://pdd-install-notifier.sergei-pdd.workers.dev/api/blog/schedule"
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
DAY = re.compile(r"\d{4}-\d{2}-\d{2}")


def validate_schedule(payload):
    if (not isinstance(payload, dict) or type(payload.get("schema")) is not int
            or payload.get("schema") != 1 or payload.get("complete") is not True):
        raise ValueError("Unversioned or incomplete schedule response")
    articles = payload.get("articles")
    count = payload.get("count")
    if not isinstance(articles, list) or type(count) is not int or count != len(articles) or count > 1000:
        raise ValueError("Invalid schedule count")
    result = {}
    for article in articles:
        if not isinstance(article, dict) or set(article) != {"slug", "datePublished", "published"}:
            raise ValueError("Invalid schedule record")
        slug, day = article["slug"], article["datePublished"]
        if not isinstance(slug, str) or not SLUG.fullmatch(slug) or len(slug) > 200 or slug in result:
            raise ValueError("Invalid or duplicate schedule slug")
        if not isinstance(day, str) or not DAY.fullmatch(day):
            raise ValueError("Invalid publication day")
        date.fromisoformat(day)
        if type(article["published"]) is not bool:
            raise ValueError("Invalid publication permission")
        result[slug] = article
    return result


def synchronize(payload, blog_dir=BLOG):
    schedule = validate_schedule(payload)
    changes = []
    disabled = 0
    known = set()
    # Read and validate all sources before writing any of them.
    for path in sorted(Path(blog_dir).glob("*/source.json")):
        source = json.loads(path.read_text(encoding="utf-8"))
        slug = source.get("slug")
        if slug != path.parent.name:
            raise ValueError(f"Source slug does not match its directory: {path}")
        known.add(slug)
        updated = dict(source)
        if slug in schedule:
            updated.update(datePublished=schedule[slug]["datePublished"], published=schedule[slug]["published"])
            updated["dateModified"] = max(updated.get("dateModified", updated["datePublished"]), updated["datePublished"])
        else:
            updated["published"] = False
            disabled += 1
        if updated != source:
            changes.append((path, updated))
    for path, source in changes:
        temporary = path.with_suffix(".json.schedule-tmp")
        temporary.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)
    return {"records": len(schedule), "updated": len(changes), "disabled_missing": disabled,
            "unknown_remote": len(set(schedule) - known)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schedule-json", type=Path, help="Use a saved versioned response for an isolated build/test")
    args = parser.parse_args()
    try:
        if args.schedule_json:
            payload = json.loads(args.schedule_json.read_text(encoding="utf-8"))
        else:
            request = Request(SCHEDULE_URL, headers={"Accept": "application/json", "Cache-Control": "no-cache"})
            with urlopen(request, timeout=20) as response:
                if response.status != 200:
                    raise ValueError("Schedule endpoint did not return HTTP 200")
                body = response.read(1024 * 1024 + 1)
                if len(body) > 1024 * 1024:
                    raise ValueError("Schedule response is too large")
                payload = json.loads(body)
        result = synchronize(payload)
    except Exception as error:
        print(f"Blog publication stopped: {error}", file=sys.stderr)
        return 1
    print("Blog schedule synchronized: " + json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
