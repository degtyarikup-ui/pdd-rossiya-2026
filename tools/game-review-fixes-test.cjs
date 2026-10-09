// Physical coverage of reviewed topology, models and exits; never writes user notes.
const assert=require('node:assert/strict'),fs=require('node:fs'),{chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.requestAnimationFrame=()=>0;window.reviewEvents=[];});
  await page.goto((process.env.GAME_LAB_URL||'http://127.0.0.1:8941')+'/game/index.html');
  await page.waitForFunction(()=>window.__lab?.run('!!playerCarGroup'));
  await page.evaluate(()=>__lab.run(`window.FlutterChannel={postMessage:m=>window.reviewEvents.push(JSON.parse(m))};`));
  const ids=['ticket_15_15','ticket_16_15','ticket_18_14','ticket_22_13','ticket_16_14','ticket_17_14','ticket_20_13','ticket_20_14','ticket_20_2','ticket_21_8','ticket_14_8','road_19_16','road_20_16','road_21_11','ticket_18_9','ticket_24_9','ticket_24_13','road_24_16','road_25_16','road_26_9','ticket_21_15','ticket_26_13','ticket_27_9','road_27_10'];
  fs.mkdirSync('output/game-review/fixed',{recursive:true});
  for(const id of ids){
   await page.evaluate(id=>{__lab.show(id);__lab.run(`clearMistakeHighlight();state.viewportInsets={top:110,bottom:300};for(let i=0;i<180;i++)updateCamera(1/60);renderer.render(scene,camera);`);},id);
   await page.screenshot({path:'output/game-review/fixed/'+id+'.png'});
  }
  const results=await page.evaluate(()=>__lab.run(`(()=>{
    const result={};
    for(const id of ['ticket_15_15','ticket_16_15','ticket_18_14','ticket_22_13','ticket_26_13']) {
      __lab.show(id);const it=state.intersections[0],spec=routeSpec(it.situation);
      result[id]={exits:Object.keys(it.previews),paths:{}};
      for(const action of (spec.allowedManeuvers||[spec.maneuver])) {
        const r={intersection:it,spec},planned=maneuverPoints(r,action,playerCarGroup.position.clone()),path=curve(planned.points),bad=[];
        refreshRoadBounds();for(let i=0;i<=200;i++){const p=path.getPointAt(i/200),v=path.getTangentAt(i/200),yaw=Math.atan2(v.x,v.z);if(!playerOnRoad(p,yaw))bad.push([+p.x.toFixed(2),+(p.z-it.centerZ).toFixed(2)]);}
        result[id].paths[action]={bad,yaw:planned.exitYaw};
      }
    }
    __lab.show('ticket_20_13');const it=state.intersections[0],walkers=ensureTraffic(it).filter(a=>a.config.type==='pedestrian');
    let minimum=Infinity;for(let i=0;i<=100;i++){const points=walkers.map(a=>a.path.getPointAt(i/100));minimum=Math.min(minimum,points[0].distanceTo(points[1]));}
    result.pedestrians={count:walkers.length,minimum};
    __lab.show('ticket_16_14');result.sidecar=state.intersections[0].actors.find(a=>a.config.id==='ring_moto').mesh.userData.sidecar;
    __lab.show('ticket_17_14');result.tanker=state.intersections[0].actors.find(a=>a.config.id==='npc_truck_right').mesh.userData.tanker;
    __lab.show('road_21_11');result.rail={white:state.roadEvent.rail.white.length,glows:state.roadEvent.rail.red.some(p=>p.glow.visible)};
    __lab.show('ticket_20_2');result.openEntrance=state.intersections[0].seg.children.some(g=>g.userData.openEntrance===true);
    __lab.show('ticket_24_13');result.overheadSign=state.intersections[0].seg.children.some(g=>g.userData.overheadLaneSign);
    __lab.show('road_24_16');result.twoLampCrossing={red:state.roadEvent.rail.red.length,white:state.roadEvent.rail.white.length};
    __lab.show('road_25_16');const train=state.roadEvent.rail.train;result.departingTrain={tail:train.mesh.position.x+train.halfLength,clearAt:train.clearCrossingDistance};
    __lab.show('road_26_9');result.busBay={exists:!!state.roadEvent.busBay,strokes:0};state.roadEvent.busBay.traverse(o=>{if(o.userData.busStopZigzag)result.busBay.strokes++;});
    return result;
  })()`));
  fs.writeFileSync('output/game-review/fixed/checks.json',JSON.stringify(results,null,2));
  for(const id of ['ticket_15_15','ticket_16_15','ticket_18_14'])assert(!results[id].exits.includes('right'),id+' phantom exit');
  for(const id of ['ticket_15_15','ticket_16_15','ticket_18_14','ticket_22_13','ticket_26_13'])for(const [action,p] of Object.entries(results[id].paths))assert.equal(p.bad.length,0,id+':'+action+' kerb '+JSON.stringify(p.bad.slice(0,4)));
  assert(results.pedestrians.count>=2 && results.pedestrians.count<=3);assert(results.pedestrians.minimum>.6);assert(results.sidecar);assert(results.tanker);assert(results.openEntrance);assert.equal(results.rail.white,0);assert.equal(results.rail.glows,false);assert(results.overheadSign);assert.deepEqual(results.twoLampCrossing,{red:4,white:0});assert(results.departingTrain.tail < -4.2);assert(results.busBay.exists && results.busBay.strokes===1);
  // Drive both skew-junction exits through handoff, with real inputs at 60/30 fps.
  for(const id of ['ticket_15_15','ticket_16_15','ticket_18_14','ticket_22_13','ticket_26_13'])for(const choice of ['ticket_22_13','ticket_26_13'].includes(id)?['left']:id==='ticket_18_14'?['left','straight','uturn']:['left','straight'])for(const simple of [true,false]) {
   const r=await page.evaluate(({id,choice,simple})=>__lab.run(`(()=>{
    __lab.show(${JSON.stringify(id)});state.paused=false;window.game.setSimpleSteering(${simple});window.game.proceedAfterAnswer(true,${JSON.stringify(id)});
    const r=state.resolution,dt=${simple?'1/30':'1/60'};window.reviewEvents=[];
    if(!${simple}){const p=maneuverPoints(r,${JSON.stringify(choice)},playerCarGroup.position.clone());r.path=curve(p.points);r.length=r.path.getLength();r.exitYaw=p.exitYaw;r.exitDirection=${JSON.stringify(choice)};}
    const tick=()=>{updateActors(dt);if(state.resolution)updateResolution(dt);else updatePlayerMovement(dt);};
    for(let i=0;i<1500&&!r.yielding.every(a=>a.cleared||a.done);i++)tick();
    if(${simple}&&${JSON.stringify(choice)}==='uturn')window.game.chooseUturn();else if(${simple}&&${JSON.stringify(choice)}!=='straight')window.game.changeLane(${JSON.stringify(choice)});
    let progress=0,medianHeld=0;
    for(let i=0;i<7000&&state.resolution;i++) {
      if(!${simple}){
        let best=Infinity,nearest=progress;for(let u=progress;u<=Math.min(1,progress+.12);u+=.004){const d=r.path.getPointAt(u).distanceTo(playerCarGroup.position);if(d<best){best=d;nearest=u;}}progress=nearest;
        const target=progress>.94?r.path.getPointAt(1).addScaledVector(r.path.getTangentAt(1),20):r.path.getPointAt(Math.min(1,progress+2/r.length));
        const yaw=Math.atan2(target.x-playerCarGroup.position.x,target.z-playerCarGroup.position.z),err=Math.atan2(Math.sin(yaw-playerCarGroup.rotation.y),Math.cos(yaw-playerCarGroup.rotation.y));
        window.game.setSteering(THREE.MathUtils.clamp(err*3/(Math.max(1,state.speed)*.32),-1,1));
      }
      window.game.setGas(!r.recovery&&state.speed<4);tick();if(r.medianWait>0&&!r.medianGreen&&Math.abs(state.speed)<.01)medianHeld+=dt;
    }
    window.game.setGas(false);window.game.setSteering(0);refreshRoadBounds();
    return {medianHeld,medianGreen:!!r.medianGreen,done:!state.resolution,onRoad:playerOnRoad(),yaw:playerCarGroup.rotation.y,faults:reviewEvents.filter(e=>e.event==='violation').map(e=>e.type),at:playerCarGroup.position.toArray()};
   })()`),{id,choice,simple});
   console.log(id,choice,simple?'simple':'free',JSON.stringify(r));if(id==='ticket_26_13'){assert(r.medianGreen);assert(r.medianHeld>1.8);}assert(r.done,id+' exit failed');assert(r.onRoad,id+' exit seam');assert.deepEqual(r.faults,[],id+' driving faults');assert(Math.abs(r.yaw)<.1,id+' rebased bearing');
  }
  // Approach the new median at normal driving speed, before the question
  // opens. Steering assistance must not keep the car on the grass separator.
  for(const id of ['ticket_22_13','ticket_26_13'])for(const simple of [true,false]) {
    const r=await page.evaluate(({id,simple})=>__lab.run(`(()=>{
      __lab.show(${JSON.stringify(id)});const it=state.intersections[0];
      state.isAtSituation=false;state.paused=false;playerCarGroup.position.set(-1.8,0,it.centerZ-40);
      playerCarGroup.rotation.y=0;state.autoPath=null;state.speed=0;window.reviewEvents=[];
      window.game.setSimpleSteering(${simple});window.game.setGas(true);
      for(let i=0;i<5000&&!state.isAtSituation;i++)updatePlayerMovement(1/60);
      return {arrived:state.isAtSituation,onRoad:playerOnRoad(),faults:reviewEvents.filter(e=>e.event==='violation')};
    })()`),{id,simple});
    assert(r.arrived && r.onRoad,id+' median approach');assert.deepEqual(r.faults,[],id+' approach faults');
  }
  assert.deepEqual(errors,[]);console.log('Review fixes: geometry, models, pedestrian spacing and 18 driven exits passed');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
