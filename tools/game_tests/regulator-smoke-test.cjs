// Browser regression of the exported Godot game. Requires Playwright and Chrome.
// GAME_WEB_DIR=<export directory> node tools/game_tests/regulator-smoke-test.cjs
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const root = path.resolve(__dirname, '../..');
const base = path.resolve(process.env.GAME_WEB_DIR || path.join(root, 'build/web/godot'));
const output = path.join(root,'output/game-review/regulator-smoke');
fs.mkdirSync(output,{recursive:true});
const errors = [];
const server = http.createServer((req,res) => {
  if (req.url === '/') {
    const args = new URLSearchParams({regulator:'1',auto:'1',lang:'en',mute:'1',paint:'#0574F8',
      economy:JSON.stringify({seconds:3,lives:5,maxScore:1500,base:24,step:2,bonusCap:4}),
      'screen-dp':'390','session-id':'browser-test','best-score':'500'});
    res.setHeader('Content-Type','text/html');
    res.end(`<style>body{margin:0}iframe{width:390px;height:844px;border:0}</style><iframe src="/index.html?${args}"></iframe><script>window.events=[];addEventListener('message',e=>{try{events.push(JSON.parse(e.data))}catch{}})</script>`);
    return;
  }
  const url = new URL(req.url,'http://localhost');
  const file = path.resolve(base, '.'+decodeURIComponent(url.pathname));
  if (!file.startsWith(base+path.sep) || !fs.existsSync(file)) {res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type', ({'.wasm':'application/wasm','.js':'application/javascript','.html':'text/html','.pck':'application/octet-stream','.png':'image/png'})[path.extname(file)] || 'application/octet-stream');
  fs.createReadStream(file).pipe(res);
});
(async()=>{
 let browser;
 try {
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--enable-webgl','--use-angle=swiftshader','--disable-web-security']});
  const page=await browser.newPage({viewport:{width:390,height:844}});
  page.on('pageerror', e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error' && /SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(m.text())});
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.waitForFunction(()=>events.some(e=>{try{const d=JSON.parse(e.json);return d.summary?.runs?.some(r=>r.finished)}catch{return false}}),null,{timeout:60000});
  await page.screenshot({path:path.join(output,'web-result.png')});
  const packets=await page.evaluate(()=>events);
  const last=packets.filter(p=>p.kind==='send').map(p=>JSON.parse(p.json)).at(-1);
  assert.equal(last.summary.runs.length,1);
  assert.equal(last.summary.runs[0].id,'browser-test-1');
  assert(last.summary.runs[0].solved>0);
  assert(last.summary.runs[0].score<=1500);
  assert.equal(errors.length,0,errors.join('\n'));
  // Restart inside the engine, then use its own Exit button: both rounds survive.
  await page.mouse.click(195,589);
  await page.waitForFunction(()=>events.some(e=>{try{const d=JSON.parse(e.json);return d.summary?.runs?.some(r=>r.id==='browser-test-2' && r.finished)}catch{return false}}),null,{timeout:20000});
  await page.mouse.click(195,639);
  await page.waitForFunction(()=>events.some(e=>e.kind==='exit'),null,{timeout:10000});
  const exit=await page.evaluate(()=>events.find(e=>e.kind==='exit'));
  const summary=JSON.parse(exit.json);
  assert.equal(summary.runs.length,2);
  assert.deepEqual(summary.runs.map(r=>r.id),['browser-test-1','browser-test-2']);
  for (const run of summary.runs) {
    const expected=Array.from({length:run.solved},(_,i)=>24+Math.min(i,4)*2).reduce((a,b)=>a+b,0);
    assert.equal(run.score,Math.min(expected,1500));
    assert.equal(run.finished,true);
  }
  assert.equal(errors.length,0,errors.join('\n'));
  fs.writeFileSync(path.join(output,'web-packets.json'),JSON.stringify(await page.evaluate(()=>events),null,2));
  console.log('Web regulator: encoded arguments, timer, scoring, checkpoints, restart and exit PASS');
 } finally {await browser?.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
