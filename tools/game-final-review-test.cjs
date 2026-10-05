// Final source review: all active junction paths and actor centres, read-only.
const assert=require('node:assert/strict'),fs=require('fs'),{chromium}=require('playwright');
(async()=>{const b=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});try{const p=await b.newPage();await p.addInitScript(()=>window.requestAnimationFrame=()=>0);await p.goto((process.env.GAME_LAB_URL||'http://127.0.0.1:8941')+'/game/index.html');await p.waitForFunction(()=>window.__lab?.run('!!playerCarGroup'));
const evidence=await p.evaluate(()=>__lab.run(`(()=>{const result={};
  for(const id of ['ticket_28_15','ticket_33_15']){__lab.show(id);result[id]=state.intersections[0].actors.some(a=>a.mesh.userData.tanker);}
  for(const id of ['ticket_31_14','ticket_32_15','ticket_34_13','ticket_39_13']){__lab.show(id);const it=state.intersections[0],tram=it.actors.find(a=>a.config.type==='tram');result[id]=tram.initialPos.x>playerCarGroup.position.x&&Math.cos(tram.mesh.rotation.y)>.9;}
  __lab.show('ticket_32_15');result.sidecar=state.intersections[0].actors.some(a=>a.mesh.userData.sidecar);
  __lab.show('ticket_40_13');const trams=state.intersections[0].actors.filter(a=>a.config.type==='tram');result.rightTrams=trams.length===2&&trams.every(a=>a.initialPos.x<playerCarGroup.position.x)&&trams.some(a=>Math.cos(a.mesh.rotation.y)<-.9)&&trams.some(a=>Math.cos(a.mesh.rotation.y)>.9);
  __lab.show('ticket_11_2');result.sourceLanes=state.intersections[0].situation.mainLaneDividers.includes(3.6);
  __lab.show('ticket_7_5');result.whiteMarkings=state.intersections[0].situation.junctionLaneMarkingPaths.length===2&&state.intersections[0].situation.hideGuide;
  __lab.show('ticket_9_14');result.deadEnd=state.intersections[0].situation.signs.some(s=>s.code==='6.8.2');
  __lab.show('road_11_4');result.zoneEnd=state.roadEvent.scene.endSign==='5.32'&&state.roadEvent.endSignZ<state.roadEvent.endZ;
  __lab.show('road_29_3');result.rural=state.roadEvent.scene.unmarkedRoad&&state.roadEvent.scene.outsideSettlement;
  __lab.show('road_31_4');let shield;state.roadEvent.bypass.traverse(o=>{if(o.userData.chevrons)shield=o;});result.chevrons=shield?.userData.chevrons==='left'&&Math.abs(shield.position.z-state.roadEvent.stopZ-58)<.01;
  __lab.show('road_9_9');result.leftBay=state.roadEvent.busBay.userData.baySide===1;
  __lab.show('event_obstacle');result.mechanic=state.roadEvent.group.children.some(o=>o.userData.changingTyre)&&state.roadEvent.group.children.some(o=>o.userData.spareWheel);
  __lab.show('event_courtyard');let ramp;state.roadEvent.driveway.traverse(o=>{if(o.userData.loweredDriveway)ramp=o;});const ys=Array.from(ramp.geometry.attributes.position.array).filter((v,i)=>i%3===1);result.ramp=Math.min(...ys)<.025&&Math.max(...ys)>.17;
  __lab.show('event_busstop');refreshRoadBounds();result.bay=roadSupports(new THREE.Vector3(-6.7,0,40))&&!roadSupports(new THREE.Vector3(-6.7,0,59));
  const savedRandom=Math.random;try{for(const id of ['ticket_1_13','ticket_2_13'])for(const seed of [0,.4,.9]){
    Math.random=()=>seed;__lab.show(id);const it=state.intersections[0],peds=it.actors.filter(a=>a.config.type==='pedestrian');
    const expected=seed===0?1:seed===.4?2:3;let spaced=peds.length===expected;
    for(let i=0;i<peds.length;i++)for(let j=i+1;j<peds.length;j++)spaced&&=peds[i].initialPos.distanceTo(peds[j].initialPos)>1.2;
    state.paused=false;window.game.proceedAfterAnswer(true,id);for(let i=0;i<1800;i++)updateActors(1/60);
    result[id+'_'+expected]=spaced&&state.actors.filter(a=>a.config.type==='pedestrian').every(a=>a.cleared);
  }}finally{Math.random=savedRandom;}
  return result;})()`));for(const [name,passed]of Object.entries(evidence))assert.equal(passed,true,name);fs.writeFileSync('output/game-review/final-evidence.json',JSON.stringify(evidence,null,2));
const ids=await p.evaluate(()=>__lab.run(`SITUATIONS.filter(s=>routeSpec(s).reviewed).map(s=>s.id)`));let data=[];
for(const id of ids){const r=await p.evaluate(id=>__lab.run(`(()=>{__lab.show(${JSON.stringify(id)});const it=state.intersections[0],spec=routeSpec(it.situation);refreshRoadBounds();let paths={};for(const a of spec.allowedManeuvers||[spec.maneuver]){const planned=maneuverPoints({intersection:it,spec},a,playerCarGroup.position.clone()),path=curve(planned.points),bad=[];for(let n=0;n<=150;n++){let u=n/150,q=path.getPointAt(u),v=path.getTangentAt(u),yaw=Math.atan2(v.x,v.z);if(!playerOnRoad(q,yaw))bad.push([+q.x.toFixed(2),+(q.z-it.centerZ).toFixed(2)]);}paths[a]=bad;}const motions=ensureTraffic(it),actors=motions.filter(a=>a.config.type!=='pedestrian'&&!a.config.stationary).map(a=>{let bad=[];for(let n=0;n<=100;n++){let q=a.path.getPointAt(n/100);if(Math.abs(q.x)>30||Math.abs(q.z-it.centerZ)>24)continue;if(!roadSupports(q))bad.push([+q.x.toFixed(2),+(q.z-it.centerZ).toFixed(2)]);}return {id:a.config.id,bad};});return {id:${JSON.stringify(id)},paths,actors};})()`),id);data.push(r);}fs.writeFileSync('output/game-review/final-path-audit.json',JSON.stringify(data,null,2));const faults=data.filter(r=>Object.values(r.paths).some(v=>v.length)||r.actors.some(a=>a.bad.length && !(r.id==='ticket_21_8'&&a.id==='cyclist')));assert.deepEqual(faults,[],'legal paths must fit the carriageway');console.log('Audited '+ids.length+' junctions');}
finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
