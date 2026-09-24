// Раздел «Аналитика» админки: заменяет старую разметку и скрипт из
// экранированной строки worker.js. Данные — /api/admin/stats (события по
// дням + сводка профилей). Графики — свой SVG, без Chart.js.
//
// Клиентский код — String.raw без обратных кавычек и ${ внутри.

import { BRAND_ICON_PATHS } from './brand_icons.js';

export const ANALYTICS_VIEW_HTML = String.raw`
    <!-- 1. ANALYTICS VIEW -->
    <div id="analytics-view">
      <style>
        .an-kpis { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:14px; margin-bottom:18px; }
        .an-kpi { background:var(--card-bg); border-radius:18px; padding:18px 18px 14px; display:flex; flex-direction:column; min-height:150px; }
        .an-kpi-label { font-size:12.5px; font-weight:700; color:var(--text-light); display:flex; align-items:center; justify-content:space-between; gap:8px; }
        .an-kpi-value { font-size:32px; font-weight:800; letter-spacing:-1px; margin-top:8px; font-variant-numeric:tabular-nums; line-height:1.1; color:var(--text); }
        .an-kpi-sub { font-size:12px; color:var(--text-muted); margin-top:6px; line-height:1.45; }
        .an-kpi-sub b { color:var(--text-light); font-weight:700; }
        .an-kpi-spark { margin-top:auto; padding-top:10px; }
        .an-delta { display:inline-flex; align-items:center; gap:3px; font-size:12px; font-weight:800; padding:2px 7px; border-radius:7px; white-space:nowrap; font-variant-numeric:tabular-nums; }
        .an-delta.up { color:#0B7A53; background:#E6F6EF; }
        .an-delta.down { color:#C2361A; background:#FDECE8; }
        .an-delta.flat { color:var(--text-muted); background:var(--surface-gray); }
        .an-grid-2 { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr); gap:18px; margin-bottom:18px; }
        .an-card { background:var(--card-bg); border-radius:18px; padding:20px; min-width:0; margin-bottom:18px; }
        .an-grid-2 .an-card { margin-bottom:0; }
        .an-card-head { display:flex; align-items:flex-start; justify-content:space-between; gap:12px; margin-bottom:16px; }
        .an-card-title { font-size:15px; font-weight:800; letter-spacing:-.2px; color:var(--text); }
        .an-card-hint { font-size:12px; color:var(--text-muted); margin-top:3px; }
        .an-installs { display:grid; grid-template-columns:minmax(0,1fr) 260px; gap:24px; align-items:start; }
        .an-chart { position:relative; width:100%; }
        .an-chart svg { display:block; width:100%; height:auto; overflow:visible; }
        .an-legend { display:flex; flex-wrap:wrap; gap:14px; margin-top:10px; font-size:12px; color:var(--text-light); font-weight:600; }
        .an-legend span { display:inline-flex; align-items:center; gap:6px; }
        .an-swatch { width:10px; height:10px; border-radius:3px; display:inline-block; }
        .an-rows { display:flex; flex-direction:column; }
        .an-row { display:grid; grid-template-columns:28px minmax(0,1fr) auto; gap:10px; align-items:center; padding:9px 0; }
        .an-row + .an-row { border-top:1px solid var(--surface-gray); }
        .an-row-name { font-size:13px; font-weight:700; color:var(--text); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .an-row-meta { font-size:11.5px; color:var(--text-muted); margin-top:1px; }
        .an-row-val { text-align:right; font-size:14px; font-weight:800; font-variant-numeric:tabular-nums; color:var(--text); }
        .an-row-val .an-delta { margin-top:3px; }
        .an-share { height:4px; border-radius:2px; background:var(--surface-gray); margin-top:5px; overflow:hidden; }
        .an-share > div { height:100%; border-radius:2px; }
        .an-logo { width:28px; height:28px; border-radius:8px; display:flex; align-items:center; justify-content:center; background:var(--bg); flex-shrink:0; }
        .an-logo svg { width:16px; height:16px; display:block; }
        .an-mono { width:28px; height:28px; border-radius:8px; display:flex; align-items:center; justify-content:center; color:#fff; font-weight:800; font-size:13px; flex-shrink:0; }
        .an-funnel { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; }
        .an-step { background:var(--bg); border-radius:14px; padding:14px; position:relative; }
        .an-step-v { font-size:24px; font-weight:800; letter-spacing:-.5px; font-variant-numeric:tabular-nums; }
        .an-step-l { font-size:12px; color:var(--text-muted); font-weight:600; margin-top:2px; }
        .an-step-rate { font-size:12px; font-weight:700; color:var(--primary); margin-top:8px; }
        .an-table { width:100%; border-collapse:collapse; font-size:13px; }
        .an-table th { text-align:right; font-size:11px; text-transform:uppercase; letter-spacing:.4px; color:var(--text-muted); font-weight:700; padding:0 0 8px; }
        .an-table th:first-child, .an-table td:first-child { text-align:left; }
        .an-table td { text-align:right; padding:8px 0; border-top:1px solid var(--surface-gray); font-variant-numeric:tabular-nums; font-weight:600; color:var(--text); }
        .an-table td + td, .an-table th + th { padding-left:12px; }
        .an-src { display:flex; align-items:center; gap:10px; font-weight:700; }
        .an-muted { color:var(--text-muted); font-weight:500; }
        .an-note { font-size:12px; color:#8A5A00; background:#FFF7E6; border-radius:10px; padding:9px 12px; margin-top:14px; line-height:1.45; }
        .an-empty { color:var(--text-muted); font-size:13px; padding:18px 0; text-align:center; }
        .an-events { display:flex; flex-direction:column; }
        .an-event { display:grid; grid-template-columns:28px minmax(0,1fr) auto; gap:10px; align-items:center; padding:8px 0; font-size:13px; }
        .an-event + .an-event { border-top:1px solid var(--surface-gray); }
        .an-tip { position:fixed; z-index:9999; pointer-events:none; background:#121212; color:#fff; border-radius:10px; padding:9px 11px; font-size:12px; line-height:1.5; box-shadow:0 8px 24px rgba(0,0,0,.18); display:none; min-width:140px; }
        .an-tip b { font-weight:800; }
        .an-tip-row { display:flex; align-items:center; justify-content:space-between; gap:14px; }
        .an-tip-row span { display:inline-flex; align-items:center; gap:6px; }
        @media (max-width: 1200px) { .an-kpis { grid-template-columns:repeat(2,minmax(0,1fr)); } .an-installs { grid-template-columns:1fr; } }
        @media (max-width: 900px) { .an-grid-2 { grid-template-columns:1fr; } .an-funnel { grid-template-columns:1fr; } }
      </style>
      <div class="an-kpis" id="an-kpis"></div>
      <div class="an-card">
        <div class="an-card-head"><div><div class="an-card-title">Установки по дням</div><div class="an-card-hint" id="an-installs-hint"></div></div></div>
        <div class="an-installs"><div><div class="an-chart" id="an-installs-chart"></div><div class="an-legend" id="an-installs-legend"></div></div><div class="an-rows" id="an-stores"></div></div>
        <div id="an-installs-note"></div>
      </div>
      <div class="an-grid-2">
        <div class="an-card">
          <div class="an-card-head"><div><div class="an-card-title">Сайт → магазин</div><div class="an-card-hint">Сколько посетителей сайта уходят скачивать приложение</div></div></div>
          <div class="an-funnel" id="an-funnel"></div>
          <div class="an-chart" id="an-web-chart" style="margin-top:16px"></div>
          <div class="an-legend" id="an-web-legend"></div>
        </div>
        <div class="an-card">
          <div class="an-card-head"><div><div class="an-card-title">Откуда приходят на сайт</div><div class="an-card-hint">Визиты и переходы в магазин по источникам</div></div></div>
          <div id="an-sources"></div>
        </div>
      </div>
      <div class="an-grid-2">
        <div class="an-card" id="an-apps-card">
          <div class="an-card-head"><div><div class="an-card-title">По странам</div><div class="an-card-hint">Установки за период и зарегистрированные пользователи</div></div></div>
          <div id="an-apps"></div>
        </div>
        <div class="an-card">
          <div class="an-card-head"><div><div class="an-card-title">Последние события</div><div class="an-card-hint">Установки и переходы в магазин</div></div></div>
          <div class="an-events" id="an-events"></div>
        </div>
      </div>
      <div class="an-tip" id="an-tip"></div>
    </div>
`;

