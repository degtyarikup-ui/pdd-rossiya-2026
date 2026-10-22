#!/usr/bin/env python3
"""Build Worker blog metadata from article sources, without publishing anything.

Use --existing with a freshly read blog_articles KV backup to preserve existing
admin records exactly. Records whose source directory was removed are omitted;
new sources supply the new records. The JSON output is suitable for Wrangler's
``kv key put blog_articles --path ...`` after review.
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BLOG = ROOT / "web_landing/ru/blog"
MODULE = ROOT / "server/install-notifier/blog_catalog.js"
FIELDS = (
    "slug", "title", "shortTitle", "description", "datePublished",
    "dateModified", "readingMinutes", "cluster", "cover", "coverAlt",
    "published",
)


def build_catalog(blog_dir=BLOG, existing=(), refresh_media=()):
    """Keep existing source-backed records and add metadata for new sources."""
    existing_by_slug = {}
    for article in existing:
        slug = article.get("slug")
        if not isinstance(slug, str) or not slug or slug in existing_by_slug:
            raise ValueError("Existing catalogue has an invalid or duplicate slug")
        existing_by_slug[slug] = article
    articles = []
    refresh_media = set(refresh_media)
    for path in sorted(Path(blog_dir).glob("*/source.json")):
        source = json.loads(path.read_text(encoding="utf-8"))
        slug = source.get("slug")
        if slug != path.parent.name:
            raise ValueError(f"Source slug does not match its directory: {path}")
        if slug in existing_by_slug:
            article = dict(existing_by_slug[slug])
            if slug in refresh_media:
                article.update(cover=source.get("cover"), coverAlt=source.get("coverAlt"))
            articles.append(article)
        else:
            article = {field: source[field] for field in FIELDS if field in source}
            for field in ("title", "description", "datePublished", "published"):
                if field not in article:
                    raise ValueError(f"Missing metadata field {field}: {path}")
            articles.append(article)
    return articles


def module_text(articles):
    return (
        "// Generated catalogue fallback. Update with tools/blog_admin/build_worker_catalog.py.\n"
        "export const DEFAULT_BLOG_ARTICLES = "
        + json.dumps(articles, ensure_ascii=False, indent=2)
        + ";\n"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--existing", type=Path, help="Fresh JSON KV backup; keep existing source-backed records exactly")
    parser.add_argument("--catalog-json", type=Path, help="Write reviewed metadata for a later KV update")
    parser.add_argument("--write-module", action="store_true", help="Update the tracked Worker fallback module")
    parser.add_argument("--refresh-media", nargs="*", default=[], metavar="SLUG", help="Refresh only cover/coverAlt for these existing records, preserving admin dates and all other fields")
    args = parser.parse_args()
    existing = json.loads(args.existing.read_text(encoding="utf-8")) if args.existing else []
    if not isinstance(existing, list):
        parser.error("--existing must contain a JSON array")
    articles = build_catalog(existing=existing, refresh_media=args.refresh_media)
    if args.catalog_json:
        args.catalog_json.parent.mkdir(parents=True, exist_ok=True)
        args.catalog_json.write_text(json.dumps(articles, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.write_module:
        MODULE.write_text(module_text(articles), encoding="utf-8")
    print(f"Catalogue: {len(articles)} articles; no remote data changed")


if __name__ == "__main__":
    main()
