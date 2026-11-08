// Ready styles for the game's detail maps (textures/detail/<kind>.png, 256 x 256, seamless):
// R = the fine detail of top faces, G = large patches (sampled at macroScale), B = the detail of
// walls. 0.5 keeps the colour; the shader multiplies the difference by the kind's gain.
// Every style is drawn here, tileable, from a seed: no files to look for.
const TexGen = (() => {
  const N = 256;

  function rng(seed) {
    let s = seed >>> 0 || 1;
    return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) % 100000) / 100000; };
  }

  // Value noise on a periodic lattice (cells x cells over the tile): wraps at the edges.
  function noise(cells, seed) {
    const r = rng(seed), lat = new Float32Array(cells * cells);
    for (let i = 0; i < lat.length; i++) lat[i] = r();
    const out = new Float32Array(N * N);
    const s = (t) => t * t * (3 - 2 * t);
    for (let y = 0; y < N; y++) {
      const fy = (y / N) * cells, y0 = Math.floor(fy), ty = s(fy - y0);
      for (let x = 0; x < N; x++) {
        const fx = (x / N) * cells, x0 = Math.floor(fx), tx = s(fx - x0);
        const a = lat[(y0 % cells) * cells + (x0 % cells)], b = lat[(y0 % cells) * cells + ((x0 + 1) % cells)];
        const c = lat[((y0 + 1) % cells) * cells + (x0 % cells)], d = lat[((y0 + 1) % cells) * cells + ((x0 + 1) % cells)];
        out[y * N + x] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
      }
    }
    return out;
  }
  function fbm(base, octaves, gain, seed) {
    const out = new Float32Array(N * N);
    let amp = 1, total = 0;
    for (let o = 0; o < octaves; o++) {
      const n = noise(base << o, seed + o * 101);
      for (let i = 0; i < out.length; i++) out[i] += n[i] * amp;
      total += amp;
      amp *= gain;
    }
    for (let i = 0; i < out.length; i++) out[i] /= total;
    return out;
  }
  // Pixel noise (white), for grain.
  function grain(seed) {
    const r = rng(seed), out = new Float32Array(N * N);
    for (let i = 0; i < out.length; i++) out[i] = r();
    return out;
  }
  // Box blur that wraps (twice: close to a gaussian).
  function blur(a, rad) {
    if (rad < 1) return a;
    let src = a;
    for (let pass = 0; pass < 2; pass++) {
      const tmp = new Float32Array(N * N), out = new Float32Array(N * N), w = 2 * rad + 1;
      for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
        let sum = 0;
        for (let k = -rad; k <= rad; k++) sum += src[y * N + ((x + k + N) % N)];
        tmp[y * N + x] = sum / w;
      }
      for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
        let sum = 0;
        for (let k = -rad; k <= rad; k++) sum += tmp[((y + k + N) % N) * N + x];
        out[y * N + x] = sum / w;
      }
      src = out;
    }
    return src;
  }
  // Around 0.5 with the given spread (standard deviation).
  function spread(a, sd) {
    let m = 0;
    for (const v of a) m += v;
    m /= a.length;
    let v2 = 0;
    for (const v of a) v2 += (v - m) * (v - m);
    const k = sd / (Math.sqrt(v2 / a.length) || 1);
    const out = new Float32Array(a.length);
    for (let i = 0; i < a.length; i++) out[i] = Math.max(0, Math.min(1, 0.5 + (a[i] - m) * k));
    return out;
  }
  const mix = (a, b, t) => a.map((v, i) => v * (1 - t) + b[i] * t);

  // Joints of tiles or bricks: darker lines `width` pixels wide, softened. rows x cols cells over the tile,
  // every other row shifted by `offset` of a cell (bricks); cols 0 = only the rows (roof tiles).
  function joints(rows, cols, offset, width, soft) {
    const out = new Float32Array(N * N);
    for (let y = 0; y < N; y++) {
      const ry = (y / N) * rows, row = Math.floor(ry), fy = ry - row;
      const dy = Math.min(fy, 1 - fy) * (N / rows);
      for (let x = 0; x < N; x++) {
        let dx = Infinity;
        if (cols) {
          let rx = (x / N) * cols + (row % 2 ? offset : 0);
          rx -= Math.floor(rx);
          dx = Math.min(rx, 1 - rx) * (N / cols);
        }
        out[y * N + x] = Math.min(dx, dy) < width / 2 ? 0 : 1;
      }
    }
    return blur(out, soft);
  }

  // One shade per tile, brick or plank (the same cells as joints()): a quiet, even variation.
  function cells(rows, cols, offset, sd, seed) {
    const out = new Float32Array(N * N);
    const hash = (a, b) => { let h = (a * 374761393 + b * 668265263 + seed * 2147483647) | 0; h = (h ^ (h >>> 13)) * 1274126177; return ((h ^ (h >>> 16)) >>> 0) / 4294967295; };
    for (let y = 0; y < N; y++) {
      const row = Math.floor((y / N) * rows);
      for (let x = 0; x < N; x++) {
        let rx = cols ? (x / N) * cols + (row % 2 ? offset : 0) : 0;
        const col = cols ? ((Math.floor(rx) % cols) + cols) % cols : 0;
        out[y * N + x] = (hash(row, col) - 0.5) * 2 * sd;
      }
    }
    return out;
  }
  // Tiles: 0.5 plus each tile's shade, darker joints. depth: how much darker a joint is.
  function tiles(rows, cols, offset, width, depth, sd, seed) {
    const j = joints(rows, cols, offset, width, 1), c = cells(rows, cols, offset, sd, seed);
    return j.map((v, i) => 0.5 + c[i] - (1 - v) * depth);
  }
  const flat = (seed, sd, rad = 2) => spread(blur(fbm(16, 2, 0.5, seed), rad), sd);
  const patches = (seed, sd) => spread(fbm(3, 3, 0.5, seed + 7), sd);
  // Minimal: almost even colour, a calm large variation, clean joints where the material has them.
  // Made for gain 1 (the picture's numbers are the contrast itself).
  const MINIMAL = {
    asphalt: (s) => ({ r: flat(s, 0.006), g: patches(s, 0.12), pick: { gain: 1, macro: 0.04 } }),
    pavement: (s) => { const t = tiles(4, 4, 0, 3, 0.07, 0.022, s); return { r: t, b: t, g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }; },
    grass: (s) => ({ r: flat(s, 0.006), g: patches(s, 0.16), pick: { gain: 1, macro: 0.07 } }),
    gravel: (s) => ({ r: flat(s, 0.02, 1), g: patches(s, 0.1), pick: { gain: 1, macro: 0.04 } }),
    ballast: (s) => ({ r: flat(s, 0.02, 1), g: patches(s, 0.1), pick: { gain: 1, macro: 0.04 } }),
    plaster: (s) => ({ r: flat(s, 0.005), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    panel: (s) => ({ r: tiles(3, 2, 0, 3, 0.05, 0.015, s), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    brick: (s) => ({ r: tiles(16, 8, 0.5, 3, 0.06, 0.02, s), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    roofTile: (s) => ({ r: tiles(10, 0, 0, 4, 0.06, 0.015, s), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    roofFlat: (s) => ({ r: flat(s, 0.005), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    wood: (s) => ({ r: tiles(2, 6, 0.5, 2, 0.05, 0.02, s), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    deck: (s) => ({ r: tiles(2, 6, 0.5, 2, 0.05, 0.02, s), g: patches(s, 0.1), pick: { gain: 1, macro: 0.03 } }),
    metal: (s) => ({ r: flat(s, 0.005), g: patches(s, 0.08), pick: { gain: 1, macro: 0.02 } }),
    leaves: (s) => ({ r: flat(s, 0.015), g: patches(s, 0.12), pick: { gain: 1, macro: 0.05 } }),
    bark: (s) => ({ r: flat(s, 0.012), g: patches(s, 0.08), pick: { gain: 1, macro: 0.02 } }),
  };

  // The styles a kind offers. pick: the numbers that suit the picture (gain, macro).
  const BASE = [
    // Fine, but without the pixel-sharp sparkle: grain softened by a pixel, quiet patches.
    { id: "soft", title: "Мягкая", make: (seed) => ({ r: spread(blur(mix(grain(seed), fbm(32, 2, 0.5, seed), 0.5), 1), 0.025), g: spread(fbm(4, 3, 0.5, seed + 7), 0.14) }), pick: { gain: 2.0, macro: 0.06 } },
    { id: "smooth", title: "Гладкая", make: (seed) => ({ r: spread(blur(fbm(32, 2, 0.5, seed), 2), 0.015), g: spread(fbm(3, 2, 0.5, seed + 7), 0.12) }), pick: { gain: 1.2, macro: 0.04 } },
    { id: "grain", title: "Зерно", make: (seed) => ({ r: spread(mix(grain(seed), fbm(32, 2, 0.5, seed), 0.5), 0.03), g: spread(fbm(4, 3, 0.5, seed + 7), 0.16) }), pick: { gain: 3.5, macro: 0.12 } },
  ];
  // Compacted earth, small stones and irregular worn patches, on a seamless world tile.
  // Medium-scale clumps stay visible at the overhead camera; fine grit fades in the shared shader.
  function earth(seed) {
    const coarse = fbm(3, 3, 0.55, seed), clumps = fbm(18, 3, 0.5, seed + 23);
    const grit = blur(grain(seed + 47), 1), worn = noise(5, seed + 61);
    const r = new Float32Array(N * N);
    for (let i = 0; i < r.length; i++) {
      const stone = Math.max(0, clumps[i] - 0.6) * 0.8;
      r[i] = 0.5 + (coarse[i] - 0.5) * 0.30 + (clumps[i] - 0.5) * 0.24
        + (grit[i] - 0.5) * 0.18 + stone - Math.max(0, 0.38 - worn[i]) * 0.25;
    }
    return { r: spread(r, 0.065), g: spread(fbm(3, 4, 0.55, seed + 7), 0.18) };
  }
  const EXTRA = {
    dirt: [{ id: "earth", title: "Укатанный грунт", make: earth, pick: { gain: 1.0, macro: 0.24, macroScale: 0.35, period: 4.8 } }],
    pavement: [{ id: "tiles", title: "Плитка", make: (seed) => ({ r: spread(mix(joints(8, 8, 0, 2, 1), blur(fbm(16, 2, 0.5, seed), 2), 0.25), 0.035), g: spread(fbm(4, 3, 0.5, seed + 7), 0.12) }), pick: { gain: 2.4, macro: 0.06 } }],
    brick: [{ id: "bricks", title: "Кладка", make: (seed) => ({ r: spread(mix(joints(16, 8, 0.5, 3, 1), blur(fbm(16, 2, 0.5, seed), 1), 0.2), 0.06), g: spread(fbm(4, 3, 0.5, seed + 7), 0.14) }), pick: { gain: 1.4, macro: 0.06 } }],
    roofTile: [{ id: "rows", title: "Ряды", make: (seed) => ({ r: spread(mix(joints(12, 0, 0, 4, 2), blur(fbm(16, 2, 0.5, seed), 1), 0.3), 0.045), g: spread(fbm(4, 3, 0.5, seed + 7), 0.14) }), pick: { gain: 1.3, macro: 0.05 } }],
    grass: [{ id: "meadow", title: "Луг", make: (seed) => ({ r: spread(blur(fbm(24, 3, 0.55, seed), 1), 0.035), g: spread(fbm(3, 4, 0.55, seed + 7), 0.2) }), pick: { gain: 1.2, macro: 0.14 } }],
  };

  const styles = (kind) => [{ id: "current", title: "Сейчас" },
    ...(MINIMAL[kind] ? [{ id: "minimal", title: "Минимал", make: MINIMAL[kind] }] : []), ...BASE, ...(EXTRA[kind] || [])];
  const cache = new Map();
  // The style's channels as numbers 0..1 ({ w, h, r, g, b }) and the numbers it suits.
  function build(kind, id) {
    const key = kind + "|" + id;
    if (!cache.has(key)) {
      const st = styles(kind).find((s) => s.id === id);
      if (!st || !st.make) return null;
      const seed = [...kind].reduce((a, c) => a * 31 + c.charCodeAt(0), 7) & 0xffff;
      const made = st.make(seed);
      cache.set(key, { w: N, h: N, r: made.r, g: made.g, b: made.b || made.r, pick: made.pick || st.pick });
    }
    return cache.get(key);
  }
  // The channels as a PNG data URL (and a Blob for the upload).
  function toCanvas(px) {
    const c = document.createElement("canvas");
    c.width = px.w; c.height = px.h;
    const ctx = c.getContext("2d"), img = ctx.createImageData(px.w, px.h);
    for (let i = 0; i < px.w * px.h; i++) {
      img.data[i * 4] = Math.round(px.r[i] * 255);
      img.data[i * 4 + 1] = Math.round(px.g[i] * 255);
      img.data[i * 4 + 2] = Math.round((px.b || px.r)[i] * 255);
      img.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    return c;
  }

  return { styles, build, toCanvas, N };
})();

if (typeof module !== "undefined" && module.exports) module.exports = TexGen;
