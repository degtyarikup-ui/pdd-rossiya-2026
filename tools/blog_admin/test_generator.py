"""Регрессии реального расписания и границы редактор → публичный сайт."""
import datetime
import json
import re
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.blog_admin import generator


class PublicationTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(generator.REPO) / "scratch"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="blog-generator-test-", dir=scratch)
        self.root = Path(self.temp.name)
        self.site = self.root / "site"
        self.blog = self.site / "blog"
        self.blog.mkdir(parents=True)
        (self.site / "index.html").write_text("<!-- BLOG:START --><!-- BLOG:END -->", encoding="utf-8")
        self.patches = [patch.object(generator, "SITE", str(self.site)),
                        patch.object(generator, "BLOG", str(self.blog)),
                        patch.object(generator, "GLOSSARY_DIR", str(self.site / "glossary_data")),
                        patch.object(generator, "publication_day", return_value="2026-10-22")]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.temp.cleanup()

    def article(self, slug, date="2026-10-22", published=True, **extra):
        article = {"schema": 1, "slug": slug, "title": "Статья " + slug,
                   "description": "Учебный разбор ПДД", "datePublished": date,
                   "published": published, "bodyHtml": "<h2>Пример</h2><p>Текст.</p>",
                   "cluster": "prep", **extra}
        directory = self.blog / slug
        directory.mkdir()
        (directory / "source.json").write_text(json.dumps(article, ensure_ascii=False), encoding="utf-8")
        (directory / "index.html").write_text("stale preview", encoding="utf-8")
        (directory / "cover.jpg").write_bytes(b"fixture")
        return article

    def test_only_due_articles_are_public_but_editor_sees_all(self):
        self.article("past", "2026-10-21")
        self.article("today")
        self.article("tomorrow", "2026-10-23")
        self.article("draft", published=False)
        self.article("bad-date", "2026-99-99")
        self.assertEqual([a["slug"] for a in generator.load_articles()], ["today", "past"])
        self.assertEqual(len(generator.load_articles(include_drafts=True)), 5)

    def test_regen_removes_future_preview_and_every_public_index_excludes_it(self):
        self.article("today")
        self.article("tomorrow", "2026-10-23")
        self.article("draft", published=False)
        self.assertEqual(generator.regen_all(), ["today"])
        self.assertFalse((self.blog / "tomorrow" / "index.html").exists())
        self.assertFalse((self.blog / "draft" / "index.html").exists())
        for filename in ("sitemap.xml", "feed.xml", "llms.txt", "llms-full.txt", "blog/index.html", "index.html"):
            content = (self.site / filename).read_text(encoding="utf-8")
            self.assertIn("today", content, filename)
            self.assertNotIn("tomorrow", content, filename)
            self.assertNotIn("draft", content, filename)
        before = (self.blog / "today" / "index.html").stat().st_mtime_ns
        generator.regen_all()
        self.assertEqual((self.blog / "today" / "index.html").stat().st_mtime_ns, before)

    def test_preview_is_noindex_and_sources_match_structured_data(self):
        self.article("tomorrow", "2026-10-23", reviewedAt="2026-10-22",
                     sources=[{"title": "Первоисточник", "url": "https://example.org/law"},
                              {"title": "Недопустимая ссылка", "url": "javascript:alert(1)"}],
                     cta={"title": "Проверьте правило", "text": "Учебный текст", "label": "Потренироваться", "href": "https://evil.example"})
        generator.render_article("tomorrow")
        content = (self.blog / "tomorrow" / "index.html").read_text(encoding="utf-8")
        self.assertIn('<meta name="robots" content="noindex">', content)
        article_data = json.loads(re.search(r'<script type="application/ld\+json">(.*?)</script>', content, re.S).group(1))
        self.assertEqual(article_data["citation"], ["https://example.org/law"])
        self.assertIn('<a href="https://example.org/law"', content)
        self.assertNotIn("javascript:", content)
        self.assertNotIn("evil.example", content)
        self.assertIn('href="/app/" data-cta="article-practice" data-context="tomorrow"', content)
        self.assertIn('datetime="2026-10-22"', content)

    def test_clean_public_copy_removes_unreleased_assets_and_editor_sources(self):
        self.article("today")
        self.article("tomorrow", "2026-10-23")
        self.article("draft", published=False)
        import shutil
        destination = self.root / "deployment"
        shutil.copytree(self.site, destination)
        generator.clean_public_copy(str(destination))
        self.assertFalse((destination / "blog/tomorrow").exists())
        self.assertFalse((destination / "blog/draft").exists())
        self.assertTrue((destination / "blog/today/cover.jpg").exists())
        self.assertEqual(list(destination.rglob("source.json")), [])
        self.assertTrue((self.blog / "today/source.json").exists())
        with self.assertRaises(ValueError):
            generator.clean_public_copy(str(self.site))

    def test_related_links_never_include_unpublished_articles(self):
        self.article("today", relatedSlugs=["tomorrow", "past"])
        self.article("past", "2026-10-21")
        self.article("tomorrow", "2026-10-23")
        generator.render_article("today")
        content = (self.blog / "today/index.html").read_text(encoding="utf-8")
        self.assertIn('href="/blog/past/"', content)
        self.assertNotIn('href="/blog/tomorrow/"', content)

    def test_offline_cta_can_link_to_mobile_download_buttons(self):
        self.article("today", cta={"label": "Выбрать мобильную версию", "href": "/#download"})
        generator.render_article("today")
        content = (self.blog / "today/index.html").read_text(encoding="utf-8")
        self.assertIn('href="/#download" data-cta="article-practice"', content)


class MoscowDateTests(unittest.TestCase):
    def test_moscow_midnight_is_2100_utc_not_host_local_date(self):
        utc = datetime.timezone.utc
        self.assertEqual(generator.publication_day(datetime.datetime(2026, 10, 22, 20, 59, 59, tzinfo=utc)), "2026-10-22")
        self.assertEqual(generator.publication_day(datetime.datetime(2026, 10, 22, 21, 0, tzinfo=utc)), "2026-10-23")


if __name__ == "__main__":
    unittest.main()
