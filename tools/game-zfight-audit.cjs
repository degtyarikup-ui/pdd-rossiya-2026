// Run with NODE_PATH pointing at a Playwright installation and a local HTTP server.
// Instrumentation is injected into the response only; no debug API ships in the app.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
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
        state, routeSpec, THREE, get scene() { return scene; }, player: () => playerCarGroup, camera: () => camera,
        scenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed && !isRegulatorSituation(s)),
        allScenarios: () => SITUATIONS.filter(s => routeSpec(s).reviewed),
        drawSituation: nextSituation,
        randomSequence(n) { situationBag = []; state.regulatorAt = Infinity; return Array.from({ length: n }, () => nextSituation().id); },
        updateActors, updateCamera,
        roadQueue(ids) { roadBag = ids.map(id => window.PDD_ROAD_SITUATIONS.find(r => r.id === id)).reverse(); },
        actorInView,
        createTrafficLight,
        maybeReverseWorld, corridorWorldEnds,
        playerOnRoad, playerFootprint, actorFootprint, footprintsOverlap, integrateDriving,
        audioSnapshot: () => gameAudio.snapshot(), updateAudio: (dt, elapsed) => gameAudio.update(dt, elapsed),
        surfaceAt(x, z) {
          scene.updateMatrixWorld(true);
          const ray = new THREE.Raycaster(new THREE.Vector3(x, 30, z), new THREE.Vector3(0, -1, 0));
          const surfaces = [];
          state.roadSegments.forEach(seg => seg.traverse(o => { if (o.userData.surface) surfaces.push(o); }));
          return ray.intersectObjects(surfaces, false).filter(hit =>
            hit.object.userData.surface && (hit.object.material.clippingPlanes || []).every(p => p.distanceToPoint(hit.point) >= -0.001))
            .map(hit => hit.object.userData.surface);
        },
        drive(maxFrames = 2400) {
          const r = state.resolution;
          if (!r) return;
          this.tick(20);
          let progress = 0;
          for (let frame = 0; frame < maxFrames && state.resolution; frame++) {
            let nearest = progress, best = Infinity;
            for (let t = progress; t <= Math.min(1, progress + 0.12); t += 0.005) {
              const d = r.path.getPointAt(t).distanceTo(playerCarGroup.position);
              if (d < best) { best = d; nearest = t; }
            }
            progress = nearest;
            const target = progress > 0.94 ? r.path.getPointAt(1).addScaledVector(r.path.getTangentAt(1), 20) :
              r.path.getPointAt(Math.min(1, progress + 2.5 / r.length));
            const heading = Math.atan2(target.x - playerCarGroup.position.x, target.z - playerCarGroup.position.z);
            const error = Math.atan2(Math.sin(heading - playerCarGroup.rotation.y), Math.cos(heading - playerCarGroup.rotation.y));
            window.game.setSteering(Math.max(-1, Math.min(1, error * 3 / (Math.max(1, state.speed) * 0.32))));
            window.game.setGas(state.speed < 4);
            this.tick(1 / 60);
            if (r.recovery) return { failure: 'impact', position: playerCarGroup.position.toArray(), faults: [...r.faults] };
          }
          window.game.setGas(false); window.game.setSteering(0);
          return { complete: !state.resolution };
        },
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
        selectAll(index) {
          resetGame();
          state.roadSegments.forEach(disposeSegment);
          state.roadSegments = []; state.intersections = [];
          situationIndex = index; situationBag = [this.allScenarios()[index]]; buildInitialTrack();
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
    await page.waitForFunction(() => window.events.some(e => e.event === 'ready'), null, { timeout: 90000 });

    // Z-fighting audit: at every point of a 0.5 m grid a vertical ray goes
    // through all flat ground pieces (asphalt, markings, pavements, lawns);
    // where the two topmost ones differ in colour but lie within 4 mm of
    // each other, the GPU cannot tell which is on top: they flicker.
    const scan = await page.evaluate(({ ids, step }) => {
      const t = window.__engineTest, s = t.state, T = t.THREE, found = {};
      const stats = { rays: 0, multi: 0, minDy: Infinity, minAt: null };
      const scanArea = (label, cx, cz, half) => {
        t.scene.updateMatrixWorld(true);
        const meshes = [], flat = new T.Box3();
        t.scene.traverse(o => {
          if (!o.isMesh || !o.visible || !o.material) return;
          let root = o, skip = false, visible = true;
          while (root) { if (root.userData.sceneryObject || root.userData.actor || root === t.player()) skip = true; if (!root.visible) visible = false; root = root.parent; }
          if (skip || !visible) return;
          flat.setFromObject(o);
          if (flat.isEmpty() || flat.max.y > 0.35 || flat.max.x < cx - half || flat.min.x > cx + half || flat.max.z < cz - half || flat.min.z > cz + half) return;
          const m = Array.isArray(o.material) ? o.material[0] : o.material;
          if (!m.color || m.transparent && m.opacity < 0.95) return;
          meshes.push(o);
        });
        const ray = new T.Raycaster(); ray.far = 10;
        const down = new T.Vector3(0, -1, 0), hits = [];
        for (let x = cx - half; x <= cx + half; x += step) for (let z = cz - half; z <= cz + half; z += step) {
          ray.set(new T.Vector3(x, 5, z), down);
          const h = ray.intersectObjects(meshes, false).filter(hit => {
            const m = Array.isArray(hit.object.material) ? hit.object.material[hit.face?.materialIndex || 0] : hit.object.material;
            return (m.clippingPlanes || []).every(p => p.distanceToPoint(hit.point) >= -0.001) && (!hit.face || hit.face.normal.clone().transformDirection(hit.object.matrixWorld).y > 0.5 || m.side === T.DoubleSide);
          });
          stats.rays++;
          if (h.length < 2) continue;
          stats.multi++;
          const colorOf = hit => { const m = Array.isArray(hit.object.material) ? hit.object.material[hit.face?.materialIndex || 0] : hit.object.material; return m.color.getHex(); };
          const a = h[0], b = h.find(k => colorOf(k) !== colorOf(a));
          if (b) { const dy = Math.abs(a.point.y - b.point.y); if (dy < stats.minDy) { stats.minDy = dy; stats.minAt = [label, +x.toFixed(1), +(z - cz).toFixed(1), colorOf(a).toString(16), colorOf(b).toString(16), +a.point.y.toFixed(4), +b.point.y.toFixed(4)]; } }
          if (b && Math.abs(a.point.y - b.point.y) < 0.004) {
            const key = label + ' ' + colorOf(a).toString(16) + '/' + colorOf(b).toString(16) + ' @' + a.point.y.toFixed(3);
            (found[key] ||= []).push([+x.toFixed(1), +(z - cz).toFixed(1)]);
          }
        }
      };
      for (const id of ids) {
        const i = t.allScenarios().findIndex(sc => sc.id === id);
        t.selectAll(i); s.paused = true; t.approach();
        const it = s.activeIntersection;
        scanArea(id, 0, it.centerZ, 40);
      }
      found.__stats = [stats];
      return Object.fromEntries(Object.entries(found).map(([k, v]) => [k, { n: v.length, sample: v.slice(0, 4) }]));
    }, { ids: (process.env.IDS || 'ticket_7_13,ticket_15_14,ticket_16_14,ticket_22_13,ticket_26_13,ticket_28_13,ticket_3_15,ticket_20_14,ticket_1_13,ticket_18_8').split(','), step: Number(process.env.STEP || 0.5) });
    const keys = Object.keys(scan);
    keys.forEach(k => console.log(k, JSON.stringify(scan[k])));
    console.log('z-fight spots:', keys.length);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
