// Question framing audit: in every reviewed question the game camera must
// show the whole evidence (participants with their badges, the junction's
// signals and signs, the drawn trajectories) inside the uncovered part of a
// phone screen (HUD on top, the answer card below). `fill` (how much of the
// view the evidence spans) is printed for review: markings, crossings and
// whole junctions are evidence too, so a low value alone is not an error.
// Start scripts/game_lab.sh; run with NODE_PATH pointing at Playwright.
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const LAB = process.env.GAME_LAB_URL || 'http://127.0.0.1:8940';
// A phone (390×844 CSS px) with the HUD and a three-answer card.
const INSETS = { top: 120, bottom: 360 };

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const stand = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
    await stand.goto(LAB + '/#road_14_2');
    await stand.waitForFunction(() => typeof lab !== 'undefined' && current?.id === 'road_14_2');
    const ids = (await stand.evaluate(() => items.filter(i => i.reviewed && i.kind !== 'event').map(i => i.id)))
      .filter(id => !process.env.IDS || process.env.IDS.split(',').includes(id));
    await stand.close();

    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.goto(LAB + '/game/index.html');
    await page.waitForFunction(() => window.__lab && window.__lab.run('!!playerCarGroup'), null, { polling: 200 });
    const problems = [];
    for (const id of ids) {
      const r = await page.evaluate(({ id, INSETS }) => __lab.run(`(()=>{
        let seed=12345;Math.random=()=>((seed=(seed*1664525+1013904223)>>>0)/4294967296);
        __lab.lab.freeCam=false;__lab.show(${JSON.stringify(id)});state.paused=true;
        state.viewportInsets=${JSON.stringify(INSETS)};state.viewportTarget=null;
        for(let i=0;i<400;i++)updateCamera(1/60);
        scene.updateMatrixWorld(true);camera.updateMatrixWorld(true);
        const w=renderer.domElement.clientWidth,h=renderer.domElement.clientHeight;
        const top=${INSETS.top},bottom=h-${INSETS.bottom};
        const items=[];
        const add=(name,o)=>{if(!o||!o.visible)return;const b=new THREE.Box3().setFromObject(o);if(!b.isEmpty())items.push([name,b]);};
        const ev=state.roadEvent?.phase==='question'?state.roadEvent:null,it=ev?null:state.activeIntersection;
        if(ev){
          ev.actors.forEach(a=>{if(a.config.type!=='train')add(a.config.id,a.mesh);});
          ev.group.children.filter(o=>o.userData.questionEvidence&&o!==ev.guide&&o.position.z<=ev.stopZ+60).forEach(o=>add(o.userData.signCode||'evidence',o));
        } else if(it){
          it.actors.forEach(a=>add(a.config?.id||'actor',a.mesh||a.actorMesh));
          it.seg.traverse(o=>{
            const k=o.userData.editKey||'';
            if(!(k==='light'||k.startsWith('sign')||o.userData.signCode)||!o.visible)return;
            for(let p=o.parent;p&&p!==it.seg;p=p.parent)if(p.userData.signCode||p.userData.editKey==='light')return;
            const b=new THREE.Box3().setFromObject(o);
            if(b.isEmpty()||b.min.z>it.centerZ+16||b.max.z<playerCarGroup.position.z-6||Math.abs((b.min.x+b.max.x)/2)>20)return;
            items.push([o.userData.signCode||k,b]);
          });
          it.seg.children.filter(o=>o.userData.trajectoryLabel).forEach(o=>add('label',o));
        }
        add('player',playerCarGroup);
        const out=[];let minX=Infinity,maxX=-Infinity,minY=Infinity,maxY=-Infinity;
        for(const [name,b] of items){
          let x0=Infinity,x1=-Infinity,y0=Infinity,y1=-Infinity;
          for(const cx of [b.min.x,b.max.x])for(const cy of [b.min.y,b.max.y])for(const cz of [b.min.z,b.max.z]){
            const p=new THREE.Vector3(cx,cy,cz).project(camera);const sx=(p.x+1)/2*w,sy=(1-p.y)/2*h;
            x0=Math.min(x0,sx);x1=Math.max(x1,sx);y0=Math.min(y0,sy);y1=Math.max(y1,sy);
          }
          minX=Math.min(minX,x0);maxX=Math.max(maxX,x1);minY=Math.min(minY,y0);maxY=Math.max(maxY,y1);
          const cut=[x0<-2&&'left',x1>w+2&&'right',y0<top-2&&'top',y1>bottom+2&&'bottom'].filter(Boolean);
          if(cut.length)out.push(name+':'+cut.join('+')+'['+[x0,x1,y0,y1].map(v=>Math.round(v)).join(',')+']');
        }
        // How much of the free area the evidence fills (1 = edge to edge).
        const fill=Math.max((maxX-minX)/w,(maxY-minY)/(bottom-top));
        return {out,fill:+fill.toFixed(2),n:items.length};})()`), { id, INSETS });
      if (r.out.length) problems.push(`${id} cut: ${r.out.join('; ')}`);
      console.log(id, JSON.stringify(r));
    }
    console.log('\nscenes:', ids.length, 'problems:', problems.length);
    problems.forEach(p => console.log('  ' + p));
    assert.deepEqual(errors, []);
    assert.deepEqual(problems, []);
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exit(1); });
