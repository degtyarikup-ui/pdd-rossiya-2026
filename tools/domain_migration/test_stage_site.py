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

    def test_account_login_requires_exact_origin_preserves_identity_api_and_ru_payments(self):
        with self.assertRaisesRegex(ValueError, "exact"):
            stage.stage_site(self.source, self.output, self.origin, enable_account_login=True)
        self.origin = "https://pdd-drive.app"
        self.write("app/index.html", '<html><head><base href="/app/"><script src="https://accounts.google.com/gsi/client"></script></head><body><script src="flutter_bootstrap.js"></script></body></html>')
        self.write("index.html", '<html><head></head><body><a href="https://pdd-drive.ru/tarify/">Pay</a><a href="https://pdd-drive.ru/blog/">Blog</a><script>fetch("https://api.pdd-drive.app/api/track")</script></body></html>')
        before = stage.inventory(self.source)
        manifest = stage.stage_site(self.source, self.output, self.origin, enable_account_login=True)
        self.assertEqual(before, stage.inventory(self.source))
        self.assertEqual(manifest["mode"], "account-login")
        self.assertEqual(manifest["required_headers"], stage.ACCOUNT_HEADERS)
        compiled = (self.output / "app/main.dart.js").read_text()
        self.assertIn('api="https://api.pdd-drive.app"', compiled)
        self.assertIn('old="https://pdd-install-notifier.sergei-pdd.workers.dev"', compiled)
        self.assertIn('oauth="https://oauth.yandex.ru/authorize"', compiled)
        self.assertIn('tariffs="https://pdd-drive.ru/tarify/"', compiled)
        page = (self.output / "app/index.html").read_text()
        self.assertIn('src="https://accounts.google.com/gsi/client"', page)
        self.assertIn("noindex,nofollow,noarchive,nosnippet", page)
        self.assertNotIn("Sign-in, payments and cloud sync are disabled", page)
        self.assertIn("Payments remain on pdd-drive.ru", page)
        landing = (self.output / "index.html").read_text()
        self.assertIn('href="https://pdd-drive.ru/tarify/"', landing)
        self.assertIn('href="https://pdd-drive.app/blog/"', landing)
        self.assertNotIn('/api/track', landing)
        policy = manifest["required_headers"]
        self.assertEqual(policy["Cross-Origin-Opener-Policy"], "same-origin-allow-popups")
        self.assertEqual(policy["Cross-Origin-Embedder-Policy"], "unsafe-none")
        self.assertNotIn("https://*.google.com", policy["Content-Security-Policy"])
        self.assertIn("https://accounts.google.com/gsi/", policy["Content-Security-Policy"])

    @unittest.skipUnless(shutil.which("node"), "Node is needed for exercising browser transport guards")
    def test_account_transport_guard_preserves_login_and_cloud_progress_but_blocks_checkout(self):
        harness = r'''
const vm=require('node:vm');const sent=[];const events={};
class XHR{open(method,url){sent.push(['xhr',method,url]);}}
const context={URL,DOMException,location:{origin:'https://pdd-drive.app'},document:{baseURI:'https://pdd-drive.app/app/',addEventListener:(name,fn)=>events[name]=fn},navigator:{sendBeacon:()=>{throw Error('beacon');}},XMLHttpRequest:XHR};
context.window=context;context.fetch=(input,options)=>{sent.push(['fetch',input,options?.method || 'GET']);return Promise.resolve('ok');};
context.open=(...args)=>{sent.push(['open',...args]);return 'opened';};
vm.runInNewContext(GUARD,context);
(async()=>{
 const allowed=[
  ['https://api.pdd-drive.app/api/auth/session',{method:'POST'}],
  ['https://pdd-install-notifier.sergei-pdd.workers.dev/api/auth/logout',{method:'POST'}],
  ['https://api.pdd-drive.app/api/user/status',{}],
  ['https://api.pdd-drive.app/api/user/sync',{method:'POST'}],
  ['https://api.pdd-drive.app/api/user/progress',{}],
  ['https://api.pdd-drive.app/api/user/progress/sync',{method:'POST'}],
  ['https://accounts.google.com/gsi/client',{}],['/app/canvaskit/canvaskit.wasm',{}],
 ];
 for(const args of allowed)await context.fetch(...args);
 const blocked=[
  ['https://api.pdd-drive.app/api/user/pay-intent',{method:'POST'}],
  ['https://api.pdd-drive.app/api/user/pay-check',{method:'POST'}],
  ['https://api.pdd-drive.app/api/user/delete',{method:'POST'}],
  ['https://api.pdd-drive.app/api/user/sync',{}],
  ['https://api.pdd-drive.app/api/admin/users',{}],
  ['https://api.pdd-drive.app/api/track',{method:'POST'}],
  ['https://api.pdd-drive.app.evil.test/api/user/status',{}],
  ['https://evil.test/api/user/status',{}], ['/api/user/status',{}],
  ['/app/%2561pi/status',{}], ['https://api.pdd-drive.app/%255capi/user/status',{}],
  ['http://api.pdd-drive.app/api/user/status',{}],
 ];let denied=0;
 for(const args of blocked)try{await context.fetch(...args);}catch(_){denied++;}
 new XHR().open('POST','https://api.pdd-drive.app/api/user/progress/sync');
 try{new XHR().open('POST','https://api.pdd-drive.app/api/user/pay-intent');}catch(_){denied++;}
 for(const url of ['about:blank','https://accounts.google.com/o/oauth2/auth','https://oauth.yandex.ru/authorize','https://appleid.apple.com/auth/authorize','https://pdd-drive.ru/tarify/','https://pdd-drive.ru/privacy.html','https://pdd-drive.ru/terms.html'])if(context.open(url)!=='opened')throw Error('navigation');
 for(const url of ['https://pay.example/','https://api.pdd-drive.app/api/user/pay-intent','https://pdd-drive.ru.evil.test/tarify/','https://pdd-drive.app/tarify/']){
   const expected=url==='https://pdd-drive.app/tarify/'?'opened':null;
   if(context.open(url)!==expected)throw Error('unexpected popup');
 }
 let prevented=0;events.click({target:{closest:()=>({href:'https://pay.example/'})},preventDefault(){prevented++;},stopImmediatePropagation(){}});
 events.submit({preventDefault(){prevented++;},stopImmediatePropagation(){}});
 if(context.navigator.sendBeacon('https://api.pdd-drive.app/api/track')!==false)throw Error('beacon');
 process.stdout.write(JSON.stringify({denied,sent,prevented,mode:context.__PDD_ACCOUNT_LOGIN_PREVIEW__}));
})();
'''
        result = subprocess.run([shutil.which("node"), "-e", "const GUARD=" + json.dumps(stage.ACCOUNT_ISOLATION_JS) + ";\n" + harness], text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["denied"], 13)
        self.assertEqual(len(data["sent"]), 17)
        self.assertEqual(data["prevented"], 2)
        self.assertTrue(data["mode"])

    @unittest.skipUnless(shutil.which("node"), "Node is needed for exercising browser transport guards")
    def test_account_rank_guard_allows_only_existing_read_endpoint(self):
        harness = r'''
const vm=require('node:vm');const sent=[];
class XHR{open(method,url){sent.push(['xhr',method,url]);}}
const context={URL,DOMException,location:{origin:'https://pdd-drive.app'},document:{baseURI:'https://pdd-drive.app/app/',addEventListener(){}},navigator:{},XMLHttpRequest:XHR};
context.window=context;context.fetch=(...args)=>{sent.push(['fetch',...args]);return Promise.resolve('synthetic');};context.open=()=>{};
vm.runInNewContext(GUARD,context);
(async()=>{
 let denied=0;
 for(const origin of ['https://api.pdd-drive.app','https://pdd-install-notifier.sergei-pdd.workers.dev']){
  const url=origin+'/api/game/best?userId=google_synthetic';
  await context.fetch(url);
  new XHR().open('GET',url);
  for(const method of ['POST','PUT','PATCH','DELETE','HEAD']){
   try{await context.fetch(url,{method});}catch(_){denied++;}
  }
  for(const path of [
   '/api/game/best/?userId=google_synthetic',
   '/api/game/best/extra?userId=google_synthetic',
   '/api/game/score?path=/api/game/best&userId=google_synthetic',
   '/api/game/best/extra?path=/api/game/best&userId=google_synthetic',
  ])try{await context.fetch(origin+path);}catch(_){denied++;}
 }
 for(const url of [
  '/api/game/best?userId=google_synthetic',
  'https://api.pdd-drive.app.evil.test/api/game/best?userId=google_synthetic',
  'http://api.pdd-drive.app/api/game/best?userId=google_synthetic',
 ])try{await context.fetch(url);}catch(_){denied++;}
 process.stdout.write(JSON.stringify({denied,sent}));
})();
'''
        result = subprocess.run([shutil.which("node"), "-e", "const GUARD=" + json.dumps(stage.ACCOUNT_ISOLATION_JS) + ";\n" + harness], text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["denied"], 21)
        self.assertEqual(len(data["sent"]), 4)

    @unittest.skipUnless(shutil.which("node"), "Node is needed for exercising browser transport guards")
    def test_account_telegram_guard_allows_only_existing_post_endpoints_and_exact_bot_links(self):
        harness = r'''
const vm=require('node:vm');const sent=[];const events={};
class XHR{open(method,url){sent.push(['xhr',method,url]);}}
const context={URL,DOMException,location:{origin:'https://pdd-drive.app'},document:{baseURI:'https://pdd-drive.app/app/',addEventListener:(name,fn)=>events[name]=fn},navigator:{},XMLHttpRequest:XHR};
context.window=context;context.fetch=(...args)=>{sent.push(['fetch',...args]);return Promise.resolve('synthetic');};
context.open=(...args)=>{sent.push(['open',...args]);return 'opened';};
vm.runInNewContext(GUARD,context);
(async()=>{
 let allowed=0,denied=0;
 for(const origin of ['https://api.pdd-drive.app','https://pdd-install-notifier.sergei-pdd.workers.dev']){
  for(const path of ['/api/auth/telegram/request','/api/auth/telegram/check']){
   await context.fetch(origin+path,{method:'POST'});allowed++;
   new XHR().open('POST',origin+path);allowed++;
   for(const method of ['GET','HEAD','PUT','DELETE'])try{await context.fetch(origin+path,{method});}catch(_){denied++;}
   for(const suffix of ['/','/extra'])try{await context.fetch(origin+path+suffix,{method:'POST'});}catch(_){denied++;}
  }
 }
 const nonce='auth_'+'a'.repeat(32);
 const valid=['https://t.me/pdda_bot?start='+nonce,'tg://resolve?domain=pdda_bot&start='+nonce,'tg://resolve?start='+nonce+'&domain=pdda_bot'];
 for(const url of valid){
  if(context.open(url)!=='opened')throw Error('valid bot navigation blocked');
  let prevented=false;events.click({target:{closest:()=>({href:url})},preventDefault(){prevented=true;},stopImmediatePropagation(){}});
  if(prevented)throw Error('valid bot link blocked');
 }
 const invalid=[
  'http://t.me/pdda_bot?start='+nonce,'https://t.me:8443/pdda_bot?start='+nonce,
  'https://user@t.me/pdda_bot?start='+nonce,'https://t.me.evil.test/pdda_bot?start='+nonce,
  'https://evil.t.me/pdda_bot?start='+nonce,'https://t.me/other_bot?start='+nonce,
  'https://t.me/pdda_bot/?start='+nonce,'https://t.me/pdda_bot?start='+nonce+'&extra=1',
  'https://t.me/pdda_bot?start='+nonce+'&start='+nonce,'https://t.me/pdda_bot?start='+nonce+'#extra',
  'https://t.me/pdda_bot?start=auth_'+'a'.repeat(31),'https://t.me/pdda_bot?start=auth_'+'A'.repeat(32),
  'tg://resolve?domain=other_bot&start='+nonce,'tg://resolve/?domain=pdda_bot&start='+nonce,
  'tg://resolve?domain=pdda_bot&start='+nonce+'&extra=1','tg://resolve?domain=pdda_bot&domain=pdda_bot&start='+nonce,
  'tg://resolve?domain=pdda_bot&start='+nonce+'&start='+nonce,'tg://other?domain=pdda_bot&start='+nonce,
  'tg:resolve?domain=pdda_bot&start='+nonce,'tg://user@resolve?domain=pdda_bot&start='+nonce,
 ];let navigationDenied=0;
 for(const url of invalid){
  if(context.open(url)!==null)throw Error('invalid bot navigation allowed: '+url);
  let prevented=false;events.click({target:{closest:()=>({href:url})},preventDefault(){prevented=true;},stopImmediatePropagation(){}});
  if(!prevented)throw Error('invalid bot link allowed');navigationDenied++;
 }
 for(const url of valid)try{await context.fetch(url);}catch(_){denied++;}
 process.stdout.write(JSON.stringify({allowed,denied,navigationDenied,sent}));
})();
'''
        result = subprocess.run([shutil.which("node"), "-e", "const GUARD=" + json.dumps(stage.ACCOUNT_ISOLATION_JS) + ";\n" + harness], text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["allowed"], 8)
        self.assertEqual(data["denied"], 27)
        self.assertEqual(data["navigationDenied"], 20)
        self.assertEqual(len(data["sent"]), 11)

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
   ['https://api.pdd-drive.app/api/auth/telegram/request',{method:'POST'}],
   ['https://pdd-install-notifier.sergei-pdd.workers.dev/api/auth/telegram/check',{method:'POST'}],
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
 for(const url of ['https://t.me/pdda_bot?start=auth_'+'a'.repeat(32),'tg://resolve?domain=pdda_bot&start=auth_'+'a'.repeat(32)])if(context.open(url)!==null)throw Error('guest telegram popup');
 let prevented=0;
 events.click({target:{closest:()=>({href:'https://pdd-drive.ru/tarify/'})},preventDefault(){prevented++},stopImmediatePropagation(){}});
 events.submit({preventDefault(){prevented++},stopImmediatePropagation(){}});
 process.stdout.write(JSON.stringify({denied,sent,prevented}));
})();
'''
        program = "const GUARD=" + json.dumps(stage.ISOLATION_JS) + ";\n" + harness
        result = subprocess.run([shutil.which("node"), "-e", program], text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        self.assertEqual(data["denied"], 13)
        self.assertEqual(data["prevented"], 2)
        self.assertEqual(data["sent"], [["fetch", "/app/canvaskit/canvaskit.wasm", "GET"]])


if __name__ == "__main__":
    unittest.main()
