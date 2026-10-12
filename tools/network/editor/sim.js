// The test drive inside the editor: the player's car comes up to the stop line, stands while the
// question is asked, then drives the chosen way; the participants follow their paths (those that let the
// player go wait for him). Touching cars stop the drive. Nothing in the scene changes: only the models move.
const Sim = (() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, state } = App;
  const PLAYER = { hl: 2.1, hw: 0.95 };
  let run = null, rate = 1, camera = "follow", lastT = 0, hooked = false, savedView = null;

  // A path as points with their distance along it, smoothed like the game draws it.
  function track(points) {
    const pts = Scene3D.smooth(points, 0.5);
    const d = [0];
    for (let i = 1; i < pts.length; i++) d.push(d[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
    return { pts, d, len: d.at(-1) || 0 };
  }
  function at(tr, s) {
    s = Math.max(0, Math.min(tr.len, s));
    let i = 1;
    while (i < tr.d.length - 1 && tr.d[i] < s) i++;
    const a = tr.pts[i - 1], b = tr.pts[i], seg = tr.d[i] - tr.d[i - 1] || 1, t = (s - tr.d[i - 1]) / seg;
    return { x: a[0] + (b[0] - a[0]) * t, z: a[1] + (b[1] - a[1]) * t, yaw: Math.atan2(b[0] - a[0], b[1] - a[1]) };
  }

  function setup(way) {
    const s = state.S;
    const approach = s.routes.find((r) => r.kind === "approach");
    const ways = s.routes.filter((r) => r.kind === "manoeuvre");
    const exit = ways.find((r) => r.exit === way) || ways.find((r) => r.exit === s.question.maneuver) || ways[0];
    const actors = s.actors.map((a) => {
      const r = a.route && s.routes.find((x) => x.id === a.route);
      const moving = r && !(a.behaviour || {}).staysPut;
      const tr = moving ? track(r.points) : null;
      // Where one that lets the player go waits: before the point of its path nearest to the junction.
      let hold = null;
      if (tr && (a.behaviour || {}).waitsForPlayer) {
        let best = 0, bd = Infinity;
        tr.pts.forEach((p, i) => { const dd = Math.hypot(p[0], p[1]); if (dd < bd) { bd = dd; best = tr.d[i]; } });
        hold = Math.max(0, best - 14);
      }
      const ped = a.type === "pedestrian" || a.type === "cyclist";
      return { a, tr, s: 0, v: 0, vmax: Math.min(a.maxSpeed || 10, ped ? 1.6 : 13), hold, half: ped ? [0.4, 0.4] : [a.halfLength || 2.1, a.halfWidth || 0.9] };
    });
    return {
      way: exit ? exit.exit : null,
      approach: approach ? track(approach.points) : null,
      exit: exit ? track(exit.points) : null,
      phase: "approach", s: approach ? Math.max(0, track(approach.points).len - 45) : 0, v: 8, wait: 0, ended: false, crash: null, playing: true, gone: 0, actors,
    };
  }

  function start(way) {
    if (!state.S) return;
    if (!state.S.routes.some((r) => r.kind === "approach")) return App.toast("Нет подъезда игрока: проверьте дороги", "warn");
    state.testing = true;
    savedView = Scene3D.getView();
    run = setup(way);
    Tools.set("select");
    App.select([]);
    Scene3D.setSimMode(true);
    document.body.classList.add("testing");
    if (!hooked) { Scene3D.on("frame", frame); hooked = true; }
    lastT = performance.now();
    applyCamera();
    render();
    App.renderTop();
    App.renderInspector();
  }
  function stop() {
    if (!state.testing) return;
    state.testing = false;
    run = null;
    Scene3D.setFollow(null);
    Scene3D.setSimMode(false);
    if (savedView) { Scene3D.setView(savedView); App.setView(savedView.mode); }
    document.body.classList.remove("testing");
    $("#testbar").hidden = true;
    Scene3D.refresh(state.S);
    App.renderTop();
    App.renderPanels();
  }
  const toggle = () => (state.testing ? stop() : start());

  function frame(now) {
    const dt = Math.min(0.05, (now - lastT) / 1000) * rate;
    lastT = now;
    if (!run || !run.playing || run.ended) return;
    step(dt);
  }

  function step(dt) {
    const r = run, s = state.S;
    // The player: up to the stop line, a pause for the question, then the way.
    if (r.phase === "approach" && r.approach) {
      const left = r.approach.len - r.s;
      r.v = Math.min(9, Math.sqrt(2 * 3 * Math.max(0, left)) + 0.3);
      r.s += r.v * dt;
      if (r.s >= r.approach.len) { r.s = 0; r.phase = "stop"; r.wait = Math.max(1.4, s.question.redWait || 0); r.v = 0; render(); }
    } else if (r.phase === "stop") {
      r.wait -= dt;
      if (r.wait <= 0) { r.phase = "go"; render(); }
    } else if (r.phase === "go" && r.exit) {
      r.v = Math.min(8, r.v + 2.5 * dt);
      r.s += r.v * dt;
      r.gone += r.v * dt;
      if (r.s >= r.exit.len) { r.ended = true; render(); }
    }
    const tr = r.phase === "approach" ? r.approach : r.exit;
    const pose = tr ? at(tr, r.phase === "stop" ? 0 : r.s) : { x: s.stop.x, z: s.stop.z, yaw: s.stop.yaw };
    if (r.phase === "stop" && r.exit) Object.assign(pose, { x: s.stop.x, z: s.stop.z, yaw: s.stop.yaw || 0 });
    Scene3D.setPose("player:", pose.x, pose.z, pose.yaw);
    r.pose = pose;
    // The others.
    for (const x of r.actors) {
      if (!x.tr) continue;
      const held = x.hold !== null && r.gone < 12 && x.s >= x.hold - 0.5;
      const target = held ? 0 : x.vmax;
      x.v += Math.sign(target - x.v) * Math.min(Math.abs(target - x.v), (held ? 6 : 3) * dt);
      if (held) x.v = Math.min(x.v, Math.max(0, (x.hold - x.s) * 2));
      x.s = Math.min(x.tr.len, x.s + x.v * dt);
      const p = at(x.tr, x.s);
      x.pose = p;
      Scene3D.setPose(`actor:${x.a.id}`, p.x, p.z, p.yaw);
    }
    // Touching: the two boxes overlap (separating axes on the ground).
    for (const x of r.actors) {
      const p = x.pose || { x: x.a.pos[0], z: x.a.pos[1], yaw: x.a.yaw || 0 };
      if (overlap(pose, PLAYER.hl, PLAYER.hw, p, x.half[0], x.half[1])) {
        r.crash = x.a.name || Catalog.ACTORS[x.a.type]?.name || x.a.id;
        r.playing = false;
        App.toast(`Столкновение: ${r.crash}`, "bad");
        render();
        break;
      }
    }
    if (camera === "follow") applyCamera();
  }

  function overlap(a, ahl, ahw, b, bhl, bhw) {
    const axes = (p) => [[Math.sin(p.yaw), Math.cos(p.yaw)], [Math.cos(p.yaw), -Math.sin(p.yaw)]];
    const corners = (p, hl, hw) => [[hl, hw], [hl, -hw], [-hl, hw], [-hl, -hw]].map(([l, w]) =>
      [p.x + Math.sin(p.yaw) * l + Math.cos(p.yaw) * w, p.z + Math.cos(p.yaw) * l - Math.sin(p.yaw) * w]);
    const ca = corners(a, ahl, ahw), cb = corners(b, bhl, bhw);
    for (const ax of [...axes(a), ...axes(b)]) {
      const pa = ca.map((c) => c[0] * ax[0] + c[1] * ax[1]), pb = cb.map((c) => c[0] * ax[0] + c[1] * ax[1]);
      if (Math.max(...pa) < Math.min(...pb) || Math.max(...pb) < Math.min(...pa)) return false;
    }
    return true;
  }

  function applyCamera() {
    if (!run) return;
    if (camera === "follow" && run.pose) Scene3D.setFollow({ x: run.pose.x, z: run.pose.z, yaw: run.pose.yaw, dist: 22, pitch: 0.42 });
    else Scene3D.setFollow(null);
  }

  // ---- the bar over the view and the panel -----------------------------------------------------
  const PHASE = { approach: "Подъезжает к стоп-линии", stop: "Стоит у стоп-линии — вопрос", go: "Едет" };
  function render() {
    const bar = $("#testbar");
    if (!run) { bar.hidden = true; return; }
    const s = state.S;
    const ways = s.routes.filter((r) => r.kind === "manoeuvre").map((r) => r.exit);
    const status = run.crash ? `${ic("error")}Столкновение: ${esc(run.crash)}` : run.ended ? `${ic("check-circle")}Проехал` : `${ic("car")}${PHASE[run.phase]}`;
    bar.hidden = false;
    bar.innerHTML = `<button class="icon-btn" data-sim="restart" data-tip="Сначала  R">${ic("restart")}</button>
      <button class="icon-btn big" data-sim="play" data-tip="Пауза  Пробел">${ic(run.playing && !run.ended ? "pause" : "play")}</button>
      <div class="seg">${[1, 2, 4].map((k) => `<button class="${rate === k ? "on" : ""}" data-rate="${k}">${k}×</button>`).join("")}</div>
      <span class="tsep"></span>
      <div class="seg ways">${["left", "straight", "right", "uturn"].filter((k) => ways.includes(k)).map((k) => `<button class="${run.way === k ? "on" : ""} ${s.question.maneuver === k ? "main" : ""}" data-way="${k}" data-tip="${Catalog.EXITS[k].title}${s.question.maneuver === k ? " — по условию" : ""}">${ic(Catalog.EXITS[k].icon)}</button>`).join("")}</div>
      <span class="tsep"></span>
      <div class="seg">${[["follow", "За машиной"], ["free", "Свободно"]].map(([k, t]) => `<button class="${camera === k ? "on" : ""}" data-cam="${k}">${t}</button>`).join("")}</div>
      <span class="status ${run.crash ? "bad" : run.ended ? "good" : ""}">${status}</span>
      <button class="btn ghost small" data-sim="game">${ic("gamepad")}В игре</button>
      <button class="icon-btn" data-sim="exit" data-tip="Выйти из теста  Esc">${ic("x")}</button>`;
  }
  $("#testbar").addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b || !run) return;
    if (b.dataset.sim === "restart") restart();
    if (b.dataset.sim === "play") { if (run.ended || run.crash) restart(); else run.playing = !run.playing; render(); }
    if (b.dataset.sim === "exit") stop();
    if (b.dataset.sim === "game") App.runInGame(false);
    if (b.dataset.rate) { rate = Number(b.dataset.rate); render(); }
    if (b.dataset.way) restart(b.dataset.way);
    if (b.dataset.cam) { camera = b.dataset.cam; applyCamera(); render(); }
  });
  function restart(way) {
    const w = way || (run && run.way);
    for (const a of state.S.actors) Scene3D.setPose(`actor:${a.id}`, a.pos[0], a.pos[1], a.yaw || 0);
    run = setup(w);
    lastT = performance.now();
    render();
    App.renderInspector();
  }
  document.addEventListener("keydown", (e) => {
    if (!state.testing || (e.target && e.target.tagName === "INPUT")) return;
    if (e.code === "Space") { e.preventDefault(); e.stopPropagation(); run.playing = !run.playing; render(); }
    if (e.key === "r" || e.key === "R" || e.code === "KeyR") { e.preventDefault(); e.stopPropagation(); restart(); }
    if (e.key === "Escape") { e.stopPropagation(); stop(); }
  }, true);

  function renderInspector(p) {
    const s = state.S, src = state.source, q = s.question;
    const answers = src ? src.answers.map((a) => a.text) : (q.text?.ru?.options || []);
    p.innerHTML = `<div class="insp-head"><span class="ibadge">${ic("play")}</span><div><b>Тест</b><small>как в игре, упрощённо</small></div></div>
      <section class="card">${src && src.image ? `<img class="ticket-pic" src="/asset/source/${src.image}.webp" alt="">` : ""}
        <p class="qtext">${esc(src ? src.question : q.text?.ru?.title || "")}</p>
        <div class="answers">${answers.map((a, i) => `<div class="answer ${q.correct === i ? "on" : ""}"><i>${q.correct === i ? ic("check-circle") : i + 1}</i><span>${esc(a)}</span></div>`).join("")}</div></section>
      <section class="card"><h3>${ic("car")}Участники</h3>${s.actors.length ? s.actors.map((a) => `<div class="pick static">${Thumbs.img("actor", a.type, "mini")}<span>${esc(a.name || a.id)}</span>
        <em>${(a.behaviour || {}).staysPut || !a.route ? "стоит" : (a.behaviour || {}).waitsForPlayer ? "пропускает" : "едет"}</em></div>`).join("") : `<p class="muted">Никого нет</p>`}</section>
      <section class="card"><p class="muted">Пробел — пауза, R — сначала, Esc — выйти. Полная проверка правил — кнопка «В игре».</p></section>`;
    Thumbs.fillAll(p);
  }

  return { start, stop, toggle, renderInspector };
})();
