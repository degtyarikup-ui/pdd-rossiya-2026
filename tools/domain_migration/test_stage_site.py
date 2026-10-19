"""Safety and provenance tests for deriving a preview from a deployed archive."""

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("stage_site", Path(__file__).with_name("stage_site.py"))
stage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stage)


class StageSiteTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[2] / "scratch/domain-migration-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "archive"
        self.output = self.root / "preview"
        self.source.mkdir()
        self.origin = "https://preview.pdd-drive.app"
        self.write("index.html", '<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="upgrade-insecure-requests"><meta name="robots" content="index,follow"></head><body><a href="https://pdd-drive.ru/blog/test/">Blog</a><script src="/assets/site.js"></script><script src="/assets/tracker.js"></script><script>fetch("https://api.pdd-drive.app/api/track",{method:"POST"})</script></body></html>')
        self.write("CNAME", "pdd-drive.ru\n")
        self.write("robots.txt", "User-agent: *\nAllow: /\n")
        self.write("assets/site.js", "document.title = document.title;")
        self.write("assets/tracker.js", 'fetch("https://api.pdd-drive.app/api/track",{method:"POST"});')
        self.write("app/index.html", '<html><head><base href="/app/"></head><body><script src="flutter_bootstrap.js"></script></body></html>')
        self.write("app/flutter_bootstrap.js", '_flutter.loader.load({serviceWorkerSettings:{serviceWorkerVersion:"abc"}});')
        self.write("app/main.dart.js", 'var api="https://api.pdd-drive.app", old="https://pdd-install-notifier.sergei-pdd.workers.dev", oauth="https://oauth.yandex.ru/authorize", tariffs="https://pdd-drive.ru/tarify/";')
        self.write("app/canvaskit/canvaskit.js", "export default {};")
        self.write("app/canvaskit/canvaskit.wasm", b"\0asm\x01\0\0\0")
        self.write("app/flutter_service_worker.js", "fetch('https://api.pdd-drive.app');")

    def write(self, relative, value):
        path = self.source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, bytes):
            path.write_bytes(value)
        else:
            path.write_text(value, encoding="utf-8")

    def prepare(self):
        return stage.stage_site(self.source, self.output, self.origin, "abc123")

    def test_preserves_archive_and_tracks_every_staged_file(self):
        before = stage.inventory(self.source)
        manifest = self.prepare()
        self.assertEqual(before, stage.inventory(self.source))
        self.assertEqual((self.source / "CNAME").read_text(), "pdd-drive.ru\n")
        self.assertFalse((self.output / "CNAME").exists())
        self.assertFalse((self.output / "app/flutter_service_worker.js").exists())
        self.assertFalse((self.output / "assets/tracker.js").exists())
        self.assertEqual(manifest["source_files"], before)
        self.assertEqual(manifest["source_tree_sha256"], stage.source_tree_hash(before))
        actual = stage.inventory(self.output)
        actual.pop("staging-provenance.json")
        self.assertEqual(manifest["staged_files"], actual)
        self.assertEqual((self.output / "app/canvaskit/canvaskit.wasm").read_bytes(), (self.source / "app/canvaskit/canvaskit.wasm").read_bytes())

    def test_blocks_payment_analytics_external_navigation_and_indexing(self):
        self.write("tarify/index.html", '''<html><head><meta http-equiv="refresh" content="0;url=https://pay.example"></head><body>
<a href="//api.pdd-drive.app/api/pay/platega/callback">Pay</a>
<a href="https://accounts.google.com/o/oauth2/auth">Login</a>
<a href="javascript:location='https://evil.test'" onclick="fetch('https://evil.test')" ping="https://evil.test">Bad</a>
<form action="https://pay.example" method="post"><input name="email"><button formaction="https://pay.example">Pay</button></form>
<script>location.href='https://pay.example';</script><script src="https://mc.yandex.ru/metrika/tag.js"></script>
</body></html>''')
        self.prepare()
        text = (self.output / "tarify/index.html").read_text()
        self.assertNotIn("pay.example", text)
        self.assertNotIn("metrika", text)
        self.assertNotIn("onclick", text)
        self.assertNotIn("javascript:", text)
        self.assertNotIn('http-equiv="refresh"', text)
        self.assertIn('action="/__staging_disabled__"', text)
        self.assertIn("disabled", text)
        self.assertIn("connect-src &#x27;self&#x27;", text)
        self.assertIn("form-action &#x27;none&#x27;", text)
        self.assertIn("noindex,nofollow,noarchive,nosnippet", text)
        self.assertIn('lang="ru"', text)
        self.assertIn('lang="en"', text)
        self.assertIn('lang="kk"', text)
        self.assertEqual((self.output / "robots.txt").read_text(), "User-agent: *\nDisallow: /\n")
        self.assertIn("X-Robots-Tag: noindex", (self.output / "_headers").read_text())
        self.assertNotIn("tracker.js", (self.output / "index.html").read_text())

    def test_flutters_local_renderer_and_backend_disabled_without_touching_source(self):
        self.prepare()
        bootstrap = (self.output / "app/flutter_bootstrap.js").read_text()
        self.assertIn('canvasKitBaseUrl: "/app/canvaskit/"', bootstrap)
        compiled = (self.output / "app/main.dart.js").read_text()
        self.assertNotIn("https://api.pdd-drive.app", compiled)
        self.assertNotIn("workers.dev", compiled)
        self.assertNotIn("https://oauth.yandex.ru", compiled)
        self.assertIn('api="/__staging_disabled__"', compiled)
        self.assertIn('tariffs="https://preview.pdd-drive.app/tarify/"', compiled)
        root_html = (self.output / "index.html").read_text()
        self.assertLess(root_html.index('/__staging/isolation.js'), root_html.index('/assets/site.js'))
        self.assertIn('href="https://preview.pdd-drive.app/blog/test/"', root_html)

    def test_rejects_unsafe_source_and_leaves_no_partial_output(self):
        outside = self.root / "account-secret.txt"
        outside.write_text("private")
        (self.source / "linked.txt").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "Unsafe source entry"):
            self.prepare()
        self.assertFalse(self.output.exists())
        (self.source / "linked.txt").unlink()
        for relative in ("backup/users.json", ".env.local", "users.json", "snapshot.sql", "data.tar.gz"):
            with self.subTest(relative=relative):
                self.write(relative, "private")
                with self.assertRaisesRegex(ValueError, "Private/non-static"):
                    self.prepare()
                self.assertFalse(self.output.exists())
                (self.source / relative).unlink()
                if (self.source / relative).parent != self.source:
                    (self.source / relative).parent.rmdir()

    def test_rejects_overlap_existing_output_and_production_origin(self):
        for destination in (self.source / "preview", self.root):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                stage.stage_site(self.source, destination, self.origin)
        self.output.mkdir()
        marker = self.output / "must-survive"
        marker.write_text("existing")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual(marker.read_text(), "existing")
        for origin in ("https://pdd-drive.ru", "https://www.pdd-drive.ru", "https://pdd-drive.ru.", "https://api.pdd-drive.app", "https://u:p@preview.test", "https://preview.test/path", "https://preview.test\n", "https://preview.test:bad", "http://preview.test"):
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                stage.stage_site(self.source, self.root / "other", origin)

    def test_failure_cleans_only_its_new_output_and_detects_changing_source(self):
        original_inventory = stage.inventory
        count = 0

        def changed_inventory(root):
            nonlocal count
            if root == self.source:
                count += 1
                if count == 2:
                    self.write("changed.txt", "new")
            return original_inventory(root)

        with patch.object(stage, "inventory", side_effect=changed_inventory):
            with self.assertRaisesRegex(ValueError, "Source changed"):
                self.prepare()
        self.assertFalse(self.output.exists())
        self.assertEqual((self.source / "changed.txt").read_text(), "new")
        self.write("app/flutter_bootstrap.js", "unknownBootstrap();")
        with self.assertRaisesRegex(ValueError, "Unknown Flutter bootstrap"):
            self.prepare()
        self.assertFalse(self.output.exists())

    @unittest.skipUnless(shutil.which("node"), "Node is needed for exercising browser transport guards")
    def test_runtime_guards_allow_assets_but_block_all_production_transports(self):
        harness = r'''
const vm = require('node:vm');
const sent = [];
const events = {};
class XHR {open(method,url){sent.push(['xhr',method,url])}}
const context = {
  URL, DOMException, console,
  location: {origin:'https://preview.pdd-drive.app'},
  document: {baseURI:'https://preview.pdd-drive.app/app/', addEventListener:(name,fn)=>events[name]=fn},
  navigator: {sendBeacon:()=>{sent.push(['beacon'])}},
  XMLHttpRequest: XHR,
};
context.window = context;
context.fetch = (input,options)=>{sent.push(['fetch',input,options?.method || 'GET']);return Promise.resolve('asset')};
context.open = (...args)=>{sent.push(['open',...args]); return 'opened'};
vm.runInNewContext(GUARD,context);
(async()=>{
 const attempts = [
   ['https://api.pdd-drive.app/api/user/status',{}],
   ['https://pdd-install-notifier.sergei-pdd.workers.dev/api/track',{method:'POST'}],
   ['/api/pay/lead',{}], ['/api',{}], ['/%61pi/user/status',{}],
   ['/__staging_disabled__/api/auth/yandex/start',{}],
   ['/assets/config.json',{method:'POST'}],
 ];
 let denied=0;
 for(const args of attempts)try{await context.fetch(...args)}catch(e){denied++}
 await context.fetch('/app/canvaskit/canvaskit.wasm');
 try{new XHR().open('POST','/assets/x')}catch(e){denied++}
 try{new XHR().open('GET','https://api.pdd-drive.app/x')}catch(e){denied++}
 try{new context.WebSocket('wss://api.pdd-drive.app')}catch(e){denied++}
 try{new context.EventSource('https://api.pdd-drive.app')}catch(e){denied++}
 if(context.navigator.sendBeacon('https://api.pdd-drive.app/x')!==false)throw Error('beacon');
 if(context.open('https://oauth.yandex.ru')!==null)throw Error('popup');
 let prevented=0;
 events.click({target:{closest:()=>({href:'https://pdd-drive.ru/tarify/'})},preventDefault(){prevented++},stopImmediatePropagation(){}});
 events.submit({preventDefault(){prevented++},stopImmediatePropagation(){}});
 process.stdout.write(JSON.stringify({denied,sent,prevented}));
})();
'''
        program = "const GUARD=" + json.dumps(stage.ISOLATION_JS) + ";\n" + harness
        result = subprocess.run([shutil.which("node"), "-e", program], text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["denied"], 11)
        self.assertEqual(data["prevented"], 2)
        self.assertEqual(data["sent"], [["fetch", "/app/canvaskit/canvaskit.wasm", "GET"]])


if __name__ == "__main__":
    unittest.main()
