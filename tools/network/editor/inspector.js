// The right side: what the selection is and how it can be changed, with pictures and switches instead
// of number fields. Nothing selected: the scene itself (its question, what the player does, checks,
// whether it is in the game). A texture chosen on the left: the texture.
(() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, state, r3 } = App;
  const pane = () => $("#inspector");

  // ---- small builders -----------------------------------------------------------------------
  const card = (title, body, opts = {}) => `<section class="card ${opts.cls || ""}">${title ? `<h3>${opts.icon ? ic(opts.icon) : ""}${title}${opts.aside || ""}</h3>` : ""}${body}</section>`;
  const chips = (name, items, value, opts = {}) => `<div class="seg-chips ${opts.cls || ""}">${items.map((it) =>
    `<button class="${String(it.value) === String(value) ? "on" : ""} ${it.disabled ? "off" : ""}" data-chip="${name}" data-value="${esc(it.value)}" aria-label="${esc(it.tip || it.title || it.value)}" aria-pressed="${String(it.value) === String(value)}" ${it.disabled ? "disabled" : ""} ${it.tip ? `data-tip="${esc(it.tip)}"` : ""}>${it.icon ? ic(it.icon) : ""}${it.html || ""}${it.title ? `<span>${esc(it.title)}</span>` : ""}</button>`).join("")}</div>`;
  const toggle = (name, label, on, icon) => `<label class="switch-row">${icon ? ic(icon) : ""}<span>${esc(label)}</span><input type="checkbox" data-toggle="${name}" ${on ? "checked" : ""}><i class="switch"></i></label>`;
  const button = (act, label, icon, cls = "") => `<button class="btn ${cls}" data-act="${act}">${icon ? ic(icon) : ""}<span>${esc(label)}</span></button>`;
  const slider = (name, label, value, min, max, step, shown) => `<div class="slider-row"><div class="slider-h"><span>${esc(label)}</span><em data-shown="${name}">${esc(shown)}</em></div>
    <input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-slider="${name}"></div>`;
  const stopStyles = [{ value: "solid", title: "Сплошная", icon: "stopline" }, { value: "yield", title: "Треугольники", icon: "yieldline" }];
  const setStopStyle = (item, value) => {
    if (value === "yield") item.stopStyle = "yield";
    else delete item.stopStyle;
  };

  function compactHelp(p) {
    p.querySelectorAll(".info-help, p.muted").forEach(text => text.remove());
    p.querySelectorAll(".card").forEach(section => {
      if (!section.querySelector("button, input, select, canvas, svg, .edges, p, .slider-row")) section.remove();
    });
  }

  let handlers = {};
  function bind(h) {
    handlers = h;
  }
  pane().addEventListener("click", (e) => {
    const c = e.target.closest("[data-chip]");
    if (c && handlers["chip:" + c.dataset.chip]) return handlers["chip:" + c.dataset.chip](c.dataset.value, e);
    const a = e.target.closest("[data-act]");
    if (a && handlers[a.dataset.act]) return handlers[a.dataset.act](a.dataset, e);
  });
  pane().addEventListener("change", (e) => {
    const t = e.target.closest("[data-toggle]");
    if (t && handlers["toggle:" + t.dataset.toggle]) return handlers["toggle:" + t.dataset.toggle](t.checked);
    const sl = e.target.closest("[data-slider]");
    if (sl && handlers["slider:" + sl.dataset.slider]) return handlers["slider:" + sl.dataset.slider](Number(sl.value), true);
    const tx = e.target.closest("[data-text]");
    if (tx && handlers["text:" + tx.dataset.text]) return handlers["text:" + tx.dataset.text](tx.value);
  });
  pane().addEventListener("input", (e) => {
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
  App.renderInspector = () => {
    const p = pane();
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
    compactHelp(p);
    Thumbs.fillAll(p);
  };
  App.renderSelection = () => {};
  App.showChecks = () => { App.select([]); setTimeout(() => $("#checks")?.scrollIntoView({ behavior: "smooth" }), 30); };

  const head = (icon, title, sub = "") => `<div class="insp-head">${icon}<div><b>${esc(title)}</b>${sub ? `<small>${esc(sub)}</small>` : ""}</div></div>`;
  const deleteRow = (extra = "") => `<div class="insp-actions">${extra}${button("dup", "Копия", "copy", "ghost")}${button("del", "Удалить", "trash", "danger ghost")}</div>`;
  const common = { dup: () => App.duplicate(), del: () => App.remove() };

  function playerGuideCard(question) {
    const hidden = question?.showPlayerGuide === false;
    return card("Синяя стрелка игрока", `<p${hidden ? ' class="ok-line"' : ""}>${hidden ? "Скрыта в этой сцене" : "Включена в этой сцене"}</p>
      ${button("player-guide", hidden ? "Вернуть синюю стрелку" : "Убрать синюю стрелку", hidden ? "eye" : "trash", "ghost wide")}
      ${!hidden ? button("player-path", "Править путь игрока", "route", "ghost wide") : ""}
      <p class="muted">Машина проедет тем же путём после ответа.</p>`);
  }
  const togglePlayerGuide = () => App.setPlayerGuideVisible(state.S.question?.showPlayerGuide === false);
  const playerGuideHandlers = {"player-guide": togglePlayerGuide, "player-path": () => App.selectPlayerPath()};

  // ---- the scene ----------------------------------------------------------------------------
  function regulatorInspector(p) {
    const s = state.S;
    p.innerHTML = `${head(`<span class="ibadge">${ic("person")}</span>`, "Регулировщик", "сцена мини-игры")}
      ${card("Проверить", button("regulator-run", "Тест в игре", "play", "primary wide"))}
      ${card("Сцена", `<p>Выбирайте дороги, линии разметки, дома и деревья прямо на виде. Объекты можно двигать, поворачивать, добавлять и удалять.</p>${button("regulator-officer", "Положение регулировщика", "person", "ghost wide")}${button("regulator-player", "Автомобиль игрока", "car", "ghost wide")}`)}
      ${card("Пути игрока", regulatorRouteButtons(s) + `<p>Выберите путь, затем тяните его точки на виде или задавайте координаты справа.</p>`)}
      ${card("Сохранение", `<p>«Сохранить» обновляет сцену и её поверхности для игры. «Тест в игре» сохраняет изменения и запускает мини-игру в Godot.</p>`)}
      ${card("Проверка", state.findings.length ? state.findings.map(f => `<p class="${f.level}">${esc(f.message)}</p>`).join("") : `<p class="ok-line">${ic("check-circle")}Ошибок нет</p>`)}`;
    compactHelp(p);
    bind({
      "regulator-run": () => App.runInGame(false),
      "regulator-officer": () => s.officers[0] && App.select({t:"officer", id:s.officers[0].id}),
      "regulator-player": () => App.select({t:"stop"}),
      "regulator-route": d => App.select({t:"route",id:d.id}),
    });
  }

  function regulatorRouteButtons(s, selected) {
    return `<div class="insp-actions">${s.routes.filter(r => ["approach", "manoeuvre"].includes(r.kind)).map(r => {
      const title = r.kind === "approach" ? "Подъезд" : Catalog.EXITS[r.exit].title;
      const icon = r.kind === "approach" ? "route" : Catalog.EXITS[r.exit].icon;
      return `<button class="btn ${r.id === selected ? "primary" : "ghost"}" data-act="regulator-route" data-id="${esc(r.id)}">${ic(icon)}<span>${esc(title)}</span></button>`;
    }).join("")}</div>`;
  }

  function regulatorRouteInspector(p, ref, r) {
    const index = Number.isInteger(ref.v) ? ref.v : 0;
    const point = r.points[index];
    const anchored = r.kind === "manoeuvre" ? index === 0 : index === r.points.length - 1;
    const title = r.kind === "approach" ? "Подъезд" : Catalog.EXITS[r.exit].title;
    p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, `Путь игрока: ${title.toLowerCase()}`, `${r.points.length} точек`)}
      ${card("Пути игрока", regulatorRouteButtons(state.S, r.id))}
      ${card("Редактирование", `<p>Тяните точки на виде. Двойной клик по линии добавляет точку. Выбранную точку можно удалить кнопкой ниже или клавишей Delete.</p><label class="route-field">Точка<input type="number" min="1" max="${r.points.length}" step="1" data-text="routeIndex" value="${index + 1}"></label>
        <label class="route-field">X, м<input type="number" step="0.1" data-text="routeX" value="${Number(point[0].toFixed(3))}" ${anchored ? "disabled" : ""}></label>
        <label class="route-field">Z, м<input type="number" step="0.1" data-text="routeZ" value="${Number(point[1].toFixed(3))}" ${anchored ? "disabled" : ""}></label>
        ${anchored ? `<p>Эта точка закреплена у автомобиля игрока. Чтобы изменить её, переместите автомобиль.</p>` : button("route-delete-point", "Удалить точку", "trash", "ghost wide")}
        ${index < r.points.length - 1 ? button("route-add-point", "Добавить точку после выбранной", "points", "ghost wide") : ""}`)}
      ${card("Проверить", `<p>После правки убедитесь, что путь проходит по проезжей части. «Сохранить» сохраняет траекторию для игры.</p>${button("regulator-run", "Тест в игре", "play", "primary wide")}`)}`;
    bind({
      "regulator-route": d => App.select({t:"route", id:d.id}),
      "regulator-run": () => App.runInGame(false),
      "text:routeIndex": v => { const i = Number(v) - 1; if (Number.isInteger(i) && i >= 0 && i < r.points.length) App.select({t:"route", id:r.id, v:i}); },
      ...Object.fromEntries(["routeX", "routeZ"].map((key, axis) => [`text:${key}`, v => {
        if (anchored || !v.trim() || !Number.isFinite(Number(v))) return;
        App.edit(() => { Layout.editPlayerRoute(state.S, r); r.points[index][axis] = r3(Number(v)); });
      }])),
      "route-delete-point": () => { App.select({t:"route", id:r.id, v:index}); App.remove(); },
      "route-add-point": () => {
        App.edit(() => { Layout.editPlayerRoute(state.S, r); const next = r.points[index + 1]; r.points.splice(index + 1, 0, point.map((v, axis) => r3((v + next[axis]) / 2))); });
        App.select({t:"route", id:r.id, v:index + 1});
      },
    });
  }

  function sceneInspector(p) {
    if (state.id === "mini_regulator") return regulatorInspector(p);
    const s = state.S, q = s.question || {}, src = state.source, ru = (q.text && q.text.ru) || {};
    const routes = s.routes.filter((r) => r.kind === "manoeuvre").map((r) => r.exit);
    const errors = state.findings.filter((f) => f.level === "error"), warns = state.findings.filter((f) => f.level === "warn");
    const answers = src ? src.answers.map((a) => a.text) : ru.options || [];
    const correct = q.correct;
    const plan = s.layout ? Layout.playerPlan(s) : null;
    const lanes = plan && !Layout.isFreePlayer(s) ? (plan.lanes || Layout.laneOffsets(plan.st)) : [];
    const laneItems = lanes.length === 2
      ? [{ value: 0, title: "Левая" }, { value: 1, title: "Правая" }]
      : lanes.length === 3
        ? [{ value: 0, title: "Левая" }, { value: 1, title: "Средняя" }, { value: 2, title: "Правая" }]
        : lanes.map((_, i) => ({ value: i, title: i === 0 ? "1 (левая)" : i === lanes.length - 1 ? `${i + 1} (правая)` : `${i + 1}` }));
    const curLane = plan ? plan.laneIndex : 0;
    const yields = s.actors.map((a) => `<button class="pick ${(q.yieldTo || []).includes(a.id) ? "on" : ""}" data-act="yield" data-id="${a.id}">${Thumbs.img("actor", a.type, "mini")}<span>${esc(a.name || a.id)}</span></button>`).join("");
    const edges = state.edges || {};
    const edgeMismatch = Object.values(edges).some(e => e && !(e.connectable ?? e.street));
    const side = (k) => { const e = edges[k]; return e ? ((e.connectable ?? e.street) ? "ok" : "bad") : "none"; };
    const assistant = s.assistantReview?.author === "codex";
    const approved = assistant && s.assistantReview.status === "approved" && state.playable;
    p.innerHTML = `
      ${head(`<span class="ibadge">${ic("map")}</span>`, App.sceneTitle(state.id), s.layout ? "Дороги в конструкторе" : "Дороги из картинки билета")}
      ${assistant ? card("Подготовлено Codex", `<p class="assistant-review-status">${approved ? "Одобрено вами · сцена в игре" : "Ожидает вашего одобрения"}</p><p class="assistant-review-help">${approved ? "Можно редактировать сцену или снять одобрение и вернуть её на проверку." : "Проверьте вопрос и проезд. Все объекты и маршруты доступны для ручной правки. Сохранение и тест не добавляют сцену в игру."}</p>${button(approved ? "withdraw-approval" : "approve-scene", approved ? "Снять одобрение и убрать из игры" : "Одобрить и добавить в игру", approved ? "undo" : "check-circle", approved ? "ghost wide" : "primary wide")}`, { cls: "assistant-review-card" }) : ""}
      ${card("", `${assistant ? "" : toggle("playable", "Сцена в игре", state.playable, "gamepad")}
        <div class="insp-actions">${button("run", "Тест в игре", "play", "primary")}</div>
        ${button("run-auto", "В игре на автопилоте", "video", "ghost small wide")}`)}
      ${card("Игрок едет", `${chips("maneuver", ["left", "straight", "right", "uturn"].map((k) => ({ value: k, icon: Catalog.EXITS[k].icon, tip: Catalog.EXITS[k].title, disabled: k !== "straight" && !routes.includes(k) && !(s.layout) })), q.maneuver, { cls: "arrows" })}
        ${lanes.length > 1 ? `<div class="sub-h">Полоса</div>${chips("lane", laneItems, curLane, { cls: "tiles" })}` : ""}
        <div class="sub-h">Знак скорости</div>${chips("speed", [{ value: "", title: "Нет" }, ...[20, 40, 60].map((v) => ({ value: v, html: `<span class="speed-sign">${v}</span>` }))], q.speedLimit ?? "", { cls: "signs" })}
        <div class="sub-h">Ждать на красном</div>${chips("redWait", [{ value: "", title: "Нет" }, { value: 2, title: "2 с" }, { value: 5, title: "5 с" }], q.redWait ?? "")}
        ${s.actors.length ? `<div class="sub-h">Уступить дорогу</div><div class="picks">${yields}</div>` : ""}`, { icon: "flag" })}
      ${playerGuideCard(q)}
      ${card("Дороги", s.layout
        ? `${button("select-roads", "Выбрать все дороги", "road", "ghost wide")}${button("templates", "Готовые перекрёстки", "junction", "ghost wide")}`
        : `<p class="muted">Дороги сняты с картинки билета. В конструкторе их можно двигать и менять как в SimCity.</p>${button("convert", "Перевести в конструктор", "magic", "primary wide")}`, { icon: "road" })}
      ${card("Камера вопроса", `<p class="selection-status">${s.questionView ? "Свой кадр" : "Автоматический кадр"}</p>${button("frame", "Настроить кадр", "video", "primary wide")}`, { icon: "video" })}
      ${card("Края сцены", `<div class="edges"><span class="edge-box"><i class="e-n ${side("n")}"></i><i class="e-s ${side("s")}"></i><i class="e-e ${side("e")}"></i><i class="e-w ${side("w")}"></i>${ic("car")}</span>
        <p class="${edgeMismatch ? "warn" : "muted"}">${edgeMismatch ? "Проверьте ширину дороги у края сцены." : "Стыковка учитывает фактическое направление дороги, число полос, ширину и разделитель. Центрировать косые выезды не требуется."}</p></div>`, { icon: "edges" })}
      <section class="card" id="checks"><h3>${ic(errors.length ? "error" : "check-circle")}Проверка${errors.length + warns.length ? `<em class="count ${errors.length ? "bad" : "warn"}">${errors.length + warns.length}</em>` : ""}</h3>
        ${state.findings.length ? state.findings.map((f, i) => `<button class="finding ${f.level}" data-act="finding" data-i="${i}">${ic(f.level === "error" ? "error" : "alert")}<span>${esc(f.message)}</span></button>`).join("")
          : `<p class="ok-line">${ic("check-circle")}Ошибок нет</p>`}</section>
      `;
    compactHelp(p);
    Thumbs.fillAll(p);
    bind({
      ...selectionHandlers,
      "toggle:playable": (on) => App.setPlayable(on),
      "approve-scene": () => App.setPlayable(true),
      "withdraw-approval": () => App.setPlayable(false),
      ...playerGuideHandlers,
      run: () => App.runInGame(false),
      "run-auto": () => App.runInGame(true),
      correct: (d) => App.edit((sc) => { sc.question.correct = Number(d.i); }),
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
      "chip:redWait": (v) => App.edit((sc) => { if (v === "") delete sc.question.redWait; else sc.question.redWait = Number(v); }),
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
    : key === "median" ? Layout.medianOf(st) : st[key] !== false;
  function roadSettings(streets, prefix = "") {
    const val = key => shared(streets, st => roadValue(st,key));
    const field = (title,key,html) => `<div class="road-setting">${fieldTitle(title,val(key))}${html}</div>`;
    const binary = (name, value, icon) => chips(prefix+name,[{value:"true",title:"Да",icon},{value:"false",title:"Нет"}],value);
    const soil = streets.filter(st => st.surface === "sand").length;
    const manual = streets.filter(st => st.manualMarks).length;
    const median = streets.filter(st => Layout.medianOf(st) > 0).length;
    const count = n => streets.length > 1 ? ` · дорог: ${n}` : "";
    return card("Дорога", [
      field("Покрытие", "surface", chips(prefix+"surface", [{value:"asphalt",title:"Асфальт",html:'<span class="surface-preview asphalt"></span>'},{value:"sand",title:"Грунт",html:'<span class="surface-preview sand"></span>'}],val("surface"),{cls:"surface-choices"})),
      soil ? `<p class="selection-status">Грунт: без разметки и тротуаров${count(soil)}</p>` : "",
      field("Полосы и ширина", "kind", chips(prefix+"kind", Object.entries(Layout.KINDS).map(([key, info]) => ({value:key,title:info.title,html:roadPicture(key)+`<small>${key === "yard" ? "Узкий · 5 м" : key === "street" ? "2 полосы · 8,4 м" : key === "avenue" ? "4 полосы · 14 м" : "6 полос · разделитель"}</small>`})),val("kind"),{cls:"road-profiles"})),
      field("По центру", "centre", chips(prefix+"centre", [{value:"none",title:"Нет",html:'<span class="mark-pic m-none"></span>'},{value:"dashed",title:"Прерывистая",html:'<span class="mark-pic m-dashed"></span>'},{value:"solid",title:"Сплошная",html:'<span class="mark-pic m-solid"></span>'},{value:"double",title:"Двойная",html:'<span class="mark-pic m-double"></span>'}],val("centre"),{cls:"mark-choices"})),
      median ? `<p class="selection-status">По центру — разделитель${count(median)}</p>` : "",
      manual ? `<div class="road-setting"><p class="selection-status">Ручная разметка${count(manual)}</p>${button(prefix+"marks-auto","Вернуть авторазметку","restart","ghost wide")}</div>` : "",
      `<div class="road-setting road-binary">${fieldTitle("Боковая сплошная",val("edge"))}${binary("edge",val("edge"),"marking")}</div>`,
      `<div class="road-setting road-binary">${fieldTitle("Тротуары",val("walk"))}${binary("walk",val("walk"),"person")}</div>`,
    ].join(""),{cls:"road-settings"});
  }
  function roadHandlers(refs, prefix = "") {
    const handlers = {
      [prefix+"marks-auto"]: () => changeSelected(refs,"street",st => { delete st.manualMarks; }),
    };
    for (const key of ["surface","kind","centre","walk","edge"]) handlers["chip:"+prefix+key] = value => {
      if (key === "surface" && !["asphalt","sand"].includes(value)) return;
      if (key === "kind" && !Layout.KINDS[value]) return;
      if (key === "centre" && !["none","dashed","solid","double"].includes(value)) return;
      if (["walk","edge"].includes(key) && !["true","false"].includes(value)) return;
      changeSelected(refs,"street",st => { st[key] = ["walk","edge"].includes(key) ? value === "true" : value; });
    };
    return handlers;
  }

  function multiInspector(p) {
    const refs = [...state.sel], streets = selectedOf(refs,"street"), decor = selectedOf(refs,"decor"), actors = selectedOf(refs,"actor");
    const signalActors = actors.filter(actor => ActorSignals.supports(actor.type));
    const locked = refs.length - editableRefs(refs).length;
    const canRotate = refs.some(ref => ["decor","actor","sign","officer","light","marking","lawn","road","stop"].includes(ref.t));
    const canCopy = refs.some(ref => ["decor","actor","sign","officer","light","marking","lawn"].includes(ref.t));
    const tint = shared(decor,d => d.tint || null), scale = shared(decor,d => d.scale[0]);
    const speed = shared(actors,a => Catalog.speedOf(a.maxSpeed || 10).id), signal = shared(signalActors,ActorSignals.mode);
    const kinds = {};
    refs.forEach(ref => { const name = App.nameOf(ref); kinds[name] = (kinds[name] || 0) + 1; });
    p.innerHTML = `${head(`<span class="ibadge">${ic("layers")}</span>`, `Выбрано: ${refs.length}`, Object.entries(kinds).map(([kind,n]) => `${kind} × ${n}`).join(", "))}
      ${selectionActions()}
      ${locked ? `<p class="selection-status">${ic("lock")}Заблокировано: ${locked}</p>` : ""}
      ${streets.length ? `<div class="selection-section">Дороги · ${streets.length}</div>${roadSettings(streets,"bulk-road-")}` : ""}
      ${decor.length ? `<div class="selection-section">Окружение · ${decor.length}</div>${card("Цвет",fieldTitle("Цвет моделей",tint)+tints(decor[0].prop,tint))}
        ${card("Размер", `${fieldTitle("Масштаб",scale)}${chips("bulk-scale",[.75,1,1.25,1.5].map(value => ({value,title:`×${value}`})),scale)}${slider("scale","Размер группы",1,.5,1.6,.05,"×1")}`)}` : ""}
      ${actors.length ? `<div class="selection-section">Участники · ${actors.length}</div>${card("Скорость",fieldTitle("Скорость",speed)+chips("bulk-speed",Catalog.SPEEDS.map(item => ({value:item.id,title:item.title})),speed))}` : ""}
      ${signalActors.length ? card("Поворотники", fieldTitle("Режим",signal)+chips("bulk-signal",[{value:"auto",title:"Авто"},{value:"left",title:"Левый",icon:"arrow-left"},{value:"right",title:"Правый",icon:"arrow-right"},{value:"off",title:"Выкл"}],signal)) : ""}
      ${card("Действия", `${canRotate ? `<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div>` : ""}<div class="insp-actions">${canCopy ? button("dup","Копия","copy","ghost") : ""}${button("del","Удалить выбранное","trash","danger ghost")}</div>`)}`;
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
    compactHelp(p);
    Thumbs.fillAll(p);
  }

  // ---- a prop ---------------------------------------------------------------------------------
  function tints(prop, value) {
    const list = Catalog.TINTS[Catalog.groupOf(prop).id] || [null];
    return `<div class="swatches">${list.map((c) => `<button class="sw ${c === value || (!c && !value && value !== undefined) ? "on" : ""}" data-chip="tint" data-value="${c || ""}" aria-label="${c ? `Цвет ${c}` : "Свой цвет модели"}" aria-pressed="${c === value || (!c && !value && value !== undefined)}" style="--c:${c || "transparent"}" data-tip="${c ? "" : "Свой цвет модели"}">${c ? "" : ic("x")}</button>`).join("")}</div>`;
  }
  function decorInspector(p, ref, d) {
    const group = Catalog.groupOf(d.prop);
    const variants = [...state.catalog.props.map((x) => x.id), "parked"].filter((x) => group.match(x));
    p.innerHTML = `${head(Thumbs.img("prop", d.prop, "big"), Catalog.propName(d.prop), group.title)}
      ${variants.length > 1 ? card("Заменить на", `<div class="variant-grid">${variants.map((v) => `<button class="variant ${v === d.prop ? "on" : ""}" data-chip="prop" data-value="${v}" data-tip="${esc(Catalog.propName(v))}">${Thumbs.img("prop", v)}</button>`).join("")}</div>`) : ""}
      ${card("Цвет", tints(d.prop, d.tint || null))}
      ${card("Размер и поворот", `${slider("scale", "Масштаб", d.scale[0], 0.5, 2, 0.05, `×${d.scale[0].toFixed(2)}`)}
        <div class="turn-row">${dial(d.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rot90", "90°", "", "ghost")}${button("rotr", "", "rotr", "ghost icon")}</div></div>`)}
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
      const up = () => { el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); App.endDrag(); };
      el.addEventListener("pointermove", move);
      el.addEventListener("pointerup", up);
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
    p.innerHTML = `${head(Thumbs.img("actor", a.type, "big"), a.name || Catalog.ACTORS[a.type]?.name, Catalog.ACTORS[a.type]?.name)}
      ${card("Кто это", `<div class="variant-grid">${types.map((t) => `<button class="variant ${t === a.type ? "on" : ""}" data-chip="type" data-value="${t}" data-tip="${esc(Catalog.ACTORS[t].name)}">${Thumbs.img("actor", t)}</button>`).join("")}</div>
        <input class="name-input" type="text" data-text="name" value="${esc(a.name || "")}" placeholder="Подпись над ним в игре">`)}
      ${a.type === "tram" && (s.tracks || []).length ? tramCard(s, a) : ""}
      ${a.type !== "pedestrian" && a.type !== "special" ? card("Цвет", `<div class="swatches">${PAINTS.map((c) => `<button class="sw ${(a.paint || null) === c ? "on" : ""}" data-chip="paint" data-value="${c || ""}" aria-label="${c ? `Цвет ${c}` : "Цвет модели"}" aria-pressed="${(a.paint || null) === c}" style="--c:${c || "transparent"}" data-tip="${c ? "" : "Как у модели"}">${c ? "" : ic("x")}</button>`).join("")}</div>`) : ""}
      ${ActorSignals.supports(a.type) ? card("Сигналы", `<label class="route-field">Поворотник<select data-text="turnSignal">${[["auto","Автоматически"],["left","Левый"],["right","Правый"],["off","Выключен"]].map(([value,title]) => `<option value="${value}" ${ActorSignals.mode(a) === value ? "selected" : ""}>${title}</option>`).join("")}</select></label>`
        + toggle("hazards", "Аварийная сигнализация", ActorSignals.hazards(a), "alert")
        + `<p class="muted">Автоматически — по выбранному манёвру или пути. Ручной поворотник не меняет маршрут. Аварийка включает обе стороны. Для неподвижной машины выберите «Стоит» в разделе «Куда едет».</p>`) : ""}
      ${a.track ? card("Куда едет", `${chips("move", [{ value: "stay", title: "Стоит", icon: "parked" }, { value: "go", title: "Едет по пути", icon: "route" }], moving ? "go" : "stay")}
        ${route ? button("to-route", "Выбрать траекторию пути", "route", "ghost wide") : ""}`) : card("Куда едет", lane
        ? `${chips("way", [{ value: "stay", icon: "parked", tip: "Стоит" }, ...["left", "straight", "right", "uturn"].map((k) => ({ value: k, icon: Catalog.EXITS[k].icon, tip: Catalog.EXITS[k].title, disabled: !ways.includes(k) }))], moving ? (a.way || "straight") : "stay", { cls: "arrows" })}${button("reverse", "Ехать в другую сторону", "rotr", "ghost wide")}
           ${moving && route ? button("to-route", route.manual ? "Траектория пути (ручная)" : "Траектория пути (по дорогам)", "route", "ghost wide") : ""}`
        : `${chips("move", [{ value: "stay", title: "Стоит", icon: "parked" }, { value: "go", title: "Едет по пути", icon: "route" }], moving ? "go" : "stay")}
           ${moving ? button("draw-path", route ? "Перерисовать путь" : "Нарисовать путь", "route", "ghost wide") : ""}
           ${moving && route ? button("to-route", "Выбрать траекторию пути", "route", "ghost wide") : ""}
           ${(a.type === "pedestrian" || a.type === "cyclist") && Layout.zebraPath(s, a.pos) ? button("zebra-path", "Идти по пешеходному переходу", "zebra", "primary wide") : ""}`)}
      ${moving ? card("Скорость", chips("speed", Catalog.SPEEDS.map((x) => ({ value: x.id, title: x.title })), Catalog.speedOf(a.maxSpeed || 10).id)
        + toggle("waits", "Пропускает игрока", (a.behaviour || {}).waitsForPlayer, "flag")) : ""}
      ${card("", toggle("yield", "Игрок должен уступить ему", (s.question.yieldTo || []).includes(a.id), "alert"))}
      ${card("", `<div class="turn-row">${dial(a.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
    bind({
      ...common,
      "chip:paint": (v) => App.edit(() => { if (v) a.paint = v; else delete a.paint; }),
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
    const trams = state.S.actors.filter((a) => a.track === t.id);
    p.innerHTML = `${head(`<span class="ibadge">${ic("rails")}</span>`, t.depot ? "Рельсы в депо" : "Рельсы", `трамваев: ${trams.length}`)}
      ${card("", `${toggle("depot", "Заезд в депо", !!t.depot, "home")}
        <p class="muted">Трамвай, который сворачивает на эти рельсы, уезжает с дороги и не мешает. Там, где рельсы идут по тротуару, бордюр и тротуар раскрываются под них сами.</p>
        ${button("reverse", "Развернуть направление", "rotr", "ghost wide")}
        <p class="muted">Тяните точки на виде, двойной клик по линии — новая точка. Начало ветки прилипает к другим рельсам.</p>`)}
      ${card("", `<div class="insp-actions">${button("del", "Удалить рельсы", "trash", "danger ghost")}</div>`)}`;
    bind({
      del: () => App.remove(),
      "toggle:depot": (on) => App.edit(() => { if (on) t.depot = true; else delete t.depot; }),
      reverse: () => App.edit(() => { t.points.reverse(); }),
    });
  }

  // ---- a road sign --------------------------------------------------------------------------------
  const signFaceSelection = new Map();
  function signInspector(p, ref, o) {
    const codes = state.catalog.signs || [];
    const slot = o.secondSign && signFaceSelection.get(o.id) === 1 ? 1 : 0;
    const face = slot ? o.secondSign : o;
    const custom = Array.isArray(face.laneDirections) && face.laneDirections.length > 0;
    const lanes = custom ? LaneSign.normalize(face.laneDirections) : [];
    const DIRS = [["nw", "↖"], ["north", "↑"], ["ne", "↗"], ["west", "←"], ["east", "→"], ["sw", "↙"], ["south", "↓"], ["se", "↘"]];
    const main = face.mainRoad || [], roads = face.roads || ["north", "south", "east", "west"];
    const dirChips = (name, on) => `<div class="dir-grid">${DIRS.map(([d, t]) => `<button class="${on.includes(d) ? "on" : ""}" data-chip="${name}" data-value="${d}">${t}</button>`).join("")}</div>`;
    const lanePicture = lanes => LaneSign.svg(lanes).replace('<svg ', '<svg style="width:100%;height:auto;display:block" ');
    const picture = (f, size = 56) => f.laneDirections?.length ? `<span style="display:inline-flex;flex:none;width:${size}px">${lanePicture(f.laneDirections)}</span>` : `<img class="sign-big" src="/asset/sign/${f.code}.svg" alt="" style="width:${size}px;height:${size}px;object-fit:contain;flex:none">`;
    const faceTabs = SignMount.faces(o).map((f, i) => `<button class="btn ${slot === i ? "primary" : "ghost"}" data-chip="face" data-value="${i}">${picture(f, 32)}<span>${i ? "Нижний знак" : "Верхний знак"}</span></button>`).join("");
    const laneControls = lanes.map((directions, i) => `<div class="sub-h">Полоса ${i + 1}</div><div class="seg-chips">${[["left", "←", "Налево"], ["straight", "↑", "Прямо"], ["right", "→", "Направо"]].map(([direction, arrow, title]) => `<button class="${directions.includes(direction) ? "on" : ""}" data-chip="laneDirection" data-lane="${i}" data-value="${direction}" data-tip="${title}"><span>${arrow} ${title}</span></button>`).join("")}</div>`).join("");
    p.innerHTML = `${head(picture(face), custom ? "Направления по полосам" : Catalog.signName(face.code), o.secondSign ? (slot ? "нижний знак на общей стойке" : "верхний знак на общей стойке") : `знак ${face.code}`)}
      ${card("На одной стойке", `<div class="insp-actions">${faceTabs}</div>${o.secondSign ? `<div class="insp-actions">${button("swap-signs", "Поменять местами", "rotr", "ghost")}${button("remove-second-sign", "Убрать нижний", "trash", "danger ghost")}</div>` : button("add-second-sign", "Добавить второй знак", "plus", "ghost wide")}`)}
      ${card("Щит", `${chips("signMode", [{value:"standard",title:"Готовый знак"},{value:"lanes",title:"Конструктор полос"}], custom ? "lanes" : "standard")}
        ${custom ? `<div style="margin:12px auto;max-width:240px">${lanePicture(lanes)}</div><div class="sub-h">Число полос</div>${chips("laneCount", [1,2,3,4,5,6].map(n => ({value:n,title:String(n)})), lanes.length)}${laneControls}<p class="muted">Полосы идут слева направо при взгляде на знак. На каждой можно включить несколько направлений.</p>` : `<div class="sign-grid">${codes.map((c) => `<button class="${c === face.code ? "on" : ""}" data-chip="code" data-value="${c}" data-tip="${esc(Catalog.signName(c))}"><img src="/asset/sign/${c}.svg" alt=""></button>`).join("")}</div>`}`)}
      ${card("Крепление", `${chips("mount", [{value:"pole",title:"На стойке"},{value:"cantilever",title:"Над дорогой"}], o.mount || "pole")}
        ${o.mount === "cantilever" ? `${slider("reach", "Вылет от опоры", o.reach ?? 4.5, 0.5, 15, 0.25, `${o.reach ?? 4.5} м`)}
          ${chips("armSide", [{value:"left",title:"Влево от опоры"},{value:"right",title:"Вправо от опоры"}], o.armSide || "left")}
          ${slider("clearance", "Высота нижнего края", o.clearance ?? 5.5, 5, 8, 0.25, `${o.clearance ?? 5.5} м`)}
          <p class="muted">Поставьте опору на обочине. Вылет перемещает щит над дорогой; сторону выбирайте, глядя на лицевую сторону знака.</p>` : ""}`)}
      ${card("Табличка 8.13: главная дорога", `${dirChips("main", main)}
        ${main.length ? `<div class="sub-h">Все дороги перекрёстка</div>${dirChips("roads", roads)}` : `<p class="muted">Отметьте два направления главной дороги — под выбранным знаком появится табличка.</p>`}`)}
      ${card("Надпись под выбранным знаком", `<input type="text" data-text="plate" value="${esc(face.plate || "")}" placeholder="Например: 150 м">`)}
      ${card("", `<div class="turn-row">${dial(o.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rot90", "90°", "", "ghost")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
    bind({
      ...common,
      "chip:face": (v) => { signFaceSelection.set(o.id, Number(v)); App.renderInspector(); },
      "add-second-sign": () => { signFaceSelection.set(o.id, 1); App.edit(() => { o.secondSign = {code:"2.4"}; }); },
      "remove-second-sign": () => { signFaceSelection.set(o.id, 0); App.edit(() => { delete o.secondSign; }); },
      "swap-signs": () => { signFaceSelection.set(o.id, 1 - slot); App.edit(() => SignMount.swapFaces(o)); },
      "chip:signMode": (v) => App.edit(() => { if (v === "lanes") { face.code = "5.15.1"; face.laneDirections = LaneSign.normalize(face.laneDirections || LaneSign.DEFAULT_LANES); } else delete face.laneDirections; }),
      "chip:laneCount": (v) => App.edit(() => { const n = Number(v), directions = LaneSign.normalize(face.laneDirections); face.laneDirections = Array.from({length:n}, (_, i) => directions[i] || ["straight"]); }),
      "chip:laneDirection": (v, e) => App.edit(() => { const i = Number(e.target.closest('[data-chip]').dataset.lane), directions = LaneSign.normalize(face.laneDirections); const selected = new Set(directions[i]); if (selected.has(v)) { if (selected.size === 1) return; selected.delete(v); } else selected.add(v); directions[i] = [...selected]; face.laneDirections = LaneSign.normalize(directions); }),
      "chip:mount": (v) => App.edit(() => { if (v === "cantilever") { o.mount = v; o.reach ??= 4.5; o.armSide ??= "left"; o.clearance ??= 5.5; } else delete o.mount; }),
      "chip:armSide": (v) => App.edit(() => { o.armSide = v; }),
      "slider:reach": live((_s, v) => { o.reach = r3(v); }, v => { const label = pane().querySelector('[data-shown="reach"]'); if (label) label.textContent = `${v} м`; }),
      "slider:clearance": live((_s, v) => { o.clearance = r3(v); }, v => { const label = pane().querySelector('[data-shown="clearance"]'); if (label) label.textContent = `${v} м`; }),
      "chip:code": (v) => App.edit(() => { face.code = v; delete face.laneDirections; if (v === "8.13" && !(face.mainRoad || []).length) face.mainRoad = ["south", "west"]; }),
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
      p.innerHTML = `${head(`<span class="ibadge">${ic("person")}</span>`, "Регулировщик", "положение в мини-игре")}
        ${card("Положение", `<label>X, м<input type="number" step="0.1" data-text="officerX" value="${o.pos[0]}"></label><label>Z, м<input type="number" step="0.1" data-text="officerZ" value="${o.pos[1]}"></label><p>Тяните регулировщика по сцене или задайте координаты. Жест и направление груди в каждом вопросе выбирает мини-игра.</p>`)}`;
      bind(Object.fromEntries(["officerX","officerZ"].map((key,i) => [`text:${key}`, v => App.edit(() => { if (Number.isFinite(Number(v))) o.pos[i] = Number(v); })])));
      return;
    }
    p.innerHTML = `${head(`<span class="ibadge">${ic("person")}</span>`, "Регулировщик", GESTURES.find((g) => g.value === o.gesture)?.title || "")}
      ${card("Сигнал", `<div class="gestures">${GESTURES.map((g) => `<button class="gesture ${o.gesture === g.value ? "on" : ""}" data-chip="gesture" data-value="${g.value}">${gesturePic(g.value)}<span>${g.title}</span></button>`).join("")}</div>`)}
      ${card("Куда смотрит грудью", `<div class="turn-row">${dial(o.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rot90", "90°", "", "ghost")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
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
    return `<svg viewBox="0 0 48 44" width="48" height="44"><circle cx="24" cy="7" r="4" fill="#1f2a44"/><path d="M24 12 V30 M24 30 L19 42 M24 30 L29 42 M14 16 H34" stroke="#1f2a44" stroke-width="4" stroke-linecap="round" fill="none"/><path d="${arms}" stroke="#1f2a44" stroke-width="4" stroke-linecap="round" fill="none"/></svg>`;
  }

  // ---- a traffic light -------------------------------------------------------------------------
  function lightInspector(p, ref, l) {
    const s = state.S;
    const isTram = !!l.tram;
    const lamps = Catalog.LIGHTS.map((x) => `<button class="lamp ${l.state === x.id ? "on" : ""} ${x.id === "flashing_yellow" ? "blink" : ""}" data-chip="state" data-value="${x.id}" style="--c:${x.colour}" data-tip="${x.title}"></button>`).join("");
    const tramChips = chips("tram", [
      { value: "", title: "Нет" },
      { value: "straight", title: "Прямо", icon: "arrow-up" },
      { value: "left", title: "Налево", icon: "arrow-left" },
      { value: "right", title: "Направо", icon: "arrow-right" },
      { value: "stop", title: "Стоп" },
      { value: "off", title: "Выкл" },
    ], l.tram || "", { cls: "tram-signals" });

    p.innerHTML = `${head(Thumbs.img("light", isTram ? "light_tram" : "light", "big"), isTram ? "Светофор с трамвайной секцией" : "Светофор", s.lights.length > 1 ? `один из ${s.lights.length}` : "")}
      ${card("Сигнал", `<div class="tlight">${lamps}</div><p class="muted">Сигнал один на всю сцену: меняется у всех светофоров.</p>`)}
      ${card("Знаки на стойке", `${[0, 1].map(slot => { const code = (l.mountedSigns || [])[slot]; return `<details><summary>${slot + 1}. ${code ? `${esc(Catalog.signName(code))} · ${code}` : "Добавить знак"}</summary><div class="sign-grid"><button class="${!code ? "on" : ""}" data-chip="mountedSign" data-slot="${slot}" data-value="">Нет</button>${[...new Set(["2.4", "8.13", ...(state.catalog.signs || [])])].map(c => `<button class="${code === c ? "on" : ""}" data-chip="mountedSign" data-slot="${slot}" data-value="${c}" data-tip="${esc(Catalog.signName(c))}"><img src="/asset/sign/${c}.svg" alt="${esc(Catalog.signName(c))}"></button>`).join("")}</div></details>`; }).join("")}`)}
            ${(l.mountedSigns || []).includes("8.13") ? card("Главная дорога на табличке", `<div class="dir-grid">${[["nw","↖"],["north","↑"],["ne","↗"],["west","←"],["east","→"],["sw","↙"],["south","↓"],["se","↘"]].map(([d,t]) => `<button class="${(l.mountedMainRoad || []).includes(d) ? "on" : ""}" data-chip="mountedMainRoad" data-value="${d}">${t}</button>`).join("")}</div>`) : ""}
      ${card("Верхняя секция (Т.5)", `${tramChips}<p class="muted">Бело-лунный сигнал для трамваев и маршрутных ТС.</p>`)}
      ${!isTram ? card("Стрелка", chips("arrow", [{ value: "", title: "Нет" }, { value: "left", icon: "arrow-left" }, { value: "straight", icon: "arrow-up" }, { value: "right", icon: "arrow-right" }], l.arrow || "", { cls: "arrows" })) : ""}
      ${card("", `<div class="turn-row">${dial(l.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
    bind({
      ...common,
      "chip:mountedMainRoad": (v) => App.edit(() => { const roads = new Set(l.mountedMainRoad || []); roads.has(v) ? roads.delete(v) : roads.add(v); l.mountedMainRoad = [...roads]; }),
      "chip:mountedSign": (v, e) => App.edit(() => { const signs = [...(l.mountedSigns || [])]; signs[Number(e.target.closest("[data-chip]").dataset.slot)] = v; if (v === "8.13" && !(l.mountedMainRoad || []).length) l.mountedMainRoad = ["south", "west"]; if (signs.some(Boolean)) l.mountedSigns = signs; else delete l.mountedSigns; }),
      "chip:state": (v) => App.edit((sc) => sc.lights.forEach((x) => { x.state = v; })),
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
  let roadMoreOpen = false;
  function streetInspector(p, ref, st) {
    const s = state.S, L = s.layout, crop = s.crop || 90;
    const edit = (fn, opts) => { if (!App.isLocked(ref)) return App.edit(fn,opts); };
    const allEnds = [st.a, st.b].map((nid) => {
      const n = Layout.nodeOf(L, nid), kind = Layout.nodeKind(L, n, crop);
      return { nid, end: nid === st.a ? "a" : "b", kind, set: (st.ends || {})[nid === st.a ? "a" : "b"] || {} };
    });
    const ends = allEnds.filter((e) => e.kind === "junction" || e.kind === "ring" || e.kind === "dead");
    const highwayEnds = allEnds.filter(e => e.kind === "border");
    const endName = e => {
      const n = Layout.nodeOf(L,e.nid);
      const side = Math.abs(n.x) > Math.abs(n.z) ? (n.x > 0 ? "слева" : "справа") : (n.z > 0 ? "сверху" : "снизу");
      return `${side} · ${e.end === "a" ? "начало" : "конец"}`;
    };
    const roadLength = Layout.polyLen(Layout.centreline(L,st));
    const shortHighway = st.kind === "highway" && Math.max(...Array.from({length:21},(_,i) => Layout.streetProfile(L,st,roadLength*i/20,crop).blend)) < .99;
    const pl = Layout.playerPlan(s);
    const isPlayer = pl && pl.st.id === st.id;
    const offsetText = v => v === 0 ? "Без сдвига" : `${Math.abs(v).toFixed(1)} м ${v < 0 ? "ближе" : "дальше"}`;
    p.innerHTML = `${head(`<span class="ibadge">${ic("road")}</span>`, Layout.KINDS[st.kind || "street"].title, isPlayer ? "по ней едет игрок" : "")}
      ${selectionActions()}
      ${roadSettings([st])}
      <details class="inspector-more" ${roadMoreOpen ? "open" : ""}><summary>${ic("sliders")}Перекрёстки и другие настройки</summary>
      ${st.kind !== "yard" ? card("Разделительная полоса", chips("median", [...(st.kind === "highway" ? [] : [{ value: 0, title: "Нет" }]), { value: 2, title: "2 м" }, { value: 3, title: "3 м" }, { value: 5, title: "5 м" }], Layout.medianOf(st))
        + `<p class="muted">Газон с бордюром посередине. На него можно ставить знаки и светофоры: кликните прямо на полосу.</p>`) : ""}
      ${st.kind === "highway" ? card("Стыки трассы", `<p class="muted">Сквозная трасса соединяет вопросы без сужений. Игра добавляет переход 90 м только при смене на обычную дорогу. Для перехода внутри этой сцены выберите «Дорога 2+2» у нужного конца.</p>
        ${highwayEnds.map(e => `<label>Край ${endName(e)}</label>${chips(`port-${e.end}`, [{value:"highway",title:"Трасса 3+3"},{value:"avenue",title:"Дорога 2+2"}], Layout.highwayPort(st,e.end))}`).join("")}
        ${highwayEnds.length === 2 ? `<p class="muted">Готовые варианты ${isPlayer ? "по ходу игрока" : "от начала к концу"}:</p><div class="insp-actions">${[["through","Сквозная"],["entry","Въезд на трассу"],["exit","Выезд с трассы"],["both","Оба перехода"]].map(([v,t]) => `<button class="btn ghost" data-act="highway-preset" data-preset="${v}">${t}</button>`).join("")}</div>` : ""}
        ${shortHighway ? `<p class="warn">Переходы занимают весь этот короткий участок. Удлините дорогу или выберите сквозные стыки: игра построит переход за пределами вопроса.</p>` : ""}
        <p class="muted">Шесть полос и разделитель сохраняются на стыке 3+3. Внутри сцены соединение с «Проспектом» плавно переходит к его ширине.</p>`) : ""}
      ${st.kind !== "yard" && !st.manualMarks ? card("Разметка вручную", button("marks-own", "Сделать линии редактируемыми", "marking", "ghost wide")) : ""}
      ${st.bend ? card("Геометрия",button("straighten", "Выпрямить", "road", "ghost wide")) : ""}
      ${ends.length ? card("У перекрёстка", ends.map((e, i) => `<div class="end-row"><span>${ends.length > 1 ? `Конец ${i + 1}` : "Въезд"}</span>
          <button class="pick ${e.set.stop ? "on" : ""}" data-act="end" data-end="${e.end}" data-what="stop">${ic(e.set.stopStyle === "yield" ? "yieldline" : "stopline")}${e.set.stopStyle === "yield" ? "Треугольники" : "Стоп-линия"}</button>
          <button class="pick ${e.set.zebra ? "on" : ""}" data-act="end" data-end="${e.end}" data-what="zebra">${ic("zebra")}Зебра</button></div>
          ${e.set.stop ? `<label>Вид линии</label>${chips(`stop-style-${e.end}`, stopStyles, e.set.stopStyle || "solid")}` : ""}
          ${e.kind === "junction" ? (() => {
            const value = Layout.endOffset(L, st, e.nid, crop), limits = Layout.endOffsetLimits(L, st, e.nid, crop);
            return slider(`approach-${e.end}`, Number(st.median) ? "Островок и стоп-линия" : "Положение стоп-линии", value, limits.min, limits.max, 0.1, offsetText(value))
              + `<label>Сдвиг, м<input type="number" min="${limits.min}" max="${limits.max}" step="0.1" data-text="approach-${e.end}" value="${value}" style="width:100%"></label><p class="muted">Отрицательное значение — ближе к перекрёстку, положительное — дальше. Конец островка, стоп-линия и зебра двигаются вместе.</p><button class="btn ghost wide" data-act="approach-reset" data-nid="${e.nid}">${ic("restart")}Вернуть исходное положение</button>`
              + (st.surface === "sand" ? slider(`paved-${e.end}`, "Асфальт перед перекрёстком", Layout.pavedEnd(st, e.end), 0, Layout.PAVED_MAX, 1, `${Layout.pavedEnd(st, e.end)} м`)
                + `<p class="muted">Участок с твёрдым покрытием у перекрёстка. Грунт плавно переходит в асфальт и в траву по краям. 0 — грунт до самого перекрёстка.</p>` : "");
          })() : ""}`).join("")) : ""}
      ${card("Игрок едет по ней", `<div class="insp-actions">${[st.a, st.b].map((nid) => {
        const on = isPlayer && pl.nid === nid;
        const k = Layout.nodeKind(L, Layout.nodeOf(L, nid), crop);
        const where = k === "junction" ? "к перекрёстку" : k === "ring" ? "к кольцу" : k === "border" ? "к краю сцены" : "к концу дороги";
        return `<button class="btn ${on ? "primary" : "ghost"}" data-act="player" data-toward="${nid}">${ic("car")}${esc(where)}</button>`;
      }).join("")}</div>`)}
      </details>
      ${card("", `<div class="insp-actions">${button("del", "Удалить дорогу", "trash", "danger ghost")}</div>`)}`;
    bind({
      ...selectionHandlers,
      ...roadHandlers([ref]),
      del: () => { if (!App.isLocked(ref)) App.remove(); },
      "chip:median": (v) => edit(() => { if (Number(v)) st.median = Number(v); else delete st.median; }),
      ...Object.fromEntries(highwayEnds.map(e => [`chip:port-${e.end}`, v => edit(() => Layout.setHighwayPort(st,e.end,v))])),
      "highway-preset": d => edit(() => {
        const exit = isPlayer ? (pl.nid === st.a ? "a" : "b") : "b";
        const entry = exit === "a" ? "b" : "a";
        for (const e of highwayEnds) Layout.setHighwayPort(st,e.end,
          d.preset === "both" || (d.preset === "entry" && e.end === entry) || (d.preset === "exit" && e.end === exit) ? "avenue" : "highway");
      }),
      "toggle:walk": on => edit(() => { st.walk = on; }),
      "toggle:edge": on => edit(() => { st.edge = on; }),
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
          const label = pane().querySelector(`[data-shown="approach-${e.end}"]`);
          if (label) label.textContent = offsetText(value);
          const field = pane().querySelector(`[data-text="approach-${e.end}"]`);
          if (field) field.value = value;
        })],
        [`text:approach-${e.end}`, v => edit(sc => Layout.setEndOffset(sc, st.id, e.nid, Number(v)))],
        [`slider:paved-${e.end}`, live((sc, v) => { if (!App.isLocked(ref)) Layout.setPavedEnd(sc, st.id, e.end, v); }, v => {
          const label = pane().querySelector(`[data-shown="paved-${e.end}"]`);
          if (label) label.textContent = `${Layout.pavedEnd(Layout.streetOf(state.S.layout, st.id), e.end)} м`;
        })],
      ])),
      player: (d) => edit((sc) => { sc.layout.player = { street: st.id, toward: d.toward }; }),
    });
    const more = p.querySelector(".inspector-more");
    more?.addEventListener("toggle", () => { roadMoreOpen = more.open; });
  }

  function nodeInspector(p, ref, n) {
    const s = state.S, L = s.layout, crop = s.crop || 90;
    const kind = Layout.nodeKind(L, n, crop);
    const arms = Layout.streetsAt(L, n.id).length;
    const sizes = [{ value: "s", title: "Малое", r: 15, island: 6 }, { value: "m", title: "Среднее", r: 20, island: 9 }, { value: "l", title: "Большое", r: 26, island: 13 }];
    const size = n.ring ? sizes.reduce((b, x) => Math.abs(x.r - n.ring.r) < Math.abs(b.r - n.ring.r) ? x : b, sizes[1]).value : "m";
    const hasLights = s.lights.some((l) => Math.hypot(l.pos[0] - n.x, l.pos[1] - n.z) < (n.ring ? n.ring.r + 12 : 20));
    p.innerHTML = `${head(`<span class="ibadge">${ic(n.ring ? "ring" : "junction")}</span>`, n.ring ? "Кольцо" : kind === "junction" ? "Перекрёсток" : "Точка дороги", `дорог: ${arms}`)}
      ${arms >= 2 ? card("Вид", chips("ring", [{ value: "cross", icon: "junction", title: "Перекрёсток" }, { value: "ring", icon: "ring", title: "Кольцо" }], n.ring ? "ring" : "cross", { cls: "tiles" })
        + (n.ring ? `<div class="sub-h">Размер</div>${chips("size", sizes.map((x) => ({ value: x.value, title: x.title })), size)}` : "")) : ""}
      ${n.ring ? card("Разметка кольца", toggle("ring-outer-edge", "Внешняя сплошная", n.ring.outerEdge !== false, "marking")
        + toggle("ring-inner-edge", "Сплошная вокруг островка", n.ring.innerEdge !== false, "marking")) : ""}
      ${kind === "junction" || kind === "ring" ? card("Светофоры", hasLights
        ? `${button("lights-off", "Убрать светофоры", "light", "ghost wide")}`
        : `${button("lights-on", "Поставить на все въезды", "light", "primary wide")}`) : ""}
      ${card("", `<p class="muted">Тяните точку, чтобы двигать. Бросьте на другую — соединятся.</p><div class="insp-actions">${button("del", "Удалить с дорогами", "trash", "danger ghost")}</div>`)}`;
    bind({
      del: () => App.remove(),
      "chip:ring": (v) => App.edit(() => { if (v === "ring") n.ring = { r: 20, island: 9 }; else delete n.ring; }),
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
  function playerRoutePointTools(ref, route) {
    const count = route.points.length;
    const index = Number.isInteger(ref.v) ? Math.max(0, Math.min(count - 1, ref.v)) : 0;
    const point = route.points[index];
    // Traced scenes predate the manual flag: any non-generated player route
    // is already authored and must remain editable without a mode switch.
    const manual = !!route.manual || !route.auto;
    const anchored = route.kind === "manoeuvre" ? index === 0
      : !!state.S.layout && (index === 0 || index === count - 1);
    const current = sc => sc.routes.find(r => r.id === route.id);
    const editing = manual && point ? `<label class="route-field">Точка<input type="number" min="1" max="${count}" step="1" data-text="routeIndex" value="${index + 1}"></label>
      <label class="route-field">X, м<input type="number" step="0.1" data-text="routeX" value="${r3(point[0])}" ${anchored ? "disabled" : ""}></label>
      <label class="route-field">Z, м<input type="number" step="0.1" data-text="routeZ" value="${r3(point[1])}" ${anchored ? "disabled" : ""}></label>
      ${anchored ? `<p class="muted">${route.kind === "manoeuvre" || index === count - 1 ? "Эта точка закреплена у машины игрока. Чтобы изменить её, переместите машину." : "Эта точка закреплена у въезда на дорогу."}</p>` : count > 2 ? button("route-delete-point", "Удалить точку", "trash", "ghost wide") : ""}
      ${index < count - 1 ? button("route-add-point", "Добавить точку после выбранной", "points", "ghost wide") : ""}
      ${count > 3 ? button("route-compact", "Упростить точки", "points", "ghost wide") + `<p class="muted">Убирает лишние точки, сохраняя форму пути. Изменение можно отменить.</p>` : ""}` : `<p class="muted">Опорные точки строятся по дорогам. Для изменения включите ручной путь.</p>`;
    return {
      html: card("Опорные точки", `<p>Опорных точек: ${count} · ${manual ? "ручной путь" : "строится по дорогам"}</p>${editing}`),
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
    if (state.id === "mini_regulator" && ["approach", "manoeuvre"].includes(r.kind)) return regulatorRouteInspector(p, ref, r);
    if (r.kind === "approach") {
      const points = playerRoutePointTools(ref, r);
      const manual = !!r.manual || !r.auto;
      p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, "Подъезд игрока", manual ? "ручной путь" : "строится сам")}
        ${card("До начала вопроса", `<p>Зелёная линия показывает, как игрок подъезжает к месту вопроса. После ответа он едет по линии выбранного манёвра.</p>
          ${manual ? `<p class="muted">Тяните точки или задавайте координаты справа. Двойной клик по линии добавляет точку.${s.layout ? " Начало закреплено у въезда, конец — у машины игрока." : ""}</p>${s.layout ? button("auto-path", "Снова строить по дорогам", "restart", "ghost wide") : ""}`
            : `<p class="muted">Путь пересчитывается при перемещении игрока.</p>${button("own-path", "Править путь вручную", "points", "ghost wide")}${button("auto-path", "Пересчитать подъезд", "restart", "ghost wide")}`}`)}${points.html}`;
      bind({
        ...points.handlers,
        "own-path": () => { App.select({t:"route",id:r.id}); App.edit(sc => Layout.setPlayerRouteManual(sc, sc.routes.find(x => x.id === r.id), true)); },
        "auto-path": () => { App.select({t:"route",id:r.id}); App.edit(sc => Layout.setPlayerRouteManual(sc, sc.routes.find(x => x.id === r.id), false)); },
      });
      return;
    }
    if (r.kind === "choice") {
      const used = s.routes.filter((x) => x.kind === "choice" && x !== r).map((x) => x.label);
      const ways = s.routes.filter((x) => x.kind === "manoeuvre");
      p.innerHTML = `${head(`<span class="letter-badge" style="--c:${Catalog.LETTER_COLOUR[r.label]}">${esc(r.label)}</span>`, `Вариант ответа ${r.label}`, "линия на дороге при вопросе")}
        ${card("Буква", chips("label", Catalog.LETTERS.map((l) => ({ value: l, html: `<span class="letter-badge sm" style="--c:${Catalog.LETTER_COLOUR[l]}">${l}</span>`, disabled: used.includes(l) })), r.label))}
        ${card("Вид линии", chips("arrowhead", [{value:"arrow",title:"Со стрелкой"},{value:"line",title:"Линия без стрелки"}], r.arrowhead === false ? "line" : "arrow"))}
        ${ways.length ? card("Взять путь", chips("copy", ways.map((w) => ({ value: w.exit, icon: Catalog.EXITS[w.exit].icon, tip: Catalog.EXITS[w.exit].title })), "", { cls: "arrows" })) : ""}
        ${card("", `<p class="muted">Тяните точки на виде. Двойной клик по линии — новая точка.</p>${button("mid", "Букву — на середину", "flag", "ghost wide")}<div class="insp-actions">${button("del", "Удалить", "trash", "danger ghost")}</div>`)}`;
      bind({
        ...common,
        "chip:label": (v) => App.edit(() => { r.label = v; r.id = `choice_${v}`; }) || App.select({ t: "route", id: `choice_${v}` }),
        "chip:arrowhead": v => App.edit(() => { if (v === "line") r.arrowhead = false; else delete r.arrowhead; }),
        "chip:copy": (v) => App.edit((sc) => { const w = sc.routes.find((x) => x.kind === "manoeuvre" && x.exit === v); r.points = JSON.parse(JSON.stringify(w.points)); const m = r.points[Math.floor(r.points.length * 0.6)]; r.labelPosition = [m[0], m[1]]; }),
        mid: () => App.edit(() => { const m = r.points[Math.floor(r.points.length / 2)]; r.labelPosition = [m[0], m[1]]; }),
      });
      return;
    }
    if (r.kind === "manoeuvre") {
      const points = playerRoutePointTools(ref, r);
      const main = s.question.maneuver === r.exit;
      const guideVisible = s.question?.showPlayerGuide !== false;
      p.innerHTML = `${head(`<span class="ibadge">${ic(Catalog.EXITS[r.exit]?.icon || "route")}</span>`, `Манёвр: ${Catalog.EXITS[r.exit]?.title.toLowerCase()}`, main ? "так едет игрок" : "другой выезд")}
        ${card("", `${main ? `<p class="ok-line">${ic("check-circle")}Этот манёвр — по условию вопроса</p>` : button("make-main", "Игрок едет так", "flag", "primary wide")}
          ${!guideVisible ? "" : r.auto ? `<p class="muted">Путь строится сам по дорогам.</p>${button("own-path", "Править путь вручную", "points", "ghost wide")}`
            : `<p class="muted">Тяните точки на виде, двойной клик по линии — новая точка.</p>${r.manual && s.layout ? button("auto-path", "Снова строить по дорогам", "restart", "ghost wide") : ""}`}
          ${guideVisible ? `<p class="muted">По этой линии машина игрока едет после ответа. Если в вопросе есть линии ответов, она видна только когда выбрана.</p>` : ""}`)}${playerGuideCard(s.question)}${guideVisible ? points.html : ""}`;
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
      p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, App.nameOf(ref), isManual ? "ручной путь" : "строится сам")}
        ${card("Управление траекторией", `${isManual
          ? `<p class="muted">Тяните точки на виде, двойной клик по линии — новая точка.</p>${button("auto-path", "Снова строить по дорогам", "restart", "ghost wide")}`
          : `<p class="muted">Путь строится сам по дорогам.</p>${button("own-path", "Править путь вручную", "points", "ghost wide")}`}
          ${actor ? button("actor", `К участнику (${actor.name || Catalog.ACTORS[actor.type]?.name || "авто"})`, "car", "ghost wide") : ""}
          <div class="insp-actions">${button("del", "Удалить путь", "trash", "danger ghost")}</div>`)}`;
      bind({
        actor: () => actor && App.select({ t: "actor", id: actor.id }),
        "own-path": () => App.edit((sc) => { const x = sc.routes.find((y) => y.id === r.id); if (x) { x.manual = true; delete x.auto; } }),
        "auto-path": () => App.edit((sc) => { const x = sc.routes.find((y) => y.id === r.id); if (x) { delete x.manual; x.auto = true; } }),
        del: () => App.remove(),
      });
      return;
    }
    p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, App.nameOf(ref), r.auto ? "строится сам" : "")}
      ${card("", `<p class="muted">${r.kind === "approach" ? "Подъезд игрока к стоп-линии." : "Тяните точки на виде."}</p>`)}`;
    bind({});
  }

  // ---- markings and shapes -------------------------------------------------------------------
  function markingInspector(p, ref, m) {
    const paint = m.type === "paint";
    p.innerHTML = `${head(`<span class="ibadge">${ic("marking")}</span>`, App.nameOf(ref), paint ? "снята с картинки билета" : "")}
      ${paint ? "" : card("Вид", chips("type", Object.entries(Catalog.MARKS).map(([k, v]) => ({ value: k, html: `<span class="mark-pic m-${k}"></span>`, tip: v.title })), m.type, { cls: "tiles" }))}
      ${m.type === "stop" ? card("Вид линии", chips("stop-style", stopStyles, m.stopStyle || "solid")
        + (m.stopStyle === "yield" ? button("yield-flip", "Развернуть треугольники", "rotr", "ghost wide") : "")) : ""}
      ${card("Цвет", chips("colour", [{ value: "white", html: `<span class="paint w"></span>`, title: "Белая" }, { value: "yellow", html: `<span class="paint y"></span>`, title: "Жёлтая" }], m.colour || "white"))}
      ${m.type === "solid" || m.type === "dashed" ? card("Вторая линия рядом", chips("double", [{ value: "", title: "Нет" }, { value: "solid", html: `<span class="mark-pic m-solid"></span>`, tip: "Сплошная" }, { value: "dashed", html: `<span class="mark-pic m-dashed"></span>`, tip: "Прерывистая" }], m.double || "", { cls: "tiles" })
        + (m.double ? button("flip", "На другую сторону", "rotr", "ghost wide") : "")
        + (ref.v !== undefined && ref.v > 0 && ref.v < m.points.length - 1 ? button("split", "Разрезать в выбранной точке", "marking", "ghost wide") : `<p class="muted">Выберите точку на линии, чтобы разрезать её: у частей может быть разный вид.</p>`)) : ""}
      ${card("", `<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div>${deleteRow()}`)}`;
    bind({
      ...common,
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
      "chip:type": (v) => App.edit(() => {
        m.type = v;
        if ((v === "stop" || v === "zebra") && m.points) m.points = m.points.slice(0, 2);
        if (v === "zebra") m.length = m.length || 4; else delete m.length;
        if (v === "stop") m.width = 0.4; else delete m.width;
        if (v !== "stop") delete m.stopStyle;
      }),
      "chip:stop-style": v => {
        if (!App.isLocked(ref) && stopStyles.some(style => style.value === v)) App.edit(() => setStopStyle(m, v));
      },
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
    p.innerHTML = `${head(`<span class="ibadge">${ic(ref.t === "lawn" ? "lawn" : "road")}</span>`, title, ref.t === "road" ? "снята с картинки билета" : "газон вместо тротуара")}
      ${card("", `<p class="muted">Тяните точки на виде. Двойной клик по краю — новая точка, Delete на точке — убрать её.</p>
        <div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div>
        ${ref.t === "road" && !state.S.layout ? button("convert", "Перевести дороги в конструктор", "magic", "primary wide") : ""}${deleteRow()}`)}`;
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

    p.innerHTML = `${head(`<span class="ibadge">${ic("car")}</span>`, "Игрок", "место начала вопроса")}
      ${card("Едет", chips("maneuver", ["left", "straight", "right", "uturn"].map((k) => ({ value: k, icon: Catalog.EXITS[k].icon, tip: Catalog.EXITS[k].title, disabled: !routes.includes(k) && k !== "straight" })), q.maneuver, { cls: "arrows" }))}
      ${s.id !== "mini_regulator" ? playerGuideCard(q) : ""}
      ${s.layout ? card("Размещение", chips("playerMode", [{value:"street",title:"По улице"},{value:"free",title:"Свободно"}], free ? "free" : "street")) : ""}
      ${free ? card("Положение на дороге", `<div class="insp-actions"><label>X, м<input type="number" step="0.1" data-text="playerX" value="${pose.x}" style="width:100%"></label><label>Z, м<input type="number" step="0.1" data-text="playerZ" value="${pose.z}" style="width:100%"></label></div><div class="turn-row">${dial(pose.yaw)}<label>Поворот, °<input type="number" step="1" data-text="playerYaw" value="${r3(pose.yaw * 180 / Math.PI)}" style="width:100%"></label></div><div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rot90", "90°", "", "ghost")}${button("rotr", "", "rotr", "ghost icon")}</div>`) : ""}
      ${lanes.length > 1 ? card("Полоса", chips("lane", laneItems, curLane, { cls: "tiles" })) : ""}
      ${plan && !free ? card("Начало вопроса", slider("questionOffset", "Раньше стоп-линии", Math.max(0, plan.sd - plan.stopLineDistance - 2.4), 0, Math.min(60, Math.max(0, plan.total - plan.stopLineDistance - 3.4)), 0.5, `${Math.max(0, plan.sd - plan.stopLineDistance - 2.4).toFixed(1)} м`) + button("question-at-line", "Вернуть к стоп-линии", "restart", "ghost wide")) : ""}
      ${!s.layout ? card("Полоса", `<div class="insp-actions">${button("shift-left", "Сместить влево (3.5 м)", "arrow-left", "ghost small")}${button("shift-right", "Сместить вправо (3.5 м)", "arrow-right", "ghost small")}</div>`) : ""}
      ${card("", `<p class="muted">${free ? "Тяните машину по проезжей части, в том числе по кольцу. Поверните кольцом, Q/E или задайте угол выше. Весь кузов должен оставаться на дороге." : s.layout ? (lanes.length > 1 ? "Выберите полосу выше или перетащите машину на другую полосу на виде." : "Место игрока строится по дороге: тяните машину вдоль улицы.") : "Тяните машину на виде или смещайте кнопками выше."}</p>`)}`;
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
    p.innerHTML = `${head(`<canvas class="tex-big" width="56" height="56" data-tex-head></canvas>`, info.name, info.where)}
      ${card("", `<canvas id="tex-preview" class="tex-preview" width="320" height="200"></canvas>`)}
      ${card("Стиль", `<div class="style-grid">${styles.map((st) => `<button class="style ${Textures.pendingStyle(kind) === st.id ? "on" : ""}" data-act="style" data-style="${st.id}"><canvas width="64" height="64" data-style-pic="${st.id}"></canvas><span>${esc(st.title)}</span></button>`).join("")}</div>`)}
      ${card("Настройка", `${slider("gain", "Зерно", d.gain, 0, Textures.PARAMS.gain.max, 0.1, shown("gain", d.gain))}
        ${slider("macro", "Пятна", d.macro, 0, Textures.PARAMS.macro.max, 0.01, shown("macro", d.macro))}
        ${d.period !== undefined ? slider("period", "Размер рисунка", d.period, 1, 16, 0.2, shown("period", d.period)) : ""}`)}
      ${card("Своя картинка", `<button class="dropzone" data-act="upload">${ic("upload")}<span>Перетащите PNG сюда или нажмите</span><small>256 × 256, бесшовная</small></button>
        ${meta.backups ? button("restore", "Вернуть прежнюю картинку", "undo", "ghost wide") : ""}`)}
      ${card("", `<div class="insp-actions">${button("reset", "Сбросить", "restart", "ghost")}${button("apply", "Применить в игре", "check-circle", "primary")}</div>`)}`;
    Textures.draw(p.querySelector("[data-tex-head]"), kind, "final", 1);
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
