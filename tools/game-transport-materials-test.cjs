// Real transport models: materials must preserve silhouettes, colours, edit
// indices and signals; shared atlases must survive repeated segment deletion.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require('playwright');
const factories = {
  bus: 'createBus(0xF59E0B)', van: 'createVan(0xF2C230)', truck: 'createTruck(0x3B82F6)',
  tanker: 'createTanker(0xFFFFFF)', tractor: 'createTractor(0x317ED4)', special: 'createSpecialCar(0xFFFFFF)',
  motorcycle: 'createMotorcycle(0xD62D2D,0xD62D2D)', sidecar: 'createMotorcycleSidecar(0xD62D2D)',
  cyclist: 'createCyclist(0x10B981,1)', citybike: 'createCyclist(0x10B981,0)', touringbike: 'createCyclist(0x10B981,2)',
  tram: 'createTram()', train: 'createTrain(0x3B82F6)', cart: 'createHorseCart()'
};
(async () => {
  const browser = await chromium.launch({headless: true,
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--use-angle=swiftshader']});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}}), errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => window.requestAnimationFrame = () => 0);
    await page.goto((process.env.GAME_LAB_URL || 'http://127.0.0.1:8941') + '/game/index.html');
    await page.waitForFunction(() => window.__lab?.run('!!playerCarGroup'));
    const result = await page.evaluate(factories => __lab.run(`(() => {
      const factories = ${JSON.stringify(factories)}, ids = Object.keys(factories), models = [];
      const studio = new THREE.Scene(), c = new THREE.PerspectiveCamera(40,390/844,.1,150);
      c.position.set(14,12,20); c.lookAt(0,1,0);
      studio.add(new THREE.AmbientLight(0xffffff,.8));
      const sun = new THREE.DirectionalLight(0xffffff,.8); sun.position.set(4,8,5); studio.add(sun);
      const build = id => { Math.random=()=>.25; return eval(factories[id]); };
      const draw = model => { studio.add(model); renderer.render(studio,c); studio.remove(model); };
      let rimsTurn = true, sidecarWheelStable = true, beaconColours = true, glassPanes = true, cabSupported=true, riderConnected=true, vanGlazing=true;
      for (const id of ids) {
        const model = build(id), box = new THREE.Box3().setFromObject(model); let meshes=0, triangles=0, uvValid=true;
        const roles = new Set(), paints = new Set();
        model.traverse(o => {
          if (!o.isMesh) return; meshes++; triangles += (o.geometry.index?.count || o.geometry.attributes.position.count)/3;
          const m=o.material; if (m.userData.vehicleSurface) {
            roles.add(m.userData.vehicleSurface);
            const uv=o.geometry.attributes.uv;
            uvValid &&= !!uv && uv.count===o.geometry.attributes.position.count && Array.from(uv.array).every(Number.isFinite);
            if (m.userData.vehicleSurface==='paint'&&!m.vertexColors) paints.add(m.color.getHex());
          }
        });
        if(id==='tractor') {
          for(const pane of model.userData.cabWindows) {
            const pb=new THREE.Box3().setFromObject(pane);
            cabSupported &&= pb.min.x>=-.75&&pb.max.x<=.75&&pb.min.y>=1.43&&pb.max.y<=2.71&&pb.min.z>=-1.27&&pb.max.z<=.41;
          }
        }
        if(id==='motorcycle') {
          const hands=[];model.traverse(o=>{if(o.name==='rider-hand')hands.push(o);});
          riderConnected = hands.length===2 && hands.every(o=>Math.abs(o.position.y-1.10)<.03&&Math.abs(o.position.z-.60)<.03&&Math.abs(Math.abs(o.position.x)-.295)<.02);
        }
        if(id==='van') {
          const shield=model.children.find(o=>o.name==='van-windscreen'),body=model.children.find(o=>o.name==='van-shell');
          const pos=shield.geometry.attributes.position;
          for(let i=0;i<pos.count;i++)vanGlazing &&= pos.getZ(i)>1.92+(pos.getY(i)-1.28)*(-.68/.62);
          vanGlazing &&= body.geometry.type==='ExtrudeGeometry';
        }
        draw(model);
        models.push({id,meshes,triangles,uvValid,roles:[...roles],paints:[...paints],box:[box.min.toArray(),box.max.toArray()],calls:renderer.info.render.calls,
          wheels:model.userData.wheels?.length||0,rims:model.userData.rims?.length||0});
        if (model.userData.rims) {
          spinActorWheels(model,.36*.7);
          rimsTurn &&= model.userData.rims.every((rim,i) => Math.abs(rim.rotation.x-model.userData.wheels[i].rotation.x)<1e-6 && Math.abs(rim.rotation.x)>.1);
        }
        if (id==='sidecar') {
          const wheel=model.userData.wheels[2], width=new THREE.Box3().setFromObject(wheel).getSize(new THREE.Vector3()).x;
          spinActorWheels(model,.36*.7);
          sidecarWheelStable = Math.abs(new THREE.Box3().setFromObject(wheel).getSize(new THREE.Vector3()).x-width)<1e-6;
        }
        if (id==='special') beaconColours = JSON.stringify(model.userData.beacons.map(o=>o.material.color.getHex()))===JSON.stringify([0x0574F8,0xEF4444]) && model.userData.beacons.every(o=>o.material.map.name==='vehicle:lamp-lens');
        if (id==='bus'||id==='tram') glassPanes &&= model.children.some(o=>o.material?.map?.name==='vehicle:transport:'+id+'-windows');
        disposeSegment(model);
      }
      // Warm every passenger atlas too, then stress the complete shared cache.
      for (const id of Object.keys(PDD_VEHICLES.specs)) { const m=PDD_VEHICLES.create(id); draw(m); disposeSegment(m); }
      const maps=PDD_VEHICLE_MATERIALS.cacheInfo(), cacheSize=maps.length;
      const sample=build('bus'), watched=new Set(); let sharedDisposals=0;
      sample.traverse(o=>{const map=o.material?.map;if(map&&!watched.has(map)){watched.add(map);map.addEventListener('dispose',()=>sharedDisposals++);}});
      disposeSegment(sample); let lowTextures=Infinity, highTextures=0;
      for (let i=0;i<84;i++) { const m=build(ids[i%ids.length]); draw(m); disposeSegment(m);lowTextures=Math.min(lowTextures,renderer.info.memory.textures);highTextures=Math.max(highTextures,renderer.info.memory.textures); }
      const cacheStable=cacheSize===PDD_VEHICLE_MATERIALS.cacheInfo().length;
      // Vertex colours still own the bicycle frame/rider identity.
      const bike=build('cyclist'), frame=bike.children.find(o=>o.isMesh);
      const vertexColours=frame.material.vertexColors && frame.geometry.attributes.color.count===frame.geometry.attributes.position.count;
      disposeSegment(bike);
      // Workshop part 0 still recolours the same bus panel, with no shared-material bleed.
      const saved=PDD_MODEL_EDITS.bus; PDD_MODEL_EDITS.bus={parts:{0:{color:'#334455'}}};
      const edited=build('bus');if(saved)PDD_MODEL_EDITS.bus=saved;else delete PDD_MODEL_EDITS.bus;
      const plain=build('bus'), editorWorks=edited.children[0].material.color.getHex()===0x334455 && plain.children[0].material.color.getHex()===0xF59E0B;
      disposeSegment(edited);disposeSegment(plain);
      return {models,maps,gpuBytes:maps.reduce((sum,m)=>sum+m.width*m.height*4*4/3,0),cacheStable,sharedDisposals,lowTextures,highTextures,rimsTurn,sidecarWheelStable,beaconColours,glassPanes,vertexColours,editorWorks,cabSupported,riderConnected,vanGlazing,rebuilds:84};
    })()`), factories);
    const before = JSON.parse(fs.readFileSync('output/game-textures/transport/before/metrics.json'));
    const colours = {bus:0xF59E0B,van:0xF2C230,truck:0x3B82F6,tractor:0x317ED4,special:0xFFFFFF,motorcycle:0xD62D2D,tram:0xD32F2F};
    for (const model of result.models) {
      const old=before.find(x=>x.id===model.id&&x.view==='front');
      assert(model.uvValid, model.id+' finite UVs');
      if (!['van','tractor','motorcycle','sidecar'].includes(model.id)) {
        assert.equal(model.meshes,old.meshes,model.id+' workshop indices');
        assert.equal(model.triangles,old.triangles,model.id+' polygons');
        for(let n=0;n<2;n++)for(let a=0;a<3;a++)assert(Math.abs(model.box[n][a]-old.box[n][a])<1e-6,model.id+' physical extent');
      } else {
        const limits={van:[2.20,2.15,4.95],tractor:[2.50,2.92,3.95],motorcycle:[.80,1.82,2.18],sidecar:[1.95,1.82,2.18]}[model.id];
        for(let a=0;a<3;a++)assert(model.box[1][a]-model.box[0][a]<=limits[a],model.id+' rebuilt model fits road');
        assert(model.box[0][1]>-1e-6,model.id+' tyres above ground');
        assert(model.triangles<4000,model.id+' triangle budget');
      }
      assert(model.calls<=old.calls,model.id+' draw calls');
      if (model.id in colours) assert(model.paints.includes(colours[model.id]),model.id+' scenario paint');
    }
    for(const key of ['cacheStable','rimsTurn','sidecarWheelStable','beaconColours','glassPanes','vertexColours','editorWorks','cabSupported','riderConnected','vanGlazing'])assert.equal(result[key],true,key);
    assert.equal(result.sharedDisposals,0);assert(result.highTextures-result.lowTextures<=2,'GPU textures grow after deletion');
    assert(result.gpuBytes<16*1024*1024,'combined passenger + transport texture budget');
    assert.deepEqual(errors,[]);
    fs.writeFileSync('output/game-textures/transport/validation.json',JSON.stringify(result,null,2));
    console.log(JSON.stringify({models:result.models.length,gpuMiB:result.gpuBytes/1024/1024,rebuilds:result.rebuilds,rimsTurn:result.rimsTurn,cacheStable:result.cacheStable,errors}));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
