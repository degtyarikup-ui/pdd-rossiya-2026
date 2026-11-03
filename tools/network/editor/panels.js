// The left side: scenes, layers (with eye and lock), the library of objects (drag them into the view)
// and the textures; and the home screen with every scene as a card.
(() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, state } = App;
  state.ltab = "scenes";
  state.texSel = null;
  let query = "", filter = "all", libQuery = "", libraryCategory = "all", filtersCollapsed = false, open = { decor: false };
  let signGroup = "";
  const COLLAPSE_STORAGE = "network-editor-scene-filters-collapsed";
  const LIBRARY_STORAGE = "network-editor-library-category";
  const LIBRARY_CATEGORIES = [["all", "Все"], ["traffic", "Транспорт"], ["signs", "Знаки"], ["decor", "Окружение"]];
  try {
    filtersCollapsed = localStorage.getItem(COLLAPSE_STORAGE) === "true";
    const category = localStorage.getItem(LIBRARY_STORAGE);
    if (LIBRARY_CATEGORIES.some(([key]) => key === category)) libraryCategory = category;
  } catch (_) { /* Optional workspace preferences. */ }

  // ---- dispatch ----------------------------------------------------------------------------
  App.renderPanels = (o = {}) => {
    const only = o.only;
    if (!only || only.includes("left")) renderLeft();
    else if (only.includes("layers") && App.leftPanelOpen?.() !== false) {
      if (state.ltab === "layers") updateSelectedRows();
      if (state.ltab === "textures" && !state.texSel) {
        const tile = $("#left-body").querySelector(".tex-tile.on");
        tile?.classList.remove("on");
        tile?.setAttribute("aria-pressed", "false");
      }
    }
    if (!only || only.includes("inspector")) App.renderInspector?.();
    if (!only) Tools.renderBar();
  };
  App.setLeftTab = (name) => {
    const switching = state.ltab !== name;
    state.ltab = name;
    App.showLeftPanel?.(name);
    if (name !== "textures") state.texSel = null;
    if (name === "layers" && state.sel?.length === 1) {
      const ref = state.sel[0];
      open[App.layerOf(ref)] = true;
      if (ref.t === "decor") open["decor:" + App.objectOf(ref).prop] = true;
    }
    document.querySelectorAll("[data-ltab]").forEach((b) => b.classList.toggle("on", b.dataset.ltab === name));
    renderLeft();
    if (switching) $("#left-body").scrollTop = 0;
    if (name === "scenes" || name === "layers") {
      const current = $("#left-body").querySelector(name === "scenes" ? ".scene-row.on" : ".lrow.on");
      if (current) current.scrollIntoView({block:"center"});
    }
    App.renderInspector?.();
  };
  document.querySelectorAll("[data-ltab]").forEach((b) => b.addEventListener("click", () => {
    if (state.ltab === b.dataset.ltab && App.leftPanelOpen?.()) App.closeLeftPanel();
    else App.setLeftTab(b.dataset.ltab);
  }));
  App.libraryCategory = () => libraryCategory;
  App.setLibraryCategory = (category, { open: show = true, clearSearch = true } = {}) => {
    if (!LIBRARY_CATEGORIES.some(([key]) => key === category)) return;
    libraryCategory = category;
    if (clearSearch) { libQuery = ""; signGroup = ""; }
    try { localStorage.setItem(LIBRARY_STORAGE, category); } catch (_) { /* Optional preference. */ }
    if (show) App.setLeftTab("library");
    else if (state.ltab === "library") renderLeft();
  };

  // The lists are rebuilt when selection or filtering changes. Keep keyboard focus
  // on the same control if it still exists in the new list.
  function focusKey(root) {
    const el = document.activeElement;
    if (!el || !root.contains(el) || !el.matches("button, select")) return null;
    if (el.id) return "#" + CSS.escape(el.id);
    const attr = Array.from(el.attributes).find(a => a.name.startsWith("data-") && a.name !== "data-tip");
    return attr ? `[${attr.name}="${CSS.escape(attr.value)}"]` : null;
  }
  function renderLeft() {
    if (App.leftPanelOpen?.() === false) return;
    const body = $("#left-body");
    const focused = focusKey(body);
    const tab = state.ltab;
    if (tab === "scenes") body.innerHTML = scenesPane();
    else if (tab === "layers") body.innerHTML = layersPane();
    else if (tab === "library") body.innerHTML = libraryPane();
    else body.innerHTML = texturesPane();
    Thumbs.fillAll(body);
    if (tab === "textures") body.querySelectorAll("canvas[data-tex]").forEach((c) => Textures.draw(c, c.dataset.tex, "final", 2));
    const input = body.querySelector("input[type=search]");
    if (input && renderLeft.focus) { input.focus(); input.setSelectionRange(...renderLeft.focus); }
    else if (focused) body.querySelector(focused)?.focus({ preventScroll: true });
    renderLeft.focus = false;
  }

  // ---- scenes --------------------------------------------------------------------------------
  const FILTERS = [["game", "В игре"], ["all", "Все созданные сцены"], ["err", "С ошибками"], ["assistant", "На одобрение"], ["questions", "План вопросов"]];
  const SECTIONS = [["scenes", "Игровые сцены", "gamepad"], ["assistant", "На одобрение", "check-circle"], ["questions", "План вопросов", "ticket"]];
  const APPROVAL_FILTERS = [["pending", "Ожидают одобрения"], ["approved", "Одобрены вами"], ["all", "Все сцены Codex"]];
  let approvalFilter = "pending", sceneSubfilter = "all";
  const FILTER_STORAGE = "network-editor-scene-filter";
  const linkedFilter = new URLSearchParams(location.search).get("filter");
  try {
    const saved = linkedFilter || localStorage.getItem(FILTER_STORAGE);
    if (FILTERS.some(([key]) => key === saved)) filter = saved;
    if (["all", "game", "err"].includes(filter)) sceneSubfilter = filter;
    if (linkedFilter && filter === linkedFilter) localStorage.setItem(FILTER_STORAGE, filter);
  } catch (_) { /* Filtering also works when browser storage is unavailable. */ }
  const isAssistant = s => s.assistantReview?.author === "codex";
  const section = () => filter === "questions" ? "questions" : filter === "assistant" ? "assistant" : "scenes";
  const pendingApproval = s => isAssistant(s) && (s.assistantReview.status !== "approved" || !s.playable);
  function sectionNav() {
    return `<nav class="scene-sections" aria-label="Разделы сцен">${SECTIONS.map(([key, label, icon]) => `<button class="${section() === key ? "on" : ""}" data-scene-section="${key}" aria-pressed="${section() === key}">${ic(icon)}<span>${label}</span><em>${key === "assistant" ? count("assistant") : count(key === "scenes" ? "all" : "questions")}</em></button>`).join("")}</nav>`;
  }
  function statusOptions() {
    if (section() === "questions") return "";
    const options = section() === "assistant" ? APPROVAL_FILTERS : FILTERS.filter(([key]) => ["all", "game", "err"].includes(key));
    const selected = section() === "assistant" ? approvalFilter : filter;
    return `<label class="scene-status-filter">${section() === "assistant" ? "Статус одобрения" : "Показать сцены"}<select data-scene-status aria-label="${section() === "assistant" ? "Статус одобрения" : "Показать сцены"}">${options.map(([key, label]) => `<option value="${key}" ${selected === key ? "selected" : ""}>${label}</option>`).join("")}</select></label>`;
  }
  function filtered() {
    const q = query.trim().toLowerCase().replaceAll("ё", "е");
    const ticket = q.match(/^(?:билет\s*№?\s*)?(\d+)[\s.,·/_-]+(?:вопрос\s*№?\s*)?(\d+)$/);
    const singleTicket = !ticket && q.match(/^(?:билет\s*№?\s*)?(\d+)$/);
    const words = q.split(/\s+/);
    return state.scenes.filter((s) => {
      if ((s.id === "mini_regulator") !== (state.section === "regulator")) return false;
      if (state.section === "regulator") return true;
      if (filter === "assistant") {
        if (!isAssistant(s) || (approvalFilter === "pending" && !pendingApproval(s)) || (approvalFilter === "approved" && pendingApproval(s))) return false;
      } else if (isAssistant(s) && pendingApproval(s)) return false;
      if (ticket) {
        if (!s.id.endsWith(`_${Number(ticket[1])}_${Number(ticket[2])}`)) return false;
      } else if (singleTicket) {
        if (!s.id.startsWith(`ticket_${Number(singleTicket[1])}_`)) return false;
      } else if (q) {
        const text = [s.id, App.sceneTitle(s.id), s.questionText].join(" ").toLowerCase().replaceAll("ё", "е");
        if (!words.every(word => text.includes(word))) return false;
      }
      if (filter === "game") return s.playable;
      if (filter === "err") return s.errors > 0;
      return true;
    }).sort((a, b) => {
      const first = a.id.match(/^ticket_(\d+)_(\d+)$/), second = b.id.match(/^ticket_(\d+)_(\d+)$/);
      return first && second ? Number(first[1]) - Number(second[1]) || Number(first[2]) - Number(second[2]) : a.id.localeCompare(b.id);
    });
  }
  function scenePicture(s) {
    if (s.preview) return `<img src="/preview/${esc(s.id)}.png?v=${App.thumbRev[s.id] || 0}" loading="lazy" decoding="async" alt="">`;
    return `<span class="no-pic" aria-label="Без превью">${ic("map")}</span>`;
  }
  function scenesPane() {
    const questions = filter === "questions" && state.section !== "regulator";
    const list = questions ? [] : filtered();
    return `${state.section === "regulator" ? "" : `<div class="pane-head"><label class="search">${ic("search")}<input type="search" id="scene-q" aria-label="Поиск сцен" placeholder="Билет или текст вопроса" value="${esc(query)}"></label>
      ${sectionNav()}<div class="scene-filter-bar"><span class="scene-filter-current" ${filtersCollapsed || questions ? "" : "hidden"}>${questions && QuestionPlan.filterSummary ? esc(QuestionPlan.filterSummary().label) : filter === "assistant" ? esc(APPROVAL_FILTERS.find(([key]) => key === approvalFilter)[1]) : esc(FILTERS.find(([key]) => key === filter)[1])} <em>${questions && QuestionPlan.filterSummary ? QuestionPlan.filterSummary(query).count : list.length}</em></span>
      <div id="scene-filters" ${filtersCollapsed ? "hidden" : ""}>${statusOptions()}</div><button class="scene-filter-toggle" data-toggle-scene-filters aria-expanded="${!filtersCollapsed}" aria-controls="scene-filters" aria-label="${filtersCollapsed ? "Показать фильтры" : "Скрыть фильтры"}" title="Фильтры">${ic("sliders")}</button></div></div>`}
      ${questions ? QuestionPlan.sidebarHtml(query, { filtersCollapsed }) : `<div class="scene-list">${list.map((s) => `<button class="scene-row ${s.id === state.id ? "on" : ""}" data-scene="${esc(s.id)}" ${s.id === state.id ? 'aria-current="true"' : ""}>
        <span class="scene-pic">${scenePicture(s)}</span>
        <span class="scene-text"><b>${esc(App.sceneTitle(s.id))}</b>
        <span class="badges">${badges(s)}</span></span></button>`).join("") || `<p class="empty-note">Ничего не нашлось</p>`}</div>`}`;
  }
  function badges(s) {
    const out = [];
    if (s.playable) out.push(`<i class="badge good">${ic("gamepad")}В игре</i>`);
    else if (!isAssistant(s) && s.id !== "mini_regulator") out.push('<i class="badge">Черновик</i>');
    if (s.errors) out.push(`<i class="badge bad" title="Ошибки проверки">${ic("error")}${s.errors}</i>`);
    if (isAssistant(s)) out.push(`<i class="badge ${pendingApproval(s) ? "" : "good"}">${pendingApproval(s) ? "На одобрении" : "Одобрено"}</i>`);
    if (s.regulator) out.push(`<i class="badge">Регулировщик</i>`);
    return out.join("");
  }

  // The home screen: the same scenes, big.
  App.renderHome = () => {
    const regulator = state.section === "regulator";
    const questions = !regulator && filter === "questions";
    const list = questions ? [] : filtered();
    const title = regulator ? "Регулировщик" : questions ? "План вопросов" : filter === "assistant" ? "Сцены Codex" : "Библиотека сцен";
    const total = questions ? QuestionPlan.filterSummary?.(query).count : list.length;
    const home = $("#home-screen");
    const focused = focusKey(home);
    home.innerHTML = `<div class="scene-browser"><div class="home-head">
        <h1>${title}${total != null ? ` <span class="browser-total">${total}</span>` : ""}</h1>
        ${regulator ? "" : `<label class="search big">${ic("search")}<input type="search" id="home-q" aria-label="Поиск по билетам и вопросам" placeholder="Билет или текст вопроса" value="${esc(query)}"></label>`}
        ${state.S ? `<button class="btn ghost" id="home-back">${ic("map")}К сцене</button>` : ""}
      </div>
      ${regulator ? "" : `<div class="home-scene-navigation">${sectionNav()}${statusOptions()}</div>`}
      ${questions ? QuestionPlan.homeHtml(query) : `<div class="home-grid">${list.map((s) => `<button class="card-scene ${s.id === state.id ? "current" : ""}" data-scene="${esc(s.id)}">
        <span class="card-pic">${scenePicture(s)}<span class="card-badges badges">${badges(s)}</span></span>
        <span class="card-body"><b>${esc(App.sceneTitle(s.id))}</b>${s.questionText ? `<small>${esc(s.questionText)}</small>` : ""}</span>
      </button>`).join("") || `<p class="empty-note">${ic("search")}Ничего не нашлось</p>`}</div>`}</div>`;
    const q = $("#home-q");
    if (renderHome.focus && q) { q.focus(); q.setSelectionRange(...renderHome.focus); }
    else if (focused) home.querySelector(focused)?.focus({ preventScroll: true });
    renderHome.focus = false;
  };
  const renderHome = App.renderHome;
  const count = (k) => k === "questions" ? (typeof QuestionPlan !== "undefined" ? QuestionPlan.visibleCount() : 0) : state.scenes.filter((s) => s.id !== "mini_regulator" && (k === "assistant" ? pendingApproval(s) : !pendingApproval(s) && (k === "all" || (k === "game" && s.playable) || (k === "err" && s.errors)))).length;
  App.sceneFilter = () => filter;
  App.sceneFiltersCollapsed = () => filtersCollapsed;
  App.setSceneFiltersCollapsed = (collapsed) => {
    filtersCollapsed = !!collapsed;
    try { localStorage.setItem(COLLAPSE_STORAGE, String(filtersCollapsed)); } catch (_) { /* Optional preference. */ }
    renderLeft();
  };
  App.setSceneFilter = (next) => {
    if (!FILTERS.some(([key]) => key === next)) return;
    filter = next;
    if (["all", "game", "err"].includes(next)) sceneSubfilter = next;
    try { localStorage.setItem(FILTER_STORAGE, filter); } catch (_) { /* Optional preference. */ }
    renderLeft();
    if (!$("#home-screen").hidden) App.renderHome();
  };
  App.setApprovalFilter = next => {
    if (!APPROVAL_FILTERS.some(([key]) => key === next)) return;
    approvalFilter = next;
    renderLeft();
    if (!$("#home-screen").hidden) App.renderHome();
  };
  App.approvalFilter = () => approvalFilter;
  App.showQuestions = (id) => {
    if (!id) state.section = "city";
    if (App.leftPanelOpen?.() && state.ltab !== "scenes") App.setLeftTab("scenes");
    App.setSceneFilter("questions");
    return QuestionPlan.open(id);
  };

  document.addEventListener("input", (e) => {
    const caret = () => [e.target.selectionStart ?? e.target.value.length, e.target.selectionEnd ?? e.target.value.length];
    if (e.target.id === "scene-q" || e.target.id === "home-q") {
      query = e.target.value;
      if (typeof QuestionPlan !== "undefined") QuestionPlan.setQuery(query);
      if (e.target.id === "home-q") { renderHome.focus = caret(); App.renderHome(); } else { renderLeft.focus = caret(); renderLeft(); }
    }
    if (e.target.id === "lib-q") { libQuery = e.target.value; renderLeft.focus = caret(); renderLeft(); $("#left-body").scrollTop = 0; }
  });
  document.addEventListener("click", (e) => {
    if (e.target.closest("[data-toggle-scene-filters]")) { App.setSceneFiltersCollapsed(!filtersCollapsed); return; }
    const navigation = e.target.closest("[data-scene-section]");
    if (navigation) {
      const next = navigation.dataset.sceneSection;
      const inDrawer = navigation.closest?.("#left-body");
      App.setSceneFilter(next === "scenes" ? sceneSubfilter : next);
      if (next === "questions") {
        const load = state.S && inDrawer ? QuestionPlan.load() : QuestionPlan.open();
        load.catch(err => App.toast(err.message, "bad"));
      }
      return;
    }
    const f = e.target.closest("[data-filter]");
    if (f) {
      App.setSceneFilter(f.dataset.filter);
      if (filter === "questions") QuestionPlan.open().catch(err => App.toast(err.message, "bad"));
      return;
    }
    const sc = e.target.closest("[data-scene]");
    if (sc) { App.openScene(sc.dataset.scene).catch((err) => App.toast(err.message, "bad")); return; }
    if (e.target.closest("#home-back")) App.showHome(false);
  });
  document.addEventListener("change", e => {
    if (e.target.matches?.("[data-sign-group]")) {
      signGroup = e.target.value;
      renderLeft();
      $("#left-body").scrollTop = 0;
      return;
    }
    if (!e.target.matches?.("[data-scene-status]")) return;
    if (filter === "assistant") App.setApprovalFilter(e.target.value);
    else App.setSceneFilter(e.target.value);
  });

  // ---- layers ----------------------------------------------------------------------------------
  const LAYERS = [
    { id: "roads", title: "Дороги", icon: "road" },
    { id: "marks", title: "Разметка", icon: "marking" },
    { id: "routes", title: "Маршруты и ответы", icon: "route" },
    { id: "actors", title: "Машины и люди", icon: "car" },
    { id: "lights", title: "Светофоры", icon: "light" },
    { id: "signs", title: "Знаки", icon: "flag" },
    { id: "decor", title: "Окружение", icon: "tree" },
  ];
  function rowsOf(layer) {
    const s = state.S;
    if (!s) return [];
    switch (layer) {
      case "roads": {
        const tracks = (s.tracks || []).map(track => ({ t: "track", id: track.id }));
        if (s.layout) {
          return [...s.layout.nodes.filter((n) => Layout.nodeKind(s.layout, n, s.crop || 90) === "junction" || n.ring).map((n) => ({ t: "node", id: n.id })),
            ...s.layout.streets.map((st) => ({ t: "street", id: st.id })), ...s.roads.filter((r) => !r.auto).map((r) => ({ t: "road", id: r.id, part: -1 })),
            ...s.lawns.filter((l) => !l.auto).map((l) => ({ t: "lawn", id: l.id })), ...tracks];
        }
        return [...s.roads.flatMap((r) => [{ t: "road", id: r.id, part: -1 }, ...(r.holes || []).map((_, k) => ({ t: "road", id: r.id, part: k }))]),
          ...s.lawns.map((l) => ({ t: "lawn", id: l.id })), ...tracks];
      }
      case "marks": return s.markings.filter((m) => !m.auto).map((m) => ({ t: "marking", id: m.id }));
      case "routes": return s.routes.filter((r) => r.kind !== "actor").map((r) => ({ t: "route", id: r.id }));
      case "actors": return [{ t: "stop" }, ...s.actors.map((a) => ({ t: "actor", id: a.id })), ...(s.officers || []).map((o) => ({ t: "officer", id: o.id }))];
      case "lights": return s.lights.map((l) => ({ t: "light", id: l.id }));
      case "decor": return s.decor.map((d) => ({ t: "decor", id: d.id }));
      case "signs": return (s.signs || []).map((d) => ({ t: "sign", id: d.id }));
      default: return [];
    }
  }
  function rowIcon(ref) {
    const o = App.objectOf(ref);
    if (ref.t === "decor") return Thumbs.img("prop", o.prop, "mini");
    if (ref.t === "sign") return `<img class="thumb mini" src="/asset/sign/${SignMount.textureCode(o)}.svg" alt="">`;
    if (ref.t === "actor") return Thumbs.img("actor", o.type, "mini");
    return ic({ node: o?.ring ? "ring" : "junction", street: "road", road: ref.part >= 0 ? "lawn" : "road", lawn: "lawn", marking: "marking",
      route: "route", track: "rails", light: "light", stop: "flag", officer: "person" }[ref.t] || "info");
  }
  function updateSelectedRows() {
    const body = $("#left-body");
    for (const row of body.querySelectorAll("[data-ref]")) {
      const ref = JSON.parse(row.dataset.ref), selected = state.sel.some(item => App.sameRef(item, ref));
      row.classList.toggle("on", selected);
      row.setAttribute("aria-pressed", String(selected));
    }
    const props = new Set(state.sel.filter(item => item.t === "decor").map(item => App.objectOf(item)?.prop));
    for (const row of body.querySelectorAll("[data-kind]")) row.classList.toggle("on-in", props.has(row.dataset.kind));
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
              <button class="lbtn lselect" data-select-prop="${esc(p)}" aria-label="Выбрать все: ${esc(Catalog.propName(p))}" title="Выбрать все">${ic("cursor")}</button>
              <button class="lbtn" data-open="${esc(key)}" aria-expanded="${!!op}" aria-label="${op ? "Свернуть" : "Раскрыть"}: ${esc(Catalog.propName(p))}">${ic("chevron", op ? "rot" : "")}</button></div>`
              + (op ? list.map((r, i) => `<button class="lrow sub2 ${isOn(r) ? "on" : ""}" aria-pressed="${isOn(r)}" data-ref="${esc(JSON.stringify(r))}"><span>${esc(Catalog.propName(p))} ${i + 1}</span></button>`).join("") : "");
          }).join("");
        } else {
          body = rows.map((r) => `<button class="lrow ${isOn(r) ? "on" : ""}" aria-pressed="${isOn(r)}" data-ref="${esc(JSON.stringify(r))}">${rowIcon(r)}<span>${esc(App.nameOf(r))}</span></button>`).join("");
        }
      }
      return `<section class="lgroup ${hiddenL ? "off" : ""}">
        <div class="lhead"><button class="layer-disclosure" data-open="${L.id}" aria-expanded="${expanded}"><span class="caret">${ic("chevron", expanded ? "rot" : "")}</span>${ic(L.icon)}<b>${L.title}</b><em>${L.id === "actors" ? rows.length - 1 : rows.length}</em></button>
          <button class="lbtn lselect" data-select-layer="${L.id}" aria-label="Выбрать все: ${L.title}" title="Выбрать все" ${hiddenL || lockedL || !rows.length ? "disabled" : ""}>${ic("cursor")}</button>
          <button class="lbtn ${lockedL ? "on" : ""}" data-lock="${L.id}" data-tip="${lockedL ? "Открыть" : "Запереть"}" aria-label="${lockedL ? "Разблокировать" : "Заблокировать"}: ${L.title}">${ic(lockedL ? "lock" : "unlock")}</button>
          <button class="lbtn ${hiddenL ? "on" : ""}" data-eye="${L.id}" data-tip="${hiddenL ? "Показать" : "Скрыть"}" aria-label="${hiddenL ? "Показать" : "Скрыть"}: ${L.title}">${ic(hiddenL ? "eye-off" : "eye")}</button></div>
        ${expanded ? `<div class="lbody">${body}</div>` : ""}</section>`;
    }).join("")}</div>`;
  }
  $("#left-body").addEventListener("click", (e) => {
    const selectLayer = e.target.closest("[data-select-layer]");
    if (selectLayer) {
      e.stopPropagation();
      if (selectLayer.disabled) return;
      let refs = rowsOf(selectLayer.dataset.selectLayer);
      if (selectLayer.dataset.selectLayer === "roads") refs = refs.filter(ref => ref.t === "street" || ref.t === "road");
      return App.select(refs.filter(App.pickable), { add: e.shiftKey });
    }
    const selectProp = e.target.closest("[data-select-prop]");
    if (selectProp) {
      e.stopPropagation();
      return App.select(state.S.decor.filter(item => item.prop === selectProp.dataset.selectProp).map(item => ({ t: "decor", id: item.id })).filter(App.pickable), { add: e.shiftKey });
    }
    const category = e.target.closest("[data-library-category]");
    if (category) {
      if (category.hasAttribute?.("data-search-all")) signGroup = "";
      App.setLibraryCategory(category.dataset.libraryCategory, { clearSearch: false });
      $("#left-body").scrollTop = 0;
      return;
    }
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
      else if (item.kind === "officer") Tools.set("officer", { keepLibrary: true });
      else if (item.kind === "sign") Tools.pickSign(item.id);
      else if (item.kind === "light") Tools.pickLight(item.id === "light_tram" || !!item.tram);
      else Tools.set("light");
      App.dismissCompactDrawer?.();
      return renderLeft();
    }
    const tex = e.target.closest("[data-texrow]");
    if (tex) { state.texSel = tex.dataset.texrow; renderLeft(); App.showInspector?.(); App.renderInspector?.(); }
  });

  // ---- library ----------------------------------------------------------------------------------
  function libraryPane() {
    const cat = state.catalog;
    if (!cat) return "";
    const q = libQuery.trim().toLowerCase().replaceAll("ё", "е");
    const words = q.split(/\s+/);
    const hit = (name) => {
      const text = name.toLowerCase().replaceAll("ё", "е");
      return words.every(word => text.includes(word));
    };
    const regulator = state.id === "mini_regulator";
    const inCategory = category => regulator ? category === "decor" : libraryCategory === "all" || libraryCategory === category;
    const tile = (item, name, pic, on, caption = `<span>${esc(name)}</span>`) => `<button class="lib-tile ${on ? "on" : ""}" draggable="true" data-lib="${esc(JSON.stringify(item))}" title="${esc(name)}" aria-label="Добавить: ${esc(name)}" aria-pressed="${!!on}">${pic}${caption}</button>`;
    const sections = [];
    const vehicles = Catalog.ACTOR_ORDER.filter((t) => cat.actorTypes[t] && hit(Catalog.ACTORS[t].name));
    if (inCategory("traffic") && vehicles.length) sections.push(`<h4>${ic("car")}Машины и люди</h4><div class="lib-grid">${vehicles.map((t) => tile({ kind: "actor", id: t }, Catalog.ACTORS[t].name, Thumbs.img("actor", t), Tools.current() === "actor" && Tools.opts.actorType === t)).join("")}</div>`);
    const signCodes = cat.signs || [];
    const groups = new Map();
    for (const code of signCodes) {
      const key = code.split(".")[0], group = cat.signInfo?.[code]?.group;
      if (!group || groups.has(key)) continue;
      const label = key === "8" ? "Таблички" : group.replace(/^Знаки | знаки$/g, "");
      groups.set(key, label.charAt(0).toUpperCase() + label.slice(1));
    }
    const number = words.find(w => /^\d+([.]\d*)*$/.test(w));
    const signs = signCodes.filter(code => (libraryCategory !== "signs" || !signGroup || code.startsWith(signGroup + "."))
      && (!number || code.startsWith(number)) && hit(`знак ${code} ${Catalog.signName(code)} ${cat.signInfo?.[code]?.folkName || ""} ${cat.signInfo?.[code]?.group || ""}`));
    if (inCategory("signs") && signs.length) {
      const visible = libraryCategory === "all" && !q ? signs.slice(0, 6) : signs;
      sections.push(`<h4>${ic("flag")}Знаки · ${signs.length}${visible.length < signs.length ? `<button class="lib-more" data-library-category="signs" aria-label="Все знаки">Все знаки ${ic("chevron")}</button>` : ""}</h4><div class="lib-grid signs">${visible.map(c => tile({ kind: "sign", id: c }, `${c} · ${Catalog.signName(c)}`, `<img class="thumb sign-pic" src="/asset/sign/${c==='5.33'?'5.33_plain':c}.svg" alt="" loading="lazy">`, Tools.current() === "sign" && Tools.opts.sign === c, `<b>${esc(c)}</b><span>${esc(Catalog.signName(c))}</span>`)).join("")}</div>`);
    }
    if (inCategory("traffic") && hit("регулировщик")) sections.push(`<h4>${ic("person")}Регулировщик</h4><div class="lib-grid">${tile({ kind: "officer", id: "officer" }, "Регулировщик", `<span class="lib-icon">${ic("person")}</span>`, Tools.current() === "officer")}</div>`);
    if (inCategory("traffic") && cat.lightAsset && hit("светофор")) {
      sections.push(`<h4>${ic("light")}Светофоры</h4><div class="lib-grid">
        ${tile({ kind: "light", id: "light" }, "Светофор", Thumbs.img("light", "light"), Tools.current() === "light" && !Tools.opts.tram)}
        ${cat.lightTramAsset ? tile({ kind: "light", id: "light_tram", tram: true }, "С трамвайной секцией", Thumbs.img("light", "light_tram"), Tools.current() === "light" && Tools.opts.tram) : ""}
      </div>`);
    }
    const props = [...cat.props.map((p) => p.id), ...(state.id === "mini_regulator" ? [] : ["parked"])];
    for (const g of Catalog.PROP_GROUPS) {
      if (!inCategory("decor")) continue;
      const items = props.filter((p) => g.match(p) && hit(Catalog.propName(p)));
      if (!items.length) continue;
      sections.push(`<h4>${ic(g.icon)}${g.title}</h4><div class="lib-grid">${items.map((p) => tile({ kind: "prop", id: p }, Catalog.propName(p), Thumbs.img("prop", p), Tools.current() === "prop" && Tools.opts.prop === p)).join("")}</div>`);
    }
    const categoryPictures = {
      all: `<span class="library-category-collage">${Thumbs.img("actor", "car")}${Thumbs.img("prop", "trees/round_0")}</span>`,
      traffic: Thumbs.img("actor", "bus"),
      signs: `<img class="thumb" src="/asset/sign/${cat.signs?.includes("2.1") ? "2.1" : cat.signs?.[0] || "2.4"}.svg" alt="">`,
      decor: Thumbs.img("prop", "buildings/home_0"),
    };
    const groupFilter = !regulator && libraryCategory === "signs" && groups.size ? `<select class="sign-group-filter" data-sign-group aria-label="Группа знаков"><option value="">Все группы знаков</option>${Array.from(groups, ([key, name]) => `<option value="${esc(key)}" ${key === signGroup ? "selected" : ""}>${esc(key)} · ${esc(name)}</option>`).join("")}</select>` : "";
    const empty = `<div class="empty-note">Ничего не нашлось${!regulator && libraryCategory !== "all" && q ? '<button class="lib-search-all" data-library-category="all" data-search-all>Искать во всех объектах</button>' : ""}</div>`;
    return `<div class="pane-head"><label class="search">${ic("search")}<input type="search" id="lib-q" aria-label="Поиск объектов" placeholder="Найти объект" value="${esc(libQuery)}"></label>${regulator ? "" : `<div class="library-categories" role="group" aria-label="Категории объектов">${LIBRARY_CATEGORIES.map(([key, label]) => `<button class="library-category ${libraryCategory === key ? "on" : ""}" data-library-category="${key}" aria-pressed="${libraryCategory === key}">${categoryPictures[key]}<span>${label}</span></button>`).join("")}</div>`}${groupFilter}</div>
      <div class="lib">${sections.join("") || empty}</div>`;
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
      return `<h4>${g.title}</h4><div class="tex-grid">${kinds.map((k) => `<button class="tex-tile ${state.texSel === k ? "on" : ""}" aria-pressed="${state.texSel === k}" data-texrow="${k}">
        <canvas width="72" height="72" data-tex="${k}"></canvas><span>${esc(Textures.INFO[k]?.name || k)}</span>${Textures.isDirty(k) ? `<i class="dot"></i>` : ""}</button>`).join("")}</div>`;
    }).join("")}</div>`;
  }
})();