const CLIENT = String.raw`
// ────────────────────── Analytics (analytics_ui.js) ──────────────────────
var AN_RELIABLE_FROM = '2026-09-25';
var AN_STORES = {
  'Google Play': { color: '#0B8A5F', icon: 'googleplay' },
  'RuStore': { color: '#1F6FEB', mono: 'R', bg: '#0077FF' },
  'App Store': { color: '#D97706', icon: 'appstore' },
  'TestFlight': { color: '#C026D3', icon: 'appstore' }
};
var AN_STORE_ORDER = ['Google Play', 'RuStore', 'App Store', 'TestFlight'];
var AN_SOURCES = {
  yandex: { name: 'Яндекс', mono: 'Я', bg: '#FC3F1D' },
  google: { name: 'Google', icon: 'google' },
  instagram: { name: 'Instagram', icon: 'instagram' },
  youtube: { name: 'YouTube', icon: 'youtube' },
  tiktok: { name: 'TikTok', icon: 'tiktok' },
  telegram: { name: 'Telegram', icon: 'telegram' },
  vk: { name: 'ВКонтакте', icon: 'vk' },
  threads: { name: 'Threads', icon: 'threads' },
  dzen: { name: 'Дзен', mono: 'Д', bg: '#000000' },
  direct: { name: 'Прямые заходы', glyph: 'link' },
  other: { name: 'Другие сайты', glyph: 'globe' }
};
var AN_APPS = { ru: 'Россия', by: 'Беларусь', rs: 'Сербия' };

function anEsc(v) { return typeof adminEsc === 'function' ? adminEsc(v) : String(v == null ? '' : v); }
function anNum(n) { return Number(n || 0).toLocaleString('ru-RU'); }
function anPlural(n, one, few, many) { var a = Math.abs(n) % 100, b = a % 10; if (a > 10 && a < 20) return many; if (b > 1 && b < 5) return few; if (b === 1) return one; return many; }
function anIcon(key, size) {
  var d = AN_BRAND_PATHS[key];
  var color = { googleplay: '#01875F', appstore: '#0D96F6', instagram: '#FF0069', youtube: '#FF0000', telegram: '#26A5E4', vk: '#0077FF', tiktok: '#000000', threads: '#000000', google: '#4285F4' }[key] || '#8E92A0';
  return '<svg viewBox="0 0 24 24" width="' + (size || 16) + '" height="' + (size || 16) + '" aria-hidden="true"><path fill="' + color + '" d="' + d + '"/></svg>';
}
function anGlyph(kind) {
  if (kind === 'link') return '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="#6B7280" stroke-width="2" stroke-linecap="round"><path d="M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1 1"/><path d="M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1-1"/></svg>';
  return '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="#6B7280" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>';
}
function anLogo(conf) {
  if (conf.mono) return '<span class="an-mono" style="background:' + conf.bg + '">' + conf.mono + '</span>';
  if (conf.icon) return '<span class="an-logo">' + anIcon(conf.icon) + '</span>';
  return '<span class="an-logo">' + anGlyph(conf.glyph) + '</span>';
}
function anSourceKey(raw) {
  var s = String(raw || '').toLowerCase();
  if (!s || s === 'direct' || s === 'none' || s === '(direct)') return 'direct';
  if (s.indexOf('yandex') !== -1 || s === 'ya' || s.indexOf('ya.ru') !== -1) return 'yandex';
  if (s === 'ig' || s.indexOf('instagram') !== -1) return 'instagram';
  if (s === 'yt' || s.indexOf('youtube') !== -1) return 'youtube';
  if (s === 'tt' || s.indexOf('tiktok') !== -1) return 'tiktok';
  if (s === 'tg' || s.indexOf('telegram') !== -1) return 'telegram';
  if (s === 'vk' || s.indexOf('vkontakte') !== -1) return 'vk';
  if (s === 'th' || s.indexOf('threads') !== -1) return 'threads';
  if (s.indexOf('dzen') !== -1 || s.indexOf('zen.yandex') !== -1) return 'dzen';
  if (s.indexOf('google') !== -1) return 'google';
  return 'other';
}
function anStoreConf(name) { return AN_STORES[name] || { color: '#8E92A0', glyph: 'globe' }; }
function anStoreLogo(name) {
  var c = anStoreConf(name);
  if (c.mono) return '<span class="an-mono" style="background:' + c.bg + '">' + c.mono + '</span>';
  if (c.icon) return '<span class="an-logo">' + anIcon(c.icon) + '</span>';
  return '<span class="an-logo">' + anGlyph('globe') + '</span>';
}
function anTargetStore(t) {
  var s = String(t || '').toLowerCase();
  if (s.indexOf('gplay') !== -1 || s.indexOf('google') !== -1) return 'Google Play';
  if (s.indexOf('rustore') !== -1) return 'RuStore';
  if (s.indexOf('appstore') !== -1 || s.indexOf('apple') !== -1) return 'App Store';
  if (s.indexOf('web') !== -1) return 'Веб-версия';
  return t || 'Другое';
}

// Изменение к прошлому периоду: ▲/▼, абсолютное и в процентах.
function anDelta(cur, prev) {
  cur = Number(cur || 0); prev = Number(prev || 0);
  var diff = cur - prev;
  if (!diff) return '<span class="an-delta flat">без изменений</span>';
  var pct = prev ? Math.round(diff / prev * 100) : null;
  var cls = diff > 0 ? 'up' : 'down';
  var arrow = diff > 0 ? '▲' : '▼';
  return '<span class="an-delta ' + cls + '" title="Было ' + anNum(prev) + '">' + arrow + ' ' + (diff > 0 ? '+' : '') + anNum(diff)
    + (pct !== null && Math.abs(pct) < 1000 ? ' · ' + (pct > 0 ? '+' : '') + pct + '%' : '') + '</span>';
}
function anPeriodWord() { return currentDays === 1 ? 'ко вчера' : 'к прошлым ' + currentDays + ' ' + anPlural(currentDays, 'дню', 'дням', 'дням'); }
function anDayLabel(key, withDow) {
  var p = key.split('-');
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2]));
  var s = d.getUTCDate() + '.' + String(d.getUTCMonth() + 1).padStart(2, '0');
  if (withDow) s = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'][d.getUTCDay()] + ', ' + s;
  return s;
}

// ── Всплывающая подсказка ──
function anTipShow(html, ev) {
  var t = document.getElementById('an-tip'); if (!t) return;
  t.innerHTML = html; t.style.display = 'block';
  var x = ev.clientX + 14, y = ev.clientY + 14;
  var r = t.getBoundingClientRect();
  if (x + r.width > window.innerWidth - 8) x = ev.clientX - r.width - 14;
  if (y + r.height > window.innerHeight - 8) y = ev.clientY - r.height - 14;
  t.style.left = x + 'px'; t.style.top = y + 'px';
}
function anTipHide() { var t = document.getElementById('an-tip'); if (t) t.style.display = 'none'; }
function anBindTips(root, tips) {
  root.querySelectorAll('[data-tip]').forEach(function (el) {
    el.addEventListener('mousemove', function (e) { anTipShow(tips[+el.dataset.tip], e); });
    el.addEventListener('mouseleave', anTipHide);
  });
}

// ── Мини-гистограмма в карточке показателя ──
function anSpark(values, color) {
  if (!values.length || currentDays === 1) return '';
  var w = 220, h = 34, n = values.length, gap = n > 40 ? 1 : 2;
  var bw = Math.max(1, (w - gap * (n - 1)) / n);
  var max = Math.max.apply(null, values.concat([1]));
  var bars = values.map(function (v, i) {
    var bh = v ? Math.max(3, v / max * h) : 2;
    return '<rect x="' + (i * (bw + gap)).toFixed(1) + '" y="' + (h - bh).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + bh.toFixed(1) + '" rx="' + Math.min(2, bw / 2) + '" fill="' + (v ? color : '#E5E7EB') + '"/>';
  }).join('');
  return '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none" style="width:100%;height:34px">' + bars + '</svg>';
}

// ── Столбчатый график по дням (с накоплением по сериям) ──
function anBarChart(el, days, series, opts) {
  opts = opts || {};
  var W = opts.width || 720, H = opts.height || 220, padL = 30, padB = 24, padT = 8;
  var n = days.length, plotW = W - padL, plotH = H - padB - padT;
  var totals = days.map(function (d) { return series.reduce(function (s, sr) { return s + (d.values[sr.key] || 0); }, 0); });
  var max = Math.max.apply(null, totals.concat([1]));
  var step = max <= 5 ? 1 : Math.ceil(max / 4 / Math.pow(10, Math.floor(Math.log10(max / 4)))) * Math.pow(10, Math.floor(Math.log10(max / 4)));
  var top = Math.ceil(max / step) * step;
  var slot = plotW / n, bw = Math.min(36, Math.max(2, slot * 0.64));
  var y = function (v) { return padT + plotH - v / top * plotH; };
  var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="' + anEsc(opts.label || '') + '">';
  for (var g = 0; g <= top; g += step) {
    svg += '<line x1="' + padL + '" x2="' + W + '" y1="' + y(g) + '" y2="' + y(g) + '" stroke="#EEF0F3" stroke-width="1"/>';
    svg += '<text x="' + (padL - 8) + '" y="' + (y(g) + 4) + '" text-anchor="end" font-size="11" fill="#8E92A0">' + g + '</text>';
  }
  var labelEvery = Math.ceil(n / 10);
  var tips = [];
  days.forEach(function (d, i) {
    var x = padL + i * slot + (slot - bw) / 2;
    var acc = 0;
    var unreliable = opts.reliableFrom && d.date < opts.reliableFrom;
    series.forEach(function (sr, si) {
      var v = d.values[sr.key] || 0; if (!v) return;
      var y0 = y(acc), y1 = y(acc + v);
      var hgt = Math.max(1, y0 - y1 - (acc ? 2 : 0));
      svg += '<rect x="' + x.toFixed(1) + '" y="' + y1.toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + hgt.toFixed(1) + '" rx="' + (acc + v === totals[i] ? Math.min(4, bw / 2) : 0) + '" fill="' + sr.color + '"' + (unreliable ? ' opacity=".32"' : '') + '/>';
      acc += v;
    });
    if (i % labelEvery === 0 || i === n - 1) {
      svg += '<text x="' + (padL + i * slot + slot / 2) + '" y="' + (H - 6) + '" text-anchor="middle" font-size="11" fill="#8E92A0">' + anDayLabel(d.date) + '</text>';
    }
    var rows = series.filter(function (sr) { return d.values[sr.key]; }).map(function (sr) {
      return '<div class="an-tip-row"><span><i class="an-swatch" style="background:' + sr.color + '"></i>' + anEsc(sr.name) + '</span><b>' + anNum(d.values[sr.key]) + '</b></div>';
    }).join('');
    tips.push('<div style="font-weight:800;margin-bottom:4px">' + anDayLabel(d.date, true) + ' · ' + anNum(totals[i]) + '</div>' + (rows || '<div style="opacity:.7">нет данных</div>')
      + (unreliable ? '<div style="opacity:.7;margin-top:4px">данные неполные</div>' : '') + (d.extra ? '<div style="opacity:.7;margin-top:4px">' + d.extra + '</div>' : ''));
    svg += '<rect data-tip="' + i + '" x="' + (padL + i * slot) + '" y="' + padT + '" width="' + slot + '" height="' + plotH + '" fill="transparent"/>';
  });
  svg += '</svg>';
  el.innerHTML = svg;
  anBindTips(el, tips);
}

// ── Отрисовка ──
function renderDashboard(data) {
  if (!document.getElementById('an-kpis')) return;
  window.__anData = data;
  var t = data.totals || {}, p = data.previous || {}, u = data.users || null;
  var timeline = data.timeline || [];

  // KPI
  var storeSet = {};
  timeline.forEach(function (d) { Object.keys(d.stores || {}).forEach(function (s) { storeSet[s] = 1; }); });
  var kpis = [];
  kpis.push('<div class="an-kpi"><div class="an-kpi-label">Новые установки ' + anDelta(t.installs, p.installs) + '</div>'
    + '<div class="an-kpi-value">' + anNum(t.installs) + '</div>'
    + '<div class="an-kpi-sub">Всего с начала: <b>' + anNum(t.grandTotal) + '</b>'
    + (t.returning ? '<br>Ещё <b>' + anNum(t.returning) + '</b> давних пользователей впервые отметились после обновления' : '') + '</div>'
    + '<div class="an-kpi-spark">' + anSpark(timeline.map(function (d) { return d.installs; }), '#0574F8') + '</div></div>');
  if (u) {
    var regDays = Object.keys(u.registrationsByDay || {}).sort();
    kpis.push('<div class="an-kpi"><div class="an-kpi-label">Регистрации ' + anDelta(u.registrations, u.previousRegistrations) + '</div>'
      + '<div class="an-kpi-value">' + anNum(u.registrations) + '</div>'
      + '<div class="an-kpi-sub">Вошли через Google или Apple. Всего аккаунтов: <b>' + anNum(u.registered) + '</b></div>'
      + '<div class="an-kpi-spark">' + anSpark(regDays.map(function (k) { return u.registrationsByDay[k]; }), '#0574F8') + '</div></div>');
    kpis.push('<div class="an-kpi"><div class="an-kpi-label">Активные за 7 дней</div>'
      + '<div class="an-kpi-value">' + anNum(u.active7) + '</div>'
      + '<div class="an-kpi-sub">Сегодня: <b>' + anNum(u.active1) + '</b> · за 30 дней: <b>' + anNum(u.active30) + '</b><br>'
      + (u.registered ? '<b>' + Math.round(u.active30 / u.registered * 100) + '%</b> аккаунтов заходили за месяц' : '') + '</div></div>');
    var bySrc = u.premiumBySource || {};
    var store = 0, manual = 0;
    Object.keys(bySrc).forEach(function (k) { if (k === 'admin_grant') manual += bySrc[k]; else store += bySrc[k]; });
    kpis.push('<div class="an-kpi"><div class="an-kpi-label">Premium сейчас</div>'
      + '<div class="an-kpi-value">' + anNum(u.premium) + '</div>'
      + '<div class="an-kpi-sub">' + (u.registered ? '<b>' + (u.premium / u.registered * 100).toFixed(1).replace('.0', '') + '%</b> аккаунтов<br>' : '')
      + 'Оплачено: <b>' + anNum(store) + '</b> · выдано вручную: <b>' + anNum(manual) + '</b></div></div>');
  }
  document.getElementById('an-kpis').innerHTML = kpis.join('');

  // Установки по магазинам
  var stores = AN_STORE_ORDER.filter(function (s) { return storeSet[s]; })
    .concat(Object.keys(storeSet).filter(function (s) { return AN_STORE_ORDER.indexOf(s) === -1; }));
  var series = stores.map(function (s) { return { key: s, name: s, color: anStoreConf(s).color }; });
  var chartEl = document.getElementById('an-installs-chart');
  var installsBox = chartEl.parentElement.parentElement;
  installsBox.style.gridTemplateColumns = currentDays > 1 ? '' : '1fr';
  chartEl.parentElement.style.display = currentDays > 1 ? '' : 'none';
  if (currentDays > 1) {
    anBarChart(chartEl, timeline.map(function (d) {
      return { date: d.date, values: d.stores || {}, extra: d.returning ? '+' + d.returning + ' вернулись после обновления' : '' };
    }), series, { label: 'Установки по дням и магазинам', reliableFrom: AN_RELIABLE_FROM });
    document.getElementById('an-installs-legend').innerHTML = series.map(function (s) {
      return '<span><i class="an-swatch" style="background:' + s.color + '"></i>' + anEsc(s.name) + '</span>';
    }).join('');
  } else {
    chartEl.innerHTML = ''; document.getElementById('an-installs-legend').innerHTML = '';
  }
  document.getElementById('an-installs-hint').textContent = currentDays > 1
    ? 'Первый запуск приложения из магазина, по дням (МСК)'
    : 'Сегодня с 00:00 МСК · сравнение со всем вчерашним днём, поэтому днём цифры ниже';
  var totalStore = stores.reduce(function (s, k) { return s + timeline.reduce(function (a, d) { return a + ((d.stores || {})[k] || 0); }, 0); }, 0);
  var prevStores = p.stores || {};
  var allStores = stores.slice();
  Object.keys(prevStores).forEach(function (s) { if (allStores.indexOf(s) === -1) allStores.push(s); });
  document.getElementById('an-stores').innerHTML = allStores.length ? allStores.map(function (s) {
    var v = timeline.reduce(function (a, d) { return a + ((d.stores || {})[s] || 0); }, 0);
    var share = totalStore ? Math.round(v / totalStore * 100) : 0;
    return '<div class="an-row">' + anStoreLogo(s)
      + '<div style="min-width:0"><div class="an-row-name">' + anEsc(s) + '</div><div class="an-share"><div style="width:' + share + '%;background:' + anStoreConf(s).color + '"></div></div><div class="an-row-meta">' + share + '% установок</div></div>'
      + '<div class="an-row-val">' + anNum(v) + '<br>' + anDelta(v, prevStores[s] || 0) + '</div></div>';
  }).join('') : '<div class="an-empty">Установок за период нет</div>';
  var firstDay = timeline.length ? timeline[0].date : '';
  document.getElementById('an-installs-note').innerHTML = firstDay && firstDay < AN_RELIABLE_FROM
    ? '<div class="an-note">Дни до ' + anDayLabel(AN_RELIABLE_FROM) + ' показаны бледно: тогда сервер отбрасывал часть свежих установок (приложение ошибочно помечало их как обновление), а 24.09 в установки попали и давние пользователи. Сравнение с этими днями занижено или завышено.</div>'
    : '';

  // Сайт → магазин
  var ctr = t.views ? (t.clicks / t.views * 100) : 0;
  var steps = [
    ['Визиты сайта', t.views, p.views, ''],
    ['Переходы в магазин', t.clicks, p.clicks, t.views ? ctr.toFixed(1).replace('.0', '') + '% посетителей' : '']
  ];
  var targets = (data.targets || []).map(function (x) { return { name: anTargetStore(x.name), clicks: x.clicks }; });
  var merged = {};
  targets.forEach(function (x) { merged[x.name] = (merged[x.name] || 0) + x.clicks; });
  var topTarget = Object.keys(merged).sort(function (a, b) { return merged[b] - merged[a]; })[0];
  document.getElementById('an-funnel').innerHTML = steps.map(function (s) {
    return '<div class="an-step"><div class="an-step-l">' + s[0] + '</div><div class="an-step-v">' + anNum(s[1]) + '</div><div style="margin-top:6px">' + anDelta(s[1], s[2]) + '</div>'
      + (s[3] ? '<div class="an-step-rate">' + s[3] + '</div>' : '') + '</div>';
  }).join('') + '<div class="an-step"><div class="an-step-l">Куда переходят</div>'
    + (Object.keys(merged).length ? Object.keys(merged).sort(function (a, b) { return merged[b] - merged[a]; }).slice(0, 4).map(function (k) {
      return '<div style="display:flex;justify-content:space-between;gap:8px;font-size:13px;font-weight:700;margin-top:6px;align-items:center"><span style="display:inline-flex;align-items:center;gap:6px">'
        + (AN_STORES[k] ? (AN_STORES[k].icon ? anIcon(AN_STORES[k].icon, 14) : '<i class="an-swatch" style="background:' + AN_STORES[k].bg + '"></i>') : anGlyph('globe').replace(/16/g, '14')) + anEsc(k) + '</span><span>' + anNum(merged[k]) + '</span></div>';
    }).join('') : '<div class="an-step-l" style="margin-top:6px">переходов нет</div>') + '</div>';
  if (currentDays > 1) {
    anBarChart(document.getElementById('an-web-chart'), timeline.map(function (d) {
      return { date: d.date, values: { clicks: d.clicks, rest: Math.max(0, d.views - d.clicks) } };
    }), [{ key: 'clicks', name: 'Перешли в магазин', color: '#0574F8' }, { key: 'rest', name: 'Только посмотрели сайт', color: '#C9D8F5' }], { width: 480, height: 170, label: 'Визиты сайта по дням' });
    document.getElementById('an-web-legend').innerHTML = '<span><i class="an-swatch" style="background:#0574F8"></i>Перешли в магазин</span><span><i class="an-swatch" style="background:#C9D8F5"></i>Только посмотрели сайт</span>';
  } else {
    document.getElementById('an-web-chart').innerHTML = ''; document.getElementById('an-web-legend').innerHTML = '';
  }

  // Источники: только трафик сайта (визиты/клики), установки по магазинам — выше.
  var srcMap = {}, prevSrc = {};
  (data.sources || []).forEach(function (s) {
    if (!s.views && !s.clicks) return;
    var k = anSourceKey(s.name);
    if (!srcMap[k]) srcMap[k] = { views: 0, clicks: 0 };
    srcMap[k].views += s.views || 0; srcMap[k].clicks += s.clicks || 0;
  });
  Object.keys(p.sources || {}).forEach(function (name) {
    var k = anSourceKey(name), v = p.sources[name];
    if (!prevSrc[k]) prevSrc[k] = { views: 0, clicks: 0 };
    prevSrc[k].views += v.views || 0; prevSrc[k].clicks += v.clicks || 0;
  });
  var srcKeys = Object.keys(srcMap).sort(function (a, b) { return srcMap[b].views - srcMap[a].views || srcMap[b].clicks - srcMap[a].clicks; });
  document.getElementById('an-sources').innerHTML = srcKeys.length
    ? '<table class="an-table"><thead><tr><th>Источник</th><th>Визиты</th><th>В магазин</th><th>Конверсия</th></tr></thead><tbody>'
      + srcKeys.map(function (k) {
        var s = srcMap[k], conf = AN_SOURCES[k];
        var conv = s.views ? Math.round(s.clicks / s.views * 100) + '%' : '<span class="an-muted">—</span>';
        return '<tr><td><div class="an-src">' + anLogo(conf) + anEsc(conf.name) + '</div></td>'
          + '<td>' + anNum(s.views) + '<div>' + anDelta(s.views, (prevSrc[k] || {}).views || 0) + '</div></td>'
          + '<td>' + anNum(s.clicks) + '</td><td>' + conv + '</td></tr>';
      }).join('') + '</tbody></table>'
    : '<div class="an-empty">Визитов за период нет</div>';

  // По странам — только когда выбраны все проекты.
  var appsCard = document.getElementById('an-apps-card');
  var apps = data.apps || {};
  var byApp = (u && u.byApp) || {};
  var codes = ['ru', 'by', 'rs'].filter(function (c) { return apps[c] || byApp[c]; });
  appsCard.style.display = currentApp === 'all' && codes.length ? '' : 'none';
  document.getElementById('an-apps').innerHTML = '<table class="an-table"><thead><tr><th>Страна</th><th>Установки</th><th>Аккаунты</th><th>Активны 7 дн</th><th>Premium</th></tr></thead><tbody>'
    + codes.map(function (c) {
      var a = apps[c] || {}, b = byApp[c] || {};
      return '<tr><td><div class="an-src"><span class="an-mono" style="background:#EFF0F4;color:#475569;font-size:11px">' + c.toUpperCase() + '</span>' + (AN_APPS[c] || c) + '</div></td>'
        + '<td>' + anNum(a.installs) + '</td><td>' + anNum(b.registered) + '</td><td>' + anNum(b.active7) + '</td><td>' + anNum(b.premium) + '</td></tr>';
    }).join('') + '</tbody></table>';

  // Последние события: установки и переходы, без просмотров.
  var events = (data.recent || []).filter(function (e) { return e.type === 'install' || e.type === 'click'; }).slice(0, 8);
  document.getElementById('an-events').innerHTML = events.length ? events.map(function (e) {
    var isInstall = e.type === 'install';
    var logo = isInstall ? anStoreLogo(e.source) : anLogo(AN_SOURCES[anSourceKey(e.source)]);
    var what = isInstall ? 'Установка · ' + anEsc(e.source) : 'Переход в ' + anEsc(anTargetStore(e.target)) + ' · ' + anEsc(AN_SOURCES[anSourceKey(e.source)].name);
    var when = new Date(e.time);
    return '<div class="an-event">' + logo + '<div style="min-width:0"><div class="an-row-name">' + what + '</div>'
      + '<div class="an-row-meta">' + anEsc(String(e.country || '').toUpperCase()) + (e.campaign ? ' · кампания ' + anEsc(e.campaign) : '') + '</div></div>'
      + '<div class="an-row-meta" style="white-space:nowrap">' + when.toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) + '</div></div>';
  }).join('') : '<div class="an-empty">Событий пока нет</div>';
}
`;

export const ANALYTICS_CLIENT_JS = 'var AN_BRAND_PATHS = ' + JSON.stringify(BRAND_ICON_PATHS) + ';\n' + CLIENT;
