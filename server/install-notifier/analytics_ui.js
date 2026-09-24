// Раздел «Аналитика» админки: заменяет старую разметку и скрипт из
// экранированной строки worker.js. Данные — /api/admin/stats (события по
// дням + сводка профилей). Графики — свой SVG в реальных пикселях.
//
// Стиль — токены приложения (AppColors / AppDimensions): акцент #0574F8,
// рост #2BC280, падение #ED4621, текст #121212 / #A1A6B7, серый #EFF0F4,
// скругления 16 (карточка) и 12 (внутри). Три размера текста: 13 — подписи,
// 15 — заголовки и значения списков, 32 — главные числа. Без прозрачности.
//
// Клиентский код — String.raw без обратных кавычек и ${ внутри.

import { BRAND_ICON_PATHS } from './brand_icons.js';

export const ANALYTICS_VIEW_HTML = String.raw`
    <!-- 1. ANALYTICS VIEW -->
    <div id="analytics-view">
      <style>
        #analytics-view { --an-accent:#0574F8; --an-green:#2BC280; --an-red:#ED4621; --an-text:#121212; --an-muted:#A1A6B7; --an-axis:#7C8190; --an-gray:#EFF0F4; }
        .an-card { background:#fff; border-radius:16px; padding:24px; min-width:0; margin-bottom:16px; }
        .an-title { font-size:15px; font-weight:800; line-height:20px; color:var(--an-text); margin-bottom:24px; }
        .an-label { font-size:13px; font-weight:600; line-height:18px; color:var(--an-muted); }
        .an-big { font-size:32px; font-weight:800; letter-spacing:-1px; line-height:40px; color:var(--an-text); font-variant-numeric:tabular-nums; margin-top:4px; }
        .an-delta { font-size:13px; font-weight:700; line-height:18px; min-height:18px; margin-top:4px; font-variant-numeric:tabular-nums; white-space:nowrap; color:var(--an-muted); }
        .an-delta.up { color:var(--an-green); }
        .an-delta.down { color:var(--an-red); }
        .an-funnel { display:grid; grid-template-columns:1fr 1fr 1fr 1fr; }
        .an-step { position:relative; padding-right:16px; }
        .an-step + .an-step { padding-left:24px; border-left:1px solid var(--an-gray); }
        .an-rate { display:inline-block; margin-top:12px; font-size:13px; font-weight:700; line-height:18px; color:var(--an-accent); background:#E8F2FE; border-radius:8px; padding:2px 8px; }
        .an-row2 { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr); gap:16px; align-items:start; }
        .an-row2 > .an-card { margin-bottom:16px; }
        .an-chart { position:relative; width:100%; }
        .an-chart svg { display:block; }
        .an-caption { font-size:13px; font-weight:600; line-height:18px; color:var(--an-muted); margin-top:12px; }
        .an-list { display:flex; flex-direction:column; gap:16px; }
        .an-item { display:grid; grid-template-columns:32px minmax(0,1fr) 64px; gap:12px; align-items:center; }
        .an-item-name { font-size:15px; font-weight:700; line-height:20px; color:var(--an-text); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .an-item-name span { color:var(--an-muted); font-weight:600; font-size:13px; }
        .an-item-val { font-size:15px; font-weight:800; line-height:20px; color:var(--an-text); text-align:right; font-variant-numeric:tabular-nums; }
        .an-item-val .an-delta { margin-top:0; min-height:0; text-align:right; }
        .an-bar { height:6px; border-radius:3px; background:var(--an-gray); margin-top:6px; overflow:hidden; }
        .an-bar > div { height:100%; border-radius:3px; }
        .an-logo { width:32px; height:32px; border-radius:12px; background:var(--an-gray); display:flex; align-items:center; justify-content:center; }
        .an-logo svg { width:18px; height:18px; display:block; }
        .an-mono { width:32px; height:32px; border-radius:12px; display:flex; align-items:center; justify-content:center; color:#fff; font-size:15px; font-weight:800; }
        .an-now { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:16px; }
        .an-empty { font-size:15px; font-weight:700; color:var(--an-muted); padding:32px 0; text-align:center; }
        .an-tip { position:fixed; z-index:9999; pointer-events:none; background:#121212; color:#fff; border-radius:12px; padding:12px; font-size:13px; line-height:20px; display:none; min-width:140px; }
        .an-tip-row { display:flex; justify-content:space-between; gap:16px; }
        .an-tip-row b { font-weight:800; }
        .an-tip-note { color:#A1A6B7; }
        @media (max-width:900px) { .an-row2 { grid-template-columns:1fr; } }
        @media (max-width:640px) {
          .an-card { padding:16px; }
          .an-funnel { grid-template-columns:1fr 1fr; row-gap:16px; }
          .an-step:nth-child(3) { padding-left:0; border-left:none; }
          .an-big { font-size:24px; line-height:32px; }
          .an-now { grid-template-columns:1fr 1fr; }
        }
      </style>
      <div class="an-card"><div class="an-funnel" id="an-funnel"></div></div>
      <div class="an-card">
        <div class="an-title" id="an-installs-title">Установки</div>
        <div class="an-chart" id="an-installs-chart"></div>
        <div class="an-caption" id="an-installs-caption"></div>
      </div>
      <div class="an-row2">
        <div class="an-card"><div class="an-title">Откуда приходят на сайт</div><div class="an-list" id="an-sources"></div></div>
        <div>
          <div class="an-card"><div class="an-title">Где устанавливают</div><div class="an-list" id="an-stores"></div></div>
          <div class="an-card" id="an-apps-card"><div class="an-title">Страны</div><div class="an-list" id="an-apps"></div></div>
        </div>
      </div>
      <div class="an-card"><div class="an-title">Сейчас</div><div class="an-now" id="an-now"></div></div>
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

// Изменение к прошлому периоду. Процент — только на базе от 10: иначе
// «▲2033%» при росте с 3 до 64 кричит громче, чем значит. Нет базы или
// сравнение нечестное (неполные дни, незаконченный сегодняшний день) — пусто.
function anDelta(cur, prev, ok) {
  if (ok === false) return '<div class="an-delta"></div>';
  cur = Number(cur || 0); prev = Number(prev || 0);
  if (!prev) return '<div class="an-delta"></div>';
  var diff = cur - prev;
  if (!diff) return '<div class="an-delta">без изменений</div>';
  var small = prev < 10 || cur < 10;
  var pct = prev ? Math.round(Math.abs(diff) / prev * 100) : 0;
  var text = small || pct > 999 ? (diff > 0 ? '+' : '−') + anNum(Math.abs(diff)) : pct + '%';
  return '<div class="an-delta ' + (small ? '' : diff > 0 ? 'up' : 'down') + '" title="Было ' + anNum(prev) + '">' + (small ? '' : diff > 0 ? '▲ ' : '▼ ') + text + '</div>';
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
  t.style.left = Math.max(8, x) + 'px'; t.style.top = Math.max(8, y) + 'px';
}
function anTipHide() { var t = document.getElementById('an-tip'); if (t) t.style.display = 'none'; }
document.addEventListener('pointerdown', function (e) { if (!e.target.closest('rect[data-i]')) anTipHide(); });

// Столбцы в реальных пикселях контейнера. На оси Y — только 0 и максимум.
function anBars(el, bars, height) {
  var W = Math.max(240, el.clientWidth), H = height, padL = 32, padB = 28, padT = 12;
  var plotW = W - padL, plotH = H - padB - padT, n = bars.length;
  var max = Math.max.apply(null, bars.map(function (b) { return b.value; }).concat([1]));
  var y = function (v) { return padT + plotH - v / max * plotH; };
  var slot = plotW / n, bw = Math.max(3, Math.min(40, slot - Math.max(2, slot * 0.3)));
  var r = Math.min(6, bw / 2);
  var s = '<svg width="' + W + '" height="' + H + '" role="img">';
  [0, max].forEach(function (g) {
    s += '<line x1="' + padL + '" x2="' + W + '" y1="' + y(g) + '" y2="' + y(g) + '" stroke="#EFF0F4"/>';
    s += '<text x="' + (padL - 10) + '" y="' + (y(g) + 4) + '" text-anchor="end" font-size="13" font-weight="600" fill="#7C8190">' + anNum(g) + '</text>';
  });
  var every = Math.ceil(n / Math.max(2, Math.floor(plotW / 64)));
  bars.forEach(function (b, i) {
    var x = padL + i * slot + (slot - bw) / 2;
    if (b.value) {
      var top1 = y(b.value), h = padT + plotH - top1, rr = Math.min(r, h);
      s += '<path fill="' + b.color + '" d="M' + x + ',' + (padT + plotH) + 'V' + (top1 + rr) + 'Q' + x + ',' + top1 + ' ' + (x + rr) + ',' + top1
        + 'H' + (x + bw - rr) + 'Q' + (x + bw) + ',' + top1 + ' ' + (x + bw) + ',' + (top1 + rr) + 'V' + (padT + plotH) + 'Z"/>';
    }
    if ((n - 1 - i) % every === 0) s += '<text x="' + Math.min(W - 20, padL + i * slot + slot / 2) + '" y="' + (H - 6) + '" text-anchor="middle" font-size="13" font-weight="600" fill="#7C8190">' + b.label + '</text>';
    s += '<rect data-i="' + i + '" x="' + (padL + i * slot) + '" y="0" width="' + slot + '" height="' + (padT + plotH) + '" fill="transparent"/>';
  });
  el.innerHTML = s + '</svg>';
  el.querySelectorAll('rect[data-i]').forEach(function (hit) {
    var show = function (e) { anTipShow(bars[+hit.dataset.i].tip, e); };
    hit.addEventListener('mousemove', show);
    hit.addEventListener('pointerdown', show);
    hit.addEventListener('mouseleave', anTipHide);
  });
}

// 90 дней — по неделям (от сегодняшнего дня назад), иначе по дням.
function anBuckets(tl) {
  if (tl.length <= 31) return tl.map(function (d) { return { from: d.date, to: d.date, days: [d] }; });
  var out = [];
  for (var end = tl.length; end > 0; end -= 7) {
    var chunk = tl.slice(Math.max(0, end - 7), end);
    out.unshift({ from: chunk[0].date, to: chunk[chunk.length - 1].date, days: chunk });
  }
  return out;
}
function anSum(days, fn) { return days.reduce(function (a, d) { return a + (fn(d) || 0); }, 0); }

function anShareList(items, total, color) {
  return items.map(function (it) {
    var share = total ? Math.round(it.value / total * 100) : 0;
    return '<div class="an-item">' + anLogo(it.conf)
      + '<div style="min-width:0"><div class="an-item-name">' + anEsc(it.name) + (it.extra ? ' <span>' + it.extra + '</span>' : '') + '</div><div class="an-bar"><div style="width:' + share + '%;background:' + (it.color || color) + '"></div></div></div>'
      + '<div class="an-item-val">' + anNum(it.value) + '<div class="an-delta" style="margin:0">' + share + '%</div></div></div>';
  }).join('');
}

function renderDashboard(data) {
  if (!document.getElementById('an-funnel')) return;
  window.__anData = data;
  var t = data.totals || {}, p = data.previous || {}, u = data.users || null;
  var tl = data.timeline || [];
  var today = currentDays === 1;
  // Честное сравнение: не для незаконченного сегодня и не с днями, когда
  // установки терялись (прошлый период целиком должен быть после AN_RELIABLE_FROM).
  var firstPrevDay = (function () { var d = new Date(); d.setDate(d.getDate() - currentDays * 2 + 1); return d.toISOString().slice(0, 10); })();
  var cmp = !today;
  var cmpInstalls = cmp && firstPrevDay >= AN_RELIABLE_FROM;

  // 1. Воронка за период
  var steps = [
    ['Визиты сайта', t.views, p.views, cmp],
    ['Перешли в магазин', t.clicks, p.clicks, cmp, 'посетителей'],
    ['Установки', t.installs, p.installs, cmpInstalls],
    ['Регистрации', u ? u.registrations : 0, u ? u.previousRegistrations : 0, cmp, 'установивших']
  ];
  document.getElementById('an-funnel').innerHTML = steps.map(function (st, i) {
    var rate = '';
    // Доля перехода — только там, где шаг действительно вытекает из
    // предыдущего: установки идут и мимо сайта, поэтому им доли нет.
    if (st[4] && steps[i - 1][1]) rate = '<div class="an-rate">' + Math.round(st[1] / steps[i - 1][1] * 100) + '% ' + st[4] + '</div>';
    return '<div class="an-step"><div class="an-label">' + st[0] + '</div><div class="an-big"' + (i === 2 ? ' style="color:#0574F8"' : '') + '>' + anNum(st[1]) + '</div>'
      + anDelta(st[1], st[2], st[3]) + rate + '</div>';
  }).join('');

  // 2. Установки по дням / неделям
  var chartCard = document.getElementById('an-installs-chart').parentElement;
  chartCard.style.display = today ? 'none' : '';
  if (!today) {
    var buckets = anBuckets(tl);
    var weekly = buckets.length && buckets[0].days.length > 1;
    document.getElementById('an-installs-title').textContent = weekly ? 'Установки по неделям' : 'Установки по дням';
    var anyOld = false;
    anBars(document.getElementById('an-installs-chart'), buckets.map(function (bk) {
      var v = anSum(bk.days, function (d) { return d.installs; });
      var old = bk.from < AN_RELIABLE_FROM;
      if (old) anyOld = true;
      var stores = {};
      bk.days.forEach(function (d) { Object.keys(d.stores || {}).forEach(function (s) { if (AN_STORES[s]) stores[s] = (stores[s] || 0) + d.stores[s]; }); });
      var head = weekly ? anDayLabel(bk.from) + '–' + anDayLabel(bk.to) : anDayLabel(bk.from, true);
      return { value: v, color: old ? '#A1A6B7' : '#0574F8', label: anDayLabel(weekly ? bk.to : bk.from),
        tip: '<div class="an-tip-row"><span>' + head + '</span><b>' + anNum(v) + '</b></div>'
          + AN_STORE_ORDER.filter(function (s) { return stores[s]; }).map(function (s) { return '<div class="an-tip-row"><span>' + s + '</span><b>' + stores[s] + '</b></div>'; }).join('')
          + (old ? '<div class="an-tip-note">неполные данные</div>' : '') };
    }), 240);
    document.getElementById('an-installs-caption').textContent = anyOld ? 'Серым — дни до ' + anDayLabel(AN_RELIABLE_FROM) + ': часть установок тогда не записалась' : '';
    if (!t.installs) document.getElementById('an-installs-chart').innerHTML = '<div class="an-empty">Пока нет установок за период</div>';
  }

  // 3. Источники: визиты, доля от всех визитов, сколько ушли в магазин
  var src = {};
  (data.sources || []).forEach(function (s) {
    if (!s.views && !s.clicks) return;
    var key = anSourceKey(s.name);
    if (!src[key]) src[key] = { views: 0, clicks: 0 };
    src[key].views += s.views || 0; src[key].clicks += s.clicks || 0;
  });
  var keys = Object.keys(src).sort(function (a, b) { return src[b].views - src[a].views; });
  var totalViews = keys.reduce(function (a, k) { return a + src[k].views; }, 0);
  var shown = keys.slice(0, 6), rest = keys.slice(6);
  var items = shown.map(function (k) { return { conf: AN_SOURCES[k], name: AN_SOURCES[k].name, value: src[k].views, extra: src[k].clicks ? '→ ' + anNum(src[k].clicks) + ' в магазин' : '' }; });
  if (rest.length) {
    var rv = rest.reduce(function (a, k) { return a + src[k].views; }, 0), rc = rest.reduce(function (a, k) { return a + src[k].clicks; }, 0);
    items.push({ conf: AN_SOURCES.other, name: 'Остальные', value: rv, extra: rc ? '→ ' + anNum(rc) + ' в магазин' : '' });
  }
  document.getElementById('an-sources').innerHTML = items.length ? anShareList(items, totalViews, '#0574F8') : '<div class="an-empty">Нет визитов</div>';

  // 4. Магазины и страны — доля от всех установок
  var storeTotals = {};
  tl.forEach(function (d) { Object.keys(d.stores || {}).forEach(function (s) { if (AN_STORES[s]) storeTotals[s] = (storeTotals[s] || 0) + d.stores[s]; }); });
  var storeNames = AN_STORE_ORDER.filter(function (s) { return storeTotals[s]; });
  var storeSum = storeNames.reduce(function (a, s) { return a + storeTotals[s]; }, 0);
  document.getElementById('an-stores').innerHTML = storeNames.length
    ? anShareList(storeNames.map(function (s) { return { conf: AN_STORES[s], name: s, value: storeTotals[s], color: AN_STORES[s].color }; }), storeSum)
    : '<div class="an-empty">Нет установок</div>';
  var apps = data.apps || {};
  var codes = ['ru', 'by', 'rs'].filter(function (c) { return (apps[c] || {}).installs; });
  var appSum = codes.reduce(function (a, c) { return a + apps[c].installs; }, 0);
  document.getElementById('an-apps-card').style.display = currentApp === 'all' && codes.length > 1 ? '' : 'none';
  document.getElementById('an-apps').innerHTML = anShareList(codes.map(function (c) {
    return { conf: { mono: c.toUpperCase(), bg: '#121212' }, name: AN_APPS[c], value: apps[c].installs };
  }), appSum, '#0574F8');

  // 5. Сейчас — не зависит от выбранного периода
  document.getElementById('an-now').innerHTML = u ? [
    ['Заходили сегодня', anNum(u.active1)],
    ['Заходили за 7 дней', anNum(u.active7)],
    ['Premium', anNum(u.premium) + '<span style="font-size:15px;color:#A1A6B7;letter-spacing:0"> из ' + anNum(u.registered) + '</span>']
  ].map(function (x) { return '<div><div class="an-label">' + x[0] + '</div><div class="an-big">' + x[1] + '</div></div>'; }).join('') : '';
}

window.addEventListener('resize', function () {
  clearTimeout(window.__anResize);
  window.__anResize = setTimeout(function () { if (window.__anData && currentFeature === 'analytics') renderDashboard(window.__anData); }, 150);
});
`;

export const ANALYTICS_CLIENT_JS = 'var AN_BRAND_PATHS = ' + JSON.stringify(BRAND_ICON_PATHS) + ';\n' + CLIENT;
