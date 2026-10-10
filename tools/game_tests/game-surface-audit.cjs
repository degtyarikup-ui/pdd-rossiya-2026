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
        state, routeSpec, THREE, get scene() { return scene; }, get renderer() { return renderer; }, season: () => season(), BRAND, player: () => playerCarGroup, camera: () => camera,
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

    // Surface audit: every junction rendered from straight above with flat
    // class colours (asphalt, pavement, lawn, markings; anything else that
    // lies flat in magenta), before and after driving its task's exit.
    // tools/game_tests/game_surface_audit.py then looks for pavement spikes, slivers of
    // lawn and gaps. Output: build/game_ui/surface-audit/*.png
    const out = process.env.OUT || 'build/game_ui/surface-audit';
    fs.mkdirSync(out, { recursive: true });
    await page.evaluate(() => {
      const t = window.__engineTest, T = t.THREE;
      window.__audit = {
        render(cx, cz, half, px, real = false) {
          const S = t.season(), scene = t.scene, renderer = t.renderer;
          scene.updateMatrixWorld(true);
          const colors = { R: 0x3C3C3C, P: 0xC8B48C, L: 0x78C850, M: 0xFFFFFF, O: 0xFF00FF };
          const mats = {};
          const matFor = (cls, src) => {
            const key = cls + '|' + (src.clippingPlanes || []).map(p => p.normal.toArray().concat(p.constant).join(',')).join(';');
            return mats[key] ||= new T.MeshBasicMaterial({ color: colors[cls], clippingPlanes: src.clippingPlanes || null, side: T.DoubleSide });
          };
          const hidden = [], swapped = [];
          const flat = new T.Box3();
          if (!real) scene.traverse(o => {
            if (!o.visible) return;
            let root = o, skip = false;
            while (root) { if (root.userData.sceneryObject || root.userData.actor || root === t.player()) skip = true; root = root.parent; }
            if (o.isLine || o.isPoints || o.isSprite) { hidden.push(o); o.visible = false; return; }
            if (!o.isMesh) return;
            if (skip) { hidden.push(o); o.visible = false; return; }
            flat.setFromObject(o);
            if (flat.max.y > 0.32 || flat.isEmpty()) { hidden.push(o); o.visible = false; return; }
            const src = Array.isArray(o.material) ? o.material[0] : o.material;
            if (!src || src.map || src.transparent && src.opacity < 0.9) { hidden.push(o); o.visible = false; return; }
            const hex = src.color ? src.color.getHex() : -1;
            const lum = src.color ? (src.color.r * 0.3 + src.color.g * 0.59 + src.color.b * 0.11) : 0;
            let cls = 'O';
            if (o.userData.surface === 'road' || hex === t.BRAND.asphalt) cls = 'R';
            else if (o.userData.surface === 'sidewalk' || hex === S.sidewalk || hex === t.BRAND.sidewalk || hex === t.BRAND.curb) cls = 'P';
            else if (hex === S.ground || (S.verge || []).includes(hex)) cls = 'L';
            else if (lum > 0.8) cls = 'M';
            else if (lum < 0.2) cls = 'R';
            swapped.push([o, o.material]);
            o.material = Array.isArray(o.material) ? o.material.map(m => matFor(cls, m)) : matFor(cls, src);
          });
          const W = Math.round(half * 2 * px);
          const cam = new T.OrthographicCamera(-half, half, half, -half, 0.1, 500);
          cam.position.set(cx, 200, cz); cam.up.set(0, 0, 1); cam.lookAt(cx, 0, cz); cam.updateMatrixWorld(true);
          const size = renderer.getSize(new T.Vector2()), ratio = renderer.getPixelRatio(), bg = scene.background, fog = scene.fog;
          const shadows = renderer.shadowMap.enabled;
          renderer.setPixelRatio(1); renderer.setSize(W, W, false); if (!real) scene.background = new T.Color(0x000000); scene.fog = null;
          renderer.shadowMap.enabled = false;
          renderer.render(scene, cam);
          const url = renderer.domElement.toDataURL('image/png');
          renderer.setPixelRatio(ratio); renderer.setSize(size.x, size.y, false); scene.background = bg; scene.fog = fog;
          renderer.shadowMap.enabled = shadows;
          hidden.forEach(o => { o.visible = true; });
          swapped.forEach(([o, m]) => { o.material = m; });
          return url;
        },
      };
    });
    const ids = await page.evaluate(() => window.__engineTest.allScenarios().map(s => s.id));
    if (process.env.REAL) {
      fs.mkdirSync(path.join(out, 'real'), { recursive: true });
      await page.evaluate(() => { window.__auditReal = true; });
    }
    const only = process.env.ONLY ? process.env.ONLY.split(',') : null;
    let n = 0;
    for (let i = 0; i < ids.length; i++) {
      if (only && !only.includes(ids[i])) continue;
      // The junction as built, then after leaving it by each exit (the
      // world is rebased and the old pieces cut at the seam).
      const exits = process.env.ALL_EXITS ? ['straight', 'left', 'right', 'uturn'] : ['task'];
      for (const exit of exits) {
        const shots = await page.evaluate(([i, exit]) => {
          const t = window.__engineTest, s = t.state, T = t.THREE;
          t.selectAll(i); s.paused = false; t.approach();
          const it = s.activeIntersection;
          const task = t.routeSpec(it.situation).maneuver;
          const way = exit === 'task' ? task : exit;
          if (way !== 'straight' && !it.previews?.[way]) return null;
          if (way === 'straight' && !it.previews?.straight) return null;
          const marker = new T.Object3D(); marker.position.set(0, 0, it.centerZ); it.seg.add(marker);
          const before = exit === 'task' || exit === 'straight' ? window.__audit.render(0, it.centerZ, 50, 8) : null;
          // Drive the exit (simple steering), then look back at the junction
          // in the rebased world.
          window.game.setSimpleSteering(true);
          window.game.proceedAfterAnswer(true, it.situation.id);
          window.game.releaseTraffic(it.situation.id);
          t.tick(0.3);
          if (way === 'uturn') window.game.chooseUturn(); else if (way !== 'straight') window.game.changeLane(way);
          for (let f = 0; f < 60 * 40 && s.resolution; f++) {
            const r = s.resolution; window.game.setGas(!r.recovery && s.speed < 9); t.tick(1 / 60);
          }
          window.game.setGas(false); t.tick(0.5);
          const at = marker.getWorldPosition(new T.Vector3());
          const after = window.__audit.render(at.x, at.z, 50, 8);
          // REAL=1: also the plain picture of the junction after the exit.
          if (window.__auditReal) window.__auditRealShot = window.__audit.render(at.x, at.z, 22, 16, true);
          return { id: it.situation.id, way, done: !s.resolution, before, after };
        }, [i, exit]);
        if (!shots) continue;
        if (shots.before) fs.writeFileSync(path.join(out, shots.id + '_a.png'), Buffer.from(shots.before.split(',')[1], 'base64'));
        fs.writeFileSync(path.join(out, shots.id + '_b_' + shots.way + '.png'), Buffer.from(shots.after.split(',')[1], 'base64'));
        if (process.env.REAL) {
          const real = await page.evaluate(() => window.__auditRealShot);
          if (real) fs.writeFileSync(path.join(out, 'real', shots.id + '_' + shots.way + '.png'), Buffer.from(real.split(',')[1], 'base64'));
        }
      }
      n++;
    }
    console.log('rendered', n, 'junctions to', out);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
