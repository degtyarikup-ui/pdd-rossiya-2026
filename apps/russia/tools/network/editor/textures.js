// The game's textures: their numbers (game_godot/scenery/index.json), their pictures
// (game_godot/textures/detail/<kind>.png) and previews shaded the way the game shades them
// (game_godot/shaders/scenery.gdshader). A new picture (a ready style or a PNG) is tried out first and
// reaches the game on "Применить".
const Textures = (() => {
  const GROUPS = [
    { id: "ground", title: "Дороги и земля" },
    { id: "build", title: "Здания и предметы" },
    { id: "nature", title: "Природа" },
  ];
  const INFO = {
    asphalt: { name: "Асфальт", group: "ground", where: "Проезжая часть", base: "#2c2f36" },
    pavement: { name: "Тротуар", group: "ground", where: "Тротуары и островки", base: "#747970" },
    grass: { name: "Газон и земля", group: "ground", where: "Земля вокруг дорог", base: "#86a97a" },
    dirt: { name: "Грунт", group: "ground", where: "Грунтовая дорога", base: "#6f5840" },
    gravel: { name: "Гравий", group: "ground", where: "Гравийные покрытия", base: "#8a8270" },
    ballast: { name: "Щебень", group: "ground", where: "Щебёночная подушка", base: "#7d7a72" },
    sleeper: { name: "Шпалы", group: "ground", where: "Шпальный настил", base: "#5e4b3b" },
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
  // The limits match server.py TEXTURE_LIMITS.
  const PARAMS = {
    gain: { min: 0, max: 8 },
    macro: { min: 0, max: 0.5 },
    macroScale: { min: 0.01, max: 2 },
    period: { min: 0.4, max: 40 },
  };

  const state = { list: [], meta: {}, saved: {}, draft: {}, px: {}, pending: {} };

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
      state.meta[t.kind] = { width: t.width, height: t.height, backups: t.backups, ground: !!t.period, rev: Date.now() };
      state.saved[t.kind] = snapshot(t);
      state.draft[t.kind] = snapshot(t);
    }
    await Promise.all(state.list.map((t) => readPixels(t.kind)));
  }

  function pixelsOf(img) {
    const c = document.createElement("canvas");
    c.width = img.width; c.height = img.height;
    const x = c.getContext("2d");
    x.drawImage(img, 0, 0);
    const data = x.getImageData(0, 0, c.width, c.height).data;
    const n = c.width * c.height;
    const r = new Float32Array(n), g = new Float32Array(n), b = new Float32Array(n);
    for (let i = 0; i < n; i++) { r[i] = data[i * 4] / 255; g[i] = data[i * 4 + 1] / 255; b[i] = data[i * 4 + 2] / 255; }
    return { w: c.width, h: c.height, r, g, b };
  }
  function readPixels(kind, src) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => { const px = pixelsOf(img); if (!src) state.px[kind] = px; resolve(px); };
      img.onerror = () => { if (!src) state.px[kind] = null; resolve(null); };
      img.src = src || `/asset/texture/${kind}.png?v=${state.meta[kind]?.rev || 0}`;
    });
  }

  const isDirty = (kind) => !!state.pending[kind] || JSON.stringify(state.draft[kind]) !== JSON.stringify(state.saved[kind]);
  const dirtyKinds = () => Object.keys(state.draft).filter(isDirty);
  const draftOf = (kind) => state.draft[kind];
  const isGround = (kind) => !!state.meta[kind]?.ground;
  const metaOf = (kind) => state.meta[kind] || {};
  const pendingStyle = (kind) => state.pending[kind]?.style || "current";
  const pictureUrl = (kind) => state.pending[kind]?.url || null;

  function setParam(kind, key, value) {
    state.draft[kind][key] = value;
  }
  function reset(kind) {
    state.draft[kind] = { ...state.saved[kind] };
    delete state.pending[kind];
  }

  // A ready style: its picture tried out, and the numbers that suit it.
  function useStyle(kind, id) {
    if (id === "current") { delete state.pending[kind]; return; }
    const px = TexGen.build(kind, id);
    if (!px) return;
    const canvas = TexGen.toCanvas(px);
    state.pending[kind] = { style: id, px, url: canvas.toDataURL("image/png"), canvas };
    Object.assign(state.draft[kind], px.pick);
  }
  // A PNG of one's own.
  async function usePng(kind, file) {
    const url = await new Promise((resolve) => { const r = new FileReader(); r.onload = () => resolve(r.result); r.readAsDataURL(file); });
    const px = await readPixels(kind, url);
    if (!px) return App.toast("Не получилось прочитать картинку", "bad");
    if (px.w !== px.h) App.toast("Картинка не квадратная: лучше 256 × 256", "warn");
    state.pending[kind] = { style: "file", px, url, blob: file };
  }

  // Sends the picture (if a new one is tried) and the numbers to the game.
  async function save(kind) {
    try {
      const p = state.pending[kind];
      if (p) {
        const blob = p.blob || await new Promise((resolve) => p.canvas.toBlob(resolve, "image/png"));
        const r = await fetch(`/api/texture/${kind}/image`, { method: "POST", headers: { "Content-Type": "image/png" }, body: blob });
        const data = await r.json().catch(() => ({}));
        if (!r.ok) throw new Error(data.error || r.statusText);
        state.meta[kind] = { ...state.meta[kind], width: data.width, height: data.height, backups: (state.meta[kind].backups || 0) + 1, rev: Date.now() };
        state.px[kind] = p.px;
        delete state.pending[kind];
        if (!data.imported) App.toast("Godot не найден: картинка дойдёт до игры после открытия проекта в Godot", "warn");
      }
      const d = state.draft[kind];
      const body = { gain: d.gain, macro: d.macro, macroScale: d.macroScale };
      if (d.period !== undefined) body.period = d.period;
      await App.api(`/api/texture/${kind}`, body);
      state.saved[kind] = { ...d };
      App.toast(`«${INFO[kind]?.name || kind}» теперь в игре`, "good");
    } catch (e) {
      App.toast(`Не сохранено: ${e.message}`, "bad");
    }
  }
  async function restore(kind) {
    try {
      await App.api(`/api/texture/${kind}/restore`, {});
      state.meta[kind] = { ...state.meta[kind], backups: Math.max(0, (state.meta[kind].backups || 1) - 1), rev: Date.now() };
      delete state.pending[kind];
      await readPixels(kind);
      App.toast("Прежняя картинка вернулась", "good");
    } catch (e) {
      App.toast(e.message, "bad");
    }
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
  function shade(px, p, u, v) {
    const fine = 0.5 + (sample(px.r, px.w, px.h, u, v) - 0.5) * p.gain;
    const large = 0.5 + (sample(px.g, px.w, px.h, u * p.macroScale + 0.31, v * p.macroScale + 0.17) - 0.5) * p.gain;
    return { fine, large, final: fine * 2 * (1 + (large * 2 - 1) * p.macro) };
  }
  function paint(canvas, kind, px, p, tilesX, tilesY = tilesX) {
    if (!px || !p || !canvas) return;
    const W = canvas.width, H = canvas.height, ctx = canvas.getContext("2d"), img = ctx.createImageData(W, H);
    const [br, bg, bb] = hex(INFO[kind]?.base || "#9aa0a8");
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const s = shade(px, p, ((x + 0.5) / W) * tilesX, ((y + 0.5) / H) * tilesY).final;
        const i = (y * W + x) * 4;
        img.data[i] = clamp(br * s); img.data[i + 1] = clamp(bg * s); img.data[i + 2] = clamp(bb * s); img.data[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
  }
  // The texture as it will look: the tried picture if there is one.
  function draw(canvas, kind, view = "final", tiles = 2) {
    paint(canvas, kind, state.pending[kind]?.px || state.px[kind], state.draft[kind], tiles);
  }
  function drawStyle(canvas, kind, id) {
    const px = id === "current" ? state.px[kind] : TexGen.build(kind, id);
    const p = id === "current" ? state.saved[kind] : { ...state.draft[kind], ...(px && px.pick) };
    paint(canvas, kind, px, p, 1.5);
  }
  // A wide strip: several metres of the surface (ground kinds at their real tile size).
  function drawScene(canvas, kind) {
    const p = state.draft[kind];
    const metres = 12, tiles = p.period ? metres / p.period : 3;
    paint(canvas, kind, state.pending[kind]?.px || state.px[kind], p, tiles, tiles * canvas.height / canvas.width);
  }

  const forScene = () => Object.fromEntries(Object.keys(state.draft).map((k) => [k, { ...state.draft[k] }]));

  return {
    GROUPS, INFO, PARAMS, state, load, isDirty, dirtyKinds, draftOf, isGround, metaOf, pendingStyle, pictureUrl,
    setParam, reset, useStyle, usePng, save, restore, draw, drawStyle, drawScene, forScene,
  };
})();
