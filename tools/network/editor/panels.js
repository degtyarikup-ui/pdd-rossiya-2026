// The left side: scenes, layers (with eye and lock), the library of objects (drag them into the view)
// and the textures; and the home screen with every scene as a card.
(() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, state } = App;
  state.ltab = "scenes";
  state.texSel = null;
  let query = "", filter = "all", libQuery = "", open = { decor: false };

  // ---- dispatch ----------------------------------------------------------------------------
  App.renderPanels = (o = {}) => {
    const only = o.only;
    if (!only || only.includes("left") || only.includes("layers")) renderLeft();
    if (!only || only.includes("inspector")) App.renderInspector?.();
    if (!only) Tools.renderBar();
  };
  App.setLeftTab = (name) => {
    state.ltab = name;
    if (name !== "textures") state.texSel = null;
    document.querySelectorAll("[data-ltab]").forEach((b) => b.classList.toggle("on", b.dataset.ltab === name));
    renderLeft();
    App.renderInspector?.();
  };
  document.querySelectorAll("[data-ltab]").forEach((b) => b.addEventListener("click", () => App.setLeftTab(b.dataset.ltab)));

  function renderLeft() {
    const body = $("#left-body");
    const tab = state.ltab;
    if (tab === "scenes") body.innerHTML = scenesPane();
    else if (tab === "layers") body.innerHTML = layersPane();
    else if (tab === "library") body.innerHTML = libraryPane();
    else body.innerHTML = texturesPane();
    Thumbs.fillAll(body);
    if (tab === "textures") body.querySelectorAll("canvas[data-tex]").forEach((c) => Textures.draw(c, c.dataset.tex, "final", 2));
    const input = body.querySelector("input[type=search]");
    if (input && renderLeft.focus) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
    renderLeft.focus = false;
  }

  // ---- scenes --------------------------------------------------------------------------------
  const FILTERS = [["all", "Все"], ["game", "В игре"], ["err", "С ошибками"], ["plan", "Конструктор"]];
  function filtered() {
    const q = query.trim().toLowerCase();
    return state.scenes.filter((s) => {
      if (q && !(s.id.includes(q.replace(/\s+/g, "_")) || App.sceneTitle(s.id).toLowerCase().includes(q) || (s.questionText || "").toLowerCase().includes(q))) return false;
      if (filter === "game") return s.playable;
      if (filter === "err") return s.errors > 0;
      if (filter === "plan") return s.layout;
      return true;
    });
  }
  const thumbUrl = (s) => s.preview ? `/preview/${s.id}.png?v=${App.thumbRev[s.id] || 0}` : "";
  function scenesPane() {
    const list = filtered();
    return `<div class="pane-head"><label class="search">${ic("search")}<input type="search" id="scene-q" placeholder="Билет, например 10 13" value="${esc(query)}"></label>
      <div class="chips">${FILTERS.map(([k, t]) => `<button class="${filter === k ? "on" : ""}" data-filter="${k}">${t}</button>`).join("")}</div></div>
      <div class="scene-list">${list.map((s) => `<button class="scene-row ${s.id === state.id ? "on" : ""}" data-scene="${s.id}">
        <span class="scene-pic">${s.preview ? `<img src="${thumbUrl(s)}" loading="lazy" alt="">` : ""}</span>
        <span class="scene-text"><b>${esc(App.sceneTitle(s.id))}</b><small>${esc(s.questionText)}</small>
        <span class="badges">${badges(s)}</span></span></button>`).join("") || `<p class="empty-note">Ничего не нашлось</p>`}</div>`;
  }
  function badges(s) {
    const out = [];
    if (s.errors) out.push(`<i class="badge bad">${ic("error")}${s.errors}</i>`);
    if (s.playable) out.push(`<i class="badge good">${ic("gamepad")}в игре</i>`);
    if (s.layout) out.push(`<i class="badge">${ic("junction")}конструктор</i>`);
    if (s.regulator) out.push(`<i class="badge">регулировщик</i>`);
    return out.join("");
  }

  // The home screen: the same scenes, big.
  App.renderHome = () => {
    const list = filtered();
    $("#home-screen").innerHTML = `<div class="home-head">
        <div><h1>Сцены игры</h1><p>${state.scenes.length} перекрёстков из билетов · в игре ${state.scenes.filter((s) => s.playable).length}</p></div>
        <label class="search big">${ic("search")}<input type="search" id="home-q" placeholder="Номер билета или слова из вопроса" value="${esc(query)}"></label>
        ${state.S ? `<button class="btn ghost" id="home-back">${ic("x")}Вернуться к сцене</button>` : ""}
      </div>
      <div class="chips home-chips">${FILTERS.map(([k, t]) => `<button class="${filter === k ? "on" : ""}" data-filter="${k}">${t} <em>${count(k)}</em></button>`).join("")}</div>
      <div class="home-grid">${list.map((s) => `<button class="card-scene" data-scene="${s.id}">
        <span class="card-pic">${s.preview ? `<img src="${thumbUrl(s)}" loading="lazy" alt="">` : `<span class="no-pic">${ic("image")}</span>`}</span>
        <span class="card-body"><b>${esc(App.sceneTitle(s.id))}</b><small>${esc(s.questionText)}</small><span class="badges">${badges(s)}</span></span>
      </button>`).join("") || `<p class="empty-note">Ничего не нашлось</p>`}</div>`;
    const q = $("#home-q");
    if (renderHome.focus) { q.focus(); q.setSelectionRange(q.value.length, q.value.length); }
    renderHome.focus = false;
  };
  const renderHome = App.renderHome;
  const count = (k) => state.scenes.filter((s) => k === "all" || (k === "game" && s.playable) || (k === "err" && s.errors) || (k === "plan" && s.layout)).length;

  document.addEventListener("input", (e) => {
    if (e.target.id === "scene-q" || e.target.id === "home-q") {
      query = e.target.value;
      if (e.target.id === "home-q") { renderHome.focus = true; App.renderHome(); } else { renderLeft.focus = true; renderLeft(); }
    }
    if (e.target.id === "lib-q") { libQuery = e.target.value; renderLeft.focus = true; renderLeft(); }
  });
  document.addEventListener("click", (e) => {
    const f = e.target.closest("[data-filter]");
    if (f) { filter = f.dataset.filter; renderLeft(); if (!$("#home-screen").hidden) App.renderHome(); return; }
    const sc = e.target.closest("[data-scene]");
    if (sc) { App.openScene(sc.dataset.scene).catch((err) => App.toast(err.message, "bad")); return; }
    if (e.target.closest("#home-back")) App.showHome(false);
  });

  // ---- layers ----------------------------------------------------------------------------------
  const LAYERS = [
    { id: "roads", title: "Дороги", icon: "road" },
    { id: "marks", title: "Разметка", icon: "marking" },
    { id: "routes", title: "Маршруты и ответы", icon: "route" },
    { id: "actors", title: "Машины и люди", icon: "car" },
    { id: "lights", title: "Светофоры", icon: "light" },
    { id: "decor", title: "Дома, деревья, предметы", icon: "tree" },
  ];
  function rowsOf(layer) {
    const s = state.S;
    if (!s) return [];
    switch (layer) {
      case "roads":
        if (s.layout) {
          return [...s.layout.nodes.filter((n) => Layout.nodeKind(s.layout, n, s.crop || 90) === "junction" || n.ring).map((n) => ({ t: "node", id: n.id })),
            ...s.layout.streets.map((st) => ({ t: "street", id: st.id })), ...s.roads.filter((r) => !r.auto).map((r) => ({ t: "road", id: r.id, part: -1 })),
            ...s.lawns.filter((l) => !l.auto).map((l) => ({ t: "lawn", id: l.id }))];
        }
        return [...s.roads.flatMap((r) => [{ t: "road", id: r.id, part: -1 }, ...(r.holes || []).map((_, k) => ({ t: "road", id: r.id, part: k }))]),
          ...s.lawns.map((l) => ({ t: "lawn", id: l.id }))];
      case "marks": return s.markings.filter((m) => !m.auto).map((m) => ({ t: "marking", id: m.id }));
      case "routes": return s.routes.filter((r) => r.kind !== "actor").map((r) => ({ t: "route", id: r.id }));
      case "actors": return [{ t: "stop" }, ...s.actors.map((a) => ({ t: "actor", id: a.id }))];
      case "lights": return s.lights.map((l) => ({ t: "light", id: l.id }));
      case "decor": return s.decor.map((d) => ({ t: "decor", id: d.id }));
      default: return [];
    }
  }
  function rowIcon(ref) {
    const o = App.objectOf(ref);
    if (ref.t === "decor") return Thumbs.img("prop", o.prop, "mini");
    if (ref.t === "actor") return Thumbs.img("actor", o.type, "mini");
    return ic({ node: o?.ring ? "ring" : "junction", street: "road", road: ref.part >= 0 ? "lawn" : "road", lawn: "lawn", marking: "marking",
      route: "route", light: "light", stop: "flag" }[ref.t] || "info");
  }
  function layersPane() {
    if (!state.S) return `<p class="empty-note">Откройте сцену</p>`;
    const isOn = (r) => state.sel.some((x) => App.sameRef(x, r));
    return `<div class="layers">${LAYERS.map((L) => {
      const rows = rowsOf(L.id);
      const hiddenL = state.hidden.has(L.id), lockedL = state.locked.has(L.id);
      const expanded = open[L.id] !== false;
      let body = "";
      if (expanded) {
        if (L.id === "decor") {
          // Props by kind: "Ель × 40", each kind opens to its items.
          const byProp = {};
          rows.forEach((r) => { const p = App.objectOf(r).prop; (byProp[p] = byProp[p] || []).push(r); });
          body = Object.entries(byProp).sort((a, b) => b[1].length - a[1].length).map(([p, list]) => {
            const key = "decor:" + p, op = open[key];
            const any = list.some(isOn);
            return `<div class="lrow sub ${any ? "on-in" : ""}" data-kind="${esc(p)}">${Thumbs.img("prop", p, "mini")}<span>${esc(Catalog.propName(p))}</span><em>${list.length}</em>
              <button class="lbtn" data-open="${esc(key)}">${ic("chevron", op ? "rot" : "")}</button></div>`
              + (op ? list.map((r, i) => `<div class="lrow sub2 ${isOn(r) ? "on" : ""}" data-ref='${esc(JSON.stringify(r))}'><span>${esc(Catalog.propName(p))} ${i + 1}</span></div>`).join("") : "");
          }).join("");
        } else {
          body = rows.map((r) => `<div class="lrow ${isOn(r) ? "on" : ""}" data-ref='${esc(JSON.stringify(r))}'>${rowIcon(r)}<span>${esc(App.nameOf(r))}</span></div>`).join("");
        }
      }
      return `<section class="lgroup ${hiddenL ? "off" : ""}">
        <div class="lhead" data-open="${L.id}"><span class="caret">${ic("chevron", expanded ? "rot" : "")}</span>${ic(L.icon)}<b>${L.title}</b><em>${L.id === "actors" ? rows.length - 1 : rows.length}</em>
          <button class="lbtn ${lockedL ? "on" : ""}" data-lock="${L.id}" data-tip="${lockedL ? "Открыть" : "Запереть"}">${ic(lockedL ? "lock" : "unlock")}</button>
          <button class="lbtn ${hiddenL ? "on" : ""}" data-eye="${L.id}" data-tip="${hiddenL ? "Показать" : "Скрыть"}">${ic(hiddenL ? "eye-off" : "eye")}</button></div>
        ${expanded ? `<div class="lbody">${body}</div>` : ""}</section>`;
    }).join("")}</div>`;
  }
  $("#left-body").addEventListener("click", (e) => {
    const eye = e.target.closest("[data-eye]");
    if (eye) { e.stopPropagation(); return App.toggleHidden(eye.dataset.eye); }
    const lock = e.target.closest("[data-lock]");
    if (lock) { e.stopPropagation(); return App.toggleLocked(lock.dataset.lock); }
    const op = e.target.closest("[data-open]");
    if (op) { const k = op.dataset.open; open[k] = k.startsWith("decor:") ? !open[k] : open[k] === false; return renderLeft(); }
    const kind = e.target.closest("[data-kind]");
    if (kind) {
      const list = state.S.decor.filter((d) => d.prop === kind.dataset.kind).map((d) => ({ t: "decor", id: d.id }));
      return App.select(list.filter(App.pickable), { add: e.shiftKey });
    }
    const row = e.target.closest("[data-ref]");
    if (row) {
      const ref = JSON.parse(row.dataset.ref);
      if (!App.pickable(ref)) return App.toast("Слой заперт или скрыт", "warn");
      e.shiftKey ? App.toggle(ref) : App.select(ref);
      if (e.detail === 2) Tools.fitSelection();
      return;
    }
    const lib = e.target.closest("[data-lib]");
    if (lib) {
      const item = JSON.parse(lib.dataset.lib);
      if (!state.S) return App.toast("Сначала откройте сцену", "warn");
      if (item.kind === "prop") Tools.pickProp(item.id);
      else if (item.kind === "actor") Tools.pickActor(item.id);
      else Tools.set("light");
      return renderLeft();
    }
    const tex = e.target.closest("[data-texrow]");
    if (tex) { state.texSel = tex.dataset.texrow; renderLeft(); App.renderInspector?.(); }
  });

  // ---- library ----------------------------------------------------------------------------------
  function libraryPane() {
    const cat = state.catalog;
    if (!cat) return "";
    const q = libQuery.trim().toLowerCase();
    const hit = (name) => !q || name.toLowerCase().includes(q);
    const tile = (item, name, pic, on) => `<button class="lib-tile ${on ? "on" : ""}" draggable="true" data-lib='${esc(JSON.stringify(item))}' data-tip="${esc(name)}">${pic}<span>${esc(name)}</span></button>`;
    const sections = [];
    const vehicles = Catalog.ACTOR_ORDER.filter((t) => cat.actorTypes[t] && hit(Catalog.ACTORS[t].name));
    if (vehicles.length) sections.push(`<h4>${ic("car")}Машины и люди</h4><div class="lib-grid">${vehicles.map((t) => tile({ kind: "actor", id: t }, Catalog.ACTORS[t].name, Thumbs.img("actor", t), Tools.current() === "actor" && Tools.opts.actorType === t)).join("")}</div>`);
    if (cat.lightAsset && hit("светофор")) sections.push(`<h4>${ic("light")}Светофор</h4><div class="lib-grid">${tile({ kind: "light", id: "light" }, "Светофор", Thumbs.img("light", "light"), Tools.current() === "light")}</div>`);
    const props = [...cat.props.map((p) => p.id), "parked"];
    for (const g of Catalog.PROP_GROUPS) {
      const items = props.filter((p) => g.match(p) && hit(Catalog.propName(p)));
      if (!items.length) continue;
      sections.push(`<h4>${ic(g.icon)}${g.title}</h4><div class="lib-grid">${items.map((p) => tile({ kind: "prop", id: p }, Catalog.propName(p), Thumbs.img("prop", p), Tools.current() === "prop" && Tools.opts.prop === p)).join("")}</div>`);
    }
    return `<div class="pane-head"><label class="search">${ic("search")}<input type="search" id="lib-q" placeholder="Найти: ель, автобус, киоск" value="${esc(libQuery)}"></label></div>
      <div class="lib">${sections.join("") || `<p class="empty-note">Ничего не нашлось</p>`}</div>`;
  }
  $("#left-body").addEventListener("dragstart", (e) => {
    const t = e.target.closest("[data-lib]");
    if (!t) return;
    e.dataTransfer.setData("text/x-scene-item", t.dataset.lib);
    e.dataTransfer.effectAllowed = "copy";
    const img = t.querySelector("img");
    if (img && img.src) e.dataTransfer.setDragImage(img, 40, 40);
  });

  // ---- textures --------------------------------------------------------------------------------
  function texturesPane() {
    return `<div class="tex-list">${Textures.GROUPS.map((g) => {
      const kinds = Textures.state.list.map((t) => t.kind).filter((k) => (Textures.INFO[k] || {}).group === g.id);
      if (!kinds.length) return "";
      return `<h4>${g.title}</h4><div class="tex-grid">${kinds.map((k) => `<button class="tex-tile ${state.texSel === k ? "on" : ""}" data-texrow="${k}">
        <canvas width="72" height="72" data-tex="${k}"></canvas><span>${esc(Textures.INFO[k]?.name || k)}</span>${Textures.isDirty(k) ? `<i class="dot"></i>` : ""}</button>`).join("")}</div>`;
    }).join("")}</div>`;
  }
})();
