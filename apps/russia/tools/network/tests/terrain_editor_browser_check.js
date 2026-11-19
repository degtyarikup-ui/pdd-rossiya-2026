// Exercise a street with a side exit. Only preview requests can write HTTP bodies.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

async function run() {
  const browser = await chromium.launch({channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1600, height:1000}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/**', route => {
      const req = route.request();
      if (req.method() === 'GET' || (req.method() === 'POST' && new URL(req.url()).pathname.startsWith('/api/preview/'))) return route.continue();
      return route.abort();
    });
    const base = process.env.EDITOR_URL || 'http://127.0.0.1:8950';
    await page.goto(new URL('/?scene=ticket_11_15', base).href);
    await page.waitForFunction(() => typeof App !== 'undefined' && App.S?.id === 'ticket_11_15' && document.querySelector('#loading').hidden);
    await page.evaluate(() => {
      if (App.S.terrain) {
        delete App.S.terrain;
        App.changed({rebuild:false});
      }
      App.select({t:'street', id:App.S.layout.streets[0].id});
      App.showInspector();
      const render = THREE.Mesh.prototype.onBeforeRender;
      THREE.Mesh.prototype.onBeforeRender = function(...args) {
        if (this.name === 'asphalt') window.testAsphalt = this;
        return render.apply(this, args);
      };
      Scene3D.setMode('3d');
      Scene3D.requestRender();
    });
    const graph = page.locator('.terrain-editor svg');
    await graph.evaluate(svg => svg.scrollIntoView({block:'center'}));
    const screenPoint = (x, y) => graph.evaluate((svg, point) => {
      const p = new DOMPoint(...point).matrixTransform(svg.getScreenCTM());
      return [p.x, p.y];
    }, [x,y]);
    await page.mouse.move(...await screenPoint(162,104));
    await page.mouse.down();
    await page.mouse.move(...await screenPoint(168,87), {steps:6});
    await page.mouse.up();

    await page.waitForFunction(() => {
      const point = App.S.terrain?.profile?.[1];
      if (!point || point[1] < 9 || !window.testAsphalt) return false;
      const ray = new THREE.Raycaster(new THREE.Vector3(0,100,point[0]), new THREE.Vector3(0,-1,0));
      const hit = ray.intersectObject(window.testAsphalt)[0];
      return hit && Math.abs(hit.point.y - point[1]) < .02;
    });
    const saved = await page.evaluate(() => App.S.terrain.profile);
    const sideHeight = await page.evaluate(() => SurfaceSupport.terrainHeight(App.S.terrain, App.S.crop, App.S.terrain.profile[1][0]));
    assert.equal(sideHeight, 0);
    await page.click('#undo');
    assert.equal(await page.evaluate(() => App.S.terrain), undefined);
    await page.click('#redo');
    assert.deepEqual(await page.evaluate(() => App.S.terrain.profile), saved);

    await page.locator('[data-terrain-action="add-bump"]').click();
    const slider = page.getByRole('slider', {name:'Высота неровности'});
    await slider.focus();
    await slider.press('End');
    assert.equal(await page.evaluate(() => App.S.terrain.bumps[0].height), .2);
    await page.locator('[data-terrain-action="remove-bump"]').click();
    await page.locator('[data-terrain-action="flat"]').click();
    await page.waitForFunction(() => !App.S.terrain && App.state.build.surfaces.every(s => !s.heights?.some(h => h > 1)));
    assert.deepEqual(errors, []);
    console.log('Terrain editor: graph dragging, asphalt raycast, level side exit, undo/redo, bump sliders and flatten passed');
  } finally {
    await browser.close();
  }
}

run().catch(error => {console.error(error); process.exitCode = 1;});
