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
 __lab.lab.freeCam=true;__lab.lab.orbit.target.set(3,0,it.centerZ-3);
 return {source:it.situation,actor:reel.npc.mesh.position.toArray(),path:reel.path.getLength()};})()`));
 if(info.source.title!==m.question.question||info.source.correctAnswerIndex!==1)throw Error('Source mismatch');
 fs.writeFileSync(out+'/scene-evidence.json',JSON.stringify(info,null,2));
 // Overlay colors come directly from AppColors; no separate reel palette.
 const dart=fs.readFileSync('lib/core/constants/app_colors.dart','utf8').split('// --- Static fallback')[1];
 const color=n=>{const h=dart.match(new RegExp('Color '+n+' = Color\\(0xFF([0-9A-F]{6})\\)'));if(!h)throw Error('Missing color '+n);return '#'+h[1];};
 const palette=Object.fromEntries(['accent','lightAccent','primaryText','secondaryText','cardBackground','green','gray','white'].map(n=>[n,color(n)]));
 await p.route('**/lab/reel-font',r=>r.fulfill({contentType:'font/ttf',body:fs.readFileSync('tools/signs_reel/fonts/Onest[wght].ttf')}));
 await p.addStyleTag({content:`@font-face{font-family:Onest;src:url('/lab/reel-font')}body{font-family:Onest,Arial,sans-serif}#hud{position:fixed;inset:0;pointer-events:none;color:${palette.primaryText}}#top{position:absolute;top:80px;left:44px;right:65px}#title{background:${palette.cardBackground};border-radius:22px;padding:22px 26px;font-size:35px;line-height:1.18;font-weight:700}#bottom{position:absolute;left:44px;right:65px;bottom:170px;background:${palette.gray};border-radius:24px;padding:16px}#options{display:grid;gap:12px}.opt{display:flex;align-items:center;gap:16px;padding:18px;border-radius:18px;background:${palette.cardBackground};font-size:25px;font-weight:600;line-height:1.22;min-height:86px}.num{flex:none;display:flex;align-items:center;justify-content:center;width:38px;height:38px;border-radius:12px;background:${palette.lightAccent};color:${palette.accent};font-size:21px;font-weight:700}.correct{background:${palette.green}}.correct .num{background:${palette.white};color:${palette.green}}#bar-track{height:8px;background:${palette.lightAccent};margin-top:14px;border-radius:8px;overflow:hidden}#bar{height:8px;background:${palette.accent};border-radius:8px}#you{position:fixed;display:flex;align-items:center;gap:7px;background:${palette.accent};color:${palette.white};font-size:20px;font-weight:700;padding:7px 12px;border-radius:11px;transform:translate(-50%,-100%)}#you svg{width:21px;height:21px}#cta{background:${palette.lightAccent};color:${palette.accent};border-radius:18px;padding:22px;font-size:31px;line-height:1.2;font-weight:700;text-align:center}#source{position:absolute;bottom:115px;left:44px;color:${palette.accent};background:${palette.lightAccent};padding:7px 13px;border-radius:10px;font-size:17px;font-weight:600}`});
 await p.evaluate(()=>{const d=document.createElement('div');d.id='hud';d.innerHTML='<div id="top"><div id="title"></div></div><div id="you"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/></svg><span>Ты</span></div><div id="bottom"><div id="options"></div><div id="bar-track"><div id="bar"></div></div><div id="cta">Ссылка на игру<br>в описании профиля</div></div><div id="source">Билет 20 · Вопрос 14</div>';document.body.append(d)});
 await p.evaluate(()=>document.fonts.load('700 25px Onest'));
 const ff=spawn('ffmpeg',['-y','-f','image2pipe','-framerate','30','-vcodec','png','-i','pipe:0','-i',out+'/sound.wav','-vf','scale=1080:1920:flags=lanczos','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-movflags','+faststart',out+'/pdd-3d-pilot-v2.mp4'],{stdio:['pipe','ignore','pipe']});let log='';ff.stderr.on('data',x=>log+=x);
 const samples=[0,Math.round(m.think*30)-30,Math.round(m.think*30),Math.round((m.reveal+1)*30),Math.round((m.reveal+3)*30),m.frames-1];
 for(let f=0;f<m.frames;f++){
 if(process.env.PREVIEW_ONLY&&!samples.includes(f))continue;
 const t=f/30;
 await p.evaluate(({t,m})=>{
 const pos=__lab.run(`(()=>{
 const t=${t},r=${m.reveal};const o=__lab.lab.orbit;
 // Five authored shots: push-in, side view, overhead decision, turn and exit.
 const think=${m.think};
 o.target.set(3,0,reel.it.centerZ-5);
 if(t<1.15){o.size=58-9*t/1.15;o.yaw=.38-.18*t/1.15;o.pitch=.88;}
 else if(t<think){o.size=54;o.yaw=-.35+(t-1.15)*.035;o.pitch=.82;}
 else if(t<r){o.size=48;o.yaw=.05;o.pitch=1.38;}
 else if(t<r+2.4){o.size=52;o.yaw=.32-(t-r)*.06;o.pitch=1.02;}
 else{o.size=57;o.yaw=-.30+(t-r-2.4)*.04;o.pitch=.82;}
 const progress=Math.max(0,Math.min(1,(t-r)/3.1));
 playerCarGroup.position.copy(reel.path.getPointAt(progress));
 const tangent=reel.path.getTangentAt(progress);playerCarGroup.rotation.y=Math.atan2(tangent.x,tangent.z);
 // The other driver waits until the player has cleared the conflict area.
 const np=Math.max(0,Math.min(.58,(t-r-3.0)/4.0));
 reel.npc.mesh.position.copy(reel.npc.path.getPointAt(np));
 const nt=reel.npc.path.getTangentAt(np);reel.npc.mesh.rotation.y=Math.atan2(nt.x,nt.z);
 reel.it.guide.visible=t>=r&&t<r+3.1;
 updateBlinkers(1/30);updateCamera(0);renderer.render(scene,camera);
 const v=playerCarGroup.position.clone();v.y+=2.5;v.project(camera);return{x:(v.x+1)*360,y:(1-v.y)*640};})()`);
 const title=document.querySelector('#title'),opts=document.querySelector('#options'),track=document.querySelector('#bar-track'),bar=document.querySelector('#bar'),you=document.querySelector('#you'),cta=document.querySelector('#cta'),top=document.querySelector('#top');
 you.style.left=pos.x+'px';you.style.top=pos.y+'px';you.style.display=t<m.cta?'flex':'none';
 title.textContent=m.question.question;
 top.style.display=t<m.cta?'block':'none';
 opts.style.display=t<m.cta?'grid':'none';
 opts.innerHTML=m.question.answers.map((a,i)=>`<div class="opt ${t>=m.reveal&&a.correct?'correct':''}"><span class="num">${i+1}</span><span>${a.text}</span></div>`).join('');
 cta.style.display=t>=m.cta?'block':'none';
 track.style.display=t>=m.think&&t<m.reveal?'block':'none';bar.style.width=(Math.max(0,1-(t-m.think)/2.2)*100)+'%';
 },{t,m});
 const frame=await p.screenshot({type:'png'});
 if(samples.includes(f))fs.writeFileSync(out+`/v2-preview-${f}.png`,frame);
 if(!ff.stdin.write(frame))await new Promise(r=>ff.stdin.once('drain',r));
 if(f%90===0)console.log(`frame ${f}/${m.frames}`);
 }
 ff.stdin.end();await new Promise((resolve,reject)=>ff.on('close',code=>code?reject(Error(log.slice(-2000))):resolve()));await b.close();if(errors.length)throw Error(errors.join('\n'));console.log('Captured',m.frames,'frames');
})().catch(e=>{console.error(e);process.exitCode=1});
