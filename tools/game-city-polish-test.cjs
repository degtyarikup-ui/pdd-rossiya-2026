// Real browser regression: city props, physical controller, question evidence,
// off-screen traffic retirement and 2–5-junction street-width runs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require('playwright');
(async () => {
 const browser = await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 try {
  const page = await browser.newPage({viewport:{width:390,height:844}}), errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.requestAnimationFrame=()=>0;window.cityEvents=[];window.FlutterChannel={postMessage:m=>cityEvents.push(JSON.parse(m))};});
  await page.goto((process.env.GAME_LAB_URL || 'http://127.0.0.1:8952')+'/game/index.html');
  await page.waitForFunction(()=>window.__lab?.run('!!playerCarGroup'));
  const checks = await page.evaluate(()=>__lab.run(`(()=>{
    const result={};
    __lab.show('road_20_16');result.rail={train:!!state.roadEvent.rail.train,open:state.roadEvent.rail.open,stop:state.roadEvent.scene.railway.requireStop};
    __lab.show('ticket_34_13');const it=state.intersections[0],tram=ensureTraffic(it).find(a=>a.config.type==='tram');
    state.viewportInsets={top:160,bottom:300};for(let i=0;i<120;i++){updateActors(1/60);updateCamera(1/60);}
    const box=new THREE.Box3().setFromObject(tram.mesh),center=box.getCenter(new THREE.Vector3()).project(camera);
    result.tram={visible:tram.mesh.visible,done:tram.done,screenY:(1-center.y)*innerHeight/2,pos:tram.mesh.position.toArray()};
    const officer=state.actors.find(a=>a.config.physicalOnly);state.speed=5;handleCollision(officer,'city-test-officer');updateActorFall(officer,.7);
    result.officer={inMotions:it.motions.includes(officer),fallen:!!officer.fall,bodyY:new THREE.Box3().setFromObject(officer.mesh.userData.body).min.y};
    const original=tram.mesh.position.clone();it.seg.userData.questionComplete=true;state.intersections=[];tram.mesh.position.add(new THREE.Vector3(500,0,500));
    for(let i=0;i<100;i++)updateActors(1/60);result.retired=tram.done&& !tram.mesh.visible;
    __lab.show('ticket_34_13');const future=ensureTraffic(state.intersections[0]).find(a=>a.config.type==='tram');future.mesh.position.add(new THREE.Vector3(500,0,500));
    for(let i=0;i<100;i++)updateActors(1/60);result.futureProtected=!future.done&&future.mesh.visible;
    resetGame();state.attract=false;state.roadSegments.slice().forEach(disposeSegment);state.roadSegments=[];state.actors=[];state.intersections=[];state.occluders=[];state.exitRoad=currentCorridor=null;
    const road=buildStraightSegment(-45,200,true);state.roadSegments.push(road);state.exitRoad=currentCorridor=road;nextSegmentZ=155;
    const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);state.roadEvent=buildGasStationEvent(g,25);refreshRoadBounds();
    playerCarGroup.position.set(-15,0,25);playerCarGroup.rotation.y=Math.PI/2;state.paused=false;clearOncoming();window.cityEvents=[];
    for(let i=0;i<300;i++)updateLaneViolation(1/60,true);
    const lettering=[];state.roadEvent.station.traverse(o=>{if(o.userData.stationLettering)lettering.push(o);});
    const canopy=state.occluders.find(o=>o.userData.gasCanopy);for(let i=0;i<120;i++)updateCamera(1/60);
    const ramp=[];state.roadEvent.station.traverse(o=>{if(o.userData.loweredDriveway){} if(o.userData.loweredDriveway){const p=o.geometry.attributes.position;for(let i=0;i<p.count;i++)if(Math.abs(p.getZ(i)-36)<.01)ramp.push(p.getY(i));}});
    result.station={letterMeshes:lettering.length,triangles:lettering[0].geometry.attributes.position.count/3,canopyOpacity:canopy.material.opacity,free:inFreeManeuverArea(),violations:window.cityEvents.filter(e=>e.event==='violation'),rampMax:Math.max(...ramp)};
    const samples=[];for(const z of [14,36])for(const x of [-3,-4.1,-5.8,-7.4,-9,-13])samples.push(playerOnRoad(new THREE.Vector3(x,0,z),Math.PI/2));result.drivewayOnRoad=samples.every(Boolean);result.middleKerbProtected=!playerOnRoad(new THREE.Vector3(-5.8,0,25),Math.PI/2);
    __lab.show('road_7_2');const ev=state.roadEvent;scene.updateMatrixWorld(true);const sw=[];for(const root of state.roadSegments)root.traverse(o=>{if(o.userData.surface==='sidewalk'&&o.visible)sw.push(o);});
    const ray=new THREE.Raycaster();result.pavements=[];for(const side of [-1,1])for(const dz of [-30,-20,-10]){ray.set(new THREE.Vector3(side*5.8,5,ev.junctionZ+dz),new THREE.Vector3(0,-1,0));result.pavements.push(ray.intersectObjects(sw).some(h=>!clippedAway(h.object.material,h.point)));}
    result.avenuePaths=[];
    for(const sc of SITUATIONS.filter(s=>routeSpec(s).reviewed&&avenueMain(s))) {
      __lab.show(sc.id);const it=state.intersections[0],spec=routeSpec(it.situation),w=avenueMain(sc);
      if(spec.maneuver!=='straight')continue;
      const planned=maneuverPoints({intersection:it,spec},'straight',playerCarGroup.position.clone()),path=curve(planned.points);
      refreshRoadBounds();const bad=[];for(let i=0;i<=100;i++){const q=path.getPointAt(i/100),t=path.getTangentAt(i/100);if(!playerOnRoad(q,Math.atan2(t.x,t.z)))bad.push(i);}
      result.avenuePaths.push({id:sc.id,width:w,exit:it.previews.straight.userData.roadWidth,bad});
    }
    state.streetRun=null;state.regulatorShown=true;situationBag=[];let width=8.4,current=[],runs=[];
    for(let i=0;i<400;i++){const s=nextSituation(width),w=avenueMain(s)||8.4;if(current.length&&current[0]!==w){runs.push(current);current=[];}current.push(w);width=s.cityContinueWidth;}runs.push(current);
    result.runs=runs.slice(1,-1).map(r=>({width:r[0],length:r.length}));return result;
  })()`));
  console.log(JSON.stringify(checks,null,2));
  assert.deepEqual(checks.rail,{train:false,open:true,stop:true});
  assert(checks.tram.visible&&!checks.tram.done&&checks.tram.screenY>160&&checks.tram.screenY<544);
  assert(checks.officer.inMotions&&checks.officer.fallen&&checks.officer.bodyY>=-.01);
  assert(checks.retired&&checks.futureProtected);
  assert.equal(checks.station.letterMeshes,1);assert(checks.station.triangles<6000);assert(checks.station.free);assert.deepEqual(checks.station.violations,[]);assert(checks.station.canopyOpacity<.5);assert(checks.station.rampMax<.05);assert(checks.drivewayOnRoad&&checks.middleKerbProtected);assert(checks.pavements.every(Boolean));
  assert(checks.avenuePaths.every(p=>p.exit===p.width&&p.bad.length===0));
  assert(checks.runs.some(r=>r.width>8.5));assert(checks.runs.filter(r=>r.width>8.5).every(r=>r.length>=2&&r.length<=5));assert(checks.runs.every(r=>r.length>=2&&r.length<=5));
  assert.deepEqual(errors,[]);
  fs.mkdirSync('output/game-review/city-polish',{recursive:true});fs.writeFileSync('output/game-review/city-polish/checks.json',JSON.stringify(checks,null,2));
  for(const id of ['ticket_34_13','road_20_16','road_7_2']){await page.evaluate(id=>{__lab.show(id);__lab.run('state.viewportInsets={top:110,bottom:300};for(let i=0;i<120;i++)updateCamera(1/60);renderer.render(scene,camera);');},id);await page.screenshot({path:'output/game-review/city-polish/'+id+'.png'});}
  await page.evaluate(()=>{__lab.show('event_gasstation');__lab.run('playerCarGroup.position.set(-2,0,10);for(let i=0;i<120;i++)updateCamera(1/60);const v=new THREE.OrthographicCamera(-22,22,22*innerHeight/innerWidth,-22*innerHeight/innerWidth,.1,300);v.position.set(23,65,-20);v.lookAt(-12,0,40);window.stationOverview=v;renderer.render(scene,v);');});
  await page.screenshot({path:'output/game-review/city-polish/gasstation.png'});
  await page.evaluate(()=>__lab.run('playerCarGroup.position.set(-19,0,40);for(let i=0;i<120;i++)updateCamera(1/60);renderer.render(scene,window.stationOverview);'));
  await page.screenshot({path:'output/game-review/city-polish/gasstation-under-canopy.png'});
  console.log('City polish regressions passed');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
