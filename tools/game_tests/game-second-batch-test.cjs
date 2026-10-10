// Integration coverage of all 25 trajectory/lane source questions and their rules.
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
    window.batch={state,player:()=>playerCarGroup,THREE,routeSpec,checkRequiredStop,checkManeuverPath,curve,planPath,applyJunctionChoice,playerOnRoad,
      show(id){
        resetGame();state.attract=false;state.roadSegments.forEach(disposeSegment);
        state.roadSegments=[];state.actors=[];state.intersections=[];state.activeIntersection=null;state.occluders=[];state.ambient=[];state.exitRoad=currentCorridor=null;
        const s=window.PDD_ROAD_SITUATIONS.find(s=>s.id===id);
        if(s){
          const road=buildStraightSegment(-45,200,true);state.roadSegments.push(road);state.exitRoad=currentCorridor=road;nextSegmentZ=155;
          const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);
          this.ev=state.roadEvent=buildQuestionEvent(g,-45,s);playerCarGroup.position.set(-1.8,0,this.ev.stopZ);playerCarGroup.rotation.y=0;startRoadQuestion();
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
  const review=JSON.parse(fs.readFileSync('docs/game/game-expansion-review.json','utf8'));
  const slots='1.9 3.8 3.9 7.5 8.4 8.8 9.9 11.2 11.8 12.5 16.2 17.8 18.9 19.8 20.2 20.6 22.8 24.9 26.9 27.9 28.2 31.5 32.9 33.8 32.5'.split(' ');
  const catalog=await page.evaluate(()=>[...window.PDD_EXTRA_SITUATIONS,...window.PDD_ROAD_SITUATIONS]);
  const selected=slots.map(slot=>catalog.find(s=>s.id.endsWith('_'+slot.replace('.','_'))));
  assert.equal(selected.length,25);assert(selected.every(Boolean));
  const out='build/game_ui/second-batch/rendered';fs.mkdirSync(out,{recursive:true});
  for(const q of selected){
   await page.evaluate(id=>batch.show(id),q.id);
   // Native render of every new layout; all required signs are bundled offline.
   await page.waitForFunction(()=>batch && [...(batch.it?.situation.signs||batch.ev?.scene.signs||[])].every(s=>PDD_SIGN_TEXTURES[s.code]),null,{polling:100});
   await page.waitForFunction(()=>batch.texturesReady(),null,{polling:50});
   await page.evaluate(()=>batch.redraw());await page.screenshot({path:out+'/'+q.id+'.png'});
  }
  const checks=await page.evaluate(ids=>{
   const t=batch,s=t.state,p=t.player(),checks={};
   const begin=(id,simple=false)=>{t.show(id);window.game.setSimpleSteering(simple);t.answer();return s.resolution;};
   // Physical driving of every new junction in BOTH control modes, using
   // public exit buttons in simple mode and steering/gas/brake in free mode.
   for(const id of ids.filter(id=>id.startsWith('ticket'))){
    for(const simple of [false,true]){
     const r=begin(id,simple),spec=r.spec;let progress=0;
     for(let i=0;i<900&&!r.yielding.every(a=>a.cleared||a.done);i++)t.tick();
     if(simple){if(spec.maneuver==='uturn')window.game.chooseUturn();else if(spec.maneuver!=='straight')window.game.changeLane(spec.maneuver);}
     for(let i=0;i<4000&&s.resolution;i++){
      if(!simple){
       let best=Infinity,nearest=progress;
       for(let u=progress;u<=Math.min(1,progress+.12);u+=.004){const d=r.path.getPointAt(u).distanceTo(p.position);if(d<best){best=d;nearest=u;}}
       progress=nearest;const target=progress>.94?r.path.getPointAt(1).addScaledVector(r.path.getTangentAt(1),20):r.path.getPointAt(Math.min(1,progress+2/r.length));
       const heading=Math.atan2(target.x-p.position.x,target.z-p.position.z),err=Math.atan2(Math.sin(heading-p.rotation.y),Math.cos(heading-p.rotation.y));
       window.game.setSteering(Math.max(-1,Math.min(1,err*3/(Math.max(1,s.speed)*.32))));
      }
      const stop=r.intersection.situation.requiredStop;
      const hold=stop!==undefined&&r.elapsed<(r.intersection.situation.redWait||0)&&p.position.z+p.userData.halfLength>r.intersection.centerZ+stop-2;
      window.game.setGas(!hold&&!r.recovery&&s.speed<4);window.game.setBrake(hold&&s.speed>.02);t.tick();
     }
     window.game.setGas(false);window.game.setBrake(false);window.game.setSteering(0);
     checks[id+':'+(simple?'simple':'free')]={done:!s.resolution,faults:t.faults(),at:p.position.toArray(),choice:r.simpleChoice};
    }
   }
   // The source question's demonstrated manoeuvre doesn't prohibit other
   // lawful exits. Drive ALL authored alternatives using the real buttons.
   for(const id of ids.filter(id=>id.startsWith('ticket'))){
    t.show(id);const choices=t.routeSpec(t.it.situation).allowedManeuvers||[];
    for(const choice of choices.filter(c=>c!==t.routeSpec(t.it.situation).maneuver)){
     const r=begin(id,true);
     for(let i=0;i<900&&!r.yielding.every(a=>a.cleared||a.done);i++)t.tick();
     if(choice==='uturn')window.game.chooseUturn();else if(choice!=='straight')window.game.changeLane(choice);
     for(let i=0;i<4000&&s.resolution;i++){
      const stop=r.intersection.situation.requiredStop;
      const hold=stop!==undefined&&r.elapsed<(r.intersection.situation.redWait||0)&&p.position.z+p.userData.halfLength>r.intersection.centerZ+stop-2;
      window.game.setGas(!hold&&!r.recovery&&s.speed<4);window.game.setBrake(hold&&s.speed>.02);t.tick();
     }
     window.game.setGas(false);window.game.setBrake(false);
     // Some junctions physically have no right-hand driveway; don't count an
     // inaccessible theoretical direction as an input option.
     checks[id+':alternative-'+choice]={done:!s.resolution,faults:t.faults(),at:p.position.toArray(),choice:r.simpleChoice};
    }
   }
   // Every visibly illegal alternative must fail BEFORE it reaches the exit,
   // including two alternatives which lead to the very same road.
   const illegal={ticket_1_9:[0,-1.8],ticket_3_8:[-12,-1.8],ticket_3_9:[0,1],ticket_8_8:[-1.8,-5],
    ticket_11_2:[-8,-1.8],ticket_11_8:[-12,-1.8],ticket_17_8:[-7,-1.8],ticket_18_9:[0,-11],
    ticket_19_8:[14,1.8],ticket_20_6:[-5.4,4],ticket_22_8:[10,-1.8],ticket_24_9:[0,-9],ticket_27_9:[0,-5.6],ticket_28_2:[-12,4.2]};
   for(const [id,[x,z]]of Object.entries(illegal)){
    const r=begin(id);
    if(id==='ticket_19_8'){p.position.set(-5.4,0,r.intersection.centerZ-5);t.checkManeuverPath(r);}
    p.position.set(x,0,r.intersection.centerZ+z);t.checkManeuverPath(r);
    checks[id+':bad']={done:true,faults:t.faults(),expect:'wrong_maneuver'};
   }
   for(const id of ['road_9_9','road_26_9','road_32_9']){
    begin(id);p.position.z=t.ev.stopZ+17;p.rotation.y=Math.PI;t.eventOnly();t.eventOnly();
    checks[id+':bad']={done:true,faults:t.faults(),expect:'wrong_maneuver',once:true};
    begin(id);p.position.z=t.ev.stopZ+17;t.eventOnly();checks[id+':legal']={done:true,faults:t.faults()};
   }
   for(const [id,x,z] of [['road_31_5',0,20],['road_32_5',-4.2,40]]){
    begin(id);p.position.set(x-1.8,0,t.ev.stopZ+z);t.eventOnly();p.position.x=x+1.8;t.eventOnly();t.eventOnly();
    checks[id+':cross']={done:true,faults:t.faults(),expect:'wrong_maneuver',once:true};
    begin(id);p.position.set(x+1.8,0,t.ev.stopZ+z);t.ev.lanePrevious=p.position.clone();p.position.x=x-1.8;t.eventOnly();
    checks[id+':return-cross']={done:true,faults:t.faults(),expect:'wrong_maneuver'};
   }
   begin('road_32_5');p.position.set(-1.8,0,t.ev.stopZ+15);t.eventOnly();p.position.x=-5.4;t.eventOnly();
   checks['road_32_5:before-solid']={done:true,faults:t.faults()};
   for(const [id,x,z] of [['road_31_5',0,20],['road_32_5',-4.2,40]]){
    begin(id);p.position.set(x-1.8,0,t.ev.stopZ+z);t.eventOnly();p.position.x=x-.5;t.eventOnly();
    checks[id+':wheel-cross']={done:true,faults:t.faults(),expect:'wrong_maneuver'};
   }
   begin('road_26_9');p.position.z=t.ev.stopZ+17;p.rotation.y=Math.PI/2;t.eventOnly();p.position.z=t.ev.stopZ+4;p.rotation.y=Math.PI;t.eventOnly();
   checks['road_26_9:started-at-stop']={done:true,faults:t.faults(),expect:'wrong_maneuver'};
   begin('road_32_9');p.position.set(1.8,0,t.ev.stopZ+20);t.tick(0);
   checks['road_32_9:either-lane']={done:!s.oncoming,faults:t.faults()};
   let r=begin('ticket_11_8');p.position.set(-16,0,r.intersection.centerZ-5.4);r.pathAudit.previous.copy(p.position);p.position.z=r.intersection.centerZ-1.8;t.checkManeuverPath(r);
   checks['ticket_11_8:lane-after-turn']={done:true,faults:t.faults()};
   begin('ticket_33_8');const parked=s.resolution.motions.find(a=>a.config.id==='parked'),before=parked.mesh.position.clone();for(let i=0;i<240;i++)t.tick();
   checks['ticket_33_8:stationary']={done:parked.mesh.position.distanceTo(before)<.01&&parked.mesh.userData.blinkerSide==='hazard',faults:t.faults()};
   return checks;
  },selected.map(s=>s.id));
  fs.writeFileSync('build/game_ui/second-batch/checks.json',JSON.stringify(checks,null,2));
  const failed=Object.entries(checks).filter(([id,r])=>!r.done || (r.expect?!r.faults.includes(r.expect)||(r.once&&r.faults.length!==1):r.faults.length));
  assert.deepEqual(failed,[],JSON.stringify(failed));assert.deepEqual(errors,[]);
  console.log(JSON.stringify({questions:25,checks:Object.keys(checks).length,screenshots:out}));
 }finally{await Promise.race([browser.close(),new Promise(resolve=>setTimeout(resolve,2000))]);}
})().then(()=>process.exit(0),e=>{console.error(e);process.exit(1);});
