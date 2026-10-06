// Deterministic capture of the actual game scene; no changes to shipped assets.
const fs=require('node:fs'),path=require('node:path'),{spawn}=require('node:child_process'),{chromium}=require('playwright');
const out=path.resolve('output/game-reels'),m=JSON.parse(fs.readFileSync(out+'/timeline.json'));
(async()=>{
 const b=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--use-angle=swiftshader']});
 const p=await b.newPage({viewport:{width:720,height:1280}}),errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.addInitScript(()=>window.requestAnimationFrame=()=>0);
 await p.goto('http://127.0.0.1:8940/game/index.html');await p.waitForFunction(()=>window.__lab?.run('!!playerCarGroup'));
 const info=await p.evaluate(()=>__lab.run(`(()=>{
 __lab.show('ticket_20_14');state.paused=true;window.game.setSeason('summer');
 const it=state.intersections[0];it.guide.visible=false;
 window.reel={it,start:playerCarGroup.position.clone(),npc:state.actors[0]};
 if(reel.npc.mesh.userData.badge)reel.npc.mesh.userData.badge.visible=false;
 reel.path=curve(maneuverPoints({intersection:it,spec:routeSpec(it.situation)},'right',reel.start).points);
 reel.camera=new THREE.PerspectiveCamera(36,720/1280,.1,1000);
 reel.it.guide.traverse(o=>{if(o.userData.routeStroke){
 o.material=o.material.clone();
 const fades=new Float32Array(o.geometry.attributes.position.count);fades.fill(1);
 o.geometry.setAttribute('reelFade',new THREE.BufferAttribute(fades,1));
 o.material.onBeforeCompile=shader=>{
 shader.vertexShader='attribute float reelFade; varying float vReelFade;\\n'+shader.vertexShader;
 shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>','#include <begin_vertex>\\nvReelFade = reelFade;');
 shader.fragmentShader='varying float vReelFade;\\n'+shader.fragmentShader;
 shader.fragmentShader=shader.fragmentShader.replace('#include <color_fragment>','#include <color_fragment>\\ndiffuseColor.a *= vReelFade;');
 };
 }});

 __lab.lab.freeCam=true;__lab.lab.orbit.target.set(3,0,it.centerZ-3);
 return {source:it.situation,actor:reel.npc.mesh.position.toArray(),path:reel.path.getLength()};})()`));
 if(info.source.title!==m.question.question||info.source.correctAnswerIndex!==1)throw Error('Source mismatch');
 fs.writeFileSync(out+'/scene-evidence.json',JSON.stringify(info,null,2));
 // Overlay colors come directly from AppColors; no separate reel palette.
 const dart=fs.readFileSync('lib/core/constants/app_colors.dart','utf8').split('// --- Static fallback')[1];
 const color=n=>{const h=dart.match(new RegExp('Color '+n+' = Color\\(0xFF([0-9A-F]{6})\\)'));if(!h)throw Error('Missing color '+n);return '#'+h[1];};
 const palette=Object.fromEntries(['accent','lightAccent','primaryText','secondaryText','cardBackground','green','gray','white'].map(n=>[n,color(n)]));
 await p.route('**/lab/reel-font',r=>r.fulfill({contentType:'font/ttf',body:fs.readFileSync('tools/signs_reel/fonts/Onest[wght].ttf')}));
 // Exact Figma 687:54 geometry, scaled from its 494×880 canvas.
 await p.route('**/lab/reel-correct',r=>r.fulfill({contentType:'image/svg+xml',body:fs.readFileSync('tools/game_reels/assets/correct.svg')}));
 await p.addStyleTag({content:`@font-face{font-family:Onest;src:url('/lab/reel-font');font-weight:100 900}body{font-family:Onest,Arial,sans-serif}#hud{position:fixed;inset:0;pointer-events:none;color:white}#shade{position:absolute;inset:0;background:linear-gradient(180deg,rgba(18,18,18,.8) 0%,rgba(18,18,18,0) 39.7727%)}#top{position:absolute;top:116.60px;left:43.7247px;right:43.7247px}#source{display:inline-block;background:#121212;border-radius:40px;padding:11.66px 17.49px;font-size:20.405px;line-height:1.1;font-weight:700}#title{margin-top:23.32px;font-size:34.98px;line-height:1.1;font-weight:700}#bottom{position:absolute;left:43.7247px;right:43.7247px;top:897.814px}#options{display:grid;gap:5.83px}.opt{display:flex;align-items:center;gap:17.49px;padding:5.83px 23.32px 5.83px 5.83px;border-radius:17.49px;background:rgba(0,0,0,.2);backdrop-filter:blur(43.72px);font-size:23.32px;font-weight:700;line-height:1.1;min-height:69.96px}.num{flex:none;display:flex;align-items:center;justify-content:center;width:58.3px;height:58.3px;border-radius:11.66px;background:#0574F8;color:white;font-size:23.32px;font-weight:700}.correct{background:#09BF18}.correct .num{background:#F8F8FA;color:#000}.num img{width:26.235px;height:26.235px}#you{position:fixed;display:flex;align-items:center;gap:7px;background:#0574F8;color:white;font-size:20px;font-weight:700;padding:7px 12px;border-radius:11px;transform:translate(-50%,-100%)}#you svg{width:21px;height:21px}`});
 await p.evaluate(()=>{const d=document.createElement('div');d.id='hud';d.innerHTML='<div id="shade"></div><div id="top"><div id="source">Билет 20, Вопрос 14</div><div id="title"></div></div><div id="you"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/></svg><span>Ты</span></div><div id="bottom"><div id="options"></div></div>';document.body.append(d)});
 await p.evaluate(()=>document.fonts.load('700 25px Onest'));
 const ff=spawn('ffmpeg',['-y','-f','image2pipe','-framerate','30','-vcodec','png','-i','pipe:0','-i',out+'/sound.wav','-vf','scale=1080:1920:flags=lanczos','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-movflags','+faststart',out+'/pdd-3d-pilot-v3.mp4'],{stdio:['pipe','ignore','pipe']});let log='';ff.stderr.on('data',x=>log+=x);
 const samples=[0,72,Math.round(m.think*30),Math.round((m.reveal+1)*30),Math.round((m.reveal+3)*30),m.frames-1];
 for(let f=0;f<m.frames;f++){
 if(process.env.PREVIEW_ONLY&&!samples.includes(f))continue;
 const t=f/30;
 await p.evaluate(({t,m})=>{
 const pos=__lab.run(`(()=>{
 const t=${t},r=${m.reveal};const o=__lab.lab.orbit;
 // Continuous camera flight: high opening -> close chase -> elevated orbit.
 const ease=x=>{x=Math.max(0,Math.min(1,x));return x*x*(3-2*x);};
 const high=new THREE.Vector3(3+Math.sin(.35-t*.015)*68,57,reel.it.centerZ-5-Math.cos(.35-t*.015)*58);
 const highTarget=new THREE.Vector3(3,0,reel.it.centerZ-5);
 const close=new THREE.Vector3(-.5,4.4,reel.start.z-8.5);
 const closeTarget=new THREE.Vector3(4,1,reel.it.centerZ-1);
 const late=new THREE.Vector3(3+Math.sin(.24-t*.018)*65,55,reel.it.centerZ-5-Math.cos(.24-t*.018)*48);
 let blend,at,eye,fov;
 if(t<2.8){blend=ease((t-1.35)/1.1);eye=high.clone().lerp(close,blend);at=highTarget.clone().lerp(closeTarget,blend);fov=36+blend*58;}
 else{blend=ease((t-3.15)/1.45);eye=close.clone().lerp(late,blend);at=closeTarget.clone().lerp(highTarget,blend);fov=94-blend*58;}
 reel.camera.position.copy(eye);reel.camera.fov=fov;reel.camera.lookAt(at);reel.camera.updateProjectionMatrix();
 const progress=Math.max(0,Math.min(1,(t-r)/3.1));
 playerCarGroup.position.copy(reel.path.getPointAt(progress));
 const tangent=reel.path.getTangentAt(progress);playerCarGroup.rotation.y=Math.atan2(tangent.x,tangent.z);
 // The other driver waits until the player has cleared the conflict area.
 const np=Math.max(0,Math.min(.58,(t-r-3.0)/4.0));
 reel.npc.mesh.position.copy(reel.npc.path.getPointAt(np));
 const nt=reel.npc.path.getTangentAt(np);reel.npc.mesh.rotation.y=Math.atan2(nt.x,nt.z);
 reel.it.guide.visible=t>=r&&progress<1;
 // Trim the existing band's indexed triangles at the nearest passed point.
 reel.it.guide.updateMatrixWorld(true);
 reel.it.guide.traverse(stroke=>{
 if(!stroke.userData.routeStroke)return;
 const pts=stroke.userData.routePoints;let nearest=0,dist=Infinity;
 pts.forEach((p,i)=>{const q=stroke.localToWorld(new THREE.Vector3(...p));const d=q.distanceToSquared(playerCarGroup.position);if(d<dist){dist=d;nearest=i;}});
 const indices=stroke.geometry.index.count;
 stroke.geometry.setDrawRange(nearest*6,Math.max(0,indices-nearest*6));
 // Sub-segment feather makes the moving edge disappear softly under the car.
 const col=stroke.geometry.attributes.reelFade;col.array.fill(1);
 for(let i=nearest;i<Math.min(pts.length,nearest+4);i++){
 const alpha=Math.min(1,(i-nearest)/3);col.setX(i*2,alpha);col.setX(i*2+1,alpha);
 }col.needsUpdate=true;
 });
 updateBlinkers(1/30);renderer.render(scene,reel.camera);
 const v=playerCarGroup.position.clone();v.y+=2.5;v.project(reel.camera);return{x:(v.x+1)*360,y:(1-v.y)*640};})()`);
 const title=document.querySelector('#title'),opts=document.querySelector('#options'),you=document.querySelector('#you');
 you.style.left=pos.x+'px';you.style.top=pos.y+'px';you.style.display=pos.x>0&&pos.x<720&&pos.y>250&&pos.y<896?'flex':'none';
 title.textContent=m.question.question;
 opts.innerHTML=m.question.answers.map((a,i)=>{const yes=t>=m.reveal&&a.correct;return `<div class="opt ${yes?'correct':''}"><span class="num">${yes?'<img src="/lab/reel-correct" alt="">':i+1}</span><span>${a.text}</span></div>`}).join('');
 },{t,m});
 const frame=await p.screenshot({type:'png'});
 if(samples.includes(f))fs.writeFileSync(out+`/v3-preview-${f}.png`,frame);
 if(!ff.stdin.write(frame))await new Promise(r=>ff.stdin.once('drain',r));
 if(f%90===0)console.log(`frame ${f}/${m.frames}`);
 }
 ff.stdin.end();await new Promise((resolve,reject)=>ff.on('close',code=>code?reject(Error(log.slice(-2000))):resolve()));await b.close();if(errors.length)throw Error(errors.join('\n'));console.log('Captured',m.frames,'frames');
})().catch(e=>{console.error(e);process.exitCode=1});
