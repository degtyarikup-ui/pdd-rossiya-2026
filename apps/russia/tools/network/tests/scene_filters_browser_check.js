// Read-only browser coverage: all API writes are aborted, approval data is an in-memory fixture.
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const base=(process.env.EDITOR_URL||'http://127.0.0.1:8950').replace(/\/$/,'');
(async()=>{
 const browser=await chromium.launch({channel:'chrome'});
 try {
  const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[],writes=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/api/**',route=>{if(route.request().method()!=='GET'){writes.push(route.request().url());return route.abort();}return route.continue();});
  await page.goto(`${base}/?filter=all`);
  await page.waitForFunction(()=>typeof App!=='undefined'&&App.state.questionsLoaded&&document.querySelector('#loading').hidden);
  const tabs=page.locator('#home-screen [data-scene-filter]');
  assert.deepEqual(await tabs.locator('span').allTextContents(),['Все','В игре','Одобрение','Не в игре']);
  assert.equal(await page.locator('#home-screen select,#home-screen [data-toggle-scene-filters]').count(),0);
  const counts=await page.evaluate(()=>['all','game','ai','plan'].map(key=>QuestionPlan.count(key)));
  assert.equal(counts[0],counts[1]+counts[2]+counts[3]);
  for(const [key,index] of [['all',0],['game',1],['assistant',2],['plan',3]]){
   await page.locator(`#home-screen [data-scene-filter="${key}"]`).click();
   assert.equal(await page.locator('#home-screen [data-plan-question]').count(),counts[index]);
   assert.equal(await page.locator(`#home-screen [data-scene-filter="${key}"]`).getAttribute('aria-pressed'),'true');
  }
  await page.locator('#home-screen [data-scene-filter="all"]').click();
  await page.locator('#home-q').fill('Билет №1 вопрос 3');
  assert.equal(await page.locator('#home-screen [data-plan-question]').count(),1);
  assert.equal(await page.locator('#home-screen [data-plan-question="ticket_1_3"]').count(),1);
  await page.locator('#home-q').fill('');
  await page.locator('#home-screen [data-plan-question="ticket_1_3"]').click();
  await page.waitForFunction(()=>App.S?.id==='ticket_1_3');
  const original=await page.evaluate(()=>JSON.stringify(App.S));
  await page.evaluate(()=>App.setLeftTab('scenes'));
  assert.equal(await page.locator('#left-body [data-scene-filter]').count(),4);
  assert.equal(await page.locator('#left-body select,#left-body [data-toggle-scene-filters]').count(),0);
  await page.locator('#left-body [data-scene-filter="assistant"]').click();
  assert.equal(await page.evaluate(()=>JSON.stringify(App.S)),original,'browsing never modifies or approves the active scene');
  await page.evaluate(()=>{App.state.questions.push({id:'ticket_99_1',ticket:99,number:1,category:'ab',question:'Проверка очереди одобрения',hasScene:true,status:'ai'});App.renderPanels({only:['left']});});
  assert.equal(await page.locator('#left-body [data-plan-question="ticket_99_1"]').count(),1);
  await page.locator('#left-body [data-scene-filter="game"]').click();
  assert.equal(await page.locator('#left-body [data-plan-question="ticket_99_1"]').count(),0,'pending scene is never in game filter');
  await page.setViewportSize({width:390,height:844});
  await page.evaluate(()=>{App.showHome(true);App.setSceneFilter('all');});
  const box=await page.locator('#home-screen .scene-tabs').boundingBox();assert(box.width<390);
  for(const button of await tabs.all())assert(await button.isVisible());
  assert(await page.locator('#home-screen').evaluate(el=>el.scrollWidth<=el.clientWidth+1));
  await page.screenshot({path:'output/scene-filters-mobile.png'});
  await page.setViewportSize({width:1280,height:900});
  await page.screenshot({path:'output/scene-filters-desktop.png'});
  await page.locator('#home-screen [data-scene-filter="plan"]').click();
  await page.reload();await page.waitForFunction(()=>typeof App!=='undefined'&&App.state.questionsLoaded&&document.querySelector('#loading').hidden);
  assert.equal(await page.evaluate(()=>App.sceneFilter()),'plan','visible filter preference survives reload after opening a scene');
  await page.goto(`${base}/?filter=questions&question=ticket_1_3`);
  await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.id==='ticket_1_3'&&document.querySelector('#loading').hidden);
  assert.equal(await page.evaluate(()=>App.sceneFilter()),'game','legacy deep link opens the original question and its visible status');
  assert.deepEqual(writes,[]);assert.deepEqual(errors,[]);
  console.log('Scene filter browser: four visible tabs, real counts/search, pending-only queue, unchanged active scene, mobile, old deep links, no writes/errors PASS');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
