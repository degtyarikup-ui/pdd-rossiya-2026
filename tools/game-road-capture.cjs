// Capture the real road scenes (game camera and close-ups) for before/after galleries.
// PASS=before|after  GAME_LAB_URL=http://127.0.0.1:8941  SHOTS=id,id (optional filter)
// The lab server only reads review/edit files; this script never posts to it.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const PASS = process.env.PASS || 'after';
const OUT = path.join('output/game-textures/roads', PASS + (process.env.SEASON ? '-' + process.env.SEASON : ''));
const SEASON = process.env.SEASON || 'summer';
const URL = (process.env.GAME_LAB_URL || 'http://127.0.0.1:8941') + '/game/index.html';

// Close-up cameras are orthographic like the game: size = visible height in metres.
// z is measured from the scene origin (junction centre, question stop line or crossing).
const SCENES = [
  { id: 'straight', label: 'Прямая дорога', build: 'straight', close: [
    { name: 'curb', x: -6.2, z: 0, size: 7, yaw: 0.5, pitch: 0.82 },
    { name: 'lanes', x: -1.8, z: 0, size: 8, yaw: 0.2, pitch: 0.9 } ] },
  { id: 'ticket_1_13', label: 'Перекрёсток', close: [
    { name: 'corner', x: -8.6, z: -8.6, size: 11, yaw: 0.45, pitch: 0.85 },
    { name: 'centre', x: 0, z: 0, size: 9, yaw: 0.25, pitch: 0.95 },
    { name: 'seam', x: -3.5, z: -26, size: 7, yaw: 0.5, pitch: 0.85 } ] },
  // U-turn: the world is rebased by 180° and the next junction is built in
  // the new coordinates; the close-up shows the seam where it meets the road.
  { id: 'uturn', label: 'После разворота мира', build: 'uturn', close: [
    { name: 'seam', x: 3.5, z: 0, size: 8, yaw: 0.5, pitch: 0.85, at: 'seamZ' } ] },
  { id: 'ticket_20_14', label: 'Т-образный перекрёсток', close: [
    { name: 'corner', x: 8.6, z: -8.6, size: 11, yaw: -0.45, pitch: 0.85 } ] },
  { id: 'ticket_15_15', label: 'Косой перекрёсток', close: [
    { name: 'mouth', x: 6, z: 6, size: 12, yaw: 0.2, pitch: 0.85 } ] },
  { id: 'ticket_16_14', label: 'Кольцо', close: [
    { name: 'island', x: 0, z: -9, size: 12, yaw: 0.2, pitch: 0.85 },
    { name: 'flare', x: -8.5, z: -15, size: 12, yaw: 0.5, pitch: 0.85 } ] },
  { id: 'ticket_22_13', label: 'Разделённая главная дорога', close: [
    { name: 'median', x: 0, z: -13, size: 12, yaw: 0.35, pitch: 0.85 } ] },
  { id: 'ticket_27_9', label: 'Разделительный островок', close: [
    { name: 'island', x: 12, z: 0, size: 14, yaw: 0.35, pitch: 0.85 } ] },
  { id: 'ticket_21_15', label: 'Грунтовый съезд', close: [
    { name: 'mouth', x: 9, z: 0, size: 12, yaw: -0.5, pitch: 0.85 },
    { name: 'transition', x: 15, z: 0, size: 12, yaw: -0.5, pitch: 0.85 } ] },
  { id: 'ticket_21_8', label: 'Въезд во двор', close: [
    { name: 'driveway', x: -8, z: 9, size: 12, yaw: 0.4, pitch: 0.85 } ] },
  { id: 'ticket_28_2', label: 'Три проезжие части', close: [
    { name: 'islands', x: 8, z: 0, size: 14, yaw: 0.35, pitch: 0.85 } ] },
  { id: 'road_15_3', label: 'Изгиб дороги', close: [
    { name: 'bend', x: -3, z: 18, size: 16, yaw: 0.2, pitch: 0.85 } ] },
  { id: 'road_2_16', label: 'Железнодорожный переезд', close: [
    { name: 'deck', x: 0, z: 0, size: 12, yaw: 0.4, pitch: 0.85, at: 'crossingZ', hideActors: true },
    { name: 'ballast', x: 12, z: 0, size: 10, yaw: 0.4, pitch: 0.85, at: 'crossingZ', hideActors: true } ] },
  { id: 'road_20_16', label: 'Переезд с тротуарами', close: [
    { name: 'pavement', x: 6, z: 0, size: 11, yaw: 0.4, pitch: 0.85, at: 'crossingZ', hideActors: true } ] },
  { id: 'road_6_10', label: 'Автомагистраль и разделитель', close: [
    { name: 'median', x: 4, z: 60, size: 16, yaw: 0.3, pitch: 0.85 } ] },
  { id: 'road_29_3', label: 'Загородная дорога', close: [
    { name: 'shoulder', x: -4.5, z: 6, size: 9, yaw: 0.4, pitch: 0.85 } ] },
  { id: 'road_2_11', label: 'Боковая дорога', close: [
    { name: 'junction', x: -9, z: -9, size: 12, yaw: 0.4, pitch: 0.85, at: 'junctionZ' } ] },
  { id: 'event_busstop', label: 'Автобусный карман', close: [
    { name: 'bay', x: 6, z: 0, size: 11, yaw: 0.4, pitch: 0.85 } ] },
];

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ headless: true,
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    args: ['--use-angle=swiftshader'] });
  const records = [];
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
    if (process.env.BASELINE) {
      // The engine as it was before this pass (saved copy), with the lab hook.
      const src = 'output/game-textures/roads/baseline-src/', mark = '  // Run init on DOM ready';
      const hook = fs.readFileSync('tools/game_lab/lab-hook.js', 'utf8');
      await page.route('**/game/game.js', r => r.fulfill({ contentType: 'application/javascript',
        body: fs.readFileSync(src + 'baseline-game.js', 'utf8').replace(mark, hook + '\n' + mark) }));
      await page.route('**/game/index.html', r => r.fulfill({ contentType: 'text/html', body: fs.readFileSync(src + 'baseline-index.html', 'utf8') }));
    }
    await page.goto(URL);
    await page.waitForFunction(() => window.__lab && window.__lab.run('!!playerCarGroup'), null, { polling: 200 });
    const only = process.env.SHOTS ? new Set(process.env.SHOTS.split(',')) : null;
    for (const scene of SCENES) {
      if (only && !only.has(scene.id)) continue;
      const ready = await page.evaluate(({ id, build, SEASON }) => __lab.run(`(()=>{
        let seed=12345;Math.random=()=>((seed=(seed*1664525+1013904223)>>>0)/4294967296);
        window.__roadShot={};
        window.game.setSeason(${JSON.stringify(SEASON)});
        __lab.lab.freeCam=false;
        ${build === 'straight' ? `
          resetGame();state.attract=false;state.roadSegments.forEach(disposeSegment);
          state.roadSegments=[];state.actors=[];state.intersections=[];state.ambient=[];state.activeIntersection=null;state.occluders=[];state.roadEvent=null;state.exitRoad=currentCorridor=null;
          const seg=buildStraightSegment(-45,200,true);state.roadSegments.push(seg);state.exitRoad=currentCorridor=seg;nextSegmentZ=155;
          __lab.lab.origin=40;__lab.lab.id='straight';playerCarGroup.visible=true;
          playerCarGroup.position.set(-1.8,0,25);playerCarGroup.rotation.set(0,0,0);state.paused=true;
          state.viewportInsets={top:110,bottom:300};state.viewportTarget=null;
          for(let i=0;i<200;i++)updateCamera(1/60);
        ` : build === 'uturn' ? `
          __lab.show('ticket_1_13');state.paused=true;
          const it=state.intersections[0];playerCarGroup.position.set(1.8,0,it.startZ-40);playerCarGroup.rotation.set(0,Math.PI,0);
          state.isAtSituation=false;state.resolution=null;
          maybeReverseWorld(true);
          const ends=corridorWorldEnds();window.__roadShot.seamZ=Math.max(...ends.map(p=>p.z));
          state.viewportInsets={top:110,bottom:300};state.viewportTarget=null;for(let i=0;i<200;i++)updateCamera(1/60);
          __lab.lab.origin=playerCarGroup.position.z;
        ` : `__lab.show(${JSON.stringify(id)});state.paused=true;state.viewportInsets={top:110,bottom:300};state.viewportTarget=null;for(let i=0;i<200;i++)updateCamera(1/60);`}
        applyWeather();
        window.__roadShot.origin=__lab.lab.origin;window.__roadShot.seamZ=window.__roadShot.seamZ;
        window.__roadShot.crossingZ=state.roadEvent&&state.roadEvent.crossingZ;
        window.__roadShot.junctionZ=state.roadEvent&&state.roadEvent.junctionZ;
        return true;})()`), { ...scene, SEASON });
      if (!ready) throw new Error('scene did not build: ' + scene.id);
      const shoot = async (name, code) => {
        const data = await page.evaluate(code => __lab.run(code), code);
        fs.writeFileSync(path.join(OUT, `${scene.id}-${name}.png`), Buffer.from(data.split(',')[1], 'base64'));
        records.push({ scene: scene.id, view: name, label: scene.label });
      };
      await shoot('game', `(()=>{__lab.lab.freeCam=false;renderer.render(scene,camera);return renderer.domElement.toDataURL('image/png');})()`);
      for (const c of scene.close) {
        await shoot(c.name, `(()=>{const o=__lab.lab.orbit,base=${c.at ? `window.__roadShot.${c.at}` : 'window.__roadShot.origin'};
          __lab.lab.freeCam=true;o.target.set(${c.x},0,base+${c.z});o.size=${c.size};o.yaw=${c.yaw};o.pitch=${c.pitch};o.dist=80;
          updateCamera(1/60);const hidden=[];${c.hideActors?`state.roadSegments.forEach(r=>r.traverse(o=>{if(o.userData.actor&&o.visible){o.visible=false;hidden.push(o);}}));`:''}renderer.render(scene,camera);const url=renderer.domElement.toDataURL('image/png');hidden.forEach(o=>o.visible=true);return url;})()`);
      }
      console.log('captured', scene.id);
    }
    const metrics = await page.evaluate(() => __lab.run(`({calls:renderer.info.render.calls,triangles:renderer.info.render.triangles,textures:renderer.info.memory.textures,geometries:renderer.info.memory.geometries})`));
    // A partial run (SHOTS) replaces only its own scenes in the list.
    const file = path.join(OUT, 'capture.json');
    if (only && fs.existsSync(file)) {
      const old = JSON.parse(fs.readFileSync(file, 'utf8')).records;
      const merged = SCENES.flatMap(sc => only.has(sc.id) ? records.filter(r => r.scene === sc.id) : old.filter(r => r.scene === sc.id));
      records.splice(0, records.length, ...merged);
    }
    fs.writeFileSync(file, JSON.stringify({ pass: PASS, records, last: metrics, errors }, null, 2));
    if (errors.length) console.log('page errors', errors);
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
