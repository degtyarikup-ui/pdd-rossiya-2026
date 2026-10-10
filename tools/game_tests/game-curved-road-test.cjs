// Exercise the actual engine: shared road geometry, driving, traffic and UI theme.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.requestAnimationFrame=()=>0;window.events=[];window.FlutterChannel={postMessage:m=>events.push(JSON.parse(m))};});
  await page.route('**/game.js',async route=>{
   const response=await route.fetch();
   const body=(await response.text()).replace('  // Run init on DOM ready',`
    window.bendTest={state,THREE,player:()=>playerCarGroup,frame:curvedRoadFrame,surface:roadSupports,
      place:placeRoadEvent,queue(s){roadBag=[s];},reverse:maybeReverseWorld,change:changeLane,refresh:refreshRoadBounds,dispose:disposeSegment,
      show(simple=false){
        resetGame();state.attract=false;state.roadSegments.forEach(disposeSegment);
        state.roadSegments=[];state.actors=[];state.intersections=[];state.activeIntersection=null;state.occluders=[];state.ambient=[];state.exitRoad=currentCorridor=null;
        const road=buildStraightSegment(-100,560,true);state.roadSegments.push(road);state.exitRoad=currentCorridor=road;nextSegmentZ=460;
        const g=new THREE.Group();scene.add(g);state.roadSegments.push(g);
        this.ev=state.roadEvent=buildQuestionEvent(g,-45,window.PDD_ROAD_SITUATIONS.find(s=>s.id==='road_15_3'));
        playerCarGroup.position.set(-1.8,0,this.ev.stopZ);playerCarGroup.rotation.y=0;startRoadQuestion();
        state.paused=false;state.simpleSteering=simple;state.viewportInsets={top:110,bottom:300};state.viewportTarget=null;
        for(let i=0;i<200;i++)updateCamera(1/60);this.draw();window.events=[];
      },
      draw(){renderer.render(scene,camera);return renderer.domElement.toDataURL();},
      answer(){window.game.proceedAfterAnswer(true,this.ev.situation.id);},
      tick(dt=1/60){updateActors(dt);updatePlayerMovement(dt);updateRoadEvent(dt);},
      drive(dt=1/60){integrateDriving(dt,40/3.6);},
      faults(){return events.filter(e=>e.event==='violation').map(e=>e.type);},
      worldTheme(dark,rain){state.rain=rain;state.overcast=rain;ensureWeatherFx();window.game.setTheme(dark);return this.draw();},
      garageTheme(dark){
        const original=Math.random;let seed=1;Math.random=()=>((seed=(seed*1664525+1013904223)>>>0)/4294967296);
        try{window.game.setTheme(dark);const r=buildRevealScene('pickup',null);renderer.render(r.scene,r.camera);return renderer.domElement.toDataURL();}
        finally{Math.random=original;}
      }
    }; // Run init on DOM ready`);
   await route.fulfill({response,body});
  });
  await page.goto((process.env.GAME_URL||'http://127.0.0.1:8938')+'/assets/game/');
  await page.waitForFunction(()=>window.bendTest&&events.some(e=>e.event==='ready'),null,{polling:100});
  // Compare pixels of exactly the same frame, including sky, asphalt and lighting.
  let themePairs=0;
  for(const season of ['summer','autumn','winter']){
   await page.evaluate(s=>{window.game.setSeason(s);bendTest.show();},season);
   for(const rain of [0,1]){
    const equal=await page.evaluate(r=>bendTest.worldTheme(false,r)===bendTest.worldTheme(true,r),rain);
    assert.ok(equal,season+' rain='+rain+' theme changes world pixels');themePairs++;
   }
  }
  assert.ok(await page.evaluate(()=>bendTest.garageTheme(false)===bendTest.garageTheme(true)),'garage sky changes with theme');
  const production=await page.evaluate(()=>{
   const t=bendTest;t.show();t.state.roadEvent=null;t.state.roadTurn=0;
   t.queue(window.PDD_ROAD_SITUATIONS.find(s=>s.id==='road_15_3'));
   const original=Math.random;Math.random=()=>.5;
   try{const ev=t.place(300);return {id:ev.situation.id,actors:ev.group.children.filter(o=>o.userData.actor).length,curve:!!ev.curve};}
   finally{Math.random=original;}
  });
  assert.equal(production.id,'road_15_3');assert.equal(production.actors,1);assert.ok(production.curve);
  const geometry=await page.evaluate(()=>{
   game.setSeason('summer');bendTest.show();const t=bendTest,e=t.ev,b=e.curve,V=(x,z)=>new t.THREE.Vector3(x,0,z);
   const joins=[b.from,b.to].every(z=>Math.abs(b.centerAt(z))<1e-6&&Math.abs(b.slopeAt(z))<1e-6);
   let supported=true,rejected=true;
   for(let z=b.from-35;z<=e.endZ+5;z+=.5){
    const x=b.centerAt(z);supported&&=t.surface(V(x-1.8,z))&&t.surface(V(x+1.8,z));
    if(z>b.from+10&&z<b.to-10)rejected&&=!t.surface(V(x+6,z))&&!t.surface(V(x-6,z));
   }
   let truck=true;const a=e.actors[0];
   for(let n=0;n<=300;n++){
    const p=a.path.getPointAt(n/300);truck&&=Math.abs(p.x-b.centerAt(p.z)-1.8)<.025;
   }
   return {joins,supported,rejected,truck,peakGrass:!t.surface(V(0,(b.from+b.to)/2))};
  });
  for(const [name,ok]of Object.entries(geometry))assert.ok(ok,name);
  for(const simple of [false,true])for(const dt of [1/60,1/30]){
   const drive=await page.evaluate(({simple,dt})=>{
    const t=bendTest,s=t.state,p=t.player();t.show(simple);t.answer();game.setGas(true);
    let worst=0,onRoad=true,offsetCorrect=true,frames=0;
    for(;frames<2100&&p.position.z<t.ev.endZ+12;frames++){
     t.tick(dt);const f=t.frame();if(f){worst=Math.max(worst,Math.abs(f.offset+1.8));offsetCorrect&&=Math.abs(s.currentLaneOffset-f.offset)<1e-6;}
     onRoad&&=playerOnRoadForTest();
    }
    function playerOnRoadForTest(){return [-1,1].every(side=>t.surface(new t.THREE.Vector3(side*p.userData.halfWidth,0,0).applyAxisAngle(new t.THREE.Vector3(0,1,0),p.rotation.y).add(p.position)));}
    return {worst,onRoad,offsetCorrect,finished:p.position.z>=t.ev.endZ+12,faults:t.faults(),x:p.position.x,yaw:p.rotation.y,frames};
   },{simple,dt});
   assert.ok(drive.finished,JSON.stringify({simple,...drive}));
   assert.ok(drive.onRoad&&drive.offsetCorrect,JSON.stringify({simple,...drive}));
   assert.ok(drive.worst<.25,JSON.stringify({simple,...drive}));
   assert.deepEqual(drive.faults,[],JSON.stringify({simple,...drive}));
   assert.ok(Math.abs(drive.x+1.8)<.15&&Math.abs(drive.yaw)<.02,JSON.stringify({simple,...drive}));
  }
  const moves=await page.evaluate(()=>{
   const t=bendTest,s=t.state,p=t.player();t.show(true);t.answer();
   const b=t.ev.curve,z=b.from+42;p.position.set(b.centerAt(z)-1.8,0,z);p.rotation.y=Math.atan(b.slopeAt(z));
   s.speed=40/3.6;s.isAccelerating=true;t.change('left');
   let left=false,right=false,road=true;
   for(let n=0;n<160;n++){t.drive();road&&=t.surface(p.position);const f=t.frame();if(f&&Math.abs(f.offset-1.8)<.08){left=true;break;}}
   t.change('right');for(let n=0;n<160;n++){t.drive();road&&=t.surface(p.position);const f=t.frame();if(f&&Math.abs(f.offset+1.8)<.08){right=true;break;}}
   // Leave enough own-lane trail behind before reversing (lane changes are retraced too).
   for(let n=0;n<120;n++)t.drive();
   // Reverse follows the recorded curve, rather than leaving it on a straight line.
   s.isAccelerating=false;s.isBraking=true;let reverseRoad=true;
   for(let n=0;n<180;n++){t.drive();reverseRoad&&=t.surface(p.position);}
   const f=t.frame(),before=f.offset;
   p.rotation.y=f.yaw+Math.PI;p.position.copy(f.pointAt(1.8,f.local.z));s.isBraking=false;s.speed=0;
   const rebased=t.reverse(true),after=t.frame();
   const snapshot={afterRoad:t.surface(p.position),afterOffset:after?.offset,
     relativeYaw:after?Math.atan2(Math.sin(p.rotation.y-after.yaw),Math.cos(p.rotation.y-after.yaw)):null};
   // Returning from the oncoming lane remains allowed near a question stop,
   // even though the retained road's local axis now faces the other way.
   p.position.copy(after.pointAt(-1.8,after.local.z));s.speed=40/3.6;s.isAccelerating=true;
   s.intersections[0].stopZ=p.position.z+10;t.change('right');let returnAfterRebase=false;
   for(let n=0;n<160;n++){t.drive();const f=t.frame();if(f&&Math.abs(f.offset-1.8)<.08){returnAfterRebase=true;break;}}
   return {left,right,road,reverseRoad,reverseOffset:before,rebased,...snapshot,returnAfterRebase};
  });
  for(const name of ['left','right','road','reverseRoad','rebased','afterRoad','returnAfterRebase'])assert.ok(moves[name],JSON.stringify(moves));
  assert.ok(Math.abs(moves.reverseOffset+1.8)<.15,JSON.stringify(moves));
  assert.ok(Math.abs(moves.afterOffset-1.8)<.01&&Math.abs(Math.abs(moves.relativeYaw)-Math.PI)<.01,JSON.stringify(moves));
  await page.evaluate(()=>{bendTest.show();bendTest.draw();});
  fs.mkdirSync('output/game-review',{recursive:true});await page.screenshot({path:'output/game-review/curve-15-3.png'});
  assert.deepEqual(errors,[]);console.log(JSON.stringify({themePairs,garageTheme:true,geometry,driveModes:2,frameRates:[60,30],moves}));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
