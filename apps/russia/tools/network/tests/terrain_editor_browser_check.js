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

    const root = page.locator('.terrain-editor');
    assert.equal(await root.locator('p, input, button, details').count(), 0);
    const clickAt = async (x,y,button='left') => page.mouse.click(...await screenPoint(x,y),{button});
    const readTerrain = () => page.evaluate(() => App.S.terrain);
    const command = name => graph.locator(`[data-command="${name}"]`).click();
    const point = () => graph.locator('[data-point="1"] circle:not(.hit)');
    const streetCount = await page.evaluate(() => App.S.layout.streets.length);

    await point().click();
    await page.keyboard.press('ArrowUp');
    assert(Math.abs((await readTerrain()).profile[1][1] - saved[1][1] - .1) < .001);
    await page.keyboard.press('ArrowDown');
    assert.deepEqual((await readTerrain()).profile,saved);
    await page.keyboard.press('Backspace');
    assert.equal(await readTerrain(), undefined);
    assert.equal(await page.evaluate(() => App.S.layout.streets.length), streetCount);
    await page.click('#undo');
    await point().click({button:'right'});
    assert.equal(await readTerrain(), undefined);
    await page.click('#undo');
    await point().click();
    await command('delete');
    assert.equal(await readTerrain(), undefined);
    await page.click('#undo');
    await clickAt(30,128,'right');
    assert.deepEqual((await readTerrain()).profile,saved);

    // A contextual action creates a bump at the clicked road coordinate.
    await clickAt(212,65,'right');
    await root.getByRole('button',{name:'Добавить неровность'}).click();
    let bump = (await readTerrain()).bumps[0];
    assert(Math.abs(bump.centre[1]-34) < 1);
    const dragHandle = async (name, dx, dy) => {
      const centre = await graph.locator(`[data-handle="${name}"] circle:not(.hit)`).evaluate(el =>
        [Number(el.getAttribute('cx')),Number(el.getAttribute('cy'))]);
      await page.mouse.move(...await screenPoint(...centre));
      await page.mouse.down();
      await page.mouse.move(...await screenPoint(centre[0]+dx,centre[1]+dy),{steps:4});
      await page.mouse.up();
    };
    await dragHandle('height',0,-40);
    await dragHandle('width',20,0);
    await dragHandle('length',15,0);
    await dragHandle('position',8,-9);
    const changed = (await readTerrain()).bumps[0];
    assert.equal(changed.height,.2);
    assert(changed.width > bump.width && changed.length > bump.length);
    assert(changed.centre[0] > bump.centre[0] && changed.centre[1] > bump.centre[1]);
    await command('back');
    await graph.locator('[data-bump="0"]').click();
    await command('delete');
    assert.equal((await readTerrain()).bumps?.length || 0,0);
    await command('menu');
    await root.getByRole('button',{name:'Выровнять профиль'}).click();
    await page.waitForFunction(() => !App.S.terrain && App.state.build.surfaces.every(s => !s.heights?.some(h => h > 1)));
    await page.click('#undo');
    assert.deepEqual((await readTerrain()).profile,saved);
    await page.evaluate(() => { App.state.locked.add('roads'); App.renderInspector(); });
    await point().click({button:'right'});
    await clickAt(200,97);
    await page.keyboard.press('Delete');
    assert.deepEqual((await readTerrain()).profile,saved);
    assert.deepEqual(errors, []);
    console.log('Terrain editor: graph dragging, asphalt raycast, level side exit, undo/redo, point deletion, graphical bump handles, flatten and road lock passed');
  } finally {
    await browser.close();
  }
}

run().catch(error => {console.error(error); process.exitCode = 1;});
