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
  // Drive both skew-junction exits through handoff, with real inputs at 60/30 fps.
  for(const id of ['ticket_10_15','ticket_13_15','ticket_2_15','ticket_31_14','ticket_32_15','ticket_34_13','ticket_39_13','ticket_40_13','ticket_40_14','ticket_1_9','ticket_28_2','ticket_3_6','ticket_12_5'])for(const choice of ['ticket_10_15','ticket_13_15'].includes(id)?['left']:['ticket_1_9','ticket_12_5'].includes(id)?['uturn']:['ticket_28_2','ticket_3_6','ticket_40_13'].includes(id)?['right']:['straight'])for(const simple of [true,false]) {
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
    window.game.setGas(false);window.game.setSteering(0);if(!state.resolution)for(let i=0;i<180;i++){window.game.setGas(state.speed<4);tick();}window.game.setGas(false);refreshRoadBounds();
    return {medianHeld,medianGreen:!!r.medianGreen,done:!state.resolution,onRoad:playerOnRoad(),yaw:playerCarGroup.rotation.y,faults:reviewEvents.filter(e=>e.event==='violation').map(e=>e.type),at:playerCarGroup.position.toArray()};
   })()`),{id,choice,simple});
   console.log(id,choice,simple?'simple':'free',JSON.stringify(r));if(id==='ticket_26_13'){assert(r.medianGreen);assert(r.medianHeld>1.8);}assert(r.done,id+' exit failed');assert(r.onRoad,id+' exit seam');assert.deepEqual(r.faults,[],id+' driving faults');assert(Math.abs(r.yaw)<.1,id+' rebased bearing');
  }
  // Approach the new median at normal driving speed, before the question
  // opens. Steering assistance must not keep the car on the grass separator.
  for(const id of ['ticket_2_15','ticket_40_14','ticket_31_14','ticket_32_15','ticket_34_13','ticket_39_13','ticket_3_6','ticket_1_9','ticket_12_5','ticket_11_2','ticket_33_8'])for(const simple of [true,false]) {
    const r=await page.evaluate(({id,simple})=>__lab.run(`(()=>{
      __lab.show(${JSON.stringify(id)});const it=state.intersections[0];
      state.isAtSituation=false;state.paused=false;playerCarGroup.position.set(-1.8,0,it.centerZ-40);
      playerCarGroup.rotation.y=0;state.autoPath=null;state.speed=0;window.reviewEvents=[];
      window.game.setSimpleSteering(${simple});window.game.setGas(true);
      for(let i=0;i<5000&&!state.isAtSituation;i++)updatePlayerMovement(1/60);
      return {arrived:state.isAtSituation,onRoad:playerOnRoad(),faults:reviewEvents.filter(e=>e.event==='violation')};
    })()`),{id,simple});
    console.log('approach',id,simple,JSON.stringify(r));assert(r.arrived && r.onRoad,id+' median approach');assert.deepEqual(r.faults,[],id+' approach faults');
  }
  assert.deepEqual(errors,[]);console.log('26 reviewed manoeuvres completed in both control modes');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
