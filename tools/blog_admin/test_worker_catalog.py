import json
from pathlib import Path
import tempfile
import unittest

from tools.blog_admin.build_worker_catalog import build_catalog, module_text


class WorkerCatalogTest(unittest.TestCase):
    def test_replacement_keeps_existing_metadata_drops_removed_and_adds_new(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for slug in ("retained", "new"):
                path = root / slug
                path.mkdir()
                (path / "source.json").write_text(json.dumps({
                    "slug": slug, "title": "Source title", "description": "Source description",
                    "datePublished": "2026-10-30", "published": True,
                    "bodyHtml": "Do not expose article bodies in the admin catalogue",
                }))
            retained = {"slug": "retained", "datePublished": "2026-09-01", "title": "Admin title", "custom": "keep"}
            result = build_catalog(root, [retained, {"slug": "removed"}])
            self.assertEqual([article["slug"] for article in result], ["new", "retained"])
            self.assertEqual(result[1], retained)
            self.assertNotIn("bodyHtml", result[0])
            self.assertIn("export const DEFAULT_BLOG_ARTICLES", module_text(result))

    def test_rejects_ambiguous_existing_catalogue(self):
        with self.assertRaises(ValueError):
            build_catalog(existing=[{"slug": "duplicate"}, {"slug": "duplicate"}])


if __name__ == "__main__":
    unittest.main()
