// End-to-end review stand, with the production engine injected by the local server.
// Start scripts/game_lab.sh; run with NODE_PATH pointing at Playwright.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({headless:true,
    executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args:['--use-angle=swiftshader']});
  try {
    const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto((process.env.GAME_LAB_URL || 'http://127.0.0.1:8940')+'/#road_14_2');
    await page.waitForFunction(()=>typeof lab!=='undefined' && current?.id==='road_14_2');
    const catalog=await page.evaluate(()=>items.filter(i=>i.reviewed).map(i=>({id:i.id,kind:i.kind,
      checks:checks(i).slice(0,3),source:original(i)?.id})));
    assert.equal(catalog.filter(i=>i.kind!=='event').length,166);
    assert.equal(catalog.filter(i=>i.kind==='event').length,7);
    assert.equal(new Set(catalog.map(i=>i.id)).size,catalog.length);
    for(const i of catalog.filter(i=>i.kind!=='event')) {
      assert.ok(i.source,i.id+' must have a source');
      assert.ok(i.checks.every(c=>c.ok),i.id+' source mismatch');
    }
    for(const [index,item] of catalog.entries()) {
      const r=await page.evaluate(id=>{open(id);return {id:lab.lab.id,selected:current.id,
        camera:lab.run('cameraViewSize'),question:frame.contentDocument.querySelector('.lab-sheet p')?.textContent,
        source:original(current)?.question};},item.id);
      assert.equal(r.id,item.id);assert.equal(r.selected,item.id);assert.ok(Number.isFinite(r.camera));
      if(item.kind!=='event')assert.equal(r.question,r.source);
      if(index%40===0)console.log('Rendered',index+1,'/',catalog.length);
    }
    await page.evaluate(()=>open('road_14_2'));
    assert.ok(await page.evaluate(()=>lab.run('cameraViewSize < 55')),'shoulder scene should remain readable');
    await page.locator('#darkTheme').check();
    assert.equal(await page.evaluate(()=>frame.contentDocument.querySelector('.lab-sheet').classList.contains('dark')),true);
    await page.locator('#phoneCard').uncheck();
    assert.equal(await page.evaluate(()=>lab.state.viewportInsets.bottom),0);
    await page.locator('#phoneCard').check();
    // New road geometry must use the same weather colour and upward normals as
    // the straight road. This catches the visible straight/curved asphalt join.
    const surface=await page.evaluate(()=>{
      lab.run('state.rain=1');open('road_19_16');
      return lab.run(`(() => {
        const ev=state.roadEvent,colors=new Set();let upward=true;
        for(const root of state.roadSegments)root.traverse(o=>{
          if(o.userData.surface!=='road' && !o.material?.userData.asphalt)return;
          if(o.material.color)colors.add(o.material.color.getHex());
          if(o.geometry.type==='BufferGeometry' && o.geometry.attributes.normal) {
            const n=o.geometry.attributes.normal;for(let i=0;i<n.count;i++)if(n.getY(i)<-.9)upward=false;
          }
        });return {colors:[...colors],upward};
      })()`);
    });
    assert.equal(surface.colors.length,1,'wet asphalt colour must agree across segment joins');
    assert.ok(surface.upward,'ribbon normals must point up');
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({questions:166,events:7,rendered:catalog.length,sourceMatched:true,phonePreview:true,roadJoin:true}));
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
