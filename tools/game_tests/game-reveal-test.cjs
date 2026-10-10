// Regression: reward taps while a question is active, reveal timing and FX lifetime.
// The private inspection API is injected into the HTTP response, never shipped.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0; window.events = []; window.skipRevealRender = true;
      window.FlutterChannel = { postMessage: m => events.push(JSON.parse(m)) };
    });
    await page.route('**/game.js', async route => {
      const response = await route.fetch();
      const body = (await response.text()).replace('renderer.render(r.scene, r.camera);', 'if (!window.skipRevealRender) renderer.render(r.scene, r.camera);').replace('  // Run init on DOM ready', `
        window.revealTest = { state, get reveal(){return reveal;},
          question(){
            resetGame(); situationBag=[SITUATIONS.find(s=>s.id==='ticket_4_14')];buildInitialTrack();
            const it=state.intersections[0];state.paused=false;
            playerCarGroup.position.set(it.situation.playerStartX??-1.8,0,it.stopZ);playerCarGroup.rotation.y=0;
            updatePlayerMovement(0);return it.situation.id;
          },
          step(n=1, fps=60){ for(let i=0;i<n;i++) updateReveal(1/fps); },
          frame(dt){lastTime=1000;animate(1000+dt*1000);},
          sharedMaps(){const maps=new Set();reveal.scene.traverse(o=>[].concat(o.material||[]).forEach(m=>{if(m.map?.userData?.pddVehicleShared)maps.add(m.map);}));return [...maps];}
        }; // Run init on DOM ready`);
      await route.fulfill({ response, body });
    });
    await page.goto((process.env.GAME_URL || 'http://127.0.0.1:8942') + '/assets/game/');
    await page.waitForFunction(() => window.revealTest && events.some(e => e.event === 'ready'), null, { polling: 100 });
    const report = await page.evaluate(() => {
      const t = revealTest, canvas = document.querySelector('canvas'), results = [];
      const tap = () => {
        const touch = new Touch({ identifier: 1, target: canvas, clientX: 190, clientY: 320 });
        canvas.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [touch], changedTouches: [touch] }));
        canvas.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [touch] }));
      };
      for (const fps of [30, 60]) for (const id of Object.keys(PDD_VEHICLES.specs)) {
        // This was the failing state: a reward appears before answer resolution.
        t.state.isAtSituation = true; t.state.isResolvingSituation = false;
        t.state.attract = false; t.state.nativeControls = true; window.game.setPaused(true);
        window.game.showReveal(id, 'orange'); const r = t.reveal;
        const before = events.filter(e => e.event === 'reveal_shown').length;
        t.step(fps, fps); const waited = r.phase === 'closed';
        tap(); const opens = r.phase === 'opening';
        window.game.openReveal(); // Duplicate Flutter/native taps must not restart it.
        let burstAt = null, burstPhase = null, burstZ = null, smoke = false, shownAt = null, clearance = true, driftingDistance = 0, maxSlip = 0, driftSmoke = false, outsideGarage = true;
        for (let frame = 1; frame <= fps * 2.2; frame++) {
          const wasDrifting = r.phase === 'drifting', previousPosition = r.car.position.clone();
          t.step(1, fps);
          if (wasDrifting) {
            outsideGarage &&= new THREE.Box3().setFromObject(r.car).max.z < -0.72;
            const dx=r.car.position.x-previousPosition.x,dz=r.car.position.z-previousPosition.z,distance=Math.hypot(dx,dz);
            driftingDistance += distance;
            if(distance*fps>1)maxSlip=Math.max(maxSlip,Math.acos(Math.max(-1,Math.min(1,(dx*Math.sin(r.car.rotation.y)+dz*Math.cos(r.car.rotation.y))/distance))));
            driftSmoke ||= r.fx.smoke.some(p => p.sprite.visible && p.strength === 1);
          }
          if (r.phase === 'driving') clearance &&= r.door.children.every(s => !s.visible);
          if (r.fx.smoke.some(p => p.sprite.visible && p.sprite.material.opacity > 0)) smoke = true;
          if (r.fx.burst && burstAt === null) { burstAt = frame / fps; burstPhase = r.phase; burstZ = r.car.position.z; }
          if (r.phase === 'shown' && shownAt === null) shownAt = frame / fps;
        }
        const parked = Math.abs(r.car.position.x) < 0.05 && Math.abs(r.car.position.z + 6.6) < 0.05 && r.car.userData.frontAxles.every(a => Math.abs(a.rotation.y) < 0.001);
        const once = events.filter(e => e.event === 'reveal_shown').length === before + 1;
        window.game.openReveal(); const staysShown = r.phase === 'shown';
        t.step(fps * 4, fps);
        const settled = !r.fx.confetti.visible && r.fx.smoke.every(p => !p.sprite.visible);
        let disposedShared = 0; t.sharedMaps().forEach(m => m.addEventListener('dispose', () => disposedShared++));
        window.game.hideReveal();
        results.push({ id, fps, waited, opens, burstAt, burstPhase, burstZ, smoke, shownAt, clearance, parked, driftingDistance, maxSlip, driftSmoke, outsideGarage, once, staysShown, settled, disposedShared,
          hidden: t.reveal === null, roadStillPaused: t.state.paused });
      }
      window.game.showReveal('sedan', 'orange'); canvas.click();
      const mouseOpens = t.reveal.phase === 'opening'; window.game.hideReveal();
      window.game.showLobby('sedan', 'orange'); t.step(120);
      const lobbyQuiet = t.reveal.phase === 'lobby' && !t.reveal.fx.burst && t.reveal.fx.smoke.every(p => !p.sprite.visible);
      window.game.hideLobby();
      const questionId = t.question();
      const questionActive = t.state.isAtSituation;
      window.game.setPaused(true); window.game.proceedAfterAnswer(true, questionId);
      window.game.showReveal('sedan', 'orange'); window.game.openReveal(); t.step(125);
      window.game.hideReveal(); window.game.setPaused(false);
      const answerResumed = questionActive && !t.state.pendingAnswer && !t.state.paused && t.state.isResolvingSituation && !!t.state.resolution;
      return { results, mouseOpens, lobbyQuiet, answerResumed };
    });
    for (const r of report.results) {
      for (const key of ['waited','opens','smoke','clearance','parked','driftSmoke','outsideGarage','once','staysShown','settled','hidden','roadStillPaused']) assert(r[key], `${r.id}/${r.fps}: ${key}`);
      assert.equal(r.burstPhase, 'driving'); assert(r.burstAt < 0.65 && r.burstZ > -2.5, JSON.stringify(r));
      assert(r.shownAt < 1.45, JSON.stringify(r)); assert(r.driftingDistance > 2, JSON.stringify(r)); assert(r.maxSlip > 0.45, JSON.stringify(r)); assert.equal(r.disposedShared, 0);
    }
    assert(report.mouseOpens); assert(report.lobbyQuiet); assert(report.answerResumed); assert.deepEqual(errors, []);
    const lowFps = await page.evaluate(() => {
      const results=[];
      for(const fps of [10,15]) {
        window.game.showReveal('sedan','orange');window.game.openReveal();let elapsed=0;
        while(revealTest.reveal.phase!=='shown' && elapsed<3){revealTest.frame(1/fps);elapsed+=1/fps;}
        results.push({fps,elapsed,shown:revealTest.reveal.phase==='shown'});window.game.hideReveal();
      }
      return results;
    });
    for(const r of lowFps)assert(r.shown && r.elapsed < 1.65,JSON.stringify(r));
    report.lowFps=lowFps;
    const out = 'output/game-review/reveal'; fs.mkdirSync(out, { recursive: true });
    await page.evaluate(() => { window.skipRevealRender = false; window.game.showReveal('sedan', 'orange'); window.game.openReveal(); revealTest.step(27); });
    await page.screenshot({ path: out + '/emerging.png' });
    await page.evaluate(() => revealTest.step(27));
    await page.screenshot({ path: out + '/celebration.png' });
    await page.evaluate(() => revealTest.step(29));
    await page.screenshot({ path: out + '/shown.png' });
    fs.writeFileSync(out + '/report.json', JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
