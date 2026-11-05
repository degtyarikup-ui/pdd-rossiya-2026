const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({channel:'chrome'});
 try {
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[],writes=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/api/**',route=>{const req=route.request();if(req.method()!=='GET'&&!new URL(req.url()).pathname.startsWith('/api/preview/')){writes.push(req.url());return route.abort();}return route.continue();});
 await page.goto((process.env.EDITOR_URL||'http://127.0.0.1:8950')+'/?scene=ticket_17_6');
 await page.waitForFunction(()=>typeof App!=='undefined'&&App.S?.id==='ticket_17_6'&&document.querySelector('#loading').hidden);
 await page.evaluate(()=>{
   const s=JSON.parse(JSON.stringify(App.S));s.lights=[{id:'mount_test',pos:[4.5,0],yaw:0,scale:1,state:'green'},{id:'ordinary',pos:[-4.5,0],yaw:0,scale:1,state:'green'}];s.actors=[];s.decor=[];
   App.state.S=s;App.state.undo=[];App.state.redo=[];App.state.savedJson=JSON.stringify(s);
   Scene3D.load(s,App.state.build);Tools.set('select');App.select({t:'light',id:'mount_test'});App.showInspector();
   Scene3D.setView({...Scene3D.getView(),mode:'3d',orbitYaw:0,orbitPitch:.5,orbitDist:32,x:0,z:-3});
 });
 const chip=(name,value)=>page.locator(`[data-chip="${name}"][data-value="${value}"]`).click();
 const loaded=name=>page.waitForFunction(name=>Scene3D.anchors.get('light:mount_test')?.group.getObjectByName(name),name);
 await chip('mount','cantilever');await loaded('lamp_green');
 let mount=await page.evaluate(()=>{
   const g=Scene3D.anchors.get('light:mount_test').group, head=g.getObjectByName('traffic_signal_head');
   return {position:head.position.toArray(),post:!!g.getObjectByName('cantilever_post'),beam:!!g.getObjectByName('cantilever_beam')};
 });
 assert.deepEqual(mount.position,[-4.5,2.9,0]);assert(mount.post&&mount.beam);
 await chip('pedestrian-right','on');await loaded('lamp_info_right');
 assert.equal(await page.evaluate(()=>Scene3D.anchors.get('light:mount_test').group.getObjectByName('traffic_signal_head').position.y),5.5-1.745);
 await chip('signal-type','reversible');await loaded('lamp_reverse_red');
 for(const state of ['red','green','yellow_left','yellow_right','off']) {
   await chip('reversible',state);await loaded('lamp_reverse_red');
   const lamps=await page.evaluate(()=>{
     const g=Scene3D.anchors.get('light:mount_test').group;
     return ['red','green','yellow_left','yellow_right'].map(s=>{const lamp=g.getObjectByName('lamp_reverse_'+s);return {visible:lamp.visible,colour:lamp.children[0].material.color.getHexString()};});
   });
   assert.equal(await page.evaluate(()=>App.S.lights[1].state),'green');
   if(state.startsWith('yellow_')) {assert(!lamps[1].visible);assert(lamps[state==='yellow_left'?2:3].visible);}
   assert.equal(lamps[0].colour,state==='red'?'ff3838':'351719');
 }
 await chip('reversible','green');await chip('armSide','right');await loaded('lamp_reverse_green');
 assert.equal(await page.evaluate(()=>Scene3D.anchors.get('light:mount_test').group.getObjectByName('traffic_signal_head').position.x),4.5);
 await chip('armSide','left');
 await page.locator('[data-slider="reach"]').fill('7.5');await page.locator('[data-slider="reach"]').dispatchEvent('change');
 assert.equal(await page.evaluate(()=>App.S.lights[0].reach),7.5);
 await page.click('#undo');assert.equal(await page.evaluate(()=>App.S.lights[0].reach),4.5);
 await page.click('#redo');assert.equal(await page.evaluate(()=>App.S.lights[0].reach),7.5);
 await page.evaluate(()=>{App.select({t:'light',id:'ordinary'});});await chip('state','red');
 assert.equal(await page.evaluate(()=>App.S.lights[0].reversible),'green');
 await page.evaluate(()=>{App.select({t:'light',id:'mount_test'});App.showInspector();});
 await loaded('lamp_reverse_green');
 const output=path.resolve(__dirname,'../../../output/signal-mounts');fs.mkdirSync(output,{recursive:true});
 await page.screenshot({path:path.join(output,'editor.png')});
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>App.showInspector());
 assert(await page.locator('#inspector').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'no mobile horizontal overflow');
 await chip('signal-type','standard');await loaded('lamp_info_right');
 assert.equal(await page.evaluate(()=>App.S.lights[0].pedestrianSections.right),'on','switch back retains previous sections');
 await page.setViewportSize({width:1440,height:1000});
 await page.evaluate(()=>Tools.set('light'));
 await page.locator('[data-light-type="reversible"]').click();
 const count=await page.evaluate(()=>App.S.lights.length);
 await page.mouse.move(700,620);await page.mouse.click(700,620);
 assert.equal(await page.evaluate(()=>App.S.lights.length),count+1,'shelf places a real object');
 assert.equal(await page.evaluate(()=>App.S.lights.at(-1).reversible),'off');
 assert.equal(await page.evaluate(()=>App.S.lights.at(-1).mount),'cantilever');
 assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
 console.log('Signal browser: mount/height/sides, five states, isolation, undo, mobile, type switch and placement PASS');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
