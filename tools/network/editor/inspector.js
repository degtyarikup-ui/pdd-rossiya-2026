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
    `<button class="${String(it.value) === String(value) ? "on" : ""} ${it.disabled ? "off" : ""}" data-chip="${name}" data-value="${esc(it.value)}" ${it.disabled ? "disabled" : ""} ${it.tip ? `data-tip="${esc(it.tip)}"` : ""}>${it.icon ? ic(it.icon) : ""}${it.html || ""}${it.title ? `<span>${esc(it.title)}</span>` : ""}</button>`).join("")}</div>`;
  const toggle = (name, label, on, icon) => `<label class="switch-row">${icon ? ic(icon) : ""}<span>${esc(label)}</span><input type="checkbox" data-toggle="${name}" ${on ? "checked" : ""}><i class="switch"></i></label>`;
  const button = (act, label, icon, cls = "") => `<button class="btn ${cls}" data-act="${act}">${icon ? ic(icon) : ""}<span>${esc(label)}</span></button>`;
  const slider = (name, label, value, min, max, step, shown) => `<div class="slider-row"><div class="slider-h"><span>${esc(label)}</span><em data-shown="${name}">${esc(shown)}</em></div>
    <input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-slider="${name}"></div>`;

  function compactHelp(p) {
    p.querySelectorAll("p.muted").forEach((text) => {
      if (text.closest(".info-help")) return;
      const info = document.createElement("details"); info.className = "info-help";
      const summary = document.createElement("summary"); summary.textContent = "i"; summary.setAttribute("aria-label", "Подсказка");
      text.replaceWith(info); info.append(summary, text);
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

  // ---- the scene ----------------------------------------------------------------------------
  function sceneInspector(p) {
    const s = state.S, q = s.question || {}, src = state.source, ru = (q.text && q.text.ru) || {};
    const routes = s.routes.filter((r) => r.kind === "manoeuvre").map((r) => r.exit);
    const errors = state.findings.filter((f) => f.level === "error"), warns = state.findings.filter((f) => f.level === "warn");
    const answers = src ? src.answers.map((a) => a.text) : ru.options || [];
    const correct = q.correct;
    const yields = s.actors.map((a) => `<button class="pick ${(q.yieldTo || []).includes(a.id) ? "on" : ""}" data-act="yield" data-id="${a.id}">${Thumbs.img("actor", a.type, "mini")}<span>${esc(a.name || a.id)}</span></button>`).join("");
    const edges = state.edges || {};
    const side = (k) => { const e = edges[k]; return e ? (e.street ? "ok" : "bad") : "none"; };
    p.innerHTML = `
      ${head(`<span class="ibadge">${ic("map")}</span>`, App.sceneTitle(state.id), s.layout ? "Дороги в конструкторе" : "Дороги из картинки билета")}
      ${card("", `${toggle("playable", "Сцена в игре", state.playable, "gamepad")}
        <div class="insp-actions">${button("run", "Тест в игре", "play", "primary")}</div>
        ${button("run-auto", "В игре на автопилоте", "video", "ghost small wide")}`)}
      ${card("Игрок едет", `${chips("maneuver", ["left", "straight", "right", "uturn"].map((k) => ({ value: k, icon: Catalog.EXITS[k].icon, tip: Catalog.EXITS[k].title, disabled: k !== "straight" && !routes.includes(k) && !(s.layout) })), q.maneuver, { cls: "arrows" })}
        <div class="sub-h">Знак скорости</div>${chips("speed", [{ value: "", title: "Нет" }, ...[20, 40, 60].map((v) => ({ value: v, html: `<span class="speed-sign">${v}</span>` }))], q.speedLimit ?? "", { cls: "signs" })}
        <div class="sub-h">Ждать на красном</div>${chips("redWait", [{ value: "", title: "Нет" }, { value: 2, title: "2 с" }, { value: 5, title: "5 с" }], q.redWait ?? "")}
        ${s.actors.length ? `<div class="sub-h">Уступить дорогу</div><div class="picks">${yields}</div>` : ""}`, { icon: "flag" })}
      ${card("Дороги", s.layout
        ? `<p class="muted">Двигайте узлы, тяните дороги инструментом ${ic("road", "inline")} R. Разметка и маршруты строятся сами.</p>${button("templates", "Готовые перекрёстки", "junction", "ghost wide")}`
        : `<p class="muted">Дороги сняты с картинки билета. В конструкторе их можно двигать и менять как в SimCity.</p>${button("convert", "Перевести в конструктор", "magic", "primary wide")}`, { icon: "road" })}
      ${card("Камера вопроса", `<p class="muted">${s.questionView ? "Кадр задан вручную." : "Кадр подбирается сам."} Видно, что попадёт на экран телефона над карточкой вопроса.</p>${button("frame", "Настроить кадр", "video", "primary wide")}`, { icon: "video" })}
      ${card("Края сцены", `<div class="edges"><span class="edge-box"><i class="e-n ${side("n")}"></i><i class="e-s ${side("s")}"></i><i class="e-e ${side("e")}"></i><i class="e-w ${side("w")}"></i>${ic("car")}</span>
        <p class="muted">${Object.values(edges).some((e) => e && !e.street) ? "Дорога у края не совпадает с улицей игры (8,4 м по центру стороны). Подвиньте конец дороги к середине стороны." : "На краях дорога встречает улицу игры без ступенек."}</p></div>`, { icon: "edges" })}
      <section class="card" id="checks"><h3>${ic(errors.length ? "error" : "check-circle")}Проверка${errors.length + warns.length ? `<em class="count ${errors.length ? "bad" : "warn"}">${errors.length + warns.length}</em>` : ""}</h3>
        ${state.findings.length ? state.findings.map((f, i) => `<button class="finding ${f.level}" data-act="finding" data-i="${i}">${ic(f.level === "error" ? "error" : "alert")}<span>${esc(f.message)}</span></button>`).join("")
          : `<p class="ok-line">${ic("check-circle")}Ошибок нет</p>`}</section>
      `;
    compactHelp(p);
    Thumbs.fillAll(p);
    bind({
      "toggle:playable": (on) => App.setPlayable(on),
      run: () => App.runInGame(false),
      "run-auto": () => App.runInGame(true),
      correct: (d) => App.edit((sc) => { sc.question.correct = Number(d.i); }),
      "chip:maneuver": (v) => App.edit((sc) => { sc.question.maneuver = v; sc.spec = { ...(sc.spec || {}), maneuver: v }; }),
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

  // ---- several things -------------------------------------------------------------------------
  function multiInspector(p) {
    const sel = state.sel;
    const decor = sel.filter((r) => r.t === "decor").map(App.objectOf);
    const kinds = {};
    sel.forEach((r) => { const n = App.nameOf(r); kinds[n] = (kinds[n] || 0) + 1; });
    p.innerHTML = `${head(`<span class="ibadge">${ic("layers")}</span>`, `Выбрано: ${sel.length}`, Object.entries(kinds).map(([k, n]) => `${k} × ${n}`).join(", "))}
      ${decor.length ? card("Цвет", tints(decor[0].prop, decor.every((d) => d.tint === decor[0].tint) ? decor[0].tint : undefined)) : ""}
      ${decor.length ? card("Размер", slider("scale", "Масштаб", 1, 0.5, 1.6, 0.05, "×1")) : ""}
      ${card("", `<div class="insp-actions">${button("rotl", "−15°", "rotl", "ghost")}${button("rotr", "+15°", "rotr", "ghost")}</div>${deleteRow()}`)}`;
    const base = decor.map((d) => [...d.scale]);
    bind({
      ...common,
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
      "chip:tint": (v) => App.edit(() => decor.forEach((d) => { d.tint = v || null; })),
      "slider:scale": live((s, v) => { decor.forEach((d, i) => { d.scale = base[i].map((x) => r3(x * v)); }); }, (v) => { $("[data-shown=scale]").textContent = `×${v.toFixed(2)}`; }),
    });
  }

  // ---- a prop ---------------------------------------------------------------------------------
  function tints(prop, value) {
    const list = Catalog.TINTS[Catalog.groupOf(prop).id] || [null];
    return `<div class="swatches">${list.map((c) => `<button class="sw ${c === value || (!c && !value && value !== undefined) ? "on" : ""}" data-chip="tint" data-value="${c || ""}" style="--c:${c || "transparent"}" data-tip="${c ? "" : "Свой цвет модели"}">${c ? "" : ic("x")}</button>`).join("")}</div>`;
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
  function bindDial(p, o) {
    const el = p.querySelector("[data-dial]");
    if (!el) return;
    el.addEventListener("pointerdown", (e) => {
      el.setPointerCapture(e.pointerId);
      App.beginDrag();
      const move = (ev) => {
        const r = el.getBoundingClientRect();
        let a = -Math.atan2(ev.clientX - (r.left + r.width / 2), -(ev.clientY - (r.top + r.height / 2)));
        if (!ev.shiftKey) a = Math.round(a / (Math.PI / 12)) * (Math.PI / 12);
        App.dragMove(() => { o.yaw = r3(a); });
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
    const lane = s.layout && Catalog.ACTORS[a.type]?.lane;
    const ways = lane ? Layout.waysFrom(s, a.pos, a.yaw) : [];
    const route = a.route && s.routes.find((r) => r.id === a.route);
    const types = Catalog.ACTOR_ORDER.filter((t) => state.catalog.actorTypes[t]);
    const moving = !(a.behaviour || {}).staysPut;
    p.innerHTML = `${head(Thumbs.img("actor", a.type, "big"), a.name || Catalog.ACTORS[a.type]?.name, Catalog.ACTORS[a.type]?.name)}
      ${card("Кто это", `<div class="variant-grid">${types.map((t) => `<button class="variant ${t === a.type ? "on" : ""}" data-chip="type" data-value="${t}" data-tip="${esc(Catalog.ACTORS[t].name)}">${Thumbs.img("actor", t)}</button>`).join("")}</div>
        <input class="name-input" type="text" data-text="name" value="${esc(a.name || "")}" placeholder="Подпись над ним в игре">`)}
      ${a.type === "tram" && (s.tracks || []).length ? tramCard(s, a) : ""}
      ${a.track ? "" : card("Куда едет", lane
        ? `${chips("way", [{ value: "stay", icon: "parked", tip: "Стоит" }, ...["left", "straight", "right", "uturn"].map((k) => ({ value: k, icon: Catalog.EXITS[k].icon, tip: Catalog.EXITS[k].title, disabled: !ways.includes(k) }))], moving ? (a.way || "straight") : "stay", { cls: "arrows" })}`
        : `${chips("move", [{ value: "stay", title: "Стоит", icon: "parked" }, { value: "go", title: "Едет по пути", icon: "route" }], moving ? "go" : "stay")}
           ${moving ? button("draw-path", route ? "Перерисовать путь" : "Нарисовать путь", "route", "ghost wide") : ""}
           ${(a.type === "pedestrian" || a.type === "cyclist") && Layout.zebraPath(s, a.pos) ? button("zebra-path", "Идти по пешеходному переходу", "zebra", "primary wide") : ""}`)}
      ${moving ? card("Скорость", chips("speed", Catalog.SPEEDS.map((x) => ({ value: x.id, title: x.title })), Catalog.speedOf(a.maxSpeed || 10).id)
        + toggle("waits", "Пропускает игрока", (a.behaviour || {}).waitsForPlayer, "flag")) : ""}
      ${card("", toggle("yield", "Игрок должен уступить ему", (s.question.yieldTo || []).includes(a.id), "alert"))}
      ${card("", `<div class="turn-row">${dial(a.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
    bind({
      ...common,
      "chip:track": (v) => App.edit((sc) => {
        if (v) { a.track = v; delete a.way; delete a.branch; }
        else { delete a.track; delete a.branch; delete a.trackDir; sc.routes = sc.routes.filter((x) => x.id !== `actor_${a.id}`); a.route = null; }
      }),
      "chip:tdir": (v) => App.edit(() => { a.trackDir = Number(v); delete a.branch; }),
      "chip:branch": (v) => App.edit(() => { if (v) a.branch = v; else delete a.branch; }),
      "chip:type": (v) => App.edit(() => {
        const tpl = state.catalog.actorTypes[v];
        a.type = v; a.asset = tpl.asset;
        if (!a.name || Object.values(Catalog.ACTORS).some((x) => x.name === a.name)) a.name = Catalog.ACTORS[v].name;
        a.halfLength = tpl.halfLength ?? a.halfLength; a.halfWidth = tpl.halfWidth ?? a.halfWidth;
      }),
      "text:name": (v) => App.edit(() => { a.name = v.trim(); }),
      "chip:way": (v) => App.edit((sc) => {
        if (v === "stay") { a.behaviour = { ...(a.behaviour || {}), staysPut: true }; delete a.way; sc.routes = sc.routes.filter((r) => r.id !== a.route); a.route = null; }
        else { a.behaviour = { ...(a.behaviour || {}), staysPut: false }; a.way = v; }
      }),
      "chip:move": (v) => App.edit((sc) => {
        a.behaviour = { ...(a.behaviour || {}), staysPut: v === "stay" };
        if (v === "stay") { sc.routes = sc.routes.filter((r) => r.id !== a.route); a.route = null; }
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
  function signInspector(p, ref, o) {
    const codes = state.catalog.signs || [];
    const DIRS = [["nw", "↖"], ["north", "↑"], ["ne", "↗"], ["west", "←"], ["east", "→"], ["sw", "↙"], ["south", "↓"], ["se", "↘"]];
    const main = o.mainRoad || [], roads = o.roads || ["north", "south", "east", "west"];
    const dirChips = (name, on) => `<div class="dir-grid">${DIRS.map(([d, t]) => `<button class="${on.includes(d) ? "on" : ""}" data-chip="${name}" data-value="${d}">${t}</button>`).join("")}</div>`;
    p.innerHTML = `${head(`<img class="sign-big" src="/asset/sign/${o.code}.svg" alt="">`, Catalog.signName(o.code), `знак ${o.code}`)}
      ${card("Знак", `<div class="sign-grid">${codes.map((c) => `<button class="${c === o.code ? "on" : ""}" data-chip="code" data-value="${c}" data-tip="${esc(Catalog.signName(c))}"><img src="/asset/sign/${c}.svg" alt=""></button>`).join("")}</div>`)}
      ${card("Табличка 8.13: главная дорога", `${dirChips("main", main)}
        ${main.length ? `<div class="sub-h">Все дороги перекрёстка</div>${dirChips("roads", roads)}` : `<p class="muted">Отметьте два направления главной дороги — под знаком появится табличка.</p>`}`)}
      ${card("Надпись на табличке", `<input type="text" data-text="plate" value="${esc(o.plate || "")}" placeholder="Например: 150 м">`)}
      ${card("", `<div class="turn-row">${dial(o.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rot90", "90°", "", "ghost")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
    bind({
      ...common,
      "chip:code": (v) => App.edit(() => { o.code = v; if (v === "8.13" && !(o.mainRoad || []).length) o.mainRoad = ["south", "west"]; }),
      "chip:main": (v) => App.edit(() => {
        const set = new Set(o.mainRoad || []);
        set.has(v) ? set.delete(v) : set.add(v);
        if (set.size) o.mainRoad = [...set]; else delete o.mainRoad;
      }),
      "chip:roads": (v) => App.edit(() => {
        const set = new Set(o.roads || ["north", "south", "east", "west"]);
        set.has(v) ? set.delete(v) : set.add(v);
        o.roads = [...set];
      }),
      "text:plate": (v) => App.edit(() => { if (v.trim()) o.plate = v.trim(); else delete o.plate; }),
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
    const lamps = Catalog.LIGHTS.map((x) => `<button class="lamp ${l.state === x.id ? "on" : ""} ${x.id === "flashing_yellow" ? "blink" : ""}" data-chip="state" data-value="${x.id}" style="--c:${x.colour}" data-tip="${x.title}"></button>`).join("");
    p.innerHTML = `${head(Thumbs.img("light", "light", "big"), "Светофор", s.lights.length > 1 ? `один из ${s.lights.length}` : "")}
      ${card("Сигнал", `<div class="tlight">${lamps}</div><p class="muted">Сигнал один на всю сцену: меняется у всех светофоров.</p>`)}
      ${card("Знаки на стойке", `${[0, 1].map(slot => { const code = (l.mountedSigns || [])[slot]; return `<details><summary>${slot + 1}. ${code ? `${esc(Catalog.signName(code))} · ${code}` : "Добавить знак"}</summary><div class="sign-grid"><button class="${!code ? "on" : ""}" data-chip="mountedSign" data-slot="${slot}" data-value="">Нет</button>${[...new Set(["2.4", "8.13", ...(state.catalog.signs || [])])].map(c => `<button class="${code === c ? "on" : ""}" data-chip="mountedSign" data-slot="${slot}" data-value="${c}" data-tip="${esc(Catalog.signName(c))}"><img src="/asset/sign/${c}.svg" alt="${esc(Catalog.signName(c))}"></button>`).join("")}</div></details>`; }).join("")}`)}
            ${(l.mountedSigns || []).includes("8.13") ? card("Главная дорога на табличке", `<div class="dir-grid">${[["nw","↖"],["north","↑"],["ne","↗"],["west","←"],["east","→"],["sw","↙"],["south","↓"],["se","↘"]].map(([d,t]) => `<button class="${(l.mountedMainRoad || []).includes(d) ? "on" : ""}" data-chip="mountedMainRoad" data-value="${d}">${t}</button>`).join("")}</div>`) : ""}
      ${card("Стрелка", chips("arrow", [{ value: "", title: "Нет" }, { value: "left", icon: "arrow-left" }, { value: "straight", icon: "arrow-up" }, { value: "right", icon: "arrow-right" }], l.arrow || "", { cls: "arrows" }))}
      ${card("", `<div class="turn-row">${dial(l.yaw)}<div class="insp-actions">${button("rotl", "", "rotl", "ghost icon")}${button("rotr", "", "rotr", "ghost icon")}</div></div>${deleteRow()}`)}`;
    bind({
      ...common,
      "chip:mountedMainRoad": (v) => App.edit(() => { const roads = new Set(l.mountedMainRoad || []); roads.has(v) ? roads.delete(v) : roads.add(v); l.mountedMainRoad = [...roads]; }),
      "chip:mountedSign": (v, e) => App.edit(() => { const signs = [...(l.mountedSigns || [])]; signs[Number(e.target.closest("[data-chip]").dataset.slot)] = v; if (v === "8.13" && !(l.mountedMainRoad || []).length) l.mountedMainRoad = ["south", "west"]; if (signs.some(Boolean)) l.mountedSigns = signs; else delete l.mountedSigns; }),
      "chip:state": (v) => App.edit((sc) => sc.lights.forEach((x) => { x.state = v; })),
      "chip:arrow": (v) => App.edit(() => { l.arrow = v || null; }),
      rotl: () => App.rotate(-15), rotr: () => App.rotate(15),
    });
    bindDial(p, l);
  }

  // ---- the road plan: a street, a node -----------------------------------------------------------
  function streetInspector(p, ref, st) {
    const s = state.S, L = s.layout, crop = s.crop || 90;
    const centre = st.centre || (st.kind === "yard" ? "none" : st.kind === "avenue" ? "double" : "dashed");
    const ends = [st.a, st.b].map((nid) => {
      const n = Layout.nodeOf(L, nid), kind = Layout.nodeKind(L, n, crop);
      return { nid, end: nid === st.a ? "a" : "b", kind, set: (st.ends || {})[nid === st.a ? "a" : "b"] || {} };
    }).filter((e) => e.kind === "junction" || e.kind === "ring" || e.kind === "dead");
    const pl = Layout.playerPlan(s);
    const isPlayer = pl && pl.st.id === st.id;
    p.innerHTML = `${head(`<span class="ibadge">${ic("road")}</span>`, Layout.KINDS[st.kind || "street"].title, isPlayer ? "по ней едет игрок" : "")}
      ${card("Покрытие", chips("surface", [{ value: "asphalt", title: "Асфальт" }, { value: "sand", title: "Песок" }], st.surface || "asphalt"))}
      ${card("Ширина", chips("kind", Object.entries(Layout.KINDS).map(([k, v]) => ({ value: k, html: `<span class="road-pic k-${k}"></span>`, title: v.title })), st.kind || "street", { cls: "tiles" }))}
      ${st.kind !== "yard" ? card("Разделительная полоса", chips("median", [{ value: 0, title: "Нет" }, { value: 2, title: "2 м" }, { value: 3, title: "3 м" }, { value: 5, title: "5 м" }], Number(st.median) || 0)
        + `<p class="muted">Газон с бордюром посередине. На него можно ставить знаки и светофоры: кликните прямо на полосу.</p>`) : ""}
      ${st.kind !== "yard" && !Number(st.median) ? card("Линия по центру", chips("centre", [{ value: "dashed", html: `<span class="mark-pic m-dashed"></span>`, tip: "Прерывистая" }, { value: "solid", html: `<span class="mark-pic m-solid"></span>`, tip: "Сплошная" },
        { value: "double", html: `<span class="mark-pic m-double"></span>`, tip: "Двойная сплошная" }, { value: "none", title: "Нет" }], centre, { cls: "tiles" })) : ""}
      ${st.kind !== "yard" ? card("Разметка вручную", st.manualMarks
        ? `<p class="muted">Линии этой улицы — ваши: выберите линию, чтобы менять вид, резать и двигать точки.</p>${button("marks-auto", "Снова строить сами", "restart", "ghost wide")}`
        : `<p class="muted">Чтобы задать участок сплошной, двойную или сплошную рядом с прерывистой.</p>${button("marks-own", "Сделать линии редактируемыми", "marking", "ghost wide")}`) : ""}
      ${card("", toggle("walk", "Тротуары", st.walk !== false && st.surface !== "sand", "person") + toggle("edge", "Боковая сплошная", st.edge !== false && st.surface !== "sand", "marking") + (st.bend ? button("straighten", "Выпрямить", "road", "ghost wide") : `<p class="muted">Тяните ромб на середине, чтобы изогнуть.</p>`))}
      ${ends.length ? card("У перекрёстка", ends.map((e, i) => `<div class="end-row"><span>${ends.length > 1 ? `Конец ${i + 1}` : "Въезд"}</span>
          <button class="pick ${e.set.stop ? "on" : ""}" data-act="end" data-end="${e.end}" data-what="stop">${ic("stopline")}Стоп-линия</button>
          <button class="pick ${e.set.zebra ? "on" : ""}" data-act="end" data-end="${e.end}" data-what="zebra">${ic("zebra")}Зебра</button></div>`).join("")) : ""}
      ${card("Игрок едет по ней", `<div class="insp-actions">${[st.a, st.b].map((nid) => {
        const on = isPlayer && pl.nid === nid;
        const k = Layout.nodeKind(L, Layout.nodeOf(L, nid), crop);
        const where = k === "junction" ? "к перекрёстку" : k === "ring" ? "к кольцу" : k === "border" ? "к краю сцены" : "к концу дороги";
        return `<button class="btn ${on ? "primary" : "ghost"}" data-act="player" data-toward="${nid}">${ic("car")}${esc(where)}</button>`;
      }).join("")}</div>`)}
      ${card("", `<div class="insp-actions">${button("del", "Удалить дорогу", "trash", "danger ghost")}</div>`)}`;
    bind({
      del: () => App.remove(),
      "chip:surface": (v) => App.edit(() => { st.surface = v; }),
      "toggle:edge": (on) => App.edit(() => { st.edge = on; }),
      "chip:kind": (v) => App.edit(() => { st.kind = v; }),
      "chip:centre": (v) => App.edit(() => { st.centre = v; }),
      "chip:median": (v) => App.edit(() => { if (Number(v)) st.median = Number(v); else delete st.median; }),
      "toggle:walk": (on) => App.edit(() => { if (on) delete st.walk; else st.walk = false; }),
      straighten: () => App.edit(() => { st.bend = null; }),
      "marks-own": () => App.edit((sc) => {
        const own = sc.markings.filter((m) => m.auto && m.street === st.id && (m.type === "solid" || m.type === "dashed"));
        for (const m of own) sc.markings.push({ ...JSON.parse(JSON.stringify(m)), id: App.uniqueId("mark_", sc.markings.map((x) => x.id)), auto: undefined, street: undefined });
        st.manualMarks = true;
      }),
      "marks-auto": () => App.edit(() => { delete st.manualMarks; }),
      end: (d) => App.edit(() => {
        st.ends = st.ends || {};
        st.ends[d.end] = { ...(st.ends[d.end] || {}) };
        st.ends[d.end][d.what] = !st.ends[d.end][d.what];
      }),
      player: (d) => App.edit((sc) => { sc.layout.player = { street: st.id, toward: d.toward }; }),
    });
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
      ${kind === "junction" || kind === "ring" ? card("Светофоры", hasLights
        ? `${button("lights-off", "Убрать светофоры", "light", "ghost wide")}`
        : `${button("lights-on", "Поставить на все въезды", "light", "primary wide")}`) : ""}
      ${card("", `<p class="muted">Тяните точку, чтобы двигать. Бросьте на другую — соединятся.</p><div class="insp-actions">${button("del", "Удалить с дорогами", "trash", "danger ghost")}</div>`)}`;
    bind({
      del: () => App.remove(),
      "chip:ring": (v) => App.edit(() => { if (v === "ring") n.ring = { r: 20, island: 9 }; else delete n.ring; }),
      "chip:size": (v) => App.edit(() => { const x = sizes.find((y) => y.value === v); n.ring = { r: x.r, island: x.island }; }),
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
  function routeInspector(p, ref, r) {
    const s = state.S;
    if (r.kind === "choice") {
      const used = s.routes.filter((x) => x.kind === "choice" && x !== r).map((x) => x.label);
      const ways = s.routes.filter((x) => x.kind === "manoeuvre");
      p.innerHTML = `${head(`<span class="letter-badge" style="--c:${Catalog.LETTER_COLOUR[r.label]}">${esc(r.label)}</span>`, `Вариант ответа ${r.label}`, "линия на дороге при вопросе")}
        ${card("Буква", chips("label", Catalog.LETTERS.map((l) => ({ value: l, html: `<span class="letter-badge sm" style="--c:${Catalog.LETTER_COLOUR[l]}">${l}</span>`, disabled: used.includes(l) })), r.label))}
        ${ways.length ? card("Взять путь", chips("copy", ways.map((w) => ({ value: w.exit, icon: Catalog.EXITS[w.exit].icon, tip: Catalog.EXITS[w.exit].title })), "", { cls: "arrows" })) : ""}
        ${card("", `<p class="muted">Тяните точки на виде. Двойной клик по линии — новая точка.</p>${button("mid", "Букву — на середину", "flag", "ghost wide")}<div class="insp-actions">${button("del", "Удалить", "trash", "danger ghost")}</div>`)}`;
      bind({
        ...common,
        "chip:label": (v) => App.edit(() => { r.label = v; r.id = `choice_${v}`; }) || App.select({ t: "route", id: `choice_${v}` }),
        "chip:copy": (v) => App.edit((sc) => { const w = sc.routes.find((x) => x.kind === "manoeuvre" && x.exit === v); r.points = JSON.parse(JSON.stringify(w.points)); const m = r.points[Math.floor(r.points.length * 0.6)]; r.labelPosition = [m[0], m[1]]; }),
        mid: () => App.edit(() => { const m = r.points[Math.floor(r.points.length / 2)]; r.labelPosition = [m[0], m[1]]; }),
      });
      return;
    }
    if (r.kind === "manoeuvre") {
      const main = s.question.maneuver === r.exit;
      p.innerHTML = `${head(`<span class="ibadge">${ic(Catalog.EXITS[r.exit]?.icon || "route")}</span>`, `Манёвр: ${Catalog.EXITS[r.exit]?.title.toLowerCase()}`, main ? "так едет игрок" : "другой выезд")}
        ${card("", `${main ? `<p class="ok-line">${ic("check-circle")}Этот манёвр — по условию вопроса</p>` : button("make-main", "Игрок едет так", "flag", "primary wide")}
          ${r.auto ? `<p class="muted">Путь строится сам по дорогам.</p>${button("own-path", "Править путь вручную", "points", "ghost wide")}`
            : `<p class="muted">Тяните точки на виде, двойной клик по линии — новая точка.</p>${r.manual ? button("auto-path", "Снова строить по дорогам", "restart", "ghost wide") : ""}`}
          <p class="muted">По этой линии машина игрока едет после ответа. Если в вопросе есть линии ответов, она видна только когда выбрана.</p>`)}`;
      bind({
        "make-main": () => App.edit((sc) => { sc.question.maneuver = r.exit; sc.spec = { ...(sc.spec || {}), maneuver: r.exit }; }),
        "own-path": () => App.edit((sc) => { const x = sc.routes.find((y) => y.id === r.id); x.manual = true; delete x.auto; }),
        "auto-path": () => App.edit((sc) => { if (sc.layout.paths) delete sc.layout.paths[r.exit]; const x = sc.routes.find((y) => y.id === r.id); delete x.manual; x.auto = true; }),
      });
      return;
    }
    const actor = r.kind === "actor" ? s.actors.find((a) => a.route === r.id) : null;
    p.innerHTML = `${head(`<span class="ibadge">${ic("route")}</span>`, App.nameOf(ref), r.auto ? "строится сам" : "")}
      ${card("", `${actor ? button("actor", "К участнику", "car", "ghost wide") : ""}<p class="muted">${r.kind === "approach" ? "Подъезд игрока к стоп-линии." : "Тяните точки на виде."}</p>`)}`;
    bind({ actor: () => App.select({ t: "actor", id: actor.id }) });
  }

  // ---- markings and shapes -------------------------------------------------------------------
  function markingInspector(p, ref, m) {
    const paint = m.type === "paint";
    p.innerHTML = `${head(`<span class="ibadge">${ic("marking")}</span>`, App.nameOf(ref), paint ? "снята с картинки билета" : "")}
      ${paint ? "" : card("Вид", chips("type", Object.entries(Catalog.MARKS).map(([k, v]) => ({ value: k, html: `<span class="mark-pic m-${k}"></span>`, tip: v.title })), m.type, { cls: "tiles" }))}
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
      }),
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

  function stopInspector(p) {
    const s = state.S, q = s.question;
    const routes = s.routes.filter((r) => r.kind === "manoeuvre").map((r) => r.exit);
    const plan = s.layout ? Layout.playerPlan(s) : null;
    p.innerHTML = `${head(`<span class="ibadge">${ic("car")}</span>`, "Игрок", "место начала вопроса")}
      ${card("Едет", chips("maneuver", ["left", "straight", "right", "uturn"].map((k) => ({ value: k, icon: Catalog.EXITS[k].icon, tip: Catalog.EXITS[k].title, disabled: !routes.includes(k) && k !== "straight" })), q.maneuver, { cls: "arrows" }))}
      ${plan ? card("Начало вопроса", slider("questionOffset", "Раньше стоп-линии", Math.max(0, plan.sd - plan.stopLineDistance - 2.4), 0, Math.min(60, Math.max(0, plan.total - plan.stopLineDistance - 3.4)), 0.5, `${Math.max(0, plan.sd - plan.stopLineDistance - 2.4).toFixed(1)} м`) + button("question-at-line", "Вернуть к стоп-линии", "restart", "ghost wide")) : ""}
      ${card("", `<p class="muted">${s.layout ? "Место игрока строится по дороге: выберите дорогу и нажмите «Ехать сюда»." : "Тяните машину на виде вдоль полосы."}</p>`)}`;
    bind({
      "slider:questionOffset": live((sc, v) => { const pl = Layout.playerPlan(sc); sc.layout.player = { ...(sc.layout.player || {}), street: pl.st.id, toward: pl.nid, questionAt: r3(pl.stopLineDistance + 2.4 + v) }; }, v => { const el = pane().querySelector('[data-shown="questionOffset"]'); if (el) el.textContent = `${v.toFixed(1)} м`; }),
      "question-at-line": () => App.edit(sc => { if (sc.layout.player) delete sc.layout.player.questionAt; }),
      "chip:maneuver": (v) => App.edit((sc) => { sc.question.maneuver = v; sc.spec = { ...(sc.spec || {}), maneuver: v }; }) });
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
