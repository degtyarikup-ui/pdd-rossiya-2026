// Audit every enabled question against its source and render the referenced
// letters. Mobile checks use the uncovered viewport between HUD and answers.
// Run with the GAME_URL / NODE_PATH setup from game-engine-test.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');

function referencedLetters(situation) {
  const text = [situation.title, ...situation.options].join(' | ');
  const letters = /траектор|Где Вы должны остановиться/ui.test(text) ? 'АБВГ' : 'АБГ';
  return [...new Set([...text.matchAll(new RegExp('(?:^|[\\s«"(,])([' + letters + '])(?=$|[\\s»".,!?)])', 'gu'))].map(m => m[1]))];
}

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0;
      window.events = [];
      window.FlutterChannel = { postMessage: m => window.events.push(JSON.parse(m)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
        window.questionEvidence = {
          catalog() { return [...SITUATIONS.filter(s => routeSpec(s).reviewed), ...(window.PDD_ROAD_SITUATIONS || [])]; },
          texturesReady() { return [...signTextureCache.values()].every(t => t.image && (t.image.complete ?? true)); },
          redraw() { renderer.render(scene, camera); },
          show(id, top = 110, bottom = 300) {
            resetGame(); state.attract = false;
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.actors = []; state.intersections = [];
            state.activeIntersection = null; state.occluders = []; state.ambient = [];
            state.exitRoad = currentCorridor = null;
            const road = (window.PDD_ROAD_SITUATIONS || []).find(s => s.id === id);
            if (road) {
              const seg = buildStraightSegment(-45, 200, true); state.roadSegments.push(seg);
              state.exitRoad = currentCorridor = seg; nextSegmentZ = 155;
              const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
              const ev = state.roadEvent = buildQuestionEvent(group, -45, road);
              playerCarGroup.position.set(-1.8, 0, ev.stopZ); playerCarGroup.rotation.y = 0;
              startRoadQuestion();
              this.group = group; this.actors = ev.actors; this.situation = road;
            } else {
              situationBag = [SITUATIONS.find(s => s.id === id)]; buildInitialTrack();
              const it = state.intersections[0];
              playerCarGroup.position.set(-1.8, 0, it.stopZ); playerCarGroup.rotation.y = 0;
              updatePlayerMovement(0);
              this.group = it.seg; this.actors = it.actors; this.situation = it.situation;
            }
            state.viewportInsets = {top, bottom}; state.viewportTarget = null;
            for (let i = 0; i < 240; i++) updateCamera(1/60);
            renderer.render(scene, camera);
            return this.snapshot();
          },
          snapshot() {
            scene.updateMatrixWorld(true);
            const width = container.clientWidth, height = container.clientHeight;
            const sprites = [];
            this.group.traverse(o => {
              if (o.userData.trajectoryLabel) sprites.push({label: o.userData.trajectoryLabel, sprite: o});
            });
            for (const a of this.actors) {
              const text = a.config.badge || a.config.name || '';
              const match = text.match(/(?:^|\\s)([АБВГ])$/u);
              if (match && a.mesh.userData.badge) sprites.push({label: match[1], sprite: a.mesh.userData.badge});
            }
            const labels = sprites.map(({label, sprite}) => {
              const at = sprite.getWorldPosition(new THREE.Vector3()).project(camera);
              const scale = sprite.getWorldScale(new THREE.Vector3());
              const x = (at.x + 1) * width / 2, y = (1 - at.y) * height / 2;
              const rx = scale.x * width / (camera.right - camera.left) / 2;
              const ry = scale.y * height / (camera.top - camera.bottom) / 2;
              let visible = true;
              for (let o = sprite; o; o = o.parent) visible &&= o.visible;
              return {label, x, y, rx, ry, visible,
                uncovered: x - rx >= 0 && x + rx <= width && y - ry >= state.viewportInsets.top && y + ry <= height - state.viewportInsets.bottom};
            });
            const arrows = [];
            this.group.traverse(o => {
              if (o.userData.guideArrow) arrows.push(o.getWorldPosition(new THREE.Vector3()).toArray());
              // Points along the continuous route band, in world coordinates.
              if (o.userData.routeStroke) o.userData.routePoints.forEach(p => arrows.push(new THREE.Vector3(...p).applyMatrix4(o.matrixWorld).toArray()));
            });
            const ev = state.roadEvent;
            let barrier = null;
            if (ev?.kind === 'detour') {
              const prop = state.props.find(p => p.ev === ev && p.kind === 'barrier');
              const at = prop.mesh.getWorldPosition(new THREE.Vector3()).project(camera);
              barrier = {x: (at.x + 1) * width / 2, y: (1 - at.y) * height / 2, framed: prop.mesh.userData.questionEvidence === true};
            }
            return {labels, arrows, barrier, originZ: ev?.stopZ ?? state.activeIntersection.centerZ};
          },
          answer() { window.game.proceedAfterAnswer(true, this.situation.id); renderer.render(scene, camera); return this.snapshot(); }
        };
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    // RAF is disabled for deterministic renders, so readiness must poll on a timer.
    await page.waitForFunction(() => window.questionEvidence && window.events.some(e => e.event === 'ready'), null, {polling: 100});
    const catalog = await page.evaluate(() => questionEvidence.catalog());
    const source = JSON.parse(fs.readFileSync('assets/countries/ru/questions/questions_ab.json', 'utf8'));
    const labelled = [];
    for (const s of catalog) {
      const [, ticket, number] = s.id.split('_');
      const q = source.tickets[Number(ticket) - 1].questions[Number(number) - 1];
      assert.equal(s.title, q.question, s.id + ': question text');
      assert.deepEqual(s.options, q.answers.map(a => a.text), s.id + ': options');
      assert.equal(s.correctAnswerIndex, q.answers.findIndex(a => a.correct), s.id + ': answer');
      const trajectories = s.scene?.trajectories || s.trajectories || [];
      const letters = [...new Set([...referencedLetters(s), ...trajectories.map(t => t.label).filter(Boolean)])];
      if (letters.length) labelled.push({s, letters});
      // Every trajectory alternative in a question must have authored geometry.
      if (/траектор/ui.test([s.title, ...s.options].join(' '))) {
        for (const letter of letters) assert(trajectories.some(t => t.label === letter), s.id + ': missing trajectory ' + letter);
      }
    }
    const output = process.env.GAME_SHOTS || 'build/game_ui/question-evidence';
    fs.mkdirSync(output, {recursive: true});
    const viewports = [
      {width: 320, height: 568, top: 90, bottom: 250},
      {width: 390, height: 844, top: 110, bottom: 300},
      {width: 402, height: 874, top: 110, bottom: 384},
    ];
    for (const v of viewports) {
      await page.setViewportSize({width: v.width, height: v.height});
      for (const {s, letters} of labelled) {
        const result = await page.evaluate(([id, top, bottom]) => questionEvidence.show(id, top, bottom), [s.id, v.top, v.bottom]);
        await page.waitForFunction(() => questionEvidence.texturesReady(), null, {polling: 50});
        await page.evaluate(() => questionEvidence.redraw());
        for (const letter of letters) {
          const labels = result.labels.filter(l => l.label === letter);
          assert.equal(labels.length, 1, s.id + ': rendered letter ' + letter);
          assert(labels[0].visible && labels[0].uncovered, s.id + ': letter behind HUD/answers ' + JSON.stringify(labels[0]));
        }
        if (s.scene?.trajectories || s.trajectories) {
          assert(result.arrows.length > 5, s.id + ': visible alternatives');
          assert(result.labels.every(l => l.rx * 2 >= 23.9), s.id + ': readable trajectory letters');
          const trajectories = s.scene?.trajectories || s.trajectories;
          for (const t of trajectories) {
            const [x, z] = t.points.at(-1), worldX = s.scene ? x : -x;
            assert(result.arrows.some(p => Math.hypot(p[0] - worldX, p[2] - result.originZ - z) < 2.5), s.id + ': arrows reach alternative ' + t.label);
          }
          for (let i = 0; i < result.labels.length; i++) for (let j = i + 1; j < result.labels.length; j++) {
            const a = result.labels[i], b = result.labels[j];
            assert(Math.abs(a.x - b.x) > a.rx + b.rx || Math.abs(a.y - b.y) > a.ry + b.ry, s.id + ': overlapping trajectory letters');
          }
          await page.screenshot({path: output + '/' + s.id + '-' + v.width + '.png'});
        }
        if (s.scene?.kind === 'detour') {
          assert(result.barrier.framed && result.barrier.y > v.top && result.barrier.y < v.height - v.bottom, s.id + ': obstacle framing');
          assert(result.labels.find(l => l.label === 'А').x < result.barrier.x, 'А must pass left of the obstacle');
          assert(result.labels.find(l => l.label === 'Б').x > result.barrier.x, 'Б must pass right of the obstacle');
          const answered = await page.evaluate(() => questionEvidence.answer());
          assert(answered.labels.every(l => !l.visible), s.id + ': hide alternatives when driving resumes');
        }
      }
    }
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({questionsAudited: catalog.length, labelledQuestions: labelled.map(x => x.s.id), viewports: viewports.length, screenshots: output}));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
