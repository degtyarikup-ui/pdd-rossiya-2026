// A world-sized label must track the camera, including the phone preview.
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({channel:'chrome'});
 try {
  const page=await browser.newPage({viewport:{width:1500,height:1000}});
  await page.goto('http://127.0.0.1:8950/?scene=ticket_3_12');
  await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.id==='ticket_3_12');
  await page.evaluate(()=>{
   App.edit(s=>s.routes.push({id:'projection_fixture',kind:'annotation',style:'text',text:'3 м',textSize:1,points:[[-.1,0],[.1,0]]}));
   Scene3D.setView({...Scene3D.getView(),mode:'plan',pxPerM:20,x:0,z:0});
  });
  const label=page.locator('.annotation-text').filter({hasText:'3 м'}).last();
  await page.waitForTimeout(100);
  let size=await label.evaluate(el=>parseFloat(getComputedStyle(el).fontSize));
  assert.ok(Math.abs(size-64*.018*20)<.01,`world size at 20 px/m: ${size}`);
  assert.equal(await label.evaluate(el=>getComputedStyle(el).translate),'-50% -50%');
  await page.evaluate(()=>Scene3D.setView({...Scene3D.getView(),pxPerM:40}));
  await page.waitForTimeout(100);
  size=await label.evaluate(el=>parseFloat(getComputedStyle(el).fontSize));
  assert.ok(Math.abs(size-64*.018*40)<.01,`world size after zoom: ${size}`);
  const expected=await page.evaluate(()=>{
   const view=QuestionCamera.normalize({});Scene3D.setPhone(view);
   return 64*.018*Scene3D.phoneRect().h/QuestionCamera.pose(view).size;
  });
  await page.waitForTimeout(100);
  size=await label.evaluate(el=>parseFloat(getComputedStyle(el).fontSize));
  assert.ok(Math.abs(size-expected)<.01,`phone scale: ${size} vs ${expected}`);
  await page.screenshot({path:'output/text-camera-parity.png'});
  console.log('PASS text world scale, zoom, phone camera and centre anchor; fixture not saved');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
