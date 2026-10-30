// Run with the local editor server on port 8950. Never saves the scene.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({channel:'chrome',headless:true});
  try {
    const page = await browser.newPage({viewport:{width:1500,height:1000}});
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    await page.goto('http://127.0.0.1:8950/?scene=ticket_3_12');
    await page.waitForFunction(() => typeof App !== 'undefined' && App.S?.id === 'ticket_3_12');
    await page.locator('[data-tool="answer"]').click();
    await page.locator('[data-answer-mode="text"]').click();
    const box = await page.locator('#view canvas').first().boundingBox();
    const click = () => page.mouse.click(box.x+box.width*.65,box.y+box.height*.45);
    const before = await page.evaluate(() => App.S.routes.length);
    await click();
    const input = page.locator('.scene-text-input');
    await input.waitFor({state:'visible',timeout:3000});
    assert.equal(await input.evaluate(el => document.activeElement === el),true);
    await input.fill('Отменить');
    await input.press('Escape');
    assert.equal(await page.evaluate(() => App.S.routes.length),before);
    await click();
    await input.fill('3 м');
    await input.press('Enter');
    assert.equal(await page.evaluate(() => App.S.routes.at(-1).text),'3 м');
    assert.equal(await page.evaluate(() => App.S.routes.length),before+1);
    await page.evaluate(() => App.undo());
    assert.equal(await page.evaluate(() => App.S.routes.length),before);
    await page.evaluate(() => App.redo());
    assert.equal(await page.evaluate(() => App.S.routes.at(-1).text),'3 м');
    assert.deepEqual(errors,[]);
    console.log('PASS actual text-tool click, focus, typing, Escape, Enter, undo/redo');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
