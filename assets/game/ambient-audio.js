// Ненавязчивый звук мини-игр «Перекрёсток» и «Регулировщик»: фон города
// (далёкий гул улицы, редкие птицы) и короткие отклики на действия.
// Всё синтезируется WebAudio — ни одного звукового файла.
//
//   const audio = window.PDD_AMBIENT.create();
//   audio.unlock();          // по первому касанию (политика автозвука)
//   audio.setEnabled(false); // настройка звука приложения
//   audio.engine('bus'); audio.bell(); audio.siren(); audio.crash();
//   audio.tap(); audio.chime(step);
(() => {
  'use strict';

  function create({ ambience = true } = {}) {
    let ctx = null, master = null, bed = null, birdsTimer = null;
    let enabled = true, unlocked = false, hidden = false;

    function ensure() {
      if (ctx) return ctx;
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
      master = ctx.createGain();
      master.gain.value = 0.9;
      master.connect(ctx.destination);
      return ctx;
    }

    // Розовый шум: одна секунда, зацикленная, — основа и гула, и удара.
    let noiseBuffer = null;
    function noise() {
      if (noiseBuffer) return noiseBuffer;
      const length = ctx.sampleRate * 2, buffer = ctx.createBuffer(1, length, ctx.sampleRate), data = buffer.getChannelData(0);
      let b0 = 0, b1 = 0, b2 = 0;
      for (let i = 0; i < length; i++) {
        const white = Math.random() * 2 - 1;
        b0 = 0.99765 * b0 + white * 0.099;
        b1 = 0.963 * b1 + white * 0.2965;
        b2 = 0.57 * b2 + white * 1.0526;
        data[i] = (b0 + b1 + b2 + white * 0.1848) * 0.2;
      }
      noiseBuffer = buffer;
      return buffer;
    }

    function live() { return enabled && unlocked && !hidden && ctx && ctx.state === 'running'; }

    // Фон: далёкий поток машин (низкий шум с медленной «волной») и птицы.
    function startBed() {
      if (!ambience || bed || !ctx) return;
      const src = ctx.createBufferSource();
      src.buffer = noise(); src.loop = true;
      const low = ctx.createBiquadFilter(); low.type = 'lowpass'; low.frequency.value = 420;
      const gain = ctx.createGain(); gain.gain.value = 0;
      const lfo = ctx.createOscillator(), lfoGain = ctx.createGain();
      lfo.frequency.value = 0.07; lfoGain.gain.value = 0.012;
      lfo.connect(lfoGain).connect(gain.gain);
      src.connect(low).connect(gain).connect(master);
      src.start(); lfo.start();
      gain.gain.linearRampToValueAtTime(0.035, ctx.currentTime + 2.5);
      bed = { src, gain, lfo };
      scheduleBirds();
    }

    function stopBed() {
      if (!bed) return;
      const { src, lfo, gain } = bed;
      try { gain.gain.cancelScheduledValues(ctx.currentTime); gain.gain.setTargetAtTime(0, ctx.currentTime, 0.3); } catch (_) {}
      setTimeout(() => { try { src.stop(); lfo.stop(); } catch (_) {} }, 1200);
      bed = null;
      clearTimeout(birdsTimer);
    }

    function scheduleBirds() {
      clearTimeout(birdsTimer);
      birdsTimer = setTimeout(() => { if (live() && bed) bird(); scheduleBirds(); }, 5000 + Math.random() * 7000);
    }

    function bird() {
      const t = ctx.currentTime, notes = 2 + Math.floor(Math.random() * 3), base = 2600 + Math.random() * 1600;
      for (let i = 0; i < notes; i++) {
        const o = ctx.createOscillator(), g = ctx.createGain(), at = t + i * (0.11 + Math.random() * 0.05);
        o.type = 'sine';
        o.frequency.setValueAtTime(base * (1 + Math.random() * 0.15), at);
        o.frequency.exponentialRampToValueAtTime(base * (0.75 + Math.random() * 0.4), at + 0.08);
        g.gain.setValueAtTime(0, at);
        g.gain.linearRampToValueAtTime(0.012, at + 0.015);
        g.gain.exponentialRampToValueAtTime(0.0001, at + 0.09);
        o.connect(g).connect(master); o.start(at); o.stop(at + 0.1);
      }
    }

    function env(g, at, peak, attack, release) {
      g.gain.setValueAtTime(0.0001, at);
      g.gain.exponentialRampToValueAtTime(peak, at + attack);
      g.gain.exponentialRampToValueAtTime(0.0001, at + attack + release);
    }

    // Машина трогается и уезжает: мотор поднимает тон, шум шин затихает.
    const ENGINE = { car: [70, 150], suv: [62, 135], truck: [45, 95], bus: [48, 100], motorcycle: [110, 260], police: [70, 150], emergency: [64, 140], tram: [0, 0] };
    function engine(type = 'car', duration = 1.8) {
      if (!live()) return;
      if (type === 'tram') { hum(duration); return; }
      const [from, to] = ENGINE[type] || ENGINE.car, t = ctx.currentTime;
      const o = ctx.createOscillator(), filter = ctx.createBiquadFilter(), g = ctx.createGain();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(from, t);
      o.frequency.exponentialRampToValueAtTime(to, t + duration * 0.7);
      filter.type = 'lowpass'; filter.frequency.setValueAtTime(380, t); filter.frequency.linearRampToValueAtTime(900, t + duration * 0.6);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(type === 'truck' || type === 'bus' ? 0.06 : 0.045, t + 0.25);
      g.gain.exponentialRampToValueAtTime(0.0001, t + duration);
      o.connect(filter).connect(g).connect(master); o.start(t); o.stop(t + duration + 0.05);
      const s = ctx.createBufferSource(), band = ctx.createBiquadFilter(), sg = ctx.createGain();
      s.buffer = noise(); band.type = 'bandpass'; band.frequency.value = 700; band.Q.value = 0.8;
      env(sg, t, 0.035, 0.4, duration);
      s.connect(band).connect(sg).connect(master); s.start(t); s.stop(t + duration + 0.5);
    }

    // Трамвай: гул тяговых двигателей и звонок.
    function hum(duration) {
      const t = ctx.currentTime, o = ctx.createOscillator(), g = ctx.createGain();
      o.type = 'triangle'; o.frequency.setValueAtTime(110, t); o.frequency.linearRampToValueAtTime(190, t + duration);
      env(g, t, 0.04, 0.3, duration);
      o.connect(g).connect(master); o.start(t); o.stop(t + duration + 0.4);
      bell();
    }

    function bell() {
      if (!live()) return;
      const t = ctx.currentTime;
      for (const at of [t, t + 0.28]) for (const [f, a] of [[1180, 0.05], [1770, 0.025], [2950, 0.012]]) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'sine'; o.frequency.value = f; env(g, at, a, 0.005, 0.9);
        o.connect(g).connect(master); o.start(at); o.stop(at + 1);
      }
    }

    // Спецсигнал: два тона, вполголоса.
    function siren(duration = 1.8) {
      if (!live()) return;
      const t = ctx.currentTime, o = ctx.createOscillator(), g = ctx.createGain();
      o.type = 'triangle';
      for (let k = 0; k < duration / 0.36; k++) o.frequency.setValueAtTime(k % 2 ? 960 : 720, t + k * 0.36);
      env(g, t, 0.035, 0.1, duration);
      o.connect(g).connect(master); o.start(t); o.stop(t + duration + 0.2);
    }

    // ДТП: глухой удар и хруст.
    function crash() {
      if (!live()) return;
      const t = ctx.currentTime;
      const s = ctx.createBufferSource(), low = ctx.createBiquadFilter(), g = ctx.createGain();
      s.buffer = noise(); low.type = 'lowpass';
      low.frequency.setValueAtTime(3200, t); low.frequency.exponentialRampToValueAtTime(240, t + 0.5);
      env(g, t, 0.35, 0.005, 0.55);
      s.connect(low).connect(g).connect(master); s.start(t); s.stop(t + 0.7);
      const o = ctx.createOscillator(), og = ctx.createGain();
      o.type = 'sine'; o.frequency.setValueAtTime(90, t); o.frequency.exponentialRampToValueAtTime(38, t + 0.3);
      env(og, t, 0.3, 0.005, 0.35);
      o.connect(og).connect(master); o.start(t); o.stop(t + 0.4);
    }

    function tap() {
      if (!live()) return;
      const t = ctx.currentTime, o = ctx.createOscillator(), g = ctx.createGain();
      o.type = 'sine'; o.frequency.setValueAtTime(880, t); o.frequency.exponentialRampToValueAtTime(620, t + 0.05);
      env(g, t, 0.05, 0.004, 0.06);
      o.connect(g).connect(master); o.start(t); o.stop(t + 0.08);
    }

    // Верный шаг: две ноты, с каждым шагом на тон выше (серия звучит как лесенка).
    function chime(step = 1) {
      if (!live()) return;
      const t = ctx.currentTime, base = 523.25 * Math.pow(2, (Math.min(step, 8) - 1) * 2 / 12);
      [[base, 0], [base * 1.5, 0.09]].forEach(([f, d]) => {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'sine'; o.frequency.value = f; env(g, t + d, 0.06, 0.006, 0.35);
        o.connect(g).connect(master); o.start(t + d); o.stop(t + d + 0.4);
      });
    }

    function unlock() {
      if (!ensure()) return;
      const go = () => { unlocked = true; if (enabled && !hidden) startBed(); };
      if (ctx.state === 'suspended') ctx.resume().then(go).catch(() => {}); else go();
    }

    function setEnabled(on) {
      enabled = on !== false;
      if (!ctx) return;
      if (enabled && unlocked && !hidden) { ctx.resume().catch(() => {}); startBed(); }
      else stopBed();
    }

    document.addEventListener('visibilitychange', () => {
      hidden = document.hidden;
      if (!ctx) return;
      if (hidden) { stopBed(); ctx.suspend().catch(() => {}); }
      else if (enabled && unlocked) ctx.resume().then(startBed).catch(() => {});
    });

    return { unlock, setEnabled, engine, bell, siren, crash, tap, chime };
  }

  window.PDD_AMBIENT = { create };
})();
