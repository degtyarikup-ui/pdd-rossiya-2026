// Integration coverage of all 30 first-batch source questions and their rules.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.requestAnimationFrame=()=>0;window.events=[];window.FlutterChannel={postMessage:m=>window.events.push(JSON.parse(m))};});
  await page.route('**/game.js',async route=>{
   const response=await route.fetch(); const body=(await response.text()).replace('  // Run init on DOM ready',`
    window.batch={state,player:()=>playerCarGroup,THREE,routeSpec,checkRequiredStop,
      show(id,approach=false){
        resetGame();state.attract=false;state.roadSegments.forEach(disposeSegment);
        state.roadSegments=[];state.actors=[];state.intersections=[];state.activeIntersection=null;state.occluders=[];state.ambient=[];state.exitRoad=currentCorridor=null;
        const s=window.PDD_ROAD_SITUATIONS.find(s=>s.id===id);
        if(s){
          const road=buildStraightSegment(-45,200,true);state.roadSegments.push(road);state.exitRoad=currentCorridor=road;nextSegmentZ=155;
          const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);
          if(approach)playerCarGroup.position.set(-1.8,0,-40);
          this.ev=state.roadEvent=buildQuestionEvent(g,-45,s);playerCarGroup.rotation.y=0;
          if(!approach){playerCarGroup.position.set(-1.8,0,this.ev.stopZ);startRoadQuestion();}
          this.it=null;
        }else{
          situationBag=[SITUATIONS.find(s=>s.id===id)];buildInitialTrack();this.it=state.intersections[0];this.ev=null;
          playerCarGroup.position.set(-1.8,0,this.it.stopZ);playerCarGroup.rotation.y=0;updatePlayerMovement(0);
        }
        state.paused=false;state.viewportInsets={top:110,bottom:300};state.viewportTarget=null;
        for(let i=0;i<200;i++)updateCamera(1/60);
        renderer.render(scene,camera);window.events=[];return true;
      },
      answer(){window.game.proceedAfterAnswer(true,(this.ev?.situation||this.it.situation).id);},
      tick(dt=1/60){updateActors(dt);if(state.resolution)updateResolution(dt);else updatePlayerMovement(dt);updateRoadEvent(dt);},
      eventOnly(dt=1/60){updateRoadEvent(dt);},
      faults(){return events.filter(e=>e.event==='violation').map(e=>e.type);},
      surface(x,z){scene.updateMatrixWorld(true);refreshRoadBounds();return roadSupports(new THREE.Vector3(x,0,z));},
      redraw(){renderer.render(scene,camera);},
      texturesReady(){return [...signTextureCache.values()].every(t=>t.image && (t.image.complete ?? true));},
    }; // Run init on DOM ready`);await route.fulfill({response,body});
  });
  await page.goto((process.env.GAME_URL||'http://127.0.0.1:8938')+'/assets/game/');
  await page.waitForFunction(()=>window.batch&&events.some(e=>e.event==='ready'),null,{polling:100});
  const review=JSON.parse(fs.readFileSync('docs/game-expansion-review.json','utf8'));
  const slots=review.firstBatch.map(s=>typeof s==='string'?s:s.slot||s.ticket+'.'+s.question);
  const catalog=await page.evaluate(()=>[...window.PDD_EXTRA_SITUATIONS,...window.PDD_ROAD_SITUATIONS]);
  const selected=slots.map(slot=>catalog.find(s=>s.id.endsWith('_'+slot.replace('.','_'))));
  assert.equal(selected.length,30);assert(selected.every(Boolean));
  const out='build/game_ui/first-batch/rendered';fs.mkdirSync(out,{recursive:true});
  for(const q of selected){
   await page.evaluate(id=>batch.show(id),q.id);
   // Native render of every new layout; all required signs are bundled offline.
   await page.waitForFunction(()=>batch && [...(batch.it?.situation.signs||batch.ev?.scene.signs||[])].every(s=>PDD_SIGN_TEXTURES[s.code]),null,{polling:100});
   await page.waitForFunction(()=>batch.texturesReady(),null,{polling:50});
   await page.evaluate(()=>batch.redraw());await page.screenshot({path:out+'/'+q.id+'.png'});
  }
  const checks=await page.evaluate(()=>{
   const t=batch,s=t.state,p=t.player(),checks={};
   const test=(id,fn)=>{t.show(id);checks[id]=fn();};
   test('ticket_3_2',()=>{
    const it=t.it,labels=it.seg.children.filter(o=>o.userData.trajectoryLabel).map(o=>o.userData.trajectoryLabel);
    t.answer();p.position.z=it.centerZ-9-p.userData.halfLength;s.speed=0;
    for(let i=0;i<60;i++)t.tick();const early=s.resolution.stopSatisfied;
    p.position.z=it.centerZ-4.2-p.userData.halfLength-.1;for(let i=0;i<60;i++)t.tick();
    return labels.join('')==='АБВ' && !early && s.resolution.stopSatisfied && !t.faults().length && !it.seg.children.some(o=>o.userData.stopLine);
   });
   for(const id of ['ticket_17_6','ticket_29_6'])test(id,()=>{
    const it=t.it;t.answer();p.position.z=it.centerZ-8.1-p.userData.halfLength;t.tick(.01);
    const blocked=t.faults().includes('red_light');
    t.show(id);t.answer();for(let i=0;i<210;i++)t.tick();
    return blocked&&!t.faults().length&&s.resolution.elapsed>=3&&t.it.seg.children.some(o=>o.userData.stopLine)===(id==='ticket_29_6');
   });
   for(const id of ['ticket_18_5','ticket_21_16','ticket_33_2'])test(id,()=>{
    const it=t.it;t.answer();
    if(it.situation.requiredStop!==undefined){p.position.z=it.centerZ+it.situation.requiredStop-p.userData.halfLength-.1;for(let i=0;i<50;i++)t.tick();}
    s.resolution.motions.forEach(a=>{a.done=true;a.mesh.visible=false;});
    p.position.set(-26,0,it.centerZ-1.8);p.rotation.y=-Math.PI/2;t.tick(0);
    return !t.faults().includes('wrong_maneuver')&&!s.resolution&&!it.previews.straight;
   });
   for(const id of ['ticket_21_8','ticket_35_8','ticket_38_8'])test(id,()=>{
    const it=t.it,side=it.situation.geometry.endsWith('left')?1:-1;
    return !!it.previews[side>0?'left':'right']&&!it.previews[side>0?'right':'left']&&!!it.previews.straight&&
      !it.seg.children.some(o=>o.userData.crosswalk||o.userData.stopLine)&&t.surface(side*12,it.centerZ)&&!t.surface(-side*12,it.centerZ);
   });
   for(const id of ['road_10_16','road_20_16','road_24_16','road_25_16','road_27_16'])test(id,()=>{
    const ev=t.ev,closed=!ev.rail.open;t.answer();p.position.z=ev.railBoundaryZ-p.userData.halfLength-.1;
    for(let i=0;i<60;i++)t.tick();const stationary=!t.faults().length;
    p.position.z=ev.railBoundaryZ-p.userData.halfLength+.5;t.eventOnly();const premature=t.faults().includes('railway');
    t.show(id);t.answer();const e=t.ev;
    if(e.scene.railway.requireStop){p.position.z=e.railBoundaryZ-p.userData.halfLength-.1;for(let i=0;i<60;i++)t.tick();}
    for(let i=0;i<700&&!e.rail.open;i++)t.tick();p.position.z=e.crossingZ+12;t.eventOnly();
    return closed&&stationary&&premature&&e.rail.open&&!t.faults().length&&
      (e.scene.railway.signals!==false||e.rail.red.length===0)&&
      (id!=='road_10_16'||e.rail.booms.length===2);
   });
   test('road_13_6',()=>t.ev.rail.open&&t.ev.rail.white.length===2&&!t.ev.rail.booms.length);
   test('road_7_2',()=>{
    const e=t.ev;t.answer();p.position.z=e.requiredStopZ-p.userData.halfLength+.5;t.eventOnly();const fail=t.faults().includes('stop');
    t.show('road_7_2');t.answer();p.position.z=t.ev.requiredStopZ-p.userData.halfLength-.1;for(let i=0;i<50;i++)t.eventOnly();
    return fail&&!t.faults().length&&t.ev.stopSatisfied&&e.junctionZ-(e.stopZ+8)===250;
   });
   test('road_11_4',()=>{const e=t.ev;t.answer();p.position.z=e.signZ+1;t.eventOnly();const before=s.speedLimitKmH===30;p.position.z=e.junctionZ+10;t.eventOnly();const after=s.speedLimitKmH===30;p.position.z=e.endSignZ+1;t.eventOnly();return before&&after&&s.speedLimitKmH===null;});
   test('road_15_3',()=>{t.answer();p.position.z=t.ev.signZ+1;t.eventOnly();return s.speedLimitKmH===40;});
   test('road_18_16',()=>{const e=t.ev;t.answer();t.eventOnly();const wait=e.bus.stopFor===Infinity;p.position.z=e.stopZ+35;t.eventOnly();return wait&&e.bus.stopFor===0&&!e.scene.signs?.some(a=>a.code==='5.16');});
   test('road_19_16',()=>{const e=t.ev;t.answer();t.eventOnly();
     const released=e.bus.stopFor===0;for(let i=0;i<600&&!e.bus.cleared;i++)t.tick();
     const legal=released&&e.bus.cleared&&!t.faults().length&&e.scene.signs.some(a=>a.code==='5.16')&&t.surface(-5.4,e.stopZ);
     t.show('road_19_16');t.answer();const bus=t.ev.bus;bus.distance=14;bus.speed=10;
     bus.mesh.position.copy(bus.path.getPointAt(bus.distance/bus.length));const v=bus.path.getTangentAt(bus.distance/bus.length);bus.mesh.rotation.y=Math.atan2(v.x,v.z);
     p.position.set(-1.8,0,bus.mesh.position.z+6);s.speed=8;t.eventOnly();
     return legal&&t.faults().includes('priority');
   });
   test('road_36_6',()=>{t.answer();for(let i=0;i<360;i++)t.eventOnly();const blocked=t.faults().includes('priority');
     t.show('road_36_6');t.answer();p.position.x=-5.4;s.speed=4;t.eventOnly();return blocked&&t.ev.policeYielded&&t.ev.police.stopFor===0&&!t.faults().length;
   });
   for(const simple of [true,false])for(const fps of [30,60]){
     t.show('road_36_6',true);window.game.setSimpleSteering(simple);window.game.setGas(true);
     const e=t.ev,car=e.police,initialGap=p.position.z-car.mesh.position.z;
     let minGap=initialGap;
     for(let i=0;i<fps*35&&!s.isAtSituation;i++){
       t.tick(1/fps);minGap=Math.min(minGap,p.position.z-car.mesh.position.z);
     }
     window.game.setGas(false);
     const gap=p.position.z-car.mesh.position.z,question=e.phase==='question';
     const reached=initialGap>=24&&minGap>=9.99&&gap>=9.99&&gap<initialGap&&car.distance>0;
     const clean=!t.faults().length&&!car.crashed&&events.filter(x=>x.event==='approach_situation'&&x.situation.id==='road_36_6').length===1;
     const before=car.mesh.position.z;t.answer();p.position.x=-5.4;s.speed=4;t.eventOnly();
     for(let i=0;i<fps*3;i++)t.tick(1/fps);
     checks['road_36_6_approach_'+simple+'_'+fps]=question&&reached&&clean&&e.policeYielded&&car.mesh.position.z>before+10&&!t.faults().length;
   }
   window.game.setSimpleSteering(true);
   test('road_31_4',()=>{const e=t.ev;
     const fabric=t.surface(-6.3,e.stopZ+40)&&t.surface(4,e.stopZ+90)&&!t.surface(1,e.stopZ+90)&&t.surface(1,e.stopZ+63);
     t.answer();window.game.setSimpleSteering(false);
     for(let f=0;f<3000&&s.roadEvent===e;f++){
       const z=p.position.z-e.stopZ,target=z<52?-1.8:z<128?4:-1.8;
       const heading=Math.atan2(target-p.position.x,7),err=Math.atan2(Math.sin(heading-p.rotation.y),Math.cos(heading-p.rotation.y));
       window.game.setSteering(Math.max(-1,Math.min(1,err*3)));window.game.setGas(s.speed<5);t.tick();
     }
     window.game.setGas(false);window.game.setSteering(0);
     return fabric&&s.roadEvent!==e&&!t.faults().length;
   });
   return checks;
  });
  for(const [id,ok]of Object.entries(checks))assert.equal(ok,true,id);
  assert.deepEqual(errors,[]);console.log(JSON.stringify({questions:selected.length,ruleChecks:Object.keys(checks).length,screenshots:out}));
 }finally{await Promise.race([browser.close(),new Promise(resolve=>setTimeout(resolve,2000))]);}
})().then(()=>process.exit(0),e=>{console.error(e);process.exit(1);});
