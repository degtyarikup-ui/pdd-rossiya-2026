// Real pointer gestures and server-built surfaces on a disposable browser fixture.
// POST writes are blocked; the only permitted POST is the read-only preview builder.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors = [], writes = [];
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('**/api/**',route=>{
      const request = route.request(), pathname = new URL(request.url()).pathname;
      if (request.method()==='POST' && !pathname.startsWith('/api/preview/')) {
        writes.push(pathname); return route.abort();
      }
      return route.continue();
    });
    await page.goto('http://127.0.0.1:8950/?scene=ticket_5_7');
    await page.waitForFunction(()=>typeof App!=='undefined' && App.S?.id==='ticket_5_7' && document.querySelector('#loading').hidden);
    await page.evaluate(async()=>{
      const s = {schema:1,id:'ticket_5_7',procedural:true,crop:70,
        layout:{nodes:[{id:'a',x:0,z:-40},{id:'b',x:0,z:40}],streets:[{id:'st',a:'a',b:'b',kind:'avenue',ends:{}}],player:{street:'st',toward:'b'}},
        question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
      Layout.apply(s);
      const result = await App.api('/api/preview/ticket_5_7',s);
      App.state.S=s; App.state.id=s.id; App.state.plan=null; App.state.build=result.build;
      App.state.savedJson=JSON.stringify(s); App.state.undo=[]; App.state.redo=[]; App.state.dirty=false;
      App.state.findings=result.findings; App.state.edges=result.edges;
      Scene3D.load(s,result.build); Tools.set('select'); App.select({t:'street',id:'st'});
      App.showInspector(); Scene3D.setMode('plan'); Scene3D.fit([-35,-50,45,50]);
      App.renderTop();
    });
    const snapshot = ()=>page.evaluate(()=>JSON.stringify(App.S));
    const original = await snapshot();
    async function screen(x,z,y=.4) {
      return page.evaluate(([x,z,y])=>{
        const rect=document.querySelector('#view canvas').getBoundingClientRect(), p=Scene3D.screenOf(x,z,y);
        return {x:rect.left+p.x,y:rect.top+p.y};
      },[x,z,y]);
    }
    const bounds = () => page.evaluate(()=>{
      const points=App.state.build.surfaces.filter(s=>s.id==='asphalt').flatMap(s=>s.verts);
      const xs=points.filter((_,i)=>i%2===0),zs=points.filter((_,i)=>i%2===1);
      return [Math.min(...xs),Math.min(...zs),Math.max(...xs),Math.max(...zs)].map(v=>Math.round(v*1000)/1000);
    });
    const initialBounds=await bounds();
    assert(initialBounds.every(Number.isFinite),'fixture has rendered asphalt');
    await page.waitForFunction(()=>Array.from(document.querySelectorAll('.tag.road-end')).filter(el=>el.style.display!=='none').length===2);
    assert.deepEqual((await page.locator('.tag.road-end').allTextContents()).sort(),['A','B']);
    const midpoint=await screen(0,0), target=await screen(22,0);
    await page.mouse.move(midpoint.x,midpoint.y); await page.mouse.down();
    const during=new Set();
    for(let i=1;i<=15;i++) {
      await page.mouse.move(midpoint.x+(target.x-midpoint.x)*i/15,midpoint.y+(target.y-midpoint.y)*i/15);
      await page.waitForTimeout(50);
      during.add(JSON.stringify(await bounds()));
    }
    assert(during.size>=3,`road surfaces must rebuild during an uninterrupted drag, observed ${during.size}`);
    const liveLength=await page.locator('[data-text="road-length"]').inputValue();
    const actualLength=await page.evaluate(()=>Layout.polyLen(Layout.centreline(App.S.layout,App.S.layout.streets[0])));
    assert(Math.abs(Number(liveLength)-actualLength)<.11,'length follows a held bend handle');
    assert(await page.locator('[data-act="straighten"]').isEnabled(),'straighten updates before pointer release');
    await page.mouse.up();
    await page.waitForFunction(()=>Scene3D.onRoad(22,0) && !Scene3D.onRoad(0,0));
    const curvedBounds=await bounds();
    assert(curvedBounds[2]>initialBounds[2]+15,'asphalt vertices follow the new curve');
    const curved=await snapshot();
    assert.equal(await page.evaluate(()=>App.state.undo.length),1,'one gesture is one undo step');
    await page.click('#undo'); assert.equal(await snapshot(),original);
    await page.waitForFunction(()=>Scene3D.onRoad(0,0) && !Scene3D.onRoad(22,0));
    await page.click('#redo'); assert.equal(await snapshot(),curved);
    await page.waitForFunction(()=>Scene3D.onRoad(22,0) && !Scene3D.onRoad(0,0));

    // Drag an endpoint away from its own old centreline. The body and angle follow.
    const beforeNode=await snapshot(), endpoint=await screen(0,40), nextEndpoint=await screen(-18,28);
    await page.mouse.move(endpoint.x,endpoint.y); await page.mouse.down();
    await page.mouse.move(nextEndpoint.x,nextEndpoint.y,{steps:12});
    assert(Math.abs(Number(await page.locator('[data-text="node-x"]').inputValue())+18)<1,'node coordinate follows the held endpoint');
    await page.mouse.up();
    await page.waitForFunction(()=>Math.abs(Layout.nodeOf(App.S.layout,'b').x+18)<1);
    const moved=await page.evaluate(()=>Layout.nodeOf(App.S.layout,'b'));
    assert(Math.abs(moved.z-28)<1,'endpoint follows both pointer axes');
    await page.evaluate(()=>App.select({t:'street',id:'st'}));
    assert(Number(await page.locator('[data-text="road-heading"]').inputValue())>340,'direction reflects moved endpoint');
    await page.click('#undo'); assert.equal(await snapshot(),beforeNode);
    await page.evaluate(()=>App.select({t:'street',id:'st'}));
    await page.locator('[data-act="straighten"]').click();
    assert.equal(await page.evaluate(()=>App.S.layout.streets[0].bend),undefined);
    assert(await page.locator('[data-act="straighten"]').isDisabled());
    await page.click('#undo'); assert.equal(await snapshot(),curved);

    // Refreshing live readouts never overwrites a numeric value being typed.
    const heading=page.locator('[data-text="road-heading"]');
    await heading.focus(); await heading.fill('123.4');
    await page.evaluate(()=>App.refreshRoadGeometry());
    assert.equal(await heading.inputValue(),'123.4');
    await heading.fill('0'); await heading.blur();
    assert.equal(await snapshot(),curved);
    await page.waitForFunction(()=>Scene3D.onRoad(22,0));
    await page.evaluate(()=>{Scene3D.setMode('3d');Scene3D.fit([-25,-48,40,48]);});
    const output=path.resolve(__dirname,'../../../output/road-editor-final.png');
    fs.mkdirSync(path.dirname(output),{recursive:true});
    await page.mouse.move(950,100);
    await page.waitForTimeout(120);
    await page.screenshot({path:output});

    await page.setViewportSize({width:390,height:844});
    await page.evaluate(()=>{Scene3D.setMode('plan');App.showInspector();});
    assert(await page.locator('#inspector').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'phone property panel has no horizontal overflow');
    await page.click('#close-inspector');
    await page.evaluate(()=>{App.select({t:'street',id:'st'});Scene3D.fit([-20,-48,40,48]);});
    const phoneMid=await screen(22,0), phoneTarget=await screen(15,0);
    await page.mouse.move(phoneMid.x,phoneMid.y);await page.mouse.down();
    await page.mouse.move(phoneTarget.x,phoneTarget.y,{steps:10});await page.mouse.up();
    await page.waitForFunction(()=>Math.abs(App.S.layout.streets[0].bend[0]-30)<2);
    await page.waitForFunction(()=>Scene3D.onRoad(15,0));
    assert.deepEqual(writes,[],'test never saves or publishes');
    assert.deepEqual(errors,[]);
    console.log(`Road editing browser: ${during.size} live surface shapes, exact bend/body alignment, live fields, endpoints, undo/redo, 3D and phone PASS`);
    console.log(output);
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
