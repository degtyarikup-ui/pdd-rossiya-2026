// Deletion affordances invoke the shared confirmation flow without opening a scene.
// The callback is stubbed and all writes are blocked, so this test cannot delete user data.
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const base = (process.env.EDITOR_URL || 'http://127.0.0.1:8950').replace(/\/$/,'');
(async()=>{
  const browser=await chromium.launch({channel:'chrome'});
  try {
    const page=await browser.newPage({viewport:{width:1280,height:820}}), errors=[], writes=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('**/api/**',route=>{
      const request=route.request();
      if(request.method()!=='GET'){writes.push(request.url());return route.abort();}
      return route.continue();
    });
    await page.goto(`${base}/?scene=ticket_5_7`);
    await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.id==='ticket_5_7'&&document.querySelector('#loading').hidden);
    const original=await page.evaluate(()=>JSON.stringify(App.S));
    await page.evaluate(()=>{
      window.__deletions=[];window.__opens=[];
      App.deleteScene=async id=>window.__deletions.push(id);
      App.openScene=async id=>window.__opens.push(id);
      App.state.scenes=[
        {id:'ticket_1_1',playable:true,errors:0,questionText:'Проверочная сцена'},
        {id:'ticket_1_2',playable:false,errors:0,questionText:'Черновик'},
        {id:'mini_regulator',playable:false,errors:0,regulator:true},
      ];
      App.state.section='city';App.setSceneFilter('all');App.showHome(true);
    });
    const deleteIn=scope=>page.locator(`${scope} [data-delete-scene="ticket_1_1"]`);
    assert.equal(await page.locator('button button').count(),0,'delete and open controls cannot be nested');
    assert(await deleteIn('#home-screen').getAttribute('aria-label'));
    assert.equal(await deleteIn('#home-screen').getAttribute('title'),'Удалить вопрос из игры');
    await deleteIn('#home-screen').click();
    assert.deepEqual(await page.evaluate(()=>window.__deletions),['ticket_1_1']);
    assert.deepEqual(await page.evaluate(()=>window.__opens),[],'home delete does not navigate');
    await page.evaluate(()=>{App.showHome(false);App.setLeftTab('scenes');});
    await deleteIn('#left-body').focus();await page.keyboard.press('Enter');
    assert.deepEqual(await page.evaluate(()=>window.__deletions),['ticket_1_1','ticket_1_1']);
    assert.deepEqual(await page.evaluate(()=>window.__opens),[],'keyboard deletion in sidebar does not navigate');
    await page.locator('#left-body [data-scene="ticket_1_2"]').click();
    assert.deepEqual(await page.evaluate(()=>window.__opens),['ticket_1_2'],'ordinary scene navigation still works');

    await page.evaluate(()=>{
      App.state.questionsLoaded=true;
      App.state.questions=[
        {id:'ticket_1_1',ticket:1,number:1,category:'ab',question:'Выбранный вопрос',decision:'yes',hasScene:false,status:'plan'},
        {id:'ticket_2_1',ticket:2,number:1,category:'ab',question:'Дорожная задача',decision:null,hasScene:false,status:'game'},
        {id:'ticket_3_1',ticket:3,number:1,category:'ab',question:'Удалённая сцена',decision:'no',hasScene:true,status:'game'},
        {id:'ticket_4_1',ticket:4,number:1,category:'ab',question:'Удалённый черновик',decision:'no',hasScene:true,status:'plan'},
      ];
      App.setSceneFilter('questions');QuestionPlan.setFilter('plan');App.showHome(true);
    });
    assert.equal(await page.evaluate(()=>QuestionPlan.visibleCount()),2,'deleted records do not reappear because an archive hasScene');
    assert.equal(await page.locator('#home-screen [data-plan-question="ticket_4_1"]').count(),0);
    await deleteIn('#home-screen').click();
    await page.evaluate(()=>{App.showHome(false);App.setLeftTab('scenes');});
    await deleteIn('#left-body').click();
    assert.equal(await page.evaluate(()=>window.__deletions.length),4,'question rows and cards share the delete action');
    assert.deepEqual(await page.evaluate(()=>window.__opens),['ticket_1_2'],'question deletion never opens its virtual scene');
    await page.evaluate(()=>{QuestionPlan.setFilter('game');App.showHome(true);});
    assert(await page.locator('#home-screen [data-plan-question="ticket_2_1"]').isDisabled());
    assert(await page.locator('#home-screen [data-delete-scene="ticket_2_1"]').isEnabled(),'deletion is separate from a disabled scene opener');
    assert.equal(await page.locator('#home-screen [data-plan-question="ticket_3_1"]').count(),0);

    await page.setViewportSize({width:390,height:844});
    assert(await page.locator('#home-screen').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'mobile cards fit their container');
    const mobileDelete=page.locator('#home-screen [data-delete-scene="ticket_2_1"]');
    assert(await mobileDelete.isVisible());
    const target=await mobileDelete.boundingBox();assert(target.width>=28&&target.height>=28);
    await mobileDelete.click();
    assert.equal(await page.evaluate(()=>window.__deletions.at(-1)),'ticket_2_1');
    await page.evaluate(()=>{App.state.section='regulator';App.showHome(true);App.renderHome();App.renderPanels({only:['left']});});
    assert.equal(await page.locator('[data-delete-scene="mini_regulator"]').count(),0,'the regulator mini-game cannot be deleted');
    assert.equal(await page.locator('button button').count(),0);
    assert.equal(await page.evaluate(()=>JSON.stringify(App.S)),original,'browsing and requesting deletion leave the current draft unchanged');
    assert.deepEqual(writes,[]);assert.deepEqual(errors,[]);
    console.log('Scene deletion UI: scene/question rows and cards, separate accessible buttons, keyboard, hidden rejected records, mobile and protected regulator PASS');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
