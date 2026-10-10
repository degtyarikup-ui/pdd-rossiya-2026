import tempfile
import unittest
from pathlib import Path
from version_web_build import version_build


class VersionWebBuildTest(unittest.TestCase):
    def test_changes_scripts_when_code_changes_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'main.dart.js').write_text('release one')
            (root / 'flutter_bootstrap.js').write_text('{"mainJsPath":"main.dart.js"}')
            (root / 'index.html').write_text('<script src="flutter_bootstrap.js"></script>')
            first = version_build(root)
            first_index = (root / 'index.html').read_text()
            self.assertEqual(first, version_build(root))
            self.assertEqual(first_index, (root / 'index.html').read_text())
            self.assertIn('?release=' + first, (root / 'flutter_bootstrap.js').read_text())
            (root / 'main.dart.js').write_text('release two')
            second = version_build(root)
            self.assertNotEqual(first, second)
            self.assertNotEqual(first_index, (root / 'index.html').read_text())
            self.assertIn('?release=' + second, (root / 'flutter_bootstrap.js').read_text())


if __name__ == '__main__':
    unittest.main()
