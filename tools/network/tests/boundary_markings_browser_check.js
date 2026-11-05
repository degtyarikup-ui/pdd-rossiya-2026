// Actual number/stepper controls, generated preview and narrow layout; no disk writes.
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:1000}}), errors=[],writes=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('**/api/**',route=>{
      const req=route.request();
      if(req.method()!=='GET'&&!new URL(req.url()).pathname.startsWith('/api/preview/')){writes.push(req.url());return route.abort();}
      return route.continue();
    });
    await page.goto((process.env.EDITOR_URL||'http://127.0.0.1:8950')+'/?scene=ticket_5_7');
    await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.id==='ticket_5_7'&&document.querySelector('#loading').hidden);
    await page.evaluate(async()=>{
      const s={schema:1,id:'ticket_5_7',procedural:true,crop:90,
        layout:{nodes:[{id:'a',x:0,z:-65},{id:'b',x:0,z:65}],streets:[{id:'st',a:'a',b:'b',kind:'street',ends:{}}],player:{street:'st',toward:'b'}},
        question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
      Layout.apply(s);const r=await App.api('/api/preview/'+s.id,s);
      App.state.S=s;App.state.id=s.id;App.state.build=r.build;App.state.findings=r.findings;App.state.edges=r.edges;
      App.state.savedJson=JSON.stringify(s);App.state.undo=[];App.state.redo=[];App.state.dirty=false;
      Scene3D.load(s,r.build);Tools.set('select');Scene3D.setMode('plan');Scene3D.fit([-35,-72,50,72]);
      App.select({t:'street',id:'st'});App.showInspector();
    });
    const original=await page.evaluate(()=>JSON.stringify(App.S));
    await page.click('[data-act="reversible-five"]');
    await page.waitForFunction(()=>App.S.markings.filter(m=>m.double==='dashed').length===2);
    assert.equal(await page.locator('.boundary-road [data-act="boundary-pick"]').count(),4);
    const five=await page.evaluate(()=>JSON.stringify(App.S));
    await page.click('#undo');assert.equal(await page.evaluate(()=>JSON.stringify(App.S)),original);
    await page.click('#redo');assert.equal(await page.evaluate(()=>JSON.stringify(App.S)),five);
    await page.click('[data-act="boundary-pick"][data-key="right-2"]');
    await page.click('[data-chip="boundary-style"][data-value="solid_dashed"]');
    assert.equal(await page.evaluate(()=>App.S.layout.streets[0].lineStyles['right-2']),'solid_dashed');
    await page.click('[data-chip="boundary-style"][data-value="dashed"]');
    await page.waitForTimeout(1200);
    await page.screenshot({path:path.resolve(__dirname,'../../../output/markings-redesign/desktop.png')});
    await page.setViewportSize({width:390,height:844});
    await page.evaluate(()=>{App.showInspector();document.querySelector('#inspector').scrollTop=0;});
    assert(await page.locator('#inspector').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'390px inspector has no horizontal overflow');
    assert(await page.locator('[data-act="boundary-pick"][data-key="centre"]').isVisible());
    await page.click('[data-act="boundary-pick"][data-key="all"]');
    await page.click('[data-chip="boundary-style"][data-value="double_dashed"]');
    assert.equal(await page.evaluate(()=>App.S.markings.filter(m=>m.double==='dashed').length),4);
    const output=path.resolve(__dirname,'../../../output/markings-redesign/mobile.png');fs.mkdirSync(path.dirname(output),{recursive:true});
    await page.screenshot({path:output});
    assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
    console.log('Boundary markings browser: preset, actual selectors, preview, undo/redo and compact 390px layout PASS');
    console.log(output);
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
