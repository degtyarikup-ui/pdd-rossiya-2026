// Road surface textures (pass 2): coverage, phase continuity across seams and
// world rebases, frames of angled roads, theme independence and lifecycle.
// GAME_URL=http://127.0.0.1:8942 node tools/game-road-materials-test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');
// Same texel: texture coordinates equal up to whole tiles (frames wrap at 44.8 m).
const sameTexel = (a, b, eps = 1e-4) => [0, 1].every(i => { const d = Math.abs(a[i] - b[i]) % 1; return Math.min(d, 1 - d) < eps; });

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  const result = {};
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } }), errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; window.events = []; window.FlutterChannel = { postMessage: m => events.push(JSON.parse(m)) }; });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('  // Run init on DOM ready', `
    window.roadTest = {
      clear() {
        resetGame(); state.attract = false; state.paused = true;
        state.roadSegments = []; state.actors = []; state.intersections = []; state.ambient = []; state.activeIntersection = null;
        state.occluders = []; state.roadEvent = null; state.exitRoad = currentCorridor = null; nextSegmentZ = 0;
      },
      seed() { let s = 7; Math.random = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); },
      junction(id) {
        this.clear(); this.seed(); situationBag = [SITUATIONS.find(s => s.id === id)]; buildInitialTrack(); this.render();
        return state.intersections[0];
      },
      road(id) {
        this.clear(); this.seed();
        const seg = buildStraightSegment(-45, 200, true); state.roadSegments.push(seg); state.exitRoad = currentCorridor = seg; nextSegmentZ = 155;
        const g = new THREE.Group(); scene.add(g); state.roadSegments.push(g); state.roadTurn = 1;
        const ev = state.roadEvent = buildQuestionEvent(g, -45, window.PDD_ROAD_SITUATIONS.find(s => s.id === id));
        playerCarGroup.position.set(-1.8, 0, ev.stopZ); this.render(); return ev;
      },
      render() { renderer.render(scene, camera); return renderer.domElement.toDataURL(); },
      // Every mesh that should be a textured road surface, and whether it is.
      audit() {
        const out = { skinned: {}, missing: [], badMaterial: 0 };
        state.roadSegments.forEach(root => root.traverse(o => {
          if (!o.isMesh || !o.visible) return;
          let p = o, skip = false; while (p) { if (p.userData.actor || p.userData.sceneryObject) skip = true; p = p.parent; }
          if (skip) return;
          const kind = window.PDD_ROADS.kindOf(o);
          const m = o.material, hex = m?.color?.getHex?.();
          const looksRoad = o.userData.surface === 'road' || o.userData.surface === 'sidewalk' || [0x2C2F36, 0x747970, 0x7A776F, 0xB9C0C6].includes(hex);
          if (!kind) { if (looksRoad && m?.isMeshLambertMaterial && !m.map) out.missing.push(o.userData.surface || hex); return; }
          if (!o.userData.pddSkinned || !o.geometry.attributes.uv || !o.geometry.attributes.pddSide) out.missing.push(kind);
          else out.skinned[kind] = (out.skinned[kind] || 0) + 1;
          if (m.userData.pddKind !== kind || !m.map?.userData.pddRoadShared || !String(m.onBeforeCompile).includes('pddMacro')) out.badMaterial++;
        }));
        return out;
      },
      // Texture coordinates of every surface of a kind straight above/below a world point.
      uvsAt(x, z, kind) {
        scene.updateMatrixWorld(true);
        const ray = new THREE.Raycaster(new THREE.Vector3(x, 5, z), new THREE.Vector3(0, -1, 0));
        const meshes = []; state.roadSegments.forEach(r => r.traverse(o => { if (o.isMesh && o.visible && o.userData.pddSkinned === kind) meshes.push(o); }));
        return ray.intersectObjects(meshes, false).filter(h => Math.abs(h.face.normal.clone().transformDirection(h.object.matrixWorld).y) > 0.6)
          .filter(h => !(h.object.material.clippingPlanes || []).some(p => p.distanceToPoint(h.point) < 0))
          .map(h => [h.uv.x, h.uv.y, h.object.uuid]);
      },
      // Apply a rigid world rebase exactly like the game does (world + camera).
      rebase(yaw, tx, tz) {
        const t = new THREE.Matrix4().makeRotationY(yaw).premultiply(new THREE.Matrix4().makeTranslation(tx, 0, tz));
        state.roadSegments.forEach(seg => seg.applyMatrix4(t)); window.PDD_ROADS.rebase(t);
        const planes = new Set(); state.roadSegments.forEach(seg => seg.traverse(o => (o.material?.clippingPlanes || []).forEach(p => planes.add(p))));
        planes.forEach(p => p.applyMatrix4(t));
        camera.position.applyMatrix4(t); camera.quaternion.premultiply(new THREE.Quaternion().setFromRotationMatrix(t)); camera.updateMatrixWorld(true);
        playerCarGroup.applyMatrix4(t);
        return t;
      },
      // Run test code inside the engine closure.
      run(fn, args) { return eval('(' + fn + ')')(...args); },
    }; // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8938') + '/assets/game/');
    await page.waitForFunction(() => window.roadTest && window.PDD_ROADS && events.some(e => e.event === 'ready'), null, { polling: 100 });

    const inGame = (fn, ...args) => page.evaluate(([f, a]) => roadTest.run(f, a), [fn.toString(), args]);
    // 1. Coverage in every road family.
    const scenes = { junction: ['ticket_1_13', 'ticket_20_14', 'ticket_15_15', 'ticket_16_14', 'ticket_22_13', 'ticket_27_9', 'ticket_21_15', 'ticket_21_8', 'ticket_28_2', 'ticket_18_14'],
      road: ['road_15_3', 'road_2_16', 'road_20_16', 'road_24_16', 'road_6_10', 'road_29_3', 'road_2_11', 'road_9_9', 'road_26_9', 'road_31_4'] };
    result.coverage = {};
    for (const [type, ids] of Object.entries(scenes)) for (const id of ids) {
      const a = await page.evaluate(([type, id]) => { type === 'junction' ? roadTest.junction(id) : roadTest.road(id); return roadTest.audit(); }, [type, id]);
      assert.deepEqual(a.missing, [], id + ': untextured road surfaces');
      assert.equal(a.badMaterial, 0, id + ': road material without the shared patch');
      assert.ok(a.skinned.asphalt > 0, id + ': no asphalt');
      result.coverage[id] = a.skinned;
    }
    assert.ok(result.coverage.road_2_16.ballast && result.coverage.road_2_16.deck && result.coverage.road_2_16.sleeper, 'railway surfaces');
    assert.ok(result.coverage.road_15_3.gravel, 'gravel shoulders of the bend');

    // 2. Seams: every overlapping surface of a kind has the same texel at the same point.
    const seams = await page.evaluate(() => {
      const it = roadTest.junction('ticket_1_13'), out = [];
      const z0 = it.startZ, samples = [];
      for (const dz of [-0.06, -0.02, 0.03, 0.08]) for (const x of [-3.1, -1.8, 0.4, 2.7]) samples.push(['asphalt', x, z0 + dz]);
      for (const dz of [-0.06, 0.05]) for (const x of [-6.9, -5.1, 5.3, 7.1]) samples.push(['pavement', x, z0 + dz]);
      // The far end of the junction, into its straight preview.
      const z1 = it.startZ + 52;
      for (const dz of [-0.05, 0.05]) for (const x of [-2, 2]) samples.push(['asphalt', x, z1 + dz]);
      for (const dz of [-0.05, 0.05]) for (const x of [-6, 6]) samples.push(['pavement', x, z1 + dz]);
      // Junction corner: cross street pavement and its preview.
      for (const dx of [-0.05, 0.05]) samples.push(['pavement', 35 + dx, it.centerZ - 6], ['asphalt', 35 + dx, it.centerZ + 1.3]);
      for (const [kind, x, z] of samples) out.push({ kind, x, z, uvs: roadTest.uvsAt(x, z, kind) });
      return out;
    });
    let overlaps = 0;
    for (const s of seams) {
      assert.ok(s.uvs.length >= 1, `no ${s.kind} at ${s.x},${s.z}`);
      for (const uv of s.uvs.slice(1)) {
        overlaps++;
        assert.ok(sameTexel(uv, s.uvs[0]), `${s.kind} phase jump at ${s.x},${s.z}: ${JSON.stringify(s.uvs)}`);
      }
    }
    assert.ok(overlaps >= 10, 'seam samples must hit overlapping pieces, got ' + overlaps);
    // Neighbouring points across a seam differ by exactly their distance.
    const step = await page.evaluate(() => {
      const it = roadTest.junction('ticket_1_13'), z = it.startZ, k = window.PDD_ROADS.kinds.asphalt.period;
      const a = roadTest.uvsAt(-1.8, z - 0.5, 'asphalt')[0], b = roadTest.uvsAt(-1.8, z + 0.5, 'asphalt')[0];
      return Math.hypot((a[0] - b[0]) * k, (a[1] - b[1]) * k);
    });
    assert.ok(Math.abs(step - 1) < 1e-3, 'scale across the straight/junction seam: ' + step);
    result.seams = { samples: seams.length, overlaps, scaleAcrossSeam: step };

    // 3. Rebase: the pattern stays on the ground and new road continues it.
    result.rebase = [];
    for (const [yaw, tx, tz] of [[Math.PI, 0, 180], [Math.PI / 2, 40, -30], [0.52, -17, 63], [-1.31, 5, 210]]) {
      const r = await page.evaluate(([fn, args]) => roadTest.run(fn, args), [(([yaw, tx, tz]) => {
        roadTest.clear(); roadTest.seed();
        const seg = buildStraightSegment(-60, 120, true); state.roadSegments.push(seg); state.exitRoad = currentCorridor = seg;
        roadTest.render();
        const probes = [[-1.8, 10], [2.2, 37.5], [-5.6, 20], [6.3, 44]];
        const kindAt = x => Math.abs(x) > 4.3 ? 'pavement' : 'asphalt';
        const before = probes.map(([x, z]) => [roadTest.uvsAt(x, z, kindAt(x))[0]]);
        const t = roadTest.rebase(yaw, tx, tz);
        const after = probes.map(([x, z]) => { const p = new THREE.Vector3(x, 0, z).applyMatrix4(t); return [roadTest.uvsAt(p.x, p.z, kindAt(x))[0]]; });
        // Next stretch: built in the new coordinates where the road ends.
        const end = new THREE.Vector3(0, 0, 60).applyMatrix4(t), dir = new THREE.Vector3(0, 0, 1).transformDirection(t);
        const next = buildStraightSegment(0, 80, true); next.rotation.y = Math.atan2(dir.x, dir.z); next.position.copy(end); state.roadSegments.push(next);
        roadTest.render();
        const seam = [];
        for (const [x, d] of [[-1.8, -0.06], [-1.8, 0.06], [2.5, 0.05], [-6, 0.05], [5.5, -0.05]]) {
          const side = new THREE.Vector3(-dir.z, 0, dir.x), p = end.clone().addScaledVector(dir, d).addScaledVector(side, -x);
          seam.push({ kind: Math.abs(x) > 4.3 ? 'pavement' : 'asphalt', uvs: roadTest.uvsAt(p.x, p.z, Math.abs(x) > 4.3 ? 'pavement' : 'asphalt') });
        }
        return { before, after, seam, frames: window.PDD_ROADS.frameCount() };
      }).toString(), [[yaw, tx, tz]]]);
      r.before.forEach((pair, i) => pair.forEach((uv, k) => {
        assert.ok(uv && r.after[i][k], 'probe lost after rebase');
        assert.ok(sameTexel(uv, r.after[i][k], 1e-5), 'texture moved by rebase ' + yaw);
      }));
      for (const s of r.seam) {
        assert.equal(s.uvs.length, 2, 'seam overlap after rebase ' + yaw + ' ' + JSON.stringify(s));
        // Same road frame (the continuation was adopted from the road): identical texels.
        assert.ok(sameTexel(s.uvs[0], s.uvs[1]), 'phase jump after rebase ' + yaw + ' ' + JSON.stringify(s.uvs));
      }
      result.rebase.push({ yaw: +yaw.toFixed(3), frames: r.frames });
    }

    // 4. A pure rebase leaves the rendered frame unchanged (no swimming).
    const still = await inGame(() => {
      const it = roadTest.junction('ticket_1_13');
      playerCarGroup.position.set(-1.8, 0, it.stopZ); for (let i = 0; i < 200; i++) updateCamera(1 / 60);
      // Only the textured surfaces, without shadows: the check is about texels.
      const roots = new Set(state.roadSegments), hidden = [];
      scene.children.forEach(o => { if (!roots.has(o) && o.visible && !o.isLight) { o.visible = false; hidden.push(o); } });
      state.roadSegments.forEach(r => r.traverse(o => { if (o.isMesh && o.visible && !o.userData.pddSkinned) { o.visible = false; hidden.push(o); } }));
      renderer.shadowMap.enabled = false;
      const a = roadTest.render();
      roadTest.rebase(Math.PI, 0, 2 * playerCarGroup.position.z);
      const b = roadTest.render();
      hidden.forEach(o => { o.visible = true; }); renderer.shadowMap.enabled = true;
      return { a, b };
    });
    const diff = await page.evaluate(async ({ a, b }) => {
      const load = src => new Promise(r => { const i = new Image(); i.onload = () => r(i); i.src = src; });
      const [ia, ib] = await Promise.all([load(a), load(b)]), c = document.createElement('canvas');
      c.width = ia.width; c.height = ia.height; const g = c.getContext('2d');
      g.drawImage(ia, 0, 0); const da = g.getImageData(0, 0, c.width, c.height).data;
      g.drawImage(ib, 0, 0); const db = g.getImageData(0, 0, c.width, c.height).data;
      let changed = 0; for (let i = 0; i < da.length; i += 4) if (Math.abs(da[i] - db[i]) + Math.abs(da[i + 1] - db[i + 1]) + Math.abs(da[i + 2] - db[i + 2]) > 24) changed++;
      return changed / (da.length / 4);
    }, still);
    assert.ok(diff < 0.002, 'frame changed after a rebase: ' + diff);
    result.rebaseFrameChange = diff;

    // 5. An angled exit gets its own frame along its axis; square ones keep the road's.
    const angled = await inGame(() => {
      const it = roadTest.junction('ticket_15_15'), out = [];
      for (const [dir, road] of Object.entries(it.previews)) {
        road.updateWorldMatrix(true, false);
        const f = window.PDD_ROADS.frame(road.userData.pddFrameId), m = road.matrixWorld.elements;
        const ux = f.a * m[0] + f.b * m[2], uz = f.c * m[0] + f.d * m[2];
        out.push({ dir, angle: Math.atan2(uz, ux), own: road.userData.pddFrameId !== it.seg.userData.pddFrameId });
      }
      return out;
    });
    for (const a of angled) assert.ok(Math.abs(Math.sin(2 * a.angle)) < 1e-3, 'paving not along the road ' + JSON.stringify(a));
    assert.ok(angled.some(a => a.own), 'skew junction: an angled arm with its own frame');
    result.angled = angled;

    // 6. Theme never changes the world; seasons and rain keep the textures.
    const themes = await inGame(() => {
      const out = [];
      for (const s of ['summer', 'autumn', 'winter']) {
        window.game.setSeason(s); roadTest.junction('ticket_1_13');
        for (const rain of [0, 1]) {
          state.rain = rain; state.overcast = rain; ensureWeatherFx(); applyWeather();
          window.game.setTheme(false); const a = roadTest.render();
          window.game.setTheme(true); const b = roadTest.render();
          out.push(a === b);
        }
      }
      state.rain = 0; state.overcast = 0; applyWeather(); window.game.setTheme(false); window.game.setSeason('summer');
      return out;
    });
    assert.ok(themes.every(Boolean), 'theme changes the world');
    result.themePairs = themes.length;

    // 7. Lifecycle: shared maps survive disposal, GPU textures and frames stay bounded.
    const life = await inGame(() => {
      const shared = window.PDD_ROADS.sharedTextures(); let disposed = 0;
      shared.forEach(t => t.addEventListener('dispose', () => disposed++));
      const counts = [], frames = [];
      const ids = ['ticket_1_13', 'ticket_15_15', 'ticket_16_14', 'ticket_21_15', 'ticket_27_9'];
      for (let i = 0; i < 40; i++) {
        if (i % 2) roadTest.road(['road_2_16', 'road_29_3', 'road_15_3'][i % 3]); else roadTest.junction(ids[i % ids.length]);
        counts.push(renderer.info.memory.textures); frames.push(window.PDD_ROADS.frameCount());
      }
      roadTest.clear(); roadTest.render();
      return { disposed, counts, frames, shared: window.PDD_ROADS.sharedTextures().length, after: renderer.info.memory.textures,
        bytes: window.PDD_ROADS.sharedTextures().reduce((s, t) => s + t.image.width * t.image.height * 4 * 4 / 3, 0) };
    });
    assert.equal(life.disposed, 0, 'a shared road map was disposed with a segment');
    assert.ok(life.shared <= 6, 'road maps: ' + life.shared);
    const firstHalf = Math.max(...life.counts.slice(10, 20)), secondHalf = Math.max(...life.counts.slice(30));
    assert.ok(secondHalf <= firstHalf + 2, 'GPU textures grow: ' + life.counts.join(','));
    assert.ok(Math.max(...life.frames) <= 6, 'road frames grow: ' + life.frames.join(','));
    result.lifecycle = { shared: life.shared, sharedMiB: +(life.bytes / 1048576).toFixed(3), gpuTextures: life.counts, maxFrames: Math.max(...life.frames) };

    assert.deepEqual(errors, []);
    fs.mkdirSync('output/game-textures/roads', { recursive: true });
    fs.writeFileSync('output/game-textures/roads/validation.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify({ scenes: Object.keys(result.coverage).length, overlaps, rebases: result.rebase.length, frameChange: diff, themePairs: themes.length, lifecycle: { shared: life.shared, maxFrames: result.lifecycle.maxFrames } }));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
