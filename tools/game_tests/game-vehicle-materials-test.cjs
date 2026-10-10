// Vehicle art regression: real models, cache lifetime, paint and physical extents.
const assert=require('node:assert/strict'),fs=require('node:fs'),{chromium}=require('playwright');
(async()=>{const b=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});try{
 const p=await b.newPage({viewport:{width:390,height:844}}),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.addInitScript(()=>window.requestAnimationFrame=()=>0);
 await p.goto((process.env.GAME_LAB_URL||'http://127.0.0.1:8941')+'/game/index.html');await p.waitForFunction(()=>window.__lab?.run('!!playerCarGroup'));
 const r=await p.evaluate(()=>__lab.run(`(()=>{
  const models=[],paintChecks=[];const props=Object.keys(PDD_VEHICLES.specs);
  const studio=new THREE.Scene(),camera=new THREE.PerspectiveCamera(35,390/844,.1,100);camera.position.set(6,4.5,7);camera.lookAt(0,.7,0);
  studio.add(new THREE.AmbientLight(0xffffff,.8));const sun=new THREE.DirectionalLight(0xffffff,.8);sun.position.set(4,8,5);studio.add(sun);
  for(const id of props){const car=PDD_VEHICLES.create(id);studio.add(car);let meshes=0,triangles=0,uvValid=true,roles=new Set();car.traverse(o=>{if(!o.isMesh)return;meshes++;triangles+=(o.geometry.index?.count||o.geometry.attributes.position.count)/3;if(o.material.userData.vehicleSurface){roles.add(o.material.userData.vehicleSurface);const uv=o.geometry.attributes.uv;uvValid&&=!!uv&&Array.from(uv.array).every(Number.isFinite);}});
   renderer.render(studio,camera);models.push({id,meshes,triangles,uvValid,roles:[...roles],calls:renderer.info.render.calls,halfWidth:car.userData.halfWidth,halfLength:car.userData.halfLength,frontWheels:car.userData.frontAxles.length,brakeLights:car.brakeLights.length});studio.remove(car);disposeSegment(car);
   for(const [paint,value]of Object.entries(PDD_VEHICLES.paints)){const c=PDD_VEHICLES.create(id,paint);const body=[];c.traverse(o=>{if(o.material?.userData.vehicleSurface==='paint')body.push(o.material.color.getHex());});paintChecks.push(body.length>0&&body.every(v=>v===value));disposeSegment(c);}
  }
  const allMaps=PDD_VEHICLE_MATERIALS.cacheInfo(),mapCount=allMaps.length;
  // This pass owns passenger maps; the engine may also have warmed bus/tram
  // materials while building its initial road. Their budget is tested separately.
  const passengerNames=new Set(['paint-grain','brushed-metal','glass','lamp-lens','tyre-atlas','alloy-rim','grille','plate','signal-halo']);
  const maps=allMaps.filter(m=>m.name.startsWith('vehicle:panels:')||passengerNames.has(m.name.slice(8)));let sharedDisposals=0;
  const sample=PDD_VEHICLES.create('sedan'),baseMap=sample.children[0].material.map;baseMap.addEventListener('dispose',()=>sharedDisposals++);disposeSegment(sample);
  let peakTextures=0,lastTextures=0,rendered=0;
  for(let n=0;n<80;n++){const c=PDD_VEHICLES.create(props[n%props.length]);studio.add(c);renderer.render(studio,camera);rendered++;peakTextures=Math.max(peakTextures,renderer.info.memory.textures);studio.remove(c);disposeSegment(c);lastTextures=renderer.info.memory.textures;}
  const cacheStable=mapCount===PDD_VEHICLE_MATERIALS.cacheInfo().length;
  const capMaterials=[];const c=PDD_VEHICLES.create('hatch');c.traverse(o=>{if(o.material?.userData.vehicleSurface==='lens')capMaterials.push(o.material.color.getHex());});
  const signalColours=capMaterials.includes(0xffae25)&&capMaterials.includes(0xd33d38)&&capMaterials.includes(0xfff3cc);
  c.blinkerL.visible=true;c.brakeLights[0].material.color.setHex(0xff3322);const animatedSignal=c.blinkerL.visible&&c.brakeLights[0].material.map.name==='vehicle:lamp-lens';disposeSegment(c);
  // Preserve model workshop recolour/part edits and independent material clones.
  const id='vehicle:sedan';PDD_MODEL_EDITS[id]={parts:{0:{color:'#334455'}}};const edited=PDD_VEHICLES.create('sedan');delete PDD_MODEL_EDITS[id];const plain=PDD_VEHICLES.create('sedan');
  const editorWorks=edited.children[0].material.color.getHex()===0x334455&&plain.children[0].material.color.getHex()===PDD_VEHICLES.specs.sedan.color;disposeSegment(edited);disposeSegment(plain);
  return {models,paintCount:paintChecks.length,allPaints:paintChecks.every(Boolean),maps,gpuBytes:maps.reduce((s,m)=>s+m.width*m.height*4*4/3,0),sharedDisposals,cacheStable,peakTextures,lastTextures,rendered,signalColours,animatedSignal,editorWorks};
 })()`));
 for(const m of r.models){assert(m.uvValid,m.id+' UV');assert.equal(m.frontWheels,2);assert(m.brakeLights>0);const s=await p.evaluate(id=>PDD_VEHICLES.specs[id],m.id);assert.equal(m.halfWidth,s.width/2);assert.equal(m.halfLength,s.length/2);assert(m.roles.includes('glass')&&m.roles.includes('rubber')&&m.roles.includes('rim'));}
 for(const k of ['allPaints','cacheStable','signalColours','animatedSignal','editorWorks'])assert.equal(r[k],true,k);
 assert.equal(r.sharedDisposals,0);assert(r.gpuBytes<6*1024*1024);assert(r.peakTextures-r.lastTextures<=2);
 const before='output/game-textures/vehicles/before/metrics.json';if(fs.existsSync(before)){const base=JSON.parse(fs.readFileSync(before));for(const m of r.models){const old=base.find(x=>x.id===m.id&&x.view==='front');assert.equal(m.meshes,old.meshes,m.id+' mesh indices');assert.equal(m.triangles,old.triangles,m.id+' polygons');assert(m.calls<=old.calls,m.id+' draw calls');}}
 assert.deepEqual(errors,[]);fs.mkdirSync('output/game-textures/vehicles',{recursive:true});fs.writeFileSync('output/game-textures/vehicles/validation.json',JSON.stringify(r,null,2));console.log(JSON.stringify({models:r.models.length,paints:r.paintCount,gpuMiB:r.gpuBytes/1024/1024,rebuilds:r.rendered,cacheStable:r.cacheStable,sharedDisposals:r.sharedDisposals,errors}));
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1});
