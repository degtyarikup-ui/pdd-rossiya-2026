// On-screen pedals and steering arrows, drawn by the page itself.
// They used to be Flutter widgets over the WebView: every press crossed the
// Flutter -> WebView bridge (an async runJavaScript on a busy platform thread),
// which on a weak phone made the car answer a noticeable moment after the
// finger. Here a press reaches the engine in the same event, with no bridge.
// Flutter only says when the controls are shown/enabled and what colours and
// labels to use (configure()); haptics and the first-gas hint go back as events.
(function () {
  const SVG = {
    left: '<svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>',
    right: '<svg viewBox="0 0 24 24"><path d="M12 4l-1.41 1.41L16.17 11H4v2h12.17l-5.58 5.59L12 20l8-8-8-8z"/></svg>',
    gas: '<svg viewBox="0 0 24 24"><path d="M6 17.59 7.41 19 12 14.42 16.59 19 18 17.59l-6-6zM6 11l1.41 1.41L12 7.83l4.59 4.58L18 11l-6-6z"/></svg>',
    brake: '<svg viewBox="0 0 44 44"><g transform="rotate(-9.17 22 22)" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M22 27V36L30 40"/><rect x="7" y="4" width="30" height="24" rx="6" fill="currentColor" fill-opacity=".12"/>' +
      '<path d="M14 11H30M14 16H30M14 21H30"/></g></svg>',
  };
  const CSS = `
#pdd-controls{position:absolute;inset:0;z-index:50;pointer-events:none;display:none;
  --acc:#0574F8;--card:#fff;--txt:#121212;--sec:#A1A6B7;--red:#F04438;--dark:#1C1D22;
  font-family:Onest,system-ui,sans-serif}
#pdd-controls.on{display:block}
#pdd-controls .grp{position:absolute;display:flex;gap:10px}
#pdd-controls .btn{pointer-events:auto;touch-action:none;position:relative;display:flex;flex-direction:column;
  align-items:center;justify-content:center;background:var(--bg,var(--card));color:var(--ic,var(--acc));
  border-radius:8px;-webkit-tap-highlight-color:transparent}
#pdd-controls .btn svg{width:30px;height:30px;fill:currentColor}
#pdd-controls .btn.brake svg{width:44px;height:44px;fill:none}
#pdd-controls .btn.off{color:var(--sec)}
#pdd-controls .btn.down{background:var(--act,var(--acc));color:#fff}
#pdd-controls .gas{border-radius:50%;width:100px;height:100px;color:var(--txt)}
#pdd-controls .gas svg{width:44px;height:44px}
#pdd-controls .gas span{font-size:10px;font-weight:700;letter-spacing:.6px;color:var(--sec)}
#pdd-controls .gas.down span{color:#fff}
#pdd-controls .brake{--bg:var(--dark);--ic:#fff;--act:var(--red);width:100px;height:76px}`;

  let root = null, enabled = false, visible = false, epoch = null, send = () => {};
  const held = [];       // steering directions currently pressed, last wins
  const releasers = [];  // one per button: force-release

  function steer() {
    const dir = enabled && held.length ? held[held.length - 1] : 0;
    window.game && window.game.setSteering(dir);
  }
  function bind(el, onChange, haptic) {
    let pid = null;
    const down = (e) => {
      if (!enabled || pid !== null) return;
      e.preventDefault();
      pid = e.pointerId;
      try { el.setPointerCapture(pid); } catch (_) {}
      el.classList.add('down');
      if (window.PDD_PERF) window.PDD_PERF.input(e.timeStamp);
      if (haptic) send({ event: 'haptic', kind: haptic });
      onChange(true);
    };
    const up = (e) => {
      if (pid === null || (e && e.pointerId !== pid)) return;
      release();
    };
    const release = () => {
      if (pid === null) return;
      pid = null;
      el.classList.remove('down');
      onChange(false);
    };
    el.addEventListener('pointerdown', down);
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('lostpointercapture', up);
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    releasers.push(release);
  }
  function make(cls, svg, label, onChange, haptic) {
    const el = document.createElement('div');
    el.className = 'btn ' + cls;
    el.setAttribute('role', 'button');
    el.innerHTML = svg + (label ? '<span></span>' : '');
    bind(el, onChange, haptic);
    return el;
  }
  function steerBtn(cls, svg, dir) {
    return make(cls, svg, false, (isDown) => {
      const i = held.indexOf(dir); if (i >= 0) held.splice(i, 1);
      if (isDown) held.push(dir);
      steer();
    }, 'select');
  }

  function build() {
    if (root) return;
    const style = document.createElement('style'); style.textContent = CSS; document.head.appendChild(style);
    root = document.createElement('div'); root.id = 'pdd-controls';
    const left = document.createElement('div'); left.className = 'grp'; left.dataset.side = 'l';
    left.append(steerBtn('left', SVG.left, 1), steerBtn('right', SVG.right, -1));
    const right = document.createElement('div'); right.className = 'grp'; right.dataset.side = 'r';
    right.style.flexDirection = 'column'; right.style.alignItems = 'center';
    let firstGas = true;
    right.append(
      make('brake', SVG.brake, false, (d) => window.game && window.game.setBrake(d), 'tap'),
      make('gas', SVG.gas, true, (d) => {
        if (d && firstGas) { firstGas = false; send({ event: 'gas_pressed' }); }
        window.game && window.game.setGas(d);
      }, 'select'),
    );
    root.append(left, right);
    document.body.appendChild(root);
  }

  function releaseAll() {
    releasers.forEach((r) => r());
    held.length = 0;
    steer();
  }

  window.PDD_TOUCH = {
    init(sendFn) { send = sendFn; build(); },
    // c: { visible, enabled, epoch, dark?, colors:{accent,card,text,secondary,red,darkCard},
    //      labels:{left,right,brake,gas}, insets:{l,r,b} } (insets in CSS px)
    configure(c) {
      build();
      if (c.colors) {
        const s = root.style, k = c.colors;
        s.setProperty('--acc', k.accent); s.setProperty('--card', k.card); s.setProperty('--txt', k.text);
        s.setProperty('--sec', k.secondary); s.setProperty('--red', k.red); s.setProperty('--dark', k.darkCard);
      }
      if (c.labels) {
        const set = (sel, text) => { const el = root.querySelector(sel); if (el) { el.setAttribute('aria-label', text); const sp = el.querySelector('span'); if (sp) sp.textContent = text; } };
        set('.left', c.labels.left); set('.right', c.labels.right); set('.brake', c.labels.brake); set('.gas', c.labels.gas);
      }
      const ins = c.insets || {};
      const l = 20 + (ins.l || 0), r = 20 + (ins.r || 0), b = 20 + (ins.b || 0);
      const width = Math.max(48, Math.min(74, (window.innerWidth - l - r - 122) / 2));
      const [gl, gr] = root.querySelectorAll('.grp');
      gl.style.left = l + 'px'; gl.style.bottom = b + 'px';
      gr.style.right = r + 'px'; gr.style.bottom = b + 'px';
      gl.querySelectorAll('.btn').forEach((el) => { el.style.width = width + 'px'; el.style.height = '76px'; });
      const wasEnabled = enabled, wasVisible = visible;
      enabled = Boolean(c.enabled); visible = Boolean(c.visible);
      root.classList.toggle('on', visible);
      root.querySelectorAll('.left, .right, .brake').forEach((el) => el.classList.toggle('off', !enabled));
      if ((c.epoch !== undefined && c.epoch !== epoch) || (wasVisible && !visible) || (wasEnabled && !enabled)) releaseAll();
      epoch = c.epoch;
    },
  };
})();
