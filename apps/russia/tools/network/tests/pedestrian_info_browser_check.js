// Real controls, asynchronous shared GLB, independent animation, undo and no author saves.
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
   const s=JSON.parse(JSON.stringify(App.S));s.lights=[{id:'info_test',pos:[0,0],yaw:0,scale:1,state:'green'}];s.actors=[];s.decor=[];
   App.state.S=s;App.state.undo=[];App.state.redo=[];App.state.savedJson=JSON.stringify(s);
   Scene3D.load(s,App.state.build);Tools.set('select');App.select({t:'light',id:'info_test'});App.showInspector();
   Scene3D.setView({...Scene3D.getView(),mode:'3d',orbitYaw:0,orbitPitch:.35,orbitDist:12,x:0,z:-3});
 });
 const chip=(side,value)=>page.locator(`[data-chip="pedestrian-${side}"][data-value="${value}"]`).click();
 await chip('left','off');await chip('right','flashing');
 await page.waitForFunction(()=>Scene3D.anchors.get('light:info_test')?.group.getObjectByName('lamp_info_right'));
 const modes=await page.evaluate(()=>App.S.lights[0].pedestrianSections);
 assert.deepEqual(modes,{left:'off',right:'flashing'});
 const phases=new Set();
 for(let n=0;n<12;n++) {phases.add(await page.evaluate(()=>Scene3D.anchors.get('light:info_test').group.getObjectByName('lamp_info_right').userData.infoLit));await page.waitForTimeout(100);}
 assert(phases.has(true)&&phases.has(false),'right panel actually flashes on a steady green signal');
 assert.equal(await page.evaluate(()=>Scene3D.anchors.get('light:info_test').group.getObjectByName('lamp_info_left').userData.infoLit),false);
 await chip('right','on');
 await page.waitForFunction(()=>Scene3D.anchors.get('light:info_test')?.group.getObjectByName('lamp_info_right')?.userData.infoLit===true);
 const output=path.resolve(__dirname,'../../../output/pedestrian-info');fs.mkdirSync(output,{recursive:true});
 await page.screenshot({path:path.join(output,'editor.png')});
 await page.click('#undo');assert.equal(await page.evaluate(()=>App.S.lights[0].pedestrianSections.right),'flashing');
 await page.click('#redo');assert.equal(await page.evaluate(()=>App.S.lights[0].pedestrianSections.right),'on');
 await chip('left','');
 await page.waitForFunction(()=>Scene3D.anchors.get('light:info_test')?.group.getObjectByName('info_body_left')?.visible===false);
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>App.showInspector());
 assert(await page.locator('#inspector').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'no horizontal overflow');
 await chip('left','on');
 assert.equal(await page.evaluate(()=>App.S.lights[0].pedestrianSections.left),'on');
 assert.deepEqual(errors,[]);assert.deepEqual(writes,[]);
 console.log('Pedestrian information browser: actual GLB, states/blinking, undo/redo, removal, mobile and no writes PASS');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
