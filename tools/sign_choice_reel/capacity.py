"""Count the actual catalog; question-volume estimates remain an editorial judgment."""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def normalized(value):
    return " ".join(value.lower().replace("ё", "е").split())


def inventory():
    rows = []
    for kind in ("signs", "markup"):
        source = ROOT / "assets/countries/ru/questions" / f"{kind}.json"
        for group, entries in json.loads(source.read_text()).items():
            entries = entries.values() if isinstance(entries, dict) else entries
            for entry in entries:
                image = ROOT / "assets/countries/ru" / entry["image"]
                if not image.is_file():
                    raise FileNotFoundError(image)
                rows.append({"kind": kind, "group": group, "number": entry["number"],
                             "title": entry["title"], "image": entry["image"],
                             "image_sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
                             "folk_name": entry.get("folkName", "").strip()})
    return rows


def summarize(rows):
    summary = {}
    for kind in ("signs", "markup"):
        entries = [row for row in rows if row["kind"] == kind]
        groups = collections.Counter(row["group"] for row in entries)
        shared = collections.defaultdict(list)
        for row in entries:
            shared[row["image_sha256"]].append(row["number"])
        summary[kind] = {
            "entries": len(entries), "groups": dict(groups),
            "unique_titles": len({normalized(row["title"]) for row in entries}),
            "category_title_groups": len({(row["group"], normalized(row["title"])) for row in entries}),
            "unique_image_paths": len({row["image"] for row in entries}),
            "unique_image_files_by_sha256": len(shared),
            "shared_image_numbers": [numbers for numbers in shared.values() if len(numbers) > 1],
            "entries_with_folk_names": sum(bool(row["folk_name"]) for row in entries),
            "unique_folk_names": len({normalized(row["folk_name"]) for row in entries if row["folk_name"]}),
        }
    summary["totals"] = {
        "catalog_entries": len(rows),
        "unique_source_images": len({row["image_sha256"] for row in rows}),
        "category_title_groups": sum(summary[kind]["category_title_groups"] for kind in ("signs", "markup")),
        "approved_episodes": 1,
        "remaining_one_per_catalog_entry": len(rows) - 1,
    }
    bank = json.loads(Path(__file__).with_name("interesting_candidates.json").read_text())
    lookup = {(('sign' if row['kind'] == 'signs' else 'mark') + ':' + row['number']): row
              for row in rows}
    seen = set()
    for item in bank["candidates"]:
        if item["id"] in seen:
            raise ValueError(f"Repeated candidate ID: {item['id']}")
        seen.add(item["id"])
        if item["tier"] not in ("core", "reserve"):
            raise ValueError(f"Unknown candidate tier: {item['tier']}")
        if len(item["options"]) != 4 or len(set(item["options"])) != 4:
            raise ValueError(f"Candidate must have four different options: {item['id']}")
        hashes = [lookup[key]["image_sha256"] for key in item["options"]]
        if len(set(hashes)) != 4:
            raise ValueError(f"Identical image files in candidate: {item['id']}")
    summary["editorial_selection"] = {
        "status": bank["status"], "excludes_approved_episode": bank["excludes_approved_episode"],
        "core_candidates": sum(item["tier"] == "core" for item in bank["candidates"]),
        "reserve_candidates": sum(item["tier"] == "reserve" for item in bank["candidates"]),
        "core_by_group": dict(collections.Counter(
            item["group"] for item in bank["candidates"] if item["tier"] == "core")),
        "total_candidates": len(bank["candidates"]),
        "note": "Catalog IDs and image uniqueness checked; question ambiguity and editorial quality require review.",
    }
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="Optional directory for JSON summary and CSV inventory")
    args = parser.parse_args()
    rows = inventory()
    summary = summarize(rows)
    payload = json.dumps(summary, ensure_ascii=False, indent=2) + "\n"
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "catalog-summary.json").write_text(payload)
        with (args.out / "catalog-inventory.csv").open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print(payload, end="")


if __name__ == "__main__":
    main()
