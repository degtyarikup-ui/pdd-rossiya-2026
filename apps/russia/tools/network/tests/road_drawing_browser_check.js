// Run with the local editor open on :8950. Only the disposable browser draft is edited.
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch({channel:"chrome"});
  try {
    const page = await browser.newPage({viewport:{width:1366,height:820}});
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.route("**/api/**", route => {
      const req = route.request();
      if (req.method() === "POST" && !new URL(req.url()).pathname.startsWith("/api/preview/")) return route.abort();
      return route.continue();
    });
    await page.goto("http://127.0.0.1:8950/?scene=ticket_3_12");
    await page.waitForFunction(() => typeof App !== "undefined" && App.S?.id === "ticket_3_12");
    await page.keyboard.press("2");
    const snapshot = () => page.evaluate(() => JSON.stringify(App.S));
    const baseline = await snapshot();
    async function point(x, z, double = false) {
      const p = await page.evaluate(([x,z]) => {
        const rect = document.querySelector("#view canvas").getBoundingClientRect();
        const p = Scene3D.screenOf(x,z);
        return [rect.left + p.x, rect.top + p.y];
      }, [x,z]);
      if (double) await page.mouse.dblclick(...p);
      else await page.mouse.click(...p);
    }
    await page.keyboard.press("r");
    await point(0,26);
    await point(0,40);
    assert.equal(await snapshot(), baseline);
    await page.keyboard.press("Escape");

    await point(38,40);
    await point(38,23);
    const first = await snapshot();
    assert.notEqual(first, baseline);
    await point(22,23);
    const second = await snapshot();
    await page.locator('[data-draw="back"]').click();
    assert.equal(await snapshot(), first);
    await page.locator("#redo").click();
    assert.equal(await snapshot(), second);
    await page.locator("#undo").click();
    // Continue from the endpoint remaining after undo instead of starting a disconnected stroke.
    await point(38,8);
    assert.equal(await page.evaluate(() => {
      const L = App.S.layout;
      const anchor = L.nodes.find(n => Math.abs(n.x-38)<.5 && Math.abs(n.z-23)<.5);
      return Layout.streetsAt(L,anchor.id).length;
    }),2);
    await page.locator('[data-draw="done"]').click();
    assert.equal(await page.locator("[data-draw]").count(),0);
    await page.click("#undo");
    await page.click("#undo");
    assert.equal(await snapshot(), baseline);

    await page.keyboard.press("t");
    await point(23,16,true);
    assert.equal(await snapshot(), baseline,"double-click on the first point must not create zero-length rails");
    await point(23,38,true);
    const track = await page.evaluate(() => App.S.tracks.at(-1));
    assert.equal(track.points.length,2,"double-click to finish must not duplicate the endpoint");
    await page.click("#undo");
    assert.equal(await snapshot(), baseline);
    assert.deepEqual(errors, []);
    console.log("Road drawing: occupied map, undo/redo during a stroke, continuing from restored anchor and double-click rails PASS");
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
