// The right side: what the selection is and how it can be changed, with pictures and switches instead
// of number fields. Nothing selected: the scene itself (its question, what the player does, checks,
// whether it is in the game). A texture chosen on the left: the texture.
(() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, state, r3 } = App;
  const pane = () => $("#inspector");

  // ---- small builders -----------------------------------------------------------------------
  const card = (title, body, opts = {}) => `<section class="card ${opts.cls || ""}">${title ? `<h3>${opts.icon ? ic(opts.icon) : ""}${title}${opts.aside || ""}</h3>` : ""}${body}</section>`;
  const propertyRow = (label, controls) => `<div class="property-row" role="group" aria-label="${esc(label)}"><span class="property-label">${esc(label)}</span><div class="property-control">${controls}</div></div>`;
  const chips = (name, items, value, opts = {}) => `<div class="seg-chips ${opts.cls || ""}">${items.map((it) =>
    `<button class="${String(it.value) === String(value) ? "on" : ""} ${it.disabled ? "off" : ""}" data-chip="${name}" data-value="${esc(it.value)}" aria-label="${esc(it.tip || it.title || it.value)}" aria-pressed="${String(it.value) === String(value)}" ${it.disabled ? "disabled" : ""} ${it.tip ? `data-tip="${esc(it.tip)}"` : ""}>${it.icon ? ic(it.icon) : ""}${it.html || ""}${it.title ? `<span>${esc(it.title)}</span>` : ""}</button>`).join("")}</div>`;
  const toggle = (name, label, on, icon) => `<label class="switch-row">${icon ? ic(icon) : ""}<span>${esc(label)}</span><input type="checkbox" data-toggle="${name}" ${on ? "checked" : ""}><i class="switch"></i></label>`;
  const button = (act, label, icon, cls = "") => `<button class="btn ${cls}" data-act="${act}">${icon ? ic(icon) : ""}<span>${esc(label)}</span></button>`;
  const slider = (name, label, value, min, max, step, shown) => `<div class="slider-row"><div class="slider-h"><span>${esc(label)}</span><em data-shown="${name}">${esc(shown)}</em></div>
    <input type="range" aria-label="${esc(label)}" min="${min}" max="${max}" step="${step}" value="${value}" data-slider="${name}"></div>`;
  const stopStyles = [{ value: "solid", title: "Сплошная", icon: "stopline" }, { value: "yield", title: "Треугольники", icon: "yieldline" }];
  const setStopStyle = (item, value) => {
    if (value === "yield") item.stopStyle = "yield";
    else delete item.stopStyle;
  };

  let handlers = {};
  const selectionLocked = () => state.sel.length === 1 && App.isLocked(state.sel[0])
    && !(state.texSel && state.ltab === "textures");
  let compositionField = null;
  pane().addEventListener("compositionstart", e => { compositionField = e.target; });
  pane().addEventListener("compositionend", () => { compositionField = null; });
  App.hasPendingInspectorField = () => {
    const field = document.activeElement;
    return !!field?.matches?.("#inspector input[data-text]:enabled") && !selectionLocked()
      && (field.value !== field.defaultValue || field.validity.badInput);
  };
  App.commitInspectorField = () => {
    const field = document.activeElement;
    if (field && field === compositionField) return false;
    if (!App.hasPendingInspectorField()) return true;
    if (!field.reportValidity()) return false;
    const handler = handlers["text:" + field.dataset.text];
    if (!handler || handler(field.value) === false) return false;
    // A normalized no-op (for example, whitespace after an existing name) causes no rerender.
    if (field.isConnected && field.value.trim() === field.defaultValue) field.value = field.defaultValue;
    return true;
  };
  function bind(h) {
    handlers = h;
  }
  pane().addEventListener("click", (e) => {
    if (selectionLocked()) return;
    const c = e.target.closest("[data-chip]");
    if (c?.disabled) return;
    if (c && handlers["chip:" + c.dataset.chip]) return handlers["chip:" + c.dataset.chip](c.dataset.value, e);
    const a = e.target.closest("[data-act]");
    if (a && handlers[a.dataset.act]) return handlers[a.dataset.act](a.dataset, e);
  });
  pane().addEventListener("change", (e) => {
    if (selectionLocked()) return;
    const t = e.target.closest("[data-toggle]");
    if (t && handlers["toggle:" + t.dataset.toggle]) return handlers["toggle:" + t.dataset.toggle](t.checked);
    const sl = e.target.closest("[data-slider]");
    if (sl && handlers["slider:" + sl.dataset.slider]) return handlers["slider:" + sl.dataset.slider](Number(sl.value), true);
    const tx = e.target.closest("[data-text]");
    if (tx && handlers["text:" + tx.dataset.text]) return handlers["text:" + tx.dataset.text](tx.value);
  });
  pane().addEventListener("input", (e) => {
    if (selectionLocked()) return;
    if (e.target.closest("input[data-text]")) App.renderTop();
    const search = e.target.closest("[data-sign-search]");
    if (search) {
      handlers.searchSigns?.(search.value);
      return;
    }
    const sl = e.target.closest("[data-slider]");
    if (sl && handlers["slider:" + sl.dataset.slider]) handlers["slider:" + sl.dataset.slider](Number(sl.value), false);
  });

  // Live slider: the first move opens one undo step, the release closes it.
  function live(fn, show) {
    return (v, done) => {
      if (!live.open) { App.beginDrag(); live.open = true; }
      App.dragMove((s) => fn(s, v));
      if (show) show(v);
      if (done) { live.open = false; App.endDrag(); }
    };
  }

  // ---- dispatch ---------------------------------------------------------------------------
  let lastSelection = "";
  App.renderInspector = () => {
    const p = pane(), selection = JSON.stringify([state.id, state.ltab === "textures" && state.texSel, state.sel.map(r => [r.t, r.id])]);
    const same = lastSelection === selection;
    const scroll = same ? p.scrollTop : 0;
    const active = document.activeElement;
    if (same && active && active === compositionField) return;
    // Keep keyboard focus on the same field when an edit rebuilds the inspector.
    const focus = same && active && p.contains(active)
      ? Array.from(active.attributes).filter(a => a.name.startsWith("data-")) : [];
    const draft = focus.length && active.matches('input[type="text"], input[type="search"], input[type="number"]')
      ? {value:active.value, initial:active.defaultValue, start:active.selectionStart, end:active.selectionEnd} : null;
    lastSelection = selection;
    render(p);
    if (selectionLocked()) {
      p.querySelectorAll("button, input, select").forEach(field => { field.disabled = true; });
    }
    if (focus.length) {
      const selector = focus.map(a => `[${a.name}="${CSS.escape(a.value)}"]`).join("");
      const field = p.querySelector(selector);
      field?.focus({preventScroll:true});
      // A preview response can arrive while the author is still typing a name or a caption.
      if (field && draft && field.defaultValue === draft.initial) {
        field.value = draft.value;
        if (draft.start !== null) field.setSelectionRange(draft.start, draft.end);
      }
    }
    p.scrollTop = scroll;
  };
  function render(p) {
    if (state.ltab === "textures" && state.texSel) return textureInspector(p);
    if (!state.S) { p.innerHTML = `<div class="empty-pane">${ic("map")}<p>Откройте сцену</p></div>`; bind({}); return; }
    const sel = state.sel;
    if (!sel.length) return sceneInspector(p);
    if (sel.length > 1) return multiInspector(p);
    const ref = sel[0], o = App.objectOf(ref);
    if (!o && ref.t !== "stop") return sceneInspector(p);
    const view = { decor: decorInspector, actor: actorInspector, officer: officerInspector, sign: signInspector, track: trackInspector, light: lightInspector, street: streetInspector, node: nodeInspector,
      route: routeInspector, marking: markingInspector, lawn: shapeInspector, road: shapeInspector, stop: stopInspector }[ref.t];
    view(p, ref, o);
    Thumbs.fillAll(p);
  }
  App.renderSelection = () => {};
  App.showChecks = () => {
    state.texSel = null;
    App.select([]);
    $("#checks")?.scrollIntoView({block:"nearest"});
  };

  const head = (icon, title, sub = "") => `<div class="insp-head">${icon}<div><h2>${esc(title)}</h2>${selectionLocked()
    ? `<small class="insp-lock">${ic("lock")}Слой заблокирован</small>`
    : sub ? `<small>${esc(sub)}</small>` : ""}</div></div>`;
  const deleteRow = (extra = "") => `<div class="insp-actions">${extra}${button("dup", "Копия", "copy", "ghost")}${button("del", "Удалить", "trash", "danger ghost")}</div>`;
  const common = { dup: () => App.duplicate(), del: () => App.remove() };

  function playerGuideCard(question, editing = false) {
    const hidden = question?.showPlayerGuide === false;
    const label = editing ? "Показывать" : "Стрелка игрока";
    return card("", `<div class="path-property"><span>${label}</span>
      <button class="path-visibility" data-act="player-guide" aria-label="Показывать стрелку игрока" aria-pressed="${!hidden}">${ic(hidden ? "eye-off" : "eye")}${hidden ? "Скрыта" : "Видна"}</button></div>
      ${hidden ? "" : `<div class="path-actions">${button("player-path", editing ? "К концу" : "Править форму", "points", "ghost")}${button("player-guide-short", "Сбросить до 8 м", "restart", "ghost")}</div>`}`, {cls:"path-sheet"});
  }
  const togglePlayerGuide = () => App.setPlayerGuideVisible(state.S.question?.showPlayerGuide === false);
  const playerGuideHandlers = {"player-guide": togglePlayerGuide, "player-path": () => App.selectPlayerPath(), "player-guide-short": () => App.resetPlayerGuide()};

  // ---- the scene ----------------------------------------------------------------------------
  function sceneChecks() {
    if (!state.findings.length) return `<p class="ok-line">${ic("check-circle")}Ошибок нет</p>`;
    return `<h3>Проверка <small>${state.findings.length}</small></h3>` + state.findings.map((f, i) =>
      `<button class="finding ${f.level}" data-act="finding" data-i="${i}">${ic(f.level === "error" ? "error" : "alert")}<span>${esc(f.message)}</span></button>`).join("");
  }

  function regulatorInspector(p) {
    const s = state.S;
    p.innerHTML = `${head(`<span class="ibadge">${ic("person")}</span>`, "Регулировщик")}
      ${card("", propertyRow("Участники", `<div class="insp-actions">${button("regulator-officer", "Регулировщик", "person", "ghost")}${button("regulator-player", "Игрок", "car", "ghost")}</div>`))}
      ${card("Маршруты", regulatorRouteButtons(s))}
      <section id="checks" class="card">${sceneChecks()}<div class="insp-actions">${button("regulator-run", "Тест в игре", "play", "ghost")}</div></section>`;
    bind({
      "regulator-run": () => App.runInGame(false),
      finding: d => focusFinding(state.findings[Number(d.i)]),
      "regulator-officer": () => s.officers[0] && App.select({t:"officer", id:s.officers[0].id}),
      "regulator-player": () => App.select({t:"stop"}),
      "regulator-route": d => App.select({t:"route",id:d.id}),
    });
  }

  function regulatorRouteButtons(s, selected) {
    return `<div class="regulator-routes">${s.routes.filter(r => ["approach", "manoeuvre"].includes(r.kind)).map(r => {
      const title = r.kind === "approach" ? "Подъезд" : Catalog.EXITS[r.exit].title;
      const icon = r.kind === "approach" ? "route" : Catalog.EXITS[r.exit].icon;
      return `<button class="btn ${r.id === selected ? "primary" : "ghost"}" aria-pressed="${r.id === selected}" data-act="regulator-route" data-id="${esc(r.id)}">${ic(icon)}<span>${esc(title)}</span></button>`;
    }).join("")}</div>`;
  }

  function regulatorRouteInspector(p, ref, r) {
    const index = Number.isInteger(ref.v) ? ref.v : 0;
    const point = r.points[index];
    const anchored = r.kind === "manoeuvre" ? index === 0 : index === r.points.length - 1;
    p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, "Путь игрока")}
      ${card("", regulatorRouteButtons(state.S, r.id), {cls:"path-sheet"})}
      ${pointEditor(r.points, index, anchored ? "У автомобиля" : "", false)}
      ${card("", button("regulator-run", "Тест в игре", "play", "ghost wide"))}`;
    bind({
      "regulator-route": d => App.select({t:"route", id:d.id}),
      "regulator-run": () => App.runInGame(false),
      "text:routeIndex": v => { const i = Number(v) - 1; if (Number.isInteger(i) && i >= 0 && i < r.points.length) App.select({t:"route", id:r.id, v:i}); },
      ...Object.fromEntries(["routeX", "routeZ"].map((key, axis) => [`text:${key}`, v => {
        if (anchored || !v.trim() || !Number.isFinite(Number(v))) return;
        App.edit(() => { Layout.editPlayerRoute(state.S, r); r.points[index][axis] = r3(Number(v)); });
      }])),
      "route-delete-point": () => { if (!anchored && r.points.length > 2) { App.select({t:"route", id:r.id, v:index}); App.remove(); } },
      "route-add-point": () => {
        App.edit(() => { Layout.editPlayerRoute(state.S, r); const next = r.points[index + 1]; r.points.splice(index + 1, 0, point.map((v, axis) => r3((v + next[axis]) / 2))); });
        App.select({t:"route", id:r.id, v:index + 1});
      },
    });
  }

  function sceneInspector(p) {
    if (state.id === "mini_regulator") return regulatorInspector(p);
    const s = state.S, q = s.question || {};
    const routes = s.routes.filter((r) => r.kind === "manoeuvre").map((r) => r.exit);
    const plan = s.layout ? Layout.playerPlan(s) : null;
    const lanes = plan && !Layout.isFreePlayer(s) ? (plan.lanes || Layout.laneOffsets(plan.st)) : [];
    const laneItems = lanes.length === 2
      ? [{ value: 0, title: "Левая" }, { value: 1, title: "Правая" }]
      : lanes.length === 3
        ? [{ value: 0, title: "Левая" }, { value: 1, title: "Средняя" }, { value: 2, title: "Правая" }]
        : lanes.map((_, i) => ({ value: i, title: i === 0 ? "1 (левая)" : i === lanes.length - 1 ? `${i + 1} (правая)` : `${i + 1}` }));
    const curLane = plan ? plan.laneIndex : 0;
    const yields = s.actors.map((a) => `<button class="pick ${(q.yieldTo || []).includes(a.id) ? "on" : ""}" data-act="yield" data-id="${esc(a.id)}" aria-pressed="${(q.yieldTo || []).includes(a.id)}">${Thumbs.img("actor", a.type, "mini")}<span>${esc(a.name || a.id)}</span></button>`).join("");
    const edges = state.edges || {};
    const edgeMismatch = Object.values(edges).some(e => e && !(e.connectable ?? e.street));
    const side = (k) => { const e = edges[k]; return e ? ((e.connectable ?? e.street) ? "ok" : "bad") : "none"; };
    const assistant = s.assistantReview?.author === "codex";
    const approved = assistant && s.assistantReview.status === "approved" && state.playable;
    const maneuver = chips("maneuver", ["left", "straight", "right", "uturn"].map(k => ({
      value:k, icon:Catalog.EXITS[k].icon, tip:Catalog.EXITS[k].title,
      disabled:k !== "straight" && !routes.includes(k) && !s.layout,
    })), q.maneuver, {cls:"arrows"});
    const speeds = [{value:"", title:"Нет"}, ...[20,40,60].map(v => ({value:v, tip:`${v} км/ч`, html:`<span class="speed-sign">${v}</span>`}))];
    const waits = [{value:"", title:"Нет"}, ...[2,5].map(v => ({value:v, title:`${v} с`}))];
    p.innerHTML = `
      ${head(`<span class="ibadge">${ic("map")}</span>`, "Сцена")}
      ${assistant ? card("Подготовлено Codex", `<p class="assistant-review-status">${approved ? "Одобрено вами · сцена в игре" : "Ожидает вашего одобрения"}</p>${button(approved ? "withdraw-approval" : "approve-scene", approved ? "Снять одобрение и убрать из игры" : "Одобрить и добавить в игру", approved ? "undo" : "check-circle", approved ? "ghost wide" : "primary wide")}`, {cls:"assistant-review-card"})
        : card("", toggle("playable", "В игре", state.playable, "gamepad"))}
      ${card("", propertyRow("Манёвр", maneuver)
        + (lanes.length > 1 ? propertyRow("Полоса", chips("lane", laneItems, curLane)) : "")
        + propertyRow("Ограничение", chips("speed", speeds, q.speedLimit ?? "", {cls:"signs"}))
        + (s.lights.some(light => light.state === "flashing_green")
          ? propertyRow("После ответа", `<span class="signal-sequence"><i class="signal-dot yellow"></i>Жёлтый ${ic("chevron")}<i class="signal-dot red"></i>Красный</span>`)
          : propertyRow("Пауза на красном", chips("redWait", waits, q.redWait ?? "")))
        + (s.actors.length ? propertyRow("Уступить", `<div class="yield-choices">${yields}</div>`) : ""), {cls:"property-fields"})}
      ${playerGuideCard(q)}
      ${card("", propertyRow("Кадр вопроса", button("frame", "Настроить", "video", "ghost"))
        + propertyRow("Дороги", `<div class="insp-actions">${s.layout
          ? button("select-roads", "Все дороги", "road", "ghost") + button("templates", "Шаблоны", "junction", "ghost")
          : button("convert", "В конструктор", "road", "ghost")}</div>`)
        + propertyRow("Выезды", `<div class="edges"><span class="edge-box" aria-hidden="true"><i class="e-n ${side("n")}"></i><i class="e-s ${side("s")}"></i><i class="e-e ${side("e")}"></i><i class="e-w ${side("w")}"></i>${ic("junction")}</span>
          <span class="${edgeMismatch ? "warn" : ""}">${edgeMismatch ? "Разная ширина" : Object.values(edges).filter(Boolean).length}</span></div>`), {cls:"property-fields"})}
      <section class="card" id="checks">${sceneChecks()}
        <div class="insp-actions">${button("run","Тест в игре","play","ghost")}${button("run-auto","Автопилот","car","ghost")}</div></section>`;
    Thumbs.fillAll(p);
    bind({
      ...selectionHandlers,
      "toggle:playable": (on) => App.setPlayable(on),
      "approve-scene": () => App.setPlayable(true),
      "withdraw-approval": () => App.setPlayable(false),
      ...playerGuideHandlers,
      run: () => App.runInGame(false),
      "run-auto": () => App.runInGame(true),
      "chip:maneuver": (v) => App.edit((sc) => { sc.question.maneuver = v; sc.spec = { ...(sc.spec || {}), maneuver: v }; }),
      "chip:lane": (v) => App.edit((sc) => {
        const pl = Layout.playerPlan(sc);
        sc.layout.player = {
          ...(sc.layout.player || {}),
          street: pl ? pl.st.id : sc.layout?.player?.street,
          toward: pl ? pl.nid : sc.layout?.player?.toward,
          lane: Number(v),
        };
      }),
      "chip:speed": (v) => App.edit((sc) => { if (v === "") delete sc.question.speedLimit; else sc.question.speedLimit = Number(v); }),
      "chip:redWait": (v) => App.edit((sc) => { if(sc.lights.some(light=>light.state === "flashing_green"))return; if (v === "") delete sc.question.redWait; else sc.question.redWait = Number(v); }),
      yield: (d) => App.edit((sc) => {
        const set = new Set(sc.question.yieldTo || []);
        set.has(d.id) ? set.delete(d.id) : set.add(d.id);
        sc.question.yieldTo = [...set];
      }),
      templates: () => Tools.set("junction"),
      frame: () => Framing.start(),
      photo: () => Framing.openPhoto(),
      pin: () => Framing.pin(true),
      convert: () => Tools.convertScene(),
      finding: (d) => focusFinding(state.findings[Number(d.i)]),
    });
  }

  function focusFinding(f) {
    const ref = f && f.ref;
    if (!ref) return;
    const s = state.S;
    let r = null;
    if (ref.type === "route") r = { t: "route", id: ref.id };
    else if (ref.type === "road") r = { t: "road", id: ref.id, part: -1 };
    else if (ref.type === "lawn") r = { t: "lawn", id: ref.id };
    else if (ref.type === "marking") r = { t: "marking", id: ref.id };
    else if (ref.type === "actor") r = { t: "actor", id: ref.id };
    else if (ref.type === "light") r = { t: "light", id: ref.id };
    else if (ref.type === "prop" && ref.id) r = { t: "decor", id: ref.id };
    else if (ref.type === "stop") r = { t: "stop" };
    if (r && r.t === "road" && s.roads.find((x) => x.id === r.id)?.auto) {
      const st = s.layout?.streets.find((x) => `road_${x.id}` === r.id);
      r = st ? { t: "street", id: st.id } : null;
    }
    if (!r) return;
    App.select(r);
    Tools.fitSelection();
  }

  // ---- selection and shared settings -----------------------------------------------------------
  const editableRefs = refs => refs.filter(ref => App.objectOf(ref) && !App.isLocked(ref));
  const selectedOf = (refs, type) => editableRefs(refs).filter(ref => ref.t === type).map(App.objectOf);
  const shared = (objects, get) => {
    if (!objects.length) return undefined;
    const first = get(objects[0]);
    return objects.every(object => Object.is(get(object), first)) ? first : undefined;
  };
  const mixedBadge = mixed => mixed ? '<span class="mixed-badge">Разные</span>' : "";
  const fieldTitle = (title, value) => `<div class="setting-title"><span>${esc(title)}</span>${mixedBadge(value === undefined)}</div>`;
  const selectionActions = () => `<div class="selection-actions">${button("select-roads", "Все дороги", "road", "ghost small")}${button("clear-selection", "Снять выбор", "x", "ghost small")}</div>`;
  const selectionHandlers = {
    "select-roads": () => App.select((state.S.layout?.streets || []).map(st => ({t:"street",id:st.id})).filter(App.pickable)),
    "clear-selection": () => App.select([]),
  };
  function changeSelected(refs, type, fn, opts) {
    const objects = selectedOf(refs, type);
    if (objects.length) App.edit(sc => objects.forEach(object => fn(object, sc)), opts);
  }

  function roadPicture(kind) {
    const lanes = {yard:2,street:2,avenue:4,highway:6}[kind] || 2;
    const width = {yard:32,street:48,avenue:66,highway:84}[kind] || 48;
    const start = (96 - width) / 2, lane = width / lanes;
    const lines = Array.from({length:lanes-1}, (_, i) => {
      const x = start + lane * (i + 1), centre = i + 1 === lanes / 2;
      return centre && kind === "highway"
        ? `<path d="M${x} 0V52" stroke="#8cbd74" stroke-width="5"/>`
        : `<path d="M${x} 0V52" stroke="#fff" stroke-width="1.4" ${centre ? "" : 'stroke-dasharray="6 5"'}/>`;
    }).join("");
    return `<svg class="road-profile" viewBox="0 0 96 52" aria-hidden="true"><rect x="${start-4}" width="${width+8}" height="52" rx="4" fill="#c4c9bd"/><rect x="${start}" width="${width}" height="52" fill="#424954"/>${lines}<path d="M${start+lane/2} 32v-13m-3 4 3-4 3 4 M${start+width-lane/2} 19v13m-3-4 3 4 3-4" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  }
  const roadValue = (st, key) => key === "kind" ? st.kind || "street" : key === "surface" ? st.surface || "asphalt"
    : key === "centre" ? st.centre || (st.kind === "yard" ? "none" : st.kind === "avenue" ? "double" : "dashed")
    : key === "shoulder" ? !!st.shoulder : key === "median" ? Layout.medianOf(st) : st[key] !== false;
  function roadFieldApplies(st, key) {
    if (key === "centre") return st.surface !== "sand" && !st.manualMarks && !Layout.medianOf(st);
    if (key === "walk" || key === "edge") return st.surface !== "sand";
    return true;
  }
  function roadSettings(streets, prefix = "") {
    const val = key => shared(streets.filter(st => roadFieldApplies(st,key)), st => roadValue(st,key));
    const paved = streets.some(st => roadFieldApplies(st,"walk"));
    const centre = streets.some(st => roadFieldApplies(st,"centre"));
    const manual = streets.some(st => st.manualMarks);
    const profile = chips(prefix+"kind", Object.entries(Layout.KINDS).map(([value, info]) => ({
      value, title: info.title, html: roadPicture(value),
      tip: `${info.title} · ${String(Layout.widthOf({kind:value})).replace(".", ",")} м`,
    })), val("kind"), {cls:"road-profiles"});
    const surfaces = chips(prefix+"surface", [
      {value:"asphalt", title:"Асфальт", html:'<i class="surface-preview asphalt"></i>'},
      {value:"sand", title:"Грунт", html:'<i class="surface-preview sand"></i>'},
    ], val("surface"), {cls:"road-surfaces"});
    const marks = [["none","Без линии"],["dashed","Прерывистая"],["solid","Сплошная"],["double","Двойная сплошная"]];
    const markButtons = chips(prefix+"centre", marks.map(([value,title]) => ({
      value, tip:title, title:value === "none" ? "Нет" : "", html:value === "none" ? "" : `<i class="mark-pic m-${value}"></i>`,
    })), val("centre"), {cls:"road-lines"});
    return card(prefix ? `Дороги · ${streets.length}` : "", `
      ${fieldTitle("Профиль",val("kind"))}${profile}
      <div class="road-row">${fieldTitle("Покрытие",val("surface"))}${surfaces}</div>
      ${centre ? `<div class="road-row">${fieldTitle("Осевая",val("centre"))}${markButtons}</div>` : ""}
      ${[["edge","Краевая линия"],["walk","Тротуары"],["shoulder","Обочина"]].filter(([key]) => key === "shoulder" || paved).map(([key,title]) =>
        `<div class="road-switch">${toggle(prefix+key,title,val(key) === true)}${mixedBadge(val(key) === undefined)}</div>`).join("")}
      ${manual ? button(prefix+"marks-auto","Вернуть авторазметку","restart","ghost small") : ""}
    `, {cls:"road-sheet"});
  }

  function roadHandlers(refs, prefix = "") {
    const change = (key, fn) => {
      const streets = selectedOf(refs,"street").filter(st => roadFieldApplies(st,key));
      if (streets.length) App.edit(() => streets.forEach(fn));
    };
    const setFlag = (key,on) => change(key,st => {
      if (key === "shoulder") {
        if (on) { st.shoulder = 2.5; st.walk = false; }
        else delete st.shoulder;
      } else {
        st[key] = on;
        if (key === "walk" && on) delete st.shoulder;
      }
    });
    const h = {[prefix+"marks-auto"]: () => change("manualMarks",st => { delete st.manualMarks; })};
    for (const key of ["walk","edge","shoulder"]) h["toggle:"+prefix+key] = on => setFlag(key,on);
    for (const [key,values] of Object.entries({surface:["asphalt","sand"], kind:Object.keys(Layout.KINDS), centre:["none","dashed","solid","double"]})) {
      h["chip:"+prefix+key] = value => { if (values.includes(value)) change(key,st => { st[key] = value; }); };
    }
    for (const key of ["walk","edge"]) h["chip:"+prefix+key] = value => {
      if (["true","false"].includes(value)) setFlag(key,value === "true");
    };
    return h;
  }

  function multiInspector(p) {
    const refs = [...state.sel], streets = selectedOf(refs,"street"), decor = selectedOf(refs,"decor"), actors = selectedOf(refs,"actor");
    const signalActors = actors.filter(actor => ActorSignals.supports(actor.type));
    const locked = refs.length - editableRefs(refs).length;
    const canRotate = refs.some(App.canRotate), canCopy = refs.some(App.canCopy), canDelete = refs.some(App.canRemoveObject);
    const tint = shared(decor,d => d.tint || null), scale = shared(decor,d => d.scale[0]);
    const speed = shared(actors,a => Catalog.speedOf(a.maxSpeed || 10).id), signal = shared(signalActors,ActorSignals.mode);
    p.innerHTML = `${head(`<span class="ibadge">${ic("layers")}</span>`, `Выбрано · ${refs.length}`)}
      ${selectionActions()}
      ${locked ? `<p class="selection-status">${ic("lock")}Заблокировано: ${locked}</p>` : ""}
      ${streets.length ? roadSettings(streets,"bulk-road-") : ""}
      ${decor.length ? card(`Окружение · ${decor.length}`, `${fieldTitle("Цвет",tint)}${tints(decor[0].prop,tint)}
        ${fieldTitle("Масштаб",scale)}${chips("bulk-scale",[.75,1,1.25,1.5].map(value => ({value,title:`×${value}`})),scale)}
        ${slider("scale","Множитель",1,.5,1.6,.05,"×1")}`, {cls:"road-sheet"}) : ""}
      ${actors.length ? card(`Участники · ${actors.length}`, `${fieldTitle("Скорость",speed)}${chips("bulk-speed",Catalog.SPEEDS.map(item => ({value:item.id,title:item.title})),speed)}
        ${signalActors.length ? fieldTitle("Поворотники",signal)+chips("bulk-signal",[{value:"auto",title:"Авто"},{value:"left",title:"Левый",icon:"arrow-left"},{value:"right",title:"Правый",icon:"arrow-right"},{value:"off",title:"Выкл"}],signal) : ""}`, {cls:"road-sheet"}) : ""}
      ${canRotate || canCopy || canDelete ? card("", `<div class="insp-actions road-actions">${canRotate ? button("rotl","−15°","rotl","ghost")+button("rotr","+15°","rotr","ghost") : ""}${canCopy ? button("dup","Копия","copy","ghost") : ""}${canDelete ? button("del","Удалить","trash","danger ghost") : ""}</div>`) : ""}`;
    const base = new Map(decor.map(d => [d.id,[...d.scale]]));
    const rotate = degree => {
      const selected = editableRefs(refs), before = [...state.sel];
      App.select(selected); App.rotate(degree); App.select(before);
    };
    bind({
      ...selectionHandlers, ...roadHandlers(refs,"bulk-road-"),
      dup: () => { App.select(editableRefs(refs)); App.duplicate(); },
      del: () => { App.select(editableRefs(refs)); App.remove(); },
      rotl: () => rotate(-15), rotr: () => rotate(15),
      "chip:tint": value => changeSelected(refs,"decor",d => { d.tint = value || null; }),
      "chip:bulk-scale": value => { const n = Number(value); if ([.75,1,1.25,1.5].includes(n)) changeSelected(refs,"decor",d => { d.scale = [n,n,n]; }); },
      "slider:scale": live((_sc,value) => selectedOf(refs,"decor").forEach(d => { if (base.has(d.id)) d.scale = base.get(d.id).map(v => r3(v*value)); }), value => { const label = $("[data-shown=scale]"); if (label) label.textContent = `×${value.toFixed(2)}`; }),
      "chip:bulk-speed": value => { const item = Catalog.SPEEDS.find(item => item.id === value); if (item) changeSelected(refs,"actor",a => { a.maxSpeed = item.v; }); },
      "chip:bulk-signal": value => { if (["auto","left","right","off"].includes(value)) changeSelected(refs,"actor",a => { if (ActorSignals.supports(a.type)) ActorSignals.setTurn(a,value); },{rebuild:false}); },
    });
    Thumbs.fillAll(p);
  }

  // ---- a prop ---------------------------------------------------------------------------------
  function tints(prop, value) {
    const list = Catalog.TINTS[Catalog.groupOf(prop).id] || [null];
    return `<div class="swatches">${list.map((c) => `<button class="sw ${c === value || (!c && !value && value !== undefined) ? "on" : ""}" data-chip="tint" data-value="${c || ""}" aria-label="${c ? `Цвет ${c}` : "Свой цвет модели"}" aria-pressed="${c === value || (!c && !value && value !== undefined)}" style="--c:${c || "transparent"}" data-tip="${c ? "" : "Свой цвет модели"}">${c ? "" : ic("x")}</button>`).join("")}</div>`;
  }
  function modelChoices(kind, action, models, active, name) {
    return `<div class="object-models">${models.map(id => {
      const label = esc(name(id));
      return `<button data-chip="${action}" data-value="${esc(id)}" aria-label="${label}" title="${label}" aria-pressed="${id === active}">${Thumbs.img(kind, id)}</button>`;
    }).join("")}</div>`;
  }
  function objectHeading(yaw, quarter = false) {
    return `<div class="turn-row object-turn">${dial(yaw)}<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${quarter ? button("rot90", "90°", "", "ghost") : ""}${button("rotr", "+15°", "rotr", "ghost")}</div></div>`;
  }
  function decorInspector(p, ref, d) {
    const group = Catalog.groupOf(d.prop);
    const variants = [...state.catalog.props.map(x => x.id), "parked"].filter(group.match);
    p.innerHTML = `${head(Thumbs.img("prop", d.prop, "big"), Catalog.propName(d.prop), group.title)}
      ${variants.length > 1 ? card("Модель", modelChoices("prop", "prop", variants, d.prop, Catalog.propName)) : ""}
      ${card("Цвет", tints(d.prop, d.tint || null))}
      ${card("", slider("scale", "Масштаб", d.scale[0], .5, 2, .05, `×${d.scale[0].toFixed(2)}`) + objectHeading(d.yaw, true))}
      ${card("", deleteRow())}`;
    bind({
      ...common,
      "chip:prop": (v) => App.edit(() => { d.prop = v; }),
      "chip:tint": (v) => App.edit(() => { d.tint = v || null; }),
      "slider:scale": live(() => { const v = Number($("[data-slider=scale]").value); d.scale = [r3(v), r3(v), r3(v)]; }, (v) => { $("[data-shown=scale]").textContent = `×${v.toFixed(2)}`; }),
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15), rot90: () => App.rotate(90),
    });
    bindDial(p, d);
  }

  // A round handle for the heading: drag it round.
  function dial(yaw) {
    const a = yaw || 0;
    return `<div class="dial" data-dial><svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="27"/><path d="M32 32 L${32 + Math.sin(-a) * 24} ${32 - Math.cos(-a) * 24}"/><circle class="knob" cx="${32 + Math.sin(-a) * 24}" cy="${32 - Math.cos(-a) * 24}" r="5"/></svg></div>`;
  }
  function bindDial(p, o, rotate = null) {
    const el = p.querySelector("[data-dial]");
    if (!el) return;
    el.addEventListener("pointerdown", (e) => {
      if (selectionLocked() || e.button !== 0) return;
      el.setPointerCapture(e.pointerId);
      App.beginDrag();
      const move = (ev) => {
        const r = el.getBoundingClientRect();
        let a = -Math.atan2(ev.clientX - (r.left + r.width / 2), -(ev.clientY - (r.top + r.height / 2)));
        if (!ev.shiftKey) a = Math.round(a / (Math.PI / 12)) * (Math.PI / 12);
        let accepted = true;
        App.dragMove(sc => { if (rotate) accepted = rotate(sc, r3(a)); else o.yaw = r3(a); });
        if (accepted === false) return;
        el.querySelector("path").setAttribute("d", `M32 32 L${32 + Math.sin(-a) * 24} ${32 - Math.cos(-a) * 24}`);
        const k = el.querySelector(".knob");
        k.setAttribute("cx", 32 + Math.sin(-a) * 24);
        k.setAttribute("cy", 32 - Math.cos(-a) * 24);
      };
      const stop = ev => {
        el.removeEventListener("pointermove", move);
        el.removeEventListener("pointerup", stop);
        el.removeEventListener("pointercancel", stop);
        el.removeEventListener("lostpointercapture", stop);
        if (ev.type === "pointerup") App.endDrag(); else App.cancelDrag();
      };
      el.addEventListener("pointermove", move);
      el.addEventListener("pointerup", stop);
      el.addEventListener("pointercancel", stop);
      el.addEventListener("lostpointercapture", stop);
      move(e);
    });
  }

  // ---- a participant ---------------------------------------------------------------------------
  // A tram on the rails: which track, which way, and the branch it turns onto (its depot).
  function tramCard(s, a) {
    const tr = Tracks.of(s, a.track);
    const pr = tr ? Tracks.project(tr.points, a.pos) : null;
    const branches = tr ? Tracks.branchesAhead(s, tr, pr.at, a.trackDir === -1 ? -1 : 1) : [];
    const label = (t) => `${t.depot ? "Депо" : "Путь"} ${s.tracks.indexOf(t) + 1}`;
    return card("По рельсам", `${chips("track", [{ value: "", title: "Нет" }, ...s.tracks.map((t) => ({ value: t.id, title: label(t) }))], a.track || "")}
      ${tr ? `<div class="sub-h">Направление</div>${chips("tdir", [{ value: 1, icon: "arrow-up", title: "Как рельсы" }, { value: -1, icon: "arrow-uturn", title: "Обратно" }], a.trackDir === -1 ? -1 : 1)}` : ""}
      ${branches.length ? `<div class="sub-h">Дальше</div>${chips("branch", [{ value: "", title: "Прямо" }, ...branches.map((b) => ({ value: b.track.id, title: `на ${label(b.track)}` }))], a.branch || "")}` : ""}`, { icon: "rails" });
  }

  function actorInspector(p, ref, a) {
    const s = state.S;
    const plan = App.planScene();
    const lane = !!plan && Catalog.ACTORS[a.type]?.lane && (s.layout || a.way || !a.route);
    const ways = lane ? Layout.waysFrom(plan, a.pos, a.yaw) : [];
    const PAINTS = [null, "#F2F3F5", "#B9C0C7", "#2B2F36", "#C0392B", "#317ED4", "#1F3A5F", "#4D7768", "#E8C547", "#F08A24", "#8A6E4B"];
    const route = a.route && s.routes.find((r) => r.id === a.route);
    const types = Catalog.ACTOR_ORDER.filter((t) => state.catalog.actorTypes[t]);
    const moving = !(a.behaviour || {}).staysPut;
    const picture=a.type==='motorcycle'&&typeof a.sidecar==='boolean'?Thumbs.img('motorcycle',a.sidecar?'sidecar':'solo','big'):Thumbs.img('actor',a.type,'big');
    const movement = lane && !a.track
      ? chips("way", [{value:"stay",icon:"parked",tip:"Стоит"}, ...["left","straight","right","uturn"].map(k => ({value:k,icon:Catalog.EXITS[k].icon,tip:Catalog.EXITS[k].title,disabled:!ways.includes(k)}))], moving ? a.way || "straight" : "stay", {cls:"arrows"})
      : chips("move", [{value:"stay",title:"Стоит",icon:"parked"},{value:"go",title:"Едет",icon:"route"}], moving ? "go" : "stay");
    const pathActions = [
      lane && !a.track ? button("reverse","Развернуть","rotr","ghost") : "",
      route && (moving || a.track) ? button("to-route","К траектории","points","ghost") : "",
      !a.track ? button("draw-path",route?.manual ? "Перерисовать" : "Нарисовать путь","route","ghost") : "",
      !a.track && ["pedestrian","cyclist"].includes(a.type) && Layout.zebraPath(s,a.pos) ? button("zebra-path","По переходу","zebra","ghost") : "",
    ].join("");
    p.innerHTML = `${head(picture, a.name || Catalog.ACTORS[a.type]?.name, a.name && a.name !== Catalog.ACTORS[a.type]?.name ? Catalog.ACTORS[a.type]?.name : "")}
      ${card("Движение", movement + (pathActions ? `<div class="object-actions">${pathActions}</div>` : "")
        + (moving ? propertyRow("Скорость",chips("speed",Catalog.SPEEDS.map(x=>({value:x.id,title:x.title})),Catalog.speedOf(a.maxSpeed || 10).id))
          + toggle("waits","Пропускает игрока",a.behaviour?.waitsForPlayer,"flag") : "")
        + toggle("yield","Игрок уступает",(s.question.yieldTo || []).includes(a.id),"alert"))}
      ${a.type === "tram" && s.tracks?.length ? tramCard(s, a) : ""}
      ${ActorSignals.supports(a.type) ? card("Сигналы", propertyRow("Поворотник", `<select data-text="turnSignal" aria-label="Поворотник">${[["auto","Авто"],["left","Левый"],["right","Правый"],["off","Выкл."]].map(([value,label])=>`<option value="${value}" ${ActorSignals.mode(a) === value ? "selected" : ""}>${label}</option>`).join("")}</select>`)
        + toggle("hazards","Аварийка",ActorSignals.hazards(a),"alert")
        + (DriverSignal.supports(a.type) ? propertyRow("Рука водителя", chips("driver-signal",DriverSignal.poses.map(([value,title])=>({value,title:title.replace("Рука вверх","Вверх").replace("Рука влево","Влево")})),a.driverSignal || "none")) : "")) : ""}
      ${card("Модель", modelChoices("actor","type",types,a.type,t=>Catalog.ACTORS[t].name)
        + propertyRow("Подпись", `<input class="name-input" type="text" data-text="name" value="${esc(a.name || "")}" aria-label="Подпись в игре" placeholder="Без подписи">`))}
      ${a.type === "pedestrian" ? card("Поза",chips("pedestrian-pose",ActorAppearance.poses.map(([value,title])=>({value,title})),a.pedestrianPose || "stand")
        + (a.pedestrianPose && a.pedestrianPose !== "stand" ? propertyRow("Рука",chips("pose-arm",[{value:"right",title:"Правая"},{value:"left",title:"Левая"}],a.poseArm || "right")) : "")) : ""}
      ${a.type === "motorcycle" ? card("Коляска",chips("sidecar",[{value:"no",title:"Без коляски",html:Thumbs.img("motorcycle","solo")},{value:"yes",title:"С коляской",html:Thumbs.img("motorcycle","sidecar")}],ActorAppearance.sidecar(a,state.catalog)?"yes":"no",{cls:"tiles sidecar-options"})) : ""}
      ${a.type !== "pedestrian" && a.type !== "special" ? card("Цвет", `<div class="swatches">${PAINTS.map(c => `<button class="sw ${(a.paint || null) === c ? "on" : ""}" data-chip="paint" data-value="${c || ""}" aria-label="${c ? `Цвет ${c}` : "Цвет модели"}" aria-pressed="${(a.paint || null) === c}" style="--c:${c || "transparent"}">${c ? "" : ic("x")}</button>`).join("")}</div>`) : ""}
      ${card("Поворот",objectHeading(a.yaw))}
      ${card("",deleteRow())}`;
    bind({
      ...common,
      "chip:paint": (v) => App.edit(() => { if (v) a.paint = v; else delete a.paint; }),
      'chip:driver-signal':value=>{if(!App.isLocked(ref)&&DriverSignal.poses.some(([key])=>key===value))App.edit(()=>{a.driverSignal=value;},{rebuild:false});},
      'chip:pedestrian-pose':value=>{
        if(App.isLocked(ref)||!ActorAppearance.poses.some(([key])=>key===value))return;
        App.edit(()=>{a.pedestrianPose=value;a.pedestrianLook ??= 0;a.poseArm ??= 'right';},{rebuild:false});
      },
      'chip:pose-arm':value=>{if(!App.isLocked(ref)&&['left','right'].includes(value))App.edit(()=>{a.poseArm=value;},{rebuild:false});},
      'chip:sidecar':value=>{
        if(App.isLocked(ref)||!['yes','no'].includes(value))return;
        App.edit(()=>{a.sidecar=value==='yes';Object.assign(a,ActorAppearance.bounds(a.sidecar,a.scale));});
      },
      "toggle:hazards": on => App.edit(() => ActorSignals.setHazards(a,on)),
      "text:turnSignal": v => { if (["auto","left","right","off"].includes(v)) App.edit(() => ActorSignals.setTurn(a,v), { rebuild: false }); },
      reverse: () => App.edit(() => { a.yaw = App.r3(((a.yaw || 0) + 2 * Math.PI) % (2 * Math.PI) - Math.PI); }),
      "to-route": () => { if (route) App.select({ t: "route", id: route.id }); },
      "chip:track": (v) => App.edit((sc) => {
        if (v) { a.track = v; delete a.way; delete a.branch; sc.routes = sc.routes.filter((x) => x.id !== a.route); a.route = null; }
        else { delete a.track; delete a.branch; delete a.trackDir; sc.routes = sc.routes.filter((x) => x.id !== `actor_${a.id}`); a.route = null; }
      }),
      "chip:tdir": (v) => App.edit(() => { a.trackDir = Number(v); delete a.branch; if (route) delete route.manual; }),
      "chip:branch": (v) => App.edit(() => { if (v) a.branch = v; else delete a.branch; if (route) delete route.manual; }),
      "chip:type": (v) => App.edit(() => {
        const tpl = state.catalog.actorTypes[v];
        a.type = v; a.asset = tpl.asset;
        if(v!=='pedestrian'){delete a.pedestrianPose;delete a.poseArm;delete a.pedestrianLook;}
        if(v!=='motorcycle')delete a.sidecar;
        if(!DriverSignal.supports(v))delete a.driverSignal;
        if (!a.name || Object.values(Catalog.ACTORS).some((x) => x.name === a.name)) a.name = Catalog.ACTORS[v].name;
        a.halfLength = tpl.halfLength ?? a.halfLength; a.halfWidth = tpl.halfWidth ?? a.halfWidth;
      }),
      "text:name": (v) => App.edit(() => { a.name = v.trim(); }),
      "chip:way": (v) => App.edit((sc) => {
        if (v === "stay") { ActorSignals.setMoving(a,false); delete a.way; sc.routes = sc.routes.filter((r) => r.id !== a.route); a.route = null; }
        else {
          ActorSignals.setMoving(a,true);
          a.way = v;
          const r = sc.routes.find((x) => x.id === (a.route || `actor_${a.id}`));
          if (r) { delete r.manual; r.auto = true; }
        }
      }),
      "chip:move": (v) => App.edit((sc) => {
        ActorSignals.setMoving(a,v !== "stay");
        if (v === "stay" && !a.track) { sc.routes = sc.routes.filter((r) => r.id !== a.route); a.route = null; }
      }),
      "draw-path": () => Tools.drawPathFor(a.id),
      "zebra-path": () => App.edit((sc) => {
        const path = Layout.zebraPath(sc, a.pos);
        if (!path) return;
        const rid = `actor_${a.id}`;
        sc.routes = sc.routes.filter((x) => x.id !== rid);
        sc.routes.push({ id: rid, kind: "actor", points: path });
        a.route = rid;
        a.behaviour = { ...(a.behaviour || {}), staysPut: false };
        a.yaw = App.r3(Math.atan2(path[1][0] - path[0][0], path[1][1] - path[0][1]));
      }),
      "chip:speed": (v) => App.edit(() => { a.maxSpeed = Catalog.SPEEDS.find((x) => x.id === v).v; }),
      "toggle:waits": (on) => App.edit(() => { a.behaviour = { ...(a.behaviour || {}), waitsForPlayer: on }; }),
      "toggle:yield": (on) => App.edit((sc) => {
        const set = new Set(sc.question.yieldTo || []);
        on ? set.add(a.id) : set.delete(a.id);
        sc.question.yieldTo = [...set];
      }),
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
    });
    bindDial(p, a);
  }

  // ---- tram tracks ----------------------------------------------------------------------------------
  function trackInspector(p, ref, t) {
    const edit = fn => { if (!App.isLocked(ref)) App.edit(fn); };
    const trams = state.S.actors.filter((a) => a.track === t.id);
    const railway = t.railType === "railway";
    p.innerHTML = `${head(`<span class="ibadge">${ic("rails")}</span>`, "Рельсы", trams.length ? `Трамваев · ${trams.length}` : "")}
      ${card("Тип рельсов", chips("rail-type", [{value:"tram",title:"Трамвайные"},{value:"railway",title:"Железнодорожные"}], railway ? "railway" : "tram")
        + toggle("render-track","Видны в игре", t.render === true,"eye")
        + (!railway ? toggle("depot","Заезд в депо",!!t.depot,"home") : ""))}
      ${card("", `<div class="object-actions">${button("reverse","Развернуть путь","rotr","ghost")}${button("del","Удалить","trash","danger ghost")}</div>`)}`;
    bind({
      del: () => { if (!App.isLocked(ref)) App.remove(); },
      "chip:rail-type": (v) => edit(() => { if (["tram", "railway"].includes(v)) { t.railType = v; t.render = true; } }),
      "toggle:render-track": (on) => edit(() => { t.render = on; }),
      "toggle:depot": (on) => edit(() => { if (on) t.depot = true; else delete t.depot; }),
      reverse: () => edit(() => { t.points.reverse(); }),
    });
  }

  // ---- a road sign --------------------------------------------------------------------------------
  // Both mount types browse the same catalogue. Only the current page creates image nodes.
  const signFaceSelection = new Map();
  const pickerState = {key:"", query:"", group:"", page:0};
  function signPicker(key, codes, active, chip, slot) {
    const pageSize = 8;
    if (pickerState.key !== key) Object.assign(pickerState, {key, query:"", group:"", page:Math.max(0, Math.floor(codes.indexOf(active) / pageSize))});
    const entry = code => state.catalog.signInfo?.[code] || {};
    const groups = [...new Set(codes.map(c => c.split(".")[0]))];
    const groupName = ["", "Предупреждающие", "Приоритет", "Запрещающие", "Предписывающие", "Особые предписания", "Информация", "Сервис", "Таблички"];
    function results() {
      const words = pickerState.query.toLowerCase().replaceAll("ё","е").trim().split(/\s+/);
      const matches = codes.filter(code => {
        if (pickerState.group && code.split(".")[0] !== pickerState.group) return false;
        const info = entry(code);
        const name = `знак ${code} ${Catalog.signName(code)} ${info.folkName || ""} ${info.group || ""}`.toLowerCase().replaceAll("ё","е");
        return words.every(word => /^[\d.]+$/.test(word) ? code.startsWith(word) : name.includes(word));
      });
      const last = Math.max(0,Math.ceil(matches.length / pageSize) - 1);
      pickerState.page = Math.min(last, Math.max(0,pickerState.page));
      const start = pickerState.page * pageSize;
      const arrows = last > 0 ? `<div class="picker-pages"><button data-act="previous-signs" aria-label="Предыдущие знаки" ${start ? "" : "disabled"}>${ic("chevron")}</button><span>${pickerState.page+1} / ${last+1}</span><button data-act="next-signs" aria-label="Следующие знаки" ${pickerState.page===last ? "disabled" : ""}>${ic("chevron")}</button></div>` : "";
      return matches.length ? `<div class="object-sign-grid">${matches.slice(start,start+pageSize).map(code => {
        const name = esc(`${code} · ${Catalog.signName(code)}`);
        return `<button data-chip="${chip}" data-slot="${slot}" data-value="${esc(code)}" aria-label="${name}" title="${name}" aria-pressed="${active===code}"><img src="/asset/sign/${code==='5.33'?'5.33_plain':code}.svg" alt=""><span>${esc(code)}</span></button>`;
      }).join("")}</div>${arrows}` : '<span class="picker-empty">Знак не найден</span>';
    }
    function refresh() {
      const box = pane().querySelector("[data-sign-results]");
      if (box) box.innerHTML = results();
    }
    return {
      html: `<div class="sign-picker-controls"><label class="search">${ic("search")}<input type="search" data-sign-search aria-label="Поиск знака" placeholder="Номер, название" value="${esc(pickerState.query)}"></label><select data-text="signGroup" aria-label="Группа знаков"><option value="">Все группы</option>${groups.map(g=>`<option value="${esc(g)}" ${pickerState.group === g ? "selected" : ""}>${esc(g)} · ${esc(groupName[Number(g)] || g)}</option>`).join("")}</select></div><div data-sign-results>${results()}</div>`,
      handlers: {
        searchSigns: query => { pickerState.query = query; pickerState.page = 0; refresh(); },
        "text:signGroup": group => { pickerState.group = group; pickerState.page = 0; refresh(); },
        "previous-signs": () => { pickerState.page--; App.renderInspector(); },
        "next-signs": () => { pickerState.page++; App.renderInspector(); },
      },
    };
  }
  const compassDirs = [["nw","↖","Вверх-влево"],["north","↑","Вверх"],["ne","↗","Вверх-вправо"],["west","←","Влево"],["east","→","Вправо"],["sw","↙","Вниз-влево"],["south","↓","Вниз"],["se","↘","Вниз-вправо"]];
  function compass(name, selected, label) {
    return `<div class="dir-grid object-compass" role="group" aria-label="${esc(label)}">${compassDirs.map(([d,arrow,title])=>`<button class="${selected.includes(d) ? "on" : ""}" data-chip="${name}" data-value="${d}" aria-pressed="${selected.includes(d)}" aria-label="${title}" title="${title}">${arrow}</button>`).join("")}</div>`;
  }
  function signInspector(p, ref, o) {
    const codes = state.catalog.signs || [], key = `${state.id}/sign/${o.id}`;
    const slot = o.secondSign && signFaceSelection.get(key) === 1 ? 1 : 0;
    const face = slot ? o.secondSign : o;
    const custom = !!face.laneDirections?.length;
    const lanes = custom ? LaneSign.normalize(face.laneDirections) : [];
    const main = face.mainRoad || [], roads = face.roads || ["north","south","east","west"];
    const picker = signPicker(`${key}/${slot}`,codes,face.code,"code",slot);
    const lanePicture = directions => LaneSign.svg(directions).replace("<svg ", '<svg style="width:100%;height:auto;display:block" ');
    const picture = (f, size = 44) => f.laneDirections?.length ? `<span class="lane-thumb" style="width:${size}px">${lanePicture(f.laneDirections)}</span>` : `<img width="${size}" height="${size}" class="sign-big" src="/asset/sign/${SignMount.textureCode(f)}.svg" alt="">`;
    const faceTabs = o.secondSign ? `<div class="mount-slots">${SignMount.faces(o).map((f,i)=>`<button data-chip="face" data-value="${i}" aria-pressed="${slot===i}">${picture(f,24)}${i ? "Нижний" : "Верхний"}</button>`).join("")}</div>` : "";
    const laneControls = lanes.map((directions,i)=>propertyRow(`Полоса ${i+1}`, `<div class="seg-chips arrows">${[["left","←","Налево"],["straight","↑","Прямо"],["right","→","Направо"]].map(([dir,arrow,title])=>`<button class="${directions.includes(dir) ? "on" : ""}" data-chip="laneDirection" data-lane="${i}" data-value="${dir}" aria-label="${title}" title="${title}" aria-pressed="${directions.includes(dir)}">${arrow}</button>`).join("")}</div>`)).join("");
    const numeric = SignMount.numberSpec(face.code);
    p.innerHTML = `${head(picture(face),custom ? "Направления по полосам" : Catalog.signName(face.code),face.code)}
      ${card("Щит", faceTabs + chips("signMode",[{value:"standard",title:"Знак"},{value:"lanes",title:"Полосы"}],custom?"lanes":"standard")
        + (custom ? propertyRow("Полос",chips("laneCount",[1,2,3,4,5,6].map(n=>({value:n,title:String(n)})),lanes.length)) + laneControls : picker.html)
        + (!custom && numeric ? propertyRow(`Число, ${numeric.unit}`,`<input type="text" inputmode="decimal" data-text="signNumber" aria-label="Число на знаке" value="${esc(face.number ?? numeric.default)}">`) : "")
        + (face.code==="5.33" ? propertyRow("Вариант",chips("zone-variant",[{value:"plain",title:"Обычный"},{value:"weekends",title:"Выходные"}],face.zoneVariant || "weekends")) : ""))}
      ${card("Стойка", `<div class="object-actions">${o.secondSign ? button("swap-signs","Поменять местами","rotr","ghost") + button("remove-second-sign","Убрать нижний","trash","danger ghost") : button("add-second-sign","Добавить нижний знак","plus","ghost")}</div>`
        + propertyRow("Монтаж",chips("mount",[{value:"pole",title:"Стойка"},{value:"cantilever",title:"Консоль"}],o.mount || "pole"))
        + (o.mount === "cantilever" ? slider("reach","Вылет",o.reach ?? 4.5,.5,15,.25,`${o.reach ?? 4.5} м`)
          + propertyRow("Консоль",chips("armSide",[{value:"left",title:"Слева"},{value:"right",title:"Справа"}],o.armSide || "left"))
          + slider("clearance","Нижний край",o.clearance ?? 5.5,5,8,.25,`${o.clearance ?? 5.5} м`) : ""))}
      ${card("Табличка",propertyRow("Надпись",`<input type="text" aria-label="Надпись под знаком" data-text="plate" value="${esc(face.plate || "")}" placeholder="150 м">`)
        + propertyRow("Главная · 8.13",compass("main",main,"Главная дорога"))
        + (main.length ? propertyRow("Все дороги",compass("roads",roads,"Дороги перекрёстка")) : ""))}
      ${card("Поворот",objectHeading(o.yaw,true))}${card("",deleteRow())}`;
    bind({
      ...common, ...picker.handlers,
      "chip:face": v => { signFaceSelection.set(key,Number(v)); App.renderInspector(); },
      "add-second-sign": () => { signFaceSelection.set(key,1); App.edit(() => { o.secondSign = {code:"2.4"}; }); },
      "remove-second-sign": () => { signFaceSelection.set(key,0); App.edit(() => { delete o.secondSign; }); },
      "swap-signs": () => { signFaceSelection.set(key,1-slot); App.edit(() => SignMount.swapFaces(o)); },
      "text:signNumber": value => {
        const number = Number(value.trim().replace(",", "."));
        if (App.isLocked(ref)) return;
        if (!value.trim() || !SignMount.validNumber(number,face.code)) { App.toast("Введите допустимое положительное число (до двух знаков после запятой)", "warn"); App.renderInspector(); return false; }
        App.edit(() => { face.number = number; });
      },
      "chip:signMode": (v) => App.edit(() => { if (v === "lanes") { face.code = "5.15.1"; delete face.number; face.laneDirections = LaneSign.normalize(face.laneDirections || LaneSign.DEFAULT_LANES); } else delete face.laneDirections; }),
      "chip:laneCount": (v) => App.edit(() => { const n = Number(v), directions = LaneSign.normalize(face.laneDirections); face.laneDirections = Array.from({length:n}, (_, i) => directions[i] || ["straight"]); }),
      "chip:laneDirection": (v, e) => App.edit(() => { const i = Number(e.target.closest('[data-chip]').dataset.lane), directions = LaneSign.normalize(face.laneDirections); const selected = new Set(directions[i]); if (selected.has(v)) { if (selected.size === 1) return; selected.delete(v); } else selected.add(v); directions[i] = [...selected]; face.laneDirections = LaneSign.normalize(directions); }),
      "chip:mount": (v) => App.edit(() => { if (v === "cantilever") { o.mount = v; o.reach ??= 4.5; o.armSide ??= "left"; o.clearance ??= 5.5; } else delete o.mount; }),
      "chip:armSide": (v) => App.edit(() => { o.armSide = v; }),
      "slider:reach": live((_s, v) => { o.reach = r3(v); }, v => { const label = pane().querySelector('[data-shown="reach"]'); if (label) label.textContent = `${v} м`; }),
      "slider:clearance": live((_s, v) => { o.clearance = r3(v); }, v => { const label = pane().querySelector('[data-shown="clearance"]'); if (label) label.textContent = `${v} м`; }),
      "chip:code": (v) => App.edit(() => { face.code = v; delete face.laneDirections; delete face.number; if(v==='5.33')face.zoneVariant='plain';else delete face.zoneVariant; if (v === "8.13" && !(face.mainRoad || []).length) face.mainRoad = ["south", "west"]; }),
      'chip:zone-variant':value=>{if(!App.isLocked(ref)&&['plain','weekends'].includes(value))App.edit(()=>{face.zoneVariant=value;});},
      "chip:main": (v) => App.edit(() => {
        const set = new Set(face.mainRoad || []);
        set.has(v) ? set.delete(v) : set.add(v);
        if (set.size) face.mainRoad = [...set]; else delete face.mainRoad;
      }),
      "chip:roads": (v) => App.edit(() => {
        const set = new Set(face.roads || ["north", "south", "east", "west"]);
        set.has(v) ? set.delete(v) : set.add(v);
        face.roads = [...set];
      }),
      "text:plate": (v) => App.edit(() => { if (v.trim()) face.plate = v.trim(); else delete face.plate; }),
      "text:plateSign": v => {
        if (App.isLocked(ref) || (v && !codes.includes(v))) return;
        App.edit(() => { if (v) face.plateSign = v; else delete face.plateSign; });
      },
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15), rot90: () => App.rotate(90),
    });
    bindDial(p, o);
  }

  // ---- a traffic controller ----------------------------------------------------------------------
  const GESTURES = [
    { value: "sides", title: "Руки в стороны" }, { value: "forward", title: "Правая рука вперёд" },
    { value: "up", title: "Рука вверх" }, { value: "down", title: "Руки опущены" },
  ];
  function officerInspector(p, ref, o) {
    if (state.id === "mini_regulator") {
      p.innerHTML = `${head(`<span class="ibadge">${ic("person")}</span>`,"Регулировщик")}
        ${card("Положение", `<div class="object-coords">${["X","Z"].map((axis,i)=>`<label>${axis}, м<input type="number" step="0.1" data-text="officer${axis}" value="${o.pos[i]}"></label>`).join("")}</div>`)}`;
      bind(Object.fromEntries(["officerX","officerZ"].map((key,i) => [`text:${key}`, v => App.edit(() => { if (v.trim() && Number.isFinite(Number(v))) o.pos[i] = Number(v); })])));
      return;
    }
    p.innerHTML = `${head(`<span class="ibadge">${ic("person")}</span>`,"Регулировщик")}
      ${card("Жест",`<div class="gestures object-gestures">${GESTURES.map(g=>`<button class="gesture ${o.gesture===g.value ? "on" : ""}" data-chip="gesture" data-value="${g.value}" aria-pressed="${o.gesture===g.value}">${gesturePic(g.value)}<span>${g.title}</span></button>`).join("")}</div>`)}
      ${card("Поворот",objectHeading(o.yaw,true))}${card("",deleteRow())}`;
    bind({
      ...common,
      "chip:gesture": (v) => App.edit(() => { o.gesture = v; }),
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15), rot90: () => App.rotate(90),
    });
    bindDial(p, o);
  }
  // The signal as a small figure: the arms as the officer holds them.
  function gesturePic(g) {
    const arms = { sides: "M8 16 H40", forward: "M8 16 L14 26 M40 16 L32 14", up: "M8 16 L14 26 M40 16 L40 2", down: "M8 16 L10 28 M40 16 L38 28" }[g];
    return `<svg viewBox="0 0 48 44" width="48" height="44"><circle cx="24" cy="7" r="4" fill="currentColor"/><path d="M24 12 V30 M24 30 L19 42 M24 30 L29 42 M14 16 H34" stroke="currentColor" stroke-width="4" stroke-linecap="round" fill="none"/><path d="${arms}" stroke="currentColor" stroke-width="4" stroke-linecap="round" fill="none"/></svg>`;
  }

  // ---- a traffic light -------------------------------------------------------------------------
  function lightInspector(p, ref, l) {
    const s = state.S, isTram = !!l.tram;
    const key = `${state.id}/light/${l.id}`, slot = signFaceSelection.get(key) || 0;
    const mounted = l.mountedSigns || [];
    const codes = [...new Set(["2.4", "8.13", ...(state.catalog.signs || [])])];
    const picker = signPicker(`${key}/${slot}`,codes,mounted[slot],"mountedSign",slot);
    const signalChoice = x => `<button class="signal-choice ${l.state===x.id ? "on" : ""}" data-chip="state" data-value="${x.id}" aria-label="${x.title}" aria-pressed="${l.state===x.id}"><span class="lamp ${l.state===x.id ? "on" : ""} ${x.id.startsWith("flashing_") ? "blink" : ""}" style="--c:${x.colour}"></span><span>${x.title}</span></button>`;
    const lamps = `<div class="signal-steady">${Catalog.LIGHTS.filter(x=>!x.id.startsWith("flashing_")).map(signalChoice).join("")}</div><div class="signal-flashing">${Catalog.LIGHTS.filter(x=>x.id.startsWith("flashing_")).map(signalChoice).join("")}</div>`;
    const tramChips = chips("tram", [{value:"",title:"Нет"},{value:"straight",tip:"Прямо",icon:"arrow-up"},{value:"left",tip:"Налево",icon:"arrow-left"},
      {value:"right",tip:"Направо",icon:"arrow-right"},{value:"stop",title:"Стоп"},{value:"off",title:"Выкл."}],l.tram || "",{cls:"tram-signals"});
    const slots = [0,1].map(i => {
      const code = mounted[i], title = i ? "Нижний" : "Верхний";
      const pic = code ? `<img src="/asset/sign/${esc(code)}.svg" alt="">` : ic("plus");
      return `<button data-chip="mountSlot" data-value="${i}" aria-pressed="${slot===i}" aria-label="${title} знак · ${code || "нет"}">${pic}<span>${title}<small>${code || "Нет"}</small></span></button>`;
    }).join("");
    p.innerHTML = `${head(Thumbs.img("light",isTram ? "light_tram" : "light","big"),"Светофор")}
      ${card(s.lights.length>1 ? "Сигнал всех светофоров" : "Сигнал", `<div class="signal-picker">${lamps}</div>${l.state==="flashing_green" ? `<div class="signal-after-answer"><b>После ответа</b><span><i class="signal-dot yellow"></i>Жёлтый · 3 с ${ic("arrow-right")}<i class="signal-dot red"></i>Красный</span></div>` : ""}`)}
      ${card("Секции",propertyRow("Трамвайная",tramChips) + (!isTram ? propertyRow("Стрелка",chips("arrow",[{value:"",title:"Нет"},{value:"left",tip:"Налево",icon:"arrow-left"},{value:"straight",tip:"Прямо",icon:"arrow-up"},{value:"right",tip:"Направо",icon:"arrow-right"}],l.arrow || "",{cls:"arrows"})) : ""))}
      ${card("Знаки на стойке",`<div class="mount-slots">${slots}${mounted[slot] ? `<button data-chip="mountedSign" data-value="" data-slot="${slot}" aria-label="Снять выбранный знак" title="Снять знак">${ic("trash")}</button>` : ""}</div>` + picker.html
        + (mounted.includes("8.13") ? propertyRow("Главная · 8.13",compass("mountedMainRoad",l.mountedMainRoad || [],"Главная дорога")) : ""))}
      ${card("Поворот",objectHeading(l.yaw))}${card("",deleteRow())}`;
    bind({
      ...common, ...picker.handlers,
      "chip:mountSlot": v => { signFaceSelection.set(key,Number(v)); App.renderInspector(); },
      "chip:mountedMainRoad": (v) => App.edit(() => { const roads = new Set(l.mountedMainRoad || []); roads.has(v) ? roads.delete(v) : roads.add(v); l.mountedMainRoad = [...roads]; }),
      "chip:mountedSign": (v, e) => App.edit(() => { const signs = [...(l.mountedSigns || [])]; signs[Number(e.target.closest("[data-chip]").dataset.slot)] = v; if (v === "8.13" && !(l.mountedMainRoad || []).length) l.mountedMainRoad = ["south", "west"]; if (signs.some(Boolean)) l.mountedSigns = signs; else delete l.mountedSigns; }),
      "chip:state": v => {
        if (App.isLocked(ref) || !Catalog.LIGHTS.some(x=>x.id === v)) return;
        App.edit(sc => {
          sc.lights.forEach(x => {x.state=v;});
          if (v === "flashing_green") { sc.question = sc.question || {}; sc.question.redWait=null; }
        });
      },
      "chip:tram": (v) => App.edit(() => {
        l.tram = v || null;
        const cat = state.catalog;
        if (v) {
          l.arrow = null;
          l.asset = cat?.lightTramAsset || cat?.lightAssets?.tram || l.asset;
        } else {
          l.asset = cat?.lightAssets?.[""] || cat?.lightAsset || l.asset;
        }
      }),
      "chip:arrow": (v) => App.edit(() => {
        l.arrow = v || null;
        const assets = state.catalog?.lightAssets;
        if (assets) {
          if (!v) l.asset = assets[""] || l.asset;
          else if (assets[v]) l.asset = assets[v];
          else if (v === "left" && assets["right"]) l.asset = assets["right"];
        }
      }),
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
    });
    bindDial(p, l);
  }

  // ---- the road plan: a street, a node -----------------------------------------------------------
  function roadNumber(key, title, value, min, max, step, reset = "") {
    const attr = `min="${min}" max="${max}" step="${step}" value="${r3(value)}" aria-label="${esc(title)}, м"`;
    return `<div class="road-measure"><span>${esc(title)}</span><input type="range" data-slider="${key}" ${attr}>
      <label><input type="number" data-text="${key}" required ${attr}> м</label>${reset}</div>`;
  }
  function streetInspector(p, ref, st) {
    const s = state.S, L = s.layout, crop = s.crop || 90;
    const edit = (fn, opts) => { if (!App.isLocked(ref)) return App.edit(fn,opts); };
    const allEnds = [st.a, st.b].map((nid) => {
      const n = Layout.nodeOf(L, nid), kind = Layout.nodeKind(L, n, crop);
      return { nid, end: nid === st.a ? "a" : "b", kind, set: (st.ends || {})[nid === st.a ? "a" : "b"] || {} };
    });
    const ends = allEnds.filter((e) => e.kind === "junction" || e.kind === "ring" || e.kind === "dead");
    const highwayEnds = allEnds.filter(e => e.kind === "border");
    const endLabel = e => {
      const here = Layout.nodeOf(L,e.nid), there = Layout.nodeOf(L,st[e.end === "a" ? "b" : "a"]);
      const dx = here.x-there.x, dz = here.z-there.z;
      return Math.abs(dx) > Math.abs(dz) ? (dx > 0 ? "Слева" : "Справа") : (dz > 0 ? "Сверху" : "Снизу");
    };
    const pl = Layout.playerPlan(s), isPlayer = pl?.st.id === st.id;
    const direction = allEnds.map(e => {
      const where = {junction:"к перекрёстку", ring:"к кольцу", border:"к краю"}[e.kind] || "к концу";
      return `<option value="${esc(e.nid)}" ${isPlayer && pl.nid === e.nid ? "selected" : ""}>${endLabel(e)} · ${where}</option>`;
    }).join("");
    const portField = e => `<div class="road-row"><span>${endLabel(e)}</span>${chips(`port-${e.end}`, [{value:"highway",title:"3+3"},{value:"avenue",title:"2+2"}], Layout.highwayPort(st,e.end))}</div>`;
    const entryEnd = isPlayer && pl.nid === st.a ? "b" : "a";
    const transition = e => Layout.highwayPort(st,e.end) === "avenue";
    const entry = highwayEnds.find(e => e.end === entryEnd), exit = highwayEnds.find(e => e.end !== entryEnd);
    const portScheme = () => {
      if (highwayEnds.length === 1) return portField(highwayEnds[0]);
      const preset = transition(entry) ? (transition(exit) ? "both" : "entry") : transition(exit) ? "exit" : "through";
      const options = [["through","3+3 с двух сторон"],["entry",`2+2 · ${endLabel(entry)}`],["exit",`2+2 · ${endLabel(exit)}`],["both","2+2 с двух сторон"]];
      return `<label class="road-row"><span>Стыки</span><select data-text="highway-preset" aria-label="Стыки трассы">${options.map(([v,t])=>`<option value="${v}" ${v === preset ? "selected" : ""}>${t}</option>`).join("")}</select></label>`;
    };
    const endPanel = e => {
      const offset = Layout.endOffset(L, st, e.nid, crop), limits = Layout.endOffsetLimits(L, st, e.nid, crop);
      const reset = offset ? `<button class="icon-btn" aria-label="Сбросить отступ" title="Сбросить отступ" data-act="approach-reset" data-nid="${esc(e.nid)}">${ic("restart")}</button>` : "";
      const feature = (key,title,icon) => `<button class="pick ${e.set[key] ? "on" : ""}" aria-pressed="${!!e.set[key]}" data-act="end" data-end="${e.end}" data-what="${key}">${ic(icon)}${title}</button>`;
      return card(ends.length === 1 ? "Въезд" : `Въезд · ${endLabel(e)}`, `
        <div class="road-entry">${feature("stop","Стоп-линия","stopline")}${feature("zebra","Зебра","zebra")}</div>
        ${e.set.stop ? `<div class="road-row"><span>Линия</span>${chips(`stop-style-${e.end}`, stopStyles, e.set.stopStyle || "solid")}</div>` : ""}
        ${e.kind === "junction" ? roadNumber(`approach-${e.end}`,"Отступ",offset,limits.min,limits.max,.1,reset) : ""}
        ${e.kind === "junction" && st.surface === "sand" ? roadNumber(`paved-${e.end}`,"Асфальт",Layout.pavedEnd(st,e.end),0,Layout.PAVED_MAX,1) : ""}
      `, {cls:"road-sheet"});
    };
    p.innerHTML = `${head(`<span class="ibadge">${ic("road")}</span>`, "Дорога")}
      ${roadSettings([st])}
      ${card("", `${st.kind !== "yard" ? `<div class="road-row"><span>Разделитель</span>${chips("median", [...(st.kind === "highway" ? [] : [{value:0,title:"Нет"}]), ...[2,3,5].map(value => ({value,title:`${value} м`}))], Layout.medianOf(st))}</div>` : ""}
        <label class="road-row"><span>Игрок</span><select data-text="player-end" aria-label="Направление игрока">${!isPlayer ? '<option value="" selected disabled>Не назначен</option>' : ""}${direction}</select></label>
        ${st.kind !== "yard" && st.surface !== "sand" && !st.manualMarks ? button("marks-own","Редактировать линии отдельно","marking","ghost small") : ""}
        ${st.bend ? button("straighten","Выпрямить дорогу","road","ghost small") : ""}`, {cls:"road-sheet"})}
      ${st.kind === "highway" && highwayEnds.length ? card(highwayEnds.length === 1 ? "Стык трассы" : "", portScheme(), {cls:"road-sheet"}) : ""}
      ${ends.map(endPanel).join("")}
      <div class="selection-actions road-footer">${button("select-roads","Все дороги","road","ghost small")}${button("clear-selection","Снять выбор","x","ghost small")}
        <button class="icon-btn" data-act="del" aria-label="Удалить дорогу" title="Удалить дорогу">${ic("trash")}</button></div>`;
    bind({
      ...selectionHandlers,
      ...roadHandlers([ref]),
      del: () => { if (!App.isLocked(ref)) App.remove(); },
      "chip:median": (v) => edit(() => { if (Number(v)) st.median = Number(v); else delete st.median; }),
      ...Object.fromEntries(highwayEnds.map(e => [`chip:port-${e.end}`, v => edit(() => Layout.setHighwayPort(st,e.end,v))])),
      "text:highway-preset": preset => edit(() => {
        for (const e of highwayEnds) Layout.setHighwayPort(st,e.end,
          preset === "both" || (preset === "entry" && e === entry) || (preset === "exit" && e === exit) ? "avenue" : "highway");
      }),
      straighten: () => edit(() => { st.bend = null; }),
      "marks-own": () => edit((sc) => {
        const own = sc.markings.filter((m) => m.auto && m.street === st.id && (m.type === "solid" || m.type === "dashed"));
        for (const m of own) sc.markings.push({ ...JSON.parse(JSON.stringify(m)), id: App.uniqueId("mark_", sc.markings.map((x) => x.id)), auto: undefined, street: undefined });
        st.manualMarks = true;
      }),
      "marks-auto": () => edit(() => { delete st.manualMarks; }),
      end: (d) => edit(() => {
        st.ends = st.ends || {};
        st.ends[d.end] = { ...(st.ends[d.end] || {}) };
        st.ends[d.end][d.what] = !st.ends[d.end][d.what];
      }),
      ...Object.fromEntries(ends.map(e => [`chip:stop-style-${e.end}`, v => {
        if (!stopStyles.some(style => style.value === v)) return;
        edit(() => {
          st.ends = st.ends || {};
          st.ends[e.end] = { ...(st.ends[e.end] || {}), stop: true };
          setStopStyle(st.ends[e.end], v);
        });
      }])),
      "approach-reset": d => edit(sc => Layout.setEndOffset(sc, st.id, d.nid, 0)),
      ...Object.fromEntries(ends.filter(e => e.kind === "junction").flatMap(e => [
        [`slider:approach-${e.end}`, live((sc, v) => { if (!App.isLocked(ref)) Layout.setEndOffset(sc, st.id, e.nid, v); }, v => {
          const value = Layout.endOffset(state.S.layout, Layout.streetOf(state.S.layout, st.id), e.nid, crop);
          const field = pane().querySelector(`[data-text="approach-${e.end}"]`);
          if (field) field.value = value;
        })],
        [`text:approach-${e.end}`, v => v.trim() !== "" && edit(sc => Layout.setEndOffset(sc, st.id, e.nid, Number(v)))],
        [`slider:paved-${e.end}`, live((sc, v) => { if (!App.isLocked(ref)) Layout.setPavedEnd(sc, st.id, e.end, v); }, v => {
          const field = pane().querySelector(`[data-text="paved-${e.end}"]`);
          if (field) field.value = Layout.pavedEnd(Layout.streetOf(state.S.layout, st.id), e.end);
        })],
        [`text:paved-${e.end}`, v => v.trim() !== "" && edit(sc => Layout.setPavedEnd(sc, st.id, e.end, Number(v)))],
      ])),
      "text:player-end": nid => {
        if ([st.a,st.b].includes(nid) && !(isPlayer && pl.nid === nid)) edit(sc => { sc.layout.player = {street:st.id, toward:nid}; });
      },
    });
  }

  function nodeInspector(p, ref, n) {
    const s = state.S, L = s.layout, crop = s.crop || 90;
    const kind = Layout.nodeKind(L, n, crop);
    const arms = Layout.streetsAt(L, n.id).length;
    const sizes = [{ value: "s", title: "Малое", r: 15, island: 6 }, { value: "m", title: "Среднее", r: 20, island: 9 }, { value: "l", title: "Большое", r: 26, island: 13 }];
    const size = n.ring ? sizes.reduce((b, x) => Math.abs(x.r - n.ring.r) < Math.abs(b.r - n.ring.r) ? x : b, sizes[1]).value : "m";
    const hasLights = s.lights.some((l) => Math.hypot(l.pos[0] - n.x, l.pos[1] - n.z) < (n.ring ? n.ring.r + 12 : 20));
    p.innerHTML = `${head(`<span class="ibadge">${ic(n.ring ? "ring" : "junction")}</span>`, n.ring ? "Кольцо" : kind === "junction" ? "Перекрёсток" : "Точка дороги")}
      ${arms >= 2 ? card("", `<div class="road-row"><span>Форма</span>${chips("ring", [{value:"cross", icon:"junction", title:arms === 2 ? "Стык" : "Перекрёсток"},{value:"ring", icon:"ring", title:"Кольцо"}], n.ring ? "ring" : "cross")}</div>
        ${n.ring ? `<div class="road-row"><span>Радиус</span>${chips("size", sizes.map(x => ({value:x.value, title:`${x.r} м`})), size)}</div>
          ${toggle("ring-outer-edge","Внешняя сплошная",n.ring.outerEdge !== false)}${toggle("ring-inner-edge","Сплошная вокруг островка",n.ring.innerEdge !== false)}` : ""}`,{cls:"road-sheet"}) : ""}
      ${kind === "junction" || kind === "ring" ? card("", `<div class="road-row"><span>Светофоры</span>${hasLights ? button("lights-off","Убрать","light","ghost small") : button("lights-on","На все въезды","light","ghost small")}</div>`,{cls:"road-sheet"}) : ""}
      ${card("", button("del","Удалить точку с дорогами","trash","danger ghost"))}`;
    bind({
      del: () => App.remove(),
      "chip:ring": value => {
        if ((value === "ring") === !!n.ring) return;
        App.edit(() => { if (value === "ring") n.ring = {r:20, island:9}; else delete n.ring; });
      },
      "chip:size": (v) => App.edit(() => { const x = sizes.find((y) => y.value === v); n.ring = { ...n.ring, r: x.r, island: x.island }; }),
      "toggle:ring-outer-edge": (on) => App.edit(() => { if (on) delete n.ring.outerEdge; else n.ring.outerEdge = false; }),
      "toggle:ring-inner-edge": (on) => App.edit(() => { if (on) delete n.ring.innerEdge; else n.ring.innerEdge = false; }),
      "lights-on": () => App.edit((sc) => placeLights(sc, n)),
      "lights-off": () => App.edit((sc) => { sc.lights = sc.lights.filter((l) => Math.hypot(l.pos[0] - n.x, l.pos[1] - n.z) >= (n.ring ? n.ring.r + 12 : 20)); }),
    });
  }

  // One light per arm, on its right corner, facing the coming cars.
  function placeLights(s, n) {
    const L = s.layout;
    for (const st of Layout.streetsAt(L, n.id)) {
      const line = Layout.lineFrom(L, st, n.id);
      const probe = Layout.along(line, 14).p;
      const spot = Tools.lightSpot(probe);
      if (!spot) continue;
      const id = App.uniqueId("light_", s.lights.map((l) => l.id));
      s.lights.push({ id, pos: spot.pos, yaw: spot.yaw, scale: 1, arrow: null, state: s.lights[0]?.state || "green", asset: state.catalog.lightAsset });
    }
  }

  // ---- routes ------------------------------------------------------------------------------
  function pathMode(manual, canAuto, count, canRebuild = false) {
    const option = (value, title, icon, current, enabled) => `<button aria-pressed="${current}" ${enabled && !current ? `data-act="${value}"` : "disabled"}>${ic(icon)}${title}</button>`;
    const label = manual ? "Путь" : `${count} ${App.plural(count, ["точка","точки","точек"])}`;
    return card("", `<div class="path-property"><span>${label}</span><div class="path-mode" role="group" aria-label="Построение пути">
      ${option("auto-path","Авто","road",!manual,canAuto)}${option("own-path","Вручную","points",manual,true)}</div>
      ${canRebuild ? `<button class="btn ghost path-reset" data-act="auto-path" title="Пересчитать подъезд" aria-label="Пересчитать подъезд">${ic("restart")}</button>` : ""}</div>`, {cls:"path-sheet"});
  }

  function pointEditor(points, index, anchor, canCompact) {
    const count = points.length, point = points[index];
    if (!point) return "";
    return card("", `<div class="path-coordinates">
      <label>Точка<span class="point-index"><input type="number" min="1" max="${count}" step="1" data-text="routeIndex" value="${index + 1}"><small>/ ${count}</small></span></label>
      ${["X","Z"].map((axis,i) => `<label>${axis}, м<input type="number" step="0.1" data-text="route${axis}" value="${r3(point[i])}" ${anchor ? "disabled" : ""}></label>`).join("")}</div>
      ${anchor ? `<span class="point-anchor">${ic("lock")}${anchor}</span>` : ""}
      <div class="path-actions">
        ${index < count - 1 ? button("route-add-point","Вставить","plus","ghost") : ""}
        ${!anchor && count > 2 ? button("route-delete-point","Удалить","trash","ghost") : ""}
        ${canCompact && count > 3 ? button("route-compact","Упростить","points","ghost") : ""}</div>`, {cls:"path-sheet"});
  }

  function playerRoutePointTools(ref, route) {
    const count = route.points.length;
    const index = Number.isInteger(ref.v) ? Math.max(0, Math.min(count - 1, ref.v)) : 0;
    // Traced scenes predate the manual flag: any non-generated player route
    // is already authored and must remain editable without a mode switch.
    const manual = !!route.manual || !route.auto;
    const anchored = ["manoeuvre", "guide"].includes(route.kind) ? index === 0
      : !!state.S.layout && (index === 0 || index === count - 1);
    const current = sc => sc.routes.find(r => r.id === route.id);
    const anchor = anchored ? (route.kind === "approach" && index === 0 ? "У въезда" : "У автомобиля") : "";
    return {
      html: manual ? pointEditor(route.points,index,anchor,true) : "",
      handlers: {
        "text:routeIndex": v => {
          const i = Number(v) - 1;
          const r = current(state.S);
          if (Number.isInteger(i) && r && i >= 0 && i < r.points.length) App.select({t:"route", id:route.id, v:i});
        },
        ...Object.fromEntries(["routeX", "routeZ"].map((key, axis) => [`text:${key}`, v => {
          if (!manual || anchored || !v.trim() || !Number.isFinite(Number(v))) return;
          App.edit(sc => {
            const r = current(sc);
            if (!r?.points[index]) return;
            Layout.editPlayerRoute(sc, r);
            r.points[index][axis] = r3(Number(v));
            if (r.kind === "approach" && !sc.layout && index === r.points.length - 1 && sc.stop) {
              sc.stop[axis === 0 ? "x" : "z"] = r.points[index][axis];
            }
          });
        }])),
        "route-delete-point": () => {
          if (!manual || anchored || count <= 2) return;
          App.select({t:"route", id:route.id, v:index});
          App.remove();
        },
        "route-add-point": () => {
          if (!manual || index >= count - 1) return;
          App.edit(sc => {
            const r = current(sc);
            if (!r?.points[index + 1]) return;
            Layout.editPlayerRoute(sc, r);
            const a = r.points[index], b = r.points[index + 1];
            r.points.splice(index + 1, 0, a.map((n, axis) => r3((n + b[axis]) / 2)));
          });
          App.select({t:"route", id:route.id, v:index + 1});
        },
        "route-compact": () => {
          if (!manual || count <= 3) return;
          // Simplification changes indices. Drop the old selected vertex before
          // App.edit rebuilds the route and immediately rerenders the inspector.
          App.select({t:"route", id:route.id});
          App.edit(sc => Layout.compactPlayerRoute(sc, current(sc)));
        },
      },
    };
  }

  function routeInspector(p, ref, r) {
    const s = state.S;
    if (r.kind === "guide") {
      const points = playerRoutePointTools(ref, r);
      p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, "Стрелка игрока")}
        ${playerGuideCard(s.question, true)}
        ${s.question?.showPlayerGuide === false ? "" : points.html}`;
      bind({...points.handlers, ...playerGuideHandlers});
      return;
    }
    if (state.id === "mini_regulator" && ["approach", "manoeuvre"].includes(r.kind)) return regulatorRouteInspector(p, ref, r);
    if (r.kind === "approach") {
      const points = playerRoutePointTools(ref, r);
      const manual = !!r.manual || !r.auto;
      p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, "Подъезд игрока")}
        ${pathMode(manual, !!s.layout, r.points.length, !manual)}${points.html}`;
      bind({
        ...points.handlers,
        "own-path": () => { App.select({t:"route",id:r.id}); App.edit(sc => Layout.setPlayerRouteManual(sc, sc.routes.find(x => x.id === r.id), true)); },
        "auto-path": () => { App.select({t:"route",id:r.id}); App.edit(sc => Layout.setPlayerRouteManual(sc, sc.routes.find(x => x.id === r.id), false)); },
      });
      return;
    }
    if (r.kind === "annotation") {
      const textOnly = r.style === "text", field = textOnly ? "free-text" : "annotation-text";
      const colours = [...AnnotationLine.colours];
      if (r.colour && !colours.some(([value]) => value === r.colour)) colours.push([r.colour,"Исходный"]);
      const kind = chips("annotation-style", AnnotationLine.styles.map(([value,title]) => ({value,title})), r.style || "line");
      const label = `<input type="text" data-text="${field}" aria-label="Текст надписи" placeholder="Например, 3 м" maxlength="120" value="${esc(r.text || "")}">`;
      p.innerHTML = `${head(`<span class="ibadge">${textOnly ? "Тт" : ic("measure")}</span>`, textOnly ? "Надпись" : "Обозначение")}
        ${card("Вид", kind, {cls:"path-sheet"})}
        ${card("Текст", label + (textOnly ? button("edit-text", "На сцене", "points", "ghost") : ""), {cls:"path-inline"})}
        ${textOnly
          ? card("Оформление", slider("text-size", "Размер", r.textSize || 1, .4, 4, .1, `${r.textSize || 1}×`)
            + slider("text-angle", "Поворот", r.textAngle || 0, -180, 180, 1, `${r.textAngle || 0}°`)
            + button("reset-angle", "Угол 0°", "restart", "ghost"), {cls:"path-sheet"})
          : card("Цвет", chips("annotation-colour", colours.map(([value,tip]) => ({value,tip,html:`<span class="paint" style="background:${value}"></span>`})), r.colour || "#20242b"), {cls:"path-inline"})
            + card("", slider("annotation-width", "Толщина", r.width ?? .16, .08, .6, .02, `${(r.width ?? .16).toFixed(2)} м`), {cls:"path-sheet"})}
        ${card("", (textOnly ? "" : `<div class="insp-actions">${button("annotation-reverse","Развернуть","rotr","ghost")}${button("rotl","−15°","rotl","ghost")}${button("rotr","+15°","rotr","ghost")}</div>`) + deleteRow())}`;
      const shown = (name, value) => { const output = p.querySelector(`[data-shown="${name}"]`); if (output) output.textContent = value; };
      bind({...common,
        "edit-text": () => Tools.editText(r),
        ["text:" + field]: value => App.edit(() => { r.text = value.slice(0,120); }, {rebuild:false}),
        "chip:annotation-style": value => {
          if (AnnotationLine.styles.some(([key]) => key === value)) App.edit(() => { r.style = value; }, {rebuild:false});
        },
        "chip:annotation-colour": value => { if (/^#[0-9a-f]{6}$/i.test(value)) App.edit(() => { r.colour = value; }, {rebuild:false}); },
        "slider:text-size": live((_sc,v) => { r.textSize = v; }, v => shown("text-size", `${v}×`)),
        "slider:text-angle": live((_sc,v) => { r.textAngle = v; }, v => shown("text-angle", `${v}°`)),
        "slider:annotation-width": live((_sc,v) => { r.width = v; }, v => shown("annotation-width", `${v.toFixed(2)} м`)),
        "reset-angle": () => App.edit(() => { r.textAngle = 0; }, {rebuild:false}),
        "annotation-reverse": () => App.edit(() => { r.points.reverse(); }, {rebuild:false}),
        rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
      });
      return;
    }
    if (r.kind === "choice") {
      const used = s.routes.filter((x) => x.kind === "choice" && x !== r).map((x) => x.label);
      const letterOnly = r.display === "letter";
      const hasPath = r.points?.length >= 2;
      const ways = s.routes.filter((x) => x.kind === "manoeuvre");
      const letters = chips("label", Catalog.LETTERS.map(l => ({value:l,html:`<span class="letter-badge sm" style="--c:${Catalog.LETTER_COLOUR[l]}">${l}</span>`,disabled:used.includes(l)})), r.label);
      const displays = [{value:"arrow",title:"Стрелка",html:AnswerMark.picture("answer",r.label)},{value:"line",title:"Линия",html:AnswerMark.picture("line",r.label)},{value:"letter",title:"Буква",html:AnswerMark.picture("letter",r.label)}];
      p.innerHTML = `${head(`<span class="letter-badge" style="--c:${Catalog.LETTER_COLOUR[r.label]}">${esc(r.label)}</span>`, "Вариант ответа")}
        ${card("", `<div class="path-property"><span>Метка</span>${letters}</div>
          ${chips("answer-display", displays, letterOnly ? "letter" : r.arrowhead === false ? "line" : "arrow", {cls:"answer-display"})}`, {cls:"path-sheet"})}
        ${!letterOnly && ways.length ? card("Взять траекторию", chips("copy", ways.map(w => ({value:w.exit,icon:Catalog.EXITS[w.exit].icon,tip:Catalog.EXITS[w.exit].title})), "", {cls:"arrows"}), {cls:"path-sheet"}) : ""}
        ${letterOnly ? card("", `<div class="path-coordinates">${["X","Z"].map((axis,i) => `<label>${axis}, м<input type="number" step="0.1" data-text="letter${axis}" value="${r3(r.labelPosition[i])}"></label>`).join("")}</div>`, {cls:"path-sheet"})
          : card("", `<div class="path-actions">${button("mid", "Букву в центр", "flag", "ghost")}${button("as-annotation", "Убрать букву", "measure", "ghost")}</div>`, {cls:"path-sheet"})}
        ${card("", button("del", "Удалить вариант", "trash", "danger ghost wide"), {cls:"path-sheet"})}`;
      bind({
        ...common,
        'as-annotation':()=>{
          if(App.isLocked(ref))return;
          const made=App.edit(sc=>{
            const id=App.uniqueId('annotation_',sc.routes.map(route=>route.id));
            Object.assign(r,{id,kind:'annotation',style:r.arrowhead===false?'line':'arrow',colour:Catalog.LETTER_COLOUR[r.label] || '#20242b',width:.16});
            delete r.label;delete r.labelPosition;delete r.arrowhead;delete r.auto;
            return {t:'route',id};
          });
          App.select(made);
        },
        "chip:label": v => {
          if (App.isLocked(ref) || !AnswerMark.free(s, r).includes(v)) return;
          App.edit(() => { r.label = v; r.id = `choice_${v}`; }); App.select({t:"route",id:r.id});
        },
        "chip:answer-display": v => {
          if (App.isLocked(ref)) return;
          if (v !== "letter" && !hasPath) return Tools.drawAnswerRoute(r.id, v === "arrow");
          App.edit(() => {
            if (v === "letter") { r.labelPosition = [...AnswerMark.position(r)]; r.display = "letter"; }
            else { delete r.display; if (v === "line") r.arrowhead = false; else delete r.arrowhead; }
          });
          App.select({t:"route",id:r.id});
        },
        "text:letterX": v => { if (!App.isLocked(ref) && v.trim() && Number.isFinite(Number(v))) App.edit(() => {r.labelPosition[0] = r3(Number(v));}, {rebuild:false}); },
        "text:letterZ": v => { if (!App.isLocked(ref) && v.trim() && Number.isFinite(Number(v))) App.edit(() => {r.labelPosition[1] = r3(Number(v));}, {rebuild:false}); },
        "chip:copy": (v) => App.edit((sc) => { const w = sc.routes.find((x) => x.kind === "manoeuvre" && x.exit === v); r.points = JSON.parse(JSON.stringify(w.points)); const m = r.points[Math.floor(r.points.length * 0.6)]; r.labelPosition = [m[0], m[1]]; }),
        mid: () => App.edit(() => { r.labelPosition = Layout.along(r.points, Layout.polyLen(r.points) / 2).p.map(r3); }, {rebuild:false}),
      });
      return;
    }
    if (r.kind === "manoeuvre") {
      const points = playerRoutePointTools(ref, r);
      const main = s.question.maneuver === r.exit;
      const guideVisible = s.question?.showPlayerGuide !== false;
      const manual = !!r.manual || !r.auto;
      p.innerHTML = `${head(`<span class="ibadge">${ic(Catalog.EXITS[r.exit]?.icon || "route")}</span>`, `Манёвр · ${Catalog.EXITS[r.exit]?.title.toLowerCase()}`, main ? "Едет игрок" : "")}
        ${main ? "" : card("", button("make-main", "Назначить игроку", "flag", "ghost wide"), {cls:"path-sheet"})}
        ${guideVisible ? pathMode(manual, !!s.layout, r.points.length) + points.html : ""}
        ${playerGuideCard(s.question)}`;
      bind({
        ...points.handlers,
        ...playerGuideHandlers,
        "make-main": () => App.edit((sc) => { sc.question.maneuver = r.exit; sc.spec = { ...(sc.spec || {}), maneuver: r.exit }; }),
        "own-path": () => { App.select({t:"route",id:r.id}); App.edit(sc => Layout.setPlayerRouteManual(sc, sc.routes.find(x => x.id === r.id), true)); },
        "auto-path": () => { App.select({t:"route",id:r.id}); App.edit(sc => Layout.setPlayerRouteManual(sc, sc.routes.find(x => x.id === r.id), false)); },
      });
      return;
    }
    if (r.kind === "actor") {
      const actor = s.actors.find((a) => a.route === r.id || `actor_${a.id}` === r.id);
      const isManual = !!r.manual;
      p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, "Путь участника")}
        ${pathMode(isManual, true, r.points.length)}
        ${card("", `<div class="path-actions">${actor ? button("actor", actor.name || Catalog.ACTORS[actor.type]?.name || "Участник", "car", "ghost") : ""}${button("del", "Удалить путь", "trash", "danger ghost")}</div>`, {cls:"path-sheet"})}`;
      bind({
        actor: () => actor && App.select({ t: "actor", id: actor.id }),
        "own-path": () => App.edit((sc) => { const x = sc.routes.find((y) => y.id === r.id); if (x) { x.manual = true; delete x.auto; } }),
        "auto-path": () => App.edit((sc) => { const x = sc.routes.find((y) => y.id === r.id); if (x) { delete x.manual; x.auto = true; } }),
        del: () => App.remove(),
      });
      return;
    }
    p.innerHTML = head(`<span class="ibadge">${ic("route")}</span>`, App.nameOf(ref));
    bind({});
  }

  // ---- markings and shapes -------------------------------------------------------------------
  function markingInspector(p, ref, m) {
    const paint = m.type === "paint", arrow = m.type === "arrow", bus = m.type === "bus_stop";
    const busValue = key => key === "length" ? BusStopMark.length(m) : m[key] ?? BusStopMark.defaults[key];
    const busSize = (key,title) => {
      const [min,max,step]=BusStopMark.limits[key], value=Number(busValue(key).toFixed(2));
      return `<div class="bus-stop-size"><label ${key === "step" ? 'title="Шаг равномерно подгоняется под длину"' : ""}>${title}<span><input type="number" min="${min}" max="${max}" step="${step}" data-text="bus-${key}" aria-label="${title}, м" value="${value}"> м</span></label><input type="range" min="${min}" max="${max}" step="${step}" data-slider="bus-${key}" aria-label="${title}" value="${value}"></div>`;
    };
    const setBusSize = (key,value) => { if(key === "length") BusStopMark.setLength(m,value); else m[key]=value; };
    const typeOptions = paint ? "" : chips("type", Object.entries(Catalog.MARKS).map(([k,v]) => ({value:k,html:k === "bus_stop" ? BusStopMark.svg() : k === "arrow" ? DirectionMark.svg() : `<span class="mark-pic m-${k}"></span>`,tip:v.title})),m.type,{cls:"path-marks"});
    const arrowLength = arrow && m.points?.length === 2 ? Math.hypot(m.points[1][0] - m.points[0][0], m.points[1][1] - m.points[0][1]) : 6;
    p.innerHTML = `${head(`<span class="ibadge">${bus ? BusStopMark.svg() : ic("marking")}</span>`, App.nameOf(ref), paint ? "снята с картинки билета" : "")}
      ${paint ? "" : card("Разметка", typeOptions, {cls:"path-sheet"})}
      ${bus ? card("Размеры остановки", `<div class="path-sizes">${busSize("length","Длина")}${busSize("depth","Глубина зубцов")}${busSize("step","Шаг зубцов")}${busSize("width","Толщина линии")}</div>`
        + `<div class="bus-stop-summary"><span data-bus-count>${BusStopMark.label(m)}</span>${button("bus-side", "На другую сторону", "measure", "ghost")}</div>`, {cls:"path-sheet"}) : ""}
      ${arrow ? card("Направления по полосе", chips("mark-direction", DirectionMark.variants.map(([value, title]) => ({value, tip:title, html: DirectionMark.svg(value)})), m.direction || "straight", {cls:"path-directions"}), {cls:"path-sheet"})
        + card("", slider("mark-length", "Длина", arrowLength, 1, 30, .5, `${arrowLength.toFixed(1)} м`)
          + slider("mark-width", "Ширина", m.width ?? 2.6, .4, 6, .1, `${(m.width ?? 2.6).toFixed(1)} м`)
          + button("mark-flip", "Развернуть на 180°", "rotr", "ghost wide"), {cls:"path-sheet"}) : ""}
      ${m.type === "stop" ? card("Вид линии", chips("stop-style", stopStyles, m.stopStyle || "solid")
        + (m.stopStyle === "yield" ? button("yield-flip", "Развернуть треугольники", "rotr", "ghost wide") : "")) : ""}
      ${bus ? "" : card("Цвет", chips("colour", [{ value: "white", html: `<span class="paint w"></span>`, title: "Белая" }, { value: "yellow", html: `<span class="paint y"></span>`, title: "Жёлтая" }], m.colour || "white"), {cls:"path-inline"})}
      ${m.type === "solid" || m.type === "dashed" ? card("Вторая линия рядом", chips("double", [{ value: "", title: "Нет" }, { value: "solid", html: `<span class="mark-pic m-solid"></span>`, tip: "Сплошная" }, { value: "dashed", html: `<span class="mark-pic m-dashed"></span>`, tip: "Прерывистая" }], m.double || "", { cls: "tiles" })
        + (m.double ? button("flip", "На другую сторону", "rotr", "ghost wide") : "")
        + (ref.v !== undefined && ref.v > 0 && ref.v < m.points.length - 1 ? button("split", "Разрезать в точке", "marking", "ghost wide") : "")) : ""}
      ${card("", `<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div>${deleteRow()}`)}`;
    bind({
      ...common,
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
      ...Object.fromEntries((bus ? Object.keys(BusStopMark.limits) : []).flatMap(key => [
        ["slider:bus-"+key,live((_sc,value) => { if(!App.isLocked(ref))setBusSize(key,value); },value => {
          const input=p.querySelector(`[data-text="bus-${key}"]`); if(input)input.value=Number(value.toFixed(2));
          const count=p.querySelector('[data-bus-count]'); if(count)count.textContent=`${BusStopMark.label(m)}`;
        })],
        ["text:bus-"+key,raw => {
          if(App.isLocked(ref))return;
          const value=Number(raw),[min,max]=BusStopMark.limits[key];
          if(!raw.trim() || !Number.isFinite(value) || value<min || value>max) { App.toast(`Введите значение от ${min} до ${max} м`,"warn");App.renderInspector();return; }
          App.edit(()=>setBusSize(key,value));
        }],
      ])),
      "bus-side": () => { if(!App.isLocked(ref))App.edit(()=>{m.side=-(m.side ?? 1);}); },
      "chip:type": (v) => { if(App.isLocked(ref))return; App.edit(() => {
        m.type = v;
        if (["stop", "zebra", "arrow"].includes(v) && m.points) m.points = m.points.slice(0, 2);
        if (v === "zebra") m.length = m.length || 4; else delete m.length;
        if (v === "stop") m.width = 0.4; else delete m.width;
        if (v === "arrow") { m.direction = m.direction || "straight"; m.width = 2.6; }
        else delete m.direction;
        if (v !== "stop") delete m.stopStyle;
        if (v === "bus_stop") {
          m.points=[m.points[0],m.points.at(-1)];
          Object.assign(m,BusStopMark.defaults); m.colour="yellow";
          BusStopMark.setLength(m,Math.max(2,Math.min(60,BusStopMark.length(m))));
          m.side=BusStopMark.chooseSide(state.S,m); delete m.double;
        } else { delete m.depth;delete m.step;delete m.side; }
      }); },
      "chip:stop-style": v => {
        if (!App.isLocked(ref) && stopStyles.some(style => style.value === v)) App.edit(() => setStopStyle(m, v));
      },
      "chip:mark-direction": value => { if (!App.isLocked(ref)) App.edit(() => { m.direction = value; }); },
      "slider:mark-length": live((_sc, value) => {
        if (App.isLocked(ref) || !m.points?.[1]) return;
        const [a,b] = m.points, length = Math.hypot(b[0]-a[0],b[1]-a[1]) || 1;
        m.points[1] = [r3(a[0]+(b[0]-a[0])/length*value),r3(a[1]+(b[1]-a[1])/length*value)];
      }, value => { const label = p.querySelector('[data-shown="mark-length"]'); if (label) label.textContent = `${value.toFixed(1)} м`; }),
      "slider:mark-width": live((_sc, value) => { if (!App.isLocked(ref)) m.width = value; }, value => { const label = p.querySelector('[data-shown="mark-width"]'); if (label) label.textContent = `${value.toFixed(1)} м`; }),
      "mark-flip": () => { if (!App.isLocked(ref)) App.rotate(180); },
      "yield-flip": () => { if (!App.isLocked(ref)) App.edit(() => { m.points.reverse(); }); },
      "chip:colour": (v) => App.edit(() => { m.colour = v; }),
      "chip:double": (v) => App.edit(() => { if (v) { m.double = v; m.side = m.side || 1; } else { delete m.double; delete m.side; } }),
      flip: () => App.edit(() => { m.side = -(m.side || 1); }),
      split: () => {
        const at = ref.v;
        const ref2 = App.edit((sc) => {
          const id = App.uniqueId("mark_", sc.markings.map((x) => x.id));
          const rest = { ...JSON.parse(JSON.stringify(m)), id, points: m.points.slice(at) };
          m.points = m.points.slice(0, at + 1);
          sc.markings.push(rest);
          return { t: "marking", id };
        });
        App.select(ref2);
      },
    });
  }
  function shapeInspector(p, ref, o) {
    const title = App.nameOf(ref);
    p.innerHTML = `${head(`<span class="ibadge">${ic(ref.t === "lawn" ? "lawn" : "road")}</span>`, title)}
      ${card("", propertyRow("Поворот", `<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div>`))}
      ${ref.t === "road" && !state.S.layout ? card("", button("convert", "Перевести в конструктор", "road", "ghost wide")) : ""}
      ${card("", ref.t === "road" ? button("del", "Удалить", "trash", "danger ghost wide") : deleteRow())}`;
    bind({ ...common, rotl: () => App.rotate(-15), rotr: () => App.rotate(15), convert: () => Tools.convertScene() });
  }

  function shiftPlayerLateral(sc, delta) {
    if (!sc.stop) return;
    const yaw = sc.stop.yaw || 0;
    const rDir = [-Math.cos(yaw), Math.sin(yaw)];
    const dx = rDir[0] * delta, dz = rDir[1] * delta;
    sc.stop.x = r3(sc.stop.x + dx);
    sc.stop.z = r3(sc.stop.z + dz);
    const ap = (sc.routes || []).find((r) => r.id === "approach");
    if (ap && ap.points) ap.points = ap.points.map((p) => [r3(p[0] + dx), r3(p[1] + dz)]);
    for (const r of sc.routes || []) {
      if (r.kind === "guide") r.points = r.points.map(p => [r3(p[0] + dx), r3(p[1] + dz)]);
      if (r.kind === "manoeuvre" && r.points && r.points.length) {
        r.points[0] = [sc.stop.x, sc.stop.z];
      }
    }
  }

  function stopInspector(p) {
    const s = state.S, q = s.question;
    const routes = s.routes.filter((r) => r.kind === "manoeuvre").map((r) => r.exit);
    const plan = s.layout ? Layout.playerPlan(s) : null;
    const free = Layout.isFreePlayer(s), pose = Layout.playerPose(s);
    const lanes = plan && !Layout.isFreePlayer(s) ? (plan.lanes || Layout.laneOffsets(plan.st)) : [];
    const laneItems = lanes.length === 2
      ? [{ value: 0, title: "Левая" }, { value: 1, title: "Правая" }]
      : lanes.length === 3
        ? [{ value: 0, title: "Левая" }, { value: 1, title: "Средняя" }, { value: 2, title: "Правая" }]
        : lanes.map((_, i) => ({ value: i, title: i === 0 ? "1 (левая)" : i === lanes.length - 1 ? `${i + 1} (правая)` : `${i + 1}` }));
    const curLane = plan ? plan.laneIndex : 0;

    const maneuver = chips("maneuver", ["left", "straight", "right", "uturn"].map(k => ({value:k,icon:Catalog.EXITS[k].icon,tip:Catalog.EXITS[k].title,disabled:!routes.includes(k) && k !== "straight"})), q.maneuver, {cls:"arrows"});
    const placement = chips("playerMode", [{value:"street",title:"По улице"},{value:"free",title:"Свободно"}], free ? "free" : "street");
    const distance = plan && !free ? Math.max(0, plan.sd - plan.stopLineDistance - 2.4) : 0;
    p.innerHTML = `${head(`<span class="ibadge">${ic("car")}</span>`, "Игрок")}
      ${card("Манёвр", maneuver, {cls:"path-inline"})}
      ${s.layout ? card("Привязка", placement, {cls:"path-inline"}) : ""}
      ${free ? card("", `<div class="path-coordinates">${[["X, м","playerX",pose.x,.1],["Z, м","playerZ",pose.z,.1],["Угол, °","playerYaw",r3(pose.yaw*180/Math.PI),1]].map(([label,key,v,step])=>`<label>${label}<input type="number" step="${step}" data-text="${key}" value="${v}"></label>`).join("")}</div>
        <div class="turn-row">${dial(pose.yaw)}<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rot90", "90°", "", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div></div>`, {cls:"path-sheet"}) : ""}
      ${lanes.length > 1 ? card("Полоса", chips("lane", laneItems, curLane), {cls:"path-inline"}) : ""}
      ${plan && !free ? card("", slider("questionOffset", "До стоп-линии", distance, 0, Math.min(60, Math.max(0, plan.total - plan.stopLineDistance - 3.4)), .5, `${distance.toFixed(1)} м`)
        + `<button class="btn ghost path-reset" data-act="question-at-line" title="Вернуть к стоп-линии" aria-label="Вернуть к стоп-линии">${ic("restart")}</button>`, {cls:"path-inline path-offset"}) : ""}
      ${!s.layout ? card("Сдвиг на 3,5 м", `<div class="path-actions">${button("shift-left", "Влево", "arrow-left", "ghost")}${button("shift-right", "Вправо", "arrow-right", "ghost")}</div>`, {cls:"path-inline"}) : ""}
      ${s.id !== "mini_regulator" ? playerGuideCard(q) : ""}`;
    const moveFree = (axis, value) => App.edit(sc => { const at = Layout.playerPose(sc), number = Number(value); if (!Number.isFinite(number)) return; at[axis] = number; if (!Layout.movePlayer(sc, [at.x, at.z])) App.toast("Весь автомобиль должен оставаться на проезжей части"); });
    const turnFree = angle => App.edit(sc => { if (!Layout.rotatePlayer(sc, angle)) App.toast("После поворота автомобиль выходит за край дороги"); });
    bind({
      ...playerGuideHandlers,
      "chip:playerMode": (v) => App.edit(sc => Layout.setPlayerMode(sc, v)),
      "text:playerX": (v) => moveFree("x", v),
      "text:playerZ": (v) => moveFree("z", v),
      "text:playerYaw": (v) => { if (Number.isFinite(Number(v))) turnFree(Number(v) * Math.PI / 180); },
      rotl: () => turnFree(Layout.playerPose(state.S).yaw - Math.PI / 12),
      rotr: () => turnFree(Layout.playerPose(state.S).yaw + Math.PI / 12),
      rot90: () => turnFree(Layout.playerPose(state.S).yaw + Math.PI / 2),
      "chip:maneuver": (v) => App.edit((sc) => { sc.question.maneuver = v; sc.spec = { ...(sc.spec || {}), maneuver: v }; }),
      "chip:lane": (v) => App.edit((sc) => {
        const pl = Layout.playerPlan(sc);
        sc.layout.player = {
          ...(sc.layout.player || {}),
          street: pl ? pl.st.id : sc.layout?.player?.street,
          toward: pl ? pl.nid : sc.layout?.player?.toward,
          lane: Number(v),
        };
      }),
      "slider:questionOffset": live((sc, v) => { const pl = Layout.playerPlan(sc); sc.layout.player = { ...(sc.layout.player || {}), street: pl.st.id, toward: pl.nid, questionAt: r3(pl.stopLineDistance + 2.4 + v) }; }, v => { const el = pane().querySelector('[data-shown="questionOffset"]'); if (el) el.textContent = `${v.toFixed(1)} м`; }),
      "question-at-line": () => App.edit(sc => { if (sc.layout.player) delete sc.layout.player.questionAt; }),
      "shift-left": () => App.edit((sc) => shiftPlayerLateral(sc, -3.5)),
      "shift-right": () => App.edit((sc) => shiftPlayerLateral(sc, 3.5)),
    });
    if (free) bindDial(p, pose, (sc, yaw) => Layout.rotatePlayer(sc, yaw));
  }

  // ---- a texture -----------------------------------------------------------------------------
  function textureInspector(p) {
    const kind = state.texSel, info = Textures.INFO[kind] || { name: kind };
    const d = Textures.draftOf(kind), meta = Textures.metaOf(kind);
    const styles = TexGen.styles(kind);
    const shown = (key, v) => key === "period" ? `${v.toFixed(1)} м` : key === "macroScale" ? `${(1 / v).toFixed(1)}×` : `${Math.round(v / Textures.PARAMS[key].max * 100)}%`;
    p.innerHTML = `${head(`<span class="ibadge">${ic("tiles")}</span>`, info.name)}
      ${card("", `<canvas id="tex-preview" class="tex-preview" width="320" height="94" role="img" aria-label="Предпросмотр текстуры"></canvas>
        <div class="style-grid">${styles.map(st => `<button class="style ${Textures.pendingStyle(kind) === st.id ? "on" : ""}" data-act="style" data-style="${st.id}" aria-pressed="${Textures.pendingStyle(kind) === st.id}"><canvas width="48" height="48" data-style-pic="${st.id}"></canvas><span>${esc(st.title)}</span></button>`).join("")}</div>`, {cls:"texture-samples"})}
      ${card("", slider("gain", "Зерно", d.gain, 0, Textures.PARAMS.gain.max, 0.1, shown("gain", d.gain))
        + slider("macro", "Пятна", d.macro, 0, Textures.PARAMS.macro.max, 0.01, shown("macro", d.macro))
        + (d.period !== undefined ? slider("period", "Размер рисунка", d.period, 1, 16, 0.2, shown("period", d.period)) : ""))}
      ${card("", `<button class="texture-upload" data-act="upload">${ic("upload")}Загрузить PNG<small>256 × 256</small></button>
        ${meta.backups ? button("restore", "Вернуть предыдущую текстуру", "undo", "ghost wide") : ""}`)}
      ${card("", `<div class="insp-actions">${button("reset", "Сбросить", "restart", "ghost")}${button("apply", "Применить в игре", "check-circle", "primary")}</div>`)}`;
    drawPreview();
    styles.forEach((st) => {
      const c = p.querySelector(`[data-style-pic="${st.id}"]`);
      if (c) Textures.drawStyle(c, kind, st.id);
    });
    const setP = (key) => (v, done) => {
      Textures.setParam(kind, key, v);
      p.querySelector(`[data-shown="${key}"]`).textContent = shown(key, v);
      Scene3D.setTextures(Textures.forScene());
      drawPreview();
      if (done) App.renderPanels({ only: ["left"] });
    };
    bind({
      "slider:gain": setP("gain"), "slider:macro": setP("macro"), "slider:period": setP("period"),
      style: (dd) => { Textures.useStyle(kind, dd.style); afterPicture(kind); App.renderInspector(); },
      upload: () => $("#file").click(),
      restore: async () => { await Textures.restore(kind); afterPicture(kind); App.renderInspector(); },
      reset: () => { Textures.reset(kind); afterPicture(kind); App.renderInspector(); },
      apply: async () => { await Textures.save(kind); App.renderPanels(); },
    });
    function drawPreview() {
      const c = p.querySelector("#tex-preview");
      if (c) Textures.drawScene(c, kind);
    }
  }
  function afterPicture(kind) {
    Scene3D.setTextures(Textures.forScene());
    Scene3D.reloadPicture(kind, Textures.pictureUrl(kind));
    App.renderPanels({ only: ["left"] });
  }
  App.afterTexturePicture = afterPicture;

  // A PNG for the texture: chosen or dropped on the panel.
  $("#file").addEventListener("change", async (e) => {
    const f = e.target.files[0];
    e.target.value = "";
    if (f && state.texSel) { await Textures.usePng(state.texSel, f); afterPicture(state.texSel); App.renderInspector(); }
  });
  const ins = pane();
  ins.addEventListener("dragover", (e) => { if (state.texSel && e.dataTransfer.types.includes("Files")) { e.preventDefault(); ins.classList.add("dropping"); } });
  ins.addEventListener("dragleave", () => ins.classList.remove("dropping"));
  ins.addEventListener("drop", async (e) => {
    ins.classList.remove("dropping");
    const f = [...(e.dataTransfer.files || [])].find((x) => x.type === "image/png");
    if (!f || !state.texSel) return;
    e.preventDefault();
    await Textures.usePng(state.texSel, f);
    afterPicture(state.texSel);
    App.renderInspector();
  });
})();
