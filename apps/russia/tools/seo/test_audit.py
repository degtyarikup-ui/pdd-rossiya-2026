"""The separately maintained Flutter app is not a missing landing page."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.seo import audit


class LlmsLinkTests(unittest.TestCase):
    def test_app_endpoint_is_allowed_but_missing_article_still_fails(self):
        scratch = Path(audit.REPO) / "scratch"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="seo-audit-test-", dir=scratch) as directory:
            root = Path(directory)
            (root / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://pdd-drive.ru/sitemap.xml\n", encoding="utf-8")
            for name in ("llms.txt", "llms-full.txt"):
                (root / name).write_text("[App](https://pdd-drive.ru/app/)\n[Missing](https://pdd-drive.ru/blog/missing/)\n", encoding="utf-8")
            with patch.object(audit, "SITE", directory):
                report = audit.Report()
                audit.check_robots_and_llms(report, {"/", "/blog/"})
            self.assertEqual(len(report.errors), 2)
            self.assertTrue(all("/blog/missing/" in message for _, message in report.errors))


if __name__ == "__main__":
    unittest.main()
