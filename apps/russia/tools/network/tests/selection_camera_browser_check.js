// Exercise the normal canvas, selection strip and camera on a scene with hand-drawn actor routes.
const {chromium} = require("playwright");
const assert = require("node:assert/strict");

(async () => {
  const browser = await chromium.launch({channel:"chrome"});
  try {
    const page = await browser.newPage({viewport:{width:1440,height:900}});
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.route("**/api/**", route => {
      const request = route.request();
      if (request.method() === "POST" && !new URL(request.url()).pathname.startsWith("/api/preview/")) {
        errors.push("Unexpected write to " + request.url()); return route.abort();
      }
      return route.continue();
    });
    await page.goto("http://127.0.0.1:8950/?scene=ticket_8_13");
    await page.waitForFunction(() => typeof App !== "undefined" && App.S && document.querySelector("#loading").hidden);
    const original = await page.evaluate(() => {
      App.select({t:"decor",id:App.S.decor[0].id}); App.copy();
      const actor = App.S.actors.find(a => a.way && App.S.routes.find(r => r.id === a.route)?.manual);
      App.select({t:"actor",id:actor.id});
      return {scene:JSON.stringify(App.S), actor, path:App.S.routes.find(r => r.id === actor.route)};
    });
    await page.click("#selection-copy");
    const result = await page.evaluate(old => {
      const copy = App.objectOf(App.state.sel[0]);
      return {copy, path:App.S.routes.find(r => r.id === copy.route), original:App.S.routes.find(r => r.id === old.route), buffer:App.state.clipboard[0].t};
    }, original.actor);
    assert.deepEqual(result.original, original.path);
    assert.equal(result.buffer, "decor");
    assert(result.path.manual);
    assert.deepEqual(result.path.points, original.path.points.map(([x,z]) => [Math.round((x+3)*1000)/1000, Math.round((z-3)*1000)/1000]));
    await page.click("#undo");
    assert.equal(await page.evaluate(() => JSON.stringify(App.S)), original.scene);

    await page.evaluate(() => { App.select({t:"decor",id:App.S.decor[0].id}); Tools.fitSelection(); });
    const before = await page.evaluate(() => structuredClone(App.objectOf(App.state.sel[0])));
    await page.click("#selection-rotr");
    await page.click("#selection-copy");
    await page.click("#selection-rotl");
    await page.click("#undo");
    assert.equal(await page.evaluate(() => App.S.decor.length), JSON.parse(original.scene).decor.length + 1, "undoing rotation must keep the duplicate");
    await page.click("#undo");
    await page.click("#undo");
    await page.evaluate(id => App.select({t:"decor",id}), before.id);
    const knob = await page.locator("#rotation-overlay circle").boundingBox();
    const target = await page.evaluate(() => {
      const t = Scene3D.turnHandle, p = Scene3D.screenOf(t.cx+8,t.cz+8);
      const box = document.querySelector("#view").getBoundingClientRect();
      return {x:p.x+box.left,y:p.y+box.top};
    });
    await page.mouse.move(knob.x + knob.width/2, knob.y + knob.height/2);
    await page.mouse.down(); await page.mouse.move(target.x,target.y,{steps:8}); await page.mouse.up();
    const turned = await page.evaluate(() => App.objectOf(App.state.sel[0]));
    assert.deepEqual(turned.pos,before.pos);
    assert.notEqual(turned.yaw,before.yaw);
    await page.click("#undo");
    assert.equal(await page.evaluate(() => JSON.stringify(App.S)), original.scene);

    await page.click("#close-inspector");
    await page.evaluate(() => App.select([]));
    await page.setViewportSize({width:390,height:844});
    await page.click("#z-fit");
    function framed() {
      const frame = App.mapFrame(), c = App.S.crop;
      return [[-c,-c],[c,-c],[-c,c],[c,c]].every(pt => {
        const p = Scene3D.screenOf(...pt);
        return p.x >= frame.x && p.x <= frame.x + frame.width && p.y >= frame.y && p.y <= frame.y + frame.height;
      });
    }
    assert(await page.evaluate(framed), "near and far corners of the 3D scene fit on a phone");
    await page.click("#z-in");
    const scale = () => page.evaluate(() => { const v = Scene3D.getView(); return Scene3D.worldPerPixel(v.x,v.z); });
    const oldScale = await scale();
    await page.click("#v-plan");
    assert(Math.abs(await scale() - oldScale) < .001);
    await page.click("#z-fit");
    assert(await page.evaluate(framed), "plan fits on the same phone");
    await page.click("#v-3d");
    await page.locator("#compass").focus(); await page.keyboard.press("ArrowLeft");
    assert(Math.abs(await page.evaluate(() => Scene3D.getView().orbitYaw) - Math.PI) > .1);
    await page.keyboard.press("Enter");
    assert.equal(await page.evaluate(() => Scene3D.getView().orbitYaw), Math.PI);
    assert.deepEqual(errors, []);
    console.log("Canvas: manual-route duplicate, preserved clipboard, independent undo, rotation grip, portrait fit, consistent zoom and compass PASS");
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
