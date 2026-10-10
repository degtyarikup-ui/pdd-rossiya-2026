// Run with NODE_PATH pointing at a Playwright installation and a local HTTP server.
// Instrumentation is injected into the response only; no debug API ships in the app.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.events = [];
      window.FlutterChannel = { postMessage: message => window.events.push(JSON.parse(message)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
      window.__engineTest = {
        state, routeSpec, createRouteGuide, curve, player: () => playerCarGroup, camera: () => camera,
        scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed && !isRegulatorSituation(s)),
        tick(seconds) {
          for (let i = 0; i < Math.ceil(seconds * 60); i++) {
            if (reveal) { updateReveal(1/60); continue; }
            if (!state.paused) {
              updateAttract(1/60);
              updateActors(1/60);
              if (state.resolution) updateResolution(1/60); else updatePlayerMovement(1/60);
              updateRoadEvent(1/60);
            }
            updateBlinkers(1/60); gameAudio.update(1/60, performance.now() / 1000); updateCamera(1/60); checkAndSpawnNext();
          }
          if (seconds >= 0.1) renderer.render(scene, camera);
        },
        select(index) {
          resetGame();
          state.roadSegments.forEach(disposeSegment);
          state.roadSegments = []; state.intersections = [];
          situationIndex = index; situationBag = [this.scenarios()[index]]; buildInitialTrack();
        },
        approach() {
          if (!state.intersections.length) {
            playerCarGroup.position.z = nextSegmentZ - 100;
            checkAndSpawnNext();
          }
          playerCarGroup.position.z = state.intersections[0].stopZ;
          updatePlayerMovement(0);
        }
      };
      // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'));


    const result = await page.evaluate(() => {
      const t = window.__engineTest, s = t.state;
      const straight = t.createRouteGuide([t.curve([new THREE.Vector3(0,0,0), new THREE.Vector3(0,0,80)])]);
      const straightTip = straight.children.find(o => o.userData.guideArrow).position.z;
      if (Math.abs(straightTip - 14) > .01) throw new Error('Straight direction cue is too long: ' + straightTip);
      const turn = t.createRouteGuide([t.curve([[0,0],[0,5],[2,8],[5,10],[50,10]].map(([x,z]) => new THREE.Vector3(x,0,z)))]);
      const tip = turn.children.find(o => o.userData.guideArrow).position;
      if (tip.x > 15 || tip.x < 4 || Math.abs(tip.z - 10) > 1) throw new Error('Turn cue does not end shortly into the receiving lane: ' + tip.toArray());
      const cases = [];
      t.scenarios().forEach((sc, i) => {
        if (sc.geometry !== 'divided_main') return;
        for (const direction of [1, -1, 2]) {
          t.select(i); s.paused = false; window.game.setSimpleSteering(true); t.approach();
          const it = s.activeIntersection;
          // Hold while the question still blocks driving; apply only later.
          window.game.setSteering(direction);
          const waiting = s.resolution == null;
          window.game.proceedAfterAnswer(true, it.situation.id);
          window.game.releaseTraffic(it.situation.id);
          t.tick(4);
          window.game.setGas(true);
          let chosen = null;
          for (let f=0;f<1200 && s.resolution;f++) {
            t.tick(1/60);
            if(s.resolution?.simpleChoice && s.resolution.simpleChoice !== 'straight') chosen=s.resolution.simpleChoice;
            if(s.resolution?.recovery) break;
          }
          window.game.setSteering(0); window.game.setGas(false);
          cases.push({id:sc.id,direction,chosen,waiting,recovery:!!s.resolution?.recovery});
        }
      });
      return cases;
    });
    console.log(JSON.stringify(result));
    assert(result.length > 0);
    for (const c of result) {
      assert(c.waiting);
      assert.equal(c.chosen, ({1:'left', '-1':'right', 2:'uturn'})[c.direction], JSON.stringify(c));
      assert.equal(c.recovery, false, JSON.stringify(c));
    }
    if (process.env.GAME_CAPTURE) {
      await page.evaluate(() => {
        const t=window.__engineTest;
        t.select(t.scenarios().findIndex(sc => sc.geometry === 'divided_main'));
        t.state.paused=false; t.approach();
        window.game.proceedAfterAnswer(true, t.state.activeIntersection.situation.id);
        t.tick(4); window.game.setPaused(true);
      });
      await page.screenshot({path:process.env.GAME_CAPTURE});
    }
    assert.equal(errors.length,0,errors.join('\n'));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exit(1); });
