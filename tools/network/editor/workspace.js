// Transient workspace state lives outside the scene document.
(() => {
  const $ = selector => document.querySelector(selector);
  const app = $("#app"), drawer = $("#left-drawer"), inspector = $("#inspector-shell");
  const compact = matchMedia("(max-width: 960px)");
  const labels = {scenes: "Сцены", layers: "Слои", library: "Объекты", textures: "Текстуры"};
  let autoInspect = true, inspectorForSelection = false;

  function leftPanel(name) {
    drawer.hidden = !name;
    app.classList.toggle("left-open", !!name);
    if (name) $("#drawer-title").textContent = labels[name];
    document.querySelectorAll("[data-ltab]").forEach(button => {
      button.setAttribute("aria-controls", drawer.id);
      button.setAttribute("aria-expanded", String(button.dataset.ltab === name));
    });
  }
  function properties(open, contextual = false) {
    if (open && compact.matches) leftPanel(null);
    inspector.hidden = !open;
    app.classList.toggle("inspector-open", open);
    $("#inspect-toggle").setAttribute("aria-expanded", String(open));
    inspectorForSelection = open && contextual;
  }
  App.showLeftPanel = name => {
    if (compact.matches) properties(false);
    leftPanel(name);
  };
  App.closeLeftPanel = () => leftPanel(null);
  App.leftPanelOpen = () => !drawer.hidden;
  App.dismissCompactDrawer = () => { if (compact.matches) leftPanel(null); };
  App.showInspector = () => { autoInspect = true; properties(true); };
  function closeInspector() { autoInspect = false; properties(false); $("#inspect-toggle").focus(); }
  $("#close-inspector").onclick = closeInspector;
  $("#inspect-toggle").onclick = () => inspector.hidden ? App.showInspector() : closeInspector();
  $("#close-left").onclick = () => { leftPanel(null); $(`[data-ltab="${App.state.ltab}"]`).focus(); };
  compact.addEventListener("change", () => {
    if (compact.matches && !drawer.hidden) properties(false);
  });
  leftPanel(null);

  App.updateWorkspaceStatus = () => {
    const tool = Tools.list().find(t => t.id === Tools.current());
    if (tool && $("#tool-status").dataset.tool !== tool.id) {
      $("#tool-status").innerHTML = App.ic(tool.icon) + App.esc(tool.title);
      $("#tool-status").dataset.tool = tool.id;
    }
    const { dirty, virtual, sel } = App.state;
    $("#selection-status").textContent = sel.length === 1 ? App.nameOf(sel[0]) : sel.length ? `Выбрано · ${sel.length}` : "";
    $("#file-status").textContent = dirty ? "Есть изменения" : virtual ? "Новая сцена" : "Сохранено";
    $("#file-status").classList.toggle("unsaved", !!(dirty || virtual));
  };
  App.selectionChanged = () => {
    if (App.state.sel.length && autoInspect && !compact.matches && Tools.current() === "select" && inspector.hidden) properties(true, true);
    if (!App.state.sel.length && inspectorForSelection) properties(false);
    App.updateWorkspaceStatus();
  };
  App.sceneOpened = () => {
    properties(false);
    autoInspect = true;
    App.dismissCompactDrawer();
    const mini = App.state.id === "mini_regulator";
    $("#reference-toggle").disabled = mini;
    $("#frame-scene").disabled = mini;
    App.updateWorkspaceStatus();
  };
  $("#reference-toggle").onclick = () => { App.dismissCompactDrawer(); Framing.pin($("#refpic").hidden); };
  $("#frame-scene").onclick = () => Framing.start();

  Scene3D.on("camera", ({mode}) => {
    $("#v-plan").setAttribute("aria-pressed", String(mode === "plan"));
    $("#v-3d").setAttribute("aria-pressed", String(mode === "3d"));
    const view = Scene3D.getView(), metresPerPixel = Scene3D.worldPerPixel(view.x, view.z);
    if (!(metresPerPixel > 0)) return;
    const ideal = metresPerPixel * 66, power = 10 ** Math.floor(Math.log10(ideal));
    const metres = [1,2,5].filter(m => m * power <= ideal).at(-1) * power;
    $("#scale-rule").style.width = (metres / metresPerPixel) + "px";
    $("#scale-label").textContent = metres.toLocaleString("ru-RU") + " м";
  });
  // Dialogs temporarily own the keyboard, including Tab and Enter on their buttons.
  const modals = [...document.querySelectorAll(".modal")];
  let modal = null, previousFocus = null;
  function syncDialog() {
    const next = modals.find(el => !el.hidden);
    if (next === modal) return;
    if (next) {
      if (!modal) previousFocus = document.activeElement;
      app.inert = true;
      modal = next;
      (next.querySelector('[data-answer="no"], [data-close]') || next.querySelector("button"))?.focus();
    } else if (modal) {
      app.inert = false;
      modal = null;
      if (previousFocus?.isConnected) previousFocus.focus({preventScroll:true});
      previousFocus = null;
    }
  }
  const dialogs = new MutationObserver(syncDialog);
  modals.forEach(el => dialogs.observe(el, {attributes:true, attributeFilter:["hidden"]}));
  document.addEventListener("keydown", e => {
    if (e.key !== "Tab" || !modal) return;
    const buttons = modal.querySelectorAll("button:not(:disabled)");
    const first = buttons[0], last = buttons[buttons.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });
  document.querySelectorAll("button[data-tip]").forEach(button => {
    if (!button.hasAttribute("aria-label")) button.setAttribute("aria-label", button.dataset.tip);
  });
})();
