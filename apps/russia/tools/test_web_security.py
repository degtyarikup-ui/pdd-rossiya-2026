import base64
import hashlib
import unittest
from tools.web_security import secure_html


class WebSecurityTest(unittest.TestCase):
    def test_policy_hash_matches_executable_inline_script_and_is_idempotent(self):
        script = "window.example = '&<>';\n"
        source = '<html><head><meta charset="UTF-8"></head><body><script>' + script + '</script></body></html>'
        secured = secure_html(source)
        expected = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        self.assertIn(expected, secured)
        self.assertIn("script-src-attr &#x27;none&#x27;", secured)
        self.assertEqual(secure_html(secured), secured)
        self.assertLess(secured.index('charset='), secured.index('Content-Security-Policy'))

    def test_prior_upgrade_policy_is_replaced_instead_of_silently_combined(self):
        source = '<head><meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests"><script src="/assets/site.js"></script></head>'
        secured = secure_html(source)
        self.assertEqual(secured.count('http-equiv="Content-Security-Policy"'), 1)
        self.assertIn('object-src', secured)


if __name__ == "__main__":
    unittest.main()
