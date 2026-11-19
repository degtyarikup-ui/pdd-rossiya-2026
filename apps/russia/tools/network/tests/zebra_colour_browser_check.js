// Exercise the actual two-colour crossing without writing to the authored ticket.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1500,height:1000}});
    await page.route('**/api/**', route => {
      const r = route.request();
      return r.method() === 'GET' || r.url().includes('/api/preview/') ? route.continue() : route.abort();
    });
    await page.goto((process.env.EDITOR_URL || 'http://127.0.0.1:8950')+'/?scene=ticket_13_5');
    await page.waitForFunction(()=>typeof App !== 'undefined' && App.S?.id === 'ticket_13_5' && document.querySelector('#loading').hidden);
    await page.evaluate(()=>{
      Tools.set('select');
      Scene3D.setMode('plan');
      Scene3D.fit([-12,-14,12,14]);
    });
    const crossing = () => page.evaluate(()=>App.S.markings.find(m=>m.type==='zebra'));
    const original = await crossing();
    assert.equal(original.colour,'white_yellow');
    const screen = (x,z) => page.evaluate(([x,z])=>{
      const r = document.querySelector('#view canvas').getBoundingClientRect(), p = Scene3D.screenOf(x,z);
      return {x:r.left+p.x, y:r.top+p.y};
    },[x,z]);
    const a = await screen(2,0), b = await screen(2,5);
    await page.mouse.move(a.x,a.y); await page.mouse.down();
    await page.mouse.move(b.x,b.y,{steps:12}); await page.mouse.up();
    const moved = await crossing();
    for (const [i,[x,z]] of moved.points.entries()) {
      assert.ok(Math.abs(x-original.points[i][0])<0.03 && Math.abs(z-original.points[i][1]-5)<0.03);
    }
    await page.evaluate(()=>App.showInspector());
    const setColour = value => page.click(`[data-chip="colour"][data-value="${value}"]`);
    const yellow = () => page.evaluate(async()=>{
      const {build} = await App.api('/api/preview/'+App.S.id,App.S);
      return build.surfaces.find(s=>s.id==='marking_yellow')?.idx.length || 0;
    });
    await setColour('white');
    assert.equal(await yellow(),0);
    await setColour('white_yellow');
    assert.ok(await yellow()>0);
    assert.deepEqual((await crossing()).points,moved.points);
    await page.click('#undo'); await page.click('#undo'); await page.click('#undo');
    assert.deepEqual(await crossing(),original);
    console.log('PASS ticket 13·5 crossing: full drag, both colour modes, preview geometry and undo');
  } finally {
    await browser.close();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
