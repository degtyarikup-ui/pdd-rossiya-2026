// Render every reviewed intersection scenario for visual/legal QA.
// Run with the same GAME_URL / NODE_PATH setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
        window.intersectionReview = {
          ready() { return !!playerCarGroup; },
          ids() { return SITUATIONS.filter(s => routeSpec(s).reviewed === true).map(s => s.id); },
          surfacesAt(x, z) {
            scene.updateMatrixWorld(true);
            const surfaces = [];
            state.roadSegments.forEach(s => s.traverse(o => { if (o.userData.surface) surfaces.push(o); }));
            const ray = new THREE.Raycaster(new THREE.Vector3(x, 20, z), new THREE.Vector3(0, -1, 0));
            return ray.intersectObjects(surfaces, false).filter(h =>
              (h.object.material.clippingPlanes || []).every(p => p.distanceToPoint(h.point) >= -0.001))
              .map(h => ({ surface: h.object.userData.surface, dirt: !!h.object.userData.dirtSurface }));
          },
          dirtApproach() {
            const it = state.activeIntersection;
            const center = it.centerZ;
            const core = [10, 30, 34.9, 35.1, 50, 75].map(d => this.surfacesAt(-d, center));
            const shoulders = [6, 10, 30, 50, 75].flatMap(d => [-1, 1].map(side => this.surfacesAt(-d, center + side * 6.5)));
            return { core, shoulders };
          },
          enterDirt(distance = 15) {
            const it = state.activeIntersection;
            window.game.proceedAfterAnswer(true, it.situation.id);
            state.resolution.exitDirection = 'right'; state.resolution.exitYaw = -Math.PI / 2;
            playerCarGroup.position.set(-26, 0, it.centerZ - 1.8);
            playerCarGroup.rotation.y = -Math.PI / 2;
            state.roadTurn = 1; state.forceRoadEvent = 'cyclist';
            finishManeuver();
            scene.updateMatrixWorld(true); refreshRoadBounds();
            const road = state.exitRoad;
            const supported = [2, 8, 12, 30, 60, 90, 120, 150].flatMap(z => [-1.8, 1.8].map(x =>
              playerOnRoad(road.localToWorld(new THREE.Vector3(x, 0, z)), 0)));
            const paved = road.localToWorld(new THREE.Vector3(0, 0, road.userData.dirtPavedFrom)).z;
            this.dirtView(distance);
            return { supported, paved, eventZ: state.roadEvent.cycZ };
          },
          dirtView(distance) {
            playerCarGroup.position.copy(state.exitRoad.localToWorld(new THREE.Vector3(-1.8, 0, distance)));
            state.viewportInsets = { top: 110, bottom: 150 }; state.viewportTarget = null;
            for (let i = 0; i < 240; i++) updateCamera(1/60);
            renderer.render(scene, camera);
          },
          show(id) {
            resetGame(); state.attract = false;
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.actors = []; state.intersections = [];
            state.activeIntersection = null; state.occluders = []; state.ambient = [];
            state.exitRoad = currentCorridor = null;
            const situation = SITUATIONS.find(s => s.id === id);
            if (!situation || routeSpec(situation).reviewed !== true) throw new Error('Unreviewed situation: ' + id);
            situationBag = [situation]; buildInitialTrack();
            const intersection = state.intersections[0];
            playerCarGroup.position.z = intersection.stopZ;
            updatePlayerMovement(0);
            state.viewportInsets = { top: 110, bottom: 300 }; state.viewportTarget = null;
            for (let i = 0; i < 180; i++) updateCamera(1/60);
            renderer.render(scene, camera);
            let crosswalks = 0, stopLines = 0, tSidewalks = 0, tEdgeBridges = 0;
            let tangentDashes = true, ringDashes = 0;
            intersection.seg.traverse(o => {
              if (intersection.situation.geometry === 'roundabout' && o.userData.roadMarking) {
                ringDashes++;
                const radial = new THREE.Vector3(o.position.x, 0, o.position.z - intersection.centerZ).normalize();
                const along = new THREE.Vector3(0, 0, 1).applyQuaternion(o.quaternion);
                tangentDashes &&= Math.abs(radial.dot(along)) < 0.001;
              }
              if (o.userData.crosswalk) crosswalks++;
              if (o.userData.stopLine) stopLines++;
              if (o.userData.tJunctionSidewalk) tSidewalks++;
              if (o.userData.tJunctionEdgeBridge) tEdgeBridges++;
            });
            scene.updateMatrixWorld(true);
            const ray = new THREE.Raycaster(new THREE.Vector3(0, 20, intersection.centerZ + 12), new THREE.Vector3(0, -1, 0));
            const surfaces = [];
            state.roadSegments.forEach(s => s.traverse(o => { if (o.userData.surface) surfaces.push(o); }));
            const farArmRoad = ray.intersectObjects(surfaces, false).some(h => h.object.userData.surface === 'road' &&
              (h.object.material.clippingPlanes || []).every(p => p.distanceToPoint(h.point) >= -0.001));
            return {
              actors: intersection.situation.actorsConfig.length,
              renderedActors: intersection.actors.length,
              signs: intersection.situation.signs.length,
              maneuver: routeSpec(intersection.situation).maneuver,
              yieldTo: routeSpec(intersection.situation).yieldTo,
              geometry: intersection.situation.geometry || 'cross',
              hasStraightExit: !!intersection.previews.straight,
              crosswalks, tangentDashes, ringDashes,
              expectedCrosswalks: !!intersection.situation.crosswalks?.length,
              stopLines,
              expectedStopLine: intersection.situation.hasStopLine ?? (!!intersection.situation.trafficLights ||
                intersection.situation.signs.some(s => s.code === '2.5')),
              farArmRoad,
              // A hand-drawn layout (skew_three_way…) has its far arm at an
              // angle: the straight-ahead probe at x = 0 misses it by design.
              authoredLayout: !!intersection.situation.junctionLayout,
              tSidewalks,
              tEdgeBridges,
            };
          },
          render() { renderer.render(scene, camera); }
        };
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.intersectionReview?.ready(), null, { polling: 100 });
    const allIds = await page.evaluate(() => intersectionReview.ids());
    const ids = process.env.GAME_SCENARIO ? allIds.filter(id => id === process.env.GAME_SCENARIO) : allIds;
    const output = process.env.GAME_SHOTS || 'build/game_ui/intersection-review';
    fs.mkdirSync(output, { recursive: true });
    for (const id of ids) {
      const result = await page.evaluate(id => intersectionReview.show(id), id);
      assert.equal(result.renderedActors, result.actors, id + ': actor count');
      assert(result.tangentDashes, id + ': roundabout dashes must follow the lane');
      if (result.geometry === 'roundabout') assert(result.ringDashes > 10);
      assert.equal(result.crosswalks, result.expectedCrosswalks ? 1 : 0, id + ': pedestrian-crossing evidence');
      assert.equal(result.stopLines, result.expectedStopLine ? 1 : 0, id + ': stop-line evidence');
      assert.equal(result.hasStraightExit, result.geometry !== 't_no_straight', id + ': junction geometry');
      if (!result.authoredLayout) assert.equal(result.farArmRoad, result.geometry !== 't_no_straight', id + ': far-arm asphalt');
      assert.equal(result.tSidewalks, result.geometry === 't_no_straight' ? 1 : 0, id + ': continuous T-junction sidewalk');
      assert.equal(result.tEdgeBridges, result.geometry === 't_no_straight' ? 1 : 0, id + ': continuous T-junction edge marking');
      await page.evaluate(() => new Promise(resolve => setTimeout(() => { intersectionReview.render(); resolve(); }, 100)));
      await page.screenshot({ path: output + '/' + id + '.png' });
      if (result.geometry === 'dirt_approach') {
        const dirt = await page.evaluate(() => intersectionReview.dirtApproach());
        for (const surfaces of dirt.core) {
          assert(surfaces.some(s => s.surface === 'road' && s.dirt), id + ': dirt continues across the preview seam');
          assert(!surfaces.some(s => s.surface === 'road' && !s.dirt), id + ': no asphalt under the unpaved arm');
        }
        assert(dirt.shoulders.every(surfaces => !surfaces.some(s => s.surface === 'sidewalk')), id + ': grass shoulders, including the mouth');
        const drive = await page.evaluate(() => intersectionReview.enterDirt());
        assert(drive.supported.every(Boolean), id + ': both lanes remain drivable after the turn');
        assert(drive.eventZ > drive.paved, id + ': next event follows the unpaved section');
        await page.screenshot({ path: output + '/' + id + '-right.png' });
        await page.evaluate(() => intersectionReview.dirtView(60));
        await page.screenshot({ path: output + '/' + id + '-transition.png' });
      }
    }
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ reviewed: ids.length, screenshots: output }));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
