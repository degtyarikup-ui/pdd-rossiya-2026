// The game's textures: their numbers (game_godot/scenery/index.json), their pictures
// (game_godot/textures/detail/<kind>.png) and a preview of each one shaded the way the game shades
// it (game_godot/shaders/scenery.gdshader). The editor edits the numbers and the picture files.
const Textures = (() => {
  const GROUPS = [
    { id: "ground", title: "Дороги и земля" },
    { id: "build", title: "Здания и предметы" },
    { id: "nature", title: "Природа" },
  ];
  // name: the Russian title; group: the list it sits in; where: what it covers in the game;
  // inScene: the editor's 3D view draws it (roads, pavements, lawns); base: a colour for the preview.
  const INFO = {
    asphalt: { name: "Асфальт", group: "ground", where: "Проезжая часть дорог и перекрёстков", inScene: true, base: "#2c2f36" },
    pavement: { name: "Тротуар", group: "ground", where: "Тротуары и островки безопасности", inScene: true, base: "#747970" },
    grass: { name: "Газон и земля", group: "ground", where: "Газоны, клумбы и земля вокруг дорог", inScene: true, base: "#86a97a" },
    gravel: { name: "Гравий", group: "ground", where: "Гравийные покрытия; в сети дорог не назначен", base: "#8a8270" },
    ballast: { name: "Щебень", group: "ground", where: "Щебёночная подушка; в сети дорог не назначен", base: "#7d7a72" },
    sleeper: { name: "Шпалы", group: "ground", where: "Шпальный настил; в сети дорог не назначен", base: "#5e4b3b" },
    plaster: { name: "Штукатурка", group: "build", where: "Фасады домов", base: "#e9e4d8" },
    panel: { name: "Панели", group: "build", where: "Панельные дома", base: "#c9c4b8" },
    brick: { name: "Кирпич", group: "build", where: "Кирпичные стены", base: "#a85a3c" },
    roofTile: { name: "Черепица", group: "build", where: "Скаты крыш", base: "#8b4b3a" },
    roofFlat: { name: "Плоская крыша", group: "build", where: "Плоские крыши", base: "#6e6e6e" },
    window: { name: "Окна", group: "build", where: "Окна зданий", base: "#7f98a8" },
    door: { name: "Двери", group: "build", where: "Двери зданий", base: "#7a5a3c" },
    wood: { name: "Дерево", group: "build", where: "Деревянные элементы", base: "#a9825a" },
    metal: { name: "Металл", group: "build", where: "Металлические элементы", base: "#8c939b" },
    deck: { name: "Настил", group: "build", where: "Настилы и площадки", base: "#9b7b57" },
    bark: { name: "Кора", group: "nature", where: "Стволы деревьев", base: "#5b4a3a" },
    leaves: { name: "Листва", group: "nature", where: "Кроны деревьев", base: "#4f8a3f" },
  };
  // What each number does, for the inspector (the limits match server.py TEXTURE_LIMITS).
  const PARAMS = {
    gain: { label: "Контраст зерна", min: 0, max: 8, step: 0.1, unit: "", hint: "Насколько заметна мелкая фактура. Меньше — ровнее цвет, больше — заметнее зерно." },
    macro: { label: "Пятна: сила", min: 0, max: 0.5, step: 0.01, unit: "", hint: "Крупные светлые и тёмные пятна на поверхности. 0 — пятен нет." },
    macroScale: { label: "Пятна: масштаб", min: 0.01, max: 2, step: 0.01, unit: "", hint: "Больше — пятна мельче и чаще." },
    period: { label: "Размер плитки", min: 0.4, max: 40, step: 0.1, unit: "м", hint: "Длина одного повтора рисунка на дороге или газоне. Меньше — рисунок мельче." },
  };

  const state = { list: [], meta: {}, saved: {}, draft: {}, px: {} };

  const snapshot = (t) => {
    const o = { gain: t.gain, macro: t.macro, macroScale: t.macroScale };
    if (t.period) o.period = t.period;
    return o;
  };
  const clamp = (v) => Math.max(0, Math.min(255, Math.round(v)));
  const hex = (c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));

  async function load() {
    state.list = await fetch("/api/textures").then((r) => r.json());
    for (const t of state.list) {
      state.meta[t.kind] = { width: t.width, height: t.height, backups: t.backups, ground: !!t.period };
      state.saved[t.kind] = snapshot(t);
      state.draft[t.kind] = snapshot(t);
    }
    await Promise.all(state.list.map((t) => ensurePixels(t.kind)));
  }

  // The picture as numbers in 0..1, read once: a 256 x 256 map is small.
  function ensurePixels(kind) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const c = document.createElement("canvas");
        c.width = img.width; c.height = img.height;
        const x = c.getContext("2d");
        x.drawImage(img, 0, 0);
        const data = x.getImageData(0, 0, c.width, c.height).data;
        const n = c.width * c.height;
        const r = new Float32Array(n), g = new Float32Array(n);
        for (let i = 0; i < n; i++) { r[i] = data[i * 4] / 255; g[i] = data[i * 4 + 1] / 255; }
        state.px[kind] = { w: c.width, h: c.height, r, g };
        resolve();
      };
      img.onerror = () => { state.px[kind] = null; resolve(); };
      img.src = `/asset/texture/${kind}.png?v=${state.meta[kind]?.rev || 0}`;
    });
  }

  async function reloadPicture(kind, meta = {}) {
    state.meta[kind] = { ...state.meta[kind], ...meta, rev: Date.now() };
    await ensurePixels(kind);
  }

  const isDirty = (kind) => JSON.stringify(state.draft[kind]) !== JSON.stringify(state.saved[kind]);
  const dirtyKinds = () => Object.keys(state.draft).filter(isDirty);
  const draftOf = (kind) => state.draft[kind];
  const savedOf = (kind) => state.saved[kind];
  const isGround = (kind) => !!state.meta[kind]?.ground;
  const metaOf = (kind) => state.meta[kind] || {};

  function setParam(kind, key, value) {
    state.draft[kind][key] = value;
  }
  function reset(kind) {
    state.draft[kind] = { ...state.saved[kind] };
  }
  function markSaved(kind) {
    state.saved[kind] = { ...state.draft[kind] };
  }

  // Bilinear lookup of a channel at (u, v) in tiles, wrapping like a repeating texture.
  function sample(ch, w, h, u, v) {
    const x = u * w - 0.5, y = v * h - 0.5;
    const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
    const ix = (n) => ((n % w) + w) % w, iy = (n) => ((n % h) + h) % h;
    const r0 = iy(y0) * w, r1 = iy(y0 + 1) * w;
    const a = ch[r0 + ix(x0)], b = ch[r0 + ix(x0 + 1)], c = ch[r1 + ix(x0)], d = ch[r1 + ix(x0 + 1)];
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  }

  // One point of a surface, the game's formula: fine grain x coarse patches, scaled by the gain.
  function shade(px, p, u, v) {
    const fine = 0.5 + (sample(px.r, px.w, px.h, u, v) - 0.5) * p.gain;
    const large = 0.5 + (sample(px.g, px.w, px.h, u * p.macroScale + 0.31, v * p.macroScale + 0.17) - 0.5) * p.gain;
    return { fine, large, final: fine * 2 * (1 + (large * 2 - 1) * p.macro) };
  }

  // Draws the texture as tiles x tiles repeats on a square canvas. view: "final" (on the kind's
  // colour, as the game shows it), "fine" (the grain only) or "large" (the patches only).
  function draw(canvas, kind, view = "final", tiles = 2) {
    const px = state.px[kind], p = state.draft[kind];
    if (!px || !p) return;
    const size = canvas.width;
    const ctx = canvas.getContext("2d");
    const img = ctx.createImageData(size, size);
    const [br, bg, bb] = hex(INFO[kind]?.base || "#9aa0a8");
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const s = shade(px, p, ((x + 0.5) / size) * tiles, ((y + 0.5) / size) * tiles);
        let r, g, b;
        if (view === "fine" || view === "large") {
          r = g = b = clamp((view === "fine" ? s.fine : s.large) * 255);
        } else {
          r = clamp(br * s.final); g = clamp(bg * s.final); b = clamp(bb * s.final);
        }
        const i = (y * size + x) * 4;
        img.data[i] = r; img.data[i + 1] = g; img.data[i + 2] = b; img.data[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
  }

  // The numbers the 3D view needs, for every texture (it uses the three it draws).
  const forScene = () => Object.fromEntries(Object.keys(state.draft).map((k) => [k, { ...state.draft[k] }]));

  return {
    GROUPS, INFO, PARAMS, state, load, reloadPicture, isDirty, dirtyKinds, draftOf, savedOf, isGround, metaOf,
    setParam, reset, markSaved, draw, forScene, ensurePixels,
  };
})();
