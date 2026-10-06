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
        state, routeSpec, THREE, get scene() { return scene; }, roadSupports: p => roadSupports(p), refreshRoadBounds: () => refreshRoadBounds(), player: () => playerCarGroup, camera: () => camera,
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

    // Actor-path audit: a vehicle's whole path (with its body width) must
    // not run through a pole: a lamp, a sign or a signal, a tree trunk.
    const report = await page.evaluate((process_ids) => {
      const t = window.__engineTest, s = t.state, T = t.THREE, out = [];
      const all = t.allScenarios();
      for (let i = 0; i < all.length; i++) {
        if (process_ids && !process_ids.includes(all[i].id)) continue;
        t.selectAll(i); s.paused = true; t.approach();
        t.scene.updateMatrixWorld(true);
        const poles = [];
        s.roadSegments.forEach(seg => seg.traverse(o => {
          if (!o.isMesh || !o.visible || o.userData.actor) return;
          for (let r = o; r; r = r.parent) if (r.userData.actor || r === t.player() || !r.visible) return;
          const g = o.geometry; if (!g || g.type !== 'CylinderGeometry' && g.type !== 'BoxGeometry') return;
          const b = new T.Box3().setFromObject(o);
          const w = b.max.x - b.min.x, d = b.max.z - b.min.z, h = b.max.y - b.min.y;
          if (w > .35 || d > .35 || h < 1.2 || b.min.y > .4) return;
          let sign = false; for (let r = o; r; r = r.parent) if (r.userData.signCode) sign = r.userData.signCode;
          const chain=[];for(let r=o;r&&chain.length<6;r=r.parent)chain.push(r.type+':'+Object.keys(r.userData).join('|')+':'+r.visible);
          poles.push({ x: (b.min.x + b.max.x) / 2, z: (b.min.z + b.max.z) / 2, sign, chain });
        }));
        for (const a of s.actors || []) {
          if (!a.path || a.config.type === 'pedestrian' || a.config.type === 'bike') continue;
          const fp = t.actorFootprint(a), half = fp.halfWidth || 1;
          const route = a.railPath || a.path, L = route.getLength();
          for (let u = 0; u <= L; u += .5) {
            const p = route.getPointAt(Math.min(1, u / L)).clone().applyMatrix4(a.mesh.parent.matrixWorld);
            const hit = poles.find(q => Math.hypot(q.x - p.x, q.z - p.z) < half + .15);
            if (hit) { out.push({ id: all[i].id, actor: a.config.id, type: a.config.type, pole: [+hit.x.toFixed(1), +hit.z.toFixed(1)], sign: hit.sign, chain: hit.chain }); break; }
          }
        }
      }
      return { out, counted: all.length };
    }, (process.env.IDS||'').split(',').filter(Boolean).length ? process.env.IDS.split(',') : null);
    console.log('scenes:', report.counted, 'hits:', report.out.length);
    report.out.forEach(r => console.log(JSON.stringify(r)));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
