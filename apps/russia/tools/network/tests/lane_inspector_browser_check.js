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
    const field=key=>page.locator(`[data-text="lanes-${key}"]`);
    await field('a-right').fill('3');await field('a-right').blur();
    await page.waitForFunction(()=>App.S.layout.streets[0].lanes?.a.right===3);
    assert.equal(await page.locator('.road-profiles [aria-pressed="true"]').count(),0);
    assert.equal(await page.evaluate(()=>App.state.undo.length),1);
    await page.click('#undo');assert.equal(await page.evaluate(()=>JSON.stringify(App.S)),original);
    await page.click('#redo');
    await page.locator('[data-act="lane-step"][data-key="b-right"][data-step="1"]').click();
    await field('width').fill('3.5');await field('width').blur();
    await field('taper').fill('55');await field('taper').blur();
    await page.waitForFunction(()=>App.S.layout.streets[0].lanes.taper===55);
    await page.waitForTimeout(350);
    assert.equal(await field('b-right').inputValue(),'2');
    assert.equal(await field('width').inputValue(),'3.5');
    assert.equal(await page.locator('#inspector details,#inspector summary').count(),0);
    const custom=await page.evaluate(()=>JSON.stringify(App.S));
    await page.locator('[data-chip="kind"][data-value="street"]').click();
    assert.equal(await page.evaluate(()=>App.S.layout.streets[0].lanes),undefined);
    await page.click('#undo');assert.equal(await page.evaluate(()=>JSON.stringify(App.S)),custom);

    await page.evaluate(()=>{App.state.locked.add('roads');App.renderInspector();});
    assert(await field('a-right').isDisabled());
    assert(await page.locator('[data-act="lane-step"][data-key="a-right"][data-step="1"]').isDisabled());
    await page.evaluate(()=>{App.state.locked.delete('roads');App.renderInspector();});
    await page.setViewportSize({width:390,height:844});
    await page.evaluate(()=>{App.showInspector();document.querySelector('#inspector').scrollTop=0;});
    assert(await page.locator('#inspector').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'390px inspector has no horizontal overflow');
    for(const key of ['a-left','a-right','b-left','b-right']) {
      assert(await field(key).isVisible());
      assert(await field(key).evaluate(el=>el.getBoundingClientRect().width>=20),'counts remain readable');
    }
    await page.locator('[data-act="lane-step"][data-key="a-left"][data-step="1"]').click();
    assert.equal(await field('a-left').inputValue(),'2');
    const output=path.resolve(__dirname,'../../../output/lane-inspector-mobile.png');fs.mkdirSync(path.dirname(output),{recursive:true});
    await page.screenshot({path:output});
    assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
    console.log('Lane inspector browser: actual fields/steppers, custom preset state, undo/redo, locked controls and compact 390px layout PASS');
    console.log(output);
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
