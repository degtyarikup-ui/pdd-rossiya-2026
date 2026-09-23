// All road questions remain playable; verify their rendered evidence with the real engine.
// Run with the same GAME_URL / NODE_PATH setup as game-engine-test.cjs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { Buffer } = require('node:buffer');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader']});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}});
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
        window.roadReview = {
          sample(n) { roadBag = []; return Array.from({length:n}, () => nextRoadSituation()?.id ?? null); },
          signMounting() {
            const sign = createRoadSign('2.4');
            const plate = createTextPlate('200 м');
            const pole = sign.children.find(o => o.geometry?.type === 'CylinderGeometry');
            const face = sign.children.find(o => o.geometry?.type === 'PlaneGeometry');
            const plateFace = plate.children.find(o => o.geometry?.type === 'PlaneGeometry');
            const poleFront = -Math.max(pole.geometry.parameters.radiusTop, pole.geometry.parameters.radiusBottom);
            return {poleFront, signFace: face.position.z, plateFace: plateFace.position.z};
          },
          showOneWay(id) {
            resetGame(); state.attract = false;
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.intersections = [];
            const situation = SITUATIONS.find(s => s.id === id);
            situationBag = [situation]; buildInitialTrack();
            playerCarGroup.position.z = state.intersections[0].stopZ;
            updatePlayerMovement(0);
            state.viewportInsets = {top: 110, bottom: 300}; state.viewportTarget = null;
            for (let i = 0; i < 180; i++) updateCamera(1/60);
            renderer.render(scene, camera);
            const texture = signTextureCache.get(situation.signs[0].code);
            const faces = [];
            state.intersections[0].seg.traverse(o => {
              if (o.isMesh && o.material?.map === texture) faces.push(o);
            });
            return {faces: faces.length, aspect: faces[0]?.geometry.parameters.width / faces[0]?.geometry.parameters.height};
          },
          show(id) {
            resetGame(); state.attract = false;
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.actors = []; state.intersections = [];
            state.activeIntersection = null; state.occluders = []; state.ambient = [];
            state.exitRoad = currentCorridor = null;
            const road = buildStraightSegment(-45, 200, true); state.roadSegments.push(road);
            state.exitRoad = currentCorridor = road; nextSegmentZ = 155;
            const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
            const s = window.PDD_ROAD_SITUATIONS.find(s => s.id === id);
            const ev = state.roadEvent = buildQuestionEvent(group, -45, s);
            playerCarGroup.position.set(-1.8, 0, ev.stopZ); startRoadQuestion();
            state.viewportInsets = {top: 110, bottom: 300}; state.viewportTarget = null;
            playerCarGroup.position.set(-1.8, 0, ev.stopZ);
            for (let i = 0; i < 180; i++) updateCamera(1/60);
            updateRoadEvent(0); renderer.render(scene, camera);
            return {actors: ev.actors.length, signs: (s.scene.signs || []).every(sg => !!window.PDD_SIGN_TEXTURES[sg.code]),
              visibleActors: ev.actors.every(a => { const p = a.mesh.position.clone().project(camera);
                return Math.abs(p.x) < 1 && p.y < 1 - 220/844 && p.y > -1 + 600/844; })};
          },
          sideExit(side) {
            const ev = state.roadEvent;
            ev.phase = 'manual'; state.isAtSituation = false;
            playerCarGroup.position.set(side * 36, 0, ev.junctionZ - side * 1.8);
            playerCarGroup.rotation.y = side * Math.PI / 2;
            updateRoadEvent(0);
            return [10, 30, 70, 110].every(d => this.surface(-1.8, playerCarGroup.position.z + d).includes('road'));
          },
          surface(x, z) {
            scene.updateMatrixWorld(true);
            const ray = new THREE.Raycaster(new THREE.Vector3(x, 20, z), new THREE.Vector3(0,-1,0));
            const meshes = []; state.roadSegments.forEach(s => s.traverse(o => { if (o.userData.surface) meshes.push(o); }));
            return ray.intersectObjects(meshes, false).filter(h => (h.object.material.clippingPlanes || []).every(p => p.distanceToPoint(h.point) >= -0.001)).map(h => h.object.userData.surface);
          },
          evidence() {
            const ev = state.roadEvent, s = ev.scene, result = {};
            if (s.junction) {
              result.crossingRoad = [-25,-6,0,6,25].every(x => {
                const hits = this.surface(x, ev.junctionZ); return hits.includes('road') && !hits.includes('sidewalk');
              });
              result.wholeScenery = true;
              state.roadSegments.forEach(seg => seg.traverse(o => {
                if (!o.userData.sceneryObject) return;
                o.traverse(part => {
                  const materials = Array.isArray(part.material) ? part.material : [part.material];
                  if (materials.some(m => m?.clippingPlanes?.length)) result.wholeScenery = false;
                });
              }));
              result.sideRoadsContinue = [-60, 60, -150, 150].every(x => this.surface(x, ev.junctionZ).includes('road'));
              result.crossingConnects = [-12,12].every(d => this.surface(-1.8, ev.junctionZ + d).includes('road'));
              if (s.junction.priority === 'secondary') {
                result.plateDistance = ev.junctionZ - (ev.stopZ + s.signs[0].z) === 200;
                result.nextJunctionAfterAuthored = nextSegmentZ >= ev.junctionZ + 55;
              }
              ev.phase = 'manual';
              result.overtakeAtCrossing = roadOvertakeAllowedAt(ev.junctionZ) === (s.junction.priority === 'main');
              result.overtakeBeforeCrossing = roadOvertakeAllowedAt(ev.junctionZ - 15);
              ev.phase = 'question';
            }
            if (s.motorway) {
              // Mid-motorway (past the 45 m swing-out): own carriageway, grass
              // median, then the opposite carriageway (not drivable from here).
              const mz = ev.stopZ + 90;
              result.separateCarriageways = this.surface(-1.8, mz).includes('road') && this.surface(11.4, mz).includes('road') &&
                this.surface(5.7, mz).includes('median') && !this.surface(5.7, mz).includes('road');
              result.forwardLeftLane = roadOvertakeAllowedAt(mz);
            }
            if (s.outsideSettlement) {
              result.ruralShoulder = !this.surface(-5.7, ev.stopZ + 12).includes('sidewalk');
              result.approachLimit = state.speedLimitKmH === 70;
              ev.phase = 'manual'; playerCarGroup.position.z = ev.signZ + 1; updateRoadEvent(0);
              result.limitAfterSign = state.speedLimitKmH === 90;
              playerCarGroup.position.z = ev.stopZ; ev.phase = 'question';
            }
            if (ev.situation.id === 'road_18_11') {
              // Truck Б joins from behind when the question starts: in the
              // player's lane behind them, signalling left (it has begun overtaking).
              const b = ev.actors.find(a => a.config.maneuver === 'overtake');
              result.truckBehindOvertaking = !!b && b.mesh.position.z < ev.stopZ && b.mesh.position.x < 0 && b.signalPlan[0].side === 'left';
            }
            if (ev.situation.id === 'road_20_11') // As in the photo: the truck just ahead is still in its lane with the
            // left signal on (it is starting to overtake).
            result.truckAheadOvertaking = ev.actors[0].mesh.position.z > ev.stopZ && ev.actors[0].mesh.position.x < 0 && ev.actors[0].signalPlan[0].side === 'left';
            if (ev.situation.id === 'road_2_11') result.rightHandTraffic = ev.actors[1].mesh.position.x < -8 && ev.actors[0].dependencies.includes(ev.actors[1]);
            if (s.junction) {
              // The world turns round the player's position: the crossing ends
              // up mirrored about it.
              const mirrored = 2 * playerCarGroup.position.z - ev.junctionZ;
              playerCarGroup.rotation.y = Math.PI; state.isAtSituation = false;
              maybeReverseWorld(true);
              result.crossingSurvivesReversal = this.surface(6, mirrored).includes('road') && !this.surface(6, mirrored).includes('sidewalk');
            }
            return result;
          },
          render() { renderer.render(scene, camera); }
        };
        // Run init on DOM ready`);
      await route.fulfill({response, body});
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.roadReview);
    const catalog = await page.evaluate(() => window.PDD_ROAD_SITUATIONS);
    assert.equal(catalog.length, 18);
    const splitCodes = ['5.7.1', '5.7.2', '5.19.1', '5.19.2'];
    const splitSigns = await page.evaluate(codes => codes.map(code => window.PDD_SIGN_TEXTURES[code]), splitCodes);
    const splitSvgs = splitSigns.map(uri => Buffer.from(uri.split(',')[1], 'base64').toString('utf8'));
    assert.match(splitSvgs[0], /viewBox="0 0 137 48"/);
    assert.match(splitSvgs[1], /viewBox="148 0 137 48"/);
    assert.match(splitSvgs[2], /viewBox="0 3 84 84"/);
    assert.match(splitSvgs[3], /viewBox="89 3 84 84"/);
    assert.equal(await page.evaluate(() => window.PDD_SIGN_ASPECT['5.7.1']), 2.854);
    assert.equal(await page.evaluate(() => window.PDD_SIGN_ASPECT['5.7.2']), 2.854);
    const mounting = await page.evaluate(() => roadReview.signMounting());
    assert(mounting.signFace < mounting.poleFront, 'road sign face must be in front of its pole');
    assert(mounting.plateFace < mounting.poleFront, 'supplementary plate must be in front of its pole');
    const questions = JSON.parse(fs.readFileSync('assets/countries/ru/questions/questions_ab.json', 'utf8'));
    for (const scene of catalog) {
      const [, ticket, number] = scene.id.split('_');
      const q = questions.tickets[Number(ticket)-1].questions[Number(number)-1];
      assert.equal(scene.title, q.question); assert.equal(scene.explanation, q.comment);
      assert.deepEqual(scene.options, q.answers.map(a => a.text));
      assert.equal(scene.correctAnswerIndex, q.answers.findIndex(a => a.correct));
    }
    const enabled = catalog;
    const ids = enabled.map(s => s.id).sort();
    const samples = await page.evaluate(() => roadReview.sample(180));
    for (let i = 0; i < samples.length; i += ids.length) assert.deepEqual(samples.slice(i, i + ids.length).sort(), ids);
    const output = process.env.GAME_SHOTS || 'build/game_ui/road-review';
    fs.mkdirSync(output, {recursive: true});
    for (const s of enabled) {
      const result = await page.evaluate(id => roadReview.show(id), s.id);
      assert.equal(result.actors, (s.scene.vehicles || []).length, s.id);
      assert(result.signs, s.id + ' sign texture missing');
      assert(result.visibleActors, s.id + ' actor hidden behind question/HUD');
      await page.evaluate(() => new Promise(resolve => setTimeout(() => { roadReview.render(); resolve(); }, 100)));
      await page.screenshot({path: output + '/' + s.id + '.png'});
      const evidence = await page.evaluate(() => roadReview.evidence());
      for (const [name, passed] of Object.entries(evidence)) assert.equal(passed, true, s.id + ': ' + name);
    }
    for (const side of [-1, 1]) {
      await page.evaluate(() => roadReview.show('road_38_11'));
      assert(await page.evaluate(side => roadReview.sideExit(side), side), 'side exit must generate a continuous driving corridor');
    }
    const oneWayOutput = output + '/one-way'; fs.mkdirSync(oneWayOutput, {recursive: true});
    for (const id of ['ticket_18_8', 'ticket_14_8']) {
      const rendered = await page.evaluate(id => roadReview.showOneWay(id), id);
      assert.equal(rendered.faces, 1, id + ': exactly one one-way sign face');
      assert(Math.abs(rendered.aspect - 2.854) < 0.002, id + ': individual sign aspect');
      await page.evaluate(() => new Promise(resolve => setTimeout(() => { roadReview.render(); resolve(); }, 150)));
      await page.screenshot({path: oneWayOutput + '/' + id + '.png'});
    }
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({reviewed: ids, playable: ids.length, selectionDraws: samples.length, screenshots: output}));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
