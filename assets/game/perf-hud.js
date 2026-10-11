// Performance probe (off by default; Flutter turns it on from the hidden debug
// sheet: setPerfHud). Measures what a player feels on a weak phone: frame rate,
// the longest frame, how many frames were over 33 ms, the draw load from
// renderer.info and the JS-side delay from a press to the frame that shows it.
// Every 5 s one summary line also goes to Flutter ({event:'perf'}) so a build
// on a real phone can be read from logcat without looking at the screen.
(function () {
  let renderer = null, send = null, box = null, on = false;
  let gpu = '', tier = '';
  let last = 0, frames = 0, sum = 0, worst = 0, slow = 0, cpuSum = 0, cpuWorst = 0;
  let windowStart = 0, report = 0, inputLat = 0, inputWorst = 0, pendingInput = 0;
  let frameStart = 0;

  function gpuName() {
    try {
      const gl = renderer.getContext();
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      return ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : String(gl.getParameter(gl.RENDERER));
    } catch (_) { return ''; }
  }

  function ensureBox() {
    if (box) return;
    box = document.createElement('div');
    box.style.cssText = 'position:absolute;left:6px;top:calc(env(safe-area-inset-top,0px) + 64px);z-index:200;' +
      'pointer-events:none;font:11px/1.35 monospace;color:#fff;background:rgba(0,0,0,.62);padding:4px 6px;' +
      'border-radius:6px;white-space:pre;display:none';
    document.body.appendChild(box);
  }

  const api = {
    init(r, sendFn) { renderer = r; send = sendFn; },
    get enabled() { return on; },
    set(value) {
      on = Boolean(value);
      ensureBox();
      box.style.display = on ? 'block' : 'none';
      last = 0; frames = 0; sum = worst = slow = cpuSum = cpuWorst = 0; windowStart = report = 0;
      if (on && !gpu && renderer) gpu = gpuName();
    },
    // A press just arrived (event.timeStamp, same clock as rAF).
    setTier(t) { tier = t; },
    input(ts) { if (on) pendingInput = ts || performance.now(); },
    begin(now) {
      if (!on) return;
      frameStart = performance.now();
    },
    end(now) {
      if (!on) return;
      // Frames are counted where a picture was actually drawn (a capped frame
      // returns early and never gets here), by the time between two drawings.
      if (last) {
        const dt = now - last;
        frames++; sum += dt; if (dt > worst) worst = dt; if (dt > 33.5) slow++;
      }
      last = now;
      if (!windowStart) windowStart = now;
      const cpu = performance.now() - frameStart;
      cpuSum += cpu; if (cpu > cpuWorst) cpuWorst = cpu;
      if (pendingInput) {
        inputLat = performance.now() - pendingInput; pendingInput = 0;
        if (inputLat > inputWorst) inputWorst = inputLat;
      }
      if (now - windowStart < 1000 || !frames) return;
      const avg = sum / frames, info = renderer.info;
      const stats = {
        fps: Math.round(1000 / avg), avgMs: +avg.toFixed(1), worstMs: Math.round(worst), slowFrames: slow,
        cpuMs: +(cpuSum / frames).toFixed(1), cpuWorstMs: Math.round(cpuWorst),
        calls: info.render.calls, tris: info.render.triangles, geoms: info.memory.geometries,
        textures: info.memory.textures, ratio: +renderer.getPixelRatio().toFixed(2),
        inputMs: Math.round(inputLat), inputWorstMs: Math.round(inputWorst), gpu, tier,
      };
      box.textContent =
        `${stats.fps} fps  ${stats.avgMs} ms (worst ${stats.worstMs}, slow ${stats.slowFrames})\n` +
        `cpu ${stats.cpuMs} ms (worst ${stats.cpuWorstMs})  calls ${stats.calls}  tris ${(stats.tris / 1000).toFixed(0)}k\n` +
        `geom ${stats.geoms}  tex ${stats.textures}  ratio ${stats.ratio}  tier ${tier}\n` +
        `input ${stats.inputMs} ms (worst ${stats.inputWorstMs})\n${gpu}`;
      if (!report) report = now;
      if (now - report >= 5000 && send) { report = now; send({ event: 'perf', ...stats }); inputWorst = 0; }
      frames = 0; sum = worst = slow = cpuSum = cpuWorst = 0; windowStart = now;
    },
  };
  window.PDD_PERF = api;
})();
