// Production geometry regression: yard fences must leave road/traffic corridors open.
// NODE_PATH=<Playwright modules> GAME_URL=<local repo server> node tools/game_tests/game-fence-clearance-test.cjs
// GAME_SCRIPT selects a saved engine baseline; GAME_CAPTURE writes the real scene preview.
const assert = require('node:assert/strict');
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
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0;
      window.events = [];
      window.FlutterChannel = { postMessage: m => events.push(JSON.parse(m)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch({ maxRetries: 3 });
      const source = process.env.GAME_SCRIPT ? fs.readFileSync(process.env.GAME_SCRIPT, 'utf8') : await response.text();
      const hook = `
        window.fenceTest = {
          state, THREE, createFence, roadSupports, refreshRoadBounds, clearSceneryOffRoad, onPathCorridor,
          fresh() {
            resetGame(); state.roadSegments.slice().forEach(disposeSegment);
            state.roadSegments = []; state.intersections = []; state.actors = [];
            state.occluders = []; state.ambient = []; state.pathCorridors = [];
            state.resolution = null; state.activeIntersection = null; state.exitRoad = currentCorridor = null;
            sceneryJobs.length = 0; streamScenery = false;
            state.paused = false; state.isAtSituation = false; state.attract = false;
            Math.random = () => .35;
          },
          fence(parent, length, x, z, yaw = 0) {
            const fence = createFence(length); fence.userData.sceneryObject = true;
            fence.position.set(x,0,z); fence.rotation.y = yaw; parent.add(fence); return fence;
          },
          fixture(yaw = 0, nested = false, clipped = false) {
            this.fresh();
            const root = new THREE.Group(); root.rotation.y = yaw; scene.add(root); state.roadSegments.push(root);
            roadSurface(root,70,8.4,0,0);
            if (clipped) root.children[0].material.clippingPlanes = [new THREE.Plane(new THREE.Vector3(0,0,-1),0)];
            const roadside = new THREE.Group(); root.add(roadside);
            const parent = nested ? roadside : root;
            const fence = this.fence(parent,14,8,8);
            const yard = this.fence(parent,14,8,24);
            scene.updateMatrixWorld(true);
            refreshRoadBounds();
            const originOnRoad = roadSupports(fence.getWorldPosition(new THREE.Vector3()).setY(0));
            return { originOnRoad, blockedHidden: !fence.visible, yardKept: yard.visible };
          },
          longFence() {
            this.fresh(); const root = new THREE.Group(); scene.add(root); state.roadSegments.push(root);
            roadSurface(root,8.4,70,0,0);
            const fence = this.fence(root,44,20,0,Math.PI/2);
            refreshRoadBounds(); return !fence.visible;
          },
          pathFence() {
            this.fresh(); const root = new THREE.Group(); scene.add(root); state.roadSegments.push(root);
            const fence = this.fence(root,14,8,8), yard = this.fence(root,14,8,24);
            const p = new THREE.Vector3(8,0,1), r = 1.5;
            state.pathCorridors = [{ points: [p], r, box: new THREE.Box3().setFromPoints([p]).expandByScalar(r) }];
            refreshRoadBounds(); return { blockedHidden: !fence.visible, yardKept: yard.visible };
          },
          bend() {
            this.fresh();
            const road = buildStraightSegment(-100,560,true); state.roadSegments.push(road); currentCorridor = state.exitRoad = road;
            nextSegmentZ = 460;
            const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
            const ev = state.roadEvent = buildQuestionEvent(group,-45,window.PDD_ROAD_SITUATIONS.find(s => s.id === 'road_15_3'));
            const z = (ev.curve.from + ev.curve.to)/2, x = ev.curve.centerAt(z);
            // Both ends are grass while the middle crosses the actual bend.
            const fence = this.fence(group,24,x-10,z,Math.PI/2);
            const yard = this.fence(group,8,x+14,z);
            refreshRoadBounds(); return { blockedHidden: !fence.visible, yardKept: yard.visible };
          },
          scene(id = 'ticket_3_13', deferred = false) {
            this.fresh(); state.district = 1; streamScenery = deferred;
            const incoming = buildStraightSegment(-14,140,true,1);
            state.roadSegments.push(incoming); currentCorridor = incoming;
            buildIntersectionSegment(50,SITUATIONS.find(s => s.id === id),incoming);
            while (sceneryJobs.length) processSceneryJobs(1000);
            refreshRoadBounds();
            const fences = [];
            state.roadSegments.forEach(root => root.traverse(o => {
              // The baseline has no footprint marker yet, identify its wood mesh.
              if (o.isGroup && o.children.length === 1 && o.children[0].material?.color?.getHex() === 0x8A7660) fences.push(o);
            }));
            const overlaps = fences.filter(o => {
              if (!o.visible) return false;
              o.children[0].geometry.computeBoundingBox();
              const b = o.children[0].geometry.boundingBox;
              for (let z = b.min.z; z <= b.max.z; z += .1) for (const x of [b.min.x,b.max.x])
                if (roadSupports(new THREE.Vector3(x,0,z).applyMatrix4(o.matrixWorld).setY(0))) return true;
              return false;
            });
            const it = state.intersections[0];
            camera.position.set(30,42,it.centerZ-28); camera.lookAt(0,0,it.centerZ+2);
            renderer.render(scene,camera);
            return { id, deferred, fences: fences.length, preserved: fences.filter(o => o.visible).length,
              blocking: overlaps.length, nestedIncoming: incoming.parent === it.seg };
          },
          retainedSideStreet() {
            this.fresh();
            const incoming=buildStraightSegment(-100,550,true);state.roadSegments.push(incoming);currentCorridor=state.exitRoad=incoming;nextSegmentZ=450;
            const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);
            const ev=state.roadEvent=buildQuestionEvent(g,-45,window.PDD_ROAD_SITUATIONS.find(s=>s.id==='road_27_10'));
            const road=ev.junctionPreviews.left;scene.updateMatrixWorld(true);
            finishRoadEvent(false);state.sideJunction=null;
            playerCarGroup.position.copy(road.localToWorld(new THREE.Vector3(-1.8,0,35)));
            const axis=new THREE.Vector3(0,0,1).transformDirection(road.matrixWorld);
            playerCarGroup.rotation.y=Math.atan2(axis.x,axis.z);
            const recovered=recoverSideRoadContinuation();
            playerCarGroup.position.z=nextSegmentZ-140;checkAndSpawnNext();refreshRoadBounds();
            const pavements=[];scene.traverse(o=>{if(o.userData.surface==='sidewalk')pavements.push(o);});
            const blocked=[];
            for(let z=0;z<130;z+=1){
              const ray=new THREE.Raycaster(new THREE.Vector3(-1.8,10,z),new THREE.Vector3(0,-1,0));
              if(ray.intersectObjects(pavements,false).some(h=>{
                for(let o=h.object;o;o=o.parent)if(!o.visible)return false;
                return !clippedAway(h.object.material,h.point);
              }))blocked.push(z);
            }
            return {recovered,corridor:currentCorridor===road,onRoad:playerOnRoad(),nextJunction:state.intersections.length>0,blocked};
          },
          regulatorSelection() {
            this.fresh();situationBag=[];state.junctionsDrawn=0;state.regulatorAt=4;state.regulatorShown=false;
            const draws=Array.from({length:10},()=>nextSituation());
            return { count:draws.filter(isRegulatorSituation).length, scheduled:isRegulatorSituation(draws[3]),
              reviewed:draws.every(s=>routeSpec(s).reviewed) };
          },
          gasStation() {
            this.fresh();state.labels.gasStation='ГазЛукПук';
            const road=buildStraightSegment(-100,400,true);state.roadSegments.push(road);currentCorridor=state.exitRoad=road;nextSegmentZ=300;
            const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);
            const ev=state.roadEvent=buildGasStationEvent(g,70);scene.updateMatrixWorld(true);
            const surfaces=[];scene.traverse(o=>{if(o.userData.surface)surfaces.push(o);});
            const at=(x,z)=>new THREE.Raycaster(new THREE.Vector3(x,10,z),new THREE.Vector3(0,-1,0)).intersectObjects(surfaces,false).filter(h=>{
              for(let o=h.object;o;o=o.parent)if(!o.visible)return false;
              return (h.object.material.clippingPlanes||[]).every(p=>p.distanceToPoint(h.point)>=-.001);
            }).map(h=>h.object.userData.surface);
            const result={entrances:[59,81].every(z=>at(-5.8,z).includes('road')&&!at(-5.8,z).includes('sidewalk')),
              middle:at(-5.8,70).includes('sidewalk'),forecourt:roadSupports(new THREE.Vector3(-22,0,70)),
              question:!!ev.situation,actors:ev.actors.length};
            camera.position.set(36,44,40);camera.lookAt(-12,0,70);renderer.render(scene,camera);
            return result;
          },
          evidence(id) {
            this.fresh();
            const incoming = buildStraightSegment(-100,150,true);
            state.roadSegments.push(incoming); currentCorridor = incoming;
            buildIntersectionSegment(50,SITUATIONS.find(s => s.id === id),incoming);
            while (sceneryJobs.length) processSceneryJobs(1000);
            refreshRoadBounds(); resolveSceneryOverlaps();
            const it = state.intersections[0]; state.activeIntersection = it;
            state.isAtSituation = true; playerCarGroup.position.set(it.playerStartX ?? -1.8,0,it.stopZ);
            for (let i=0;i<60;i++) updateCamera(1/60);
            const controllers=[]; it.seg.traverse(o=>{if(o.userData.trafficController)controllers.push(o);});
            const shown=o=>{for(let p=o;p;p=p.parent)if(!p.visible)return false;return true;};
            return { id, controllers:controllers.length, visible:controllers.every(shown) };
          },
          reverseCorridor() {
            this.fresh();
            const road = buildStraightSegment(-100,200,true); state.roadSegments.push(road); currentCorridor = state.exitRoad = road;
            playerCarGroup.position.set(-1.8,0,0); playerCarGroup.rotation.y = Math.PI;
            const p = new THREE.Vector3(8,0,1), r=1.5;
            const c = { points: [p], r, box: new THREE.Box3().setFromPoints([p]).expandByScalar(r) };
            state.pathCorridors = [c];
            const reversed = maybeReverseWorld(true);
            const expected = new THREE.Vector3(-8,0,-1);
            return { reversed, moved: c.points[0].distanceTo(expected)<1e-6,
              covered: onPathCorridor(expected), oldCleared: !onPathCorridor(new THREE.Vector3(8,0,1)),
              boxExact: c.box.min.distanceTo(expected.clone().addScalar(-r))<1e-6 && c.box.max.distanceTo(expected.clone().addScalar(r))<1e-6 };
          }
        };
        situationBag = [SITUATIONS.find(s => s.id === 'ticket_3_13')];
      `;
      await route.fulfill({ response, body: source.replace('  // Run init on DOM ready', hook + '\n  // Run init on DOM ready') });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8947') + '/assets/game/');
    await page.waitForFunction(() => window.fenceTest && events.some(e => e.event === 'ready' || e.event === 'engine_error'), null, { polling: 100, timeout: 90000 });
    assert.deepEqual(errors, []);
    const geometry = await page.evaluate(() => ({
      straight: fenceTest.fixture(), diagonal: fenceTest.fixture(Math.PI/3),
      nested: fenceTest.fixture(0,true), clipped: fenceTest.fixture(0,false,true),
      long: fenceTest.longFence(), path: fenceTest.pathFence(), bend: fenceTest.bend(), reverse: fenceTest.reverseCorridor()
    }));
    assert.deepEqual(await page.evaluate(()=>fenceTest.retainedSideStreet()),{recovered:true,corridor:true,onRoad:true,nextJunction:true,blocked:[]});
    assert.deepEqual(await page.evaluate(()=>fenceTest.regulatorSelection()),{count:1,scheduled:true,reviewed:true});
    assert.deepEqual(await page.evaluate(()=>fenceTest.gasStation()),{entrances:true,middle:true,forecourt:true,question:false,actors:0});
    if(process.env.GAS_CAPTURE)await page.screenshot({path:process.env.GAS_CAPTURE});
    const regulators = [];
    for (const id of ['ticket_5_13','ticket_12_13','ticket_23_13','ticket_34_13','ticket_36_13'])
      regulators.push(await page.evaluate(id=>fenceTest.evidence(id),id));
    assert(regulators.every(r=>r.controllers===1 && r.visible),JSON.stringify(regulators));
    const scenes = [];
    for (const [id,deferred] of [['ticket_10_15',true],['ticket_3_13',true],['ticket_3_13',false]])
      scenes.push(await page.evaluate(([id,deferred]) => fenceTest.scene(id,deferred),[id,deferred]));
    if (process.env.GAME_CAPTURE) {
      fs.mkdirSync(path.dirname(process.env.GAME_CAPTURE), { recursive: true });
      await page.screenshot({ path: process.env.GAME_CAPTURE });
    }
    console.log(JSON.stringify({ geometry, scenes },null,2));
    for (const name of ['straight','diagonal','nested'])
      assert.deepEqual(geometry[name], { originOnRoad: false, blockedHidden: true, yardKept: true },name);
    assert.deepEqual(geometry.clipped, { originOnRoad: false, blockedHidden: false, yardKept: true },'clipped road must not remove a yard fence');
    assert.equal(geometry.long,true,'long fences cannot bypass clearance as merged rows');
    assert.deepEqual(geometry.path,{ blockedHidden: true, yardKept: true },'traffic corridor checks use the whole fence footprint');
    assert.deepEqual(geometry.bend,{ blockedHidden: true, yardKept: true },'curved road uses its actual drivable surface');
    assert.deepEqual(geometry.reverse,{ reversed: true, moved: true, covered: true, oldCleared: true, boxExact: true },'U-turn rebases traffic clearance without inflating it');
    for (const scene of scenes) {
      assert(scene.fences > 0 && scene.preserved > 0 && scene.nestedIncoming,JSON.stringify(scene));
      assert.equal(scene.blocking,0,'production scenery cannot fence off an exit: '+JSON.stringify(scene));
    }
    assert.deepEqual(errors,[]);
    console.log('PASS: actual fence footprint, nested and streamed scenery, curved/diagonal roads, traffic corridors and yard fences');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
