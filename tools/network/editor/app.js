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
    scenes: [], questions: [], questionsLoaded: false, catalog: null, sel: [], hidden: new Set(), locked: new Set(),
    undo: [], redo: [], savedJson: "", dirty: false, clipboard: null, testing: false,
    deletedSceneIds: new Set(),
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
  let cancelConfirmation = null;
  function confirmBox(title, text, yes = "Да", allowDiscard = false) {
    cancelConfirmation?.();
    return new Promise((resolve) => {
      $("#confirm-title").textContent = title;
      $("#confirm-text").textContent = text;
      $("#confirm-yes").textContent = yes;
      $("#confirm-discard").hidden = !allowDiscard;
      const box = $("#confirm");
      box.hidden = false;
      const done = (v) => { box.hidden = true; box.onclick = null; cancelConfirmation = null; document.removeEventListener("keydown", key, true); resolve(v); };
      cancelConfirmation = () => done(false);
      const key = e => { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); done(false); } };
      document.addEventListener("keydown", key, true);
      box.onclick = (e) => {
        const a = e.target.closest("[data-answer]");
        if (a) done(allowDiscard && a.dataset.answer === "discard" ? "discard" : a.dataset.answer === "yes");
        else if (e.target === box) done(false);
      };
    });
  }

  // ---- the scene's objects --------------------------------------------------------------------
  const S = () => state.S;
  // The scene with a road plan to find lanes in: its own, or the one detected for a traced scene.
  const hasPlayerPlan = scene => !!scene?.layout && !scene.layout.preserveSource;
  function planScene() {
    if (hasPlayerPlan(state.S)) return state.S;
    if (!state.S) return null;
    const added = state.S.layout?.preserveSource ? state.S.layout : null;
    if (!added?.streets.length) return state.plan ? {...state.S, layout:state.plan} : null;
    // Lane suggestions may combine detected native roads and authored additions;
    // this temporary graph never replaces either source or the player's routes.
    const base = state.plan || {nodes:[],streets:[]}, prefix = added.generatedPrefix || "plan_";
    return {...state.S, layout:{...base,
      nodes:[...base.nodes, ...added.nodes.map(node => ({...node, id:prefix+node.id}))],
      streets:[...base.streets, ...added.streets.map(street => ({...street, id:prefix+street.id, a:prefix+street.a, b:prefix+street.b}))],
    }};
  }
  function objectOf(ref) {
    const s = state.S;
    if (!s || !ref) return null;
    switch (ref.t) {
      case "pocket": return (s.pockets || []).find((x) => x.id === ref.id);
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
    if (ref.t === "route" && o.display === "letter") return [];
    if (ref.t === "route" || ref.t === "track") return o.points;
    if (ref.t === "marking") return o.points || (o.polygons && o.polygons[0] && o.polygons[0].outer);
    if (ref.t === "lawn") return o.outer;
    if (ref.t === "road") return ref.part >= 0 ? o.holes[ref.part] : o.outer;
    return null;
  }
  function shapeCenter(ref) {
    const points = pointsOfRef(ref) || [];
    if (!points.length) return [0, 0];
    return [0, 1].map(axis => (Math.min(...points.map(p => p[axis])) + Math.max(...points.map(p => p[axis]))) / 2);
  }
  const isGeneratedSurface = (item, scene = state.S) => !!item && (scene?.layout?.preserveSource
    ? Layout.planGenerated(scene, item) : !!item.auto);
  const isNativeShape = ref => ["road", "lawn"].includes(ref.t) && !isGeneratedSurface(objectOf(ref));
  const isPaint = (ref) => objectOf(ref)?.type === "paint";
  const layerOf = (ref) => ({ pocket: "roads", decor: "decor", track: "roads", sign: "signs", actor: "actors", officer: "actors", light: "lights", route: "routes", marking: "marks", lawn: "roads",
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
      case "track": return o.railType === "railway" ? "Железнодорожные рельсы" : o.depot ? "Рельсы в депо" : "Рельсы";
      case "route":
        if (o.kind === "annotation") return o.style === "text" ? o.text || "Надпись" : "Линия-обозначение";
        if (o.kind === "guide") return "Синяя стрелка игрока";
        if (o.kind === "manoeuvre") return `Манёвр: ${Catalog.EXITS[o.exit]?.title.toLowerCase() || o.exit}`;
        if (o.kind === "choice") return o.display === "letter" ? `Буква ${o.label}` : `Ответ ${o.label}`;
        if (o.kind === "approach") return "Подъезд игрока";
        return `Путь: ${objectOf({ t: "actor", id: o.id.replace(/^actor_/, "") })?.name || "участник"}`;
      case "marking": return o.type === "paint" ? "Разметка сцены" : Catalog.MARKS[o.type]?.title || o.type;
      case "pocket": return "Дорожный карман";
      case "lawn": return "Газон";
      case "road": return ref.part >= 0 ? "Островок" : o.name || "Дорога";
      case "street": return Layout.KINDS[o.kind || "street"].title;
      case "node": return o.ring ? "Кольцо" : "Перекрёсток";
      case "stop": return "Игрок и стоп-линия";
      default: return ref.t;
    }
  }

  // ---- history -----------------------------------------------------------------------------
  const snapshotText = () => JSON.stringify(state.S);
  function followAssistantApproval(review, reviewed, questionPool, saved) {
    const apply = scene => {
      scene.assistantReview = { ...review };
      scene.reviewed = reviewed === true;
      if (questionPool) scene.questionPool = { ...questionPool };
      else delete scene.questionPool;
      return scene;
    };
    apply(state.S);
    apply(saved);
    // Undo remains available for geometry, but can never undo an approval action.
    for (const key of ["undo", "redo"]) state[key] = state[key].map(text => JSON.stringify(apply(JSON.parse(text))));
  }
  // One undo step around fn (which changes state.S). The road plan rebuilds what it makes.
  let lastMergedEdit = null;
  function actorIntents() {
    if (!state.S?.layout?.preserveSource) return null;
    return new Map((state.S.actors || []).map(actor => [actor.id, JSON.stringify([
      actor.pos, actor.yaw, actor.way, actor.behaviour?.staysPut, actor.track,
      state.S.routes.find(route => route.id === (actor.route || `actor_${actor.id}`))?.manual,
    ])]));
  }
  function refreshEditedActors(before) {
    if (!before) return;
    const after = actorIntents(), plan = planScene();
    if (!after || !plan) return;
    const actors = state.S.actors.filter(actor => before.get(actor.id) !== after.get(actor.id));
    if (!actors.length) return;
    const subset = {...state.S, actors};
    Layout.applyActors(subset, plan);
    state.S.routes = subset.routes;
  }
  function edit(fn, opts = {}) {
    if (!state.S) return;
    const before = snapshotText();
    const intents = opts.rebuild !== false ? actorIntents() : null;
    const result = fn(state.S);
    if (opts.rebuild !== false) {
      if (state.S.layout) Layout.apply(state.S);
      if (state.S.tracks) Tracks.apply(state.S);
      if (!state.S.layout && state.plan) Layout.applyActors(state.S, planScene());
      refreshEditedActors(intents);
    }
    const after = snapshotText();
    if (after === before) return result;
    const now = Date.now();
    const merge = opts.merge && lastMergedEdit?.key === opts.merge && lastMergedEdit.after === before &&
      lastMergedEdit.scene === state.S && now - lastMergedEdit.time < 600;
    if (!merge || !state.undo.length) state.undo.push(before);
    lastMergedEdit = opts.merge ? {key:opts.merge, after, scene:state.S, time:now} : null;
    if (state.undo.length > 400) state.undo.shift();
    state.redo = [];
    changed(opts);
    return result;
  }
  // A drag: one undo step from its start, the view follows every move.
  let dragBase = null, dragGeneration = 0;
  function beginDrag() {
    lastMergedEdit = null;
    dragBase = snapshotText();
    dragGeneration++;
  }
  function dragMove(fn, opts = {}) {
    const intents = opts.rebuild !== false ? actorIntents() : null;
    fn(state.S);
    if (opts.rebuild !== false) {
      if (state.S.layout) Layout.apply(state.S);
      if (state.S.tracks) Tracks.apply(state.S);
      if (!state.S.layout && state.plan) Layout.applyActors(state.S, planScene());
      refreshEditedActors(intents);
    }
    Scene3D.refresh(state.S);
    App.renderSelection?.();
    App.refreshRoadGeometry?.();
    if (opts.rebuild !== false || opts.surfaces) schedulePreview(true);
  }
  function endDrag(opts = {}) {
    if (dragBase === null) return;
    const before = dragBase;
    dragBase = null;
    if (snapshotText() !== before) {
      state.undo.push(before);
      state.redo = [];
      changed(opts);
    }
  }
  function cancelDrag() {
    if (dragBase === null) return;
    if (snapshotText() === dragBase) { dragBase = null; return; }
    state.S = JSON.parse(dragBase);
    dragBase = null;
    afterHistory();
  }
  function undo() {
    if (dragBase !== null) {
      if (typeof Tools !== "undefined") Tools.escape?.();
      cancelDrag();
      return;
    }
    if (!state.undo.length) return;
    state.redo.push(snapshotText());
    state.S = JSON.parse(state.undo.pop());
    afterHistory();
  }
  function redo() {
    if (dragBase !== null) {
      if (typeof Tools !== "undefined") Tools.escape?.();
      cancelDrag();
      return;
    }
    if (!state.redo.length) return;
    state.undo.push(snapshotText());
    state.S = JSON.parse(state.redo.pop());
    afterHistory();
  }
  function afterHistory() {
    state.sel = state.sel.filter((r) => objectOf(r));
    App.selectionChanged?.();
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
  let previewTimer = null, previewRevision = 0, previewEpoch = 0;
  let previewFlight = false, previewPending = false;
  function schedulePreview(live = false) {
    previewRevision++;
    previewPending = true;
    // Throttle a held pointer rather than debouncing it: surfaces and markings
    // keep following the handle even when the pointer never comes to rest.
    if (live && (previewTimer !== null || previewFlight)) return;
    clearTimeout(previewTimer);
    previewTimer = setTimeout(runPreview, live ? 40 : 0);
  }
  async function runPreview() {
    previewTimer = null;
    if (!state.S || previewFlight || !previewPending) return;
    previewPending = false;
    previewFlight = true;
    const mine = previewRevision, epoch = previewEpoch, sid = state.id;
    const gesture = dragBase === null ? null : dragGeneration;
    const current = () => epoch === previewEpoch && sid === state.id;
    try {
      const r = await api(`/api/preview/${sid}`, state.S);
      // During the same drag, show completed frames in order. After release,
      // cancellation, undo or a scene change only the exact latest frame may win.
      const live = gesture !== null && dragBase !== null && gesture === dragGeneration;
      if (!current() || (mine !== previewRevision && !live)) return;
      state.build = r.build;
      Scene3D.setBuild(r.build);
      if (mine === previewRevision) {
        state.findings = r.findings;
        state.edges = r.edges;
        if (dragBase === null) {
          renderTop();
          App.renderPanels?.({ only: ["inspector"] });
        }
      }
    } catch (error) {
      if (current() && mine === previewRevision) toast(error.message, "bad");
    } finally {
      previewFlight = false;
      if (previewPending) {
        clearTimeout(previewTimer);
        previewTimer = setTimeout(runPreview, dragBase === null ? 0 : 40);
      }
    }
  }

  // ---- scenes ------------------------------------------------------------------------------
  let sceneListRequest = 0;
  async function loadList() {
    const request = ++sceneListRequest, scenes = await api("/api/scenes");
    if (request === sceneListRequest) state.scenes = scenes.filter(scene => !state.deletedSceneIds.has(scene.id));
  }
  let openRequest = 0, saving = null;
  function queueWrite(text, write) {
    // Each caller reports its own failure. Later writes still get their turn.
    const done = (saving ? saving.done.then(write, write) : write()).finally(() => {
      if (saving?.done === done) { saving = null; App.updateWorkspaceStatus?.(); }
    });
    saving = { text, done };
    App.updateWorkspaceStatus?.();
    return done;
  }
  async function openScene(sid) {
    const request = ++openRequest;
    cancelConfirmation?.();
    if (state.S && sid === state.id) {
      setSceneSection(sid);
      showHome(false);
      App.renderPanels?.();
      return;
    }
    let r;
    try { r = await api(`/api/scene/${sid}`); }
    catch (error) { if (request === openRequest) throw error; return; }
    // Decide whether to discard at the moment of leaving. The user can still edit
    // the current map while another scene is downloading or a save is pending.
    while (request === openRequest && saving) await saving.done.catch(() => {});
    if (request !== openRequest) return;
    if (state.dirty) {
      const choice = await confirmBox("Сохранить изменения?", `${sceneTitle(state.id)} → ${sceneTitle(sid)}`, "Сохранить и открыть", true);
      if (!choice || request !== openRequest) return;
      if (choice === true) {
        // The map stays available during the write. Its status and a retry are visible even
        // when this scene switch was initiated from the library.
        showHome(false, true);
        const saved = await save();
        if (!saved || request !== openRequest || state.dirty || state.virtual || saving) return;
      }
    }
    previewEpoch++;
    previewRevision++;
    previewPending = false;
    clearTimeout(previewTimer);
    previewTimer = null;
    dragBase = null;
    state.S = r.scene;
    state.S.markings = state.S.markings || [];
    state.S.lawns = state.S.lawns || [];
    state.id = sid;
    if (sid !== "mini_regulator") state.lastTicket = sid;
    setSceneSection(sid);
    // A traced scene has no road plan: one detected from its roads finds the lanes and ways of its cars.
    state.plan = null;
    if (!hasPlayerPlan(state.S) && sid !== "mini_regulator") api(`/api/layout/detect/${sid}`).then((d) => { if (state.id === sid) { state.plan = d.layout; App.renderInspector?.(); } }).catch(() => {});
    state.findings = r.findings;
    state.edges = r.edges;
    state.build = r.build;
    state.source = r.source;
    state.playable = r.playable;
    state.undo = [];
    state.redo = [];
    state.sel = [];
    state.virtual = r.virtual === true;
    state.savedJson = snapshotText();
    state.dirty = false;
    // Refresh generated views in memory; author paths and on-disk sources wait for Save.
    if (state.S.layout && (state.S.layout.streets?.some(st => st.kind === "highway") ||
        r.findings?.some(f => ["road-invalid","lawn-invalid"].includes(f.code) &&
          [...(state.S.roads || []),...(state.S.lawns || [])].some(item => item.auto && item.id === f.ref?.id)))) {
      Layout.apply(state.S);
    }
    if (hasPlayerPlan(state.S)) Layout.refreshPlayerRoutes(state.S);
    if (state.virtual) state.savedJson = snapshotText();
    if (snapshotText() !== state.savedJson) {
      state.undo.push(state.savedJson);
      state.dirty = true;
    }
    App.sceneOpened?.();
    Tools.set("select");
    Scene3D.load(state.S, state.dirty && !state.virtual ? null : r.build);
    showHome(false);
    history.replaceState(null, "", `?scene=${sid}`);
    renderTop();
    App.renderPanels?.();
    if (state.dirty && !state.virtual) {
      schedulePreview();
      toast("Автоматические пути обновлены. Сохраните, чтобы применить их в игре.", "good");
    }
    if (typeof Framing !== "undefined") Framing.refresh();
  }
  const sceneTitle = (sid) => {
    if (sid === "mini_regulator") return "Мини-игра «Регулировщик»";
    const m = String(sid || "").match(/^ticket_(cd_)?(\d+)_(\d+)$/);
    return m ? `Билет ${m[2]} · вопрос ${m[3]}${m[1] ? " · C/D" : ""}` : sid;
  };
  function setSceneSection(sid) {
    state.section = sid === "mini_regulator" ? "regulator" : "city";
    document.querySelectorAll("[data-editor-section]").forEach(b => {
      const on = b.dataset.editorSection === state.section;
      b.classList.toggle("on", on); b.setAttribute("aria-selected", String(on));
    });
  }

  function save() {
    if (state.deleting?.includes(state.id)) return false;
    // Textures are not part of a scene: they reach the game by their own "Применить в игре".
    if (!state.S || (!state.dirty && !state.virtual && !saving)) { toast("Всё сохранено"); renderTop(); return true; }
    const sid = state.id, text = snapshotText();
    if (saving?.text === text) return saving.done;
    const queued = !!saving;
    return queueWrite(text, () => saveSnapshot(sid, text, queued));
  }
  async function saveSnapshot(sid, text, queued) {
    try {
      const submitted = JSON.parse(text);
      if (queued) {
        // Publication may have changed ahead of this geometry save in the queue.
        const saved = JSON.parse(state.savedJson);
        for (const key of ["reviewed", "assistantReview", "questionPool"]) {
          if (key in saved) submitted[key] = saved[key]; else delete submitted[key];
        }
      }
      const r = await api(`/api/scene/${sid}`, submitted);
      if (state.id !== sid) return;
      if (r.assistantReview) {
        followAssistantApproval(r.assistantReview, r.reviewed, r.questionPool, submitted);
        state.playable = state.S.reviewed;
      }
      state.savedJson = JSON.stringify(submitted);
      state.dirty = snapshotText() !== state.savedJson;
      state.virtual = false;
      if (!state.dirty) state.findings = r.findings;
      const errors = r.findings.filter((f) => f.level === "error").length;
      const gone = r.removed && r.removed.length ? ` Удалено: ${r.removed.length}.` : "";
      toast(errors ? `Сохранено, но есть ошибки: ${errors}.${gone}` : `Сохранено.${gone}`, errors ? "warn" : "good");
      if (!state.dirty) saveThumb(sid);
      loadList().then(async () => { if (typeof QuestionPlan !== "undefined") await QuestionPlan.load({refresh:true}); App.renderPanels?.(); });
      return true;
    } catch (e) {
      toast(`Не сохранено: ${e.message}`, "bad");
      return false;
    } finally { renderTop(); }
  }
  // The card picture of the scene list: the view from above as it is now.
  function saveThumb(sid) {
    try {
      Scene3D.capture(360).toBlob((blob) => {
        if (blob) fetch(`/api/thumb/${sid}`, { method: "POST", body: blob }).then(r => { if (r.ok) thumbRev[sid] = Date.now(); }).catch(() => {});
      }, "image/png");
    } catch (e) { /* the picture is a nicety */ }
  }
  const thumbRev = {};

  async function deleteScene(sid) {
    if (state.deleting || !/^ticket_\d+_\d+$/.test(sid)) return false;
    const request = ++openRequest;
    state.deleting = [sid];
    cancelConfirmation?.();
    try {
      // A save already in progress finishes before we describe the files being
      // deleted. New writes to this question are blocked until deletion ends.
      while (saving) await saving.done.catch(() => {});
      if (request !== openRequest) return false;
      const info = await api(`/api/scene/${sid}/deletion`);
      if (request !== openRequest) return false;
      state.deleting = info.ids;
      renderTop();
      const copies = info.ids.filter(id => id !== sid);
      const text = `${sceneTitle(sid)}. ${info.hasScene ? "Сцена, её файлы и вопрос будут удалены из игры и списка." : "Вопрос будет удалён из игры и плана."}`
        + (copies.length ? ` Копии этого вопроса: ${copies.map(sceneTitle).join("; ")}.` : "")
        + (info.ids.includes(state.id) && state.dirty ? " Несохранённые изменения этой сцены тоже будут удалены." : "");
      if (!await confirmBox("Удалить вопрос?", text, "Удалить") || request !== openRequest) return false;
      const result = await queueWrite(null, () => api(`/api/scene/${sid}/delete`, {revision:info.revision}));
      const removed = new Set(result.ids);
      sceneListRequest++;
      removed.forEach(id => state.deletedSceneIds.add(id));
      state.scenes = state.scenes.filter(scene => !removed.has(scene.id));
      state.questions = state.questions.filter(question => !removed.has(question.id));
      if (removed.has(state.lastTicket)) state.lastTicket = null;
      if (removed.has(state.id)) {
        previewEpoch++; previewRevision++; previewPending = false;
        clearTimeout(previewTimer); previewTimer = null; dragBase = null;
        Tools.set("select");
        Object.assign(state, {S:null, id:null, build:null, plan:null, source:null, edges:null,
          sel:[], undo:[], redo:[], findings:[], savedJson:"", dirty:false, virtual:false, playable:false});
        App.selectionChanged?.();
        showHome(true, true);
        history.replaceState(null, "", App.sceneFilter?.() === "questions" ? "?filter=questions" : "/");
      }
      renderTop(); App.renderPanels?.(); App.renderHome?.();
      toast("Вопрос удалён", "good");
      // Refresh counts independently of the completed deletion. A temporary
      // list failure must not leave a deleted document open or invite a retry.
      loadList().then(async () => {
        if (typeof QuestionPlan !== "undefined") await QuestionPlan.load({refresh:true});
        App.renderPanels?.(); App.renderHome?.();
      }).catch(() => {});
      return true;
    } catch (error) {
      toast(`Не удалено: ${error.message}`, "bad");
      return false;
    } finally { state.deleting = null; renderTop(); }
  }

  async function setPlayable(on) {
    if (!state.S || state.including || state.deleting?.includes(state.id)) return;
    const sid = state.id, request = openRequest;
    state.including = true;
    try {
      if (state.dirty || state.virtual || saving) { await save(); if (state.dirty || state.virtual) return; }
      if (state.id !== sid || openRequest !== request) return;
      await queueWrite(null, async () => {
        const saved = JSON.parse(state.savedJson);
        const r = await api(`/api/game/include/${sid}`, { playable: on });
        state.playable = r.playable;
        state.S.reviewed = saved.reviewed = on;
        if (r.assistantReview) followAssistantApproval(r.assistantReview, on, on ? null : state.S.questionPool, saved);
        if (on) { delete state.S.questionPool; delete saved.questionPool; }
        state.savedJson = JSON.stringify(saved);
        state.dirty = snapshotText() !== state.savedJson;
        toast(on ? `Сцена в игре. Всего в игре: ${r.count}` : "Сцена убрана из игры", "good");
      });
      loadList().then(async () => { if (typeof QuestionPlan !== "undefined") await QuestionPlan.load({refresh:true}); App.renderPanels?.(); });
    } catch (e) {
      toast(e.message, "bad");
    } finally {
      state.including = false;
      App.renderInspector?.();
    }
    renderTop();
  }

  async function runInGame(auto = false) {
    if (!state.S || state.deleting?.includes(state.id)) return;
    const sid = state.id, request = openRequest;
    if (state.dirty || state.virtual || saving) { await save(); if (state.dirty || state.virtual) return; }
    if (request !== openRequest || state.id !== sid) return;
    try {
      toast("Готовлю перекрёсток для игры…");
      const r = await api(`/api/game/run/${sid}`, { auto });
      toast(r.launched ? "Игра открывается в отдельном окне на этом перекрёстке" : r.error, r.launched ? "good" : "bad");
    } catch (e) {
      toast(e.message, "bad");
    }
  }

  // ---- selection ------------------------------------------------------------------------------
  function select(list, opts = {}) {
    const arr = (Array.isArray(list) ? list : list ? [list] : []).filter((r) => r && (objectOf(r) || r.t === "stop"));
    state.sel = opts.add ? uniq([...state.sel, ...arr]) : arr;
    lastMergedEdit = null;
    if (state.sel.length) state.texSel = null;   // the inspector shows what was picked, not the texture
    Scene3D.setSelection(state.sel);
    App.selectionChanged?.();
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
    if (!kinds.size || kinds.has("pocket")) (s.pockets || []).forEach(p => all.push({t:"pocket",id:p.id}));
    if (!kinds.size || kinds.has("street")) (s.layout?.streets || []).forEach(st => all.push({t:"street",id:st.id}));
    if (!kinds.size || kinds.has("road")) s.roads.filter(r => !isGeneratedSurface(r)).forEach(r => all.push({t:"road",id:r.id,part:-1}));
    if (!kinds.size || kinds.has("sign")) (s.signs || []).forEach(o => all.push({t:"sign",id:o.id}));
    if (!kinds.size || kinds.has("officer")) (s.officers || []).forEach(o => all.push({t:"officer",id:o.id}));
    if (!kinds.size || kinds.has("decor")) s.decor.forEach((d) => all.push({ t: "decor", id: d.id }));
    if (!kinds.size || kinds.has("actor")) s.actors.forEach((a) => all.push({ t: "actor", id: a.id }));
    if (!kinds.size || kinds.has("light")) s.lights.forEach((l) => all.push({ t: "light", id: l.id }));
    select(all.filter(pickable));
  }

  // ---- moving, turning, copying, deleting ------------------------------------------------------
  const movable = (ref) => ["pocket", "decor", "track", "sign", "actor", "officer", "light", "marking", "lawn", "road", "route", "stop", "node", "street"].includes(ref.t);
  function moveRef(s, ref, dx, dz) {
    const o = objectOf(ref);
    if (!o) return;
    const shift = (p) => { p[0] = r3(p[0] + dx); p[1] = r3(p[1] + dz); };
    if (ref.t === "pocket" || ref.t === "decor" || ref.t === "actor" || ref.t === "light" || ref.t === "officer" || ref.t === "sign") {
      o.pos = [r3(o.pos[0] + dx), r3(o.pos[1] + dz)];
      if (ref.t === "actor") {
        const rid = o.route || `actor_${o.id}`;
        const r = s.routes.find((x) => x.id === rid);
        if (r && (!o.way || r.manual)) r.points.forEach(shift);
      }
    } else if (ref.t === "stop") {
      if (Layout.isFreePlayer(s)) return Layout.movePlayer(s, [s.stop.x + dx, s.stop.z + dz]);
      if (hasPlayerPlan(s)) return;
      s.stop.x = r3(s.stop.x + dx); s.stop.z = r3(s.stop.z + dz);
      const ap = s.routes.find((r) => r.id === "approach");
      if (ap && ap.points) ap.points.forEach(shift);
      for (const guide of s.routes.filter(r => r.kind === "guide")) guide.points.forEach(shift);
      if (s.id === "mini_regulator") for (const r of s.routes.filter(r => r.kind === "manoeuvre")) r.points[0] = [s.stop.x, s.stop.z];
    } else if (ref.t === "node") {
      Layout.moveNode(s, ref.id, [o.x + dx, o.z + dz]);
    } else if (ref.t === "street") {
      Layout.moveNodes(s, [o.a, o.b], [dx, dz]);
    } else if (ref.t === "route") {
      if (o.auto) return;
      if (s.id === "mini_regulator" && ["approach", "manoeuvre"].includes(o.kind)) return;
      Layout.editPlayerRoute(s, o);
      o.points.forEach((p, i) => { if (o.kind !== "guide" || i > 0) shift(p); });
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
    const list = state.sel.filter(r => !isLocked(r) && movable(r));
    if (!list.length) return;
    edit((s) => {
      const nodes = new Set();
      for (const ref of list) {
        if (ref.t === "node") nodes.add(ref.id);
        if (ref.t === "street") {
          const st = Layout.streetOf(s.layout, ref.id);
          if (st) { nodes.add(st.a); nodes.add(st.b); }
        }
      }
      const delta = nodes.size ? Layout.moveNodes(s, [...nodes], [dx, dz]) : [dx, dz];
      list.filter(r => !["node", "street"].includes(r.t)).forEach(r => moveRef(s, r, ...delta));
    }, {merge:"nudge:" + list.map(r => `${r.t}:${r.id}`).sort().join("|"), rebuild:!list.every(isNativeShape)});
  }
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

  // A complete inserted location keeps its parts aligned when rotated or copied.
  // Selecting only some of its parts retains ordinary independent object editing.
  const PRESET_LISTS = [["decor","decor"],["roads","road"],["markings","marking"]];
  function completePresetGroups(refs) {
    const selected = new Set(refs.filter(r => !(r.t === "road" && r.part >= 0)).map(r => `${r.t}:${r.id}`));
    const groups = new Map();
    for (const [key,t] of PRESET_LISTS) for (const o of state.S?.[key] || []) {
      if (!o.presetInstance) continue;
      if (!groups.has(o.presetInstance)) groups.set(o.presetInstance,[]);
      groups.get(o.presetInstance).push({t,id:o.id,o});
    }
    return [...groups].filter(([,members]) => members.length > 1 && members.every(r => selected.has(`${r.t}:${r.id}`)))
      .map(([id,members]) => ({id,members}));
  }
  function presetCoordinates(o) {
    return [...(o.pos ? [o.pos] : []), ...(o.points || []), ...(o.outer || []), ...(o.holes || []).flat(),
      ...(o.polygons || []).flatMap(p => [...p.outer,...(p.holes || []).flat()])];
  }
  function rotatePreset(group, angle) {
    const points = group.members.flatMap(({o}) => presetCoordinates(o));
    if (!points.length) return;
    const [cx,cz] = [0,1].map(axis => (Math.min(...points.map(p => p[axis])) + Math.max(...points.map(p => p[axis]))) / 2);
    const c = Math.cos(angle), n = Math.sin(angle);
    for (const p of points) {
      const x = p[0]-cx, z = p[1]-cz;
      p[0] = r3(cx+x*c-z*n); p[1] = r3(cz+x*n+z*c);
    }
    for (const {o} of group.members) if (o.pos) o.yaw = r3(wrap((o.yaw || 0)-angle));
  }

  // Turns the selection by `deg` degrees: each object about itself; a shape about its middle.
  function canRotate(ref) {
    const o = objectOf(ref);
    if (!o || isLocked(ref)) return false;
    if (ref.t === "stop") return Layout.isFreePlayer(state.S);
    if (ref.t === "route") return o.kind === "annotation";
    if (ref.t === "street") return state.sel.length === 1;
    return ["pocket","decor","sign","actor","officer","light","marking","lawn","road"].includes(ref.t) && !isGeneratedSurface(o);
  }
  function rotate(deg) {
    const list = state.sel.filter(canRotate);
    if (!list.length) return;
    const a = (deg * Math.PI) / 180;
    if (list.length === 1 && list[0].t === "street") {
      const candidate = { ...state.S, layout: JSON.parse(JSON.stringify(state.S.layout)) };
      const st = Layout.streetOf(candidate.layout, list[0].id);
      const start = Layout.nodeOf(candidate.layout, st.a), end = Layout.nodeOf(candidate.layout, st.b);
      if (Layout.setStreetGeometry(candidate, st.id, {heading:Math.atan2(end.x-start.x, end.z-start.z)-a})) {
        edit(s => { s.layout = candidate.layout; }, {merge:`rotate:street:${st.id}`});
      }
      return;
    }
    const presets = completePresetGroups(list);
    const grouped = new Set(presets.flatMap(group => group.members.map(r => `${r.t}:${r.id}`)));
    edit((s) => {
      presets.forEach(group => rotatePreset(group,a));
      for (const ref of list) {
        if (grouped.has(`${ref.t}:${ref.id}`)) continue;
        const o = objectOf(ref);
        if (ref.t === "stop") { if (Layout.isFreePlayer(s)) Layout.rotatePlayer(s, (s.stop.yaw || 0) - a); continue; }
        if (ref.t === "route" && o.style === "text") { o.textAngle = ((o.textAngle || 0) + deg + 540) % 360 - 180; continue; }
        if (o.pos) { o.yaw = r3(wrap((o.yaw || 0) - a)); continue; }
        const rings = ref.t === "route" ? [o.points] : ref.t === "marking" ? (o.points ? [o.points] : o.polygons.flatMap((p) => [p.outer, ...(p.holes || [])]))
          : ref.t === "road" && ref.part >= 0 ? [o.holes[ref.part]] : [o.outer, ...(o.holes || [])];
        const all = rings.flat();
        const [cx, cz] = isNativeShape(ref) ? shapeCenter(ref) : [all.reduce((t, p) => t + p[0], 0) / all.length, all.reduce((t, p) => t + p[1], 0) / all.length];
        const c = Math.cos(a), n = Math.sin(a);
        rings.forEach((ring) => ring.forEach((p) => {
          const x = p[0] - cx, z = p[1] - cz;
          p[0] = r3(cx + x * c - z * n);
          p[1] = r3(cz + x * n + z * c);
        }));
      }
    }, {merge:"rotate", rebuild:!list.every(isNativeShape)});
  }
  const wrap = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a <= -Math.PI) a += 2 * Math.PI; return a; };

  function uniqueId(prefix, taken) {
    let n = 1;
    while (taken.includes(`${prefix}${n}`)) n++;
    return `${prefix}${n}`;
  }

  // Copies of things: props, participants (with their path), lights, markings, lawns.
  const COPYABLE = ["pocket", "decor", "sign", "actor", "officer", "light", "marking", "lawn"];
  function canCopy(ref) {
    const o = objectOf(ref);
    if (!o || isLocked(ref)) return false;
    if (ref.t === "road" && !(ref.part >= 0) && !isGeneratedSurface(o) && o.presetInstance)
      return completePresetGroups(state.sel.filter(r => !isLocked(r))).some(group => group.id === o.presetInstance);
    return COPYABLE.includes(ref.t) && !isGeneratedSurface(o) || ref.t === "route" && o.kind === "annotation";
  }
  function selectionCopies() {
    const refs = state.sel.filter(canCopy);
    const complete = new Set(completePresetGroups(refs).map(group => group.id));
    return refs.map(ref => {
      const o = objectOf(ref);
      const route = ref.t === "actor" && state.S.routes.find(r => r.id === (o.route || `actor_${o.id}`));
      return JSON.parse(JSON.stringify({t:ref.t, o, presetGroup:complete.has(o.presetInstance), route:route && (route.manual || !o.way) ? route : null}));
    });
  }
  function copy() {
    const copies = selectionCopies();
    if (!copies.length) return false;
    state.clipboard = copies;
    toast(`Скопировано: ${copies.length}`);
    return true;
  }
  function insertCopies(copies, offset) {
    if (!copies?.length || copies.some(isLocked)) return false;
    select(edit(s => {
      const used = PRESET_LISTS.flatMap(([key]) => (s[key] || []).map(o => o.presetInstance).filter(Boolean));
      const instances = new Map();
      for (const c of copies) if (c.presetGroup && c.o.presetInstance && !instances.has(c.o.presetInstance)) {
        const id = uniqueId("preset_",used); used.push(id); instances.set(c.o.presetInstance,id);
      }
      return copies.map(c => pasteOne(s,c,offset,c.presetGroup ? instances.get(c.o.presetInstance) : null));
    }));
    return true;
  }
  function paste(offset = 4) { return insertCopies(state.clipboard, offset); }
  function pasteOne(s, c, offset, presetInstance = null) {
    const o = JSON.parse(JSON.stringify(c.o));
    if (presetInstance) o.presetInstance = presetInstance;
    else delete o.presetInstance;
    const listKey = { road:"roads", pocket: "pockets", decor: "decor", sign: "signs", actor: "actors", officer: "officers", light: "lights", marking: "markings", lawn: "lawns", route: "routes" }[c.t];
    const prefix = c.t === "actor" ? `${o.type}_` : { road:"road_", pocket: "pocket_", decor: "decor_", sign: "sign_", officer: "officer_", light: "light_", marking: "mark_", lawn: "lawn_", route: "annotation_" }[c.t];
    s[listKey] = s[listKey] || [];
    const taken = s[listKey].map(x => x.id);
    if (c.t === "actor") {
      for (const r of s.routes) if (r.id.startsWith("actor_")) taken.push(r.id.slice(6));
    }
    o.id = uniqueId(prefix, taken);
    delete o.auto;
    delete o.planGenerated;
    const ref = { t: c.t, id: o.id };
    s[listKey].push(o);
    if (c.t === "actor") {
      // Detach the clone from the original path before moveRef shifts its points.
      o.route = null;
      if (c.route) {
        const r = { ...JSON.parse(JSON.stringify(c.route)), id: `actor_${o.id}` };
        delete r.auto;
        s.routes.push(r);
        o.route = r.id;
      }
    }
    moveRef(s, ref, offset, -offset);
    return ref;
  }
  function duplicate(offset = 3) { return insertCopies(selectionCopies(), offset); }

  // The blue arrow is a question visual, independent of its driving route and
  // the editor's local layer visibility. Hide/show is an ordinary undoable edit.
  function selectPlayerPath() {
    if (!state.S || state.S.id === "mini_regulator" || state.locked.has("routes")) return;
    let route = state.S.routes.find(r => r.kind === "guide");
    if (!route) {
      edit(sc => Layout.resetPlayerGuide(sc), {rebuild:false});
      route = state.S.routes.find(r => r.kind === "guide");
    }
    if (route) select({t:"route", id:route.id, v:route.points.length - 1});
  }

  function resetPlayerGuide() {
    if (!state.S || state.S.id === "mini_regulator" || state.locked.has("routes")) return;
    edit(sc => Layout.resetPlayerGuide(sc), {rebuild:false});
    selectPlayerPath();
  }

  function setPlayerGuideVisible(visible) {
    if (!state.S || state.S.id === "mini_regulator" || state.id === "mini_regulator" || state.locked.has("routes")) return;
    select(state.sel.map(ref => {
      if (ref.t !== "route" || !["manoeuvre", "guide"].includes(objectOf(ref)?.kind)) return ref;
      const {v, point, ...route} = ref;
      return route;
    }));
    edit(sc => {
      sc.question = sc.question || {};
      if (visible) {
        delete sc.question.showPlayerGuide;
        if (!sc.routes.some(r => r.kind === "guide")) Layout.resetPlayerGuide(sc);
      }
      else sc.question.showPlayerGuide = false;
    }, {rebuild:false});
    // Manoeuvres are drawn in the editor only while selected. Make restoring
    // the guide visible immediately, including from the scene/player cards.
    if (visible) selectPlayerPath();
  }

  function canRemoveObject(ref) {
    const o = objectOf(ref);
    return o && !isLocked(ref) && ref.t !== "stop" &&
      !(ref.t === "route" && (o.auto || ["approach","manoeuvre","guide"].includes(o.kind))) &&
      !(["marking","road","lawn"].includes(ref.t) && isGeneratedSurface(o));
  }
  async function remove() {
    const list = state.sel.filter(r => !isLocked(r));
    if (!list.length) return;
    // A point of a shape or route, when one is picked.
    if (list.length === 1 && list[0].v !== undefined) {
      const ref = list[0], pts = pointsOfRef(ref);
      const least = ref.t === "route" || (ref.t === "marking") ? 2 : 3;
      if (!pts || pts.length <= least) return toast("Меньше точек нельзя", "warn");
      const o = objectOf(ref);
      if (ref.t === "route" && ["manoeuvre", "guide"].includes(o?.kind) && ref.v === 0) return toast("Эта точка закреплена у автомобиля игрока", "warn");
      if (ref.t === "route" && state.S.id === "mini_regulator" && ((o?.kind === "manoeuvre" && ref.v === 0) || (o?.kind === "approach" && ref.v === pts.length - 1))) return toast("Эта точка закреплена у автомобиля игрока", "warn");
      if (ref.t === "route" && o?.kind === "approach" && hasPlayerPlan(state.S) && (!o.manual || ref.v === 0 || ref.v === pts.length - 1)) return toast("Начало подъезда закреплено у въезда, конец — у игрока", "warn");
      edit(() => {
        if (ref.t === "route" && o) {
          Layout.editPlayerRoute(state.S, o);
        }
        pts.splice(ref.v, 1);
      }, {rebuild:!isNativeShape(ref)});
      return select({ ...ref, v: undefined });
    }
    const hidesPlayerGuide = state.S.id !== "mini_regulator" && list.some(r => r.t === "route" && ["manoeuvre", "guide"].includes(objectOf(r)?.kind));
    const removable = list.filter(canRemoveObject);
    if (!removable.length && hidesPlayerGuide) return setPlayerGuideVisible(false);
    if (!removable.length) return toast("Это строится само по дорогам", "warn");
    if (hidesPlayerGuide) select([]);
    edit((s) => {
      if (hidesPlayerGuide) { s.question = s.question || {}; s.question.showPlayerGuide = false; }
      for (const ref of removable) {
        if (ref.t === "street") { Layout.removeStreet(s, ref.id); continue; }
        if (ref.t === "node") { Layout.removeNode(s, ref.id); continue; }
        if (ref.t === "road" && ref.part >= 0) { objectOf(ref)?.holes.splice(ref.part, 1); continue; }
        const key = { pocket: "pockets", decor: "decor", track: "tracks", sign: "signs", actor: "actors", officer: "officers", light: "lights", route: "routes", marking: "markings", lawn: "lawns", road: "roads" }[ref.t];
        const o = objectOf(ref);
        if (!o) continue;
        s[key] = s[key].filter((x) => x !== o);
        if (ref.t === "actor") {
          if (o.route && !s.actors.some(a => a.route === o.route)) s.routes = s.routes.filter(r => r.id !== o.route);
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
    App.selectionChanged?.();
    Scene3D.setHidden(state.hidden);
    Scene3D.setSelection(state.sel);
    App.renderPanels?.();
  }
  function toggleLocked(layer) {
    state.locked.has(layer) ? state.locked.delete(layer) : state.locked.add(layer);
    state.sel = state.sel.filter(pickable);
    App.selectionChanged?.();
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
    $("#save").disabled = !!state.deleting?.includes(state.id) || (!state.dirty && !state.virtual && !App.hasPendingInspectorField?.());
    $("#save").classList.toggle("pulse", state.dirty || state.virtual);
    $("#undo").disabled = !state.undo.length;
    $("#redo").disabled = !state.redo.length;
    $("#play").disabled = !s;
    App.updateWorkspaceStatus?.();
    document.title = s ? `${state.dirty ? "• " : ""}${sceneTitle(state.id)} — Редактор сцен` : "Редактор сцен";
  }
  function plural(n, forms) {
    const m = n % 100, k = n % 10;
    if (m > 10 && m < 20) return forms[2];
    if (k === 1) return forms[0];
    if (k > 1 && k < 5) return forms[1];
    return forms[2];
  }

  function showHome(on, keepRequest = false) {
    if (!keepRequest) { ++openRequest; cancelConfirmation?.(); }
    $("#home-screen").hidden = !on;
    $("#app").classList.toggle("at-home", on);
    if (on) App.renderHome?.();
    else if (state.id) setSceneSection(state.id);
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
    if (typeof Framing !== "undefined" && Framing.on) return;
    const typing = e.target && (["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName) || e.target.isContentEditable);
    if (!$("#confirm").hidden) return;
    for (const modal of [$("#keys"), $("#lightbox")]) {
      if (!modal.hidden) {
        if (e.key === "Escape") { e.preventDefault(); modal.hidden = true; }
        return;
      }
    }
    if (!$("#home-screen").hidden && e.key === "Escape" && state.S && !typing) { showHome(false); return; }
    if (e.key === "Enter" && e.target?.closest?.("button, summary")) return;
    for (const k of KEYS) {
      if (!matches(e, k.combo)) continue;
      if (typing && !k.always) return;
      if (k.needScene && (!state.S || !$("#home-screen").hidden)) return;
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
    const saveEditor = e => {
      if (e.isComposing || App.commitInspectorField?.() === false) return;
      return save();
    };
    $("#save").onclick = saveEditor;
    // Keep a typed value focused until the click can validate and commit it.
    $("#save").onpointerdown = e => { if (e.button === 0 && App.hasPendingInspectorField?.()) e.preventDefault(); };
    key(G1, "mod+s", "Сохранить", saveEditor, { always: true, needScene: true });
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
    key(G2, "q", "Повернуть на −15°", () => { if (!Tools.rotateBrush?.(-15)) rotate(-15); }, { needScene: true, show: ["q", "e"] });
    key(G2, "e", "Повернуть на +15°", () => { if (!Tools.rotateBrush?.(15)) rotate(15); }, { needScene: true, hiddenInHelp: true });
    key(G2, "arrowleft", "Сдвинуть на 10 см (⇧ — на 1 м)", () => nudgeScreen(-1, 0, 0.1), { needScene: true, show: ["arrowleft", "arrowright", "arrowup", "arrowdown"] });
    key(G2, "arrowright", "", () => nudgeScreen(1, 0, 0.1), { needScene: true, hiddenInHelp: true });
    key(G2, "arrowup", "", () => nudgeScreen(0, 1, 0.1), { needScene: true, hiddenInHelp: true });
    key(G2, "arrowdown", "", () => nudgeScreen(0, -1, 0.1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowleft", "", () => nudgeScreen(-1, 0, 1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowright", "", () => nudgeScreen(1, 0, 1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowup", "", () => nudgeScreen(0, 1, 1), { needScene: true, hiddenInHelp: true });
    key(G2, "shift+arrowdown", "", () => nudgeScreen(0, -1, 1), { needScene: true, hiddenInHelp: true });
    key(G3, "i", "Линия (в инструменте Ответы)", () => Tools.set("annotation"), { needScene: true });
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
    try {
      Scene3D.mount($("#view"));
    } catch (e) {
      startupError("Не удалось открыть 3D-вид", e);
      return;
    }
    Tools.init();
    bindKeys();
    $("#undo").onclick = undo;
    $("#redo").onclick = redo;
    $("#play").onclick = () => runInGame(false);
    $("#help").onclick = () => { renderKeys(); $("#keys").hidden = false; };
    $("#keys").addEventListener("click", (e) => { if (e.target.id === "keys" || e.target.closest("[data-close]")) $("#keys").hidden = true; });
    $("#home").onclick = () => { if ($("#home-screen").hidden) showHome(true); };
    document.querySelectorAll("[data-editor-section]").forEach(b => b.onclick = async () => {
      if (b.dataset.editorSection === "city" && !$("#home-screen").hidden) {
        setSceneSection(null);
        showHome(true);
        return;
      }
      const sid = b.dataset.editorSection === "regulator" ? "mini_regulator" : state.lastTicket || state.scenes.find(s => s.id !== "mini_regulator")?.id;
      if (sid) await openScene(sid).catch(e => toast(e.message, "bad"));
    });
    $("#status").onclick = () => { App.showInspector?.(); App.showChecks?.(); };
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
      [state.catalog] = await Promise.all([api("/api/catalog"), Textures.load(), loadList(), DirectionMark.load()]);
      Catalog.setSignCatalog(state.catalog.signInfo);
      Catalog.setPropCatalog?.(state.catalog.props);
    } catch (e) {
      startupError("Не удалось загрузить сцены", e);
      return;
    }
    Scene3D.setTextures(Textures.forScene());
    if (typeof QuestionPlan !== "undefined") await QuestionPlan.load().catch(() => {});
    App.renderPanels?.();
    renderTop();
    const params = new URLSearchParams(location.search);
    const first = params.get("scene");
    if (first) await openScene(first).catch((e) => { toast(e.message, "bad"); showHome(true); });
    else if (params.get("filter") === "questions" && typeof QuestionPlan !== "undefined") {
      await App.showQuestions?.(params.get("question") || undefined);
    } else showHome(true);
    $("#loading").hidden = true;
  }

  function startupError(message, error) {
    const loading = $("#loading");
    loading.innerHTML = `<b>${esc(message)}</b><small>${esc(error.message)}</small><button class="btn" id="retry-load">Повторить</button>`;
    $("#retry-load").onclick = () => location.reload();
  }

  return {
    state, planScene, hasPlayerPlan, api, toast, confirm: confirmBox, esc, ic, r3, objectOf, pointsOfRef, shapeCenter, isGeneratedSurface, isPaint, layerOf, catalogSize, sameRef, nameOf,
    edit, beginDrag, dragMove, endDrag, cancelDrag, undo, redo, changed, openScene, sceneTitle, save, deleteScene, setPlayable, runInGame,
    select, toggle, pickable, isLocked, moveRef, nudge, canRotate, canCopy, canRemoveObject, rotate, copy, paste, duplicate, remove, setPlayerGuideVisible, selectPlayerPath, resetPlayerGuide, uniqueId, toggleHidden, toggleLocked,
    renderTop, showHome, setView, plural, thumbRev, boot, loadList,
    get S() { return state.S; },
    get isSaving() { return !!saving; },
  };
})();
