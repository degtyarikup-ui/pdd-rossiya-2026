// The real App confirmation/deletion flow against in-memory HTTP responses.
// Every destructive request is fulfilled here; none can reach the local server.
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const base=(process.env.EDITOR_URL||'http://127.0.0.1:8950').replace(/\/$/,'');
(async()=>{
  const browser=await chromium.launch({channel:'chrome'});
  try {
    const page=await browser.newPage({viewport:{width:1280,height:820}});
    const current='ticket_9_14',other='ticket_2_9',removed=new Set(),posts=[],unexpected=[],errors=[];
    let failDelete=false,build=null,holdNextList=false,heldList=null;
    const listed=[current,other].map(id=>({id,playable:true,errors:0,questionText:'Проверка удаления'}));
    const questions=listed.map(s=>{const [,ticket,number]=s.id.split('_');return {id:s.id,ticket:Number(ticket),number:Number(number),category:'ab',question:'Проверка удаления',decision:'yes',hasScene:true,status:'game'};});
    const fulfill=(route,data,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(data)});
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('**/api/**',async route=>{
      const request=route.request(),pathname=new URL(request.url()).pathname;
      if(pathname==='/api/scenes'){
        if(holdNextList){holdNextList=false;heldList=route;return;}
        // Simulate a cached list that has not observed the deletion yet.
        return fulfill(route,listed);
      }
      if(pathname==='/api/questions')return fulfill(route,{questions});
      const description=/^\/api\/scene\/(ticket_\d+_\d+)\/deletion$/.exec(pathname);
      if(description)return fulfill(route,{id:description[1],ids:[description[1]],hasScene:true,revision:'fixture-r1'});
      const deletion=/^\/api\/scene\/(ticket_\d+_\d+)\/delete$/.exec(pathname);
      if(deletion){
        assert.equal(request.method(),'POST');assert.deepEqual(request.postDataJSON(),{revision:'fixture-r1'});
        posts.push(deletion[1]);
        if(failDelete)return fulfill(route,{error:'Сцена изменилась после подтверждения'},409);
        removed.add(deletion[1]);return fulfill(route,{ids:[deletion[1]]});
      }
      if(pathname.startsWith('/api/preview/'))return fulfill(route,{build,findings:[],edges:{}});
      if(request.method()!=='GET'){unexpected.push(pathname);return route.abort();}
      return route.continue();
    });
    await page.goto(`${base}/?scene=${current}`);
    await page.waitForFunction(id=>typeof App!=='undefined'&&App.S?.id===id&&document.querySelector('#loading').hidden,current);
    build=await page.evaluate(()=>App.state.build);
    await page.evaluate(()=>{
      App.edit(s=>{s.question.authorNote='Несохранённая работа';},{rebuild:false});
      App.setSceneFilter('all');App.showHome(false);App.setLeftTab('scenes');
    });
    const snapshot=()=>page.evaluate(()=>({scene:JSON.stringify(App.S),undo:JSON.stringify(App.state.undo),dirty:App.state.dirty,id:App.state.id}));
    const draft=await snapshot();
    const requestDelete=async id=>{
      await page.locator(`#left-body [data-delete-scene="${id}"]`).click();
      await page.locator('#confirm').waitFor({state:'visible'});
      assert.equal(await page.locator('#confirm-title').innerText(),'Удалить вопрос?');
      assert.equal(await page.locator('#confirm-yes').innerText(),'Удалить');
      assert(await page.locator('#confirm-discard').isHidden());
    };
    const settled=()=>page.waitForFunction(()=>App.state.deleting===null);

    await requestDelete(current);
    assert.match(await page.locator('#confirm-text').innerText(),/Несохранённые изменения/);
    await page.locator('#confirm [data-answer="no"]').click();await settled();
    assert.deepEqual(await snapshot(),draft,'cancel preserves current draft and history');assert.equal(posts.length,0);

    failDelete=true;
    await requestDelete(current);await page.locator('#confirm-yes').click();await settled();
    assert.deepEqual(await snapshot(),draft,'server conflict preserves current draft and history');
    assert.match(await page.locator('#toast').innerText(),/Не удалено.*Сцена изменилась/);
    assert.equal(await page.locator(`#left-body [data-delete-scene="${current}"]`).count(),1);

    failDelete=false;
    holdNextList=true;
    await page.evaluate(()=>{window.__earlierSceneList=App.loadList();});
    for(let tries=0;!heldList&&tries<50;tries++)await page.waitForTimeout(10);
    assert(heldList,'an older scene refresh is held while deletion proceeds');
    await requestDelete(other);
    assert.doesNotMatch(await page.locator('#confirm-text').innerText(),/Несохранённые изменения/);
    await page.locator('#confirm-yes').click();await settled();
    await page.waitForFunction(id=>!App.state.scenes.some(s=>s.id===id),other);
    assert.deepEqual(await snapshot(),draft,'deleting another scene leaves the active unsaved work untouched');
    assert.equal(await page.locator(`#left-body [data-delete-scene="${other}"]`).count(),0);
    await fulfill(heldList,listed);await page.evaluate(()=>window.__earlierSceneList);
    assert.equal(await page.evaluate(id=>App.state.scenes.some(s=>s.id===id),other),false,'a delayed older list cannot resurrect the deleted row');
    await page.waitForFunction(id=>!QuestionPlan.list().some(q=>q.id===id),other);

    await requestDelete(current);await page.locator('#confirm-yes').click();await settled();
    await page.waitForFunction(()=>App.S===null&&!document.querySelector('#home-screen').hidden);
    assert.equal(await page.evaluate(()=>App.state.id),null);
    assert.equal(await page.evaluate(()=>App.state.dirty),false);
    assert.deepEqual(await page.evaluate(()=>[App.state.undo.length,App.state.redo.length,App.state.sel.length]),[0,0,0]);
    assert.equal(await page.evaluate(()=>App.state.lastTicket),null);
    assert(await page.locator('#save').isDisabled());
    await page.waitForFunction(()=>App.state.scenes.length===0&&QuestionPlan.visibleCount()===0);
    assert.equal(await page.locator('#home-screen [data-delete-scene]').count(),0,'deleted scene cards stay absent after refresh');
    await page.evaluate(()=>App.setSceneFilter('questions'));
    assert.equal(await page.locator('#home-screen [data-plan-question]').count(),0,'question backlog stays empty even when stale responses retain the old decision and hasScene records');
    await page.evaluate(()=>App.undo());assert.equal(await page.evaluate(()=>App.S),null,'undo cannot resurrect the deleted document');
    assert.deepEqual(posts,[current,other,current]);
    assert.deepEqual(unexpected,[],'no save/publish/thumbnail request reaches the server');
    assert.deepEqual(errors,[]);
    console.log('Scene deletion flow browser: real confirmation, cancel/conflict, unrelated draft, stale scene/question responses, current cleanup and no JS errors PASS');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
