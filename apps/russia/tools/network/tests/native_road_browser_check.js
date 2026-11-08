// Real native-road editing on a private browser page. No scene is saved to disk.
// Only read-only preview POSTs are allowed; reload receives an in-memory saved draft.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const base = (process.env.EDITOR_URL || 'http://127.0.0.1:8950').replace(/\/$/,'');
const id = 'ticket_9_14';
const source = JSON.parse(fs.readFileSync(path.resolve(__dirname,`../../../game_godot/network/${id}.json`),'utf8'));
const output = path.resolve(__dirname,'../../../output/native-road-editor.png');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors=[],writes=[];
    let savedEnvelope=null;
    page.on('pageerror',error=>errors.push(error.message));
    page.on('dialog',dialog=>dialog.accept());
    await page.route('**/api/**',route=>{
      const req=route.request(), pathname=new URL(req.url()).pathname;
      if(req.method()==='POST'&&!pathname.startsWith('/api/preview/')) {
        writes.push(pathname);return route.abort();
      }
      if(req.method()==='GET'&&pathname===`/api/scene/${id}`&&savedEnvelope)
        return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(savedEnvelope)});
      return route.continue();
    });
    await page.goto(`${base}/?scene=${id}`);
    const loaded=()=>page.waitForFunction(id=>typeof App!=='undefined'&&App.S?.id===id&&document.querySelector('#loading').hidden,id);
    await loaded();
    const snapshot=()=>page.evaluate(()=>JSON.stringify(App.S));
    const current=()=>page.evaluate(()=>JSON.parse(JSON.stringify(App.S)));
    const original=await snapshot();assert.deepEqual(await current(),source,'opening keeps the authored document intact');
    await page.evaluate(()=>{Scene3D.setMode('plan');Scene3D.fit([-95,-95,95,95]);App.closeLeftPanel();});
    async function screen(x,z,y=.4) {
      return page.evaluate(([x,z,y])=>{
        const rect=document.querySelector('#view canvas').getBoundingClientRect(),p=Scene3D.screenOf(x,z,y);
        return {x:rect.left+p.x,y:rect.top+p.y};
      },[x,z,y]);
    }
    async function clickWorld(x,z) {const p=await screen(x,z,0);await page.mouse.click(p.x,p.y);}
    const roadAt=(x,z)=>page.evaluate(([x,z])=>Scene3D.onRoad(x,z),[x,z]);
    const waitRoad=(x,z,on=true)=>page.waitForFunction(([x,z,on])=>Scene3D.onRoad(x,z)===on,[x,z,on]);
    const inspect=async()=>{
      await page.evaluate(()=>{Tools.set('select');App.select({t:'road',id:'road_0'});App.showInspector();});
      await page.locator('[data-text="shape-center-x"]').waitFor();
    };
    const assertSource=async()=>{
      const scene=await current();
      for(const key of Object.keys(source)) {
        if(['roads','markings','lawns'].includes(key)) assert.deepEqual(scene[key].filter(x=>!x.planGenerated),source[key],key);
        else assert.deepEqual(scene[key],source[key],key);
      }
      assert.equal(scene.roads.find(r=>r.id==='road_0').outer.length,139);
      assert(await roadAt(-70,0),'the interior dead end remains asphalt');
    };

    await clickWorld(-70,0);
    assert.equal(await page.evaluate(()=>App.state.sel[0]?.t),'road','dead end selects the native road directly');
    await inspect();
    assert.equal(await page.locator('#inspector [data-act="convert"]').count(),0);
    assert(!/конструктор|перевести/i.test(await page.locator('#inspector').innerText()));
    assert.equal(await snapshot(),original,'browsing the native panel is not a conversion');
    assert.equal(await page.locator('[data-text="shape-index"]').getAttribute('max'),'139');

    // Zoom far enough to distinguish dense neighbours, then drag an actual contour vertex.
    async function widenNativePoint() {
      await inspect();
      await page.evaluate(()=>Scene3D.fit([-15,60,28,96]));
      const vertex=await page.evaluate(()=>App.S.roads.find(r=>r.id==='road_0').outer[137]);
      const from=await screen(...vertex),to=await screen(vertex[0]+8,vertex[1]);
      const hit=await page.evaluate(([x,z])=>{const p=Scene3D.screenOf(x,z,.4);return Scene3D.hitAt(p.x,p.y);},vertex);
      assert.equal(hit?.v,137,'the visible contour handle maps to the intended vertex');
      const shapes=new Set();
      await page.mouse.move(from.x,from.y);await page.mouse.down();
      for(let i=1;i<=12;i++) {
        await page.mouse.move(from.x+(to.x-from.x)*i/12,from.y+(to.y-from.y)*i/12);
        await page.waitForTimeout(60);
        shapes.add(await page.evaluate(()=>JSON.stringify(App.state.build.surfaces.find(s=>s.id==='asphalt')?.verts)));
      }
      await page.mouse.up();
      const changed=await page.evaluate(()=>App.S.roads.find(r=>r.id==='road_0').outer[137]);
      assert(Math.abs(changed[0]-(vertex[0]+8))<.3,'vertex follows the pointer');
      assert.equal(await page.locator('[data-text="shape-index"]').inputValue(),'138');
      assert(shapes.size>=2,'real server-built asphalt updates during the native drag');
      await waitRoad(9,75);
      return shapes.size;
    }
    assert.equal(await roadAt(9,75),false);
    const liveShapes=await widenNativePoint();
    assert.equal(await page.evaluate(()=>App.S.roads[0].outer.length),139);
    const changed=await snapshot();assert.notEqual(changed,original);
    await page.click('#undo');assert.equal(await snapshot(),original);await waitRoad(9,75,false);
    await page.click('#redo');assert.equal(await snapshot(),changed);await waitRoad(9,75);
    await page.click('#undo');assert.equal(await snapshot(),original);await waitRoad(9,75,false);

    // Numeric shape controls remain compact and exact; the change affects the chosen road only.
    const x=Number(await page.locator('[data-text="shape-center-x"]').inputValue());
    await page.locator('[data-text="shape-center-x"]').fill(String(x+1.25));
    await page.locator('[data-text="shape-center-x"]').press('Tab');
    assert(Math.abs(await page.evaluate(()=>App.shapeCenter(App.state.sel[0])[0])-(x+1.25))<.001);
    await page.click('#undo');assert.equal(await snapshot(),original);

    // Drawing the first new street is additive, including when no previous layout exists.
    await page.click('#close-inspector');
    await page.evaluate(()=>Scene3D.fit([-95,-70,95,95]));
    await page.keyboard.press('r');
    await clickWorld(30,25);assert.equal(await snapshot(),original);
    await clickWorld(30,50);await page.keyboard.press('Escape');
    await page.waitForFunction(()=>App.S.layout?.preserveSource&&App.S.layout.streets.length===1);
    await waitRoad(30,38);await assertSource();
    const added=await snapshot();
    await page.click('#undo');assert.equal(await snapshot(),original);await waitRoad(30,38,false);
    await page.click('#redo');assert.equal(await snapshot(),added);await waitRoad(30,38);await assertSource();

    // The native shape remains independently selectable/editable beside generated streets.
    await page.keyboard.press('v');await page.evaluate(()=>{App.select([]);Scene3D.fit([-95,-70,95,95]);});
    await clickWorld(-70,0);assert.equal(await page.evaluate(()=>App.state.sel[0]?.id),'road_0');
    await widenNativePoint();assert(await roadAt(-70,0));
    await page.click('#undo');assert.equal(await snapshot(),added);await waitRoad(9,75,false);await assertSource();

    // Persist/reopen without any disk writes: serve the serialized draft through the GET endpoint.
    savedEnvelope=await page.evaluate(async()=>{
      const scene=JSON.parse(JSON.stringify(App.S));
      const preview=await App.api('/api/preview/'+scene.id,scene);
      return {...preview,scene,source:App.state.source,playable:App.state.playable};
    });
    await page.reload();await loaded();
    assert.equal(await snapshot(),added,'reopening preserves source shapes and additive graph exactly');
    await waitRoad(30,38);await assertSource();
    await inspect();
    await page.evaluate(()=>{Scene3D.setMode('3d');Scene3D.fit([-93,-45,55,65]);});
    await page.mouse.move(950,90);
    await page.waitForTimeout(250);
    fs.mkdirSync(path.dirname(output),{recursive:true});await page.screenshot({path:output});

    await page.setViewportSize({width:520,height:800});
    await page.evaluate(()=>App.showInspector());
    assert(await page.locator('#inspector').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'compact native panel has no horizontal overflow');
    assert.equal(await page.locator('#inspector details, #inspector summary').count(),0);
    assert.equal(await page.locator('[data-text="shape-index"]').getAttribute('max'),'139');
    assert.equal(await snapshot(),added,'narrow layout and panel inspection keep data intact');
    assert.deepEqual(writes,[],'no scene write, save or publication was attempted');
    assert.deepEqual(errors,[]);
    console.log(`Native road browser: ${liveShapes} live asphalt shapes, 139 vertices, dead end, native fields, additive street, undo/redo, in-memory reload and 520px panel PASS`);
    console.log(output);
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
