const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({channel:'chrome'});
 try {
  const page=await browser.newPage({viewport:{width:1500,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:8950/?scene=ticket_3_16');
  await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.layout);
  await page.evaluate(()=>App.select(App.S.layout.streets.map(s=>({t:'street',id:s.id}))));
  const shoulder=page.locator('label:has([data-toggle="bulk-road-shoulder"])');
  if(await page.locator('[data-toggle="bulk-road-shoulder"]').isChecked()) await shoulder.click();
  const before=await page.evaluate(()=>JSON.stringify(App.S.layout.streets));
  await shoulder.click();
  assert.equal(await page.locator('[data-chip="bulk-road-shoulder"]').count(),0);
  await page.waitForFunction(()=>App.state.build.surfaces.some(s=>s.id==='rural_shoulder'));
  assert.equal(await page.evaluate(()=>App.S.layout.streets.every(s=>s.shoulder===2.5&&s.walk===false)),true);
  assert.equal(await page.evaluate(()=>App.S.roads.filter(r=>r.id.startsWith('road_')&&r.shoulder).every(r=>r.walk===false)),true);
  await page.evaluate(()=>Scene3D.setView({...Scene3D.getView(),mode:'3d',orbitDist:65,x:0,z:0}));
  await page.screenshot({path:'output/shoulder-editor.png'});
  await page.evaluate(()=>App.undo());assert.equal(await page.evaluate(()=>JSON.stringify(App.S.layout.streets)),before);
  await page.evaluate(()=>App.redo());
  await page.locator('label:has([data-toggle="bulk-road-walk"])').click();
  assert.equal(await page.evaluate(()=>App.S.layout.streets.every(s=>!s.shoulder&&s.walk)),true);
  assert.deepEqual(errors,[]);
  console.log('PASS bulk shoulder UI, generated road metadata, undo/redo and switching back to sidewalk; no scene saved');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
