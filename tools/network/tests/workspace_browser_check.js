// Run against the local editor on :8950. Editing and history stay in this browser session.
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch({ channel: "chrome" });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    const errors = [], writes = [];
    page.on("pageerror", error => errors.push(error.message));
    // Report unexpected persistence without ever letting the test modify a real scene.
    await page.route("**/api/**", route => {
      const req = route.request();
      if (req.method() === "POST" && !new URL(req.url()).pathname.startsWith("/api/preview/")) {
        writes.push(req.url());
        return route.abort();
      }
      return route.continue();
    });
    await page.goto("http://127.0.0.1:8950/");
    await page.locator("#home-q").fill("11·15");
    await page.locator('#home-screen [data-scene="ticket_11_15"]').click();
    await page.waitForFunction(() => document.querySelector("#home-screen").hidden && App.state.id === "ticket_11_15");
    const baseline = await page.evaluate(() => JSON.stringify(App.S));
    assert(await page.locator("#left-drawer").isHidden());
    assert(await page.locator("#inspector-shell").isHidden());
    assert(await page.locator("#refpic").isHidden());

    const layers = page.locator('[data-ltab="layers"]');
    await layers.click();
    assert.equal(await layers.getAttribute("aria-expanded"), "true");
    await layers.click();
    await page.click("#reference-toggle");
    await page.locator("#refpic [data-photo]").waitFor({state:"visible"});
    await page.click("#refpic [data-collapse]");

    const target = await page.evaluate(() => {
      const pos = App.S.actors[0].pos;
      const p = Scene3D.screenOf(pos[0], pos[1]);
      const box = document.querySelector("#view").getBoundingClientRect();
      return { x: box.x + p.x, y: box.y + p.y };
    });
    await page.mouse.click(target.x, target.y);
    await page.locator("#inspector-shell").waitFor({state:"visible"});
    await page.click("#close-inspector");
    await page.keyboard.press("r");
    const palette = page.locator("#popover");
    assert(await palette.locator('[data-road="avenue"]').isVisible());
    await palette.locator('[data-road="avenue"]').click();
    await palette.locator("[data-fold]").click();
    assert(await palette.isHidden());

    await page.click("#home");
    await page.locator("#home-back").focus();
    await page.keyboard.press("Delete");
    await page.keyboard.press("r");
    assert.equal(await page.evaluate(() => JSON.stringify(App.S)), baseline);
    await page.locator("#home-back").click();
    await page.setViewportSize({width:390,height:844});
    await page.click("#frame-scene");
    const frame = await page.locator(".phone-frame").boundingBox();
    const controls = await page.locator(".phone-camera").boundingBox();
    assert(frame.height > 300 && frame.y + frame.height <= controls.y);
    await page.locator('[data-frame="cancel"]').click();
    assert.equal(await page.evaluate(() => JSON.stringify(App.S)), baseline);
    assert.deepEqual(writes, []);
    assert.deepEqual(errors, []);
    console.log("Workspace: scene search, drawer toggles, map picking, palette, library shortcuts and narrow framing PASS");
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
