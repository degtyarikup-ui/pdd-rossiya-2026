// The editor's core: the open scene and its history, the selection, saving, the keys. The view is in
// scene3d.js, what the pointer does in tools.js, the panels in panels.js and inspector.js, the test
// drive in sim.js. Everything edits the scene through App.edit(), which keeps undo and the road plan.
const App = (() => {
  const $ = (s) => document.querySelector(s);
  const esc = (v) => String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const ic = (name, cls = "") => `<svg class="i ${cls}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const r3 = (v) => Math.round(v * 1000) / 1000;

  const state = {
    S: null, id: null, build: null, findings: [], edges: null, source: null, playable: false,
    scenes: [], catalog: null, sel: [], hidden: new Set(), locked: new Set(),
    undo: [], redo: [], savedJson: "", dirty: false, clipboard: null, testing: false,
  };

  // ---- api and messages ---------------------------------------------------------------------
  async function api(path, body, raw) {
    const opts = body === undefined ? {} : { method: "POST", headers: { "Content-Type": raw ? "application/octet-stream" : "application/json" }, body: raw ? body : JSON.stringify(body) };
    const r = await fetch(path, opts);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.error || r.statusText);
    return data;
  }
  function toast(text, kind = "") {
    const t = $("#toast");
    t.innerHTML = `${ic(kind === "bad" ? "error" : kind === "warn" ? "alert" : kind === "good" ? "check-circle" : "info")}<span>${esc(text)}</span>`;
    t.className = "toast show " + kind;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => (t.className = "toast"), 3200);
  }
  function confirmBox(title, text, yes = "Да") {
    return new Promise((resolve) => {
      $("#confirm-title").textContent = title;
      $("#confirm-text").textContent = text;
      $("#confirm-yes").textContent = yes;
      const box = $("#confirm");
      box.hidden = false;
      const done = (v) => { box.hidden = true; box.onclick = null; document.removeEventListener("keydown", key, true); resolve(v); };
      const key = (e) => { if (e.key === "Escape") { e.stopPropagation(); done(false); } if (e.key === "Enter") { e.stopPropagation(); done(true); } };
      document.addEventListener("keydown", key, true);
      box.onclick = (e) => {
        const a = e.target.closest("[data-answer]");
        if (a) done(a.dataset.answer === "yes");
        else if (e.target === box) done(false);
      };
    });
  }

  // ---- the scene's objects --------------------------------------------------------------------
  const S = () => state.S;
  // The scene with a road plan to find lanes in: its own, or the one detected for a traced scene.
  const planScene = () => (state.S && state.S.layout ? state.S : state.S && state.plan ? { ...state.S, layout: state.plan } : null);
  function objectOf(ref) {
    const s = state.S;
    if (!s || !ref) return null;
    switch (ref.t) {
      case "decor": return s.decor.find((x) => x.id === ref.id);
      case "actor": return s.actors.find((x) => x.id === ref.id);
      case "light": return s.lights.find((x) => x.id === ref.id);
      case "officer": return (s.officers || []).find((x) => x.id === ref.id);
      case "sign": return (s.signs || []).find((x) => x.id === ref.id);
      case "track": return (s.tracks || []).find((x) => x.id === ref.id);
      case "route": return s.routes.find((x) => x.id === ref.id);
      case "marking": return (s.markings || []).find((x) => x.id === ref.id);
      case "lawn": return (s.lawns || []).find((x) => x.id === ref.id);
      case "road": return s.roads.find((x) => x.id === ref.id);
      case "street": return s.layout && Layout.streetOf(s.layout, ref.id);
      case "node": return s.layout && Layout.nodeOf(s.layout, ref.id);
      case "stop": return s.stop;
      default: return null;
    }
  }
  // The point list a ref is drawn and edited by (a route, a marking line, a road's or lawn's ring).
  function pointsOfRef(ref) {
    const o = objectOf(ref);
    if (!o) return null;
    if (ref.t === "route" || ref.t === "track") return o.points;
    if (ref.t === "marking") return o.points || (o.polygons && o.polygons[0] && o.polygons[0].outer);
    if (ref.t === "lawn") return o.outer;
    if (ref.t === "road") return ref.part >= 0 ? o.holes[ref.part] : o.outer;
    return null;
  }
  const isPaint = (ref) => objectOf(ref)?.type === "paint";
  const layerOf = (ref) => ({ decor: "decor", track: "roads", sign: "signs", actor: "actors", officer: "actors", light: "lights", route: "routes", marking: "marks", lawn: "roads",
    road: "roads", street: "roads", node: "roads", bend: "roads", stop: "actors" }[ref.t]);
  const catalogSize = (prop) => prop === "parked" ? [1.9, 1.4, 4.2] : state.catalog?.props.find((p) => p.id === prop)?.size;
  const sameRef = (a, b) => a && b && a.t === b.t && (a.id ?? null) === (b.id ?? null) && (a.part ?? -1) === (b.part ?? -1);

  function nameOf(ref) {
    const o = objectOf(ref);
    if (!o && ref.t !== "stop") return "";
    switch (ref.t) {
      case "decor": return Catalog.propName(o.prop);
      case "actor": return o.name || Catalog.ACTORS[o.type]?.name || o.type;
      case "light": return "Светофор";
      case "officer": return "Регулировщик";
      case "sign": return Catalog.signName(o.code);
      case "track": return o.depot ? "Рельсы в депо" : "Рельсы";
      case "route":
        if (o.kind === "manoeuvre") return `Манёвр: ${Catalog.EXITS[o.exit]?.title.toLowerCase() || o.exit}`;
        if (o.kind === "choice") return `Ответ ${o.label}`;
        if (o.kind === "approach") return "Подъезд игрока";
        return `Путь: ${objectOf({ t: "actor", id: o.id.replace(/^actor_/, "") })?.name || "участник"}`;
      case "marking": return o.type === "paint" ? "Разметка сцены" : Catalog.MARKS[o.type]?.title || o.type;
      case "lawn": return "Газон";
      case "road": return ref.part >= 0 ? "Островок" : "Дорога";
      case "street": return Layout.KINDS[o.kind || "street"].title;
      case "node": return o.ring ? "Кольцо" : "Перекрёсток";
      case "stop": return "Игрок и стоп-линия";
      default: return ref.t;
    }
  }

  // ---- history -----------------------------------------------------------------------------
  const snapshotText = () => JSON.stringify(state.S);
  // One undo step around fn (which changes state.S). The road plan rebuilds what it makes.
  function edit(fn, opts = {}) {
    if (!state.S) return;
    const before = snapshotText();
    const result = fn(state.S);
    if (state.S.layout) Layout.apply(state.S);
    if (state.S.tracks) Tracks.apply(state.S);
    if (!state.S.layout && state.plan) Layout.applyActors(state.S, planScene());
    const after = snapshotText();
    if (after === before) return result;
    if (!opts.merge || !state.undo.length) state.undo.push(before);
    if (state.undo.length > 400) state.undo.shift();
    state.redo = [];
    changed(opts);
    return result;
  }
  // A drag: one undo step from its start, the view follows every move.
  let dragBase = null;
  function beginDrag() { dragBase = snapshotText(); }
  function dragMove(fn) {
    fn(state.S);
    if (state.S.layout) Layout.apply(state.S);
    if (state.S.tracks) Tracks.apply(state.S);
    if (!state.S.layout && state.plan) Layout.applyActors(state.S, planScene());
    Scene3D.refresh(state.S);
    App.renderSelection?.();
  }
  function endDrag() {
    if (dragBase === null) return;
    if (snapshotText() !== dragBase) {
      state.undo.push(dragBase);
      state.redo = [];
      changed();
    }
    dragBase = null;
  }
  function cancelDrag() {
    if (dragBase === null) return;
    state.S = JSON.parse(dragBase);
    dragBase = null;
    afterHistory();
  }
  function undo() {
    if (!state.undo.length) return;
    state.redo.push(snapshotText());
    state.S = JSON.parse(state.undo.pop());
    afterHistory();
  }
  function redo() {
    if (!state.redo.length) return;
    state.undo.push(snapshotText());
    state.S = JSON.parse(state.redo.pop());
    afterHistory();
  }
  function afterHistory() {
    state.sel = state.sel.filter((r) => objectOf(r));
    changed();
  }
  function changed(opts = {}) {
    state.dirty = snapshotText() !== state.savedJson;
    if (typeof Framing !== "undefined") Framing.refresh();
    Scene3D.refresh(state.S);
    Scene3D.setSelection(state.sel);
    schedulePreview();
    renderTop();
    if (!opts.quiet) App.renderPanels?.();
  }

  // ---- preview: the server checks and builds the unsaved scene --------------------------------
  let previewTimer = null, previewSeq = 0;
  function schedulePreview() {
    clearTimeout(previewTimer);
    previewTimer = setTimeout(runPreview, 220);
  }
  async function runPreview() {
    if (!state.S) return;
    const mine = ++previewSeq, sid = state.id;
    const r = await api(`/api/preview/${sid}`, state.S).catch((e) => { toast(e.message, "bad"); return null; });
    if (!r || mine !== previewSeq || sid !== state.id) return;
    state.findings = r.findings;
    state.edges = r.edges;
    state.build = r.build;
    Scene3D.setBuild(r.build);
    renderTop();
    App.renderPanels?.({ only: ["inspector"] });
  }

  // ---- scenes ------------------------------------------------------------------------------
  async function loadList() {
    state.scenes = await api("/api/scenes");
  }
  async function openScene(sid) {
    if (state.dirty && sid !== state.id && !(await confirmBox("Уйти без сохранения?", "В этой сцене есть несохранённые правки.", "Уйти"))) return;
    const r = await api(`/api/scene/${sid}`);
    state.S = r.scene;
    state.S.markings = state.S.markings || [];
    state.S.lawns = state.S.lawns || [];
    state.id = sid;
    if (sid !== "mini_regulator") state.lastTicket = sid;
    state.section = sid === "mini_regulator" ? "regulator" : "city";
    document.querySelectorAll("[data-editor-section]").forEach(b => {
      const on = b.dataset.editorSection === state.section;
      b.classList.toggle("on", on); b.setAttribute("aria-selected", String(on));
    });
    // A traced scene has no road plan: one detected from its roads finds the lanes and ways of its cars.
    state.plan = null;
    if (!state.S.layout && sid !== "mini_regulator") api(`/api/layout/detect/${sid}`).then((d) => { if (state.id === sid) { state.plan = d.layout; App.renderInspector?.(); } }).catch(() => {});
    state.findings = r.findings;
    state.edges = r.edges;
    state.build = r.build;
    state.source = r.source;
    state.playable = r.playable;
    state.undo = [];
    state.redo = [];
    state.sel = [];
    state.savedJson = snapshotText();
    state.dirty = false;
    // Older highway saves contain automatic tapers at both borders. Refresh only the
    // generated geometry in memory; manual edits and the on-disk source wait for Save.
    if (state.S.layout?.streets?.some(st => st.kind === "highway")) {
      Layout.apply(state.S);
      if (snapshotText() !== state.savedJson) {
        state.undo.push(state.savedJson);
        state.dirty = true;
      }
    }
    Tools.set("select");
    Scene3D.load(state.S, state.dirty ? null : r.build);
    showHome(false);
    history.replaceState(null, "", `?scene=${sid}`);
    renderTop();
    App.renderPanels?.();
    if (state.dirty) {
      schedulePreview();
      toast("Трасса пересобрана по настройкам стыков. Сохраните, чтобы обновить игру.", "good");
    }
    if (typeof Framing !== "undefined") Framing.refresh();
  }
  const sceneTitle = (sid) => {
    if (sid === "mini_regulator") return "Мини-игра «Регулировщик»";
    const m = String(sid || "").match(/^ticket_(\d+)_(\d+)$/);
    return m ? `Билет ${m[1]} · вопрос ${m[2]}` : sid;
  };

  async function save() {
    // Textures are not part of a scene: they reach the game by their own "Применить в игре".
    if (!state.S || !state.dirty) { toast("Всё сохранено"); renderTop(); return; }
    try {
      const r = await api(`/api/scene/${state.id}`, state.S);
      state.savedJson = snapshotText();
      state.dirty = false;
      state.findings = r.findings;
      const errors = r.findings.filter((f) => f.level === "error").length;
      const gone = r.removed && r.removed.length ? ` Удалено: ${r.removed.length}.` : "";
      toast(errors ? `Сохранено, но есть ошибки: ${errors}.${gone}` : `Сохранено.${gone}`, errors ? "warn" : "good");
      saveThumb();
      loadList().then(() => App.renderPanels?.());
    } catch (e) {
      toast(`Не сохранено: ${e.message}`, "bad");
    }
    renderTop();
  }
  // The card picture of the scene list: the view from above as it is now.
  function saveThumb() {
    try {
      Scene3D.capture(360).toBlob((blob) => {
        if (blob) fetch(`/api/thumb/${state.id}`, { method: "POST", body: blob }).then(() => { thumbRev[state.id] = Date.now(); });
      }, "image/png");
    } catch (e) { /* the picture is a nicety */ }
  }
  const thumbRev = {};

  async function setPlayable(on) {
    if (state.dirty) await save();
    try {
      const r = await api(`/api/game/include/${state.id}`, { playable: on });
      state.playable = r.playable;
      // The file changed on the server (its "reviewed" flag): the open copy follows.
      state.S.reviewed = on;
      state.savedJson = snapshotText();
      toast(on ? `Сцена в игре. Всего в игре: ${r.count}` : "Сцена убрана из игры", "good");
      loadList().then(() => App.renderPanels?.());
    } catch (e) {
      toast(e.message, "bad");
    }
    renderTop();
  }

  async function runInGame(auto = false) {
    if (!state.S) return;
    if (state.dirty) await save();
    try {
      toast("Готовлю перекрёсток для игры…");
      const r = await api(`/api/game/run/${state.id}`, { auto });
      toast(r.launched ? "Игра открывается в отдельном окне на этом перекрёстке" : r.error, r.launched ? "good" : "bad");
    } catch (e) {
      toast(e.message, "bad");
    }
  }

  // ---- selection ------------------------------------------------------------------------------
  function select(list, opts = {}) {
    const arr = (Array.isArray(list) ? list : list ? [list] : []).filter((r) => r && (objectOf(r) || r.t === "stop"));
    state.sel = opts.add ? uniq([...state.sel, ...arr]) : arr;
    if (state.sel.length) state.texSel = null;   // the inspector shows what was picked, not the texture
    Scene3D.setSelection(state.sel);
    App.renderPanels?.({ only: ["inspector", "layers"] });
  }
  function toggle(ref) {
    const has = state.sel.some((r) => sameRef(r, ref));
    select(has ? state.sel.filter((r) => !sameRef(r, ref)) : [...state.sel, ref]);
  }
  const uniq = (list) => list.filter((r, i) => list.findIndex((x) => sameRef(x, r)) === i);
  const isLocked = (ref) => state.locked.has(layerOf(ref));
  const isHidden = (ref) => state.hidden.has(layerOf(ref));
  const pickable = (ref) => !isLocked(ref) && !isHidden(ref);

  function selectAll() {
    const s = state.S;
    if (!s) return;
    const kinds = new Set(state.sel.map((r) => r.t));
    const all = [];
    if (!kinds.size || kinds.has("decor")) s.decor.forEach((d) => all.push({ t: "decor", id: d.id }));
    if (!kinds.size || kinds.has("actor")) s.actors.forEach((a) => all.push({ t: "actor", id: a.id }));
    if (!kinds.size || kinds.has("light")) s.lights.forEach((l) => all.push({ t: "light", id: l.id }));
    select(all.filter(pickable));
  }

  // ---- moving, turning, copying, deleting ------------------------------------------------------
  const movable = (ref) => ["decor", "track", "sign", "actor", "officer", "light", "marking", "lawn", "road", "route", "stop", "node"].includes(ref.t);
  function moveRef(s, ref, dx, dz) {
    const o = objectOf(ref);
    if (!o) return;
    const shift = (p) => { p[0] = r3(p[0] + dx); p[1] = r3(p[1] + dz); };
    if (ref.t === "decor" || ref.t === "actor" || ref.t === "light" || ref.t === "officer" || ref.t === "sign") {
      o.pos = [r3(o.pos[0] + dx), r3(o.pos[1] + dz)];
      if (ref.t === "actor") {
        const rid = o.route || `actor_${o.id}`;
        const r = s.routes.find((x) => x.id === rid);
        if (r && (!o.way || r.manual)) r.points.forEach(shift);
      }
    } else if (ref.t === "stop") {
      if (Layout.isFreePlayer(s)) return Layout.movePlayer(s, [s.stop.x + dx, s.stop.z + dz]);
      if (s.layout) return;
      s.stop.x = r3(s.stop.x + dx); s.stop.z = r3(s.stop.z + dz);
      const ap = s.routes.find((r) => r.id === "approach");
      if (ap && ap.points) ap.points.forEach(shift);
      if (s.id === "mini_regulator") for (const r of s.routes.filter(r => r.kind === "manoeuvre")) r.points[0] = [s.stop.x, s.stop.z];
    } else if (ref.t === "node") {
      Layout.moveNode(s, ref.id, [o.x + dx, o.z + dz]);
    } else if (ref.t === "route") {
      if (o.auto) return;
      if (s.id === "mini_regulator" && ["approach", "manoeuvre"].includes(o.kind)) return;
      Layout.editPlayerRoute(s, o);
      o.points.forEach(shift);
      if (o.labelPosition) shift(o.labelPosition);
    } else if (ref.t === "track") {
      o.points.forEach(shift);
    } else if (ref.t === "marking") {
      if (o.points) o.points.forEach(shift);
      (o.polygons || []).forEach((p) => { p.outer.forEach(shift); (p.holes || []).forEach((h) => h.forEach(shift)); });
    } else if (ref.t === "lawn" || ref.t === "road") {
      const rings = ref.t === "road" && ref.part >= 0 ? [o.holes[ref.part]] : [o.outer, ...(o.holes || [])];
      rings.forEach((ring) => ring.forEach(shift));
    }
  }
  function nudge(dx, dz) {
    const list = state.sel.filter(movable);
    if (!list.length) return;
    edit((s) => list.forEach((r) => moveRef(s, r, dx, dz)), { merge: Date.now() - nudge.last < 600 });
    nudge.last = Date.now();
  }
  nudge.last = 0;
  // Arrow keys move along the screen, whichever way the view is turned (snapped to the axes when close).
  function nudgeScreen(right, up, step) {
    const v = $("#view"), cx = v.clientWidth / 2, cy = v.clientHeight / 2;
    const o = Scene3D.worldAt(cx, cy), r = Scene3D.worldAt(cx + 40, cy), u = Scene3D.worldAt(cx, cy - 40);
    if (!o || !r || !u) return;
    const axis = (b) => {
      let x = b.x - o.x, z = b.z - o.z;
      const l = Math.hypot(x, z) || 1;
      x /= l; z /= l;
      if (Math.abs(x) > 0.94) return [Math.sign(x), 0];
      if (Math.abs(z) > 0.94) return [0, Math.sign(z)];
      return [x, z];
    };
    const R = axis(r), U = axis(u);
    nudge(r3((R[0] * right + U[0] * up) * step), r3((R[1] * right + U[1] * up) * step));
  }

  // Turns the selection by `deg` degrees: each object about itself; a shape about its middle.
  function rotate(deg) {
    const list = state.sel.filter((r) => ["decor", "sign", "actor", "officer", "light", "marking", "lawn", "road", "stop"].includes(r.t));
    if (!list.length) return;
    const a = (deg * Math.PI) / 180;
    edit((s) => {
      for (const ref of list) {
        const o = objectOf(ref);
        if (ref.t === "stop") { if (Layout.isFreePlayer(s)) Layout.rotatePlayer(s, (s.stop.yaw || 0) - a); continue; }
        if (o.pos) { o.yaw = r3(wrap((o.yaw || 0) - a)); continue; }
        const rings = ref.t === "marking" ? (o.points ? [o.points] : o.polygons.flatMap((p) => [p.outer, ...(p.holes || [])]))
          : ref.t === "road" && ref.part >= 0 ? [o.holes[ref.part]] : [o.outer, ...(o.holes || [])];
        const all = rings.flat();
        const cx = all.reduce((t, p) => t + p[0], 0) / all.length, cz = all.reduce((t, p) => t + p[1], 0) / all.length;
        const c = Math.cos(a), n = Math.sin(a);
        rings.forEach((ring) => ring.forEach((p) => {
          const x = p[0] - cx, z = p[1] - cz;
          p[0] = r3(cx + x * c - z * n);
          p[1] = r3(cz + x * n + z * c);
        }));
      }
    }, { merge: Date.now() - rotate.last < 600 });
    rotate.last = Date.now();
  }
  rotate.last = 0;
  const wrap = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a <= -Math.PI) a += 2 * Math.PI; return a; };

  function uniqueId(prefix, taken) {
    let n = 1;
    while (taken.includes(`${prefix}${n}`)) n++;
    return `${prefix}${n}`;
  }

  // Copies of things: props, participants (with their path), lights, markings, lawns.
  const COPYABLE = ["decor", "sign", "actor", "officer", "light", "marking", "lawn"];
  function copy() {
    const list = state.sel.filter((r) => COPYABLE.includes(r.t));
    if (!list.length) return false;
    state.clipboard = list.map((r) => {
      const o = JSON.parse(JSON.stringify(objectOf(r)));
      const route = r.t === "actor" && o.route && !o.way ? JSON.parse(JSON.stringify(state.S.routes.find((x) => x.id === o.route) || null)) : null;
      return { t: r.t, o, route };
    }).filter((c) => !(c.t === "marking" && c.o.auto));
    toast(`Скопировано: ${state.clipboard.length}`);
    return true;
  }
  function paste(offset = 4) {
    if (!state.clipboard || !state.clipboard.length) return;
    const made = edit((s) => state.clipboard.map((c) => pasteOne(s, c, offset)));
    select(made);
  }
  function pasteOne(s, c, offset) {
    const o = JSON.parse(JSON.stringify(c.o));
    const listKey = { decor: "decor", sign: "signs", actor: "actors", officer: "officers", light: "lights", marking: "markings", lawn: "lawns" }[c.t];
    const prefix = c.t === "actor" ? `${o.type}_` : { decor: "decor_", sign: "sign_", officer: "officer_", light: "light_", marking: "mark_", lawn: "lawn_" }[c.t];
    s[listKey] = s[listKey] || [];
    o.id = uniqueId(prefix, s[listKey].map((x) => x.id));
    delete o.auto;
    const ref = { t: c.t, id: o.id };
    s[listKey].push(o);
    moveRef(s, ref, offset, -offset);
    if (c.t === "actor") {
      if (c.route) {
        const r = { ...JSON.parse(JSON.stringify(c.route)), id: `actor_${o.id}` };
        delete r.auto;
        r.points = r.points.map((p) => [r3(p[0] + offset), r3(p[1] - offset)]);
        s.routes.push(r);
        o.route = r.id;
      } else if (!o.way) o.route = null;
    }
    return ref;
  }
  function duplicate() {
    if (copy()) paste(3);
  }

  async function remove() {
    const list = state.sel;
    if (!list.length) return;
    // A point of a shape or route, when one is picked.
    if (list.length === 1 && list[0].v !== undefined) {
      const ref = list[0], pts = pointsOfRef(ref);
      const least = ref.t === "route" || (ref.t === "marking") ? 2 : 3;
      if (!pts || pts.length <= least) return toast("Меньше точек нельзя", "warn");
      const o = objectOf(ref);
      if (ref.t === "route" && state.S.id === "mini_regulator" && ((o?.kind === "manoeuvre" && ref.v === 0) || (o?.kind === "approach" && ref.v === pts.length - 1))) return toast("Эта точка закреплена у автомобиля игрока", "warn");
      if (ref.t === "route" && o?.kind === "approach" && state.S.layout && (!o.manual || ref.v === 0 || ref.v === pts.length - 1)) return toast("Начало подъезда закреплено у въезда, конец — у игрока", "warn");
      edit(() => {
        if (ref.t === "route" && o) {
          Layout.editPlayerRoute(state.S, o);
        }
        pts.splice(ref.v, 1);
      });
      return select({ ...ref, v: undefined });
    }
    const removable = list.filter((r) => r.t !== "stop" && !(r.t === "route" && (objectOf(r)?.auto || objectOf(r)?.kind === "approach" || (state.S.id === "mini_regulator" && objectOf(r)?.kind === "manoeuvre"))) && !(r.t === "marking" && objectOf(r)?.auto));
    if (!removable.length) return toast("Это строится само по дорогам", "warn");
    edit((s) => {
      for (const ref of removable) {
        if (ref.t === "street") { Layout.removeStreet(s, ref.id); continue; }
        if (ref.t === "node") { Layout.removeNode(s, ref.id); continue; }
        if (ref.t === "road" && ref.part >= 0) { objectOf(ref)?.holes.splice(ref.part, 1); continue; }
        const key = { decor: "decor", track: "tracks", sign: "signs", actor: "actors", officer: "officers", light: "lights", route: "routes", marking: "markings", lawn: "lawns", road: "roads" }[ref.t];
        const o = objectOf(ref);
        if (!o) continue;
        s[key] = s[key].filter((x) => x !== o);
        if (ref.t === "actor" && o.route) {
          s.routes = s.routes.filter((r) => r.id !== o.route);
          if (s.question?.yieldTo) s.question.yieldTo = s.question.yieldTo.filter((x) => x !== o.id);
        }
        if (ref.t === "route") s.actors.forEach((a) => { if (a.route === o.id || o.id === `actor_${a.id}`) { a.route = null; delete a.way; } });
      }
    });
    select([]);
  }

  // ---- visibility and locks (layers panel) ------------------------------------------------------
  function toggleHidden(layer) {
    state.hidden.has(layer) ? state.hidden.delete(layer) : state.hidden.add(layer);
    state.sel = state.sel.filter(pickable);
    Scene3D.setHidden(state.hidden);
    Scene3D.setSelection(state.sel);
    App.renderPanels?.();
  }
  function toggleLocked(layer) {
    state.locked.has(layer) ? state.locked.delete(layer) : state.locked.add(layer);
    state.sel = state.sel.filter(pickable);
    Scene3D.setSelection(state.sel);
    App.renderPanels?.();
  }

  // ---- the top bar ------------------------------------------------------------------------------
  function renderTop() {
    const s = state.S;
    const err = state.findings.filter((f) => f.level === "error").length;
    $("#title").textContent = s ? sceneTitle(state.id) : "Редактор сцен";
    const chip = $("#status");
    chip.hidden = !s;
    chip.className = "chip " + (err ? "bad" : state.playable ? "good" : "");
    chip.innerHTML = !s ? "" : err ? `${ic("error")}${err} ${plural(err, ["ошибка", "ошибки", "ошибок"])}` : state.playable ? `${ic("check-circle")}в игре` : "не в игре";
    if (state.id === "mini_regulator" && !err) chip.textContent = "мини-игра";
    chip.dataset.tip = err ? "Открыть проверку" : "";
    $("#save").disabled = !state.dirty;
    $("#save").classList.toggle("pulse", state.dirty);
    $("#undo").disabled = !state.undo.length;
    $("#redo").disabled = !state.redo.length;
    $("#play").disabled = !s;
    document.title = s ? `${state.dirty ? "• " : ""}${sceneTitle(state.id)} — Редактор сцен` : "Редактор сцен";
  }
  function plural(n, forms) {
    const m = n % 100, k = n % 10;
    if (m > 10 && m < 20) return forms[2];
    if (k === 1) return forms[0];
    if (k > 1 && k < 5) return forms[1];
    return forms[2];
  }

  function showHome(on) {
    $("#home-screen").hidden = !on;
    $("#app").classList.toggle("at-home", on);
    if (on) App.renderHome?.();
  }

  // ---- keys ----------------------------------------------------------------------------------
  // [keys, what, handler]; the list is also the help sheet (?), grouped by `group`.
  const KEYS = [];
  function key(group, combo, label, fn, opts = {}) { KEYS.push({ group, combo, label, fn, ...opts }); }
  function matches(e, combo) {
    if (combo === "+") return !e.metaKey && !e.ctrlKey && !e.altKey && (e.key === "+" || e.key === "=");
    const parts = combo.toLowerCase().split("+");
    const k = parts.pop();
    const mod = parts.includes("mod"), shift = parts.includes("shift"), alt = parts.includes("alt");
    if (mod !== (e.metaKey || e.ctrlKey) || alt !== e.altKey) return false;
    const code = e.code.replace(/^Key|^Digit/, "").toLowerCase();
    const want = k === "+" ? ["=", "equal", "+"] : k === "-" ? ["-", "minus"] : k === "?" ? ["?", "/", "slash"] : [k];
    const hit = want.includes(e.key.toLowerCase()) || want.includes(code);
    if (!hit) return false;
    if (k === "?") return true;
    return shift === e.shiftKey;
  }
  function onKey(e) {
    const typing = e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable);
    if (!$("#keys").hidden && e.key === "Escape") { $("#keys").hidden = true; return; }
    for (const k of KEYS) {
      if (!matches(e, k.combo)) continue;
      if (typing && !k.always) return;
      if (k.needScene && !state.S) return;
      e.preventDefault();
      k.fn(e);
      return;
    }
  }
  const KEY_TEXT = { mod: "⌘", shift: "⇧", alt: "⌥", enter: "↵", escape: "Esc", delete: "Delete", backspace: "⌫",
    arrowup: "↑", arrowdown: "↓", arrowleft: "←", arrowright: "→", space: "Пробел" };
  const keyLabel = (combo) => combo === "+" ? "+" : combo.split("+").map((p) => KEY_TEXT[p.toLowerCase()] || p.toUpperCase()).join("");
  function renderKeys() {
    const groups = [...new Set(KEYS.filter((k) => !k.hiddenInHelp).map((k) => k.group))];
    $("#keys-body").innerHTML = groups.map((g) => `<section><h3>${g}</h3><dl>${KEYS.filter((k) => k.group === g && !k.hiddenInHelp)
      .map((k) => `<dt>${(k.show || [k.combo]).map((c) => `<kbd>${esc(keyLabel(c))}</kbd>`).join(" ")}</dt><dd>${esc(k.label)}</dd>`).join("")}</dl></section>`).join("")
      + `<section><h3>Мышь и трекпад</h3><dl>
        <dt><kbd>Пробел</kbd>+тянуть</dt><dd>двигать вид</dd><dt>ПКМ</dt><dd>вращать вид (3D)</dd>
        <dt>Колесо, щипок</dt><dd>масштаб</dd><dt>Два пальца</dt><dd>двигать вид</dd>
        <dt><kbd>⇧</kbd>+клик</dt><dd>добавить к выбору</dd><dt><kbd>⌥</kbd>+тянуть</dt><dd>тянуть копию</dd></dl></section>`;
  }

  function bindKeys() {
    const G1 = "Общее", G2 = "Выбранное", G3 = "Инструменты", G4 = "Вид";
    key(G1, "mod+s", "Сохранить", () => save(), { always: true, needScene: true });
    key(G1, "mod+z", "Отменить", () => undo(), { needScene: true });
    key(G1, "mod+shift+z", "Вернуть", () => redo(), { needScene: true });
    key(G1, "mod+y", "Вернуть", () => redo(), { needScene: true, hiddenInHelp: true });
    key(G1, "p", "Тест в игре (этот перекрёсток)", () => runInGame(false), { needScene: true });
    key(G1, "mod+enter", "Тест в игре", () => runInGame(false), { needScene: true, hiddenInHelp: true });
    key(G1, "?", "Клавиши", () => { renderKeys(); $("#keys").hidden = false; });
    key(G2, "mod+c", "Копировать", () => copy(), { needScene: true });
    key(G2, "mod+v", "Вставить", () => paste(), { needScene: true });
    key(G2, "mod+d", "Дублировать", () => duplicate(), { needScene: true });
    key(G2, "mod+a", "Выбрать все такие же", () => selectAll(), { needScene: true });
    key(G2, "delete", "Удалить", () => remove(), { needScene: true, show: ["delete", "backspace"] });
    key(G2, "backspace", "Удалить", () => remove(), { needScene: true, hiddenInHelp: true });
    key(G2, "escape", "Снять выбор, отменить", () => Tools.escape(), { needScene: true });
    key(G2, "enter", "Готово (рисование)", () => Tools.enter(), { needScene: true });
    key(G2, "q", "Повернуть на −15°", () => rotate(-15), { needScene: true, show: ["q", "e"] });
    key(G2, "e", "Повернуть на +15°", () => rotate(15), { needScene: true, hiddenInHelp: true });
    key(G2, "arrowleft", "Сдвинуть на 10 см (⇧ — на 1 м)", () => nudgeScreen(-1, 0, 0.1), { needScene: true, show: ["arrowleft", "arrowright", "arrowup", "arrowdown"] });
    key(G2, "arrowright", "", () => nudgeScreen(1, 0, 0.1), { needScene: true, hiddenInHelp: true });
    key(G2, "arrowup", "", () => nudgeScreen(0, 1, 0.1), { needScene: true, hiddenInHelp: true });
    key(G2, "arrowdown", "", () => nudgeScreen(0, -1, 0.1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowleft", "", () => nudgeScreen(-1, 0, 1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowright", "", () => nudgeScreen(1, 0, 1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowup", "", () => nudgeScreen(0, 1, 1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowdown", "", () => nudgeScreen(0, -1, 1), { needScene: true, hiddenInHelp: true });
    for (const t of Tools.list()) key(G3, t.key.toLowerCase(), t.title, () => Tools.set(t.id), { needScene: true });
    key(G4, "f", "Показать всё (или выбранное)", () => Tools.fitSelection(), { needScene: true });
    key(G4, "2", "Вид сверху", () => setView("plan"), { needScene: true });
    key(G4, "3", "Объёмный вид", () => setView("3d"), { needScene: true });
    key(G4, "+", "Приблизить", () => Scene3D.zoomBy(1.25), { needScene: true, show: ["+", "-"] });
    key(G4, "-", "Отдалить", () => Scene3D.zoomBy(0.8), { needScene: true, hiddenInHelp: true });
    key(G4, "shift+r", "Показать или скрыть маршруты", () => toggleHidden("routes"), { needScene: true });
    document.addEventListener("keydown", onKey);
  }

  function setView(m) {
    Scene3D.setMode(m);
    $("#v-plan").classList.toggle("on", m === "plan");
    $("#v-3d").classList.toggle("on", m === "3d");
  }

  // ---- boot ----------------------------------------------------------------------------------
  async function boot() {
    Scene3D.mount($("#view"));
    Tools.init();
    bindKeys();
    $("#undo").onclick = undo;
    $("#redo").onclick = redo;
    $("#save").onclick = save;
    $("#play").onclick = () => runInGame(false);
    $("#help").onclick = () => { renderKeys(); $("#keys").hidden = false; };
    $("#keys").addEventListener("click", (e) => { if (e.target.id === "keys" || e.target.closest("[data-close]")) $("#keys").hidden = true; });
    $("#home").onclick = () => showHome(true);
    document.querySelectorAll("[data-editor-section]").forEach(b => b.onclick = async () => {
      const sid = b.dataset.editorSection === "regulator" ? "mini_regulator" : state.lastTicket || state.scenes.find(s => s.id !== "mini_regulator")?.id;
      if (sid && sid !== state.id) await openScene(sid);
    });
    $("#status").onclick = () => App.showChecks?.();
    $("#v-plan").onclick = () => setView("plan");
    $("#v-3d").onclick = () => setView("3d");
    $("#z-in").onclick = () => Scene3D.zoomBy(1.25);
    $("#z-out").onclick = () => Scene3D.zoomBy(0.8);
    $("#z-fit").onclick = () => Tools.fitSelection();
    setView("3d");
    Scene3D.on("camera", ({ mode }) => {
      $("#v-plan").classList.toggle("on", mode === "plan");
      $("#v-3d").classList.toggle("on", mode === "3d");
    });
    addEventListener("beforeunload", (e) => { if (state.dirty || Textures.dirtyKinds().length) { e.preventDefault(); e.returnValue = ""; } });
    try {
      [state.catalog] = await Promise.all([api("/api/catalog"), Textures.load(), loadList()]);
    } catch (e) {
      toast("Сервер редактора не отвечает: " + e.message, "bad");
      return;
    }
    Scene3D.setTextures(Textures.forScene());
    App.renderPanels?.();
    renderTop();
    const first = new URLSearchParams(location.search).get("scene");
    if (first) openScene(first).catch((e) => { toast(e.message, "bad"); showHome(true); });
    else showHome(true);
  }

  return {
    state, planScene, api, toast, confirm: confirmBox, esc, ic, r3, objectOf, pointsOfRef, isPaint, layerOf, catalogSize, sameRef, nameOf,
    edit, beginDrag, dragMove, endDrag, cancelDrag, undo, redo, changed, openScene, sceneTitle, save, setPlayable, runInGame,
    select, toggle, pickable, isLocked, moveRef, nudge, rotate, copy, paste, duplicate, remove, uniqueId, toggleHidden, toggleLocked,
    renderTop, showHome, setView, plural, thumbRev, boot, loadList,
    get S() { return state.S; },
  };
})();
