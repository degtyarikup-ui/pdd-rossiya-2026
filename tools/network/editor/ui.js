// The editor's logic: scenes, the object tree, tools, the inspector, the question panel,
// checks, undo/redo, live preview and saving. The 3D view is in scene3d.js.
const Ed = (() => {
  const $ = (s) => document.querySelector(s);
  const esc = (v) => String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const RAD = 180 / Math.PI;
  const EXIT = { left: "налево", right: "направо", straight: "прямо", uturn: "разворот" };
  const TYPE = { car: "Легковой автомобиль", truck: "Грузовик", bus: "Автобус", tram: "Трамвай", pedestrian: "Пешеход",
    cyclist: "Велосипедист", motorcycle: "Мотоцикл", special: "Спецмашина", van: "Фургон", tanker: "Цистерна", cart: "Повозка" };
  const LIGHT = { red: "Красный", yellow: "Жёлтый", green: "Зелёный", flashing_yellow: "Мигающий жёлтый" };
  const ARROW = { "": "нет", left: "налево", right: "направо", straight: "прямо" };
  const LETTERS = ["А", "Б", "В", "Г", "Д"];
  const TOOLS = {
    select: { key: "V", hint: "Выбор: нажмите объект или линию. Тяните точку или объект. Двойной клик по линии добавляет точку." },
    route: { key: "M", hint: "Маршрут: кликайте точки пути. Двойной клик или Enter — готово, Esc — отмена." },
    road: { key: "D", hint: "Дорога: кликайте углы контура. Клик у первой точки или Enter — замкнуть." },
    island: { key: "I", hint: "Островок: контур внутри дороги. Клик у первой точки или Enter — замкнуть." },
    decor: { key: "P", hint: "Декор: кликните место, чтобы поставить выбранный предмет." },
    actor: { key: "A", hint: "Участник: кликните место, чтобы поставить машину или пешехода." },
    light: { key: "L", hint: "Светофор: кликните место у дороги." },
    stop: { key: "S", hint: "Стоп-линия: кликните место, где начинается остановка (подъезд подстроится)." },
  };
  const DRIVEN = ["car", "truck", "bus", "motorcycle", "tram", "van", "special", "tanker"];

  let scenes = [], catalog = null, filter = "all", query = "", objQuery = "";
  let S = null, id = null, findings = [], source = null, seq = 0, previewTimer = null;
  let sel = null, tool = "select", ltab = "scenes", rtab = "props", opts = { route: "manoeuvre", exit: "left", label: "А", actorType: "car", prop: "", draw: null };
  let undoStack = [], redoStack = [], dirty = false, savedJson = "", drag = null, draft = null, cursorWorld = null;
  let openGroups = { roads: true, routes: true, actors: true, lights: true, decor: false, stop: true };

  // ---- api ---------------------------------------------------------------------------
  async function api(path, body) {
    const r = await fetch(path, body === undefined ? {} : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.error || r.statusText);
    return data;
  }

  function toast(text, kind = "") {
    const t = $("#toast");
    t.textContent = text;
    t.className = "toast show " + kind;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => (t.className = "toast"), 3200);
  }

  // ---- geometry ----------------------------------------------------------------------
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const polyLength = (pts) => pts.slice(1).reduce((s, p, i) => s + dist(pts[i], p), 0);
  const area = (poly) => Math.abs(poly.reduce((s, p, i) => {
    const q = poly[(i + 1) % poly.length];
    return s + p[0] * q[1] - q[0] * p[1];
  }, 0)) / 2;
  const pad = (n) => String(n).padStart(2, "0");

  // ---- data helpers ------------------------------------------------------------------
  const routeOf = (rid) => S.routes.find((r) => r.id === rid);
  const actorOf = (aid) => S.actors.find((a) => a.id === aid);
  const lightOf = (lid) => S.lights.find((l) => l.id === lid);
  const decorOf = (did) => S.decor.find((d) => d.id === did);
  const isApproach = (r) => r.kind === "approach";

  function objectOf(s) {
    if (!S || !s) return null;
    if (s.t === "route") return routeOf(s.id);
    if (s.t === "road") return S.roads[s.i];
    if (s.t === "actor") return actorOf(s.id);
    if (s.t === "light") return lightOf(s.id);
    if (s.t === "decor") return decorOf(s.id);
    if (s.t === "stop") return S.stop;
    return null;
  }

  function uniqueId(prefix, taken) {
    let n = 1;
    while (taken.includes(`${prefix}${n}`)) n++;
    return `${prefix}${n}`;
  }

  function snap() {
    undoStack.push(JSON.stringify(S));
    if (undoStack.length > 300) undoStack.shift();
    redoStack = [];
  }

  function changed(redraw = true) {
    dirty = JSON.stringify(S) !== savedJson;
    schedulePreview();
    if (redraw) Scene3D.refresh(S);
    renderAll();
  }

  function commit(fn, redraw = true) {
    snap();
    fn();
    changed(redraw);
  }

  function undo() {
    if (!undoStack.length) return;
    redoStack.push(JSON.stringify(S));
    S = JSON.parse(undoStack.pop());
    afterHistory();
  }

  function redo() {
    if (!redoStack.length) return;
    undoStack.push(JSON.stringify(S));
    S = JSON.parse(redoStack.pop());
    afterHistory();
  }

  function afterHistory() {
    dirty = JSON.stringify(S) !== savedJson;
    sel = sel && objectOf(sel) ? sel : null;
    Scene3D.refresh(S);
    schedulePreview();
    renderAll();
  }

  // ---- scenes ------------------------------------------------------------------------
  async function loadList() {
    scenes = await api("/api/scenes");
    renderScenes();
  }

  async function openScene(sid) {
    if (dirty && !confirm("Есть несохранённые правки. Открыть другую сцену без сохранения?")) return;
    const r = await api(`/api/scene/${sid}`);
    S = r.scene;
    id = sid;
    findings = r.findings;
    source = r.source;
    undoStack = [];
    redoStack = [];
    dirty = false;
    savedJson = JSON.stringify(S);
    sel = null;
    draft = null;
    tool = "select";
    Scene3D.load(S, r.build);
    Scene3D.setSelection(null);
    $("#empty").hidden = true;
    renderAll();
    renderScenes();
  }

  function sceneTitle(sid) {
    const m = sid.match(/^ticket_(\d+)_(\d+)$/);
    return m ? `Билет ${m[1]} · вопрос ${m[2]}` : sid;
  }

  function renderScenes() {
    const q = query.trim().toLowerCase();
    const list = scenes.filter((s) => (!q || s.id.includes(q) || sceneTitle(s.id).toLowerCase().includes(q)) &&
      (filter === "all" || (filter === "err" && s.errors) || (filter === "todo" && s.status === "unverified")));
    $("#scene-list").innerHTML = list.map((s) => {
      const ok = !s.errors;
      return `<button class="scene-row ${s.id === id ? "on" : ""}" data-id="${s.id}">
        <img src="/preview/${s.id}.png" loading="lazy" onerror="this.style.visibility='hidden'" alt="">
        <span class="scene-text"><b>${esc(sceneTitle(s.id))}</b>
        <small>${s.errors ? `${s.errors} ${plural(s.errors, ["ошибка", "ошибки", "ошибок"])}` : "проверка пройдена"}${s.warns ? ` · ${s.warns} замеч.` : ""}
        · ${s.status === "ok" ? "сверено" : s.status === "fixed" ? "исправлено" : "не сверено"}</small></span>
        <i class="dot ${s.errors ? "bad" : ok && s.status !== "unverified" ? "good" : "todo"}"></i></button>`;
    }).join("") || `<div class="empty-list">Ничего не найдено</div>`;
    $("#count-scenes").textContent = `${list.length} из ${scenes.length}`;
  }

  function plural(n, forms) {
    const m = n % 100, k = n % 10;
    if (m > 10 && m < 20) return forms[2];
    if (k === 1) return forms[0];
    if (k > 1 && k < 5) return forms[1];
    return forms[2];
  }

  // ---- tools -------------------------------------------------------------------------
  function setTool(t) {
    tool = t;
    draft = null;
    Scene3D.setDraft(null);
    renderTools();
    renderStatus();
  }

  function cancelDraft() {
    draft = null;
    Scene3D.setDraft(null);
  }

  function finishDraft() {
    if (!draft) return;
    const d = draft;
    draft = null;
    Scene3D.setDraft(null);
    if (d.kind === "route") {
      const min = 2;
      if (d.points.length < min) return toast("У маршрута должно быть хотя бы две точки", "warn");
      commit(() => {
        const r = addRoute(d.meta, d.points);
        if (r) sel = { t: "route", id: r.id };
      });
    } else if (d.kind === "road") {
      if (d.points.length < 3) return toast("У дороги должно быть хотя бы три точки", "warn");
      commit(() => {
        const rid = uniqueId("road_", S.roads.map((r) => r.id));
        S.roads.push({ id: rid, outer: d.points, holes: [] });
        sel = { t: "road", i: S.roads.length - 1, part: -1 };
      });
    } else if (d.kind === "island") {
      if (d.points.length < 3) return toast("Островку нужно хотя бы три точки", "warn");
      const c = centroid(d.points);
      const i = S.roads.findIndex((r) => inside(c, r.outer));
      if (i < 0) return toast("Островок должен лежать внутри дороги", "bad");
      commit(() => {
        S.roads[i].holes.push(d.points);
        sel = { t: "road", i, part: S.roads[i].holes.length - 1 };
      });
    }
  }

  function centroid(poly) {
    const n = poly.length;
    return { x: poly.reduce((s, p) => s + p[0], 0) / n, z: poly.reduce((s, p) => s + p[1], 0) / n };
  }

  function inside(p, poly) {
    let c = false;
    const pt = Array.isArray(p) ? { x: p[0], z: p[1] } : p;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const [xi, zi] = poly[i], [xj, zj] = poly[j];
      if ((zi > pt.z) !== (zj > pt.z) && pt.x < ((xj - xi) * (pt.z - zi)) / (zj - zi) + xi) c = !c;
    }
    return c;
  }

  function addRoute(meta, points) {
    if (meta.kind === "manoeuvre") {
      const rid = `manoeuvre_${meta.exit}`;
      if (routeOf(rid)) return toast(`Манёвр «${EXIT[meta.exit]}» уже есть — сначала удалите его`, "warn") || null;
      const r = { id: rid, kind: "manoeuvre", points, exit: meta.exit, exitYaw: 0 };
      S.routes.push(r);
      return r;
    }
    if (meta.kind === "choice") {
      const rid = `choice_${meta.label}`;
      if (routeOf(rid)) return toast(`Вариант «${meta.label}» уже есть`, "warn") || null;
      const r = { id: rid, kind: "choice", points, label: meta.label, labelPosition: [points[Math.floor(points.length / 2)][0], points[Math.floor(points.length / 2)][1]] };
      S.routes.push(r);
      return r;
    }
    if (meta.kind === "actor") {
      const a = actorOf(meta.actor);
      if (!a) return null;
      const rid = `actor_${a.id}`;
      const old = routeOf(rid);
      if (old) S.routes.splice(S.routes.indexOf(old), 1);
      const r = { id: rid, kind: "actor", points };
      S.routes.push(r);
      a.route = rid;
      return r;
    }
    return null;
  }

  function insertVertex(owner, seg, world) {
    const at = { x: world.x, z: world.z };
    const pt = [Math.round(at.x * 20) / 20, Math.round(at.z * 20) / 20];
    if (owner.t === "route") {
      const r = routeOf(owner.id);
      if (!r) return;
      commit(() => r.points.splice(seg + 1, 0, pt));
    } else if (owner.t === "road") {
      const ring = ringOf(owner);
      if (ring) commit(() => ring.splice(seg + 1, 0, pt));
    }
  }

  function ringOf(s) {
    const r = S.roads[s.i];
    if (!r) return null;
    return s.part === -1 ? r.outer : r.holes[s.part];
  }

  function deleteVertex(owner, index) {
    if (owner.t === "route") {
      const r = routeOf(owner.id);
      if (!r) return;
      if (r.points.length <= 2) return toast("В маршруте должно остаться две точки", "warn");
      commit(() => r.points.splice(index, 1));
    } else if (owner.t === "road") {
      const ring = ringOf(owner);
      if (!ring) return;
      if (ring.length <= 3) return toast("В контуре должно остаться три точки", "warn");
      commit(() => ring.splice(index, 1));
    }
  }

  function placeAt(t, world) {
    const p = [Math.round(world.x * 20) / 20, Math.round(world.z * 20) / 20];
    if (t === "decor") {
      const prop = opts.prop || (catalog && catalog.props[0] && catalog.props[0].id);
      if (!prop) return;
      commit(() => {
        const did = uniqueId("decor_", S.decor.map((d) => d.id));
        S.decor.push({ id: did, prop, pos: p, yaw: 0, scale: [1, 1, 1], tint: null });
        sel = { t: "decor", id: did };
      });
    } else if (t === "actor") {
      const tpl = catalog && catalog.actorTypes[opts.actorType];
      if (!tpl) return toast("Для этого типа нет модели в сцене-образце", "bad");
      commit(() => {
        const aid = uniqueId(`${opts.actorType}_`, S.actors.map((a) => a.id));
        S.actors.push({ id: aid, type: opts.actorType, name: tpl.name || TYPE[opts.actorType], asset: tpl.asset, route: null,
          pos: p, yaw: 0, scale: [1, 1, 1], maxSpeed: tpl.maxSpeed ?? 12, clearDistance: tpl.clearDistance ?? 6,
          halfLength: tpl.halfLength ?? 2, halfWidth: tpl.halfWidth ?? 0.9, behaviour: { staysPut: false, waitsForPlayer: true } });
        sel = { t: "actor", id: aid };
      });
    } else if (t === "light") {
      if (!catalog || !catalog.lightAsset) return toast("Нет модели светофора", "bad");
      commit(() => {
        const lid = uniqueId("light_", S.lights.map((l) => l.id));
        S.lights.push({ id: lid, pos: p, yaw: 0, scale: 1, arrow: null, state: "red", asset: catalog.lightAsset });
        sel = { t: "light", id: lid };
      });
    } else if (t === "stop") {
      commit(() => moveStop(p[0], p[1]));
      sel = { t: "stop" };
    }
  }

  // The stop line and the end of the approach are one point: moving one moves the other.
  function moveStop(x, z) {
    S.stop.x = x;
    S.stop.z = z;
    const ap = routeOf("approach");
    if (ap) ap.points[ap.points.length - 1] = [x, z];
  }

  // ---- selection and dragging --------------------------------------------------------
  function select(s) {
    sel = s;
    Scene3D.setSelection(s && s.t !== "question" ? s : null);
    renderAll();
  }

  function onPointer(e) {
    if (!S) return;
    if (e.type === "move") {
      cursorWorld = e.world;
      renderStatus();
      if (draft && e.world) {
        draft.cursor = [e.world.x, e.world.z];
        Scene3D.setDraft(draft);
      }
      return;
    }
    if (e.type === "leave") { cursorWorld = null; renderStatus(); return; }
    if (e.type === "down") return pointerDown(e);
    if (e.type === "drag") return pointerDrag(e);
    if (e.type === "up") return pointerUp(e);
    if (e.type === "dblclick") return doubleClick(e);
  }

  function pointerDown(e) {
    const h = e.hit;
    if (tool !== "select") return drawClick(e);
    if (!h) { if (!e.shift) select(null); return; }
    if (h.kind === "vertex") {
      sel = h.owner.t === "route" ? { t: "route", id: h.owner.id } : { ...h.owner };
      sel.v = h.index;
      Scene3D.setSelection(sel);
      snap();
      drag = { kind: "vertex", owner: { ...sel }, index: h.index, moved: false };
      renderAll();
      return;
    }
    if (h.kind === "anchor") {
      sel = { t: h.t, id: h.id };
      Scene3D.setSelection(sel);
      snap();
      drag = { kind: "anchor", t: h.t, id: h.id, moved: false };
      renderAll();
      return;
    }
    if (h.kind === "route") {
      sel = { t: "route", id: h.id };
      Scene3D.setSelection(sel);
      renderAll();
      return;
    }
    if (h.kind === "road") {
      sel = { t: "road", i: h.i, part: h.part };
      Scene3D.setSelection(sel);
      renderAll();
      return;
    }
  }

  function drawClick(e) {
    const w = e.world;
    if (!w) return;
    const pt = [Math.round(w.x * 20) / 20, Math.round(w.z * 20) / 20];
    if (tool === "route") {
      if (!draft) draft = { kind: "route", meta: routeMeta(), points: [] };
      if (draft.kind !== "route") return;
      draft.points.push(pt);
      Scene3D.setDraft(draft);
      renderTools();
      return;
    }
    if (tool === "road" || tool === "island") {
      const kind = tool === "road" ? "road" : "island";
      if (!draft) draft = { kind, points: [] };
      if (draft.points.length >= 3 && dist(pt, draft.points[0]) < 1.2) return finishDraft();
      draft.points.push(pt);
      Scene3D.setDraft(draft);
      renderTools();
      return;
    }
    if (tool === "stop" || tool === "decor" || tool === "actor" || tool === "light") placeAt(tool, w);
    renderAll();
    if (tool !== "stop" && tool !== "decor" && tool !== "actor" && tool !== "light") return;
    setTool("select");
  }

  function routeMeta() {
    if (opts.route === "manoeuvre") return { kind: "manoeuvre", exit: opts.exit };
    if (opts.route === "choice") return { kind: "choice", label: opts.label };
    return { kind: "actor", actor: opts.actorFor || (S.actors[0] && S.actors[0].id) };
  }

  function pointerDrag(e) {
    if (!drag) return;
    const w = e.world;
    if (!w) return;
    if (drag.kind === "vertex") {
      const pt = [w.x, w.z];
      const owner = drag.owner;
      const target = owner.t === "route" ? routeOf(owner.id)?.points : ringOf(owner);
      if (!target) return;
      target[drag.index] = pt;
      drag.moved = true;
      Scene3D.refresh(S);
      Scene3D.setSelection(sel);
      renderStatus();
      return;
    }
    if (drag.kind === "anchor") {
      const x = w.x, z = w.z;
      if (drag.t === "stop") moveStop(x, z);
      else {
        const o = drag.t === "actor" ? actorOf(drag.id) : drag.t === "light" ? lightOf(drag.id) : decorOf(drag.id);
        if (!o) return;
        o.pos = [x, z];
        if (drag.t === "actor" && o.route) {
          const r = routeOf(o.route);
          if (r) r.points[0] = [x, z];
        }
      }
      drag.moved = true;
      Scene3D.refresh(S);
      Scene3D.setSelection(sel);
      renderStatus();
    }
  }

  function pointerUp() {
    if (!drag) return;
    const d = drag;
    drag = null;
    if (!d.moved) { undoStack.pop(); renderAll(); return; }
    dirty = JSON.stringify(S) !== savedJson;
    schedulePreview();
    renderAll();
  }

  function doubleClick(e) {
    if (tool === "route" && draft && draft.kind === "route") {
      if (draft.points.length > 1 && JSON.stringify(draft.points.at(-1)) === JSON.stringify(draft.points.at(-2))) draft.points.pop();
      return finishDraft();
    }
    if ((tool === "road" || tool === "island") && draft) {
      if (draft.points.length > 1 && JSON.stringify(draft.points.at(-1)) === JSON.stringify(draft.points.at(-2))) draft.points.pop();
      return finishDraft();
    }
    if (tool === "select" && e.hit && e.hit.kind === "route" && e.world) {
      insertVertex({ t: "route", id: e.hit.id }, e.hit.seg, e.world);
    } else if (tool === "select" && e.hit && e.hit.kind === "road" && e.world) {
      insertVertex({ t: "road", i: e.hit.i, part: e.hit.part }, e.hit.seg, e.world);
    }
  }

  function deleteSelected() {
    if (!sel) return;
    if (sel.v !== undefined && sel.v >= 0 && (sel.t === "route" || sel.t === "road")) return deleteVertex(sel, sel.v);
    if (sel.t === "route") {
      const r = routeOf(sel.id);
      if (!r) return;
      if (isApproach(r)) return toast("Подъезд к стоп-линии удалить нельзя", "warn");
      commit(() => {
        S.routes.splice(S.routes.indexOf(r), 1);
        const a = S.actors.find((x) => x.route === r.id);
        if (a) a.route = null;
        sel = null;
      });
    } else if (sel.t === "road") {
      commit(() => {
        if (sel.part === -1) S.roads.splice(sel.i, 1);
        else S.roads[sel.i].holes.splice(sel.part, 1);
        sel = null;
      });
    } else if (sel.t === "actor") {
      commit(() => {
        const a = actorOf(sel.id);
        S.actors.splice(S.actors.indexOf(a), 1);
        const r = a.route && routeOf(a.route);
        if (r) S.routes.splice(S.routes.indexOf(r), 1);
        sel = null;
      });
    } else if (sel.t === "light") {
      commit(() => { S.lights.splice(S.lights.indexOf(lightOf(sel.id)), 1); sel = null; });
    } else if (sel.t === "decor") {
      commit(() => { S.decor.splice(S.decor.indexOf(decorOf(sel.id)), 1); sel = null; });
    }
    Scene3D.setSelection(sel);
    renderAll();
  }

  function nudge(dx, dz) {
    if (!sel) return;
    if (sel.v !== undefined && sel.v >= 0) {
      const owner = sel;
      const target = owner.t === "route" ? routeOf(owner.id)?.points : ringOf(owner);
      if (!target) return;
      commit(() => { target[owner.v] = [target[owner.v][0] + dx, target[owner.v][1] + dz]; });
      return;
    }
    const o = objectOf(sel);
    if (!o) return;
    commit(() => {
      if (sel.t === "stop") moveStop(S.stop.x + dx, S.stop.z + dz);
      else o.pos = [o.pos[0] + dx, o.pos[1] + dz];
    });
  }

  function rotate(deg) {
    const o = objectOf(sel);
    if (!o || sel.v !== undefined && sel.v >= 0) return;
    commit(() => {
      if (sel.t === "stop") S.stop.yaw += (deg * Math.PI) / 180;
      else o.yaw += (deg * Math.PI) / 180;
    });
  }

  // ---- live preview ------------------------------------------------------------------
  function schedulePreview() {
    clearTimeout(previewTimer);
    previewTimer = setTimeout(runPreview, 260);
  }

  async function runPreview() {
    if (!S) return;
    const mine = ++seq;
    const sid = id;
    const r = await api(`/api/preview/${sid}`, S).catch(() => null);
    if (!r || mine !== seq || sid !== id) return;
    findings = r.findings;
    Scene3D.setBuild(r.build);
    renderChecks();
    renderStatus();
    renderScenes();
  }

  async function save() {
    if (!S) return;
    if (!dirty) return toast("Все правки сохранены");
    try {
      const r = await api(`/api/scene/${id}`, S);
      dirty = false;
      savedJson = JSON.stringify(S);
      findings = r.findings;
      const gone = r.removed && r.removed.length ? ` · удалено: ${r.removed.join(", ")}` : "";
      toast(`Сохранено · ${r.findings.filter((f) => f.level === "error").length} ошибок${gone}`, r.removed && r.removed.length ? "warn" : "good");
      await loadList();
      renderAll();
    } catch (e) {
      toast(`Не сохранено: ${e.message}`, "bad");
    }
  }

  // ---- rendering ---------------------------------------------------------------------
  function renderAll() {
    renderHeader();
    renderTree();
    renderInspector();
    renderChecks();
    renderTools();
    renderStatus();
    $("#empty").hidden = !!S;
  }

  function renderHeader() {
    const err = findings.filter((f) => f.level === "error").length;
    const warn = findings.filter((f) => f.level === "warn").length;
    $("#title").textContent = S ? sceneTitle(id) : "Выберите сцену";
    $("#status").className = "chip " + (!S ? "" : err ? "bad" : "good");
    $("#status").textContent = !S ? "" : err ? `${err} ${plural(err, ["ошибка", "ошибки", "ошибок"])}` : warn ? `${warn} замеч.` : "всё в порядке";
    $("#dirty").hidden = !dirty;
    $("#save").disabled = !S || !dirty;
    $("#undo").disabled = !undoStack.length;
    $("#redo").disabled = !redoStack.length;
    document.title = S ? `${sceneTitle(id)} · Редактор сцен` : "Редактор сцен";
  }

  function renderTools() {
    document.querySelectorAll("#tools [data-tool]").forEach((b) => b.classList.toggle("on", b.dataset.tool === tool));
    const o = $("#tool-opts");
    const parts = [];
    if (tool === "route") {
      parts.push(`<label>Что рисуем
        <select id="o-route"><option value="manoeuvre" ${opts.route === "manoeuvre" ? "selected" : ""}>Манёвр на выезд</option>
        <option value="choice" ${opts.route === "choice" ? "selected" : ""}>Вариант ответа А/Б/В</option>
        <option value="actor" ${opts.route === "actor" ? "selected" : ""}>Путь участника</option></select></label>`);
      if (opts.route === "manoeuvre") parts.push(`<label>Выезд <select id="o-exit">${Object.entries(EXIT).map(([k, v]) => `<option value="${k}" ${opts.exit === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>`);
      if (opts.route === "choice") parts.push(`<label>Буква <select id="o-label">${LETTERS.map((l) => `<option ${opts.label === l ? "selected" : ""}>${l}</option>`).join("")}</select></label>`);
      if (opts.route === "actor") parts.push(`<label>Участник <select id="o-actor">${S ? S.actors.map((a) => `<option value="${a.id}" ${opts.actorFor === a.id ? "selected" : ""}>${esc(a.name || a.id)}</option>`).join("") : ""}</select></label>`);
    }
    if (tool === "decor" && catalog) {
      parts.push(`<label>Предмет <select id="o-prop">${catalog.props.map((p) => `<option ${opts.prop === p.id ? "selected" : ""}>${p.id}</option>`).join("")}</select></label>`);
    }
    if (tool === "actor" && catalog) {
      parts.push(`<label>Тип <select id="o-type">${Object.keys(catalog.actorTypes).map((t) => `<option value="${t}" ${opts.actorType === t ? "selected" : ""}>${TYPE[t] || t}</option>`).join("")}</select></label>`);
    }
    if (draft) parts.push(`<span class="pill">${draft.kind === "route" ? "точек" : "точек"}: ${draft.points.length}</span>`);
    o.innerHTML = parts.join("");
    o.hidden = !parts.length;
    const bind = (sel, fn) => { const el = $(sel); if (el) el.onchange = () => fn(el); };
    bind("#o-route", (el) => { opts.route = el.value; renderTools(); });
    bind("#o-exit", (el) => { opts.exit = el.value; });
    bind("#o-label", (el) => { opts.label = el.value; });
    bind("#o-actor", (el) => { opts.actorFor = el.value; });
    bind("#o-prop", (el) => { opts.prop = el.value; });
    bind("#o-type", (el) => { opts.actorType = el.value; });
    $("#hint").textContent = TOOLS[tool].hint;
  }

  function renderStatus() {
    $("#cursor").textContent = cursorWorld ? `x ${cursorWorld.x.toFixed(2)} · z ${cursorWorld.z.toFixed(2)} м` : "x — · z — м";
    const px = Scene3D.pxPerM;
    const bar = Math.min(200, Math.max(30, Math.round(10 * px)));
    $("#scale-bar").style.width = bar + "px";
    $("#scale-text").textContent = `10 м`;
    $("#zoom-text").textContent = Scene3D.mode === "plan" ? `${px.toFixed(1)} px/м` : "3D";
  }

  // The object tree (left panel, "Объекты").
  function renderTree() {
    if (!S) { $("#object-tree").innerHTML = `<div class="empty-list">Откройте сцену, чтобы увидеть её объекты</div>`; return; }
    const q = objQuery.trim().toLowerCase();
    const hit = (t) => !q || t.toLowerCase().includes(q);
    const group = (key, title, count, body) => {
      const open = openGroups[key] !== false;
      return `<div class="tree-group"><button class="tree-head" data-group="${key}">
        <span class="caret">${open ? "▾" : "▸"}</span>${title}<em>${count}</em></button>${open ? `<div class="tree-body">${body}</div>` : ""}</div>`;
    };
    const row = (s, label, extra = "", cls = "") => {
      const on = sel && sel.t === s.t && (s.t === "stop" || sel.id === s.id) && (sel.i === undefined || sel.i === s.i) && (sel.part === undefined || sel.part === s.part);
      return `<button class="tree-row ${on ? "on" : ""} ${cls}" data-sel='${esc(JSON.stringify(s))}'>${label}${extra ? `<small>${extra}</small>` : ""}</button>`;
    };
    const roads = S.roads.map((r, i) => {
      const main = row({ t: "road", i, part: -1 }, `Дорога ${i + 1}`, `${Math.round(area(r.outer))} м²${r.holes.length ? ` · островков ${r.holes.length}` : ""}`);
      const holes = r.holes.map((h, k) => row({ t: "road", i, part: k }, `Островок ${k + 1}`, `${Math.round(area(h))} м²`, "sub")).join("");
      return hit(`дорога ${i + 1}`) || holes ? main + holes : "";
    }).join("");
    const routeRows = (kind) => S.routes.filter((r) => r.kind === kind).map((r) => {
      const name = kind === "manoeuvre" ? `Манёвр «${EXIT[r.exit]}»` : kind === "choice" ? `Вариант ${r.label}` : kind === "approach" ? "Подъезд к стоп-линии" : `Путь: ${actorOf(r.id.replace("actor_", ""))?.name || r.id}`;
      return hit(name) ? row({ t: "route", id: r.id }, name, `${r.points.length} точ.`) : "";
    }).join("");
    const actors = S.actors.map((a) => hit(a.name || a.id) ? row({ t: "actor", id: a.id }, esc(a.name || a.id), TYPE[a.type] || a.type) : "").join("");
    const lights = S.lights.map((l) => hit("светофор") ? row({ t: "light", id: l.id }, `Светофор ${l.id.replace("light_", "")}`, LIGHT[l.state] || "") : "").join("");
    const decorByProp = {};
    S.decor.forEach((d) => { (decorByProp[d.prop] = decorByProp[d.prop] || []).push(d); });
    const decor = Object.entries(decorByProp).map(([p, list]) => hit(p) ? `<div class="tree-sub"><span>${p}</span><em>${list.length}</em></div>${list.map((d, k) => row({ t: "decor", id: d.id }, `${p.split("/").pop()} ${k + 1}`, `${d.pos[0].toFixed(1)}, ${d.pos[1].toFixed(1)}`, "sub")).join("")}` : "").join("");
    $("#object-tree").innerHTML = [
      group("roads", "Дорожное полотно", S.roads.length, roads || `<div class="tree-none">Нет дорог</div>`),
      group("routes", "Маршруты", S.routes.length, ["manoeuvre", "choice", "approach", "actor"].map((k) => routeRows(k)).join("") || `<div class="tree-none">Нет маршрутов</div>`),
      group("stop", "Стоп-линия и старт", 1, row({ t: "stop" }, "Стоп-линия / старт", `${S.stop.x.toFixed(2)}, ${S.stop.z.toFixed(2)}`)),
      group("actors", "Участники", S.actors.length, actors || `<div class="tree-none">Нет участников</div>`),
      group("lights", "Светофоры", S.lights.length, lights || `<div class="tree-none">Нет светофоров</div>`),
      group("decor", "Декор у дороги", S.decor.length, decor || `<div class="tree-none">Нет декора</div>`),
    ].join("");
  }

  // The right panel: properties of the selection, or the scene overview.
  function renderInspector() {
    const pane = $("#rpane");
    document.querySelectorAll("#rtabs [data-rtab]").forEach((b) => b.classList.toggle("on", b.dataset.rtab === rtab));
    if (!S) { pane.innerHTML = `<div class="empty-pane">Выберите сцену слева, чтобы начать.</div>`; return; }
    if (rtab === "question") return renderQuestion(pane);
    if (rtab === "checks") return renderChecks();
    if (!sel) return renderOverview(pane);
    const o = objectOf(sel);
    if (!o) return renderOverview(pane);
    if (sel.t === "route") return renderRoute(pane, o);
    if (sel.t === "road") return renderRoad(pane, o);
    if (sel.t === "actor") return renderActor(pane, o);
    if (sel.t === "light") return renderLight(pane, o);
    if (sel.t === "decor") return renderDecor(pane, o);
    if (sel.t === "stop") return renderStop(pane);
  }

  function renderOverview(pane) {
    const err = findings.filter((f) => f.level === "error").length;
    pane.innerHTML = `
      <section class="card">
        <h3>Сцена</h3>
        <dl class="kv"><dt>Дороги</dt><dd>${S.roads.length}</dd><dt>Маршруты</dt><dd>${S.routes.length}</dd>
        <dt>Участники</dt><dd>${S.actors.length}</dd><dt>Светофоры</dt><dd>${S.lights.length}</dd><dt>Декор</dt><dd>${S.decor.length}</dd>
        <dt>Проверка</dt><dd class="${err ? "bad-t" : "good-t"}">${err ? `${err} ${plural(err, ["ошибка", "ошибки", "ошибок"])}` : "ошибок нет"}</dd></dl>
      </section>
      <section class="card">
        <h3>Как работать</h3>
        <ul class="howto">
          <li>Нажмите объект на плане или в списке «Объекты» слева.</li>
          <li>Тяните точки линий и объекты. Стрелки двигают на 5 см, Shift — на 50 см.</li>
          <li><kbd>V</kbd> выбор, <kbd>M</kbd> маршрут, <kbd>D</kbd> дорога, <kbd>I</kbd> островок, <kbd>P</kbd> декор, <kbd>A</kbd> участник, <kbd>L</kbd> светофор, <kbd>S</kbd> стоп-линия.</li>
          <li><kbd>⌘Z</kbd> отмена, <kbd>⌘S</kbd> сохранить, <kbd>F</kbd> весь вид, <kbd>?</kbd> все клавиши.</li>
        </ul>
      </section>`;
  }

  function fieldNum(label, value, key, step = 0.05, unit = "") {
    return `<label class="field"><span>${label}${unit ? ` <em>${unit}</em>` : ""}</span>
      <input type="number" step="${step}" value="${value === undefined || value === null ? "" : Number(value).toFixed(3).replace(/\.?0+$/, "")}" data-f="${key}"></label>`;
  }

  function bindForm(pane, handlers) {
    pane.querySelectorAll("[data-f]").forEach((el) => {
      const h = handlers[el.dataset.f];
      if (!h) return;
      el.addEventListener("change", () => h(el));
    });
    pane.querySelectorAll("[data-act]").forEach((el) => {
      const h = handlers[el.dataset.act];
      if (h) el.addEventListener("click", () => h(el));
    });
  }

  function renderRoute(pane, r) {
    const approach = isApproach(r);
    const actor = r.kind === "actor" ? actorOf(r.id.replace("actor_", "")) : null;
    const pts = r.points;
    const title = r.kind === "manoeuvre" ? `Манёвр «${EXIT[r.exit]}»` : r.kind === "choice" ? `Вариант ${r.label}` : approach ? "Подъезд к стоп-линии" : `Путь участника${actor ? `: ${esc(actor.name)}` : ""}`;
    const extra = r.kind === "manoeuvre"
      ? `<div class="row">${`<label class="field"><span>Выезд</span><select data-f="exit">${Object.entries(EXIT).map(([k, v]) => `<option value="${k}" ${r.exit === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>`}</div>
         ${fieldNum("Поворот выезда", (r.exitYaw || 0) * RAD, "exitYaw", 1, "°")}
         <p class="note">${S.question.maneuver === r.exit ? "Это правильный манёвр по условию вопроса — по нему поедет машина." : "Альтернативный выезд. Машина поедет по нему, только если его выберет игрок."}</p>`
      : r.kind === "choice"
        ? `<label class="field"><span>Буква на дороге</span><select data-f="label">${LETTERS.map((l) => `<option ${r.label === l ? "selected" : ""}>${l}</option>`).join("")}</select></label>
           <div class="row"><button class="btn" data-act="letter-mid">Поставить букву в середину пути</button></div>`
        : approach
          ? `<p class="note">Конец подъезда всегда совпадает со стоп-линией. Двигайте стоп-линию — подъезд подстроится.</p>`
          : `<div class="row"><button class="btn" data-act="actor-of-route">Открыть участника</button>
              <button class="btn danger" data-act="route-unlink">Отвязать путь</button></div>`;
    pane.innerHTML = `
      <section class="card">
        <div class="card-head"><h3>${title}</h3><span class="pill">${r.id}</span></div>
        ${extra}
        <div class="stats">Точек: <b>${pts.length}</b> · длина: <b>${polyLength(pts).toFixed(1)} м</b></div>
        ${sel.v !== undefined && sel.v >= 0 ? `<div class="sel-pt">Точка ${sel.v + 1}: ${pts[sel.v][0].toFixed(2)}, ${pts[sel.v][1].toFixed(2)}</div>` : ""}
        <div class="actions">
          <button class="btn" data-act="pt-add">Добавить точку в конец</button>
          <button class="btn danger" data-act="route-del" ${approach ? "disabled" : ""}>Удалить маршрут</button>
        </div>
      </section>
      <section class="card">
        <h3>Точки</h3>
        <div class="pts">${pts.map((p, i) => `<div class="pt ${sel.v === i ? "on" : ""}" data-pt="${i}"><span>${i + 1}</span>
          <input type="number" step="0.05" value="${p[0].toFixed(2)}" data-pt-x="${i}"><input type="number" step="0.05" value="${p[1].toFixed(2)}" data-pt-z="${i}">
          <button class="icon-btn" data-pt-del="${i}" title="Удалить точку">×</button></div>`).join("")}</div>
      </section>`;
    bindForm(pane, {
      exit: (el) => commit(() => { r.exit = el.value; r.id = `manoeuvre_${el.value}`; sel = { t: "route", id: r.id }; }),
      exitYaw: (el) => commit(() => { r.exitYaw = Number(el.value) / RAD; }),
      label: (el) => commit(() => { r.label = el.value; r.id = `choice_${el.value}`; sel = { t: "route", id: r.id }; }),
      "letter-mid": () => commit(() => { const m = pts[Math.floor(pts.length / 2)]; r.labelPosition = [m[0], m[1]]; }),
      "pt-add": () => commit(() => { const l = pts.at(-1), q = pts.at(-2) || l; pts.push([+(l[0] + (l[0] - q[0]) * 0.5).toFixed(2), +(l[1] + (l[1] - q[1]) * 0.5).toFixed(2)]); }),
      "route-del": () => deleteSelected(),
      "route-unlink": () => commit(() => { actor.route = null; S.routes.splice(S.routes.indexOf(r), 1); sel = { t: "actor", id: actor.id }; }),
      "actor-of-route": () => select({ t: "actor", id: actor.id }),
    });
    pane.querySelectorAll("[data-pt-x],[data-pt-z]").forEach((el) => el.addEventListener("change", () => {
      const i = Number(el.dataset.ptX ?? el.dataset.ptZ);
      commit(() => { pts[i] = [el.dataset.ptX !== undefined ? Number(el.value) : pts[i][0], el.dataset.ptZ !== undefined ? Number(el.value) : pts[i][1]]; });
    }));
    pane.querySelectorAll("[data-pt]").forEach((el) => el.addEventListener("click", (e) => {
      if (e.target.closest("input,button")) return;
      sel = { ...sel, v: Number(el.dataset.pt) };
      Scene3D.setSelection(sel);
      renderInspector();
    }));
    pane.querySelectorAll("[data-pt-del]").forEach((el) => el.addEventListener("click", () => deleteVertex(sel, Number(el.dataset.ptDel))));
  }

  function renderRoad(pane, road) {
    const ring = ringOf(sel);
    const holes = road.holes.map((h, k) => `<button class="tree-row ${sel.part === k ? "on" : ""}" data-hole="${k}">Островок ${k + 1}<small>${Math.round(area(h))} м² · точек ${h.length}</small></button>`).join("");
    pane.innerHTML = `
      <section class="card">
        <div class="card-head"><h3>${sel.part === -1 ? "Дорога" : `Островок ${sel.part + 1}`}</h3><span class="pill">road_${sel.i}</span></div>
        <div class="stats">Площадь: <b>${Math.round(area(road.outer))} м²</b> · точек контура: <b>${road.outer.length}</b>${road.holes.length ? ` · островков: <b>${road.holes.length}</b>` : ""}</div>
        <p class="note">Дорога — это контур. Островки внутри него не едут. Тяните углы на плане, двойной клик по стороне добавляет угол.</p>
        <div class="actions">
          <button class="btn" data-act="island">Нарисовать островок</button>
          ${sel.part !== -1 ? `<button class="btn danger" data-act="hole-del">Удалить островок</button>` : `<button class="btn danger" data-act="road-del">Удалить дорогу</button>`}
        </div>
      </section>
      ${holes ? `<section class="card"><h3>Островки</h3>${holes}</section>` : ""}
      <section class="card"><h3>Точки ${sel.part === -1 ? "контура" : "островка"}</h3>
        <div class="pts">${ring.map((p, i) => `<div class="pt ${sel.v === i ? "on" : ""}" data-pt="${i}"><span>${i + 1}</span>
          <input type="number" step="0.05" value="${p[0].toFixed(2)}" data-rx="${i}"><input type="number" step="0.05" value="${p[1].toFixed(2)}" data-rz="${i}">
          <button class="icon-btn" data-rdel="${i}" title="Удалить точку">×</button></div>`).join("")}</div>
      </section>`;
    bindForm(pane, {
      "island": () => setTool("island"),
      "hole-del": () => deleteSelected(),
      "road-del": () => deleteSelected(),
    });
    pane.querySelectorAll("[data-hole]").forEach((el) => el.addEventListener("click", () => select({ t: "road", i: sel.i, part: Number(el.dataset.hole) })));
    pane.querySelectorAll("[data-rx],[data-rz]").forEach((el) => el.addEventListener("change", () => {
      const i = Number(el.dataset.rx ?? el.dataset.rz);
      commit(() => { ring[i] = [el.dataset.rx !== undefined ? Number(el.value) : ring[i][0], el.dataset.rz !== undefined ? Number(el.value) : ring[i][1]]; });
    }));
    pane.querySelectorAll("[data-rdel]").forEach((el) => el.addEventListener("click", () => deleteVertex(sel, Number(el.dataset.rdel))));
    pane.querySelectorAll("[data-pt]").forEach((el) => el.addEventListener("click", (e) => {
      if (e.target.closest("input,button")) return;
      sel = { ...sel, v: Number(el.dataset.pt) };
      Scene3D.setSelection(sel);
      renderInspector();
    }));
  }

  function renderActor(pane, a) {
    const r = a.route && routeOf(a.route);
    const types = catalog ? Object.keys(catalog.actorTypes) : [a.type];
    pane.innerHTML = `
      <section class="card">
        <div class="card-head"><h3>${esc(a.name || a.id)}</h3><span class="pill">${a.id}</span></div>
        <label class="field"><span>Название</span><input type="text" value="${esc(a.name)}" data-f="name"></label>
        <label class="field"><span>Тип</span><select data-f="type">${types.map((t) => `<option value="${t}" ${a.type === t ? "selected" : ""}>${TYPE[t] || t}</option>`).join("")}</select></label>
        <div class="row2">${fieldNum("X", a.pos[0], "x", 0.05, "м")}${fieldNum("Z", a.pos[1], "z", 0.05, "м")}</div>
        <div class="row2">${fieldNum("Поворот", a.yaw * RAD, "yaw", 1, "°")}${fieldNum("Масштаб", a.scale[0], "scale", 0.05)}</div>
      </section>
      <section class="card">
        <h3>Движение</h3>
        <div class="row2">${fieldNum("Скорость", a.maxSpeed, "maxSpeed", 0.5, "м/с")}${fieldNum("Дистанция", a.clearDistance, "clearDistance", 0.5, "м")}</div>
        <label class="check"><input type="checkbox" data-f="staysPut" ${a.behaviour?.staysPut ? "checked" : ""}> Стоит на месте (припаркован)</label>
        <label class="check"><input type="checkbox" data-f="waitsForPlayer" ${a.behaviour?.waitsForPlayer ? "checked" : ""}> Пропускает игрока</label>
        <div class="route-line">${r ? `Путь: ${r.points.length} точек, ${polyLength(r.points).toFixed(1)} м` : "Пути нет — участник стоит"}</div>
        <div class="actions">
          <button class="btn" data-act="actor-route">${r ? "Перерисовать путь" : "Нарисовать путь"}</button>
          ${r ? `<button class="btn" data-act="actor-route-sel">Показать путь</button>` : ""}
        </div>
      </section>
      <section class="card"><div class="actions"><button class="btn danger" data-act="actor-del">Удалить участника</button></div></section>`;
    bindForm(pane, {
      name: (el) => commit(() => { a.name = el.value; }),
      type: (el) => commit(() => { a.type = el.value; const tpl = catalog.actorTypes[el.value]; if (tpl) { a.asset = tpl.asset; } }),
      x: (el) => commit(() => { a.pos[0] = Number(el.value); if (r) r.points[0] = [a.pos[0], a.pos[1]]; }),
      z: (el) => commit(() => { a.pos[1] = Number(el.value); if (r) r.points[0] = [a.pos[0], a.pos[1]]; }),
      yaw: (el) => commit(() => { a.yaw = Number(el.value) / RAD; }),
      scale: (el) => commit(() => { a.scale = [Number(el.value), Number(el.value), Number(el.value)]; }),
      maxSpeed: (el) => commit(() => { a.maxSpeed = Number(el.value); }),
      clearDistance: (el) => commit(() => { a.clearDistance = Number(el.value); }),
      staysPut: (el) => commit(() => { a.behaviour = { ...(a.behaviour || {}), staysPut: el.checked }; }),
      waitsForPlayer: (el) => commit(() => { a.behaviour = { ...(a.behaviour || {}), waitsForPlayer: el.checked }; }),
      "actor-route": () => { opts.route = "actor"; opts.actorFor = a.id; setTool("route"); },
      "actor-route-sel": () => select({ t: "route", id: r.id }),
      "actor-del": () => deleteSelected(),
    });
  }

  function renderLight(pane, l) {
    pane.innerHTML = `
      <section class="card">
        <div class="card-head"><h3>Светофор</h3><span class="pill">${l.id}</span></div>
        <label class="field"><span>Сигнал</span><select data-f="state">${Object.entries(LIGHT).map(([k, v]) => `<option value="${k}" ${l.state === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
        <label class="field"><span>Стрелка</span><select data-f="arrow">${Object.entries(ARROW).map(([k, v]) => `<option value="${k}" ${(l.arrow || "") === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
        <div class="row2">${fieldNum("X", l.pos[0], "x", 0.05, "м")}${fieldNum("Z", l.pos[1], "z", 0.05, "м")}</div>
        <div class="row2">${fieldNum("Поворот", l.yaw * RAD, "yaw", 1, "°")}${fieldNum("Масштаб", l.scale, "scale", 0.05)}</div>
        <div class="actions"><button class="btn danger" data-act="light-del">Удалить светофор</button></div>
      </section>`;
    bindForm(pane, {
      state: (el) => commit(() => { l.state = el.value; }, false),
      arrow: (el) => commit(() => { l.arrow = el.value || null; }),
      x: (el) => commit(() => { l.pos[0] = Number(el.value); }),
      z: (el) => commit(() => { l.pos[1] = Number(el.value); }),
      yaw: (el) => commit(() => { l.yaw = Number(el.value) / RAD; }),
      scale: (el) => commit(() => { l.scale = Number(el.value); }),
      "light-del": () => deleteSelected(),
    });
  }

  function renderDecor(pane, d) {
    const props = catalog ? catalog.props.map((p) => p.id) : [d.prop];
    pane.innerHTML = `
      <section class="card">
        <div class="card-head"><h3>${d.prop.split("/").pop()}</h3><span class="pill">${d.id}</span></div>
        <label class="field"><span>Предмет</span><select data-f="prop">${props.map((p) => `<option ${d.prop === p ? "selected" : ""}>${p}</option>`).join("")}</select></label>
        <div class="row2">${fieldNum("X", d.pos[0], "x", 0.05, "м")}${fieldNum("Z", d.pos[1], "z", 0.05, "м")}</div>
        <div class="row2">${fieldNum("Поворот", d.yaw * RAD, "yaw", 1, "°")}${fieldNum("Масштаб", d.scale[0], "scale", 0.05)}</div>
        <label class="field"><span>Оттенок</span><div class="tint"><input type="color" value="${d.tint || "#ffffff"}" data-f="tint"><button class="btn" data-act="tint-clear">Без оттенка</button></div></label>
        <div class="actions"><button class="btn danger" data-act="decor-del">Удалить предмет</button></div>
      </section>`;
    bindForm(pane, {
      prop: (el) => commit(() => { d.prop = el.value; }),
      x: (el) => commit(() => { d.pos[0] = Number(el.value); }),
      z: (el) => commit(() => { d.pos[1] = Number(el.value); }),
      yaw: (el) => commit(() => { d.yaw = Number(el.value) / RAD; }),
      scale: (el) => commit(() => { d.scale = [Number(el.value), Number(el.value), Number(el.value)]; }),
      tint: (el) => commit(() => { d.tint = el.value; }),
      "tint-clear": () => commit(() => { d.tint = null; }),
      "decor-del": () => deleteSelected(),
    });
  }

  function renderStop(pane) {
    const ap = routeOf("approach");
    pane.innerHTML = `
      <section class="card">
        <div class="card-head"><h3>Стоп-линия и старт</h3><span class="pill">stop</span></div>
        <div class="row2">${fieldNum("X", S.stop.x, "x", 0.05, "м")}${fieldNum("Z", S.stop.z, "z", 0.05, "м")}</div>
        ${fieldNum("Направление", S.stop.yaw * RAD, "yaw", 1, "°")}
        <p class="note">Стоп-линия и конец подъезда — одна точка. Перетащите её на плане или введите координаты.</p>
        <div class="actions">
          <button class="btn" data-act="stop-to-approach">Поставить в конец подъезда</button>
          ${ap ? `<button class="btn" data-act="approach-sel">Показать подъезд</button>` : ""}
        </div>
      </section>`;
    bindForm(pane, {
      x: (el) => commit(() => moveStop(Number(el.value), S.stop.z)),
      z: (el) => commit(() => moveStop(S.stop.x, Number(el.value))),
      yaw: (el) => commit(() => { S.stop.yaw = Number(el.value) / RAD; }),
      "stop-to-approach": () => ap && commit(() => moveStop(ap.points.at(-1)[0], ap.points.at(-1)[1])),
      "approach-sel": () => select({ t: "route", id: "approach" }),
    });
  }

  // The question: the original ticket picture and text, and the answer and rules the game uses.
  function renderQuestion(pane) {
    const q = S.question;
    const ru = (q.text && q.text.ru) || {};
    const src = source;
    const srcBlock = src ? `
      <section class="card">
        <div class="card-head"><h3>Оригинал билета</h3><span class="pill">${src.category === "ab" ? "A/B" : "C/D"} · билет ${src.ticket}, вопрос ${src.number}</span></div>
        ${src.image ? `<img class="orig" src="/asset/source/${src.image}.webp" alt="Картинка из билета">` : ""}
        <p class="orig-q">${esc(src.question)}</p>
        <ol class="answers">${src.answers.map((a) => `<li class="${a.correct ? "ok" : ""}">${esc(a.text)}${a.correct ? " ✓" : ""}</li>`).join("")}</ol>
        ${src.comment ? `<details><summary>Комментарий из билета</summary><p class="comment">${esc(src.comment)}</p></details>` : ""}
      </section>` : `<section class="card"><p class="note">Для этой сцены нет оригинала билета.</p></section>`;
    const options = (ru.options || []);
    const yieldActors = S.actors.map((a) => `<label class="check"><input type="checkbox" data-yield="${a.id}" ${(q.yieldTo || []).includes(a.id) ? "checked" : ""}> ${esc(a.name || a.id)}</label>`).join("");
    pane.innerHTML = `
      ${srcBlock}
      <section class="card">
        <h3>Что видит игрок</h3>
        <p class="qtitle">${esc(ru.title || "")}</p>
        <div class="options">${options.map((o, i) => `<label class="opt ${q.correct === i ? "on" : ""}"><input type="radio" name="correct" value="${i}" ${q.correct === i ? "checked" : ""}> ${esc(o)}</label>`).join("")}</div>
        <div class="row2">
          <label class="field"><span>Манёвр по условию</span><select data-f="maneuver">${["straight", "left", "right", "uturn"].map((m) => `<option value="${m}" ${q.maneuver === m ? "selected" : ""}>${EXIT[m] || "прямо"}</option>`).join("")}</select></label>
          ${fieldNum("Ограничение", q.speedLimit, "speedLimit", 1, "км/ч")}
        </div>
        <div class="row2">${fieldNum("Пауза на красном", q.redWait, "redWait", 0.5, "с")}${fieldNum("Стоп на z", q.requiredStop, "requiredStop", 0.1, "м")}</div>
        <div class="field"><span>Уступить дорогу</span><div class="checks">${yieldActors || `<em class="note">Участников нет</em>`}</div></div>
      </section>
      <section class="card">
        <h3>Сверка с билетом</h3>
        <label class="field"><span>Статус</span><select data-f="status">${[["unverified", "Не сверено"], ["ok", "Соответствует билету"], ["fixed", "Исправлено вручную"]].map(([k, v]) => `<option value="${k}" ${(S.compliance || {}).status === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
        <label class="field"><span>Заметки</span><textarea rows="3" data-f="notes" placeholder="Что не так, что поправили">${esc((S.compliance || {}).notes || "")}</textarea></label>
      </section>`;
    pane.querySelectorAll('input[name="correct"]').forEach((el) => el.addEventListener("change", () => commit(() => { q.correct = Number(el.value); }, false)));
    bindForm(pane, {
      maneuver: (el) => commit(() => { q.maneuver = el.value; S.spec = { ...(S.spec || {}), maneuver: el.value }; }, false),
      speedLimit: (el) => commit(() => { q.speedLimit = el.value === "" ? null : Number(el.value); }),
      redWait: (el) => commit(() => { q.redWait = el.value === "" ? null : Number(el.value); }),
      requiredStop: (el) => commit(() => { q.requiredStop = el.value === "" ? null : Number(el.value); }),
      status: (el) => commit(() => { S.compliance = { ...(S.compliance || {}), status: el.value }; }, false),
      notes: (el) => commit(() => { S.compliance = { ...(S.compliance || {}), notes: el.value }; }, false),
    });
    pane.querySelectorAll("[data-yield]").forEach((el) => el.addEventListener("change", () => commit(() => {
      const list = new Set(q.yieldTo || []);
      el.checked ? list.add(el.dataset.yield) : list.delete(el.dataset.yield);
      q.yieldTo = [...list];
    }, false)));
  }

  // Checks: each finding points at the object it is about.
  function renderChecks() {
    const pane = $("#rpane");
    const err = findings.filter((f) => f.level === "error").length;
    const warn = findings.filter((f) => f.level === "warn").length;
    $("#check-count").textContent = findings.length ? `${err + warn}` : "";
    $("#check-count").className = err ? "count bad" : warn ? "count warn" : "count";
    if (rtab !== "checks") return;
    if (!S) return;
    const items = findings.length ? findings.map((f, i) => `
      <button class="finding ${f.level}" data-finding="${i}">
        <i>${f.level === "error" ? "✕" : "!"}</i><span>${esc(f.message)}</span></button>`).join("")
      : `<div class="ok-box">✓ Ошибок нет: дорога, маршруты и участники на месте.</div>`;
    pane.innerHTML = `<section class="card"><h3>Проверка сцены</h3><p class="note">Ошибки мешают игре. Предупреждения — проверьте глазами. Нажмите строку, чтобы перейти к объекту.</p>${items}</section>`;
    pane.querySelectorAll("[data-finding]").forEach((el) => el.addEventListener("click", () => focusFinding(findings[Number(el.dataset.finding)])));
  }

  function focusFinding(f) {
    const ref = f.ref;
    if (!ref) return;
    if (ref.type === "question") { rtab = "question"; renderInspector(); return; }
    let s = null;
    if (ref.type === "route") s = { t: "route", id: ref.id };
    else if (ref.type === "road") { const i = S.roads.findIndex((r) => r.id === ref.id); if (i >= 0) s = { t: "road", i, part: -1 }; }
    else if (ref.type === "stop") s = { t: "stop" };
    else if (ref.type === "light") s = { t: "light", id: ref.id };
    else if (ref.type === "actor") s = { t: "actor", id: ref.id };
    else if (ref.type === "prop") s = ref.id ? { t: "decor", id: ref.id } : null;
    if (!s) return;
    rtab = "props";
    select(s);
    const o = objectOf(s);
    const at = o && (o.points || o.outer || (o.pos ? o.pos : null));
    if (at) {
      const c = at.length && Array.isArray(at[0]) ? at[Math.floor(at.length / 2)] : at;
      Scene3D.focus(c[0], c[1]);
    }
  }

  // ---- boot --------------------------------------------------------------------------
  function bindUi() {
    $("#scene-list").addEventListener("click", (e) => {
      const b = e.target.closest("[data-id]");
      if (b) openScene(b.dataset.id).catch((err) => toast(err.message, "bad"));
    });
    $("#q").addEventListener("input", (e) => { query = e.target.value; renderScenes(); });
    $("#filters").addEventListener("click", (e) => {
      const b = e.target.closest("[data-f]");
      if (!b) return;
      filter = b.dataset.f;
      document.querySelectorAll("#filters button").forEach((x) => x.classList.toggle("on", x === b));
      renderScenes();
    });
    document.querySelectorAll("[data-ltab]").forEach((b) => b.addEventListener("click", () => {
      ltab = b.dataset.ltab;
      document.querySelectorAll("[data-ltab]").forEach((x) => x.classList.toggle("on", x === b));
      $("#pane-scenes").hidden = ltab !== "scenes";
      $("#pane-objects").hidden = ltab !== "objects";
    }));
    $("#oq").addEventListener("input", (e) => { objQuery = e.target.value; renderTree(); });
    $("#object-tree").addEventListener("click", (e) => {
      const g = e.target.closest("[data-group]");
      if (g) { openGroups[g.dataset.group] = openGroups[g.dataset.group] === false; renderTree(); return; }
      const r = e.target.closest("[data-sel]");
      if (r) { const s = JSON.parse(r.dataset.sel); select(s); focusSelection(s); }
    });
    document.querySelectorAll("[data-rtab]").forEach((b) => b.addEventListener("click", () => {
      rtab = b.dataset.rtab;
      renderInspector();
      renderChecks();
    }));
    document.querySelectorAll("#tools [data-tool]").forEach((b) => b.addEventListener("click", () => setTool(b.dataset.tool)));
    $("#undo").onclick = undo;
    $("#redo").onclick = redo;
    $("#save").onclick = save;
    $("#help").onclick = () => $("#help-dialog").hidden = false;
    $("#help-dialog").addEventListener("click", (e) => { if (e.target.id === "help-dialog" || e.target.dataset.close !== undefined) $("#help-dialog").hidden = true; });
    $("#zin").onclick = () => Scene3D.zoomBy(1.25);
    $("#zout").onclick = () => Scene3D.zoomBy(0.8);
    $("#zfit").onclick = () => Scene3D.fit();
    $("#mode").onclick = () => { Scene3D.setMode(Scene3D.mode === "plan" ? "3d" : "plan"); $("#mode").textContent = Scene3D.mode === "plan" ? "3D вид" : "Вид сверху"; renderStatus(); };
    addEventListener("beforeunload", (e) => { if (dirty) { e.preventDefault(); e.returnValue = ""; } });
    document.addEventListener("keydown", onKey);
    Scene3D.on("pointer", onPointer);
    Scene3D.on("zoom", renderStatus);
  }

  function focusSelection(s) {
    const o = objectOf(s);
    if (!o) return;
    let c = null;
    if (s.t === "stop") c = [S.stop.x, S.stop.z];
    else if (o.pos) c = o.pos;
    else if (o.points) c = o.points[Math.floor(o.points.length / 2)];
    else if (o.outer) c = o.outer[0];
    if (c) Scene3D.focus(c[0], c[1]);
  }

  function isTyping(e) {
    const t = e.target;
    return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable);
  }

  function onKey(e) {
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === "s") { e.preventDefault(); return save(); }
    if (mod && e.key.toLowerCase() === "z") { e.preventDefault(); return e.shiftKey ? redo() : undo(); }
    if (isTyping(e) || mod) return;
    if (!S) return;
    const k = e.key.toLowerCase();
    const map = { v: "select", m: "route", d: "road", i: "island", p: "decor", a: "actor", l: "light", s: "stop" };
    if (map[k] && !e.altKey) { e.preventDefault(); return setTool(map[k]); }
    if (k === "escape") { cancelDraft(); setTool("select"); select(null); return; }
    if (k === "enter") { e.preventDefault(); return finishDraft(); }
    if (k === "backspace" || k === "delete") { e.preventDefault(); return deleteSelected(); }
    const step = e.shiftKey ? 0.5 : 0.05;
    if (k === "arrowleft") { e.preventDefault(); return nudge(-step, 0); }
    if (k === "arrowright") { e.preventDefault(); return nudge(step, 0); }
    if (k === "arrowup") { e.preventDefault(); return nudge(0, step); }
    if (k === "arrowdown") { e.preventDefault(); return nudge(0, -step); }
    if (k === "[") return rotate(e.shiftKey ? -45 : -5);
    if (k === "]") return rotate(e.shiftKey ? 45 : 5);
    if (k === "f") return Scene3D.fit();
    if (k === "?") return ($("#help-dialog").hidden = false);
  }

  async function boot() {
    bindUi();
    Scene3D.mount($("#view"));
    catalog = await api("/api/catalog");
    await loadList();
    renderAll();
    renderTools();
    renderStatus();
    const first = new URLSearchParams(location.search).get("scene");
    if (first) openScene(first).catch((err) => toast(err.message, "bad"));
  }

  return { boot, get S() { return S; } };
})();

document.addEventListener("DOMContentLoaded", () => Ed.boot().catch((e) => {
  document.getElementById("toast").textContent = "Ошибка запуска: " + e.message;
  document.getElementById("toast").className = "toast show bad";
}));
