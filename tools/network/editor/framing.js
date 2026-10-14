// The question's camera, framed on a phone held upright (what players see above the question card), and
// the ticket's photo: opened large, or pinned over the view to build the scene by it.
const Framing = (() => {
  const $ = (s) => document.querySelector(s);
  const { esc, ic, state } = App;
  const PHONE_H = 844, TILT = Math.sin(Math.atan2(42, 44));
  let phone = null, before = null;

  // How tall the question card is on a phone (px of 844): its title, the question and the answers.
  function cardHeight() {
    const src = state.source, q = state.S.question || {};
    const text = src ? src.question : q.text?.ru?.title || "";
    const answers = src ? src.answers.map((a) => a.text) : q.text?.ru?.options || [];
    const lines = (t, per) => Math.max(1, Math.ceil(String(t).length / per));
    const h = 78 + 21 * lines(text, 40) + answers.reduce((sum, a) => sum + 22 + 19 * lines(a, 42), 0) + 10 * answers.length;
    return Math.max(200, Math.min(560, Math.round(h)));
  }

  // The framing the game would use now: the editor's own, or the exported samples for this card.
  function current(card) {
    const s = state.S;
    if (s.questionView) return { centre: [...s.questionView.centre], height: s.questionView.height, card };
    const samples = s.questionCamera || [];
    let look = [0, -8], size = 42;
    if (samples.length) {
      let lo = samples[0], hi = samples.at(-1);
      for (let i = 0; i + 1 < samples.length; i++) if (card >= samples[i].bottom && card <= samples[i + 1].bottom) { lo = samples[i]; hi = samples[i + 1]; break; }
      const k = Math.max(0, Math.min(1, (card - lo.bottom) / Math.max(1, hi.bottom - lo.bottom)));
      look = [lo.look[0] + (hi.look[0] - lo.look[0]) * k, lo.look[1] + (hi.look[1] - lo.look[1]) * k];
      size = lo.size + (hi.size - lo.size) * k;
    }
    const free = Math.max(0.3, 1 - card / PHONE_H);
    return { centre: [look[0], look[1] + (1 - free) * size * 0.5 / TILT], height: size * free, card };
  }

  function start() {
    if (!state.S) return;
    Tools.set("select");
    App.select([]);
    before = Scene3D.getView();
    phone = current(cardHeight());
    Scene3D.setPhone(phone);
    document.body.classList.add("framing");
    render();
  }
  function stop(save) {
    if (!phone) return;
    if (save === "save") App.edit((s) => { s.questionView = { centre: phone.centre.map(App.r3), height: App.r3(phone.height) }; });
    if (save === "auto") App.edit((s) => { delete s.questionView; });
    phone = null;
    Scene3D.setPhone(null);
    if (before) { Scene3D.setView(before); App.setView(before.mode); }
    document.body.classList.remove("framing");
    $("#phone").hidden = true;
    if (save) App.toast(save === "save" ? "Кадр вопроса сохранится вместе со сценой" : "Кадр вопроса снова подбирается сам", "good");
  }

  // The phone over the view: dark around it, the question card at its bottom, the buttons below.
  function render() {
    const el = $("#phone");
    if (!phone) { el.hidden = true; return; }
    const rc = Scene3D.phoneRect(), s = state.S, src = state.source, q = s.question || {};
    const answers = src ? src.answers.map((a) => a.text) : q.text?.ru?.options || [];
    const k = rc.h / PHONE_H;
    el.hidden = false;
    el.innerHTML = `<div class="phone-frame" style="left:${rc.x}px;top:${rc.y}px;width:${rc.w}px;height:${rc.h}px">
        <div class="phone-card" style="height:${phone.card * k}px;font-size:${Math.max(7, 13 * k)}px">
          <b>${esc(src ? src.question : q.text?.ru?.title || "")}</b>${answers.map((a, i) => `<span>${i + 1}. ${esc(a)}</span>`).join("")}</div>
      </div>
      <div class="phone-bar">
        <span class="muted">Тяните — двигать кадр, колесо — ближе и дальше</span>
        <button class="btn ghost" data-frame="auto">${ic("restart")}Сам подбирать</button>
        <button class="btn ghost" data-frame="cancel">Отмена</button>
        <button class="btn primary" data-frame="save">${ic("check-circle")}Готово</button>
      </div>`;
  }
  $("#phone").addEventListener("click", (e) => {
    const b = e.target.closest("[data-frame]");
    if (b) stop(b.dataset.frame === "cancel" ? null : b.dataset.frame);
  });
  Scene3D.on("phone", (p) => { phone = { ...phone, ...p }; });
  new ResizeObserver(() => { if (phone) { Scene3D.setPhone(phone); render(); } }).observe($("#view"));
  document.addEventListener("keydown", (e) => {
    if (!phone) return;
    if (e.key === "Escape") { e.stopPropagation(); stop(null); }
    if (e.key === "Enter") { e.stopPropagation(); stop("save"); }
  }, true);

  // ---- the ticket's photo ---------------------------------------------------------------------
  const photo = () => state.source && state.source.image ? `/asset/source/${state.source.image}.webp` : null;
  function openPhoto() {
    const src = photo();
    if (!src) return;
    $("#lightbox").innerHTML = `<img src="${src}" alt=""><div class="lightbox-bar"><button class="btn ghost" data-pin>${ic("image")}Закрепить над сценой</button><button class="btn primary" data-close>Закрыть</button></div>`;
    $("#lightbox").hidden = false;
  }
  $("#lightbox").addEventListener("click", (e) => {
    if (e.target.closest("[data-pin]")) { pin(true); $("#lightbox").hidden = true; return; }
    if (e.target.closest("[data-close]") || e.target.id === "lightbox") $("#lightbox").hidden = true;
  });
  // A pinned photo floats over the view: drag it by its top, resize it by its corner.
  let pinned = true, collapsed = false, showQuestion = false, showComment = false;
  function pin(on) {
    pinned = true;
    collapsed = !on;
    const el = $("#refpic");
    const src = photo();
    el.hidden = !state.S || state.id === "mini_regulator";
    if (state.id === "mini_regulator") return;
    el.classList.toggle("collapsed", collapsed);
    const source = state.source, q = state.S?.question || {}, ru = q.text?.ru || {};
    const answers = source ? source.answers.map(a => a.text) : ru.options || [];
    el.innerHTML = `<div class="refpic-head"><span>${esc(App.sceneTitle(state.id))}</span><button class="icon-btn" data-big data-tip="Крупно">${ic("fit")}</button><button class="icon-btn" data-collapse aria-label="Свернуть или развернуть">${collapsed ? "+" : "−"}</button></div>
      ${src ? `<img data-photo src="${src}" alt="Фото текущего вопроса">` : ""}
      <div class="ref-controls"><button class="btn ghost small" data-question aria-pressed="${showQuestion}">Вопрос и ответы</button><button class="btn ghost small" data-comment aria-pressed="${showComment}">Комментарий</button></div>
      <div class="refpic-body">${showQuestion ? `<p class="qtext">${esc(source ? source.question : ru.title || "")}</p><div class="answers">${answers.map((a, i) => `<button class="answer ${q.correct === i ? "on" : ""}" data-correct="${i}"><i>${i + 1}</i><span>${esc(a)}</span></button>`).join("")}</div>` : ""}${showComment ? `<p class="comment">${esc(source?.comment || "Комментарий отсутствует")}</p>` : ""}</div>`;
  }
  (() => {
    const el = $("#refpic");
    let drag = null;
    el.addEventListener("click", (e) => {
      if (e.target.closest("[data-collapse]")) { collapsed = !collapsed; pin(!collapsed); }
      else if (e.target.closest("[data-question]")) { showQuestion = !showQuestion; pin(!collapsed); }
      else if (e.target.closest("[data-comment]")) { showComment = !showComment; pin(!collapsed); }
      else if (e.target.closest("[data-big], [data-photo]")) openPhoto();
      else if (e.target.closest("[data-correct]")) App.edit(s => { s.question.correct = Number(e.target.closest("[data-correct]").dataset.correct); });
    });
    el.addEventListener("pointerdown", (e) => {
      if (e.target.closest("button") || e.target.closest("[data-photo]")) return;
      if (e.target.closest("[data-big]")) { openPhoto(); return; }
      if (!e.target.closest(".refpic-head")) return;
      drag = { x: e.clientX - el.offsetLeft, y: e.clientY - el.offsetTop };
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener("pointermove", (e) => {
      if (!drag) return;
      el.style.left = e.clientX - drag.x + "px";
      el.style.top = e.clientY - drag.y + "px";
    });
    el.addEventListener("pointerup", () => { drag = null; });
  })();

  return { start, stop, openPhoto, pin, refresh: () => pin(!collapsed), get on() { return !!phone; } };
})();
