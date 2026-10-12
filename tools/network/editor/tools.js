// What the pointer does in the view: the tools of the toolbar (select, hand, road, junctions, markings,
// lawns, participants, lights, answers, props and the brush), their options and the one-line hint.
const Tools = (() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, r3 } = App;
  const LIST = [
    { id: "select", key: "V", title: "Выбор", icon: "cursor", hint: "Клик — выбрать, тянуть — двигать. ⇧ — добавить, рамка — выбрать несколько" },
    { id: "hand", key: "H", title: "Рука", icon: "hand", hint: "Тяните, чтобы двигать вид" },
    { sep: true },
    { id: "road", key: "R", title: "Дорога", icon: "road", hint: "Кликайте точки дороги. Пересечения станут перекрёстками. ↵ — готово" },
    { id: "junction", key: "J", title: "Готовые перекрёстки", icon: "junction", hint: "Выберите перекрёсток — он заменит дороги сцены" },
    { id: "marking", key: "M", title: "Разметка", icon: "marking", hint: "" },
    { id: "track", key: "T", title: "Рельсы", icon: "rails", hint: "Кликайте точки рельсов, начало ветки прилипает к путям. ↵ — готово" },
    { id: "lawn", key: "G", title: "Газон вместо тротуара", icon: "lawn", hint: "Кликайте углы газона, клик в первую точку — готово" },
    { sep: true },
    { id: "actor", key: "C", title: "Машины и люди", icon: "car", hint: "Клик по дороге — встанет на полосу. Тяните — задать направление" },
    { id: "light", key: "L", title: "Светофор", icon: "light", hint: "Клик у перекрёстка — встанет на угол лицом к машинам" },
    { id: "sign", key: "N", title: "Знак", icon: "flag", hint: "Клик у дороги — знак встанет справа лицом к машинам. Знак выберите слева" },
    { id: "officer", key: "U", title: "Регулировщик", icon: "person", hint: "Клик — поставить регулировщика. Тяните — куда он смотрит" },
    { id: "answer", key: "A", title: "Вариант ответа", icon: "route", hint: "Кликайте точки пути. ↵ — готово" },
    { sep: true },
    { id: "prop", key: "O", title: "Объект", icon: "tree", hint: "Клик — поставить, тянуть — повернуть. Выберите объект слева" },
    { id: "brush", key: "B", title: "Кисть деревьев", icon: "brush", hint: "Ведите с зажатой кнопкой — посадите деревья. ⌥ — стирать" },
  ];
  const opts = { sign: "2.4", roadKind: "street", mark: "dashed", actorType: "car", prop: "trees/round_0", brushProps: ["trees/round_0", "trees/pine_0", "trees/birch_0"], brushSize: 8 };
  let tool = "select", drag = null, draft = null, placeYaw = null, hoverRef = null, lastWorld = null;

  const S = () => App.state.S;
  const snapGrid = (v, e) => (e && e.alt ? v : Math.round(v * 2) / 2);   // half a metre: neat, and ⌥ for free

  // ---- the toolbar -----------------------------------------------------------------------
  function renderBar() {
    $("#toolbar").innerHTML = LIST.map((t) => t.sep ? `<span class="tsep"></span>` :
      `<button data-tool="${t.id}" class="${t.id === tool ? "on" : ""}" data-tip="${esc(t.title)}  ${t.key}">${ic(t.icon)}</button>`).join("");
    renderPopover();
    renderHint();
  }

  function set(id) {
    if (!LIST.find((t) => t.id === id)) return;
    finishDraft(true);
    tool = id;
    opts.pathFor = null;
    placeYaw = null;
    Scene3D.setGhost(null);
    Scene3D.setPanTool(id === "hand");
    Scene3D.setPlanHandles(["select", "road"].includes(id));
    if (id === "prop" && App.state.ltab !== "library") App.setLeftTab?.("library");
    renderBar();
  }
  const current = () => tool;

  // Options of a tool, above the toolbar: pictures, not words.
  function renderPopover() {
    const pop = $("#popover");
    let html = "";
    if (tool === "road") {
      html = Object.entries(Layout.KINDS).map(([k, v]) => `<button class="pchip ${opts.roadKind === k ? "on" : ""}" data-road="${k}">
        <span class="road-pic k-${k}"></span><span>${v.title}</span></button>`).join("");
    } else if (tool === "junction") {
      html = Layout.TEMPLATES.map((t) => `<button class="ptile" data-tpl="${t.id}">${Layout.svg(Layout.template(t.id), 90, 64)}<span>${esc(t.title)}</span></button>`).join("");
    } else if (tool === "marking") {
      html = Object.entries(Catalog.MARKS).map(([k, v]) => `<button class="pchip ${opts.mark === k ? "on" : ""}" data-mark="${k}"><span class="mark-pic m-${k}"></span><span>${v.title}</span></button>`).join("");
    } else if (tool === "actor") {
      const types = Catalog.ACTOR_ORDER.filter((t) => App.state.catalog?.actorTypes[t]);
      html = types.map((t) => `<button class="ptile small ${opts.actorType === t ? "on" : ""}" data-actor="${t}">${Thumbs.img("actor", t)}<span>${Catalog.ACTORS[t].name}</span></button>`).join("");
    } else if (tool === "brush") {
      const trees = ["trees/round_0", "trees/pine_0", "trees/birch_0", "street/bush"];
      html = trees.map((p) => `<button class="ptile small ${opts.brushProps.includes(p) ? "on" : ""}" data-brush="${p}">${Thumbs.img("prop", p)}<span>${Catalog.propName(p)}</span></button>`).join("")
        + `<span class="psep"></span>` + [4, 8, 16].map((s) => `<button class="pchip ${opts.brushSize === s ? "on" : ""}" data-bsize="${s}"><span class="dot-pic" style="--d:${4 + s}px"></span></button>`).join("");
    } else if (tool === "prop") {
      html = `<button class="ptile wide on">${Thumbs.img("prop", opts.prop)}<span>${esc(Catalog.propName(opts.prop))}</span></button>`;
    }
    pop.innerHTML = html;
    pop.classList.toggle("grid", tool === "junction");
    pop.hidden = !html || !S();
    pop.querySelectorAll("img[data-thumb]").forEach((img) => Thumbs.fill(img));
  }

  function renderHint(text) {
    const t = LIST.find((x) => x.id === tool);
    let h = text ?? (t ? t.hint : "");
    if (tool === "marking") h = opts.mark === "stop" || opts.mark === "zebra"
      ? (S()?.layout ? "Клик у перекрёстка — включить или выключить на этом въезде" : "Два клика поперёк дороги")
      : "Кликайте точки линии. ↵ — готово";
    const el = $("#hint");
    el.hidden = !S() || !h;
    el.innerHTML = h ? `${ic(t ? t.icon : "info")}<span>${esc(h)}</span>` : "";
  }

  function bindBar() {
    $("#toolbar").addEventListener("click", (e) => {
      const b = e.target.closest("[data-tool]");
      if (!b) return;
      if (!S()) return App.toast("Сначала откройте сцену", "warn");
      set(b.dataset.tool);
    });
    $("#popover").addEventListener("click", (e) => {
      const b = e.target.closest("button");
      if (!b) return;
      if (b.dataset.road) { opts.roadKind = b.dataset.road; renderPopover(); }
      if (b.dataset.mark) { opts.mark = b.dataset.mark; finishDraft(true); renderPopover(); renderHint(); }
      if (b.dataset.actor) { opts.actorType = b.dataset.actor; renderPopover(); }
      if (b.dataset.tpl) applyTemplate(b.dataset.tpl);
      if (b.dataset.brush) {
        const p = b.dataset.brush, list = opts.brushProps;
        opts.brushProps = list.includes(p) ? (list.length > 1 ? list.filter((x) => x !== p) : list) : [...list, p];
        renderPopover();
      }
      if (b.dataset.bsize) { opts.brushSize = Number(b.dataset.bsize); renderPopover(); }
    });
  }

  // ---- ready-made junctions -----------------------------------------------------------------
  async function applyTemplate(kind) {
    const s = S();
    const traced = s.roads.some((r) => !r.auto);
    const ok = await App.confirm("Заменить дороги сцены?", traced
      ? "Дороги, разметка и газоны сцены построятся заново по выбранному перекрёстку. Дома, деревья, машины и ответы останутся. Можно отменить ⌘Z."
      : "Дороги сцены построятся заново. Можно отменить ⌘Z.", "Заменить");
    if (!ok) return;
    App.edit((sc) => {
      sc.layout = Layout.template(kind, sc.crop || 90);
      sc.roads = []; sc.markings = []; sc.lawns = [];
      sc.routes = sc.routes.filter((r) => r.kind === "choice" || r.kind === "actor");
    });
    App.select([]);
    set("select");
    App.toast("Готово: дороги, разметка и маршруты построены", "good");
  }

  // Turns a traced scene into a road plan matching it (the server finds the arms at the sides).
  async function convertScene() {
    const s = S();
    const r = await App.api(`/api/layout/detect/${App.state.id}`).catch((e) => { App.toast(e.message, "bad"); return null; });
    if (!r) return;
    // Islands of the old roads stay (a roundabout's island is the plan's own): each as a small road with
    // the island cut out, so the builder keeps the kerb round it.
    const ring = r.layout.nodes.find((n) => n.ring);
    // Only islands that lie well inside the new carriageway: one on a widening the plan does not have would
    // stick out over the pavement.
    const planned = Layout.generate({ ...s, layout: r.layout }).roads;
    const inPoly = (p, poly) => {
      let c = false;
      for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const [xi, zi] = poly[i], [xj, zj] = poly[j];
        if ((zi > p[1]) !== (zj > p[1]) && p[0] < ((xj - xi) * (p[1] - zi)) / (zj - zi) + xi) c = !c;
      }
      return c;
    };
    const holes = s.roads.flatMap((road) => road.holes || []);
    const islands = holes.filter((h) => {
      const c = h.reduce((a, p) => [a[0] + p[0] / h.length, a[1] + p[1] / h.length], [0, 0]);
      if (ring && Math.hypot(c[0] - ring.x, c[1] - ring.z) < ring.ring.island + 3) return false;
      return h.every((p) => planned.some((road) => inPoly(p, road.outer)));
    });
    const dropped = holes.length - islands.length - (ring ? 1 : 0);
    App.edit((sc) => {
      sc.layout = r.layout;
      sc.roads = islands.map((h, k) => {
        const c = h.reduce((a, p) => [a[0] + p[0] / h.length, a[1] + p[1] / h.length], [0, 0]);
        return { id: `island_${k + 1}`, outer: h.map((p) => [r3(c[0] + (p[0] - c[0]) * 1.25), r3(c[1] + (p[1] - c[1]) * 1.25)]), holes: [h] };
      });
      sc.lawns = [];
      sc.markings = (sc.markings || []).filter((m) => m.type !== "paint");
      sc.routes = sc.routes.filter((x) => x.kind === "choice" || x.kind === "actor");
    });
    App.toast(dropped > 0 ? `Дороги в конструкторе. Островков на расширениях убрано: ${dropped} — ⌘Z вернёт` : "Дороги теперь можно править как в конструкторе", dropped > 0 ? "warn" : "good");
    set("select");
    return s;
  }

  // ---- the pointer ---------------------------------------------------------------------------
  function onPointer(e) {
    if (!S()) return;
    if (e.type === "leave") { Scene3D.setGhost(null); setHover(null); return; }
    if (e.world) lastWorld = e.world;
    const handler = HANDLERS[tool] || HANDLERS.select;
    handler[e.type] && handler[e.type](e);
  }

  function setHover(ref) {
    if (App.sameRef(ref, hoverRef) || (!ref && !hoverRef)) return;
    hoverRef = ref;
    Scene3D.setHover(ref && ref.t !== "turn" && ref.t !== "bend" ? ref : null);
    $("#view").style.cursor = ref ? (ref.t === "turn" ? "grab" : ref.point || ref.t === "node" || ref.t === "bend" ? "move" : "pointer") : "";
  }

  const skipLocked = (ref) => !App.pickable(ref);

  // Select and move.
  const select = {
    down(e) {
      const h = Scene3D.hitAt(e.sx, e.sy, skipLocked);
      if (!h) { drag = { kind: "marquee", x0: e.sx, y0: e.sy, add: e.shift }; return; }
      if (h.t === "turn") return startTurn(e);
      if (h.t === "letter") { App.select({ t: "route", id: h.id }); App.beginDrag(); drag = { kind: "letter", id: h.id }; return; }
      if (h.t === "stop" && S().layout) { App.select({ t: "stop" }); App.beginDrag(); drag = { kind: "stop" }; return; }
      if (h.point) {
        App.select({ ...h, v: h.v });
        App.beginDrag();
        drag = { kind: "point", ref: h, moved: false };
        return;
      }
      if (h.t === "bend") { App.beginDrag(); drag = { kind: "bend", id: h.id }; return; }
      const already = App.state.sel.some((r) => App.sameRef(r, h));
      if (e.shift) { App.toggle(h); return; }
      // Things (props, cars, lights, junction points) move at once; a road, a line or a lawn is picked
      // first and moved by a second drag, so a click on the asphalt never shifts the road by accident.
      const thing = ["decor", "sign", "actor", "officer", "light", "node", "stop"].includes(h.t);
      if (!already) App.select(h);
      if (!already && !thing) return;
      // Alt: drag a copy, the original stays.
      if (e.alt && App.copy()) { App.paste(0); }
      App.beginDrag();
      drag = { kind: "move", start: e.world, last: e.world, moved: false, nodeRef: h.t === "node" ? h : null, street: h.t === "street" ? h.id : null };
    },
    move(e) {
      if (!drag) return setHover(Scene3D.hitAt(e.sx, e.sy, skipLocked));
      if (drag.kind === "marquee") {
        const m = $("#marquee");
        const x0 = Math.min(drag.x0, e.sx), y0 = Math.min(drag.y0, e.sy), x1 = Math.max(drag.x0, e.sx), y1 = Math.max(drag.y0, e.sy);
        if (x1 - x0 + y1 - y0 < 6) return;
        m.hidden = false;
        Object.assign(m.style, { left: x0 + "px", top: y0 + "px", width: x1 - x0 + "px", height: y1 - y0 + "px" });
        drag.rect = [x0, y0, x1, y1];
        return;
      }
      if (!e.world) return;
      if (drag.kind === "turn") return turnMove(e);
      if (drag.kind === "letter") {
        return App.dragMove((s) => { const rt = s.routes.find((x) => x.id === drag.id); if (rt) rt.labelPosition = [r3(e.world.x), r3(e.world.z)]; });
      }
      if (drag.kind === "stop") {
        // The player's car slides along its lane: how far before the junction the question comes.
        return App.dragMove((s) => {
          const plan = Layout.playerPlan(s);
          if (!plan) return;
          const line = Layout.lineFrom(s.layout, plan.st, plan.nid);
          let best = 0, bd = Infinity;
          for (let d = 2; d < plan.total - 1; d += 0.25) {
            const p = Layout.along(line, d).p, dd = Math.hypot(p[0] - e.world.x, p[1] - e.world.z);
            if (dd < bd) { bd = dd; best = d; }
          }
          s.layout.player = { ...s.layout.player, street: plan.st.id, toward: plan.nid, stopAt: r3(Math.max(2, best - 2.4)) };
        });
      }
      if (drag.kind === "point") {
        drag.moved = true;
        const ref = drag.ref;
        return App.dragMove(() => {
          const pts = App.pointsOfRef(ref);
          if (pts) pts[ref.v] = [r3(snapGrid(e.world.x, e)), r3(snapGrid(e.world.z, e))];
          const o = App.objectOf(ref);
          if (ref.t === "route" && o.kind === "approach" && ref.v === pts.length - 1) { S().stop.x = pts[ref.v][0]; S().stop.z = pts[ref.v][1]; }
        });
      }
      if (drag.kind === "bend") {
        return App.dragMove((s) => {
          const st = Layout.streetOf(s.layout, drag.id);
          const A = Layout.nodeOf(s.layout, st.a), B = Layout.nodeOf(s.layout, st.b);
          const M = [e.world.x, e.world.z];
          // The handle is the middle of the curve: the control point that puts the middle there.
          const C = [2 * M[0] - (A.x + B.x) / 2, 2 * M[1] - (A.z + B.z) / 2];
          const straight = Math.hypot(M[0] - (A.x + B.x) / 2, M[1] - (A.z + B.z) / 2) < 1.5;
          st.bend = straight ? null : [r3(C[0]), r3(C[1])];
        });
      }
      if (drag.kind === "move") {
        const dx = e.world.x - drag.last.x, dz = e.world.z - drag.last.z;
        if (!drag.moved && Math.hypot(e.world.x - drag.start.x, e.world.z - drag.start.z) < 0.3) return;
        drag.moved = true;
        drag.last = e.world;
        App.dragMove((s) => {
          if (drag.nodeRef) return Layout.moveNode(s, drag.nodeRef.id, [snapGrid(e.world.x, e), snapGrid(e.world.z, e)]);
          if (drag.street) {
            const st = Layout.streetOf(s.layout, drag.street);
            for (const nid of [st.a, st.b]) { const n = Layout.nodeOf(s.layout, nid); n.x = r3(n.x + dx); n.z = r3(n.z + dz); }
            if (st.bend) st.bend = [r3(st.bend[0] + dx), r3(st.bend[1] + dz)];
            return;
          }
          for (const ref of App.state.sel) App.moveRef(s, ref, dx, dz);
        });
      }
    },
    up(e) {
      const d = drag;
      drag = null;
      if (!d) return;
      if (d.kind === "marquee") {
        $("#marquee").hidden = true;
        if (d.rect) {
          const found = Scene3D.inRect(...d.rect, skipLocked);
          App.select(found, { add: d.add });
        } else if (!d.add) App.select([]);
        return;
      }
      if (d.kind === "move" && d.nodeRef && d.moved) {
        // A node dropped on another one joins it.
        const s = S(), n = Layout.nodeOf(s.layout, d.nodeRef.id);
        const other = s.layout.nodes.find((m) => m.id !== n.id && Math.hypot(m.x - n.x, m.z - n.z) < 3);
        if (other) App.dragMove((sc) => Layout.mergeNodes(sc, n.id, other.id));
      }
      if (d.kind === "move" && d.moved) snapActorsToLanes();
      if (["turn", "point", "bend", "letter", "stop"].includes(d.kind) || d.moved) App.endDrag();
      else App.cancelDrag();
      App.renderPanels?.();
    },
    dblclick(e) {
      // A point more on a route, a road's or lawn's outline: double click on its line.
      const sel = App.state.sel;
      if (sel.length !== 1 || !e.world) return;
      const ref = sel[0], pts = App.pointsOfRef(ref);
      if (!pts || (ref.t === "route" && App.objectOf(ref).auto)) return;
      const closed = ref.t === "road" || ref.t === "lawn";
      let best = -1, bd = 3;
      for (let i = 0; i < pts.length - (closed ? 0 : 1); i++) {
        const a = pts[i], b = pts[(i + 1) % pts.length];
        const d = segDist([e.world.x, e.world.z], a, b);
        if (d < bd) { bd = d; best = i; }
      }
      if (best < 0) return;
      App.edit(() => pts.splice(best + 1, 0, [r3(e.world.x), r3(e.world.z)]));
      App.select({ ...ref, v: best + 1 });
    },
  };

  function segDist(p, a, b) {
    const dx = b[0] - a[0], dz = b[1] - a[1], l2 = dx * dx + dz * dz || 1;
    const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2));
    return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dz));
  }

  function startTurn(e) {
    const th = Scene3D.turnHandle;
    App.beginDrag();
    drag = { kind: "turn", cx: th.cx, cz: th.cz };
  }
  function turnMove(e) {
    const yaw = Math.atan2(e.world.x - drag.cx, e.world.z - drag.cz);
    const snapped = e.shift ? yaw : Math.round(yaw / (Math.PI / 12)) * (Math.PI / 12);
    App.dragMove(() => {
      for (const ref of App.state.sel) {
        const o = App.objectOf(ref);
        if (o && o.pos) o.yaw = r3(snapped);
      }
    });
  }

  // A participant moved on a planned road stands on the nearest lane, facing the traffic.
  function snapActorsToLanes() {
    const s = S();
    if (!s.layout) return;
    App.dragMove(() => {
      for (const ref of App.state.sel) {
        if (ref.t !== "actor") continue;
        const a = App.objectOf(ref);
        if (!Catalog.ACTORS[a.type]?.lane) continue;
        const hit = Layout.nearestLane(s, a.pos, a.yaw);
        if (hit && hit.d < 4) { a.pos = [r3(hit.point[0]), r3(hit.point[1])]; a.yaw = r3(hit.yaw); a.way = a.way || "straight"; }
      }
    });
  }

  // Hand: the view moves (scene3d does it while the tool is on).
  const hand = {};

  // ---- road: click by click, each step a street ------------------------------------------------
  const road = {
    move(e) {
      if (!e.world) return;
      const s = S();
      const snapped = Layout.snapPoint(s.layout ? s : { ...s, layout: { nodes: [], streets: [] } }, [e.world.x, e.world.z]);
      const at = snapped.p;
      Scene3D.setDraft({ kind: "road", points: draft ? draft.points : [], cursor: draft ? at : null, width: Layout.KINDS[opts.roadKind].width,
        snap: snapped.node || snapped.port || snapped.street ? at : null, snapKind: snapped.port ? "port" : "node" });
      if (!draft) setHover(null);
    },
    down(e) {
      if (!e.world) return;
      const s = S();
      const first = !s.layout;
      const snapped = Layout.snapPoint(s.layout ? s : { ...s, layout: { nodes: [], streets: [] } }, [e.world.x, e.world.z]);
      if (!draft) { draft = { points: [snapped.p] }; road.move(e); return; }
      const a = draft.points.at(-1), b = snapped.p;
      if (Math.hypot(b[0] - a[0], b[1] - a[1]) < 3) return finishDraft();
      App.edit((sc) => {
        if (!sc.layout) {
          sc.layout = { nodes: [], streets: [] };
          // A traced scene starts its plan from nothing: its old road copy is replaced.
          sc.roads = sc.roads.filter((r) => r.auto);
          sc.markings = (sc.markings || []).filter((m) => m.type !== "paint");
          sc.routes = sc.routes.filter((r) => r.kind === "choice" || r.kind === "actor");
        }
        Layout.addStreet(sc, a, b, opts.roadKind);
      });
      if (first) App.toast("Новая дорога. Старые дороги сцены заменены — ⌘Z вернёт", "warn");
      draft.points.push(b);
      road.move(e);
    },
    dblclick() { finishDraft(); },
  };

  // ---- markings: lines by clicks; stop lines and zebras by a click at a junction's arm -----------
  const marking = {
    move(e) {
      if (draft && e.world) {
        draft.cursor = [snapGrid(e.world.x, e), snapGrid(e.world.z, e)];
        Scene3D.setDraft({ kind: "line", points: draft.points, cursor: draft.cursor, colour: 0xffffff });
      }
    },
    down(e) {
      if (!e.world) return;
      const s = S(), p = [snapGrid(e.world.x, e), snapGrid(e.world.z, e)];
      if ((opts.mark === "stop" || opts.mark === "zebra") && s.layout) return toggleEnd(p, opts.mark);
      if (!draft) draft = { points: [] };
      draft.points.push(p);
      if ((opts.mark === "stop" || opts.mark === "zebra") && draft.points.length === 2) return finishDraft();
      marking.move(e);
    },
    dblclick() { finishDraft(); },
  };

  // The end of a street nearest to the point (at a junction or a dead end): its stop line or zebra on or off.
  function toggleEnd(p, what) {
    const s = S(), L = s.layout;
    let best = null;
    for (const st of L.streets) {
      for (const nid of [st.a, st.b]) {
        const n = Layout.nodeOf(L, nid), kind = Layout.nodeKind(L, n, s.crop || 90);
        if (kind === "border" || kind === "joint") continue;
        const line = Layout.lineFrom(L, st, nid);
        const at = Layout.along(line, Math.min(12, Layout.polyLen(line) / 2)).p;
        const d = Math.hypot(at[0] - p[0], at[1] - p[1]);
        if (d < 14 && (!best || d < best.d)) best = { d, st, end: st.a === nid ? "a" : "b" };
      }
    }
    if (!best) return App.toast("Кликните на дорогу у перекрёстка", "warn");
    App.edit((sc) => {
      const st = Layout.streetOf(sc.layout, best.st.id);
      st.ends = st.ends || {};
      st.ends[best.end] = { ...(st.ends[best.end] || {}) };
      st.ends[best.end][what] = !st.ends[best.end][what];
    });
  }

  // ---- lawn: a polygon -------------------------------------------------------------------------
  const lawn = {
    move(e) {
      if (draft && e.world) Scene3D.setDraft({ kind: "line", points: draft.points, cursor: [snapGrid(e.world.x, e), snapGrid(e.world.z, e)], closed: true, colour: 0x2bc280 });
    },
    down(e) {
      if (!e.world) return;
      const p = [snapGrid(e.world.x, e), snapGrid(e.world.z, e)];
      if (!draft) draft = { points: [] };
      if (draft.points.length >= 3 && Math.hypot(p[0] - draft.points[0][0], p[1] - draft.points[0][1]) < 2) return finishDraft();
      draft.points.push(p);
      lawn.move(e);
    },
    dblclick() { finishDraft(); },
  };

  // ---- answers: a route with the next free letter -------------------------------------------------
  const answer = {
    move(e) {
      if (draft && e.world) Scene3D.setDraft({ kind: "line", points: draft.points, cursor: [r3(e.world.x), r3(e.world.z)], colour: 0xe0533d });
    },
    down(e) {
      if (!e.world) return;
      if (!draft) draft = { points: [] };
      draft.points.push([r3(e.world.x), r3(e.world.z)]);
      answer.move(e);
    },
    dblclick() { finishDraft(); },
  };

  // ---- placing things: participants, lights, props --------------------------------------------------
  function ghostFor(kind, w, yaw) {
    const s = S();
    let x = w.x, z = w.z, y = yaw ?? 0, url = null, half = [1, 1], scale = 1;
    if (kind === "actor") {
      const tpl = App.state.catalog.actorTypes[opts.actorType];
      url = tpl ? `/asset/scene/${tpl.asset}` : null;
      half = [tpl?.halfLength || 2, tpl?.halfWidth || 0.9];
      if (s.layout && Catalog.ACTORS[opts.actorType]?.lane && yaw === null) {
        const hit = Layout.nearestLane(s, [x, z]);
        if (hit && hit.d < 5) { x = hit.point[0]; z = hit.point[1]; y = hit.yaw; }
      }
    } else if (kind === "sign") {
      url = null;
      half = [0.3, 1.5];
      y = yaw ?? Math.PI;
      const spot = s.layout && yaw === null ? lightSpot([x, z]) : null;
      if (spot) {
        // A little further out than a traffic light: before the junction, on the right.
        x = r3(spot.pos[0] + Math.sin(spot.yaw) * 2); z = r3(spot.pos[1] + Math.cos(spot.yaw) * 2); y = spot.yaw;
      }
    } else if (kind === "officer") {
      half = [0.4, 0.4];
      x = snapGrid(x); z = snapGrid(z);
      y = yaw ?? 0;
    } else if (kind === "light") {
      url = App.state.catalog.lightAsset ? `/asset/scene/${App.state.catalog.lightAsset}` : null;
      half = [0.5, 0.5];
      const spot = s.layout && yaw === null ? lightSpot([x, z]) : null;
      if (spot) { x = spot.pos[0]; z = spot.pos[1]; y = spot.yaw; }
    } else {
      url = opts.prop === "parked" ? "/asset/models/traffic/sedan.glb" : `/asset/scenery/${opts.prop}.glb`;
      const size = App.catalogSize(opts.prop) || [2, 2, 2];
      half = [size[2] / 2, size[0] / 2];
      x = snapGrid(x); z = snapGrid(z);
    }
    return { url, x, z, yaw: y, half, scale };
  }

  // Where a traffic light stands for the arm of a junction nearest to p: on the right corner before the
  // junction, facing the cars that come (as in the scenes made from the tickets).
  function lightSpot(p) {
    const s = S(), L = s.layout;
    let best = null;
    for (const n of L.nodes) {
      const kind = Layout.nodeKind(L, n, s.crop || 90);
      if (kind !== "junction" && kind !== "ring") continue;
      for (const st of Layout.streetsAt(L, n.id)) {
        const line = Layout.lineFrom(L, st, n.id);
        const others = Layout.streetsAt(L, n.id).filter((x) => x !== st).map(Layout.widthOf);
        const back = n.ring ? n.ring.r + 2 : Math.max(...others) / 2 + 4.3;
        const a = Layout.along(line, back);
        const tin = [-a.t[0], -a.t[1]];
        const rightIn = [-tin[1], tin[0]];
        const off = Layout.widthOf(st) / 2 + 1.2;
        const pos = [a.p[0] + rightIn[0] * off, a.p[1] + rightIn[1] * off];
        const d = Math.hypot(pos[0] - p[0], pos[1] - p[1]);
        if (d < 18 && (!best || d < best.d)) best = { d, pos: pos.map(r3), yaw: r3(Layout.heading([-tin[0], -tin[1]])) };
      }
    }
    return best;
  }

  function placer(kind) {
    return {
      move(e) {
        if (!e.world) return;
        if (drag && drag.kind === "place") {
          const dx = e.world.x - drag.g.x, dz = e.world.z - drag.g.z;
          if (Math.hypot(dx, dz) > 0.8) { drag.yaw = Math.atan2(dx, dz); drag.turned = true; }
          Scene3D.setGhost({ ...drag.g, yaw: drag.turned ? drag.yaw : drag.g.yaw });
          return;
        }
        Scene3D.setGhost(ghostFor(kind, e.world, placeYaw));
      },
      down(e) {
        if (!e.world) return;
        drag = { kind: "place", g: ghostFor(kind, e.world, placeYaw), turned: false };
      },
      up() {
        if (!drag || drag.kind !== "place") return;
        const g = drag.g, yaw = drag.turned ? drag.yaw : g.yaw;
        if (drag.turned) placeYaw = yaw;
        drag = null;
        place(kind, g, yaw);
      },
    };
  }

  function place(kind, g, yaw) {
    const s = S(), cat = App.state.catalog;
    let ref = null;
    if (kind === "actor") {
      const tpl = cat.actorTypes[opts.actorType];
      if (!tpl) return App.toast("Для этого типа нет модели", "bad");
      ref = App.edit((sc) => {
        const id = App.uniqueId(`${opts.actorType}_`, sc.actors.map((a) => a.id));
        const onRails = opts.actorType === "tram" && Tracks.nearest(sc, [g.x, g.z]);
        const lane = sc.layout && Catalog.ACTORS[opts.actorType].lane && !(onRails && onRails.d < 6);
        sc.actors.push({ id, type: opts.actorType, name: Catalog.ACTORS[opts.actorType].name, asset: tpl.asset, route: null,
          pos: [r3(g.x), r3(g.z)], yaw: r3(yaw), scale: [1, 1, 1], maxSpeed: tpl.maxSpeed ?? 10, clearDistance: tpl.clearDistance ?? 6,
          halfLength: tpl.halfLength ?? 2, halfWidth: tpl.halfWidth ?? 0.9, behaviour: { staysPut: !lane, waitsForPlayer: true },
          ...(lane ? { way: "straight" } : {}) });
        if (onRails && onRails.d < 6) {
          const a = sc.actors.at(-1);
          a.track = onRails.track.id;
          // The way along the rails nearest to the heading it was put down with.
          const pts = onRails.track.points;
          const fw = [pts.at(-1)[0] - pts[0][0], pts.at(-1)[1] - pts[0][1]];
          a.trackDir = fw[0] * Math.sin(yaw) + fw[1] * Math.cos(yaw) >= 0 ? 1 : -1;
          delete a.way;
        }
        // A pedestrian put down near a zebra crosses the road by it.
        const walk = opts.actorType === "pedestrian" && Layout.zebraPath(sc, [r3(g.x), r3(g.z)]);
        if (walk && Math.hypot(walk[1][0] - g.x, walk[1][1] - g.z) < 12) {
          const a = sc.actors.at(-1);
          sc.routes.push({ id: `actor_${id}`, kind: "actor", points: walk });
          a.route = `actor_${id}`;
          a.behaviour.staysPut = false;
          a.yaw = r3(Math.atan2(walk[1][0] - walk[0][0], walk[1][1] - walk[0][1]));
        }
        return { t: "actor", id };
      });
    } else if (kind === "sign") {
      ref = App.edit((sc) => {
        sc.signs = sc.signs || [];
        const id = App.uniqueId("sign_", sc.signs.map((o) => o.id));
        sc.signs.push({ id, code: opts.sign, pos: [r3(g.x), r3(g.z)], yaw: r3(yaw) });
        return { t: "sign", id };
      });
    } else if (kind === "officer") {
      ref = App.edit((sc) => {
        sc.officers = sc.officers || [];
        const id = App.uniqueId("officer_", sc.officers.map((o) => o.id));
        sc.officers.push({ id, pos: [r3(g.x), r3(g.z)], yaw: r3(yaw), gesture: "sides" });
        return { t: "officer", id };
      });
    } else if (kind === "light") {
      if (!cat.lightAsset) return App.toast("Нет модели светофора", "bad");
      ref = App.edit((sc) => {
        const id = App.uniqueId("light_", sc.lights.map((l) => l.id));
        const state0 = sc.lights[0]?.state || "green";
        sc.lights.push({ id, pos: [r3(g.x), r3(g.z)], yaw: r3(yaw), scale: 1, arrow: null, state: state0, asset: cat.lightAsset });
        return { t: "light", id };
      });
    } else {
      ref = App.edit((sc) => {
        const id = App.uniqueId("decor_", sc.decor.map((d) => d.id));
        sc.decor.push({ prop: opts.prop, pos: [r3(g.x), r3(g.z)], yaw: r3(yaw), scale: [1, 1, 1], tint: null, id });
        return { t: "decor", id };
      });
    }
    if (ref) App.select(ref);
  }

  // ---- the brush: trees along the stroke, a little apart and each a bit different ---------------------
  const brush = {
    move(e) {
      if (!e.world) return;
      Scene3D.setDraft({ kind: "line", points: circle([e.world.x, e.world.z], opts.brushSize / 2), cursor: null, colour: e.alt ? 0xed4621 : 0x2bc280, closed: true, bare: true });
      if (drag && drag.kind === "brush") brushAt(e);
    },
    down(e) {
      if (!e.world) return;
      App.beginDrag();
      drag = { kind: "brush", erase: e.alt, last: null };
      brushAt(e);
    },
    up() {
      if (drag && drag.kind === "brush") { App.endDrag(); App.renderPanels?.(); }
      drag = null;
    },
  };
  function circle(c, r) {
    return Array.from({ length: 24 }, (_, i) => [c[0] + Math.cos((i / 24) * Math.PI * 2) * r, c[1] + Math.sin((i / 24) * Math.PI * 2) * r]);
  }
  function brushAt(e) {
    const s = S(), p = [e.world.x, e.world.z], r = opts.brushSize / 2;
    if (drag.erase || e.alt) {
      App.dragMove((sc) => { sc.decor = sc.decor.filter((d) => !(opts.brushProps.includes(d.prop) && Math.hypot(d.pos[0] - p[0], d.pos[1] - p[1]) < r)); });
      return;
    }
    if (drag.last && Math.hypot(p[0] - drag.last[0], p[1] - drag.last[1]) < Math.max(2.5, r * 0.6)) return;
    drag.last = p;
    const spacing = 3.2;
    const count = Math.max(1, Math.round((r * r) / 16));
    const road = App.state.build;
    App.dragMove((sc) => {
      for (let k = 0; k < count; k++) {
        const a = Math.random() * Math.PI * 2, d = Math.sqrt(Math.random()) * r;
        const q = [p[0] + Math.cos(a) * d, p[1] + Math.sin(a) * d];
        if (sc.decor.some((x) => Math.hypot(x.pos[0] - q[0], x.pos[1] - q[1]) < spacing)) continue;
        if (onRoad(q, road)) continue;
        const prop = opts.brushProps[Math.floor(Math.random() * opts.brushProps.length)];
        const tints = (Catalog.TINTS.trees || []).filter(Boolean).slice(0, 4);
        const k1 = 0.85 + Math.random() * 0.3;
        sc.decor.push({ prop, pos: [r3(q[0]), r3(q[1])], yaw: r3(Math.random() * Math.PI * 2 - Math.PI), scale: [r3(k1), r3(k1), r3(k1)],
          tint: prop.startsWith("trees/") ? tints[Math.floor(Math.random() * tints.length)] : null, id: App.uniqueId("decor_", sc.decor.map((x) => x.id)) });
      }
    });
  }
  // Trees keep off the carriageway and the pavement (the build's surfaces).
  function onRoad(q, B) {
    if (!B) return false;
    for (const surf of B.surfaces) {
      if (surf.id !== "asphalt" && surf.id !== "pavement" && surf.id !== "island") continue;
      const v = surf.verts, idx = surf.idx;
      for (let k = 0; k + 2 < idx.length; k += 3) {
        const a = idx[k] * 2, b = idx[k + 1] * 2, c = idx[k + 2] * 2;
        if (inTri(q, v[a], v[a + 1], v[b], v[b + 1], v[c], v[c + 1])) return true;
      }
    }
    return false;
  }
  function inTri(p, ax, az, bx, bz, cx, cz) {
    const d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz);
    if (Math.abs(d) < 1e-12) return false;
    const w1 = ((bz - cz) * (p[0] - cx) + (cx - bx) * (p[1] - cz)) / d;
    const w2 = ((cz - az) * (p[0] - cx) + (ax - cx) * (p[1] - cz)) / d;
    return w1 >= 0 && w2 >= 0 && 1 - w1 - w2 >= 0;
  }

  // Tram tracks: a line by clicks, its points snap onto the tracks already there.
  const track = {
    move(e) {
      if (!e.world) return;
      const p = Tracks.snap(S(), [r3(e.world.x), r3(e.world.z)]);
      Scene3D.setDraft({ kind: "line", points: draft ? draft.points : [], cursor: p, colour: 0x8b5cf6 });
    },
    down(e) {
      if (!e.world) return;
      if (!draft) draft = { points: [] };
      draft.points.push(Tracks.snap(S(), [r3(e.world.x), r3(e.world.z)]));
      track.move(e);
    },
    dblclick() { finishDraft(); },
  };

  const HANDLERS = { select, hand, road, junction: select, marking, lawn, track, answer, actor: placer("actor"), light: placer("light"), officer: placer("officer"), sign: placer("sign"), prop: placer("prop"), brush };

  // ---- finishing a drawing ------------------------------------------------------------------------
  function finishDraft(cancel = false) {
    const d = draft;
    draft = null;
    Scene3D.setDraft(null);
    if (!d || cancel) return;
    const pts = d.points;
    if (tool === "marking" && pts.length >= 2) {
      const ref = App.edit((s) => {
        const id = App.uniqueId("mark_", s.markings.map((m) => m.id));
        const m = { id, type: opts.mark, colour: "white", points: pts };
        if (opts.mark === "stop") m.width = 0.4;
        if (opts.mark === "zebra") m.length = 4;
        s.markings.push(m);
        return { t: "marking", id };
      });
      App.select(ref);
    } else if (tool === "track" && pts.length >= 2) {
      const ref = App.edit((s) => {
        s.tracks = s.tracks || [];
        const id = App.uniqueId("track_", s.tracks.map((t) => t.id));
        s.tracks.push({ id, points: pts });
        return { t: "track", id };
      });
      App.select(ref);
    } else if (tool === "lawn" && pts.length >= 3) {
      const ref = App.edit((s) => {
        const id = App.uniqueId("lawn_", s.lawns.map((l) => l.id));
        s.lawns.push({ id, outer: pts, holes: [] });
        return { t: "lawn", id };
      });
      App.select(ref);
    } else if (tool === "answer" && pts.length >= 2 && opts.pathFor) {
      const aid = opts.pathFor;
      opts.pathFor = null;
      App.edit((s) => {
        const a = s.actors.find((x) => x.id === aid);
        if (!a) return;
        const rid = `actor_${a.id}`;
        s.routes = s.routes.filter((r) => r.id !== rid);
        s.routes.push({ id: rid, kind: "actor", points: [[a.pos[0], a.pos[1]], ...pts] });
        a.route = rid;
        a.behaviour = { ...(a.behaviour || {}), staysPut: false };
      });
      App.select({ t: "actor", id: aid });
      set("select");
    } else if (tool === "answer" && pts.length >= 2) {
      const ref = App.edit((s) => {
        const used = s.routes.filter((r) => r.kind === "choice").map((r) => r.label);
        const label = Catalog.LETTERS.find((l) => !used.includes(l));
        if (!label) { App.toast("Все буквы заняты", "warn"); return null; }
        const mid = pts[Math.floor(pts.length / 2)];
        s.routes.push({ id: `choice_${label}`, kind: "choice", label, points: pts, labelPosition: [mid[0], mid[1]] });
        return { t: "route", id: `choice_${label}` };
      });
      if (ref) App.select(ref);
    }
  }

  function escape() {
    if (drag) { App.cancelDrag(); drag = null; $("#marquee").hidden = true; return; }
    if (draft) return finishDraft(true);
    if (tool !== "select") return set("select");
    App.select([]);
  }
  function enter() {
    if (draft) finishDraft();
  }

  // Shows the selection, or the whole scene.
  function fitSelection() {
    const sel = App.state.sel;
    const pts = [];
    for (const ref of sel) {
      const o = App.objectOf(ref);
      if (!o) continue;
      if (o.pos) pts.push(o.pos);
      else if (ref.t === "node") pts.push([o.x, o.z]);
      else if (ref.t === "street") Layout.centreline(S().layout, o).forEach((p) => pts.push(p));
      else (App.pointsOfRef(ref) || []).forEach((p) => pts.push(p));
    }
    if (!pts.length) return Scene3D.fit();
    const xs = pts.map((p) => p[0]), zs = pts.map((p) => p[1]);
    const pad = 12;
    Scene3D.fit([Math.min(...xs) - pad, Math.min(...zs) - pad, Math.max(...xs) + pad, Math.max(...zs) + pad]);
  }

  // A prop chosen in the library: placing it is the next click.
  function pickProp(prop) {
    opts.prop = prop;
    set("prop");
  }
  function pickSign(code) {
    opts.sign = code;
    set("sign");
  }
  function pickActor(type) {
    opts.actorType = type;
    set("actor");
  }
  // The next drawing with the answer tool is a participant's path.
  function drawPathFor(id) {
    set("answer");
    opts.pathFor = id;
    renderHint("Кликайте точки пути участника от него. ↵ — готово");
  }

  // Dropped from the library onto the view.
  function dropAt(sx, sy, item) {
    const w = Scene3D.worldAt(sx, sy);
    if (!w || !S()) return;
    if (item.kind === "prop") { opts.prop = item.id; place("prop", ghostFor("prop", w, null), 0); }
    else if (item.kind === "actor") { opts.actorType = item.id; const g = ghostFor("actor", w, null); place("actor", g, g.yaw); }
    else if (item.kind === "light") { const g = ghostFor("light", w, null); place("light", g, g.yaw); }
    else if (item.kind === "officer") place("officer", ghostFor("officer", w, null), 0);
    else if (item.kind === "sign") { opts.sign = item.id; const g = ghostFor("sign", w, null); place("sign", g, g.yaw); }
  }

  function init() {
    renderBar();
    bindBar();
    Scene3D.on("pointer", onPointer);
    const view = $("#view");
    view.addEventListener("dragover", (e) => { if (e.dataTransfer.types.includes("text/x-scene-item")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; } });
    view.addEventListener("drop", (e) => {
      const raw = e.dataTransfer.getData("text/x-scene-item");
      if (!raw) return;
      e.preventDefault();
      const r = view.getBoundingClientRect();
      dropAt(e.clientX - r.left, e.clientY - r.top, JSON.parse(raw));
    });
  }

  return { init, set, current, list: () => LIST.filter((t) => !t.sep), escape, enter, fitSelection, pickProp, pickActor, pickSign, drawPathFor, convertScene,
    applyTemplate, renderBar, renderHint, lightSpot, get opts() { return opts; } };
})();
