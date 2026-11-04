// Local editor smoke test; operates only on unsaved in-memory scene copies.
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs');
const base=process.env.EDITOR_URL || 'http://127.0.0.1:8950';
(async()=>{
 const browser=await chromium.launch({channel:'chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1500,height:1000}}),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.goto(base+'/?scene=ticket_5_4');
  await page.waitForFunction(()=>typeof App!=='undefined' && App.S?.id==='ticket_5_4' && App.state.build);
  const source=await page.evaluate(()=>JSON.stringify(App.S.roads));
  await page.evaluate(()=>{Scene3D.setMode('plan');Scene3D.fit([-22,-30,22,30]);});
  await page.locator('[data-tool="road"]').click();
  await page.locator('[data-shelf-tool="pocket"]').click();
  const location=await page.evaluate(()=>{const p=Scene3D.screenOf(5,0),r=document.querySelector('#view').getBoundingClientRect();return {x:p.x+r.left,y:p.y+r.top};});
  await page.mouse.move(location.x,location.y);await page.mouse.click(location.x,location.y);
  await page.waitForFunction(()=>App.S.pockets?.length===1);
  assert.equal(await page.evaluate(()=>App.state.sel[0].t),'pocket');
  await page.evaluate(()=>App.showInspector?.());
  const width=page.locator('[data-text="pocket-width"]');await width.fill('5');await width.press('Tab');
  const entry=page.locator('[data-text="pocket-entryLength"]');await entry.fill('12');await entry.press('Tab');
  const exit=page.locator('[data-text="pocket-exitLength"]');await exit.fill('6');await exit.press('Tab');
  await page.waitForFunction(()=>App.state.build.surfaces.find(s=>s.id==='asphalt')?.verts.some((v,i)=>i%2===0&&v>8));
  assert.equal(await page.evaluate(()=>App.S.pockets[0].width),5);
  assert.equal(await page.evaluate(()=>JSON.stringify(App.S.roads)),source);
  fs.mkdirSync('output/editor-pockets-parking',{recursive:true});
  await page.evaluate(()=>{Scene3D.setMode('3d');Scene3D.fit([-18,-25,18,25]);});
  await page.waitForLoadState('networkidle');
  await page.screenshot({path:'output/editor-pockets-parking/pocket-editor.png'});
  const saved=await page.evaluate(()=>JSON.stringify(App.S.pockets));
  await page.evaluate(()=>App.duplicate());assert.equal(await page.evaluate(()=>App.S.pockets.length),2);
  await page.evaluate(()=>App.undo());assert.equal(await page.evaluate(()=>JSON.stringify(App.S.pockets)),saved);
  // The complete fuel site is one undoable insertion, with independent selectable parts.
  await page.evaluate(()=>{Tools.pickPreset('fuel_station');Scene3D.setMode('plan');Scene3D.fit([-65,-60,65,60]);});
  const site=await page.evaluate(()=>{const p=Scene3D.screenOf(30,0),r=document.querySelector('#view').getBoundingClientRect();return {x:p.x+r.left,y:p.y+r.top};});
  const counts=await page.evaluate(()=>({decor:App.S.decor.length,roads:App.S.roads.length,markings:App.S.markings.length,undo:App.state.undo.length}));
  await page.mouse.move(site.x,site.y);await page.mouse.click(site.x,site.y);
  await page.waitForFunction(()=>App.S.decor.some(p=>p.prop==='parking/fuel_pump'));
  assert.equal(await page.evaluate(()=>App.state.undo.length),counts.undo+1);
  await page.waitForFunction(()=>{
    const expected=Math.max(...App.S.roads.filter(r=>r.surface==='asphalt').flatMap(r=>r.outer.map(p=>p[0])));
    return App.state.build.surfaces.find(s=>s.id==='asphalt')?.verts.some((v,i)=>i%2===0&&v>=expected-.01);
  });
  await page.waitForLoadState('networkidle');
  const ids=await page.evaluate(()=>App.S.decor.filter(p=>p.prop.startsWith('parking/')).map(p=>p.id));assert(ids.length>5);
  const positions=await page.evaluate(()=>App.S.decor.map(p=>[p.id,...p.pos]));
  await page.evaluate(id=>{App.select({t:'decor',id});App.nudge(1,0);},ids[0]);
  const after=await page.evaluate(()=>App.S.decor.map(p=>[p.id,...p.pos]));
  assert.equal(after.filter((p,i)=>JSON.stringify(p)!==JSON.stringify(positions[i])).length,1);
  await page.evaluate(()=>{App.select([]);Scene3D.setMode('3d');Scene3D.fit([-10,-35,65,35]);});
  await page.waitForLoadState('networkidle');
  await page.screenshot({path:'output/editor-pockets-parking/fuel-station-editor.png'});
  await page.evaluate(()=>App.undo());await page.evaluate(()=>App.undo());
  assert.deepEqual(await page.evaluate(()=>({decor:App.S.decor.length,roads:App.S.roads.length,markings:App.S.markings.length})),{decor:counts.decor,roads:counts.roads,markings:counts.markings});
  assert.deepEqual(errors,[]);
  console.log('PASS browser pocket placement/inspector/geometry/history and complete editable fuel-site insertion; no scene saved');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
