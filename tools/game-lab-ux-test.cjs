// Stand UX regression: drafts, history, failed writes, keyboard and layout.
// API writes are intercepted so this test cannot change review / scene files.
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
  try {
    const page=await browser.newPage({viewport:{width:1600,height:1000}}),errors=[];
    page.setDefaultTimeout(60000);page.on('pageerror',e=>errors.push(e.message));
    let failWrites=false;const writes=[];
    await page.route('**/api/**',async route=>{
      if(route.request().method()!=='POST')return route.continue();
      writes.push({url:route.request().url(),body:route.request().postDataJSON()});
      return route.fulfill({status:failWrites?503:200,contentType:'application/json',body:JSON.stringify(failWrites?{error:'offline'}:{ok:true})});
    });
    await page.goto((process.env.GAME_LAB_URL||'http://127.0.0.1:8940')+'/#ticket_1_15',{waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>typeof lab!=='undefined'&&current?.id==='ticket_1_15');
    await page.evaluate(()=>lab.run('renderer.setPixelRatio(0.5)'));
    assert.ok(await page.locator('header lab-icon svg').count()>0);
    assert.equal(await page.locator('#list .card').first().evaluate(el=>el.tagName),'BUTTON');
    await page.locator('#viewSettings').click();
    await page.locator('#darkTheme').check();
    assert.equal(await page.evaluate(()=>frame.contentDocument.querySelector('.lab-sheet').classList.contains('dark')),true);
    await page.keyboard.press('Escape');assert.equal(await page.locator('#viewPopover').isVisible(),false);
    await page.locator('[data-mode="edit"]').click();
    assert.equal(await page.evaluate(()=>size),'fill');
    await page.locator('[data-route="route:0"]').click();
    const original=await page.evaluate(()=>selection.x);
    await page.locator('#sx').fill('3.75');
    assert.equal(await page.locator('#sx').inputValue(),'3.75');
    assert.equal(await page.locator('#sx').evaluate(el=>el===document.activeElement),true,'typing must not rebuild the input');
    await page.locator('#sx').dispatchEvent('change');
    assert.equal(await page.evaluate(()=>selection.x),3.75);
    await page.locator('#undo').click();assert.equal(await page.evaluate(()=>selection.x),original);
    await page.locator('#redo').click();assert.equal(await page.evaluate(()=>selection.x),3.75);
    await page.locator('#helpBtn').click();assert.equal(await page.locator('#helpDlg').evaluate(el=>el.open),true);await page.keyboard.press('Escape');
    await page.evaluate(()=>open('ticket_1_14'));await page.evaluate(()=>open('ticket_1_15'));
    assert.equal(await page.evaluate(()=>dirty),true);
    assert.equal(await page.evaluate(()=>lab.describe(lab.find('route:0')).x),3.75);
    await page.locator('#signPalette summary').click();
    await page.locator('#signSearch').fill('2.4');
    assert.equal(await page.locator('[data-sign="2.4"]').isVisible(),true);
    assert.equal(await page.locator('[data-sign="1.1"]').isVisible(),false);
    const sticky=await page.locator('#save').boundingBox();assert.ok(sticky.y+sticky.height<=1000,'save action stays visible');
    failWrites=true;
    await page.locator('#save').click();await page.waitForFunction(()=>document.querySelector('#toast').classList.contains('error'));
    assert.equal(await page.evaluate(()=>dirty),true,'failed response must retain the draft');
    failWrites=false;
    await page.keyboard.press('Control+s');await page.waitForFunction(()=>!dirty);
    assert.ok(writes.some(w=>w.body.id==='ticket_1_15'&&w.body.objects.some(o=>o.key==='route:0'&&o.x===3.75)));
    // Reset is also a pending, undoable edit, including after switching modes.
    await page.locator('#drop').click({trial:true});
    page.once('dialog',dialog=>dialog.accept());await page.locator('#drop').click();assert.equal(await page.evaluate(()=>dirty),true);
    await page.locator('#undo').click();assert.equal(await page.evaluate(()=>lab.describe(lab.find('route:0')).x),3.75);
    await page.locator('[data-mode="models"]').click();
    await page.locator('#search').fill('автобус');assert.equal(await page.locator('[data-model]').count(),1);
    await page.locator('[data-model="bus"]').click();
    const colorInput=page.locator('[data-from]').first();await colorInput.fill('#112233');await colorInput.dispatchEvent('change');
    await page.locator('[data-mode="edit"]').click();await page.locator('[data-mode="models"]').click();
    assert.ok(await page.evaluate(()=>Object.values(modelDraft.colors||{}).includes('#112233')),'model draft survives mode switch');
    await page.locator('[data-mode="view"]').click();
    if(process.env.GAME_LAB_SCREENSHOT)await page.screenshot({path:process.env.GAME_LAB_SCREENSHOT});
    for(const width of [1280,1000,680]) {
      await page.setViewportSize({width,height:900});
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`horizontal overflow at ${width}`);
    }
    assert.equal(await page.evaluate(()=>/\p{Extended_Pictographic}/u.test(document.querySelector('header').textContent)),false);
    assert.deepEqual(errors,[]);
    console.log('PASS: icons, reference, settings, fields, undo/redo, drafts, search, failed save, shortcuts, model drafts, responsive layout');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
