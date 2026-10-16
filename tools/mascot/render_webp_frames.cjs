#!/usr/bin/env node
/** Offline, deterministic RGBA renders of the approved GLB studio preview.
 * Requires Playwright on NODE_PATH and tools/mascot/serve_model.py running.
 * No renderer or JavaScript runtime is shipped with the resulting WebP.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, 'output/mascot/webp-source');
const width = 384;
const framingScale = 1.08;
const horizontalFramingOffset = .20;
const durationMs = 7200;
const rates = [24, 30];
const model = path.join(root, 'assets/mascot/3d/cone-juggling.glb');
const hash = crypto.createHash('sha256').update(fs.readFileSync(model)).digest('hex');
const fingerprint = crypto.createHash('sha256').update(hash).update(JSON.stringify({framingScale,horizontalFramingOffset}))
  .update(fs.readFileSync(path.join(__dirname,'juggling_viewer.html'))).digest('hex');
const plan = {};
const ticks = new Set();
for (const fps of rates) {
  plan[fps] = Array.from({length: Math.ceil(durationMs * fps / 1000)}, (_, index) => {
    const tick = index * (120 / fps);
    ticks.add(tick);
    const startMs = Math.round(index * 1000 / fps);
    const endMs = Math.min(durationMs, Math.round((index + 1) * 1000 / fps));
    return {tick, timeSeconds: tick / 120, durationMs: endMs - startMs,
      file: `frame-${String(tick).padStart(4, '0')}.png`};
  });
}
fs.mkdirSync(output, {recursive:true});
const metadataPath = path.join(output, 'source.json');
const previous = fs.existsSync(metadataPath) ? JSON.parse(fs.readFileSync(metadataPath, 'utf8')) : null;
if (previous && (previous.renderFingerprint !== fingerprint || previous.width !== width)) {
  throw new Error('Source model or resolution changed. Move output/mascot/webp-source before rendering again.');
}
(async () => {
  const browser = await chromium.launch({channel:'chrome', headless:true, args:['--enable-unsafe-swiftshader']});
  try {
    const page = await browser.newPage({viewport:{width:1100,height:1000},deviceScaleFactor:1});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const captureURL = new URL(process.env.MASCOT_PREVIEW_URL || 'http://127.0.0.1:8794/juggling.html');
    captureURL.searchParams.set('capture','1');
    await page.goto(captureURL.toString());
    await page.waitForFunction(() => window.jugglingScene?.ready || window.jugglingScene?.error, undefined, {timeout:60000});
    const state = await page.evaluate(() => window.jugglingScene.snapshot());
    if (state.error) throw new Error(state.error);
    const alpha = await page.evaluate(() => window.jugglingScene.renderer.getContext().getContextAttributes().alpha);
    if (!alpha) throw new Error('The export WebGL context is not transparent.');
    await page.evaluate(({scale,offset}) => {
      const {camera,controls} = window.jugglingScene;
      camera.position.sub(controls.target).multiplyScalar(scale).add(controls.target);
      const shift = new THREE.Vector3(1,0,0).applyQuaternion(camera.quaternion).multiplyScalar(offset);
      camera.position.add(shift);
      controls.target.add(shift);
      camera.updateMatrixWorld();
    },{scale:framingScale,offset:horizontalFramingOffset});
    const ordered = [...ticks].sort((a,b) => a-b);
    for (let index = 0; index < ordered.length; index++) {
      const tick = ordered[index];
      const file = path.join(output, `frame-${String(tick).padStart(4, '0')}.png`);
      if (!fs.existsSync(file)) {
        const data = await page.evaluate(({time, width}) => window.jugglingScene.captureFrame(time, width), {time:tick/120,width});
        fs.writeFileSync(file, Buffer.from(data.split(',')[1], 'base64'));
      }
      if (index % 30 === 0 || index === ordered.length-1) console.log(`RGBA frames ${index+1}/${ordered.length}`);
    }
    if (errors.length) throw new Error(errors.join('\n'));
    const metadata = {version:1,modelSha256:hash,renderFingerprint:fingerprint,width,height:width,durationMs,
      transparent:true,camera:'approved front studio view',
      framingScale,horizontalFramingOffset,
      shadow:'black alpha, opacity 0.2, no baked background',rates,frames:plan};
    fs.writeFileSync(metadataPath, JSON.stringify(metadata,null,2)+'\n');
    console.log(`Rendered ${ordered.length} unique RGBA frames into ${output}`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
