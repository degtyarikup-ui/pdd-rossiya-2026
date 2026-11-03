// Inspect representative real tickets without saving. A property should remain reachable by
// scrolling or tabbing the sheet, including on the narrow layout, without opening a section.
const assert = require("node:assert/strict");
const {chromium} = require("playwright");

(async () => {
  const browser = await chromium.launch({channel:"chrome"});
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.route("**/api/**", route => {
      if (route.request().method() === "POST" && !new URL(route.request().url()).pathname.startsWith("/api/preview/")) {
        errors.push("Unexpected write: " + route.request().url());
        return route.abort();
      }
      return route.continue();
    });
    const tickets = {
      ticket_5_7: ["scene", "street", "node", "approach", "stop", "multi"],
      ticket_11_15: ["actor", "light", "decor", "texture"],
      ticket_2_9: ["sign", "track", "lawn", "marking"],
      ticket_18_8: ["choice"],
      mini_regulator: ["scene", "officer", "approach"],
    };
    for (const [id, kinds] of Object.entries(tickets)) {
      await page.goto("http://127.0.0.1:8950/?scene=" + id);
      await page.waitForFunction(id => typeof App !== "undefined" && App.S?.id === id && document.querySelector("#loading").hidden, id);
      const original = await page.evaluate(() => JSON.stringify(App.S));
      for (const width of [1280,390]) {
        await page.setViewportSize({width, height:width === 390 ? 740 : 800});
        for (const kind of kinds) {
          await page.evaluate(kind => {
            const s = App.S;
            App.state.texSel = null;
            if (kind === "texture") {
              App.setLeftTab("textures");
              const tile = document.querySelector('[data-texrow="asphalt"]'); tile.click();
            } else if (kind === "multi") {
              App.select(s.layout.streets.map(st => ({t:"street",id:st.id})));
            } else if (kind === "scene") App.select([]);
            else if (kind === "stop") App.select({t:"stop"});
            else if (kind === "approach" || kind === "choice") App.select({t:"route",id:s.routes.find(r => r.kind === kind).id});
            else {
              const list = kind === "street" ? s.layout.streets : kind === "node" ? s.layout.nodes : kind === "decor" ? s.decor : s[kind+"s"];
              App.select({t:kind,id:list[0].id});
            }
            App.showInspector();
          }, kind);
          const pane = page.locator("#inspector");
          const where = [id,kind,width].join(" / ");
          assert(await pane.locator(".insp-head").isVisible(), where);
          assert.equal(await pane.locator("details, summary, [aria-expanded]").count(), 0, where + " must be flat");
          assert(await pane.evaluate(el => el.scrollWidth <= el.clientWidth + 1), where + " horizontal overflow");
          assert.equal(await pane.getByRole("button",{name:"",exact:true}).count(), 0, where + " unnamed button");
          if (kind === "street") {
            for (const key of ['[data-chip="kind"]','[data-chip="median"]','[data-text="player-end"]','[data-act="end"]','input[data-text^="approach-"]']) {
              assert(await pane.locator(key).first().isVisible(), where + " " + key);
            }
          }
        }
      }
      assert.equal(await page.evaluate(() => JSON.stringify(App.S)), original, id + " changed while browsing properties");
    }
    assert.deepEqual(errors, []);
    console.log("Property panels: 18 contexts on desktop and phone, immediate controls, accessible actions, original scenes preserved PASS");
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
