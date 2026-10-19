import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_preview_host as host
import stage_site as stage


class PreviewHostPreparationTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[2] / "scratch/domain-migration-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / "archive"
        self.archive.mkdir()
        files = {
            "index.html": "<html><head></head><body>Landing</body></html>",
            "app/index.html": '<html><head><base href="/app/"></head><body>APP</body></html>',
            "app/flutter_bootstrap.js": "_flutter.loader.load({});",
            "app/main.dart.js": "var app=1;",
            "app/canvaskit/canvaskit.js": "var renderer=1;",
            "app/canvaskit/canvaskit.wasm": b"\0asm\x01\0\0\0",
            "app/godot/index.wasm": b"\0asm\x01\0\0\0" + b"synthetic-wasm" * 3000,
        }
        for relative, data in files.items():
            path = self.archive / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data.encode() if isinstance(data, str) else data)
        self.staged = self.root / "staged"
        stage.stage_site(self.archive, self.staged, "https://pdd-drive.app")
        self.output = self.root / "host"

    def prepare(self):
        return host.prepare_preview_host(self.staged, self.output, max_asset_bytes=8192)

    def test_copies_without_mutating_either_source_and_verifies_gzip_exact_bytes(self):
        archive_before = stage.inventory(self.archive)
        staged_before = stage.inventory(self.staged)
        report = self.prepare()
        self.assertEqual(stage.inventory(self.archive), archive_before)
        self.assertEqual(stage.inventory(self.staged), staged_before)
        original = (self.staged / "app/godot/index.wasm").read_bytes()
        packed = (self.output / "assets/app/godot/index.wasm.gz").read_bytes()
        self.assertEqual(gzip.decompress(packed), original)
        mapping = report["compressed_assets"]["/app/godot/index.wasm"]
        self.assertEqual(mapping["contentType"], "application/wasm")
        self.assertEqual(mapping["sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(mapping["gzipSha256"], hashlib.sha256(packed).hexdigest())
        self.assertFalse((self.output / "assets/app/godot/index.wasm").exists())
        self.assertFalse((self.output / "assets/_headers").exists())
        self.assertEqual((self.output / "assets/app/index.html").read_bytes(), (self.staged / "app/index.html").read_bytes())
        self.assertFalse(report["deployed"])

    def test_generated_config_has_only_new_worker_and_assets_without_production_bindings_or_route(self):
        self.prepare()
        config = json.loads((self.output / "wrangler.json").read_text())
        self.assertEqual(config["name"], "pdd-domain-migration-preview")
        self.assertEqual(config["account_id"], host.ACCOUNT_ID)
        self.assertEqual(config["assets"], {"directory": "./assets", "binding": "ASSETS", "run_worker_first": True, "not_found_handling": "none", "html_handling": "none"})
        self.assertTrue(config["workers_dev"])
        self.assertFalse(config["observability"]["enabled"])
        self.assertFalse(set(config) & {"routes", "route", "kv_namespaces", "durable_objects", "services", "secrets_store_secrets", "triggers", "vars", "d1_databases", "r2_buckets"})
        generated_policy = (self.output / "preview_policy.mjs").read_text().split("export default ", 1)[1].removesuffix(";\n")
        self.assertEqual(json.loads(generated_policy), stage.HEADERS)
        self.assertEqual((self.output / "preview_worker.mjs").read_bytes(), host.HOST_SOURCE.read_bytes())

    def test_refuses_unknown_provenance_policy_drift_tampering_and_existing_output(self):
        provenance_path = self.staged / "staging-provenance.json"
        original_provenance = provenance_path.read_text()
        provenance = json.loads(original_provenance)
        provenance["required_headers"]["Cache-Control"] = "public"
        provenance_path.write_text(json.dumps(provenance))
        with self.assertRaisesRegex(ValueError, "provenance"):
            self.prepare()
        self.assertFalse(self.output.exists())
        provenance_path.write_text(original_provenance)
        (self.staged / "app/index.html").write_text("tampered")
        with self.assertRaisesRegex(ValueError, "provenance"):
            self.prepare()
        self.assertFalse(self.output.exists())
        self.output.mkdir()
        (self.output / "keep").write_text("safe")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual((self.output / "keep").read_text(), "safe")

    def test_failures_remove_only_new_host_and_detect_source_change(self):
        before = stage.inventory(self.staged)
        with patch.object(host, "decompress_digest", return_value="wrong"):
            with self.assertRaisesRegex(ValueError, "verification failed"):
                self.prepare()
        self.assertFalse(self.output.exists())
        self.assertEqual(stage.inventory(self.staged), before)
        original_inventory = host.inventory
        count = 0

        def changing_inventory(root):
            nonlocal count
            if root == self.staged:
                count += 1
                if count == 2:
                    (root / "new.txt").write_text("changed")
            return original_inventory(root)

        with patch.object(host, "inventory", side_effect=changing_inventory):
            with self.assertRaisesRegex(ValueError, "input changed"):
                self.prepare()
        self.assertFalse(self.output.exists())
        self.assertEqual((self.staged / "new.txt").read_text(), "changed")

    def test_refuses_overlap_symlink_or_unstaged_input(self):
        for source, output in [(self.archive, self.output), (self.staged, self.staged / "nested"), (self.staged, self.root)]:
            with self.subTest(source=source, output=output), self.assertRaises(ValueError):
                host.prepare_preview_host(source, output)
        linked = self.root / "linked"
        linked.symlink_to(self.staged, target_is_directory=True)
        with self.assertRaises(ValueError):
            host.prepare_preview_host(linked, self.output)

    def test_account_login_needs_explicit_matching_stage_and_remains_assets_only(self):
        with self.assertRaisesRegex(ValueError, "provenance"):
            host.prepare_preview_host(self.staged, self.output, enable_account_login=True)
        account_staged = self.root / "account-stage"
        stage.stage_site(self.archive, account_staged, "https://pdd-drive.app", enable_account_login=True)
        with self.assertRaisesRegex(ValueError, "provenance"):
            host.prepare_preview_host(account_staged, self.output)
        before = stage.inventory(account_staged)
        report = host.prepare_preview_host(account_staged, self.output, max_asset_bytes=8192, enable_account_login=True)
        self.assertEqual(before, stage.inventory(account_staged))
        self.assertEqual(report["mode"], "account-login")
        self.assertEqual(report["headers"], stage.ACCOUNT_HEADERS)
        config = json.loads((self.output / "wrangler.json").read_text())
        self.assertFalse(config["workers_dev"])
        self.assertFalse(set(config) & {"routes", "kv_namespaces", "durable_objects", "services", "triggers", "vars", "d1_databases", "r2_buckets"})
        self.assertEqual((self.output / "apple_web_callback.mjs").read_bytes(), host.APPLE_CALLBACK_SOURCE.read_bytes())
        worker = (self.output / "worker.mjs").read_text()
        self.assertIn("accountLogin: true", worker)
        self.assertIn("handleAppleWebCallback(request, 'https://pdd-drive.app')", worker)
        self.assertEqual(report["production_bindings"], [])


if __name__ == "__main__":
    unittest.main()
