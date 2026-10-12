// The editor's logic: scenes, the object tree, the tools and their guide, the inspector, the question
// panel, checks, the textures, undo/redo, live preview and saving. The 3D view is in scene3d.js,
// the textures' numbers and pictures in textures.js.
const Ed = (() => {
  const $ = (s) => document.querySelector(s);
  const esc = (v) => String(v ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const ic = (name, cls = "") => `<svg class="i ${cls}" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const RAD = 180 / Math.PI;
  const EXIT = { left: "налево", right: "направо", straight: "прямо", uturn: "разворот" };
  const TYPE = { car: "Легковой автомобиль", truck: "Грузовик", bus: "Автобус", tram: "Трамвай", pedestrian: "Пешеход",
    cyclist: "Велосипедист", motorcycle: "Мотоцикл", special: "Спецмашина", van: "Фургон", tanker: "Цистерна", cart: "Повозка" };
  const LIGHT = { red: "Красный", yellow: "Жёлтый", green: "Зелёный", flashing_yellow: "Мигающий жёлтый" };
  const ARROW = { "": "нет", left: "налево", right: "направо", straight: "прямо" };
  const LETTERS = ["А", "Б", "В", "Г", "Д"];
  const MARK_TYPES = { solid: "Сплошная", dashed: "Прерывистая", stop: "Стоп-линия", zebra: "Зебра" };
  const MARK_COLOURS = { white: "Белая", yellow: "Жёлтая" };
  // What the props of the game are called (scenery/index.json keys: group/name_n).
  const PROP_GROUP = { buildings: "Здания", trees: "Деревья", street: "Уличные предметы" };
  const PROP_NAME = { home: "Частный дом", block: "Жилой дом", tower: "Высотка", pine: "Ель", round: "Дерево", birch: "Берёза",
    bush: "Куст", fence: "Забор", kiosk: "Киоск", lamp: "Фонарь" };
  const propTitle = (p) => {
    const [group, name = ""] = p.split("/");
    const base = name.replace(/_\d+$/, "");
    return PROP_NAME[base] || `${PROP_GROUP[group] || group} · ${name}`;
  };
  // The tools, in the order of the toolbar. icon: the picture in the toolbar and the guide.
  const TOOLS = {
    select: { key: "Q", label: "Выбрать", icon: "cursor", hint: "Выберите объект на плане или в списке слева." },
    road: { key: "D", label: "Дорога", icon: "road", hint: "Клики — точки оси. Enter — готово." },
    contour: { key: "C", label: "Контур", icon: "contour", hint: "Клики — углы. Enter или клик у первой точки — замкнуть." },
    island: { key: "I", label: "Островок", icon: "island", hint: "Контур внутри дороги. Enter — замкнуть." },
    lawn: { key: "G", label: "Газон", icon: "lawn", hint: "Контур газона. Enter — замкнуть." },
    marking: { key: "K", label: "Разметка", icon: "marking", hint: "Линия: клики, Enter. Стоп-линия и зебра: две точки поперёк." },
    route: { key: "M", label: "Маршрут", icon: "route", hint: "Клики — точки пути. Enter — готово." },
    stop: { key: "S", label: "Стоп-линия", icon: "stopline", hint: "Клик — место стоп-линии." },
    actor: { key: "A", label: "Участник", icon: "car", hint: "Клик или протяжка — место и направление." },
    light: { key: "L", label: "Светофор", icon: "light", hint: "Клик — место светофора." },
    decor: { key: "P", label: "Декор", icon: "tree", hint: "Клик или протяжка — место и направление." },
  };
  const TOOL_GROUPS = [["select"], ["road", "contour", "island"], ["lawn", "marking"], ["route", "stop"], ["actor", "light", "decor"]];
  const GROUP_ICON = { roads: "road", lawns: "lawn", marks: "marking", routes: "route", stop: "flag", actors: "car", lights: "light", decor: "tree" };
  const DRIVEN = ["car", "truck", "bus", "motorcycle", "tram", "van", "special", "tanker"];

  let scenes = [], catalog = null, filter = "all", query = "", objQuery = "", texQuery = "";
  let S = null, id = null, findings = [], source = null, seq = 0, previewTimer = null;
  let sel = null, tool = "select", ltab = "scenes", rtab = "props", texSel = null, texView = "final";
  let opts = { route: "manoeuvre", exit: "left", label: "А", actorType: "car", prop: "", draw: null,
    mark: "solid", markColour: "white", roadWidth: 8.4, pave: true, centre: false };
  let undoStack = [], redoStack = [], dirty = false, savedJson = "", drag = null, draft = null, cursorWorld = null;
  let openGroups = { roads: true, lawns: true, marks: true, routes: true, actors: true, lights: true, decor: false, stop: true };
  let legendOpen = false;
  // Placement: the tools that put an object under the cursor. Its heading follows the drag, or R.
  const PLACE = ["actor", "light", "decor", "stop"];
  let placeYaw = 0, placeDrag = null;
  // Stitching: the scene next to this one, its side, and the offset (null: where the game would put it).
  let stitch = { b: null, side: "n", dx: null, dz: null, report: null, build: null, bid: null }, stitchSeq = 0;

  // ---- api ---------------------------------------------------------------------------
  async function api(path, body) {
    const r = await fetch(path, body === undefined ? {} : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.error || r.statusText);
    return data;
  }

  function toast(text, kind = "") {
    const t = $("#toast");
    t.innerHTML = `${ic(kind === "bad" ? "error" : kind === "warn" ? "alert" : kind === "good" ? "check-circle" : "info")}<span>${esc(text)}</span>`;
    t.className = "toast show " + kind;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => (t.className = "toast"), 3600);
  }

  // ---- geometry ----------------------------------------------------------------------
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const polyLength = (pts) => pts.slice(1).reduce((s, p, i) => s + dist(pts[i], p), 0);
  const area = (poly) => Math.abs(poly.reduce((s, p, i) => {
    const q = poly[(i + 1) % poly.length];
    return s + p[0] * q[1] - q[0] * p[1];
  }, 0)) / 2;
  const r3 = (v) => Math.round(v * 1000) / 1000;
  const fmt = (v, digits = 1) => Number(v).toLocaleString("ru-RU", { minimumFractionDigits: digits, maximumFractionDigits: digits });

  // ---- data helpers ------------------------------------------------------------------
  const routeOf = (rid) => S.routes.find((r) => r.id === rid);
  const actorOf = (aid) => S.actors.find((a) => a.id === aid);
  const lightOf = (lid) => S.lights.find((l) => l.id === lid);
  const decorOf = (did) => S.decor.find((d) => d.id === did);
  const isApproach = (r) => r.kind === "approach";
  const markingOf = (mid) => (S.markings || []).find((m) => m.id === mid);

  function objectOf(s) {
    if (!S || !s) return null;
    if (s.t === "route") return routeOf(s.id);
    if (s.t === "road") return S.roads[s.i];
    if (s.t === "lawn") return (S.lawns || [])[s.i];
    if (s.t === "marking") return markingOf(s.id);
    if (s.t === "actor") return actorOf(s.id);
    if (s.t === "light") return lightOf(s.id);
    if (s.t === "decor") return decorOf(s.id);
    if (s.t === "stop") return S.stop;
    return null;
  }

  // What the selection is called in the guide and the bar of the selection.
  function selectionName(s) {
    if (!s) return "";
    if (s.t === "road") return s.part === -1 || s.part === undefined ? `Дорога ${s.i + 1}` : `Островок ${s.part + 1} дороги ${s.i + 1}`;
    if (s.t === "lawn") return s.part === -1 || s.part === undefined ? `Газон ${s.i + 1}` : `Дыра в газоне ${s.i + 1}`;
    if (s.t === "marking") { const m = markingOf(s.id); return m ? (m.type === "paint" ? "Разметка из сцены" : MARK_TYPES[m.type] || m.type) : ""; }
    if (s.t === "route") {
      const r = routeOf(s.id);
      if (!r) return "";
      if (r.kind === "manoeuvre") return `Манёвр «${EXIT[r.exit]}»`;
      if (r.kind === "choice") return `Вариант ${r.label}`;
      if (r.kind === "approach") return "Подъезд к стоп-линии";
      const a = actorOf(r.id.replace("actor_", ""));
      return `Путь: ${a ? a.name || a.id : r.id}`;
    }
    if (s.t === "actor") { const a = actorOf(s.id); return a ? a.name || a.id : ""; }
    if (s.t === "light") return `Светофор ${String(s.id).replace("light_", "")}`;
    if (s.t === "decor") { const d = decorOf(s.id); return d ? propTitle(d.prop) : ""; }
    if (s.t === "stop") return "Стоп-линия и старт";
    return "";
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

  // Dirty means the scene or a texture differs from what is saved.
  const sceneDirty = () => dirty;
  const anyDirty = () => dirty || Textures.dirtyKinds().length > 0;

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
    if (dirty && !confirm("Есть несохранённые правки в этой сцене. Открыть другую сцену без сохранения?")) return;
    const r = await api(`/api/scene/${sid}`);
    S = r.scene;
    S.lawns = S.lawns || [];
    S.markings = S.markings || [];
    id = sid;
    findings = r.findings;
    source = r.source;
    undoStack = [];
    redoStack = [];
    dirty = false;
    savedJson = JSON.stringify(S);
    sel = null;
    texSel = null;
    draft = null;
    tool = "select";
    stitch.dx = stitch.dz = null;
    stitch.bid = stitch.build = null;   // the neighbour may have changed since it was last read
    Scene3D.load(S, r.build);
    if (stitch.b) stitchUpdate();
    Scene3D.setSelection(null);
    $("#empty").hidden = true;
    renderAll();
    renderScenes();
  }

  function sceneTitle(sid) {
    const m = sid.match(/^ticket_(\d+)_(\d+)$/);
    return m ? `Билет ${m[1]} · вопрос ${m[2]}` : sid;
  }

  function plural(n, forms) {
    const m = n % 100, k = n % 10;
    if (m > 10 && m < 20) return forms[2];
    if (k === 1) return forms[0];
    if (k > 1 && k < 5) return forms[1];
    return forms[2];
  }

  function renderScenes() {
    const q = query.trim().toLowerCase();
    const match = (s) => !q || s.id.includes(q) || sceneTitle(s.id).toLowerCase().includes(q);
    const list = scenes.filter((s) => match(s) &&
      (filter === "all" || (filter === "err" && s.errors) || (filter === "todo" && s.status === "unverified")));
    $("#scene-list").innerHTML = list.map((s) => {
      const parts = [s.errors ? `${s.errors} ${plural(s.errors, ["ошибка", "ошибки", "ошибок"])}` : "без ошибок"];
      if (s.warns) parts.push(`${s.warns} замеч.`);
      parts.push(s.status === "ok" ? "сверено" : s.status === "fixed" ? "исправлено" : "не сверено");
      const dot = s.errors ? "bad" : s.status !== "unverified" ? "good" : "";
      return `<button class="scene-row ${s.id === id ? "on" : ""}" data-id="${s.id}">
        <img src="/preview/${s.id}.png" loading="lazy" onerror="this.style.visibility='hidden'" alt="">
        <span class="scene-text"><b>${esc(sceneTitle(s.id))}</b>
        <span class="scene-meta"><i class="dot ${dot}"></i>${parts.join(" · ")}</span>
        ${s.playable ? "" : `<span class="note-tag">${s.regulator ? "регулировщик" : "нет в игре"}</span>`}</span></button>`;
    }).join("") || `<div class="empty-list">Ничего не найдено. Попробуйте номер билета, например «10».</div>`;
    const count = (f) => scenes.filter(f).length;
    $("#n-all").textContent = scenes.length;
    $("#n-err").textContent = count((s) => s.errors);
    $("#n-todo").textContent = count((s) => s.status === "unverified");
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

  // Points each drawing needs, and what to say when there are fewer. Too few keeps the drawing:
  // one more click (or Enter after it) is enough, nothing is lost by an accidental double click.
  const FEW = {
    route: [2, "У маршрута должно быть хотя бы две точки"], path: [2, "Дороге нужно хотя бы две точки"],
    contour: [3, "У контура должно быть хотя бы три точки"], island: [3, "Островку нужно хотя бы три точки"],
    lawn: [3, "Газону нужно хотя бы три точки"], marking: [2, "Разметке нужно хотя бы две точки"],
  };

  function finishDraft() {
    if (!draft) return;
    if (draft.points.length < FEW[draft.kind][0]) return toast(FEW[draft.kind][1], "warn");
    const d = draft;
    draft = null;
    Scene3D.setDraft(null);
    if (d.kind === "route") {
      commit(() => {
        const r = addRoute(d.meta, d.points);
        if (r) sel = { t: "route", id: r.id };
      });
    } else if (d.kind === "path") {
      commit(() => addPathRoad(d.points, d.opts));
    } else if (d.kind === "contour") {
      commit(() => {
        const rid = uniqueId("road_", S.roads.map((r) => r.id));
        S.roads.push({ id: rid, outer: d.points, holes: [] });
        sel = { t: "road", i: S.roads.length - 1, part: -1 };
      });
    } else if (d.kind === "island") {
      const c = centroid(d.points);
      const i = S.roads.findIndex((r) => inside(c, r.outer));
      if (i < 0) return toast("Островок должен лежать внутри дороги", "bad");
      commit(() => {
        S.roads[i].holes.push(d.points);
        sel = { t: "road", i, part: S.roads[i].holes.length - 1 };
      });
    } else if (d.kind === "lawn") {
      commit(() => {
        const lid = uniqueId("lawn_", S.lawns.map((l) => l.id));
        S.lawns.push({ id: lid, outer: d.points, holes: [] });
        sel = { t: "lawn", i: S.lawns.length - 1, part: -1 };
      });
    } else if (d.kind === "marking") {
      commit(() => addMarking(d.type, d.points));
    }
  }

  // A marking as data (build.py draws it): the type and colour the tool has selected.
  function addMarking(type, points) {
    const mid = uniqueId("mark_", S.markings.map((m) => m.id));
    const m = { id: mid, type, colour: opts.markColour, points };
    if (type === "dashed" || type === "solid") m.width = 0.13;
    if (type === "stop") m.width = 0.4;
    if (type === "zebra") m.length = 4;
    S.markings.push(m);
    sel = { t: "marking", id: mid };
  }

  // A road laid along the drawn line, in the format the options ask for: the carriageway, then either the
  // pavement (the builder's own, on both sides) or grass in its place, and the centre marking.
  function addPathRoad(points, o) {
    const pts = RoadGeom.clean(points);
    if (pts.length < 2) return toast("Дороге нужно хотя бы две точки", "warn");
    const rid = uniqueId("road_", S.roads.map((r) => r.id));
    S.roads.push({ id: rid, outer: RoadGeom.outline(pts, o.width), holes: [] });
    if (!o.pave) {
      for (const side of [1, -1]) {
        const lid = uniqueId("lawn_", S.lawns.map((l) => l.id));
        S.lawns.push({ id: lid, outer: RoadGeom.strip(pts, o.width, side), holes: [] });
      }
    }
    if (o.centre) {
      const mid = uniqueId("mark_", S.markings.map((m) => m.id));
      S.markings.push({ id: mid, type: "dashed", colour: "white", width: 0.13, points: pts });
    }
    sel = { t: "road", i: S.roads.length - 1, part: -1 };
  }

  // The rings a move or turn acts on: the whole shape, or one island or hole of a road or lawn.
  function pickRings(s) {
    const all = ringsOfObject(s);
    return (s.t === "road" || s.t === "lawn") && s.part >= 0 ? [all[s.part + 1]].filter(Boolean) : all;
  }

  // Rigid moves of a whole road, a lawn or a marking (keys, the inspector, dragging the body).
  function translateObject(s, dx, dz) {
    for (const ring of pickRings(s)) ring.forEach((p) => { p[0] = r3(p[0] + dx); p[1] = r3(p[1] + dz); });
  }

  // Turns an object around the centre of its points by `deg` degrees (counter-clockwise on the plan).
  function rotateObject(s, deg) {
    const rings = pickRings(s);
    const all = rings.flat();
    if (!all.length) return;
    const cx = all.reduce((a, p) => a + p[0], 0) / all.length, cz = all.reduce((a, p) => a + p[1], 0) / all.length;
    const c = Math.cos(deg * Math.PI / 180), n = Math.sin(deg * Math.PI / 180);
    for (const ring of rings) ring.forEach((p) => {
      const x = p[0] - cx, z = p[1] - cz;
      p[0] = r3(cx + x * c - z * n);
      p[1] = r3(cz + x * n + z * c);
    });
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
    if (s.t === "lawn") {
      const l = (S.lawns || [])[s.i];
      if (!l) return null;
      return s.part === -1 ? l.outer : l.holes[s.part];
    }
    if (s.t === "marking") {
      const m = markingOf(s.id);
      return m && m.points ? m.points : null;
    }
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
    } else if (owner.t === "road" || owner.t === "lawn" || owner.t === "marking") {
      const ring = ringOf(owner);
      if (!ring) return;
      const least = owner.t === "marking" ? 2 : 3;
      if (ring.length <= least) return toast(`В контуре должно остаться точек: ${least}`, "warn");
      commit(() => ring.splice(index, 1));
    }
  }

  function placeAt(t, world, yaw = 0) {
    const p = [Math.round(world.x * 20) / 20, Math.round(world.z * 20) / 20];
    if (t === "decor") {
      const prop = opts.prop || (catalog && catalog.props[0] && catalog.props[0].id);
      if (!prop) return;
      commit(() => {
        const did = uniqueId("decor_", S.decor.map((d) => d.id));
        S.decor.push({ id: did, prop, pos: p, yaw, scale: [1, 1, 1], tint: null });
        sel = { t: "decor", id: did };
      });
    } else if (t === "actor") {
      const tpl = catalog && catalog.actorTypes[opts.actorType];
      if (!tpl) return toast("Для этого типа нет модели в сцене-образце", "bad");
      commit(() => {
        const aid = uniqueId(`${opts.actorType}_`, S.actors.map((a) => a.id));
        S.actors.push({ id: aid, type: opts.actorType, name: tpl.name || TYPE[opts.actorType], asset: tpl.asset, route: null,
          pos: p, yaw, scale: [1, 1, 1], maxSpeed: tpl.maxSpeed ?? 12, clearDistance: tpl.clearDistance ?? 6,
          halfLength: tpl.halfLength ?? 2, halfWidth: tpl.halfWidth ?? 0.9, behaviour: { staysPut: false, waitsForPlayer: true } });
        sel = { t: "actor", id: aid };
      });
    } else if (t === "light") {
      if (!catalog || !catalog.lightAsset) return toast("Нет модели светофора", "bad");
      commit(() => {
        const lid = uniqueId("light_", S.lights.map((l) => l.id));
        S.lights.push({ id: lid, pos: p, yaw, scale: 1, arrow: null, state: "red", asset: catalog.lightAsset });
        sel = { t: "light", id: lid };
      });
    } else if (t === "stop") {
      commit(() => { moveStop(p[0], p[1]); S.stop.yaw = yaw; });
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
  // Choosing an object leaves the texture being edited: the inspector shows the object.
  function select(s) {
    if (s) texSel = null;
    sel = s;
    Scene3D.setSelection(s && s.t !== "question" ? s : null);
    renderAll();
  }

  function onPointer(e) {
    if (!S) return;
    if (e.type === "move") {
      cursorWorld = e.world;
      renderStatus();
      if (PLACE.includes(tool) && !placeDrag) showGhost(tool, e.world, placeYaw);
      if (draft && e.world) {
        draft.cursor = [e.world.x, e.world.z];
        Scene3D.setDraft(draft);
      }
      return;
    }
    if (e.type === "leave") { cursorWorld = null; Scene3D.setGhost(null); renderStatus(); return; }
    if (e.type === "down") return pointerDown(e);
    if (e.type === "drag") return pointerDrag(e);
    if (e.type === "up") return pointerUp(e);
    if (e.type === "dblclick") return doubleClick(e);
  }

  function pointerDown(e) {
    const h = e.hit;
    if (tool !== "select") return drawClick(e);
    if (h && h.kind === "gizmo" && sel) {
      const w = e.world || cursorWorld;
      const c = gizmoTarget();
      snap();
      drag = { kind: "gizmo", axis: h.axis, mode: Scene3D.gizmoMode, start: { x: w.x, z: w.z }, c, base: captureObject(sel), moved: false };
      return;
    }
    if (!h) { if (!e.shift) select(null); return; }
    if (h.kind === "vertex") {
      sel = h.owner.t === "route" ? { t: "route", id: h.owner.id } : { ...h.owner };
      sel.v = h.index;
      texSel = null;
      Scene3D.setSelection(sel);
      snap();
      drag = { kind: "vertex", owner: { ...sel }, index: h.index, moved: false };
      renderAll();
      return;
    }
    if (h.kind === "anchor") {
      sel = { t: h.t, id: h.id };
      texSel = null;
      Scene3D.setSelection(sel);
      snap();
      drag = { kind: "anchor", t: h.t, id: h.id, moved: false };
      renderAll();
      return;
    }
    if (h.kind === "route") {
      sel = { t: "route", id: h.id };
      texSel = null;
      Scene3D.setSelection(sel);
      renderAll();
      return;
    }
    if (h.kind === "road" || h.kind === "lawn") {
      sel = { t: h.kind, i: h.i, part: h.part };
      texSel = null;
      Scene3D.setSelection(sel);
      // Dragging the outline or the inside moves the whole object; a click alone changes nothing.
      if (e.world) { snap(); startBodyDrag(sel, e.world); }
      renderAll();
      return;
    }
    if (h.kind === "marking") {
      sel = { t: "marking", id: h.id };
      texSel = null;
      Scene3D.setSelection(sel);
      if (e.world) { snap(); startBodyDrag(sel, e.world); }
      renderAll();
      return;
    }
  }

  // The rings (point lists) an object is made of: a road's outline and islands, a lawn, a marking.
  function ringsOfObject(s) {
    if (!S || !s) return [];
    if (s.t === "road") { const r = S.roads[s.i]; return r ? [r.outer, ...r.holes] : []; }
    if (s.t === "lawn") { const l = S.lawns[s.i]; return l ? [l.outer, ...l.holes] : []; }
    if (s.t === "marking") {
      const m = markingOf(s.id);
      if (!m) return [];
      if (m.points) return [m.points];
      return (m.polygons || []).flatMap((p) => [p.outer, ...p.holes]);
    }
    return [];
  }

  function startBodyDrag(owner, world) {
    drag = { kind: "body", owner: { ...owner }, start: [world.x, world.z], base: JSON.parse(JSON.stringify(ringsOfObject(owner))), moved: false };
  }

  function bodyDrag(w) {
    const dx = w.x - drag.start[0], dz = w.z - drag.start[1];
    ringsOfObject(drag.owner).forEach((ring, k) => ring.forEach((p, j) => {
      p[0] = r3(drag.base[k][j][0] + dx);
      p[1] = r3(drag.base[k][j][1] + dz);
    }));
    drag.moved = true;
  }

  // The footprint of the object as it will be placed (metres from its centre along and across its heading).
  function ghostHalf(t) {
    if (t === "actor") {
      const tpl = catalog && catalog.actorTypes[opts.actorType];
      return [tpl && tpl.halfLength || 2, tpl && tpl.halfWidth || 0.9];
    }
    if (t === "decor") {
      const prop = catalog && catalog.props.find((p) => p.id === opts.prop);
      const size = prop && prop.size || [2, 2, 2];
      return [size[2] / 2, size[0] / 2];
    }
    if (t === "stop") return [0.4, 4.2];
    return [0.4, 0.4];
  }

  function showGhost(t, w, yaw) {
    if (!PLACE.includes(t) || !S || !w) return Scene3D.setGhost(null);
    Scene3D.setGhost({ kind: t, x: w.x, z: w.z, yaw, half: ghostHalf(t) });
  }

  function drawClick(e) {
    const w = e.world;
    if (!w) return;
    if (PLACE.includes(tool)) {
      placeDrag = { x: w.x, z: w.z, yaw: placeYaw, moved: false };
      return;
    }
    const pt = [Math.round(w.x * 20) / 20, Math.round(w.z * 20) / 20];
    if (tool === "route") {
      if (!draft) draft = { kind: "route", meta: routeMeta(), points: [] };
      if (draft.kind !== "route") return;
      draft.points.push(pt);
      Scene3D.setDraft(draft);
      renderTools();
      return;
    }
    if (tool === "road") {
      if (!draft) draft = { kind: "path", points: [], opts: { width: opts.roadWidth, pave: opts.pave, centre: opts.centre } };
      if (dist(pt, draft.points.at(-1) || [NaN, NaN]) < 0.05) return;
      draft.points.push(pt);
      Scene3D.setDraft(draft);
      renderTools();
      return;
    }
    if (tool === "contour" || tool === "island" || tool === "lawn") {
      if (!draft) draft = { kind: tool, points: [] };
      if (draft.points.length >= 3 && dist(pt, draft.points[0]) < 1.2) return finishDraft();
      draft.points.push(pt);
      Scene3D.setDraft(draft);
      renderTools();
      return;
    }
    if (tool === "marking") {
      if (!draft) draft = { kind: "marking", type: opts.mark, points: [] };
      draft.points.push(pt);
      if ((draft.type === "stop" || draft.type === "zebra") && draft.points.length === 2) return finishDraft();
      Scene3D.setDraft(draft);
      renderTools();
      return;
    }
  }

  function finishPlace() {
    const pd = placeDrag;
    placeDrag = null;
    placeYaw = pd.moved ? pd.yaw : placeYaw;
    placeAt(tool, { x: pd.x, z: pd.z }, placeYaw);
    showGhost(tool, { x: pd.x, z: pd.z }, placeYaw);
    renderAll();
  }

  function routeMeta() {
    if (opts.route === "manoeuvre") return { kind: "manoeuvre", exit: opts.exit };
    if (opts.route === "choice") return { kind: "choice", label: opts.label };
    return { kind: "actor", actor: opts.actorFor || (S.actors[0] && S.actors[0].id) };
  }

  function pointerDrag(e) {
    const w = e.world;
    if (placeDrag && w) {
      const dx = w.x - placeDrag.x, dz = w.z - placeDrag.z;
      if (Math.hypot(dx, dz) > 0.3) {
        placeDrag.yaw = Math.atan2(dx, dz);
        placeDrag.moved = true;
        showGhost(tool, { x: placeDrag.x, z: placeDrag.z }, placeDrag.yaw);
      }
      return;
    }
    if (!drag) return;
    if (!w) return;
    if (drag.kind === "gizmo") {
      applyGizmo(w, e.shift);
      Scene3D.refresh(S);
      Scene3D.setGizmo(gizmoTarget(), drag.mode);
      renderStatus();
      return;
    }
    if (drag.kind === "body") {
      bodyDrag(w);
      Scene3D.refresh(S);
      Scene3D.setSelection(sel);
      renderStatus();
      return;
    }
    if (drag.kind === "vertex") {
      const pt = [w.x, w.z];
      const owner = drag.owner;
      const target = owner.t === "route" ? routeOf(owner.id)?.points : ringOf(owner);
      if (!target) return;
      // A displayed offset is not stored: the point follows the pointer, minus that offset.
      const off = owner.t === "route" ? Scene3D.routeOffset(routeOf(owner.id), drag.index) : [0, 0];
      target[drag.index] = [pt[0] - off[0], pt[1] - off[1]];
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
    if (placeDrag) return finishPlace();
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
    if ((tool === "road" || tool === "contour" || tool === "island" || tool === "lawn" || tool === "marking") && draft) {
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
    if (sel.v !== undefined && sel.v >= 0 && ["route", "road", "lawn", "marking"].includes(sel.t)) return deleteVertex(sel, sel.v);
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
    } else if (sel.t === "lawn") {
      commit(() => {
        if (sel.part === -1) S.lawns.splice(sel.i, 1);
        else S.lawns[sel.i].holes.splice(sel.part, 1);
        sel = null;
      });
    } else if (sel.t === "marking") {
      commit(() => {
        const at = S.markings.findIndex((m) => m.id === sel.id);
        if (at >= 0) S.markings.splice(at, 1);
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
    if (isShape(sel)) return commit(() => translateObject(sel, dx, dz));
    const o = objectOf(sel);
    if (!o) return;
    commit(() => {
      if (sel.t === "stop") moveStop(S.stop.x + dx, S.stop.z + dz);
      else o.pos = [o.pos[0] + dx, o.pos[1] + dz];
    });
  }

  function rotate(deg) {
    if (isShape(sel)) return commit(() => rotateObject(sel, deg));
    const o = objectOf(sel);
    if (!o || sel.v !== undefined && sel.v >= 0) return;
    commit(() => {
      if (sel.t === "stop") S.stop.yaw -= (deg * Math.PI) / 180;
      else o.yaw -= (deg * Math.PI) / 180;
    });
  }

  // Roads, lawns and markings are shapes: moved and turned as a whole (an island, a hole, only itself).
  const isShape = (s) => !!s && (s.t === "road" || s.t === "lawn" || s.t === "marking");
  const canRotate = (s) => !!s && s.v === undefined && (isShape(s) || ["actor", "light", "decor", "stop"].includes(s.t));

  // ---- live preview and saving -------------------------------------------------------
  function schedulePreview() {
    clearTimeout(previewTimer);
    previewTimer = setTimeout(() => { runPreview(); if (stitch.b) stitchUpdate(); }, 260);
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

  // Saves what has changed: the scene (its checks, the game's scene file) and the textures.
  async function saveAll() {
    if (!anyDirty()) return toast("Все правки сохранены");
    const done = [];
    let removed = [];
    try {
      if (S && dirty) {
        const r = await api(`/api/scene/${id}`, S);
        dirty = false;
        savedJson = JSON.stringify(S);
        findings = r.findings;
        removed = r.removed || [];
        stitch.bid = stitch.build = null;
        const gone = removed.length ? ` · удалено: ${removed.join(", ")}` : "";
        done.push(`сцена: ${r.findings.filter((f) => f.level === "error").length} ошибок${gone}`);
        await loadList();
      }
      const kinds = Textures.dirtyKinds();
      for (const kind of kinds) {
        const p = Textures.draftOf(kind);
        const body = { gain: p.gain, macro: p.macro, macroScale: p.macroScale };
        if (p.period !== undefined) body.period = p.period;
        await api(`/api/texture/${kind}`, body);
        Textures.markSaved(kind);
      }
      if (kinds.length) done.push(`текстуры: ${kinds.length}`);
      if (done.length) toast(`Сохранено · ${done.join(" · ")}`, removed.length ? "warn" : "good");
    } catch (e) {
      toast(`Не сохранено: ${e.message}`, "bad");
    }
    renderAll();
    renderTextures();
  }

  // ---- gizmo: move (W) and turn (E) the selection with the handles in the view ----------
  function gizmoTarget() {
    if (!S || tool !== "select" || !sel || (ltab === "textures" && texSel)) return null;
    const o = objectOf(sel);
    if (!o || (sel.v !== undefined && sel.v >= 0) || sel.t === "route") return null;
    if (sel.t === "stop") return { x: S.stop.x, z: S.stop.z, yaw: S.stop.yaw };
    if (o.pos) return { x: o.pos[0], z: o.pos[1], yaw: o.yaw || 0 };
    const pts = ringsOfObject(sel).flat();
    if (!pts.length) return null;
    return { x: pts.reduce((a, p) => a + p[0], 0) / pts.length, z: pts.reduce((a, p) => a + p[1], 0) / pts.length };
  }

  function setGizmoMode(mode) {
    Scene3D.setGizmo(gizmoTarget(), mode);
    renderSelBar();
  }

  // The state of the selection when a gizmo drag starts: the drag moves or turns it from here.
  function captureObject(s) {
    if (s.t === "stop") {
      const ap = routeOf("approach");
      return { x: S.stop.x, z: S.stop.z, yaw: S.stop.yaw, end: ap ? [...ap.points.at(-1)] : null };
    }
    const o = objectOf(s);
    if (o && o.pos) {
      const r = s.t === "actor" && o.route ? routeOf(o.route) : null;
      return { pos: [...o.pos], yaw: o.yaw || 0, start: r ? [...r.points[0]] : null };
    }
    return { rings: JSON.parse(JSON.stringify(ringsOfObject(s))) };
  }

  // Moves the selection by (dx, dz) from its state at the start of the drag.
  function moveFromBase(s, b, dx, dz) {
    if (s.t === "stop") return moveStop(r3(b.x + dx), r3(b.z + dz));
    const o = objectOf(s);
    if (b.pos) {
      o.pos = [r3(b.pos[0] + dx), r3(b.pos[1] + dz)];
      if (b.start) routeOf(o.route).points[0] = [...o.pos];
      return;
    }
    ringsOfObject(s).forEach((ring, k) => ring.forEach((p, j) => { p[0] = r3(b.rings[k][j][0] + dx); p[1] = r3(b.rings[k][j][1] + dz); }));
  }

  // Turns the selection by `ang` (radians) about the point c. Objects turn their heading the other way
  // round, so the handle and the model turn together.
  function turnFromBase(s, b, ang, c) {
    const cos = Math.cos(ang), sin = Math.sin(ang);
    const turn = (x, z) => [r3(c.x + (x - c.x) * cos - (z - c.z) * sin), r3(c.z + (x - c.x) * sin + (z - c.z) * cos)];
    if (s.t === "stop") { S.stop.yaw = b.yaw - ang; return; }
    const o = objectOf(s);
    if (b.pos) { o.yaw = b.yaw - ang; return; }
    ringsOfObject(s).forEach((ring, k) => ring.forEach((p, j) => { [p[0], p[1]] = turn(b.rings[k][j][0], b.rings[k][j][1]); }));
  }

  function applyGizmo(w, fineAngles) {
    const d = drag;
    if (d.mode === "move") {
      let dx = w.x - d.start.x, dz = w.z - d.start.z;
      if (d.axis === "x") dz = 0;
      if (d.axis === "z") dx = 0;
      moveFromBase(sel, d.base, dx, dz);
    } else {
      let ang = Math.atan2(w.z - d.c.z, w.x - d.c.x) - Math.atan2(d.start.z - d.c.z, d.start.x - d.c.x);
      if (fineAngles) ang = Math.round(ang / (Math.PI / 12)) * (Math.PI / 12);
      turnFromBase(sel, d.base, ang, d.c);
    }
    d.moved = true;
  }

  // ---- rendering ---------------------------------------------------------------------
  function renderAll() {
    Scene3D.setGizmo(gizmoTarget(), Scene3D.gizmoMode);
    renderHeader();
    renderTree();
    renderTextures();
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
    $("#dirty").hidden = !anyDirty();
    $("#save").disabled = !anyDirty();
    $("#undo").disabled = !undoStack.length;
    $("#redo").disabled = !redoStack.length;
    document.title = S ? `${sceneTitle(id)} · Редактор сцен` : "Редактор сцен";
  }

  // The toolbar: one button per tool, grouped. Its state and the guide follow the tool.
  function buildTools() {
    $("#tools").innerHTML = TOOL_GROUPS.map((g) => `<div class="grp">${g.map((t) => `
      <button data-tool="${t}" data-tip="${TOOLS[t].label} · ${TOOLS[t].key}">${ic(TOOLS[t].icon)}<span>${TOOLS[t].label}</span></button>`).join("")}</div>`).join("");
    $("#tools").querySelectorAll("[data-tool]").forEach((b) => b.addEventListener("click", () => {
      if (!S) return toast("Сначала выберите сцену слева", "warn");
      setTool(b.dataset.tool);
    }));
  }

  function renderTools() {
    document.querySelectorAll("#tools [data-tool]").forEach((b) => b.classList.toggle("on", b.dataset.tool === tool));
    if (!PLACE.includes(tool) || placeDrag) { if (!PLACE.includes(tool)) Scene3D.setGhost(null); }
    renderGuide();
    renderSelBar();
  }

  // Options of the tool in use (in the guide): what to draw, which exit, which letter or type.
  function toolOptions() {
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
      parts.push(`<label>Предмет <select id="o-prop">${catalog.props.map((p) => `<option value="${p.id}" ${opts.prop === p.id ? "selected" : ""}>${esc(propTitle(p.id))}</option>`).join("")}</select></label>`);
    }
    if (tool === "actor" && catalog) {
      parts.push(`<label>Тип <select id="o-type">${Object.keys(catalog.actorTypes).map((t) => `<option value="${t}" ${opts.actorType === t ? "selected" : ""}>${TYPE[t] || t}</option>`).join("")}</select></label>`);
    }
    if (tool === "marking") {
      parts.push(`<label>Тип <select id="o-mark">${Object.entries(MARK_TYPES).map(([k, v]) => `<option value="${k}" ${opts.mark === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>`);
      parts.push(`<label>Цвет <select id="o-mcolour">${Object.entries(MARK_COLOURS).map(([k, v]) => `<option value="${k}" ${opts.markColour === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>`);
    }
    if (tool === "road") {
      parts.push(`<label>Ширина, м <input id="o-width" type="number" step="0.1" min="3" max="20" value="${opts.roadWidth}"></label>`);
      parts.push(`<label class="chk"><input id="o-pave" type="checkbox" ${opts.pave ? "checked" : ""}> Тротуары</label>`);
      parts.push(`<label class="chk"><input id="o-centre" type="checkbox" ${opts.centre ? "checked" : ""}> Разметка</label>`);
    }
    return parts.join("");
  }

  // The guide: what the tool does now, its options, and the buttons that finish a drawing.
  function renderGuide() {
    const g = $("#guide");
    g.hidden = !S;
    if (!S) return;
    const drawing = tool !== "select" && !(ltab === "textures");
    let icon = TOOLS[tool].icon, title = TOOLS[tool].label, hint = TOOLS[tool].hint;
    if (ltab === "textures") {
      icon = "tiles";
      title = texSel ? `Текстура: ${Textures.INFO[texSel]?.name || texSel}` : "Текстуры игры";
      hint = texSel ? "Ползунки видны на плане сразу." : "Выберите текстуру слева.";
    } else if (tool === "select") {
      icon = "cursor";
      title = sel ? `Выбрано: ${selectionName(sel)}` : "Выберите объект";
      hint = sel ? "W — переместить · E — повернуть · R — на 15° · Delete — удалить" : TOOLS.select.hint;
    }
    $("#guide-icon").setAttribute("href", `#i-${icon}`);
    $("#guide-title").textContent = title;
    $("#guide-hint").textContent = hint;
    $("#tool-opts").innerHTML = drawing ? toolOptions() : "";
    bindToolOptions();
    const actions = $("#draft-actions");
    actions.hidden = !(drawing && draft);
    $("#draft-count").textContent = draft ? `Точек: ${draft.points.length}` : "";
  }

  function bindToolOptions() {
    const bind = (sel, fn) => { const el = $(sel); if (el) el.onchange = () => fn(el); };
    bind("#o-mark", (el) => { opts.mark = el.value; renderTools(); });
    bind("#o-mcolour", (el) => { opts.markColour = el.value; });
    bind("#o-width", (el) => { opts.roadWidth = Math.min(20, Math.max(3, Number(el.value) || 8.4)); });
    bind("#o-pave", (el) => { opts.pave = el.checked; });
    bind("#o-centre", (el) => { opts.centre = el.checked; });
    bind("#o-route", (el) => { opts.route = el.value; renderTools(); });
    bind("#o-exit", (el) => { opts.exit = el.value; });
    bind("#o-label", (el) => { opts.label = el.value; });
    bind("#o-actor", (el) => { opts.actorFor = el.value; });
    bind("#o-prop", (el) => { opts.prop = el.value; });
    bind("#o-type", (el) => { opts.actorType = el.value; });
  }

  // The bar of the selection: its name and its quick actions (the same keys work too).
  function renderSelBar() {
    const bar = $("#selbar");
    const show = !!S && !!sel && tool === "select" && ltab !== "textures" && !!objectOf(sel);
    bar.hidden = !show;
    if (!show) return;
    $("#selbar-name").textContent = selectionName(sel) + (sel.v !== undefined && sel.v >= 0 ? ` · точка ${sel.v + 1}` : "");
    const rot = canRotate(sel);
    $("#sel-rotl").hidden = !rot;
    $("#sel-rotr").hidden = !rot;
    $("#sel-move").classList.toggle("on", Scene3D.gizmoMode === "move");
    $("#sel-turn").classList.toggle("on", Scene3D.gizmoMode === "rotate");
  }

  function renderStatus() {
    $("#cursor").textContent = cursorWorld ? `x ${cursorWorld.x.toFixed(2)} · z ${cursorWorld.z.toFixed(2)} м` : "x — · z — м";
    const px = Scene3D.pxPerM;
    const bar = Math.min(200, Math.max(30, Math.round(10 * px)));
    $("#scale-bar").style.width = bar + "px";
    $("#scale-text").textContent = "10 м";
    $("#zoom-text").textContent = Scene3D.mode === "plan" ? `${px.toFixed(1)} px/м` : "3D";
    $("#mode-plan").classList.toggle("on", Scene3D.mode === "plan");
    $("#mode-3d").classList.toggle("on", Scene3D.mode !== "plan");
    $("#legend").hidden = !legendOpen;
    $("#legend-toggle").classList.toggle("on", legendOpen);
  }

  // Object tree (left panel, "Объекты").
  function renderTree() {
    if (!S) { $("#object-tree").innerHTML = `<div class="empty-list">Откройте сцену, чтобы увидеть её объекты</div>`; return; }
    const q = objQuery.trim().toLowerCase();
    const hit = (t) => !q || t.toLowerCase().includes(q);
    const group = (key, title, count, body) => {
      const open = openGroups[key] !== false;
      return `<div class="tree-group"><button class="tree-head" data-group="${key}">
        <span class="caret ${open ? "open" : ""}">${ic("chevron")}</span>${ic(GROUP_ICON[key])}${title}<em>${count}</em></button>${open ? `<div class="tree-body">${body}</div>` : ""}</div>`;
    };
    const row = (s, label, extra = "", cls = "", icon = "") => {
      const on = sel && sel.t === s.t && (s.t === "stop" || sel.id === s.id) && (sel.i === undefined || sel.i === s.i) && (sel.part === undefined || sel.part === s.part);
      return `<button class="tree-row ${on && !texSel ? "on" : ""} ${cls}" data-sel='${esc(JSON.stringify(s))}'>${icon ? ic(icon) : ""}${label}${extra ? `<small>${extra}</small>` : ""}</button>`;
    };
    const roads = S.roads.map((r, i) => {
      const main = row({ t: "road", i, part: -1 }, `Дорога ${i + 1}`, `${Math.round(area(r.outer))} м²${r.holes.length ? ` · островков ${r.holes.length}` : ""}`, "", "road");
      const holes = r.holes.map((h, k) => row({ t: "road", i, part: k }, `Островок ${k + 1}`, `${Math.round(area(h))} м²`, "sub", "island")).join("");
      return hit(`дорога ${i + 1}`) || holes ? main + holes : "";
    }).join("");
    const routeRows = (kind) => S.routes.filter((r) => r.kind === kind).map((r) => {
      const name = kind === "manoeuvre" ? `Манёвр «${EXIT[r.exit]}»` : kind === "choice" ? `Вариант ${r.label}` : kind === "approach" ? "Подъезд к стоп-линии" : `Путь: ${actorOf(r.id.replace("actor_", ""))?.name || r.id}`;
      return hit(name) ? row({ t: "route", id: r.id }, name, `${r.points.length} точ.`, "", "route") : "";
    }).join("");
    const actors = S.actors.map((a) => hit(a.name || a.id) ? row({ t: "actor", id: a.id }, esc(a.name || a.id), TYPE[a.type] || a.type, "", "car") : "").join("");
    const lights = S.lights.map((l) => hit("светофор") ? row({ t: "light", id: l.id }, `Светофор ${l.id.replace("light_", "")}`, LIGHT[l.state] || "", "", "light") : "").join("");
    const decorByProp = {};
    S.decor.forEach((d) => { (decorByProp[d.prop] = decorByProp[d.prop] || []).push(d); });
    const decor = Object.entries(decorByProp).map(([p, list]) => hit(propTitle(p)) ? `<div class="tree-sub"><span>${esc(propTitle(p))}</span><em>${list.length}</em></div>${list.map((d, k) => row({ t: "decor", id: d.id }, `Предмет ${k + 1}`,`${d.pos[0].toFixed(1)}, ${d.pos[1].toFixed(1)}`, "sub", "tree")).join("")}` : "").join("");
    const lawns = (S.lawns || []).map((l, i) => hit(`газон ${i + 1}`)
      ? row({ t: "lawn", i, part: -1 }, `Газон ${i + 1}`, `${Math.round(area(l.outer) - l.holes.reduce((s, h) => s + area(h), 0))} м²`, "", "lawn") : "").join("");
    const marks = (S.markings || []).map((m) => {
      const name = m.type === "paint" ? "Разметка из сцены" : MARK_TYPES[m.type] || m.type;
      return hit(name) ? row({ t: "marking", id: m.id }, name, MARK_COLOURS[m.colour] || "", "", "marking") : "";
    }).join("");
    $("#object-tree").innerHTML = [
      group("roads", "Дорожное полотно", S.roads.length, roads || `<div class="tree-none">Нет дорог</div>`),
      group("lawns", "Газоны и клумбы", (S.lawns || []).length, lawns || `<div class="tree-none">Нет газонов</div>`),
      group("marks", "Разметка", (S.markings || []).length, marks || `<div class="tree-none">Нет разметки</div>`),
      group("routes", "Маршруты", S.routes.length, ["manoeuvre", "choice", "approach", "actor"].map((k) => routeRows(k)).join("") || `<div class="tree-none">Нет маршрутов</div>`),
      group("stop", "Стоп-линия и старт", 1, row({ t: "stop" }, "Стоп-линия и старт", `${S.stop.x.toFixed(2)}, ${S.stop.z.toFixed(2)}`, "", "flag")),
      group("actors", "Участники", S.actors.length, actors || `<div class="tree-none">Нет участников</div>`),
      group("lights", "Светофоры", S.lights.length, lights || `<div class="tree-none">Нет светофоров</div>`),
      group("decor", "Декор у дороги", S.decor.length, decor || `<div class="tree-none">Нет декора</div>`),
    ].join("");
  }

  // Textures (left panel, "Текстуры"): every texture of the game, grouped, with its picture.
  function renderTextures() {
    const list = $("#tex-list");
    if (!list || ltab !== "textures" || !Textures.state.list.length) return;
    const q = texQuery.trim().toLowerCase();
    const kinds = Textures.state.list.map((t) => t.kind).filter((k) => {
      const info = Textures.INFO[k] || {};
      return !q || k.toLowerCase().includes(q) || (info.name || "").toLowerCase().includes(q);
    });
    list.innerHTML = Textures.GROUPS.map((g) => {
      const items = kinds.filter((k) => (Textures.INFO[k] || {}).group === g.id);
      if (!items.length) return "";
      return `<div class="tex-group-title">${g.title}</div>` + items.map((k) => {
        const info = Textures.INFO[k] || { name: k, where: "" };
        const sub = Textures.isGround(k) ? `${info.where} · плитка ${fmt(Textures.draftOf(k).period)} м` : info.where;
        return `<button class="tex-row ${texSel === k ? "on" : ""}" data-tex="${k}">
          <canvas class="tex-thumb" width="88" height="88" data-thumb="${k}"></canvas>
          <span class="tex-text"><span class="tex-name">${esc(info.name)}</span><span class="tex-sub">${esc(sub)}</span></span>
          ${Textures.isDirty(k) ? `<span class="tex-mark">изменено</span>` : ""}</button>`;
      }).join("");
    }).join("") || `<div class="empty-list">Такой текстуры нет</div>`;
    drawThumbs(list);
  }

  function drawThumbs(root) {
    root.querySelectorAll("canvas[data-thumb]").forEach((c) => Textures.draw(c, c.dataset.thumb, "final", 1));
  }

  // The right panel: properties of the selection, or the scene overview.
  function renderInspector() {
    const pane = $("#rpane");
    document.querySelectorAll("#rtabs [data-rtab]").forEach((b) => b.classList.toggle("on", b.dataset.rtab === rtab));
    if (!S) { pane.innerHTML = `<div class="empty-pane">Выберите сцену слева, чтобы начать.</div>`; return; }
    if (rtab === "stitch") return renderStitch(pane);
    if (rtab === "question") return renderQuestion(pane);
    if (rtab === "checks") return renderChecks();
    if (ltab === "textures" && texSel && Textures.state.list.length) return renderTexture(pane);
    if (!sel) return renderOverview(pane);
    const o = objectOf(sel);
    if (!o) return renderOverview(pane);
    if (sel.t === "route") return renderRoute(pane, o);
    if (sel.t === "road") return renderRoad(pane, o);
    if (sel.t === "lawn") return renderLawn(pane, o);
    if (sel.t === "marking") return renderMarking(pane, o);
    if (sel.t === "actor") return renderActor(pane, o);
    if (sel.t === "light") return renderLight(pane, o);
    if (sel.t === "decor") return renderDecor(pane, o);
    if (sel.t === "stop") return renderStop(pane);
  }

  const head = (icon, title, pill = "") => `<div class="card-h"><span class="ibadge">${ic(icon)}</span><h3>${title}</h3>${pill ? `<span class="pill">${esc(pill)}</span>` : ""}</div>`;
  const subhead = (icon, title) => `<h3>${ic(icon)}${title}</h3>`;

  function renderOverview(pane) {
    const err = findings.filter((f) => f.level === "error").length;
    const ok = err === 0;
    pane.innerHTML = `
      <section class="card">
        ${head("layers", "Сцена", sceneTitle(id))}
        <dl class="kv">
          <dt>${ic("road")}Дороги</dt><dd>${S.roads.length}</dd>
          <dt>${ic("lawn")}Газоны</dt><dd>${S.lawns.length}</dd>
          <dt>${ic("marking")}Разметка</dt><dd>${S.markings.length}</dd>
          <dt>${ic("route")}Маршруты</dt><dd>${S.routes.length}</dd>
          <dt>${ic("car")}Участники</dt><dd>${S.actors.length}</dd>
          <dt>${ic("light")}Светофоры</dt><dd>${S.lights.length}</dd>
          <dt>${ic("tree")}Декор</dt><dd>${S.decor.length}</dd>
          <dt>${ic(ok ? "check-circle" : "error")}Проверка</dt>
          <dd class="${ok ? "good-t" : "bad-t"}">${ok ? "ошибок нет" : `${err} ${plural(err, ["ошибка", "ошибки", "ошибок"])}`}</dd>
        </dl>
      </section>
      <section class="card">
        ${subhead("keyboard", "Клавиши")}
        <dl class="keys">
          <dt><kbd>Q</kbd> <kbd>W</kbd> <kbd>E</kbd> <kbd>R</kbd></dt><dd>выбор, перемещение, поворот, поворот на 15°</dd>
          <dt><kbd>D</kbd> <kbd>C</kbd> <kbd>I</kbd> <kbd>G</kbd> <kbd>K</kbd></dt><dd>дорога, контур, островок, газон, разметка</dd>
          <dt><kbd>M</kbd> <kbd>S</kbd> <kbd>A</kbd> <kbd>L</kbd> <kbd>P</kbd></dt><dd>маршрут, стоп, участник, светофор, декор</dd>
          <dt><kbd>T</kbd> <kbd>F</kbd></dt><dd>вид сверху и 3D; вся сцена</dd>
        </dl>
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
      ? `<label class="field"><span>Выезд</span><select data-f="exit">${Object.entries(EXIT).map(([k, v]) => `<option value="${k}" ${r.exit === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
         ${fieldNum("Поворот выезда", (r.exitYaw || 0) * RAD, "exitYaw", 1, "°")}
         <p class="note">${S.question.maneuver === r.exit ? "Это правильный манёвр по условию вопроса — по нему поедет машина." : "Альтернативный выезд. Машина поедет по нему, только если его выберет игрок."}</p>`
      : r.kind === "choice"
        ? `<label class="field"><span>Буква на дороге</span><select data-f="label">${LETTERS.map((l) => `<option ${r.label === l ? "selected" : ""}>${l}</option>`).join("")}</select></label>
           <div class="row"><button class="btn" data-act="letter-mid">${ic("pin")}Поставить букву в середину пути</button></div>`
        : approach
          ? `<p class="note">${ic("info")}Конец подъезда всегда совпадает со стоп-линией. Двигайте стоп-линию — подъезд подстроится.</p>`
          : `<div class="actions"><button class="btn" data-act="actor-of-route">${ic("car")}Открыть участника</button>
              <button class="btn danger" data-act="route-unlink">${ic("x")}Отвязать путь</button></div>`;
    pane.innerHTML = `
      <section class="card">
        ${head("route", title, r.id)}
        ${extra}
        <div class="stats">Точек: <b>${pts.length}</b> · длина: <b>${polyLength(pts).toFixed(1)} м</b></div>
        ${sel.v !== undefined && sel.v >= 0 ? `<div class="sel-pt">Точка ${sel.v + 1}: ${pts[sel.v][0].toFixed(2)}, ${pts[sel.v][1].toFixed(2)}</div>` : ""}
        <div class="actions">
          <button class="btn" data-act="pt-add">${ic("plus")}Добавить точку в конец</button>
          <button class="btn danger" data-act="route-del" ${approach ? "disabled" : ""}>${ic("trash")}Удалить маршрут</button>
        </div>
      </section>
      <section class="card">
        ${subhead("points", "Точки")}
        <div class="pts">${pts.map((p, i) => `<div class="pt ${sel.v === i ? "on" : ""}" data-pt="${i}"><span>${i + 1}</span>
          <input type="number" step="0.05" value="${p[0].toFixed(2)}" data-pt-x="${i}" aria-label="X точки ${i + 1}"><input type="number" step="0.05" value="${p[1].toFixed(2)}" data-pt-z="${i}" aria-label="Z точки ${i + 1}">
          <button class="icon-btn" data-pt-del="${i}" title="Удалить точку">${ic("x")}</button></div>`).join("")}</div>
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
    const holes = road.holes.map((h, k) => `<button class="tree-row ${sel.part === k ? "on" : ""}" data-hole="${k}">${ic("island")}Островок ${k + 1}<small>${Math.round(area(h))} м² · точек ${h.length}</small></button>`).join("");
    pane.innerHTML = `
      <section class="card">
        ${head("road", sel.part === -1 ? "Дорога" : `Островок ${sel.part + 1}`, `road_${sel.i}`)}
        <div class="stats">Площадь: <b>${Math.round(area(road.outer))} м²</b> · точек контура: <b>${road.outer.length}</b>${road.holes.length ? ` · островков: <b>${road.holes.length}</b>` : ""}</div>
        <p class="note">${ic("info")}Дорога — это контур. Островки внутри него не едут. Тяните углы на плане, двойной клик по стороне добавляет угол.</p>
        ${sel.part === -1 ? shapeControls() : ""}
        <div class="actions">
          <button class="btn" data-act="island">${ic("island")}Нарисовать островок</button>
          ${sel.part !== -1 ? `<button class="btn danger" data-act="hole-del">${ic("trash")}Удалить островок</button>` : `<button class="btn danger" data-act="road-del">${ic("trash")}Удалить дорогу</button>`}
        </div>
      </section>
      ${holes ? `<section class="card">${subhead("island", "Островки")}${holes}</section>` : ""}
      <section class="card">${subhead("points", sel.part === -1 ? "Точки контура" : "Точки островка")}
        <div class="pts">${ring.map((p, i) => `<div class="pt ${sel.v === i ? "on" : ""}" data-pt="${i}"><span>${i + 1}</span>
          <input type="number" step="0.05" value="${p[0].toFixed(2)}" data-rx="${i}" aria-label="X точки ${i + 1}"><input type="number" step="0.05" value="${p[1].toFixed(2)}" data-rz="${i}" aria-label="Z точки ${i + 1}">
          <button class="icon-btn" data-rdel="${i}" title="Удалить точку">${ic("x")}</button></div>`).join("")}</div>
      </section>`;
    bindForm(pane, {
      "island": () => setTool("island"),
      "hole-del": () => deleteSelected(),
      "road-del": () => deleteSelected(),
    });
    if (sel.part === -1) bindShape(pane);
    pane.querySelectorAll("[data-hole]").forEach((el) => el.addEventListener("click", () => select({ t: "road", i: sel.i, part: Number(el.dataset.hole) })));
    bindRing(pane, ring);
  }

  // Shared by roads, lawns and markings: a move and a turn of the whole shape.
  function shapeControls() {
    return `<div class="row2">${fieldNum("Сдвиг по X", 0, "dx", 0.1, "м")}${fieldNum("по Z", 0, "dz", 0.1, "м")}</div>
      <div class="row2">${fieldNum("Поворот", 0, "deg", 1, "°")}<div class="field"><span>&nbsp;</span><button class="btn" data-act="shape-apply">${ic("move")}Сдвинуть и повернуть</button></div></div>
      <div class="row"><button class="btn" data-act="shape-rot-l">${ic("rotl")}Повернуть на −15°</button><button class="btn" data-act="shape-rot-r">${ic("rotr")}Повернуть на +15°</button></div>
      <p class="note">${ic("info")}Клавиши: стрелки — сдвиг (Shift — на 50 см), [ ] — поворот. Поворот идёт вокруг центра фигуры.</p>`;
  }

  function bindShape(pane) {
    const val = (k) => Number(pane.querySelector(`[data-f="${k}"]`)?.value || 0);
    bindForm(pane, {
      "shape-apply": () => commit(() => { translateObject(sel, val("dx"), val("dz")); if (val("deg")) rotateObject(sel, val("deg")); }),
      "shape-rot-l": () => commit(() => rotateObject(sel, -15)),
      "shape-rot-r": () => commit(() => rotateObject(sel, 15)),
      "shape-del": () => deleteSelected(),
    });
  }

  function pointsList(ring) {
    return `<div class="pts">${ring.map((p, i) => `<div class="pt ${sel.v === i ? "on" : ""}" data-pt="${i}"><span>${i + 1}</span>
      <input type="number" step="0.05" value="${p[0].toFixed(2)}" data-rx="${i}" aria-label="X точки ${i + 1}"><input type="number" step="0.05" value="${p[1].toFixed(2)}" data-rz="${i}" aria-label="Z точки ${i + 1}">
      <button class="icon-btn" data-rdel="${i}" title="Удалить точку">${ic("x")}</button></div>`).join("")}</div>`;
  }

  function bindRing(pane, ring) {
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

  function renderLawn(pane, l) {
    const ring = ringOf(sel);
    const holes = sel.part === -1 ? `<p class="note">${ic("info")}Дыры в газоне: ${l.holes.length}. Островок в газоне можно удалить, выбрав его в списке «Объекты».</p>` : "";
    pane.innerHTML = `
      <section class="card">
        ${head("lawn", sel.part === -1 ? "Газон или клумба" : `Дыра ${sel.part + 1}`, `lawn_${sel.i}`)}
        <div class="stats">Площадь: <b>${Math.round(area(l.outer))} м²</b> · точек контура: <b>${l.outer.length}</b></div>
        <p class="note">${ic("info")}Газон рисуется на своём уровне, чуть ниже асфальта. Там, где он лежит на тротуаре, тротуар уступает ему место. По дорогам газон не идёт.</p>
        ${holes}
        ${shapeControls()}
        <div class="actions"><button class="btn danger" data-act="shape-del">${ic("trash")}${sel.part === -1 ? "Удалить газон" : "Удалить дыру"}</button></div>
      </section>
      <section class="card">${subhead("points", sel.part === -1 ? "Точки контура" : "Точки дыры")}${pointsList(ring)}</section>`;
    bindShape(pane);
    bindRing(pane, ring);
  }

  function renderMarking(pane, m) {
    const line = !!m.points;
    const paint = m.type === "paint";
    const width = m.type === "stop" ? 0.4 : 0.13;
    pane.innerHTML = `
      <section class="card">
        ${head("marking", paint ? "Разметка из сцены" : MARK_TYPES[m.type] || m.type, m.id)}
        ${paint
          ? `<p class="note">${ic("info")}Разметка перенесена из запечённой сцены: контур не правится точками, но её можно сдвинуть, повернуть или удалить.</p>`
          : `<label class="field"><span>Тип</span><select data-f="mtype">${Object.entries(MARK_TYPES).map(([k, v]) => `<option value="${k}" ${m.type === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>`}
        <label class="field"><span>Цвет</span><select data-f="mcolour">${Object.entries(MARK_COLOURS).map(([k, v]) => `<option value="${k}" ${(m.colour || "white") === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
        ${m.type === "solid" || m.type === "dashed" || m.type === "stop" ? fieldNum("Ширина", m.width || width, "mwidth", 0.01, "м") : ""}
        ${m.type === "zebra" ? fieldNum("Длина полос", m.length || 4, "mlength", 0.5, "м") : ""}
        ${shapeControls()}
        <div class="actions"><button class="btn danger" data-act="shape-del">${ic("trash")}Удалить разметку</button></div>
      </section>
      ${line ? `<section class="card">${subhead("points", "Точки линии")}${pointsList(m.points)}</section>` : ""}`;
    bindShape(pane);
    if (line) bindRing(pane, m.points);
    bindForm(pane, {
      mtype: (el) => commit(() => {
        m.type = el.value;
        if ((m.type === "stop" || m.type === "zebra") && m.points) m.points = m.points.slice(0, 2);
        if (m.type === "zebra") m.length = m.length || 4;
      }),
      mcolour: (el) => commit(() => { m.colour = el.value; }),
      mwidth: (el) => commit(() => { m.width = Number(el.value); }),
      mlength: (el) => commit(() => { m.length = Number(el.value); }),
    });
  }

  function renderActor(pane, a) {
    const r = a.route && routeOf(a.route);
    const types = catalog ? Object.keys(catalog.actorTypes) : [a.type];
    pane.innerHTML = `
      <section class="card">
        ${head("car", esc(a.name || a.id), a.id)}
        <label class="field"><span>Название</span><input type="text" value="${esc(a.name)}" data-f="name"></label>
        <label class="field"><span>Тип</span><select data-f="type">${types.map((t) => `<option value="${t}" ${a.type === t ? "selected" : ""}>${TYPE[t] || t}</option>`).join("")}</select></label>
        <div class="row2">${fieldNum("X", a.pos[0], "x", 0.05, "м")}${fieldNum("Z", a.pos[1], "z", 0.05, "м")}</div>
        <div class="row2">${fieldNum("Поворот", a.yaw * RAD, "yaw", 1, "°")}${fieldNum("Масштаб", a.scale[0], "scale", 0.05)}</div>
      </section>
      <section class="card">
        ${subhead("route", "Движение")}
        <div class="row2">${fieldNum("Скорость", a.maxSpeed, "maxSpeed", 0.5, "м/с")}${fieldNum("Дистанция", a.clearDistance, "clearDistance", 0.5, "м")}</div>
        <label class="check"><input type="checkbox" data-f="staysPut" ${a.behaviour?.staysPut ? "checked" : ""}> Стоит на месте (припаркован)</label>
        <label class="check"><input type="checkbox" data-f="waitsForPlayer" ${a.behaviour?.waitsForPlayer ? "checked" : ""}> Пропускает игрока</label>
        <div class="route-line">${r ? `Путь: ${r.points.length} точек, ${polyLength(r.points).toFixed(1)} м` : "Пути нет — участник стоит на месте"}</div>
        <div class="actions">
          <button class="btn" data-act="actor-route">${ic("route")}${r ? "Перерисовать путь" : "Нарисовать путь"}</button>
          ${r ? `<button class="btn" data-act="actor-route-sel">${ic("cursor")}Показать путь</button>` : ""}
        </div>
      </section>
      <section class="card"><div class="actions" style="margin-top:0"><button class="btn danger" data-act="actor-del">${ic("trash")}Удалить участника</button></div></section>`;
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
        ${head("light", "Светофор", l.id)}
        <label class="field"><span>Сигнал</span><select data-f="state">${Object.entries(LIGHT).map(([k, v]) => `<option value="${k}" ${l.state === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
        <label class="field"><span>Стрелка</span><select data-f="arrow">${Object.entries(ARROW).map(([k, v]) => `<option value="${k}" ${(l.arrow || "") === k ? "selected" : ""}>${v}</option>`).join("")}</select></label>
        <div class="row2">${fieldNum("X", l.pos[0], "x", 0.05, "м")}${fieldNum("Z", l.pos[1], "z", 0.05, "м")}</div>
        <div class="row2">${fieldNum("Поворот", l.yaw * RAD, "yaw", 1, "°")}${fieldNum("Масштаб", l.scale, "scale", 0.05)}</div>
        <div class="actions"><button class="btn danger" data-act="light-del">${ic("trash")}Удалить светофор</button></div>
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
        ${head("tree", esc(propTitle(d.prop)), d.id)}
        <label class="field"><span>Предмет</span><select data-f="prop">${props.map((p) => `<option value="${p}" ${d.prop === p ? "selected" : ""}>${esc(propTitle(p))}</option>`).join("")}</select></label>
        <div class="row2">${fieldNum("X", d.pos[0], "x", 0.05, "м")}${fieldNum("Z", d.pos[1], "z", 0.05, "м")}</div>
        <div class="row2">${fieldNum("Поворот", d.yaw * RAD, "yaw", 1, "°")}${fieldNum("Масштаб", d.scale[0], "scale", 0.05)}</div>
        <label class="field"><span>Оттенок</span><div class="tint"><input type="color" value="${d.tint || "#ffffff"}" data-f="tint"><button class="btn" data-act="tint-clear">Без оттенка</button></div></label>
        <div class="actions"><button class="btn danger" data-act="decor-del">${ic("trash")}Удалить предмет</button></div>
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
        ${head("flag", "Стоп-линия и старт", "stop")}
        <div class="row2">${fieldNum("X", S.stop.x, "x", 0.05, "м")}${fieldNum("Z", S.stop.z, "z", 0.05, "м")}</div>
        ${fieldNum("Направление", S.stop.yaw * RAD, "yaw", 1, "°")}
        <p class="note">${ic("info")}Стоп-линия и конец подъезда — одна точка. Перетащите её на плане или введите координаты.</p>
        <div class="actions">
          <button class="btn" data-act="stop-to-approach">${ic("pin")}Поставить в конец подъезда</button>
          ${ap ? `<button class="btn" data-act="approach-sel">${ic("route")}Показать подъезд</button>` : ""}
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

  // ---- stitching -----------------------------------------------------------------------
  // The report comes from the server (the seam of each scene, measured where the game joins them).
  async function stitchUpdate() {
    if (stitch.b === id) stitch.b = null;   // a scene is not its own neighbour (after switching scenes)
    if (!S || !stitch.b) {
      stitch.report = null;
      Scene3D.setNeighbour(null);
      return renderInspector();
    }
    const mine = ++stitchSeq;
    const q = new URLSearchParams({ side: stitch.side });
    if (stitch.dx !== null) q.set("dx", stitch.dx);
    if (stitch.dz !== null) q.set("dz", stitch.dz);
    const [rep, B] = await Promise.all([
      api(`/api/stitch/${id}/${stitch.b}?${q}`),
      stitch.bid === stitch.b && stitch.build ? stitch.build : api(`/api/scene/${stitch.b}`).then((r) => r.build),
    ]).catch((e) => { toast(e.message, "bad"); return [null, null]; });
    if (mine !== stitchSeq || !rep) return;
    stitch.build = B;
    stitch.bid = stitch.b;
    stitch.report = rep;
    Scene3D.setNeighbour(B, rep.dx, rep.dz, rep.seam);
    renderInspector();
  }

  function renderStitch(pane) {
    const r = stitch.report;
    const options = scenes.filter((s) => s.id !== id)
      .map((s) => `<option value="${s.id}" ${stitch.b === s.id ? "selected" : ""}>${esc(sceneTitle(s.id))}</option>`).join("");
    const sides = [["n", "Север ↑"], ["s", "Юг ↓"], ["e", "Восток →"], ["w", "Запад ←"]]
      .map(([k, label]) => `<button class="side ${stitch.side === k ? "on" : ""}" data-side="${k}">${label}</button>`).join("");
    const line = (ok, text) => `<div class="chk-row ${ok ? "ok" : "bad"}">${ic(ok ? "check-circle" : "error")}<span>${text}</span></div>`;
    let report = `<p class="note">Выберите соседнюю сцену.</p>`;
    if (r && r.error) report = line(false, r.error);
    else if (r) {
      const gap = r.gap;
      report = [
        line(r.a.street, `Этот край: ${fmt(r.a.width)} м${r.a.street ? ", как улица" : ""}`),
        line(r.b.street, `Сосед: ${fmt(r.b.width)} м${r.b.street ? ", как улица" : ""}`),
        Math.abs(gap) < 0.2 ? line(true, "Без зазора") : line(false, gap > 0 ? `Зазор ${fmt(gap)} м: его заполнит улица` : `Наложение ${fmt(-gap)} м`),
        line(Math.abs(r.offset) < 0.1, `Сдвиг по стыку ${fmt(r.offset, 2)} м`),
        line(Math.abs(r.widthDiff) < 0.1, `Разница ширины ${fmt(r.widthDiff, 2)} м`),
      ].join("");
    }
    pane.innerHTML = `
      <section class="card">
        ${head("link", "Соседняя сцена")}
        <label class="field"><span>Сцена</span><select id="st-b"><option value="">Нет</option>${options}</select></label>
        <div class="sides">${sides}</div>
        <div class="row2">
          <label class="field"><span>Сдвиг X <em>м</em></span><input type="number" step="0.1" id="st-dx" value="${r && !r.error ? r.dx : ""}"></label>
          <label class="field"><span>Сдвиг Z <em>м</em></span><input type="number" step="0.1" id="st-dz" value="${r && !r.error ? r.dz : ""}"></label>
        </div>
        <div class="actions" style="margin-top:0">
          <button class="btn" data-act="st-auto">${ic("move")}Совместить</button>
          <button class="btn" data-act="st-open" ${stitch.b ? "" : "disabled"}>${ic("scenes")}Открыть</button>
        </div>
      </section>
      <section class="card">${subhead("check", "На стыке")}${report}</section>`;
    const st = (fn) => () => { fn(); stitchUpdate(); };
    pane.querySelector("#st-b").addEventListener("change", (e) => { stitch.b = e.target.value || null; stitch.dx = stitch.dz = null; stitch.bid = null; st(() => {})(); });
    pane.querySelectorAll("[data-side]").forEach((b) => b.addEventListener("click", () => { stitch.side = b.dataset.side; stitch.dx = stitch.dz = null; st(() => {})(); }));
    pane.querySelector("#st-dx").addEventListener("change", (e) => { stitch.dx = e.target.value === "" ? null : Number(e.target.value); st(() => {})(); });
    pane.querySelector("#st-dz").addEventListener("change", (e) => { stitch.dz = e.target.value === "" ? null : Number(e.target.value); st(() => {})(); });
    bindForm(pane, {
      "st-auto": () => { stitch.dx = stitch.dz = null; stitchUpdate(); },
      "st-open": () => { if (stitch.b) openScene(stitch.b).catch((err) => toast(err.message, "bad")); },
    });
  }

  // ---- textures: the inspector of one texture ------------------------------------------
  function renderTexture(pane) {
    const kind = texSel;
    const info = Textures.INFO[kind] || { name: kind, where: "" };
    const meta = Textures.metaOf(kind);
    const p = Textures.draftOf(kind);
    const ground = Textures.isGround(kind);
    const numberRow = (key) => {
      const d = Textures.PARAMS[key];
      const digits = d.step < 0.1 ? 2 : 1;
      return `<div class="tex-param">
        <div class="tex-param-h"><span>${d.label}</span><em data-val="${key}">${fmt(p[key], digits)}${d.unit ? ` ${d.unit}` : ""}</em></div>
        <p class="hint">${d.hint}</p>
        <div class="pair">
          <input type="range" min="${d.min}" max="${d.max}" step="${d.step}" value="${p[key]}" data-range="${key}" aria-label="${d.label}">
          <input type="number" min="${d.min}" max="${d.max}" step="${d.step}" value="${p[key]}" data-num="${key}" aria-label="${d.label}, число">
        </div></div>`;
    };
    const inScene = !!info.inScene;
    pane.innerHTML = `
      <section class="card">
        <div class="tex-head"><canvas class="tex-thumb" width="96" height="96" data-thumb="${kind}"></canvas><div><b>${esc(info.name)}</b><small>${kind}</small></div></div>
        <p class="tex-where">${esc(info.where)}</p>
        <div class="tex-preview"><canvas id="tex-canvas" width="360" height="360"></canvas></div>
        <div class="tex-views" role="group" aria-label="Что показать">
          <button data-view="final" class="${texView === "final" ? "on" : ""}">Как в игре</button>
          <button data-view="fine" class="${texView === "fine" ? "on" : ""}">Зерно</button>
          <button data-view="large" class="${texView === "large" ? "on" : ""}">Пятна</button>
        </div>
        <p class="tex-file">${meta.width ? `${meta.width} × ${meta.height} px` : "картинка не найдена"} · textures/detail/${kind}.png</p>
        <p class="tex-note ${inScene ? "" : "plain"}">${inScene
          ? `${ic("info")} Видна на плане.`
          : `${ic("info")} Только в игре.`}</p>
      </section>
      <section class="card">
        ${subhead("sliders", "Настройки")}
        ${numberRow("gain")}${numberRow("macro")}${numberRow("macroScale")}${ground ? numberRow("period") : ""}
        <div class="actions" style="margin-top:4px">
          <button class="btn" data-act="tex-reset">${ic("reset")}Вернуть как было</button>
          <button class="btn primary" data-act="tex-save">${ic("save")}Сохранить текстуру</button>
        </div>
      </section>
      <section class="card">
        ${subhead("upload", "Картинка")}
        <p class="note">PNG 256 × 256. Прежняя картинка сохранится.</p>
        <div class="actions" style="margin-top:0">
          <button class="btn" data-act="tex-upload">${ic("upload")}Заменить картинку</button>
          <button class="btn" data-act="tex-restore" ${meta.backups ? "" : "disabled"}>${ic("undo")}Вернуть прежнюю${meta.backups ? ` (${meta.backups})` : ""}</button>
        </div>
      </section>`;
    drawTexturePreview();
    drawThumbs(pane);
    updateTextureButtons();
    pane.querySelectorAll("[data-view]").forEach((b) => b.addEventListener("click", () => {
      texView = b.dataset.view;
      pane.querySelectorAll("[data-view]").forEach((x) => x.classList.toggle("on", x === b));
      drawTexturePreview();
    }));
    // A slider and its number box move together; the plan follows at once, the list on the change.
    pane.querySelectorAll("[data-range],[data-num]").forEach((el) => {
      const key = el.dataset.range ?? el.dataset.num;
      const d = Textures.PARAMS[key];
      el.addEventListener("input", () => {
        if (el.value === "") return;
        const v = Math.min(d.max, Math.max(d.min, Number(el.value)));
        if (!Number.isFinite(v)) return;
        Textures.setParam(kind, key, v);
        pane.querySelectorAll(`[data-range="${key}"],[data-num="${key}"]`).forEach((x) => { if (x !== el) x.value = v; });
        pane.querySelector(`[data-val="${key}"]`).textContent = fmt(v, d.step < 0.1 ? 2 : 1) + (d.unit ? ` ${d.unit}` : "");
        textureChanged(kind, false);
      });
      el.addEventListener("change", () => textureChanged(kind, true));
    });
    bindForm(pane, {
      "tex-reset": () => { Textures.reset(kind); renderInspector(); textureChanged(kind, true); },
      "tex-save": () => saveTexture(kind),
      "tex-upload": () => $("#texture-file").click(),
      "tex-restore": () => restoreTexture(kind),
    });
  }

  function drawTexturePreview() {
    const c = $("#tex-canvas");
    if (c && texSel) Textures.draw(c, texSel, texView, 2);
  }

  function updateTextureButtons() {
    const dirtyNow = texSel && Textures.isDirty(texSel);
    document.querySelectorAll('[data-act="tex-reset"],[data-act="tex-save"]').forEach((b) => { b.disabled = !dirtyNow; });
  }

  // A texture changed: the 3D view, its thumbnail and the list follow; `commit` also marks the list.
  function textureChanged(kind, commitNow) {
    Scene3D.setTextures(Textures.forScene());
    drawTexturePreview();
    const thumb = document.querySelector(`canvas[data-thumb="${kind}"]`);
    if (thumb) Textures.draw(thumb, kind, "final", 1);
    updateTextureButtons();
    if (commitNow) { renderTextures(); renderHeader(); }
    else renderHeader();
  }

  async function saveTexture(kind) {
    const p = Textures.draftOf(kind);
    const body = { gain: p.gain, macro: p.macro, macroScale: p.macroScale };
    if (p.period !== undefined) body.period = p.period;
    try {
      await api(`/api/texture/${kind}`, body);
      Textures.markSaved(kind);
      toast(`Текстура «${Textures.INFO[kind]?.name || kind}» сохранена. Игра возьмёт её при следующем запуске`, "good");
    } catch (e) {
      toast(`Не сохранено: ${e.message}`, "bad");
    }
    renderTextures();
    renderHeader();
    updateTextureButtons();
  }

  async function restoreTexture(kind) {
    try {
      const r = await api(`/api/texture/${kind}/restore`, {});
      await Textures.reloadPicture(kind, {});
      Scene3D.reloadPicture(kind);
      toast(r.imported ? "Прежняя картинка возвращена" : "Прежняя картинка возвращена. Godot не найден: откройте проект в Godot, чтобы он переимпортировал текстуру", r.imported ? "good" : "warn");
      renderInspector();
      renderTextures();
    } catch (e) {
      toast(`Не возвращено: ${e.message}`, "bad");
    }
  }

  // ---- the question ------------------------------------------------------------------
  // The question: the original ticket picture and text, and the answer and rules the game uses.
  function renderQuestion(pane) {
    const q = S.question;
    const ru = (q.text && q.text.ru) || {};
    const src = source;
    const srcBlock = src ? `
      <section class="card">
        ${head("ticket", "Оригинал билета", `${src.category === "ab" ? "A/B" : "C/D"} · билет ${src.ticket}, вопрос ${src.number}`)}
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
        ${subhead("cursor", "Что видит игрок")}
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
        ${subhead("check", "Сверка с билетом")}
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
    $("#check-count").className = err ? "bad" : warn ? "warn" : "";
    if (rtab !== "checks") return;
    if (!S) return;
    const items = findings.length ? findings.map((f, i) => `
      <button class="finding ${f.level}" data-finding="${i}"><i>${ic(f.level === "error" ? "error" : "alert")}</i><span>${esc(f.message)}</span>${ic("chevron")}</button>`).join("")
      : `<div class="ok-box">${ic("check-circle")}Ошибок нет: дорога, маршруты и участники на месте.</div>`;
    pane.innerHTML = `<section class="card">${head("check", "Проверка сцены")}<p class="note">Ошибки мешают игре. Предупреждения проверьте глазами. Нажмите строку, чтобы перейти к объекту.</p>${items}</section>`;
    pane.querySelectorAll("[data-finding]").forEach((el) => el.addEventListener("click", () => focusFinding(findings[Number(el.dataset.finding)])));
  }

  function focusFinding(f) {
    const ref = f.ref;
    if (!ref) return;
    if (ref.type === "question") { rtab = "question"; renderInspector(); return; }
    let s = null;
    if (ref.type === "route") s = { t: "route", id: ref.id };
    else if (ref.type === "road") { const i = S.roads.findIndex((r) => r.id === ref.id); if (i >= 0) s = { t: "road", i, part: -1 }; }
    else if (ref.type === "lawn") { const i = S.lawns.findIndex((l) => l.id === ref.id); if (i >= 0) s = { t: "lawn", i, part: -1 }; }
    else if (ref.type === "marking") { if (markingOf(ref.id)) s = { t: "marking", id: ref.id }; }
    else if (ref.type === "stop") s = { t: "stop" };
    else if (ref.type === "light") s = { t: "light", id: ref.id };
    else if (ref.type === "actor") s = { t: "actor", id: ref.id };
    else if (ref.type === "prop") s = ref.id ? { t: "decor", id: ref.id } : null;
    if (!s) return;
    rtab = "props";
    ltab = "scenes";
    setLeftTab("scenes");
    select(s);
    const o = objectOf(s);
    const at = o && (o.points || o.outer || (o.pos ? o.pos : null));
    if (at) {
      const c = at.length && Array.isArray(at[0]) ? at[Math.floor(at.length / 2)] : at;
      Scene3D.focus(c[0], c[1]);
    }
  }

  // ---- boot --------------------------------------------------------------------------
  function setLeftTab(name) {
    // Textures are not drawn on the plan: a clicked drawing tool would start a shape there, so it is put away.
    if (name === "textures" && tool !== "select") { cancelDraft(); tool = "select"; }
    ltab = name;
    document.querySelectorAll("[data-ltab]").forEach((x) => x.classList.toggle("on", x.dataset.ltab === name));
    $("#pane-scenes").hidden = name !== "scenes";
    $("#pane-objects").hidden = name !== "objects";
    $("#pane-textures").hidden = name !== "textures";
    renderAll();
  }

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
    document.querySelectorAll("[data-ltab]").forEach((b) => b.addEventListener("click", () => setLeftTab(b.dataset.ltab)));
    $("#oq").addEventListener("input", (e) => { objQuery = e.target.value; renderTree(); });
    $("#object-tree").addEventListener("click", (e) => {
      const g = e.target.closest("[data-group]");
      if (g) { openGroups[g.dataset.group] = openGroups[g.dataset.group] === false; renderTree(); return; }
      const r = e.target.closest("[data-sel]");
      if (r) { const s = JSON.parse(r.dataset.sel); select(s); focusSelection(s); }
    });
    $("#tq").addEventListener("input", (e) => { texQuery = e.target.value; renderTextures(); });
    $("#tex-list").addEventListener("click", (e) => {
      const b = e.target.closest("[data-tex]");
      if (!b) return;
      texSel = b.dataset.tex;
      sel = null;
      Scene3D.setSelection(null);
      rtab = "props";
      renderAll();
    });
    document.querySelectorAll("[data-rtab]").forEach((b) => b.addEventListener("click", () => {
      rtab = b.dataset.rtab;
      renderInspector();
      renderChecks();
    }));
    $("#undo").onclick = undo;
    $("#redo").onclick = redo;
    $("#save").onclick = saveAll;
    $("#help").onclick = () => $("#help-dialog").hidden = false;
    $("#help-dialog").addEventListener("click", (e) => { if (e.target.id === "help-dialog" || e.target.dataset.close !== undefined) $("#help-dialog").hidden = true; });
    $("#legend-toggle").onclick = () => { legendOpen = !legendOpen; renderStatus(); };
    $("#legend-close").onclick = () => { legendOpen = false; renderStatus(); };
    $("#draft-done").onclick = () => finishDraft();
    $("#draft-cancel").onclick = () => { cancelDraft(); renderTools(); };
    $("#sel-move").onclick = () => setGizmoMode("move");
    $("#sel-turn").onclick = () => setGizmoMode("rotate");
    $("#sel-rotl").onclick = () => rotate(-15);
    $("#sel-rotr").onclick = () => rotate(15);
    $("#sel-del").onclick = () => deleteSelected();
    $("#sel-off").onclick = () => select(null);
    $("#zin").onclick = () => Scene3D.zoomBy(1.25);
    $("#zout").onclick = () => Scene3D.zoomBy(0.8);
    $("#zfit").onclick = () => Scene3D.fit();
    $("#mode-plan").onclick = () => setView("plan");
    $("#mode-3d").onclick = () => setView("3d");
    $("#texture-file").addEventListener("change", uploadTexture);
    addEventListener("beforeunload", (e) => { if (anyDirty()) { e.preventDefault(); e.returnValue = ""; } });
    document.addEventListener("keydown", onKey);
    Scene3D.on("pointer", onPointer);
    Scene3D.on("zoom", renderStatus);
    Scene3D.on("mode", renderStatus);
  }

  // A PNG chosen for the texture: the server keeps the old one and the game reimports the new.
  async function uploadTexture(e) {
    const file = e.target.files[0];
    e.target.value = "";
    const kind = texSel;
    if (!file || !kind) return;
    try {
      const r = await fetch(`/api/texture/${kind}/image`, { method: "POST", headers: { "Content-Type": "image/png" }, body: file });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data.error || r.statusText);
      const backups = (Textures.metaOf(kind).backups || 0) + 1;
      await Textures.reloadPicture(kind, { width: data.width, height: data.height, backups });
      Scene3D.reloadPicture(kind);
      toast(data.imported ? `Картинка «${Textures.INFO[kind]?.name || kind}» заменена` : "Картинка заменена. Godot не найден: откройте проект в Godot, чтобы он переимпортировал текстуру",
        data.imported ? "good" : "warn");
      renderInspector();
      renderTextures();
    } catch (err) {
      toast(`Не заменено: ${err.message}`, "bad");
    }
  }

  function setView(m) {
    Scene3D.setMode(m);
    renderStatus();
  }

  function focusSelection(s) {
    const o = objectOf(s);
    if (!o) return;
    let c = null;
    if (s.t === "stop") c = [S.stop.x, S.stop.z];
    else if (o.pos) c = o.pos;
    else if (o.points) c = o.points[Math.floor(o.points.length / 2)];
    else if (o.outer) c = o.outer[0];
    else if (o.polygons && o.polygons.length) c = o.polygons[0].outer[0];
    if (c) Scene3D.focus(c[0], c[1]);
  }

  function isTyping(e) {
    const t = e.target;
    return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable);
  }

  function onKey(e) {
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === "s") { e.preventDefault(); return saveAll(); }
    if (mod && e.key.toLowerCase() === "z") { e.preventDefault(); return e.shiftKey ? redo() : undo(); }
    if (isTyping(e) || mod) return;
    if (!S) return;
    const k = e.key.toLowerCase();
    if (k === "w" && sel) { e.preventDefault(); return setGizmoMode("move"); }
    if (k === "e" && sel) { e.preventDefault(); return setGizmoMode("rotate"); }
    if (k === "r" && PLACE.includes(tool)) {
      e.preventDefault();
      placeYaw += Math.PI / 12;
      return showGhost(tool, cursorWorld, placeYaw);
    }
    if (k === "r" && sel) { e.preventDefault(); return rotate(15); }
    if (k === "t") { e.preventDefault(); return setView(Scene3D.mode === "plan" ? "3d" : "plan"); }
    const map = { q: "select", v: "select", m: "route", d: "road", c: "contour", i: "island", g: "lawn", k: "marking", p: "decor", a: "actor", l: "light", s: "stop" };
    if (map[k] && !e.altKey) { e.preventDefault(); return setTool(map[k]); }
    if (k === "escape") { cancelDraft(); setTool("select"); select(null); return; }
    if (k === "enter") { e.preventDefault(); return finishDraft(); }
    if (k === "backspace" || k === "delete") { e.preventDefault(); return deleteSelected(); }
    const step = e.shiftKey ? 0.5 : 0.05;
    if (k === "arrowleft") { e.preventDefault(); return nudge(-step, 0); }
    if (k === "arrowright") { e.preventDefault(); return nudge(step, 0); }
    if (k === "arrowup") { e.preventDefault(); return nudge(0, step); }
    if (k === "arrowdown") { e.preventDefault(); return nudge(0, -step); }
    // With Shift the key reports "{" or "}", not "[" or "]": both forms are taken.
    if (k === "[" || k === "{") { e.preventDefault(); return rotate(k === "{" ? -45 : -5); }
    if (k === "]" || k === "}") { e.preventDefault(); return rotate(k === "}" ? 45 : 5); }
    if (k === "f") return Scene3D.fit();
    if (k === "?") return ($("#help-dialog").hidden = false);
  }

  async function boot() {
    buildTools();
    bindUi();
    Scene3D.mount($("#view"));
    catalog = await api("/api/catalog");
    await Textures.load();
    Scene3D.setTextures(Textures.forScene());
    await loadList();
    renderAll();
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
