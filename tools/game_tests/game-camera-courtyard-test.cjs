// Actual canvas gestures, question lifecycle, yard exits and both driving modes.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.requestAnimationFrame=()=>0;window.events=[];window.FlutterChannel={postMessage:m=>events.push(JSON.parse(m))};});
  await page.route('**/game.js',async route=>{
   const response=await route.fetch();const body=(await response.text()).replace('  // Run init on DOM ready',`
    window.cameraTest={state,THREE,get camera(){return camera;},player:()=>playerCarGroup,ground:cameraGroundAt,
     run:code=>eval(code),step(n=180){for(let i=0;i<n;i++)updateCamera(1/60);renderer.render(scene,camera);},
     show(id){
      resetGame();state.attract=false;state.roadSegments.forEach(disposeSegment);
      state.roadSegments=[];state.actors=[];state.intersections=[];state.activeIntersection=null;
      state.occluders=[];state.ambient=[];state.exitRoad=currentCorridor=null;resetQuestionCamera();
      const road=window.PDD_ROAD_SITUATIONS.find(s=>s.id===id);
      if(road){
       const seg=buildStraightSegment(-45,200,true);state.roadSegments.push(seg);state.exitRoad=currentCorridor=seg;nextSegmentZ=155;
       const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);const ev=state.roadEvent=buildQuestionEvent(g,-45,road);
       playerCarGroup.position.set(-1.8,0,ev.stopZ);playerCarGroup.rotation.y=0;startRoadQuestion();
      }else{
       situationBag=[SITUATIONS.find(s=>s.id===id)];buildInitialTrack();const it=state.intersections[0];
       playerCarGroup.position.set(it.situation.playerStartX??-1.8,0,it.stopZ);playerCarGroup.rotation.y=0;updatePlayerMovement(0);
      }
      state.paused=false;state.viewportInsets={top:110,bottom:360};state.viewportTarget=null;this.step();window.events=[];
     },
     drive(id,simple){
      this.show(id);window.game.setSimpleSteering(simple);window.game.proceedAfterAnswer(true,id);
      const r=state.resolution,choice=r.spec.maneuver,points=maneuverPoints(r,choice,playerCarGroup.position.clone());
      r.path=curve(points.points);r.length=r.path.getLength();r.exitYaw=points.exitYaw;r.exitDirection=choice;
      let progress=0;
      if(simple)window.game.changeLane(choice);
      for(let i=0;i<6000&&state.resolution;i++){
       if(!simple){
        let best=Infinity,nearest=progress;
        for(let u=progress;u<=Math.min(1,progress+.12);u+=.004){const d=r.path.getPointAt(u).distanceTo(playerCarGroup.position);if(d<best){best=d;nearest=u;}}
        progress=nearest;const target=progress>.94?r.path.getPointAt(1).addScaledVector(r.path.getTangentAt(1),20):r.path.getPointAt(Math.min(1,progress+2/r.length));
        const yaw=Math.atan2(target.x-playerCarGroup.position.x,target.z-playerCarGroup.position.z),err=Math.atan2(Math.sin(yaw-playerCarGroup.rotation.y),Math.cos(yaw-playerCarGroup.rotation.y));
        window.game.setSteering(THREE.MathUtils.clamp(err*3/(Math.max(1,state.speed)*.32),-1,1));
       }
       window.game.setGas(!r.recovery&&state.speed<4);updateActors(1/60);updateResolution(1/60);
      }
      window.game.setSteering(0);window.game.setGas(false);refreshRoadBounds();
      const exitPoint=playerCarGroup.position.clone();
      for(let i=0;i<420&&!state.resolution;i++){window.game.setGas(state.speed<4);updateActors(1/60);updatePlayerMovement(1/60);updateRoadEvent(1/60);}
      window.game.setGas(false);this.step();
      return {done:!state.resolution,onRoad:playerOnRoad(),distance:playerCarGroup.position.distanceTo(exitPoint),faults:events.filter(e=>e.event==='violation').map(e=>e.type)};
     }
    }; // Run init on DOM ready`);await route.fulfill({response,body});
  });
  await page.goto((process.env.GAME_URL||'http://127.0.0.1:8942')+'/assets/game/');
  await page.waitForFunction(()=>window.cameraTest&&events.some(e=>e.event==='ready'),null,{polling:100}).catch(e=>{console.error('Startup errors:',errors);throw e;});
  const out='output/game-review/camera-courtyard';fs.mkdirSync(out,{recursive:true});
  const gestures=await page.evaluate(()=>{
   const t=cameraTest,canvas=document.querySelector('canvas'),result={};
   const error=(p,x,y)=>{const v=p.clone().project(t.camera);return Math.hypot((v.x+1)*195-x,(1-v.y)*422-y);};
   const makeTouches=points=>points.map((p,i)=>new Touch({identifier:i,target:canvas,clientX:p[0],clientY:p[1]}));
   const touch=(type,points,changed=points)=>canvas.dispatchEvent(new TouchEvent(type,{bubbles:true,cancelable:true,touches:makeTouches(points),changedTouches:makeTouches(changed)}));
   for(const id of ['ticket_20_2','road_36_6']){
    t.show(id);let anchor=t.ground(285,215).point;
    canvas.dispatchEvent(new WheelEvent('wheel',{deltaY:-450,clientX:285,clientY:215,cancelable:true}));t.step();
    result[id+'_wheel']=error(anchor,285,215)<.05&&t.state.userZoom<.7&&t.state.questionCameraPan.length()>1;
    anchor=t.ground(220,220).point;touch('touchstart',[[220,220]]);touch('touchmove',[[285,265]]);t.step();touch('touchend',[]);
    result[id+'_pan']=error(anchor,285,265)<.05;
    anchor=t.ground(230,240).point;touch('touchstart',[[200,240],[260,240]]);touch('touchmove',[[170,235],[290,235]]);
    touch('touchmove',[[165,250],[325,250]]);t.step();touch('touchend',[]);
    result[id+'_pinch']=error(anchor,245,250)<.05;
    touch('touchstart',[[210,230]]);touch('touchmove',[[110,245]]);t.step();
    window.game.proceedAfterAnswer(true,id);
    const lane=t.state.targetLane,choice=t.state.resolution?.simpleChoice;
    touch('touchend',[],[[110,245]]);
    result[id+'_noSteering']=t.state.targetLane===lane&&t.state.resolution?.simpleChoice===choice&&t.state.laneChangeX===null;
    result[id+'_reset']=t.state.userZoom===1&&t.state.questionCameraPan.length()===0&&!t.state.questionZoomAnchor;
   }
   t.show('ticket_20_2');window.game.proceedAfterAnswer(true,'ticket_20_2');t.step();
   const before=t.camera.getWorldDirection(new t.THREE.Vector3());window.setGameZoom(.45);t.step();
   const after=t.camera.getWorldDirection(new t.THREE.Vector3());
   result.drivingTilt=Math.abs(after.y)<Math.abs(before.y)-.2&&after.z>before.z+.1;
   result.finite=t.camera.position.toArray().every(Number.isFinite);
   return result;
  });
  console.log('gestures',JSON.stringify(gestures));for(const [name,ok]of Object.entries(gestures))assert(ok,name);
  const boundaries=await page.evaluate(()=>{
   const t=cameraTest,canvas=document.querySelector('canvas'),result={};
   const touch=(type,points)=>canvas.dispatchEvent(new TouchEvent(type,{bubbles:true,cancelable:true,touches:points.map((p,i)=>new Touch({identifier:i,target:canvas,clientX:p[0],clientY:p[1]}))}));
   const corners=()=>[[0,110],[390,110],[0,484],[390,484]].map(([x,y])=>t.ground(x,y).point);
   for(const id of ['ticket_20_2','road_36_6','road_31_4','ticket_26_13']){
    t.show(id);const original=corners(),box=new t.THREE.Box3().setFromPoints(original).expandByScalar(.15);
    window.setGameZoom(.45);t.step();let within=true;
    for(const [dx,dy]of [[3000,0],[-6000,0],[0,3000],[0,-6000]]){
     touch('touchstart',[[195,297]]);touch('touchmove',[[195+dx,297+dy]]);t.step();touch('touchend',[]);
     within=within&&corners().every(p=>box.containsPoint(p));
    }
    window.setGameZoom(1);
    for(let i=0;i<180;i++){t.run('updateCamera(1/60)');within=within&&corners().every(p=>box.containsPoint(p));}
    t.step();
    const reset=t.state.questionCameraPan.length()<1e-5&&corners().every((p,i)=>p.distanceTo(original[i])<.15);
    touch('touchstart',[[195,297]]);touch('touchmove',[[5000,-5000]]);t.step();touch('touchend',[]);
    result[id]=within&&reset&&t.state.questionCameraPan.length()<1e-5;
   }
   return result;
  });
  console.log('boundaries',JSON.stringify(boundaries));for(const [id,ok]of Object.entries(boundaries))assert(ok,id+' camera escaped question');
  for(const id of ['ticket_20_2','ticket_16_2','ticket_35_8']){
   const layout=await page.evaluate(id=>{cameraTest.show(id);return cameraTest.run(`(()=>{
    const it=state.activeIntersection,arrows=[];it.guide.traverse(o=>{if(o.userData.guideArrow)arrows.push(o.position.x);});
    const exits=Object.values(it.previews).filter(o=>o.userData.courtyardExit);
    const fences=it.seg.children.filter(o=>o.userData.courtyardBoundary).map(o=>new THREE.Box3().setFromObject(o));
    const unblocked=exits.every(o=>{const gate=new THREE.Box3(new THREE.Vector3(o.position.x-.3,0,o.position.z-4.3),new THREE.Vector3(o.position.x+.3,2,o.position.z+4.3));return fences.every(b=>!b.intersectsBox(gate));});
    refreshRoadBounds();const missing=[];
    const samples=exits.every(o=>{for(let x=8;x<45;x+=.5)if(!roadSupports(new THREE.Vector3(Math.sign(o.position.x)*x,0,o.position.z)))missing.push(x);return !missing.length;});
    return {shortGuide:arrows.every(x=>Math.abs(x)<10.4),exits:exits.length,unblocked,samples,missing,viewSize:cameraViewSize,
     gates:it.seg.children.filter(o=>o.userData.openEntrance).map(o=>o.position.toArray()),positions:exits.map(o=>o.position.toArray()),center:it.centerZ};
   })()`);},id);
   console.log(id,JSON.stringify(layout));assert(layout.shortGuide&&layout.exits>0&&layout.unblocked&&layout.samples,id+' yard');
   await page.screenshot({path:out+'/'+id+'.png'});
   for(const simple of [true,false]){
    const drive=await page.evaluate(({id,simple})=>cameraTest.drive(id,simple),{id,simple});
    console.log('drive',id,simple,JSON.stringify(drive));assert(drive.done&&drive.onRoad&&drive.distance>15,id+' drive');assert.deepEqual(drive.faults,[],id+' faults');
    await page.screenshot({path:out+'/'+id+'-'+(simple?'simple':'free')+'-exit.png'});
   }
  }
  assert.deepEqual(errors,[]);console.log('Question gestures, camera reset, driving tilt and 6 courtyard drives passed');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
