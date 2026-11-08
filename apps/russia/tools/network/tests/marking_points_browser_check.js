// Real pointer gestures and server-built surfaces on a disposable browser fixture.
// POST writes are blocked; the only permitted POST is the read-only preview builder.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors = [], writes = [];
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('**/api/**',route=>{
      const request = route.request(), pathname = new URL(request.url()).pathname;
      if (request.method()==='POST' && !pathname.startsWith('/api/preview/')) {
        writes.push(pathname); return route.abort();
      }
      return route.continue();
    });
    await page.goto('http://127.0.0.1:8950/?scene=ticket_5_7');
    await page.waitForFunction(()=>typeof App!=='undefined' && App.S?.id==='ticket_5_7' && document.querySelector('#loading').hidden);
    await page.evaluate(async()=>{
      const s = {schema:1,id:'ticket_5_7',procedural:true,crop:70,
        layout:{nodes:[{id:'a',x:0,z:-40},{id:'b',x:0,z:40}],streets:[{id:'st',a:'a',b:'b',kind:'avenue',ends:{}}],player:{street:'st',toward:'b'}},
        question:{maneuver:'straight',yieldTo:[]},roads:[],markings:[],lawns:[],routes:[],actors:[],lights:[],decor:[],signs:[]};
      Layout.apply(s);
      s.markings.push({id:"points-test",type:"dashed",points:[[4,-30],[4,-15],[4,0],[4,15],[4,30]]});
      const result = await App.api('/api/preview/ticket_5_7',s);
      App.state.S=s; App.state.id=s.id; App.state.plan=null; App.state.build=result.build;
      App.state.savedJson=JSON.stringify(s); App.state.undo=[]; App.state.redo=[]; App.state.dirty=false;
      App.state.findings=result.findings; App.state.edges=result.edges;
      Scene3D.load(s,result.build); Tools.set('select'); App.select({t:'marking',id:'points-test'});
      App.showInspector(); Scene3D.setMode('plan'); Scene3D.fit([-35,-50,45,50]);
      App.renderTop();
    });
    const screen=(x,z)=>page.evaluate(([x,z])=>{const r=document.querySelector('#view canvas').getBoundingClientRect(),p=Scene3D.screenOf(x,z,.3);return{x:r.left+p.x,y:r.top+p.y};},[x,z]);
    const pts=()=>page.evaluate(()=>App.S.markings.find(m=>m.id==='points-test').points);
    const before=await pts();
    const a=await screen(8,3),b=await screen(2,-18);
    await page.mouse.move(a.x,a.y);await page.mouse.down();await page.mouse.move(b.x,b.y,{steps:12});await page.mouse.up();
    assert.deepEqual(await page.evaluate(()=>App.state.sel.map(r=>r.v).sort()),[1,2],'marquee selects vertices, not the road');
    const from=await screen(4,-15),to=await screen(7,-12);
    await page.mouse.move(from.x,from.y);await page.mouse.down();await page.mouse.move(to.x,to.y,{steps:12});await page.mouse.up();
    assert.deepEqual(await pts(),[[4,-30],[7,-12],[7,3],[4,15],[4,30]],'both selected points move, others stay');
    assert.equal(await page.evaluate(()=>App.state.undo.length),1);
    await page.keyboard.press('Delete');
    await page.waitForFunction(()=>App.S.markings.find(m=>m.id==='points-test').points.length===3);
    assert.deepEqual(await pts(),[[4,-30],[4,15],[4,30]]);
    await page.click('#undo');assert.equal((await pts()).length,5);
    await page.click('#undo');assert.deepEqual(await pts(),before);
    await page.evaluate(()=>{App.select({t:'marking',id:'points-test'});App.showInspector();});
    await page.click('[data-act="simplify-points"]');assert.deepEqual(await pts(),[[4,-30],[4,0],[4,30]]);
    await page.click('#undo');assert.deepEqual(await pts(),before);
    // Shift-click adds/removes vertices using the real canvas hit test.
    const first=await screen(4,-15),second=await screen(4,0);
    await page.mouse.click(first.x,first.y);await page.keyboard.down('Shift');await page.mouse.click(second.x,second.y);await page.keyboard.up('Shift');
    assert.equal(await page.evaluate(()=>App.state.sel.length),2);
    const output=path.resolve(__dirname,'../../../output/marking-points');fs.mkdirSync(output,{recursive:true});
    await page.screenshot({path:path.join(output,'selected-points.png')});
    assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
    console.log('Marking points browser: real marquee, group drag, delete, undo, simplify and Shift selection PASS');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
