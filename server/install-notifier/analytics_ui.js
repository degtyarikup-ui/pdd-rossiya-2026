// Раздел «Аналитика» админки: заменяет старую разметку и скрипт из
// экранированной строки worker.js. Данные — /api/admin/stats (события по
// дням + сводка профилей). Графики — свой SVG в реальных пикселях.
//
// Стиль — токены приложения (AppColors / AppDimensions): акцент #0574F8,
// рост #2BC280, падение #ED4621, текст #121212 / #A1A6B7, серый #EFF0F4,
// скругления 16 (карточка) и 12 (внутри). Три размера текста: 13 — подписи,
// 15 — заголовки и значения списков, 36 — главные числа. Без прозрачности.
//
// Клиентский код — String.raw без обратных кавычек и ${ внутри.

import { BRAND_ICON_PATHS } from './brand_icons.js';

export const ANALYTICS_VIEW_HTML = String.raw`
    <!-- 1. ANALYTICS VIEW -->
    <div id="analytics-view">
      <style>
        #analytics-view { --an-accent:#0574F8; --an-green:#2BC280; --an-red:#ED4621; --an-text:#121212; --an-muted:#A1A6B7; --an-gray:#EFF0F4; }
        .an-kpis { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:16px; margin-bottom:16px; }
        .an-card { background:#fff; border-radius:16px; padding:24px; min-width:0; }
        .an-label { font-size:13px; font-weight:600; color:var(--an-muted); line-height:18px; }
        .an-big { font-size:36px; font-weight:800; letter-spacing:-1px; line-height:44px; color:var(--an-text); margin-top:8px; font-variant-numeric:tabular-nums; }
        .an-delta { font-size:13px; font-weight:700; line-height:18px; margin-top:4px; font-variant-numeric:tabular-nums; white-space:nowrap; }
        .an-delta.up { color:var(--an-green); }
        .an-delta.down { color:var(--an-red); }
        .an-delta.flat { color:var(--an-muted); }
        .an-title { font-size:15px; font-weight:800; line-height:20px; color:var(--an-text); }
        .an-head { display:flex; align-items:baseline; justify-content:space-between; gap:16px; margin-bottom:24px; }
        .an-head .an-title-num { font-size:15px; font-weight:800; color:var(--an-text); font-variant-numeric:tabular-nums; }
        .an-main { display:grid; grid-template-columns:minmax(0,1fr) 280px; gap:32px; align-items:start; margin-bottom:16px; }
        .an-row2 { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr); gap:16px; margin-bottom:16px; align-items:start; }
        .an-chart { position:relative; width:100%; min-height:40px; }
        .an-chart svg { display:block; }
        .an-list { display:flex; flex-direction:column; gap:16px; }
        .an-item { display:grid; grid-template-columns:32px minmax(0,1fr) 72px; gap:12px; align-items:center; }
        .an-item-name { font-size:15px; font-weight:700; color:var(--an-text); line-height:20px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .an-item-val { font-size:15px; font-weight:800; color:var(--an-text); text-align:right; font-variant-numeric:tabular-nums; line-height:20px; }
        .an-item-val .an-delta { margin-top:0; text-align:right; }
        .an-bar { height:6px; border-radius:3px; background:var(--an-gray); margin-top:6px; overflow:hidden; }
        .an-bar > div { height:100%; border-radius:3px; }
        .an-logo { width:32px; height:32px; border-radius:12px; background:#F8F8FA; display:flex; align-items:center; justify-content:center; flex-shrink:0; }
        .an-logo svg { width:18px; height:18px; display:block; }
        .an-mono { width:32px; height:32px; border-radius:12px; display:flex; align-items:center; justify-content:center; color:#fff; font-size:15px; font-weight:800; flex-shrink:0; }
        .an-pair { display:grid; grid-template-columns:1fr 1fr 1fr; gap:16px; margin-bottom:24px; }
        .an-pair .an-big { font-size:28px; line-height:34px; margin-top:4px; }
        .an-empty { font-size:13px; font-weight:600; color:var(--an-muted); padding:24px 0; text-align:center; }
        .an-tip { position:fixed; z-index:9999; pointer-events:none; background:#121212; color:#fff; border-radius:12px; padding:12px; font-size:13px; line-height:20px; display:none; min-width:150px; }
        .an-tip-row { display:flex; justify-content:space-between; gap:16px; }
        .an-tip-row b { font-weight:800; }
        .an-tip-note { color:#A1A6B7; }
        @media (max-width:1200px) { .an-kpis { grid-template-columns:repeat(2,minmax(0,1fr)); } .an-main { grid-template-columns:1fr; } }
        @media (max-width:900px) { .an-row2 { grid-template-columns:1fr; } }
      </style>
      <div class="an-kpis" id="an-kpis"></div>
      <div class="an-card an-main">
        <div><div class="an-head"><div class="an-title">Установки по дням</div></div><div class="an-chart" id="an-installs-chart"></div></div>
        <div><div class="an-head"><div class="an-title">Магазины</div></div><div class="an-list" id="an-stores"></div></div>
      </div>
      <div class="an-row2">
        <div class="an-card">
          <div class="an-head"><div class="an-title">Сайт</div></div>
          <div class="an-pair" id="an-web"></div>
          <div class="an-chart" id="an-web-chart"></div>
        </div>
        <div class="an-card">
          <div class="an-head"><div class="an-title">Источники визитов</div></div>
          <div class="an-list" id="an-sources"></div>
        </div>
      </div>
      <div class="an-card" id="an-apps-card" style="margin-bottom:16px">
        <div class="an-head"><div class="an-title">Страны</div></div>
        <div class="an-kpis" id="an-apps" style="margin:0;grid-template-columns:repeat(3,minmax(0,1fr))"></div>
      </div>
      <div class="an-tip" id="an-tip"></div>
    </div>
`;

