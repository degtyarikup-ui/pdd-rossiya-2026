// Deterministic rail/occlusion/streaming regression, plus optional CPU baseline.
// NODE_PATH=<Playwright modules> GAME_URL=http://127.0.0.1:8949 node tools/game_tests/game-streaming-tram-test.cjs
// GAME_BASELINE=<saved game.js> adds a before/after build timing comparison.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const hook = `
window.__streamTest={
 state, scene:()=>scene, renderer:()=>renderer, camera:()=>camera, player:()=>playerCarGroup,
 scenarios:()=>SITUATIONS.filter(s=>routeSpec(s).reviewed),
 fresh(id,deferred=false) {
   if(typeof streamScenery!=='undefined')streamScenery=false;
   resetGame();state.roadSegments.slice().forEach(disposeSegment);
   state.roadSegments=[];state.intersections=[];state.actors=[];state.occluders=[];state.ambient=[];
   state.resolution=null;state.activeIntersection=null;state.exitRoad=null;currentCorridor=null;
   state.paused=false;state.attract=false;state.isAtSituation=false;
   if(typeof sceneryJobs!=='undefined')sceneryJobs.length=0;
   if(typeof streamScenery!=='undefined')streamScenery=deferred;
   Math.random=()=>.35;
   const started=performance.now();
   buildStraightSegment(-150,200);const incoming=state.roadSegments[state.roadSegments.length-1];currentCorridor=incoming;
   buildIntersectionSegment(50,SITUATIONS.find(s=>s.id===id),incoming);
   const ms=performance.now()-started;
   return {ms,pending:typeof sceneryJobs==='undefined'?0:sceneryJobs.length};
 },
 jobs(budget=3){return processSceneryJobs(budget);},
 pending:()=>sceneryJobs.length,
 drain(){const steps=[];while(sceneryJobs.length)steps.push(processSceneryJobs(3));return steps;},
 traffic:ensureTraffic, inheritSceneryClearances:road=>inheritSceneryClearances(road), roadSupports, refreshRoadBounds, updateActors, applyDetour, addBlocker, updateCamera, applyWeather, disposeSegment,
 render(){scene.updateMatrixWorld(true);renderer.render(scene,camera);},
 closeCamera(){state.userZoom=ZOOM_MIN;state.isAtSituation=false;state.activeIntersection=null;for(let i=0;i<80;i++)updateCamera(1/60);this.render();},
 prepareQuestion(){const it=state.intersections[0];state.activeIntersection=it;state.isAtSituation=true;playerCarGroup.position.set(it.situation.playerStartX??-1.8,0,it.stopZ);for(let i=0;i<80;i++)updateCamera(1/60);this.render();}
};
`;
(async () => {
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 const report={};
 try {
  for(const pass of process.env.GAME_BASELINE?['before','after']:['after']) {
   const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
   const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{window.requestAnimationFrame=()=>0;window.events=[];window.FlutterChannel={postMessage:m=>window.events.push(JSON.parse(m))};});
   await page.route('**/game.js',async route=>{
    const source=fs.readFileSync(pass==='before'?process.env.GAME_BASELINE:path.join(__dirname,'../../assets/game/game.js'),'utf8');
    await route.fulfill({contentType:'application/javascript',body:source.replace('  // Run init on DOM ready',hook+'\n  // Run init on DOM ready')});
   });
   await page.goto((process.env.GAME_URL||'http://127.0.0.1:8949')+'/assets/game/');
   await page.waitForFunction(()=>window.events.some(e=>e.event==='ready'||e.event==='engine_error'));
   assert.deepEqual(errors,[],JSON.stringify(await page.evaluate(()=>window.events)));
   const timings=[];
   for(let i=0;i<3;i++)timings.push(await page.evaluate(deferred=>window.__streamTest.fresh('ticket_24_13',deferred),pass==='after'));
   report[pass]={buildMs:timings.map(t=>t.ms),pending:timings[2].pending};console.log('BUILD',pass,JSON.stringify(report[pass]));
   if(pass==='before'){await page.close();continue;}
   const result=await page.evaluate(()=>{
    const t=window.__streamTest,s=t.state,it=s.intersections[0];
    const steps=t.drain();t.applyWeather();t.render();
    const tram=t.traffic(it).find(a=>a.config.type==='tram');
    const rails=[];it.seg.traverse(o=>{if(o.userData.tramRail&&o.userData.trackPath)rails.push(o);});
    const railCenters=[];
    const railNormals=rails.map(o=>o.geometry.attributes.normal.getY(0));
    for(let i=0;i<rails[0].geometry.attributes.position.count;i+=2){
     const p=new THREE.Vector3();for(const rail of rails)for(const j of [i,i+1])p.add(new THREE.Vector3().fromBufferAttribute(rail.geometry.attributes.position,j));
     railCenters.push(p.multiplyScalar(.25));
    }
    const offRail=[];
    for(let d=0;d<tram.length;d+=2){const p=tram.path.getPointAt(d/tram.length);let closest=Infinity;for(const q of railCenters)closest=Math.min(closest,p.distanceTo(q));if(closest>.31)offRail.push({d,closest});}
    const face=[];it.seg.traverse(o=>{if(o.userData.overheadSignFace)face.push(o);});
    const badge=tram.mesh.children.find(o=>o.userData.actorBadge);
    t.prepareQuestion();
    const gl=t.renderer().getContext(),w=gl.drawingBufferWidth,h=gl.drawingBufferHeight;
    const read=()=>{const data=new Uint8Array(w*h*4);gl.readPixels(0,0,w,h,gl.RGBA,gl.UNSIGNED_BYTE,data);return data;};
    const labelled=read();badge.visible=false;t.render();const clean=read();badge.visible=true;
    const corners=[];for(let i=0;i<face[0].geometry.attributes.position.count;i++)corners.push(new THREE.Vector3().fromBufferAttribute(face[0].geometry.attributes.position,i).applyMatrix4(face[0].matrixWorld).project(t.camera()));
    const minX=Math.ceil((Math.min(...corners.map(p=>p.x))+1)*w/2)+1,maxX=Math.floor((Math.max(...corners.map(p=>p.x))+1)*w/2)-1;
    const minY=Math.ceil((Math.min(...corners.map(p=>p.y))+1)*h/2)+1,maxY=Math.floor((Math.max(...corners.map(p=>p.y))+1)*h/2)-1;
    let obscuredPixels=0;
    for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++){const i=4*(y*w+x);if(clean[i+2]>clean[i]*1.5&&clean[i+2]>clean[i+1]*1.2&&Math.abs(clean[i]-labelled[i])+Math.abs(clean[i+1]-labelled[i+1])+Math.abs(clean[i+2]-labelled[i+2])>30)obscuredPixels++;}
    const first=tram.mesh.position.clone();tram.active=true;tram.waitsForPlayer=false;tram.dependencies=[];
    s.actors=[tram];t.player().position.set(-1.8,0,-120);
    t.addBlocker(it.seg,first.x-1.4,first.x+1.4,first.z+18,first.z+28);
    for(let i=0;i<480;i++)t.updateActors(1/60);
    const stopped={x:tram.mesh.position.x,z:tram.mesh.position.z,speed:tram.speed,detour:tram.detour||0};
    s.blockers=[];for(let i=0;i<2400&&!tram.done;i++)t.updateActors(1/60);
    const retired=tram.done&&!tram.mesh.visible;
    return {steps:steps.length,maxStepMs:Math.max(...steps.map(x=>x.ms)),obscuredPixels,offRail,railNormals,railCount:rails.length,stopped,first:first.toArray(),retired,
     badge:{depthTest:badge.material.depthTest,depthWrite:badge.material.depthWrite,order:badge.renderOrder},
     face:face.map(o=>({order:o.renderOrder,depthTest:o.material.depthTest})),fog:{near:t.scene().fog.near,far:t.scene().fog.far},pending:t.pending()};
   });
   report.after.result=result;
   assert(result.steps>10,'scenery must span multiple frames');assert.equal(result.pending,0);
   assert.deepEqual(result.offRail,[],'tram must follow the actual rendered track');assert.equal(result.railCount,2);assert(result.railNormals.every(n=>n>.95),'rails must face upwards');
   assert(Math.abs(result.stopped.x-result.first[0])<.01,'tram must not change lane');
   assert(result.stopped.z<result.first[2]+18-3,'tram must stop before blocked track');assert.equal(result.stopped.detour,0);assert(result.retired);
   assert(result.obscuredPixels<3,'badge obscures sign pixels: '+result.obscuredPixels);
   assert.equal(result.badge.depthTest,true);assert.equal(result.badge.depthWrite,false);
   assert(result.face.length&&result.face.every(o=>o.order>result.badge.order&&o.depthTest));assert(result.fog.near>100);
   // All authored turning tram paths must be supported by their generated rails.
   const all=await page.evaluate(()=>{
    const t=window.__streamTest,ids=t.scenarios().filter(sc=>(sc.actorsConfig||[]).some(a=>a.type==='tram')||(window.PDD_SCENARIO_ROUTES[sc.id]?.overrides?.actorsConfig||[]).some(a=>a.type==='tram')).map(sc=>sc.id);
    const out=[];
    for(const id of ids){t.fresh(id,true);const it=t.state.intersections[0];for(const a of t.traffic(it).filter(a=>a.config.type==='tram')){
      if(!a.trackPath)throw new Error('Missing track: '+id+' '+a.config.id+' '+it.situation.geometry);const net=a.trackPath,offset=net.curves[0].getLength(),len=net.getLength();let max=0,where=null;
      for(let d=0;d<a.length;d+=1){const p=a.path.getPointAt(d/a.length),q=net.getPoint((offset+d)/len);if(p.distanceTo(q)>max){max=p.distanceTo(q);where={d,p:p.toArray(),q:q.toArray(),coreSame:net.curves[1]===a.path.curves?.[0],len:a.length,pathLen:a.path.getLength()};}}
      out.push({id,actor:a.config.id,max,where});
    }}return out;
   });
   report.after.trams=all.length;assert(all.length>10);assert(all.every(x=>x.max<.1),JSON.stringify(all.filter(x=>x.max>=.1)));
   const lifecycle=await page.evaluate(()=>{
     const t=window.__streamTest;
     t.fresh('ticket_24_13',true);
     const owner=t.state.intersections[0].previews.straight;
     t.inheritSceneryClearances(owner);const inherited=owner.userData.sceneryClearance.length;
     t.scene().attach(owner);owner.position.z+=400;t.refreshRoadBounds();
     const originalCount=owner.children.length;t.drain();
     const added=owner.children.slice(originalCount).filter(o=>o.userData.sceneryObject && o.visible);
     const localBoxes=added.map(o=>new THREE.Box3().setFromObject(o).applyMatrix4(owner.matrixWorld.clone().invert()));
     const clearanceIntact=localBoxes.every(b=>!owner.userData.sceneryClearance.some(z=>b.intersectsBox(z)));
     const roadEnd=owner.userData.roadEnds[1].clone().applyMatrix4(owner.matrixWorld);
     const horizonDrivable=t.roadSupports(roadEnd.clone().add(new THREE.Vector3(-1.8,0,40)));
     t.fresh('ticket_24_13',true);const pending=t.pending(),root=t.state.roadSegments[0];
     t.disposeSegment(root);const after=t.jobs(100);
     return {inherited,added:added.length,clearanceIntact,horizonDrivable,pending,cancelled:after.pending===0&&after.steps===0};
   });
   report.after.lifecycle=lifecycle;
   assert(lifecycle.inherited>0&&lifecycle.added>10&&lifecycle.clearanceIntact);
   assert.equal(lifecycle.horizonDrivable,false,'visual horizon must not bypass junction physics');
   assert(lifecycle.pending>0&&lifecycle.cancelled,'retired roads must cancel pending jobs');
   if(process.env.GAME_OUTPUT){
    fs.mkdirSync(process.env.GAME_OUTPUT,{recursive:true});
    await page.evaluate(()=>{const t=window.__streamTest;t.fresh('ticket_24_13',true);t.drain();t.prepareQuestion();});
    await page.screenshot({path:process.env.GAME_OUTPUT+'/overhead-sign.png'});
    await page.evaluate(()=>{const t=window.__streamTest;t.fresh('ticket_21_14',true);t.drain();t.closeCamera();});
    await page.screenshot({path:process.env.GAME_OUTPUT+'/near-camera.png'});
    // Inspect the horizon from a low perspective camera, the worst visibility
    // case, independently of the current orthographic camera gesture limits.
    await page.evaluate(()=>{
      const t=window.__streamTest,p=t.player().position,cam=new THREE.PerspectiveCamera(55,390/844,.1,800);
      cam.position.set(p.x,3,p.z-9);cam.lookAt(p.x,2,p.z+60);t.renderer().render(t.scene(),cam);
    });
    await page.screenshot({path:process.env.GAME_OUTPUT+'/horizon.png'});
    await page.evaluate(()=>{
      const t=window.__streamTest;t.fresh('ticket_24_13',true);t.drain();
      const cam=new THREE.PerspectiveCamera(50,390/844,.1,600);cam.position.set(51,24,172);cam.lookAt(17,0,203);t.renderer().render(t.scene(),cam);
    });
    await page.screenshot({path:process.env.GAME_OUTPUT+'/tram-service-track.png'});
   }
   assert.deepEqual(errors,[]);await page.close();
  }
  console.log(JSON.stringify(report,null,2));
  if(process.env.GAME_OUTPUT)fs.writeFileSync(process.env.GAME_OUTPUT+'/report.json',JSON.stringify(report,null,2));
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
