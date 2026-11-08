// Real format controls and confirmations on an in-memory fixture. Only preview POSTs are allowed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[],writes=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('**/api/**',route=>{
      const req=route.request();
      if(req.method()!=='GET'&&!new URL(req.url()).pathname.startsWith('/api/preview/')){writes.push(req.url());return route.abort();}
      return route.continue();
    });
    await page.goto((process.env.EDITOR_URL||'http://127.0.0.1:8950')+'/?scene=ticket_5_7');
    await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.id==='ticket_5_7'&&document.querySelector('#loading').hidden);
    await page.evaluate(async()=>{
      const s={schema:1,id:'ticket_5_7',procedural:true,crop:90,layout:Layout.template('cross',90),
        question:{maneuver:'straight',yieldTo:[],correct:0,text:{ru:{title:'Куда можно продолжить движение?',options:['Прямо','Налево']}}},
        compliance:{status:'unverified'},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
      Layout.apply(s);const r=await App.api('/api/preview/'+s.id,s);
      App.state.S=s;App.state.id=s.id;App.state.build=r.build;App.state.findings=r.findings;App.state.edges=r.edges;
      App.state.savedJson=JSON.stringify(s);App.state.undo=[];App.state.redo=[];App.state.dirty=false;
      Scene3D.load(s,r.build);Tools.set('select');Scene3D.setMode('plan');App.select([]);App.showInspector();
    });
    const snapshot=()=>page.evaluate(()=>JSON.stringify(App.S));
    const original=await snapshot(),format=page.locator('[data-chip="scene-format"][data-value="compact"]');
    assert((await format.textContent()).includes('90 × 90 м'));
    await format.click();
    assert(await page.locator('#confirm').isVisible());
    assert.equal(await page.locator('#confirm-title').textContent(),'Сменить формат сцены?');
    await page.locator('#confirm [data-answer="no"]').click();
    assert.equal(await snapshot(),original);assert.equal(await page.evaluate(()=>App.state.undo.length),0);

    await format.click();await page.click('#confirm-yes');
    await page.waitForFunction(()=>App.S.crop===45&&App.S.layout.streets.length===1&&Scene3D.onRoad(0,30)&&!Scene3D.onRoad(30,0));
    const compact=await snapshot();
    assert.equal(await page.evaluate(()=>App.S.sceneFormat),'compact');
    assert.equal(await page.evaluate(()=>Layout.polyLen(Layout.centreline(App.S.layout,App.S.layout.streets[0]))),90);
    assert.equal(await page.evaluate(()=>App.state.undo.length),1);
    assert.equal(await format.getAttribute('aria-pressed'),'true');
    await format.click();assert(await page.locator('#confirm').isHidden(),'clicking the current format is a no-op');
    await page.click('#undo');assert.equal(await snapshot(),original);
    await page.waitForFunction(()=>Scene3D.onRoad(30,0));
    await page.click('#redo');assert.equal(await snapshot(),compact);
    await page.waitForFunction(()=>!Scene3D.onRoad(30,0));
    await page.click('#undo');assert.equal(await snapshot(),original);

    await page.evaluate(()=>{document.querySelector('#close-inspector')?.click();Tools.set('junction');});
    const shelf=page.locator('#popover [data-scene-format="compact"]');
    assert((await shelf.textContent()).includes('Прямая · 90 м'));
    await shelf.click();await page.keyboard.press('Escape');
    assert.equal(await snapshot(),original);
    await shelf.click();await page.click('#confirm-yes');
    await page.waitForFunction(()=>App.S.crop===45&&App.S.layout.streets.length===1&&!Scene3D.onRoad(30,0));
    assert.equal(await snapshot(),compact,'inspector and shelf create exactly the same format');
    assert.equal(await page.evaluate(()=>Tools.current()),'select');
    const output=path.resolve(__dirname,'../../../output/scene-format-custom-lanes.png');fs.mkdirSync(path.dirname(output),{recursive:true});
    await page.evaluate(()=>{App.select([]);App.showInspector();});
    await page.waitForFunction(()=>!document.querySelector('#toast').classList.contains('show'));
    await page.waitForTimeout(250);
    await page.screenshot({path:path.join(path.dirname(output),'scene-format-compact.png')});

    await page.evaluate(()=>{App.select({t:'street',id:App.S.layout.streets[0].id});App.showInspector();Scene3D.fit([-35,-52,35,52]);});
    await page.locator('[data-chip="kind"][data-value="avenue"]').click();
    const rightA=page.locator('[data-text="lanes-a-right"]');
    await rightA.fill('3');await rightA.blur();
    await page.waitForFunction(()=>Scene3D.onRoad(-9,-40)&&!Scene3D.onRoad(-9,40));
    const taper=page.locator('[data-text="lanes-taper"]');
    assert.equal(await taper.inputValue(),'22');assert.equal(await taper.getAttribute('max'),'22');
    assert.equal(await page.evaluate(()=>App.S.layout.streets[0].lanes.taper),40,'effective readout does not overwrite the saved request');
    const beforeTaper=await snapshot();
    await taper.fill('12');await taper.blur();
    assert.equal(await page.evaluate(()=>Layout.laneTransition(App.S.layout,App.S.layout.streets[0],App.S.crop).length),12);
    await page.click('#undo');assert.equal(await snapshot(),beforeTaper);
    const diagram=await page.locator('.lane-diagram polygon').first().getAttribute('points');
    const live=await page.evaluate(()=>{
      App.beginDrag();App.dragMove(sc=>{sc.layout.streets[0].bend=[25,0];});
      return Layout.laneTransition(App.S.layout,App.S.layout.streets[0],App.S.crop);
    });
    assert(live.length>22,'stretching the curve makes more room for its transition');
    assert.equal(Number(await taper.inputValue()),Math.round(live.length*1000)/1000,'held geometry changes refresh the actual transition');
    assert.equal(Number(await taper.getAttribute('max')),Math.round(live.max*1000)/1000);
    assert.notEqual(await page.locator('.lane-diagram polygon').first().getAttribute('points'),diagram,'miniature follows the actual profile during the drag');
    await page.evaluate(()=>App.cancelDrag());
    assert.equal(await snapshot(),beforeTaper);
    assert.equal(await taper.inputValue(),'22');
    await page.waitForFunction(()=>Scene3D.onRoad(-9,-40)&&!Scene3D.onRoad(-9,40)&&!Scene3D.onRoad(15,0));
    const result=await page.evaluate(()=>{
      const st=App.S.layout.streets[0],asphalt=App.state.build.surfaces.find(s=>s.id==='asphalt');
      const xs=asphalt.verts.filter((_,i)=>i%2===0),zs=asphalt.verts.filter((_,i)=>i%2===1);
      let drawn=null;const outline=Layout.streetOutline;
      Layout.streetOutline=(...args)=>{const points=outline(...args);drawn=points;return points;};
      try{Scene3D.refresh(App.S);}finally{Layout.streetOutline=outline;}
      return{crop:App.S.crop,length:Layout.polyLen(Layout.centreline(App.S.layout,st)),lanes:Layout.laneConfig(st),
        asphaltBounds:[Math.min(...xs),Math.min(...zs),Math.max(...xs),Math.max(...zs)],
        selectionBounds:drawn&&[Math.min(...drawn.map(p=>p[0])),Math.min(...drawn.map(p=>p[1])),Math.max(...drawn.map(p=>p[0])),Math.max(...drawn.map(p=>p[1]))],
        selectionEnds:drawn&&[-45,45].map(z=>[...new Set(drawn.filter(p=>p[1]===z).map(p=>p[0]))].sort((a,b)=>a-b)),
        findings:App.state.findings};
    });
    assert.deepEqual(result.lanes,{a:{left:2,right:3},b:{left:2,right:2},width:3.5,taper:40});
    assert.deepEqual(result.asphaltBounds,[-10.5,-45,7,45]);
    assert.deepEqual(result.selectionBounds,result.asphaltBounds,'the rendered selection follows asymmetric road edges');
    assert.deepEqual(result.selectionEnds,[[-10.5,7],[-7,7]],'the drawn outline matches both different endpoint widths');
    assert.deepEqual(result.findings,[],'the complete compact fixture has no geometry or route findings');
    await page.mouse.move(400,100);await page.waitForTimeout(100);await page.screenshot({path:output});
    assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
    console.log('Scene format browser: inspector + shelf, cancel/confirm, exact undo/redo, 90m preview and 2+3 → 2+2 visible geometry PASS');
    console.log(JSON.stringify(result));console.log(output);
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
