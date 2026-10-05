// Every scene of the lab catalogue (junctions, road questions, events):
// 1. pavement strips along the main road keep their kerb exactly on the
//    asphalt edge (4.2 m) and their outer edge at 7.4 m, so no step shows
//    where they meet a rounded corner or the next piece;
// 2. the edge line 1.2 runs on along every kerb of the main road, except at
//    a mouth where another road or a driveway joins.
// GAME_LAB_URL=http://127.0.0.1:8941 node tools/game-road-markings-audit.cjs [id,id]
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 400 } }), errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    await page.goto((process.env.GAME_LAB_URL || 'http://127.0.0.1:8941') + '/game/index.html');
    await page.waitForFunction(() => window.__lab && window.__lab.run('!!playerCarGroup'), null, { polling: 200 });
    const ids = process.argv[2] ? process.argv[2].split(',') : await page.evaluate(() => [
      ...__lab.junctions().filter(j => j.reviewed).map(j => j.id), ...__lab.roads().filter(r => r.reviewed).map(r => r.id), ...__lab.events().map(e => e.id)]);
    const kerbs = {}, lines = {};
    for (const id of ids) {
      const r = await page.evaluate(id => __lab.run(`(()=>{
        let seed=12345;Math.random=()=>((seed=(seed*1664525+1013904223)>>>0)/4294967296);
        __lab.show(${JSON.stringify(id)});scene.updateMatrixWorld(true);
        const O=__lab.lab.origin,marks=[],roads=[],walks=[],kerbs=[];
        const shown=o=>{for(let q=o;q;q=q.parent)if(!q.visible)return false;return true;};
        state.roadSegments.forEach(r=>r.traverse(o=>{
          if(!o.isMesh||!shown(o))return;
          if(o.material?.color?.getHex()===BRAND.asphaltMarking&&!o.userData.crosswalk&&!o.userData.stopLine)marks.push(o);
          else if(o.userData.surface==='road'||o.userData.dirtSurface)roads.push(o);
          else if(o.userData.surface==='sidewalk'){
            walks.push(o);
            // Straight strips along the corridor beside x = 0.
            const b=new THREE.Box3().setFromObject(o),w=b.max.x-b.min.x,d=b.max.z-b.min.z;
            if(d<w||w>3.6||Math.abs(Math.abs(o.matrixWorld.elements[0])-1)>0.01)return;
            const inner=Math.min(Math.abs(b.min.x),Math.abs(b.max.x)),outer=Math.max(Math.abs(b.min.x),Math.abs(b.max.x));
            if(inner>3.5&&inner<4.6&&(Math.abs(inner-4.2)>0.01||(w>2.5&&Math.abs(outer-7.4)>0.01)))
              kerbs.push([o.geometry.type,+inner.toFixed(3),+outer.toFixed(3),+(b.min.z-O).toFixed(1)]);
          }
        }));
        const ray=new THREE.Raycaster(),down=new THREE.Vector3(0,-1,0);
        const hit=(list,x,z)=>{ray.set(new THREE.Vector3(x,5,z),down);return ray.intersectObjects(list,false).some(h=>!clippedAway(h.object.material,h.point));};
        const gaps=[];
        for(let dz=-40;dz<=40;dz+=0.5){const z=O+dz;
          if(!hit(roads,0,z)||!hit(roads,-4.1,z)||!hit(roads,4.1,z))continue;
          for(const sx of [-1,1]){
            if(hit(roads,sx*4.6,z)||hit(roads,sx*5.6,z))continue;      // a mouth
            if(!hit(walks,sx*4.4,z)&&!hit(roads,sx*4.1,z))continue;    // no kerb here
            if(hit(roads,sx*4.25,z))continue;                          // a wider road
            if(![3.95,3.9,4.0].some(x=>hit(marks,sx*x,z)))gaps.push([sx,dz]);
          }
        }
        return {kerbs,gaps};})()`), id);
      if (r.kerbs.length) kerbs[id] = r.kerbs;
      if (r.gaps.length) lines[id] = r.gaps.map(([sx, dz]) => (sx < 0 ? 'R' : 'L') + dz).join(' ');
    }
    console.log(JSON.stringify({ scenes: ids.length, kerbs, lines }));
    assert.deepEqual(kerbs, {}, 'pavement kerbs off the 4.2 / 7.4 m lines');
    assert.deepEqual(lines, {}, 'edge line missing along a kerb');
    assert.deepEqual(errors, []);
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
