// Surface audit of the road stretches between junctions: every road
// question and every random road event (bus stop, zebra, road works,
// broken-down car, courtyard exit, cyclist, emergency vehicle) is built on a
// fresh straight road and rendered from above in flat class colours, like
// tools/game_tests/game-surface-audit.cjs does for junctions. Analyse the result with
// tools/game_tests/game_surface_audit.py build/game_ui/road-surface-audit
// Run with NODE_PATH pointing at Playwright and a local server on :8938.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; window.FlutterChannel = { postMessage() {} }; });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
        window.roadAudit = {
          fresh() {
            resetGame(); state.attract = false;
            state.roadSegments.forEach(disposeSegment);
            state.roadSegments = []; state.actors = []; state.intersections = [];
            state.activeIntersection = null; state.occluders = []; state.ambient = [];
            state.exitRoad = currentCorridor = null;
            const road = buildStraightSegment(-45, 200, true); state.roadSegments.push(road);
            state.exitRoad = currentCorridor = road; nextSegmentZ = 155;
            const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
            return group;
          },
          questions: () => window.PDD_ROAD_SITUATIONS.filter(s => s.enabled !== false).map(s => s.id),
          question(id) {
            const group = this.fresh();
            state.roadEvent = buildQuestionEvent(group, -45, window.PDD_ROAD_SITUATIONS.find(s => s.id === id));
          },
          event(kind) {
            const group = this.fresh();
            const build = { busstop: buildBusStopEvent, crosswalk: buildCrosswalkEvent, roadworks: buildRoadworksEvent,
              obstacle: buildObstacleEvent, courtyard: buildCourtyardEvent, cyclist: buildCyclistEvent,
              emergency: buildEmergencyEvent }[kind];
            state.roadEvent = build(group, 40);
            refreshRoadBounds();
          },
          // Z-fighting: two differently coloured ground layers within 4 mm.
          zfight(cx, cz, hx, hz, step = 0.5) {
            scene.updateMatrixWorld(true);
            const meshes = [], flat = new THREE.Box3(), found = {};
            scene.traverse(o => {
              if (!o.isMesh || !o.material) return;
              let root = o, skip = false, visible = true;
              while (root) { if (root.userData.sceneryObject || root.userData.actor || root === playerCarGroup) skip = true; if (!root.visible) visible = false; root = root.parent; }
              if (skip || !visible) return;
              flat.setFromObject(o);
              if (flat.isEmpty() || flat.max.y > 0.35 || flat.max.x < cx - hx || flat.min.x > cx + hx || flat.max.z < cz - hz || flat.min.z > cz + hz) return;
              const m = Array.isArray(o.material) ? o.material[0] : o.material;
              if (!m.color || m.transparent && m.opacity < 0.95) return;
              meshes.push(o);
            });
            const ray = new THREE.Raycaster(); ray.far = 10;
            const down = new THREE.Vector3(0, -1, 0);
            const colorOf = hit => { const m = Array.isArray(hit.object.material) ? hit.object.material[hit.face?.materialIndex || 0] : hit.object.material; return m.color.getHex(); };
            for (let x = cx - hx; x <= cx + hx; x += step) for (let z = cz - hz; z <= cz + hz; z += step) {
              ray.set(new THREE.Vector3(x, 5, z), down);
              const h = ray.intersectObjects(meshes, false).filter(hit => {
                const m = Array.isArray(hit.object.material) ? hit.object.material[hit.face?.materialIndex || 0] : hit.object.material;
                return (m.clippingPlanes || []).every(p => p.distanceToPoint(hit.point) >= -0.001);
              });
              if (h.length < 2) continue;
              const a = h[0], b = h.find(k => colorOf(k) !== colorOf(a));
              if (b && Math.abs(a.point.y - b.point.y) < 0.004) {
                const key = colorOf(a).toString(16) + '/' + colorOf(b).toString(16) + ' @' + a.point.y.toFixed(3) + '/' + b.point.y.toFixed(3);
                (found[key] ||= []).push([+x.toFixed(1), +z.toFixed(1)]);
              }
            }
            return Object.fromEntries(Object.entries(found).map(([k, v]) => [k, { n: v.length, sample: v.slice(0, 3) }]));
          },
          render(cx, cz, hx, hz, px, real = false) {
            const S = season();
            scene.updateMatrixWorld(true);
            const colors = { R: 0x3C3C3C, P: 0xC8B48C, L: 0x78C850, M: 0xFFFFFF, O: 0xFF00FF };
            const mats = {};
            const matFor = (cls, src) => {
              const key = cls + '|' + (src.clippingPlanes || []).map(p => p.normal.toArray().concat(p.constant).join(',')).join(';');
              return mats[key] ||= new THREE.MeshBasicMaterial({ color: colors[cls], clippingPlanes: src.clippingPlanes || null, side: THREE.DoubleSide });
            };
            const hidden = [], swapped = [], flat = new THREE.Box3();
            if (!real) scene.traverse(o => {
              if (!o.visible) return;
              let root = o, skip = false;
              while (root) { if (root.userData.sceneryObject || root.userData.actor || root === playerCarGroup) skip = true; root = root.parent; }
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
              if (o.userData.surface === 'road' || hex === BRAND.asphalt) cls = 'R';
              else if (o.userData.surface === 'sidewalk' || hex === S.sidewalk || hex === BRAND.sidewalk || hex === BRAND.curb) cls = 'P';
              else if (hex === S.ground || (S.verge || []).includes(hex)) cls = 'L';
              else if (lum > 0.8) cls = 'M';
              else if (lum < 0.2) cls = 'R';
              swapped.push([o, o.material]);
              o.material = Array.isArray(o.material) ? o.material.map(m => matFor(cls, m)) : matFor(cls, src);
            });
            const W = Math.round(hx * 2 * px), H = Math.round(hz * 2 * px);
            const cam = new THREE.OrthographicCamera(-hx, hx, hz, -hz, 0.1, 500);
            cam.position.set(cx, 200, cz); cam.up.set(0, 0, 1); cam.lookAt(cx, 0, cz); cam.updateMatrixWorld(true);
            const size = renderer.getSize(new THREE.Vector2()), ratio = renderer.getPixelRatio(), bg = scene.background, fog = scene.fog;
            renderer.setPixelRatio(1); renderer.setSize(W, H, false); if (!real) scene.background = new THREE.Color(0x000000); scene.fog = null;
            const shadows = renderer.shadowMap.enabled; renderer.shadowMap.enabled = false;
            renderer.render(scene, cam);
            const url = renderer.domElement.toDataURL('image/png');
            renderer.setPixelRatio(ratio); renderer.setSize(size.x, size.y, false); scene.background = bg; scene.fog = fog;
            renderer.shadowMap.enabled = shadows;
            hidden.forEach(o => { o.visible = true; });
            swapped.forEach(([o, m]) => { o.material = m; });
            return url;
          },
        };
        // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.roadAudit);
    const out = process.env.OUT || 'build/game_ui/road-surface-audit';
    fs.mkdirSync(out, { recursive: true });
    const save = (name, url) => fs.writeFileSync(path.join(out, name + '.png'), Buffer.from(url.split(',')[1], 'base64'));
    const only = process.env.ONLY ? process.env.ONLY.split(',') : null;
    const questions = await page.evaluate(() => window.roadAudit.questions());
    for (const id of questions) {
      if (only && !only.includes(id)) continue;
      save(id, await page.evaluate(id => { window.roadAudit.question(id); return window.roadAudit.render(0, 55, 40, 100, 8); }, id));
    }
    for (const kind of ['busstop', 'crosswalk', 'roadworks', 'obstacle', 'courtyard', 'cyclist', 'emergency']) {
      if (only && !only.includes(kind)) continue;
      save('event_' + kind, await page.evaluate(kind => { window.roadAudit.event(kind); return window.roadAudit.render(0, 40, 40, 60, 8); }, kind));
    }
    if (process.env.ZFIGHT) {
      const all = {};
      for (const id of questions) {
        const r = await page.evaluate(id => { window.roadAudit.question(id); return window.roadAudit.zfight(0, 55, 30, 100); }, id);
        if (Object.keys(r).length) all[id] = r;
      }
      for (const kind of ['busstop', 'crosswalk', 'roadworks', 'obstacle', 'courtyard', 'cyclist', 'emergency']) {
        const r = await page.evaluate(kind => { window.roadAudit.event(kind); return window.roadAudit.zfight(0, 40, 30, 60); }, kind);
        if (Object.keys(r).length) all[kind] = r;
      }
      console.log('zfight', JSON.stringify(all, null, 1));
    }
    // Plain renders (as the player sees the ground) for a look by eye.
    if (process.env.REAL) {
      for (const kind of process.env.REAL.split(',')) {
        save('real_' + kind, await page.evaluate(kind => { window.roadAudit.event(kind); return window.roadAudit.render(0, 40, 20, 30, 16, true); }, kind));
      }
    }
    if (errors.length) console.log('page errors:', errors.slice(0, 5));
    console.log('rendered road stretches to', out);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