const CLIENT = String.raw`
// ────────────────────── Analytics (analytics_ui.js) ──────────────────────
var AN_RELIABLE_FROM = '2026-09-25';
var AN_C = { accent: '#0574F8', green: '#2BC280', red: '#ED4621', text: '#121212', muted: '#A1A6B7', gray: '#EFF0F4', grid: '#F2F3F6' };
// Магазины — цвета их логотипов.
var AN_STORES = {
  'Google Play': { color: '#01875F', icon: 'googleplay' },
  'RuStore': { color: '#0077FF', mono: 'R' },
  'App Store': { color: '#0D96F6', icon: 'appstore' },
  'TestFlight': { color: '#0D96F6', icon: 'appstore' }
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
var AN_ICON_COLORS = { googleplay: '#01875F', appstore: '#0D96F6', instagram: '#FF0069', youtube: '#FF0000', telegram: '#26A5E4', vk: '#0077FF', tiktok: '#000000', threads: '#000000', google: '#4285F4' };

function anEsc(v) { return typeof adminEsc === 'function' ? adminEsc(v) : String(v == null ? '' : v); }
function anPlural(n, one, few, many) { var a = Math.abs(n || 0) % 100, b = a % 10; if (a > 10 && a < 20) return many; if (b > 1 && b < 5) return few; if (b === 1) return one; return many; }
function anNum(n) { return Number(n || 0).toLocaleString('ru-RU'); }
function anSvgIcon(key) { return '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="' + (AN_ICON_COLORS[key] || AN_C.muted) + '" d="' + AN_BRAND_PATHS[key] + '"/></svg>'; }
function anGlyph(kind) {
  if (kind === 'link') return '<svg viewBox="0 0 24 24" fill="none" stroke="#A1A6B7" stroke-width="2.2" stroke-linecap="round"><path d="M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1 1"/><path d="M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1-1"/></svg>';
  return '<svg viewBox="0 0 24 24" fill="none" stroke="#A1A6B7" stroke-width="2.2"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>';
}
function anLogo(conf) {
  if (conf.mono) return '<span class="an-mono" style="background:' + (conf.bg || conf.color) + '">' + conf.mono + '</span>';
  if (conf.icon) return '<span class="an-logo">' + anSvgIcon(conf.icon) + '</span>';
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

// ▲ +300% — процент к прошлому периоду; без базы — абсолютный прирост.
function anDelta(cur, prev) {
  cur = Number(cur || 0); prev = Number(prev || 0);
  var diff = cur - prev;
  if (!diff) return '<div class="an-delta flat">—</div>';
  var text = prev ? Math.round(Math.abs(diff) / prev * 100) + '%' : anNum(Math.abs(diff));
  return '<div class="an-delta ' + (diff > 0 ? 'up' : 'down') + '" title="Было ' + anNum(prev) + '">' + (diff > 0 ? '▲ ' : '▼ ') + text + '</div>';
}
// Изменение доли — в процентных пунктах, а не в процентах от процента.
function anDeltaPts(cur, prev) {
  var diff = cur - prev;
  if (!diff) return '<div class="an-delta flat">—</div>';
  return '<div class="an-delta ' + (diff > 0 ? 'up' : 'down') + '" title="Было ' + prev + '%">' + (diff > 0 ? '▲ ' : '▼ ') + Math.abs(diff) + ' п.п.</div>';
}
function anDayLabel(key, withDow) {
  var p = key.split('-');
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2]));
  var s = d.getUTCDate() + '.' + String(d.getUTCMonth() + 1).padStart(2, '0');
  return withDow ? ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'][d.getUTCDay()] + ', ' + s : s;
}

function anTipShow(html, ev) {
  var t = document.getElementById('an-tip'); if (!t) return;
  t.innerHTML = html; t.style.display = 'block';
  var r = t.getBoundingClientRect();
  var x = ev.clientX + 16, y = ev.clientY + 16;
  if (x + r.width > window.innerWidth - 8) x = ev.clientX - r.width - 16;
  if (y + r.height > window.innerHeight - 8) y = ev.clientY - r.height - 16;
  t.style.left = x + 'px'; t.style.top = y + 'px';
}
function anTipHide() { var t = document.getElementById('an-tip'); if (t) t.style.display = 'none'; }

// Столбцы по дням в реальных пикселях контейнера (шрифт не растягивается).
// bars: [{ date, value, back?, color, tip }] — back рисуется сзади серым.
function anBars(el, bars, height) {
  var W = Math.max(240, el.clientWidth), H = height, padL = 32, padB = 28, padT = 12;
  var plotW = W - padL, plotH = H - padB - padT, n = bars.length;
  var max = Math.max.apply(null, bars.map(function (b) { return Math.max(b.value, b.back || 0); }).concat([1]));
  var raw = max / 3, mag = Math.pow(10, Math.floor(Math.log10(raw)));
  var step = max <= 4 ? 1 : [1, 2, 5, 10].map(function (m) { return m * mag; }).find(function (s) { return s >= raw; });
  var top = Math.ceil(max / step) * step;
  var y = function (v) { return padT + plotH - v / top * plotH; };
  var slot = plotW / n, bw = Math.max(3, Math.min(32, slot - Math.max(2, slot * 0.35)));
  var r = Math.min(6, bw / 2);
  var s = '<svg width="' + W + '" height="' + H + '" role="img">';
  for (var g = 0; g <= top; g += step) {
    s += '<line x1="' + padL + '" x2="' + W + '" y1="' + y(g) + '" y2="' + y(g) + '" stroke="' + AN_C.grid + '"/>';
    s += '<text x="' + (padL - 10) + '" y="' + (y(g) + 4) + '" text-anchor="end" font-size="12" font-weight="600" fill="' + AN_C.muted + '">' + g + '</text>';
  }
  var every = Math.ceil(n / Math.max(2, Math.floor(plotW / 56)));
  function bar(x, v, color) {
    if (!v) return '';
    var top1 = y(v), h = padT + plotH - top1;
    var rr = Math.min(r, h);
    // Скругление только сверху: данные «растут» от оси.
    return '<path fill="' + color + '" d="M' + x + ',' + (padT + plotH) + 'V' + (top1 + rr) + 'Q' + x + ',' + top1 + ' ' + (x + rr) + ',' + top1
      + 'H' + (x + bw - rr) + 'Q' + (x + bw) + ',' + top1 + ' ' + (x + bw) + ',' + (top1 + rr) + 'V' + (padT + plotH) + 'Z"/>';
  }
  bars.forEach(function (b, i) {
    var x = padL + i * slot + (slot - bw) / 2;
    if (b.back) s += bar(x, b.back, AN_C.gray);
    s += bar(x, b.value, b.color);
    // Подписи дат от последнего дня назад с шагом every — последняя всегда
    // видна и не наезжает на соседнюю.
    if ((n - 1 - i) % every === 0) s += '<text x="' + Math.min(W - 18, padL + i * slot + slot / 2) + '" y="' + (H - 8) + '" text-anchor="middle" font-size="12" font-weight="600" fill="' + AN_C.muted + '">' + anDayLabel(b.date) + '</text>';
    s += '<rect data-i="' + i + '" x="' + (padL + i * slot) + '" y="0" width="' + slot + '" height="' + (padT + plotH) + '" fill="transparent"/>';
  });
  el.innerHTML = s + '</svg>';
  el.querySelectorAll('rect[data-i]').forEach(function (hit) {
    hit.addEventListener('mousemove', function (e) { anTipShow(bars[+hit.dataset.i].tip, e); });
    hit.addEventListener('mouseleave', anTipHide);
  });
}

function anKpi(label, value, delta, foot) {
  return '<div class="an-card"><div class="an-label">' + label + '</div><div class="an-big">' + value + '</div>' + (delta || '') + (foot ? '<div class="an-label" style="margin-top:4px">' + foot + '</div>' : '') + '</div>';
}

function renderDashboard(data) {
  if (!document.getElementById('an-kpis')) return;
  window.__anData = data;
  var t = data.totals || {}, p = data.previous || {}, u = data.users || null;
  var tl = data.timeline || [];
  var multi = currentDays > 1;

  // 1. Главные числа
  var k = [anKpi('Установки', anNum(t.installs), anDelta(t.installs, p.installs))];
  if (u) {
    k.push(anKpi('Регистрации', anNum(u.registrations), anDelta(u.registrations, u.previousRegistrations)));
    k.push(anKpi('Активны за 7 дней', anNum(u.active7), '', 'сегодня ' + anNum(u.active1)));
    k.push(anKpi('Premium', anNum(u.premium), '', u.registered ? (u.premium / u.registered * 100).toFixed(1).replace('.0', '') + '% аккаунтов' : ''));
  }
  document.getElementById('an-kpis').innerHTML = k.join('');

  // 2. Установки: столбцы по дням (акцент), неполные дни — серым.
  var chart = document.getElementById('an-installs-chart');
  chart.parentElement.style.display = multi ? '' : 'none';
  chart.closest('.an-main').style.gridTemplateColumns = multi ? '' : '1fr';
  if (multi) {
    anBars(chart, tl.map(function (d) {
      var old = d.date < AN_RELIABLE_FROM;
      var rows = AN_STORE_ORDER.filter(function (s) { return (d.stores || {})[s]; }).map(function (s) {
        return '<div class="an-tip-row"><span>' + s + '</span><b>' + d.stores[s] + '</b></div>';
      }).join('');
      return { date: d.date, value: d.installs, color: old ? AN_C.muted : AN_C.accent,
        tip: '<div class="an-tip-row"><span>' + anDayLabel(d.date, true) + '</span><b>' + anNum(d.installs) + '</b></div>' + rows
          + (old ? '<div class="an-tip-note">неполные данные</div>' : '') };
    }), 260);
  }
  var storeTotals = {};
  tl.forEach(function (d) { Object.keys(d.stores || {}).forEach(function (s) { if (AN_STORES[s]) storeTotals[s] = (storeTotals[s] || 0) + d.stores[s]; }); });
  var prevStores = p.stores || {};
  var names = AN_STORE_ORDER.filter(function (s) { return storeTotals[s] || prevStores[s]; });
  var sum = names.reduce(function (a, s) { return a + (storeTotals[s] || 0); }, 0);
  document.getElementById('an-stores').innerHTML = names.length ? names.map(function (s) {
    var v = storeTotals[s] || 0, conf = AN_STORES[s];
    return '<div class="an-item">' + anLogo(conf)
      + '<div style="min-width:0"><div class="an-item-name">' + s + '</div><div class="an-bar"><div style="width:' + (sum ? v / sum * 100 : 0) + '%;background:' + conf.color + '"></div></div></div>'
      + '<div class="an-item-val">' + anNum(v) + anDelta(v, prevStores[s]) + '</div></div>';
  }).join('') : '<div class="an-empty">Нет установок</div>';

  // 3. Сайт: визиты → переходы в магазин
  var conv = t.views ? Math.round(t.clicks / t.views * 100) : 0;
  var pconv = p.views ? Math.round(p.clicks / p.views * 100) : 0;
  document.getElementById('an-web').innerHTML =
    '<div><div class="an-label">Визиты</div><div class="an-big">' + anNum(t.views) + '</div>' + anDelta(t.views, p.views) + '</div>'
    + '<div><div class="an-label">В магазин</div><div class="an-big" style="color:' + AN_C.accent + '">' + anNum(t.clicks) + '</div>' + anDelta(t.clicks, p.clicks) + '</div>'
    + '<div><div class="an-label">Конверсия</div><div class="an-big">' + conv + '%</div>' + (p.views ? anDeltaPts(conv, pconv) : '') + '</div>';
  var web = document.getElementById('an-web-chart');
  web.style.display = multi ? '' : 'none';
  if (multi) {
    anBars(web, tl.map(function (d) {
      return { date: d.date, value: d.clicks, back: d.views, color: AN_C.accent,
        tip: '<div class="an-tip-row"><span>' + anDayLabel(d.date, true) + '</span></div><div class="an-tip-row"><span>Визиты</span><b>' + anNum(d.views) + '</b></div><div class="an-tip-row"><span>В магазин</span><b>' + anNum(d.clicks) + '</b></div>' };
    }), 180);
  }

  // 4. Источники визитов
  var src = {}, prevSrc = {};
  (data.sources || []).forEach(function (s) { if (!s.views) return; var key = anSourceKey(s.name); src[key] = (src[key] || 0) + s.views; });
  Object.keys(p.sources || {}).forEach(function (name) { var key = anSourceKey(name); prevSrc[key] = (prevSrc[key] || 0) + (p.sources[name].views || 0); });
  var keys = Object.keys(src).sort(function (a, b) { return src[b] - src[a]; });
  var maxSrc = keys.length ? src[keys[0]] : 1;
  document.getElementById('an-sources').innerHTML = keys.length ? keys.slice(0, 7).map(function (key) {
    var conf = AN_SOURCES[key];
    return '<div class="an-item">' + anLogo(conf)
      + '<div style="min-width:0"><div class="an-item-name">' + conf.name + '</div><div class="an-bar"><div style="width:' + (src[key] / maxSrc * 100) + '%;background:' + AN_C.accent + '"></div></div></div>'
      + '<div class="an-item-val">' + anNum(src[key]) + anDelta(src[key], prevSrc[key]) + '</div></div>';
  }).join('') : '<div class="an-empty">Нет визитов</div>';

  // 5. Страны — только когда выбраны все проекты.
  var apps = data.apps || {}, byApp = (u && u.byApp) || {};
  var codes = ['ru', 'by', 'rs'].filter(function (c) { return apps[c] || byApp[c]; });
  document.getElementById('an-apps-card').style.display = currentApp === 'all' && codes.length ? '' : 'none';
  document.getElementById('an-apps').innerHTML = codes.map(function (c) {
    var a = apps[c] || {}, b = byApp[c] || {};
    return '<div><div class="an-label">' + AN_APPS[c] + '</div><div class="an-big" style="font-size:28px;line-height:34px;margin-top:4px">' + anNum(a.installs) + '</div>'
      + '<div class="an-label" style="margin-top:4px">' + anPlural(a.installs, 'установка', 'установки', 'установок') + ' · ' + anNum(b.registered) + ' ' + anPlural(b.registered, 'аккаунт', 'аккаунта', 'аккаунтов') + '</div></div>';
  }).join('');
}

window.addEventListener('resize', function () {
  clearTimeout(window.__anResize);
  window.__anResize = setTimeout(function () { if (window.__anData && currentFeature === 'analytics') renderDashboard(window.__anData); }, 150);
});
`;

export const ANALYTICS_CLIENT_JS = 'var AN_BRAND_PATHS = ' + JSON.stringify(BRAND_ICON_PATHS) + ';\n' + CLIENT;
