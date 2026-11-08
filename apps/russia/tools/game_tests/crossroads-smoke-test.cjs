// Real Flutter scenario JSON through the native JS bridge and Three.js scene.
// NODE_PATH=<playwright modules> node tools/game_tests/crossroads-smoke-test.cjs [--all]
// DART_BIN and CHROME_PATH can override the local runtimes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const assets = path.join(root, 'assets/game');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'pdd-crossroads-smoke-'));
const output = path.join(root, 'output/game-review/crossroads-smoke');

async function main() {
  let browser;
  let server;
  try {
    const dartSource = path.join(temporary, 'scenarios.dart');
    const modelUrl = pathToFileURL(path.join(root, 'lib/data/models/crossroads_priority_model.dart')).href;
    fs.writeFileSync(dartSource, `import 'dart:convert';\nimport '${modelUrl}';\nvoid main() { print(jsonEncode(CrossroadsScenariosLibrary.allScenarios.map((s) => s.toJson()).toList())); }\n`);
    const bundledDart = path.join(os.homedir(), 'flutter/bin/dart');
    const dart = process.env.DART_BIN || (fs.existsSync(bundledDart) ? bundledDart : 'dart');
    const scenarios = JSON.parse(execFileSync(dart, ['run', dartSource], {
      cwd: root, encoding: 'utf8', timeout: 60000,
    }));
    assert(scenarios.length >= 5);

    server = http.createServer((request, response) => {
      const requestedPath = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      if (requestedPath === '/favicon.ico') { response.writeHead(204).end(); return; }
      const filename = path.resolve(assets, `.${requestedPath}`);
      if (!filename.startsWith(`${assets}${path.sep}`) || !fs.existsSync(filename)) {
        response.writeHead(404).end(); return;
      }
      const types = { '.html': 'text/html', '.js': 'application/javascript', '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg' };
      response.writeHead(200, { 'Content-Type': types[path.extname(filename)] || 'application/octet-stream' });
      fs.createReadStream(filename).pipe(response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    browser = await chromium.launch({
      headless: true,
      executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      args: ['--use-angle=swiftshader'],
    });
    const page = await browser.newPage({ viewport: { width: 414, height: 896 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.addInitScript(() => {
      window.smokeEvents = [];
      window.FlutterChannel = { postMessage: raw => window.smokeEvents.push(JSON.parse(raw)) };
    });
    await page.goto(`http://127.0.0.1:${address.port}/crossroads.html?weather=clear`);
    await page.waitForFunction(() => window.smokeEvents.some(event => event.type === 'ready'));
    assert.equal(await page.locator('canvas').count(), 1);
    await page.waitForFunction(() => window._pddCrossroads.renderer.info.render.triangles > 500);
    fs.mkdirSync(output, { recursive: true });

    const representativeIds = ['cross_main_turns_left', 'cross_equal_tram', 'cross_emergency_priority', 'cross_uturn_equal', 'cross_two_trams_and_cars'];
    const selected = process.argv.includes('--all') ? scenarios : representativeIds.map(id => {
      const scenario = scenarios.find(candidate => candidate.id === id);
      assert(scenario, `Missing representative scenario: ${id}`);
      return scenario;
    });
    const geometryCounts = [];
    const locations = new Set();
    for (const scenario of selected) {
      await page.evaluate(data => {
        window.smokeEvents = [];
        loadScenarioData(data);
        setViewInset(90, 220);
        setZoom(1);
      }, scenario);
      assert.equal(await page.evaluate(() => window._pddCrossroads.vehiclesGroup.children.length), scenario.actors.length);
      // Ясная погода всегда: ни дождя, ни прожекторов фар; рельсы — только под трамвай;
      // каждый знак смотрит на водителей своего подъезда.
      const scene = await page.evaluate(() => {
        const { scene } = window._pddCrossroads;
        let spots = 0, rain = 0, rails = 0; const signs = [];
        scene.traverse(o => {
          if (o.isSpotLight) spots++;
          if (o.isLineSegments || o.isPoints) rain++;
        });
        window._pddCrossroads.scenarioGroup.children.forEach(o => {
          const p = o.geometry?.parameters;
          if (p && Math.min(p.width, p.depth) === 0.08) rails++;
        });
        return { spots, rain, rails, fog: !!scene.fog, geometries: window._pddCrossroads.renderer.info.memory.geometries };
      });
      assert.equal(scene.spots, 0, 'no headlight spot lights');
      assert.equal(scene.rain, 0, 'no rain');
      assert.equal(scene.fog, false, 'no fog');
      const trams = scenario.actors.filter(a => a.type === 'tram');
      const axes = new Set(trams.map(a => a.side === 'north' || a.side === 'south' ? 'ns' : 'ew'));
      assert.equal(scene.rails, axes.size * 2, scenario.id + ': rails only under trams');
      locations.add(await page.evaluate(() => window._pddCrossroads.location()));
      if (scenario.closedSide) {
        // Закрытая ветка — тротуар и газон, а не серая плита на всю длину.
        const lawn = await page.evaluate(() => window._pddCrossroads.scenarioGroup.children.some(o => o.material && o.material.userData.pddKind === 'grass'));
        assert(lawn, scenario.id + ': closed arm has a lawn');
      }
      geometryCounts.push(scene.geometries);
      const facing = await page.evaluate(() => window._pddCrossroads.signsGroup.children
        .map(g => ({ x: g.position.x, z: g.position.z, ry: g.rotation.y })));
      assert.equal(facing.length, (scenario.signs || []).length, scenario.id + ': every sign is placed');
      for (const f of facing) {
        // Нормаль лица знака (+Z, повернутая) направлена от перекрёстка — к подъезду.
        const nx = Math.sin(f.ry), nz = Math.cos(f.ry);
        assert(nx * f.x + nz * f.z > 0, scenario.id + ': sign faces its approach ' + JSON.stringify(f));
      }
      if (scenario === scenarios[0]) await page.screenshot({ path: path.join(output, 'initial.png') });
      let completedSteps = 0;
      for (const actor of [...scenario.actors].sort((a, b) => a.order - b.order)) {
        await page.evaluate(id => selectVehicle(id), actor.id);
        await page.waitForFunction(expected => window.smokeEvents.filter(event => event.type === 'step_correct').length === expected, ++completedSteps);
        const lastStep = await page.evaluate(() => window.smokeEvents.filter(event => event.type === 'step_correct').at(-1));
        assert.equal(lastStep.actorId, actor.id);
        await page.waitForFunction(id => {
          const mesh = window._pddCrossroads.vehiclesGroup.children.find(child => child.userData.actorId === id);
          return mesh && !mesh.visible;
        }, actor.id, { timeout: 15000 });
      }
      await page.waitForFunction(() => window.smokeEvents.some(event => event.type === 'crossroad_complete'));
      assert.equal(await page.evaluate(() => window.smokeEvents.filter(event => event.type === 'collision').length), 0);
      console.log(`${scenario.id}: ${completedSteps} correct steps and completion`);
    }
    // Смена перекрёстков не копит геометрию (машины, метки и знаки освобождаются).
    if (selected.length >= 5) assert(locations.size >= 3, 'crossroads change locations: ' + [...locations]);
    if (geometryCounts.length > 4) assert(Math.max(...geometryCounts.slice(-3)) < geometryCounts[0] * 1.6, 'no geometry leak: ' + geometryCounts.join(','));

    // Exported Dart objects use `explanation`; the standalone demo historically
    // used `ruleExplanation`. The real bridge must preserve the actual rule.
    const scenario = scenarios[0];
    const priority = scenario.actors.find(actor => actor.order === 1);
    const wrong = scenario.actors.find(actor => actor.order === 2);
    await page.evaluate(data => { window.smokeEvents = []; loadScenarioData(data); }, scenario);
    await page.evaluate(id => selectVehicle(id), wrong.id);
    await page.waitForFunction(() => window.smokeEvents.some(event => event.type === 'collision'));
    const collision = await page.evaluate(() => window.smokeEvents.find(event => event.type === 'collision'));
    assert.equal(collision.reason, priority.explanation);
    assert.equal(collision.pddArticle, scenario.pddArticle);
    assert.equal(collision.priorityId, priority.id);
    await page.screenshot({ path: path.join(output, 'collision.png') });

    await page.evaluate(() => { window.smokeEvents = []; resetCurrentScenario(); });
    assert.equal(await page.evaluate(() => window._pddCrossroads.vehiclesGroup.children.length), scenario.actors.length);
    // Перетаскивание крутит камеру и ничего не выбирает.
    const before = await page.evaluate(() => window._pddCrossroads.camera.position.toArray());
    await page.mouse.move(120, 700); await page.mouse.down();
    await page.mouse.move(260, 660, { steps: 8 }); await page.mouse.up();
    const after = await page.evaluate(() => window._pddCrossroads.camera.position.toArray());
    assert(Math.hypot(after[0] - before[0], after[2] - before[2]) > 3, 'drag rotates the camera');
    assert.equal(await page.evaluate(() => window.smokeEvents.length), 0, 'drag does not pick a car');
    // Настоящий тап по метке над машиной, которая едет первой.
    const pin = await page.evaluate(id => {
      const { vehiclesGroup, camera, renderer } = window._pddCrossroads;
      const mesh = vehiclesGroup.children.find(c => c.userData.actorId === id);
      const v = mesh.userData.badge.userData.sprite.getWorldPosition(new mesh.position.constructor()).project(camera);
      const r = renderer.domElement.getBoundingClientRect();
      return { x: (v.x + 1) / 2 * r.width, y: (1 - v.y) / 2 * r.height - 25 };
    }, priority.id);
    await page.mouse.click(pin.x, pin.y);
    await page.waitForFunction(() => window.smokeEvents.some(event => event.type === 'step_correct'));
    assert.equal(await page.evaluate(() => window.smokeEvents.find(e => e.type === 'vehicle_tapped').actorId), priority.id);
    await page.evaluate(() => resetCamera());
    await page.evaluate(() => setZoom(0.5));
    await page.screenshot({ path: path.join(output, 'zoom-out.png') });
    await page.evaluate(() => setZoom(2.5));
    await page.screenshot({ path: path.join(output, 'zoom-in.png') });
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify({ scenarios: selected.length, collision, errors }, null, 2));
    console.log(`${selected.length} scenarios, actual Dart collision explanation, retry, bridge and zoom passed; no JavaScript errors.`);
  } finally {
    if (browser) await browser.close();
    if (server) await new Promise(resolve => server.close(resolve));
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
