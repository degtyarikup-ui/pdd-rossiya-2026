// Quality tier of the device: 'low' | 'mid' | 'high'.
// Chosen from the GPU name (what actually draws the frame), not from cores or
// RAM: an 8-core, 8 GB budget phone (Honor X7b, Adreno 610) is a weak GPU. The
// name comes from WEBGL_debug_renderer_info; when it is hidden or unknown the
// old cores/memory guess decides. A forced tier (debug menu, "budget phone"
// simulation) is kept in localStorage under pddTier.
(function () {
  const PROFILES = {
    // antialias needs a new renderer, the rest can change while running.
    low:  { antialias: false, maxRatio: 1,    minRatio: 0.75, shadowMap: 512,  shadowRadius: 2, shadowSpan: 28, fpsCap: 30, leaves: 18 },
    mid:  { antialias: true,  maxRatio: 1.25, minRatio: 1,    shadowMap: 1024, shadowRadius: 3, shadowSpan: 36, fpsCap: 0,  leaves: 28 },
    high: { antialias: true,  maxRatio: 1.75, minRatio: 1.3,  shadowMap: 1024, shadowRadius: 5, shadowSpan: 40, fpsCap: 0,  leaves: 36 },
  };

  // Pure function of the GPU string: easy to test (tools/game_tests/game-quality-tier-test.cjs).
  function classifyGpu(name) {
    const s = String(name || '').toLowerCase();
    if (!s) return null;
    if (/swiftshader|llvmpipe|software|microsoft basic/.test(s)) return null; // no real GPU info
    let m = s.match(/adreno[^0-9]*([0-9]{3})/);
    if (m) {
      const n = +m[1];
      if (n >= 730) return 'high';          // 730, 740, 750 ...
      if (n >= 650 && n < 700) return 'high'; // 650, 660
      if (n >= 700) return 'mid';           // 710, 720
      if (n >= 620) return 'mid';           // 620, 630, 635, 640
      return 'low';                         // 5xx and 610/612/613/615/618/619
    }
    m = s.match(/(?:immortalis|mali)[^a-z0-9]*-?(g|t)?-?([0-9]{2,4})/);
    if (m) {
      const n = +m[2];
      if (/immortalis/.test(s) || (m[1] === 'g' && n >= 710)) return 'high';
      if (m[1] === 'g' && n >= 76) return n >= 710 ? 'high' : 'mid'; // G76, G77, G78, G68
      if (m[1] === 'g' && n === 68) return 'mid';
      return 'low';                         // G31, G51, G52, G57, T-series
    }
    if (/xclipse|apple/.test(s)) return 'high';
    if (/powervr|vivante|videocore/.test(s)) return 'low';
    if (/nvidia|geforce|radeon|intel|iris|uhd/.test(s)) return 'high'; // desktop browser
    return null;
  }

  function readGpu() {
    try {
      const gl = document.createElement('canvas').getContext('webgl2') || document.createElement('canvas').getContext('webgl');
      if (!gl) return '';
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      const name = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
      const lose = gl.getExtension('WEBGL_lose_context'); if (lose) lose.loseContext();
      return String(name || '');
    } catch (_) { return ''; }
  }

  function forced() {
    try { const v = localStorage.getItem('pddTier'); return PROFILES[v] ? v : null; } catch (_) { return null; }
  }

  function detect() {
    const gpu = readGpu();
    const byGpu = classifyGpu(gpu);
    const cores = navigator.hardwareConcurrency || 8, mem = navigator.deviceMemory || 8;
    const fallback = cores <= 2 || mem <= 3 ? 'low' : 'mid';
    const auto = byGpu || fallback;
    const tier = forced() || auto;
    return { tier, auto, forced: forced(), gpu, source: byGpu ? 'gpu' : 'fallback', profile: PROFILES[tier] };
  }

  window.PDD_QUALITY = {
    PROFILES, classifyGpu, detect,
    force(tier) { try { if (PROFILES[tier]) localStorage.setItem('pddTier', tier); else localStorage.removeItem('pddTier'); } catch (_) {} },
  };
})();
