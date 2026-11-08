"""An admin reschedule/delete must change the actual public build, not only UI."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.blog_admin import generator
from tools.blog_admin.sync_worker_schedule import synchronize, validate_schedule


def envelope(articles):
    return {"schema": 1, "complete": True, "count": len(articles), "articles": articles}


class WorkerScheduleTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(generator.REPO) / "scratch"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="blog-schedule-test-", dir=scratch)
        self.site = Path(self.temp.name)
        self.blog = self.site / "blog"
        self.blog.mkdir()
        (self.site / "index.html").write_text("<!-- BLOG:START --><!-- BLOG:END -->")
        for slug in ("kept", "removed"):
            directory = self.blog / slug
            directory.mkdir()
            (directory / "source.json").write_text(json.dumps({
                "schema": 1, "slug": slug, "title": "Статья " + slug,
                "description": "Учебный разбор ПДД", "datePublished": "2026-10-20",
                "dateModified": "2026-10-21", "reviewedAt": "2026-10-19",
                "published": True, "bodyHtml": "<h2>Пример</h2><p>Текст.</p>", "cluster": "prep",
            }, ensure_ascii=False))
        self.patches = [patch.object(generator, "SITE", str(self.site)),
                        patch.object(generator, "BLOG", str(self.blog)),
                        patch.object(generator, "GLOSSARY_DIR", str(self.site / "glossary_data")),
                        patch.object(generator, "publication_day", return_value="2026-10-22")]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_admin_date_change_and_deletion_change_public_html_and_indexes(self):
        self.assertEqual(set(generator.regen_all()), {"kept", "removed"})
        response = envelope([{"slug": "kept", "datePublished": "2026-10-23", "published": True}])
        synchronize(response, self.blog)
        self.assertEqual(generator.regen_all(), [])
        for slug in ("kept", "removed"):
            self.assertFalse((self.blog / slug / "index.html").exists())
            self.assertTrue((self.blog / slug / "source.json").exists())
        for filename in ("sitemap.xml", "feed.xml", "llms.txt", "llms-full.txt", "blog/index.html", "index.html"):
            text = (self.site / filename).read_text()
            self.assertNotIn("/blog/kept/", text)
            self.assertNotIn("/blog/removed/", text)
        source = json.loads((self.blog / "kept/source.json").read_text())
        self.assertEqual(source["dateModified"], "2026-10-23")
        self.assertEqual(source["reviewedAt"], "2026-10-19")
        response["articles"][0]["datePublished"] = "2026-10-22"
        synchronize(response, self.blog)
        self.assertEqual(generator.regen_all(), ["kept"])
        self.assertTrue((self.blog / "kept/index.html").exists())
        self.assertIn("/blog/kept/", (self.site / "sitemap.xml").read_text())
        self.assertFalse(json.loads((self.blog / "removed/source.json").read_text())["published"])

    def test_entire_response_is_validated_before_sources_are_changed(self):
        path = self.blog / "kept/source.json"
        before = path.read_bytes()
        cases = [[], {"schema": 1, "complete": False, "count": 0, "articles": []},
                 {"schema": 1, "complete": True, "count": 1, "articles": []},
                 envelope([{"slug": "kept", "datePublished": "2026-02-30", "published": True}]),
                 envelope([{"slug": "kept", "datePublished": "2026-10-22", "published": "true"}]),
                 envelope([{"slug": "kept", "datePublished": "2026-10-22", "published": True}] * 2)]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                synchronize(value, self.blog)
            self.assertEqual(path.read_bytes(), before)

    def test_unknown_remote_source_is_reported_without_creating_content(self):
        result = synchronize(envelope([{"slug": "unknown", "datePublished": "2026-10-22", "published": True}]), self.blog)
        self.assertEqual(result["unknown_remote"], 1)
        self.assertFalse((self.blog / "unknown").exists())
        self.assertEqual(generator.regen_all(), [])


if __name__ == "__main__":
    unittest.main()
