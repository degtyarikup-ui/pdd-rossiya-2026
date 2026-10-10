// Comparative GPU-synchronised drawing on this computer, not mobile FPS.
const fs=require('node:fs'),{chromium}=require('playwright');
(async()=>{
 const b=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 try {
  const result={};
  for(const pass of ['before','after']) {
   const p=await b.newPage({viewport:{width:390,height:844}});
   await p.addInitScript(()=>window.requestAnimationFrame=()=>0);
   if(pass==='before')for(const [url,file]of [['game.js','baseline-game.js'],['vehicle-materials.js','baseline-materials.js']])
    await p.route('**/'+url,r=>{
      let body=fs.readFileSync('output/game-textures/transport/'+file,'utf8');
      if(url==='game.js')body=body.replace('  // Run init on DOM ready',fs.readFileSync('tools/game_lab/lab-hook.js','utf8')+'\n  // Run init on DOM ready');
      return r.fulfill({body,contentType:'application/javascript'});
    });
   await p.goto((process.env.GAME_LAB_URL||'http://127.0.0.1:8941')+'/game/index.html');await p.waitForFunction(()=>window.__lab?.run('!!playerCarGroup'));
   result[pass]=await p.evaluate(()=>__lab.run(`(()=>{
    Math.random=()=>.25;
    const s=new THREE.Scene(),r=new THREE.WebGLRenderer({antialias:true});r.setSize(390,844);
    const c=new THREE.OrthographicCamera(-24,24,52,-52,.1,200);c.position.set(35,50,55);c.lookAt(0,1,-15);
    s.add(new THREE.AmbientLight(0xffffff,.8));const l=new THREE.DirectionalLight(0xffffff,.8);l.position.set(4,8,5);s.add(l);
    const models=[createBus(),createVan(),createTruck(),createTanker(),createTractor(),createSpecialCar(),createMotorcycle(0xD62D2D,0xD62D2D),createMotorcycleSidecar(0xD62D2D),createCyclist(0x10B981,1),createCyclist(0x10B981,0),createCyclist(0x10B981,2),createTram(),createHorseCart()];
    models.forEach((m,i)=>{m.position.set((i%3-1)*9,0,Math.floor(i/3)*-12);s.add(m);});
    const gl=r.getContext();for(let i=0;i<30;i++)r.render(s,c);gl.finish();
    const runs=[];for(let n=0;n<7;n++){const t=performance.now();for(let i=0;i<40;i++)r.render(s,c);gl.finish();runs.push((performance.now()-t)/40);}
    const out={medianMs:[...runs].sort((a,b)=>a-b)[3],runs,calls:r.info.render.calls,triangles:r.info.render.triangles,textures:r.info.memory.textures,models:models.length};
    models.forEach(disposeSegment);r.dispose();return out;
   })()`));await p.close();
  }
  result.ratio=result.after.medianMs/result.before.medianMs;
  fs.writeFileSync('output/game-textures/transport/benchmark.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await b.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
