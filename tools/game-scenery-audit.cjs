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

    // Scenery audit: every 3D object of a junction scene (houses, trees,
    // lamps, benches, fences, kiosks, sign and signal poles…) is checked for
    // standing on the carriageway, for a house over the pavement, and for
    // objects grown into one another. Cars, people and the props of road
    // works (cones, barriers) are where they are on purpose and are skipped.
    const report = await page.evaluate(({ ids }) => {
      const t = window.__engineTest, s = t.state, T = t.THREE, out = [];
      const scanScene = label => {
        t.scene.updateMatrixWorld(true);
        t.refreshRoadBounds();
        const props = new Set((s.props || []).map(p => p.mesh));
        const skip = o => { for (let r = o; r; r = r.parent) if (r.userData.actor || r === t.player() || props.has(r) || r.userData.guideArrow || r.userData.badge) return true; return false; };
        const objects = [];
        s.roadSegments.forEach(seg => {
          if (!seg.visible) return;
          const visit = (o, depth) => {
            if (!o.visible || skip(o)) return;
            const box = new T.Box3().setFromObject(o);
            if (box.isEmpty()) return;
            // Containers (whole road pieces nested in a junction: its exit
            // roads, road-event groups, strips) are opened up.
            if (!o.isMesh && (box.max.x - box.min.x > 40 || box.max.z - box.min.z > 40)) { o.children.forEach(c => visit(c, depth + 1)); return; }
            // A 3D object: a child of a road piece that rises above the ground.
            if (box.max.y > 0.3 && (depth > 0 || o.isMesh)) {
              // Its footprint on the ground: the parts that touch it.
              const base = new T.Box3();
              o.traverse(m => { if (m.isMesh && m.visible) { const b = new T.Box3().setFromObject(m); if (!b.isEmpty() && b.min.y < 0.35) base.union(b); } });
              if (!base.isEmpty()) objects.push({ o, box, base, tall: box.max.y - box.min.y, sign: !!o.children.find(c => c.userData?.signBack) || o.userData.signCode,
                occ: s.occluders.includes(o), scen: !!o.userData.sceneryObject, depth });
              return;
            }
            if (o.children.length && (o.userData.roadEvent || o.userData.questionTopology || depth === 0)) o.children.forEach(c => visit(c, depth + 1));
          };
          seg.children.forEach(c => visit(c, 1));
        });
        const sidewalks = [];
        s.roadSegments.forEach(seg => seg.traverse(o => { if (o.isMesh && o.userData.surface === 'sidewalk') sidewalks.push(o); }));
        const ray = new T.Raycaster();
        const onSidewalk = (x, z) => { ray.set(new T.Vector3(x, 5, z), new T.Vector3(0, -1, 0)); return ray.intersectObjects(sidewalks, false).some(h => { const m = Array.isArray(h.object.material) ? h.object.material[0] : h.object.material; return (m.clippingPlanes || []).every(p => p.distanceToPoint(h.point) >= -0.001); }); };
        for (const ob of objects) {
          const b = ob.base, cx = (b.min.x + b.max.x) / 2, cz = (b.min.z + b.max.z) / 2;
          // On the carriageway: the middle of the footprint, and for bigger
          // things a grid over it, on drivable asphalt.
          const pts = [[cx, cz]];
          const w = b.max.x - b.min.x, d = b.max.z - b.min.z;
          if (w > 1 || d > 1) for (let u = 0.2; u <= 0.8; u += 0.3) for (let v = 0.2; v <= 0.8; v += 0.3) pts.push([b.min.x + u * w, b.min.z + v * d]);
          const onRoad = pts.filter(([x, z]) => t.roadSupports(new T.Vector3(x, 0, z)));
          if (onRoad.length) out.push({ label, kind: 'on road', what: ob.o.type + '/' + (ob.o.name || '') + (ob.sign ? ' sign ' + ob.sign : ''), at: [+cx.toFixed(1), +cz.toFixed(1)], size: [+w.toFixed(1), +d.toFixed(1), +ob.tall.toFixed(1)] });
          // A house (tall and big) over the pavement.
          if (ob.tall > 3 && w * d > 6) {
            const hits = pts.filter(([x, z]) => onSidewalk(x, z));
            if (hits.length) out.push({ label, kind: 'house on pavement', at: [+cx.toFixed(1), +cz.toFixed(1)], size: [+w.toFixed(1), +d.toFixed(1), +ob.tall.toFixed(1)] });
          }
        }
        // Grown into one another: a tree, a lamp or a sign pole standing
        // inside a house. (Pieces of one street-furniture set — a planter and
        // its bush — share a spot on purpose; merged blocks are left out.)
        // Houses: the street's buildings, and the baked far background (its
        // walls); trees (a crown on a trunk) are not houses.
        const treeColours = new Set(['467e3c', '3e7c42', 'e0b33c', 'd98a2b', 'c7a24a', 'b86a2a', 'c94f2b', 'b5675a', '5d4037']);
        const houses = objects.filter(o => {
          const area = (o.base.max.x - o.base.min.x) * (o.base.max.z - o.base.min.z);
          if (!(o.tall > 3 && area > 6 && area < 400)) return false;
          if (o.occ) return true;
          if (o.o.isMesh) { const m = Array.isArray(o.o.material) ? o.o.material[0] : o.o.material; return !treeColours.has(m?.color?.getHexString()); }
          return false;
        });
        // Houses grown into one another.
        for (let i = 0; i < houses.length; i++) for (let j = i + 1; j < houses.length; j++) {
          const a = houses[i].base, c = houses[j].base;
          const ox = Math.min(a.max.x, c.max.x) - Math.max(a.min.x, c.min.x), oz = Math.min(a.max.z, c.max.z) - Math.max(a.min.z, c.min.z);
          if (ox > 0.3 && oz > 0.3) out.push({ label, kind: 'house in house', a: [+((a.min.x + a.max.x) / 2).toFixed(1), +((a.min.z + a.max.z) / 2).toFixed(1), houses[i].occ ? 'occ' : houses[i].scen ? 'scen' : 'other', houses[i].o.type, houses[i].depth],
            b: [+((c.min.x + c.max.x) / 2).toFixed(1), +((c.min.z + c.max.z) / 2).toFixed(1), houses[j].occ ? 'occ' : houses[j].scen ? 'scen' : 'other', houses[j].o.type, houses[j].depth], area: +(ox * oz).toFixed(1) });
        }
        for (const small of objects) {
          const w = small.base.max.x - small.base.min.x, d = small.base.max.z - small.base.min.z;
          if (w * d > 6) continue;
          const cx = (small.base.min.x + small.base.max.x) / 2, cz = (small.base.min.z + small.base.max.z) / 2;
          for (const h of houses) {
            if (h === small) continue;
            if (cx > h.base.min.x + 0.3 && cx < h.base.max.x - 0.3 && cz > h.base.min.z + 0.3 && cz < h.base.max.z - 0.3) {
              out.push({ label, kind: 'inside a house', at: [+cx.toFixed(1), +cz.toFixed(1), +small.tall.toFixed(1)],
                house: [+((h.base.min.x + h.base.max.x) / 2).toFixed(1), +((h.base.min.z + h.base.max.z) / 2).toFixed(1), +h.tall.toFixed(1)] });
            }
          }
        }
        return objects.length;
      };
      let counted = 0;
      for (const id of ids) {
        const i = t.allScenarios().findIndex(sc => sc.id === id);
        if (i < 0) continue;
        t.selectAll(i); s.paused = true; t.approach();
        counted += scanScene(id);
      }
      return { out, counted };
    }, { ids: (process.env.IDS || '').split(',').filter(Boolean) });
    const byKind = {};
    report.out.forEach(r => { (byKind[r.kind] ||= []).push(r); });
    console.log('objects checked:', report.counted);
    for (const [k, v] of Object.entries(byKind)) {
      console.log(k + ':', v.length);
      v.slice(0, 25).forEach(r => console.log('  ', JSON.stringify(r)));
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
