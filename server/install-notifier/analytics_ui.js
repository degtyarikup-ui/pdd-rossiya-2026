// Раздел «Аналитика» админки: заменяет старую разметку и скрипт из
// экранированной строки worker.js. Данные — /api/admin/stats (события по
// дням + сводка профилей). Графики — свой SVG в реальных пикселях.
//
// Визуальная система админки: спокойный фон, белые поверхности без рамок,
// крупные числа, синий акцент и компактные подписи.
//
// Клиентский код — String.raw без обратных кавычек и ${ внутри.

import { BRAND_ICON_PATHS } from './brand_icons.js';
import { selectGeoRows } from './analytics_geo.js';

export const ANALYTICS_VIEW_HTML = String.raw`
<div id="analytics-view">
<style>
#analytics-view{--an-accent:#0574F8;--an-green:#22a875;--an-text:#17191E;--an-muted:#747B88;--an-gray:#F4F5F7;color:var(--an-text)}
.an-card{background:#fff;border:0;border-radius:20px;padding:24px;min-width:0;margin-bottom:18px;box-shadow:none}
.an-head{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:20px}
.an-title{font-size:16px;font-weight:650;color:var(--an-text);margin:0;letter-spacing:-.35px}
.an-period{font-size:12px;color:var(--an-muted);line-height:1.6;margin-bottom:16px}.an-period b{color:var(--an-text);font-weight:500}
.an-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin:0 0 18px}
.an-kpi{margin:0;padding:24px}.an-big{font-size:38px;line-height:1.1;letter-spacing:-1.8px;font-weight:550;font-variant-numeric:tabular-nums;margin:16px 0 0}
.an-kpi-top{display:flex;align-items:center;gap:8px;font-size:12px;font-weight:500;color:var(--an-muted)}.an-kpi-top .an-dot{display:none}.an-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.an-kpi.is-primary{background:var(--an-accent);color:white}.an-kpi.is-primary .an-kpi-top{color:#d4e8ff}
.an-charts-grid{display:grid;grid-template-columns:1.05fr 1fr;gap:18px;align-items:start}.an-charts-grid>.an-card{height:100%;margin:0}.an-charts-grid{margin-bottom:18px}
.an-row2{display:grid;grid-template-columns:1fr .85fr 1.35fr;gap:18px;align-items:start}
.an-chart{width:100%;min-height:190px;overflow:hidden}.an-chart svg{display:block;max-width:100%}
.an-legend{display:flex;gap:16px;align-items:center;font-size:11px;color:var(--an-muted);margin-bottom:8px}.an-legend span{display:flex;align-items:center;gap:6px}
.an-caption{font-size:11px;line-height:1.6;color:var(--an-muted);margin-top:12px}.an-caption:empty{display:none}
.an-tabs{display:flex;gap:3px;padding:4px;background:#F4F5F7;border-radius:999px;flex-wrap:wrap;width:fit-content;max-width:100%}
.an-tabs button{border:0;background:transparent;color:var(--an-muted);padding:7px 12px;border-radius:999px;font-size:11px;font-weight:550;cursor:pointer;min-height:30px}
.an-tabs button.active{background:var(--an-text);color:#fff;box-shadow:none}
.an-table-wrap{overflow:auto}.an-table{width:100%;border-collapse:collapse;font-size:12px;line-height:1.5}
.an-table th{font-size:10px;letter-spacing:0;color:var(--an-muted);font-weight:500;text-align:right;padding:0 0 12px;white-space:nowrap;text-transform:none}
.an-table td{padding:14px 0;border-top:1px solid #F2F3F5;text-align:right;font-variant-numeric:tabular-nums;font-weight:550}
.an-table th:first-child,.an-table td:first-child{text-align:left}.an-table td+td,.an-table th+th{padding-left:12px}
.an-table-name{display:flex;align-items:center;gap:10px;font-weight:550}
.an-logo,.an-mono{width:28px;height:28px;border-radius:9px;background:#F4F5F7;display:flex;align-items:center;justify-content:center;flex-shrink:0}.an-logo svg{width:16px;height:16px}.an-mono{color:#fff;font-size:12px;font-weight:600}
.an-empty{padding:36px 12px;text-align:center;font-size:12px;color:var(--an-muted);line-height:1.7}
.an-geo-tools{display:flex;gap:8px;align-items:center;margin:18px 0;flex-wrap:nowrap}
.an-search{border:0;border-radius:10px;padding:10px 12px;font-size:12px;background:#F4F5F7;min-width:0;flex:1;outline-color:var(--an-accent);min-height:38px;color:var(--an-text)}.an-geo-tools select{flex:0 1 160px}.an-geo-tools select[hidden]{display:none}
.an-clear{border:0;background:#F4F5F7;width:36px;height:38px;border-radius:10px;color:var(--an-muted);font-size:20px;flex-shrink:0;cursor:pointer}.an-clear[hidden]{display:none}
.an-geo-card .an-table td{padding:12px 0}.an-geo-card .an-table-name{display:flex;align-items:center;gap:8px}.an-flag{font-size:18px;line-height:1;width:22px;flex:0 0 22px;text-align:center}.an-geo-card .an-table td:nth-child(2){font-weight:600}.an-geo-card .an-table td:nth-child(4),.an-geo-card .an-table td:nth-child(5){color:var(--an-muted);font-weight:450}.an-share{display:inline-flex;flex-direction:column;align-items:flex-end;gap:5px}.an-share-track{width:36px;height:3px;background:#F0F2F5;border-radius:3px;overflow:hidden}.an-share-track i{display:block;height:100%;background:var(--an-accent);border-radius:3px}
.an-sort{font:inherit;letter-spacing:inherit;color:inherit;padding:0;border:0;background:none;cursor:pointer;text-transform:inherit;white-space:nowrap}.an-sort.is-sorted{color:var(--an-text)}
.an-geo-footer{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:16px;font-size:10px;color:var(--an-muted);min-height:30px}
.an-pagination{display:flex;align-items:center;gap:8px;white-space:nowrap}.an-pagination button{border:0;background:#F4F5F7;border-radius:50%;width:30px;height:30px;cursor:pointer;font-size:16px;color:var(--an-text)}.an-pagination button:disabled{opacity:.3;cursor:default}
.an-help{position:relative;font-size:12px;line-height:1.65;text-align:left;color:var(--an-muted);flex-shrink:0}.an-help summary{list-style:none;cursor:pointer;width:24px;height:24px;display:flex;align-items:center;justify-content:center;border:0;background:#F4F5F7;border-radius:50%;font-size:11px;color:var(--an-muted);font-weight:500}.an-help summary::-webkit-details-marker{display:none}.an-help[open] summary{color:white;background:var(--an-text)}.an-help>div{position:absolute;right:0;top:32px;width:280px;max-width:75vw;z-index:30;padding:16px 18px;background:var(--an-text);color:white;border:0;border-radius:16px;box-shadow:0 12px 40px #17191e25}
.an-audience{display:flex;justify-content:space-between;gap:16px;padding:0 2px 12px;flex-wrap:wrap;font-size:11px;color:var(--an-muted)}.an-audience b{color:var(--an-text);margin-left:6px;font-size:14px;font-weight:600;font-variant-numeric:tabular-nums}
.an-activity-summary{display:grid;grid-template-columns:1.3fr repeat(3,1fr);gap:16px;align-items:end;margin:4px 0 24px}.an-activity-summary span{display:flex;flex-direction:column;gap:10px;font-size:11px;color:var(--an-muted)}.an-activity-summary b{color:var(--an-text);font-size:21px;font-weight:550;line-height:1;letter-spacing:-.6px;font-variant-numeric:tabular-nums}.an-activity-summary span:first-child b{font-size:40px;letter-spacing:-1.8px;color:var(--an-accent)}
.an-activity-card .an-head{margin-bottom:24px}.an-chart-card .an-head{margin-bottom:24px}.an-dynamics-summary{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px;margin:4px 0 24px}.an-dynamics-summary span{display:flex;flex-direction:column;gap:10px;font-size:11px;color:var(--an-muted)}.an-dynamics-summary b{color:var(--an-text);font-size:40px;font-weight:550;line-height:1;letter-spacing:-1.8px;font-variant-numeric:tabular-nums}
.an-day-details{margin-top:16px}.an-day-details>summary{display:flex;align-items:center;justify-content:space-between;font-size:11px;color:var(--an-text);cursor:pointer;list-style:none;padding-top:14px;border-top:1px solid #F2F3F5}.an-day-details>summary::-webkit-details-marker{display:none}.an-day-details>summary:after{content:'+';font-size:18px;color:var(--an-muted)}.an-day-details[open]>summary:after{content:'−'}.an-day-details .an-table-wrap{max-height:320px;margin-top:18px}
.an-now{background:#fff;border-radius:20px;padding:20px 24px;margin-top:0;margin-bottom:18px;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:20px}.an-now span{display:flex;align-items:center;justify-content:space-between;gap:8px}.an-now b{font-size:18px;letter-spacing:-.3px;margin:0}
.an-tip{position:fixed;z-index:9999;pointer-events:none;background:#17191E;color:white;border-radius:14px;padding:14px 16px;font-size:12px;line-height:1.8;display:none;min-width:140px}.an-tip-row{display:flex;justify-content:space-between;gap:24px}.an-tip-note{color:#b8c4d8}
#analytics-view button:focus-visible,#analytics-view summary:focus-visible,#analytics-view input:focus-visible,#analytics-view select:focus-visible{outline:2px solid var(--an-accent);outline-offset:3px}
@media(max-width:1320px){.an-row2{grid-template-columns:1fr 1fr}.an-geo-card{grid-column:1 / -1}.an-geo-card .an-table-name{min-width:150px}}
@media(max-width:1120px){.an-charts-grid{grid-template-columns:1fr}.an-chart-card .an-legend{margin:0 0 8px}.an-grid{gap:12px}.an-kpi{padding:20px}.an-big{font-size:34px}}
@media(max-width:900px){.an-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.an-now{grid-template-columns:repeat(2,minmax(0,1fr))}.an-now span{justify-content:flex-start}.an-now b{margin-left:auto}}
@media(max-width:640px){.an-card{padding:20px;border-radius:18px}.an-grid{gap:10px}.an-kpi{padding:18px}.an-kpi-top{font-size:11px;min-height:28px;line-height:1.4}.an-big{font-size:32px;margin-top:10px}.an-row2{grid-template-columns:1fr}.an-geo-card{grid-column:auto}.an-head{gap:8px}.an-title{font-size:15px}.an-tabs button{padding:6px 10px;font-size:10px}.an-table{font-size:12px}.an-table td+td,.an-table th+th{padding-left:10px}.an-geo-card .an-table{min-width:340px}.an-activity-summary{gap:14px 10px;grid-template-columns:1.1fr repeat(3,1fr)}.an-activity-summary b{font-size:18px}.an-activity-summary span:first-child b{font-size:34px}.an-activity-summary span{font-size:10px;line-height:1.4}.an-dynamics-summary b{font-size:34px}.an-dynamics-summary span{font-size:10px}.an-geo-footer{flex-wrap:wrap}.an-now{padding:18px 20px;gap:16px}.an-now span{flex-direction:column;align-items:flex-start;gap:8px}.an-now b{margin:0;font-size:20px}.an-chart-card .an-head{flex-wrap:wrap}.an-caption{font-size:10px}}
</style>
<div class="an-period" id="an-period"></div>
<div class="an-grid" id="an-kpis"></div>
<div class="an-charts-grid">
 <div class="an-card an-activity-card">
  <div class="an-head"><div class="an-title">Ежедневное использование</div><details class="an-help"><summary aria-label="Об активности">i</summary><div>Уникальные зарегистрированные аккаунты, обращавшиеся к серверу за день по МСК. Повторные обращения не увеличивают число. Аккаунт с двумя платформами входит в обе группы, в общем числе учитывается один раз. Гости и использование без интернета сюда не входят. Сегодня — неполный день, среднее включает сегодня.</div></details></div>
  <div class="an-activity-summary" id="an-activity-summary"></div>
  <div class="an-legend"><span><i class="an-dot" style="background:#0574F8"></i>Android</span><span><i class="an-dot" style="background:#22a875"></i>iOS</span></div>
  <div class="an-chart" id="an-activity-chart"></div>
  <div class="an-caption" id="an-activity-caption"></div>
  <details class="an-day-details"><summary>Данные по дням</summary><div class="an-table-wrap" id="an-activity-table"></div></details>
 </div>
 <div class="an-card an-chart-card">
  <div class="an-head"><div class="an-title">Динамика</div><div class="an-tabs" id="an-chart-tabs"><button type="button" data-chart="app" class="active" aria-pressed="true">Приложение</button><button type="button" data-chart="site" aria-pressed="false">Сайт</button></div></div>
  <div class="an-dynamics-summary" id="an-dynamics-summary"></div>
  <div class="an-legend" id="an-chart-legend"></div><div class="an-chart" id="an-installs-chart"></div><div class="an-caption" id="an-installs-caption"></div>
 </div>
</div>
<div class="an-row2">
  <div class="an-card"><div class="an-head"><div class="an-title">Источники сайта</div><details class="an-help"><summary aria-label="Об источниках сайта">i</summary><div>Просмотры и нажатия на ссылки магазинов. Метка сайта не подтверждает источник установки.</div></details></div><div class="an-table-wrap" id="an-sources"></div></div>
  <div class="an-card"><div class="an-head"><div class="an-title">Магазины</div><details class="an-help"><summary aria-label="Об установках">i</summary><div>Первые запуски приложения. Скачивания из консолей магазинов сюда не поступают.</div></details></div><div class="an-table-wrap" id="an-stores"></div></div>
 <div class="an-card an-geo-card">
  <div class="an-head"><div class="an-title">География</div><details class="an-help"><summary aria-label="О географии">i</summary><div>Новые аккаунты выбранного периода, по последнему сохранённому IP. VPN может менять географию. Активность и Premium показывают текущее состояние этих аккаунтов.</div></details></div>
  <div class="an-tabs" id="an-geo-tabs"><button type="button" data-geo="countries" class="active" aria-pressed="true">Страны</button><button type="button" data-geo="regions" aria-pressed="false">Регионы</button><button type="button" data-geo="cities" aria-pressed="false">Города</button></div>
  <div class="an-geo-tools"><input class="an-search" id="an-geo-search" placeholder="Поиск" aria-label="Поиск по географии"><select class="an-search" id="an-geo-country" aria-label="Страна географии"><option value="all">Все страны</option></select><button type="button" class="an-clear" id="an-geo-reset" title="Сбросить поиск и страну" aria-label="Сбросить фильтры">×</button></div>
  <div class="an-table-wrap" id="an-geo"></div>
  <div class="an-geo-footer"><span id="an-geo-coverage"></span><div class="an-pagination" id="an-geo-pages"></div></div>
 </div>
</div>
<div class="an-audience an-now" id="an-now"></div>
<div class="an-tip" id="an-tip"></div>
</div>
`;

const CLIENT = String.raw`
// ────────────────────── Analytics (analytics_ui.js) ──────────────────────
var AN_RELIABLE_FROM = '2026-09-25';
var AN_C = { accent: '#0574F8', green: '#22a875', red: '#ED4621', text: '#17191E', muted: '#747B88', gray: '#F4F5F7', grid: '#F2F3F5' };
// Магазины — цвета их логотипов.
var AN_STORES = {
  'Google Play': { color: '#01875F', icon: 'googleplay' },
  'RuStore': { color: '#0077FF', mono: 'R' },
  'App Store': { color: '#0D96F6', icon: 'appstore' },
  'TestFlight': { color: '#0D96F6', icon: 'appstore' }
};
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
  direct: { name: 'Прямые / без метки', glyph: 'link' },
  other: { name: 'Другие сайты', glyph: 'globe' }
};
var AN_ICON_COLORS = { googleplay: '#01875F', appstore: '#0D96F6', instagram: '#FF0069', youtube: '#FF0000', telegram: '#26A5E4', vk: '#0077FF', tiktok: '#000000', threads: '#000000', google: '#4285F4' };

function anEsc(v) { return typeof adminEsc === 'function' ? adminEsc(v) : String(v == null ? '' : v); }
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
  var W = Math.max(240, el.clientWidth), H = height, padL = 54, padB = 28, padT = 12;
  var plotW = W - padL, plotH = H - padB - padT, n = bars.length;
  var max = Math.max.apply(null, bars.map(function (b) { return b.value; }).concat([1]));
  var y = function (v) { return padT + plotH - v / max * plotH; };
  var slot = plotW / n, bw = Math.max(3, Math.min(40, slot - Math.max(2, slot * 0.3)));
  var r = Math.min(6, bw / 2);
  var s = '<svg width="' + W + '" height="' + H + '" role="img">';
  [0, max].forEach(function (g) {
    s += '<line x1="' + padL + '" x2="' + W + '" y1="' + y(g) + '" y2="' + y(g) + '" stroke="#EFF0F4"/>';
    s += '<text x="' + (padL - 10) + '" y="' + (y(g) + 4) + '" text-anchor="end" font-size="11" font-weight="500" fill="#747B88">' + anNum(g) + '</text>';
  });
  var every = 2 * Math.ceil((n / 2) / Math.max(2, Math.floor(plotW / 70)));
  bars.forEach(function (b, i) {
    var x = padL + Math.floor(i / 2) * slot * 2 + slot + (i % 2 ? 3 : -bw - 3);
    if (b.value) {
      var top1 = y(b.value), h = padT + plotH - top1, rr = Math.min(r, h);
      s += '<path fill="' + b.color + '" d="M' + x + ',' + (padT + plotH) + 'V' + (top1 + rr) + 'Q' + x + ',' + top1 + ' ' + (x + rr) + ',' + top1
        + 'H' + (x + bw - rr) + 'Q' + (x + bw) + ',' + top1 + ' ' + (x + bw) + ',' + (top1 + rr) + 'V' + (padT + plotH) + 'Z"/>';
    }
    if (b.label && (n - 2 - i) % every === 0) s += '<text x="' + Math.min(W - 20, padL + Math.floor(i / 2) * slot * 2 + slot) + '" y="' + (H - 6) + '" text-anchor="middle" font-size="11" font-weight="500" fill="#747B88">' + b.label + '</text>';
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

var anChartMode = 'app', anGeoMode = 'countries', anGeoPage = 0, anGeoSort = 'accounts', anGeoDescending = true;
var AN_GEO_LABELS = {"regions": {"ru|moscow": "Москва", "ru|moscow oblast": "Московская область", "ru|st.-petersburg": "Санкт-Петербург", "ru|saint petersburg": "Санкт-Петербург", "ru|krasnodar krai": "Краснодарский край", "ru|sverdlovsk oblast": "Свердловская область", "ru|bashkortostan republic": "Башкортостан", "ru|rostov": "Ростовская область", "ru|rostov oblast": "Ростовская область", "ru|mariy-el republic": "Марий Эл", "ru|novosibirsk oblast": "Новосибирская область", "ru|leningradskaya oblast'": "Ленинградская область", "ru|leningrad oblast": "Ленинградская область", "ru|voronezh oblast": "Воронежская область", "ru|stavropol kray": "Ставропольский край", "ru|kaliningrad oblast": "Калининградская область", "ru|belgorod oblast": "Белгородская область", "ru|udmurtiya republic": "Удмуртия", "ru|kostroma oblast": "Костромская область", "ru|penza oblast": "Пензенская область", "ru|orenburg oblast": "Оренбургская область", "ru|ulyanovsk": "Ульяновская область", "ru|samara oblast": "Самарская область", "ru|perm krai": "Пермский край", "ru|tver oblast": "Тверская область", "ru|kursk oblast": "Курская область", "ru|chelyabinsk": "Челябинская область", "ru|vologda oblast": "Вологодская область"}, "cities": {"ru|moscow": "Москва", "ru|saint petersburg": "Санкт-Петербург", "ru|st petersburg": "Санкт-Петербург", "ru|khimki": "Химки", "ru|krasnodar": "Краснодар", "ru|yekaterinburg": "Екатеринбург", "ru|novosibirsk": "Новосибирск", "ru|rostov-on-don": "Ростов-на-Дону", "ru|ufa": "Уфа", "ru|kazan": "Казань", "ru|samara": "Самара", "ru|perm": "Пермь", "ru|chelyabinsk": "Челябинск", "ru|voronezh": "Воронеж", "ru|kaliningrad": "Калининград", "ru|belgorod": "Белгород", "ru|penza": "Пенза", "ru|orenburg": "Оренбург", "ru|ulyanovsk": "Ульяновск", "ru|vologda": "Вологда"}};
function anGeoName(row) { return (AN_GEO_LABELS[anGeoMode]||{})[(row.country+'|'+row.name).toLowerCase()] || row.name; }
function anCountryFlag(raw) {
 var code=String(raw||'').toUpperCase();
 if(!/^[A-Z]{2}$/.test(code)||['XX','ZZ','UN'].indexOf(code)!==-1)return '';
 return String.fromCodePoint(127397+code.charCodeAt(0),127397+code.charCodeAt(1));
}
function anCountryName(code) { try { return new Intl.DisplayNames(['ru'], {type:'region'}).of(code) || code; } catch (_) { return code; } }
function anTable(headers, rows) {
 return '<table class="an-table"><thead><tr>' + headers.map(function(h){return '<th scope="col">'+h+'</th>';}).join('') + '</tr></thead><tbody>' + rows.join('') + '</tbody></table>';
}
function anCell(v) { return '<td>'+anNum(v)+'</td>'; }
function anPlot(data) {
 var tl=data.timeline||[], u=data.users||{}, site=anChartMode==='site';
 var first=site?'Просмотры':'Первые запуски', second=site?'Переходы':'Новые аккаунты';
 document.getElementById('an-dynamics-summary').innerHTML=[[first,anSum(tl,function(d){return site?d.views:d.installs;})],[second,site?anSum(tl,function(d){return d.clicks;}):u.registrations]].map(function(m){return '<span>'+m[0]+'<b>'+(m[1]==null?'—':anNum(m[1]))+'</b></span>';}).join('');
 document.getElementById('an-chart-legend').innerHTML='<span><i class="an-dot" style="background:#0574F8"></i>'+first+'</span><span><i class="an-dot" style="background:#22a875"></i>'+second+'</span>';
 var buckets=anBuckets(tl), bars=[];
 buckets.forEach(function(bk){
  var a=anSum(bk.days,function(d){return site?d.views:d.installs;});
  var b=anSum(bk.days,function(d){return site?d.clicks:(u.registrationsByDay||{})[d.date];});
  var head=anDayLabel(bk.from,true)+(bk.to!==bk.from?' — '+anDayLabel(bk.to):'');
  var tip='<b>'+head+'</b><div class="an-tip-row"><span>'+first+'</span><b>'+anNum(a)+'</b></div><div class="an-tip-row"><span>'+second+'</span><b>'+(site||u?anNum(b):'—')+'</b></div>';
  bars.push({value:a,color:'#0574F8',label:anDayLabel(bk.to),tip:tip});
  bars.push({value:b,color:'#22a875',label:'',tip:tip});
 });
 var el=document.getElementById('an-installs-chart');
 if(tl.length) anBars(el,bars,205); else el.innerHTML='<div class="an-empty">Нет данных за период</div>';
 document.getElementById('an-installs-caption').textContent=tl.some(function(d){return d.date<AN_RELIABLE_FROM;})?'До 25.09 данные о первых запусках неполные.':'';
 document.querySelectorAll('[data-chart]').forEach(function(b){b.classList.toggle('active',b.dataset.chart===anChartMode);b.setAttribute('aria-pressed',String(b.dataset.chart===anChartMode));});
}
function anPercent(value,total) { var pct=total?value/total*100:0;return pct>0&&pct<1?'&lt;1%':Math.round(pct)+'%'; }
function anShare(value,total) {
 var width=total?Math.max(0,Math.min(100,value/total*100)):0;
 return '<span class="an-share">'+anPercent(value,total)+'<span class="an-share-track" aria-hidden="true"><i style="width:'+width+'%"></i></span></span>';
}
function anGeoHeader(label,key) {
 var sorted=anGeoSort===key;
 return '<th scope="col"'+(sorted?' aria-sort="'+(anGeoDescending?'descending':'ascending')+'"':'')+'><button type="button" class="an-sort'+(sorted?' is-sorted':'')+'" data-sort="'+key+'" title="'+(key==='active7'?'Аккаунты, активные за последние 7 дней':key==='premium'?'Действующий Premium':'Сортировать')+'">'+label+(sorted?(anGeoDescending?' ↓':' ↑'):'')+'</button></th>';
}
function anRenderGeo() {
 var u=(window.__anData||{}).users, geo=u&&u.geography;
 var el=document.getElementById('an-geo'), cover=document.getElementById('an-geo-coverage'), pager=document.getElementById('an-geo-pages');
 if(!geo){el.innerHTML='<div class="an-empty">Нет данных</div>';cover.textContent='';pager.innerHTML='';return;}
 var q=document.getElementById('an-geo-search').value.trim(), selector=document.getElementById('an-geo-country');
 selector.hidden=anGeoMode==='countries';
 var country=anGeoMode==='countries'?'all':selector.value;
 var prepared=(geo[anGeoMode]||[]).map(function(r){var label=anGeoMode==='countries'?anCountryName(r.country):anGeoName(r);return Object.assign({},r,{label:label,search:r.name+' '+label+' '+anCountryName(r.country)+' '+r.country});});
 var selected=AN_SELECT_GEO(prepared,{country:country,query:q,sort:anGeoSort,descending:anGeoDescending,page:anGeoPage});
 anGeoPage=selected.page;
 var headings=anGeoHeader(anGeoMode==='countries'?'Страна':anGeoMode==='regions'?'Регион':'Город','name')+anGeoHeader('Аккаунты','accounts')+'<th scope="col" title="Среди аккаунтов с известной географией, с учётом выбранной страны">Доля</th>'+anGeoHeader('Активны','active7')+anGeoHeader('Premium','premium');
 el.innerHTML=selected.rows.length?'<table class="an-table"><thead><tr>'+headings+'</tr></thead><tbody>'+selected.rows.map(function(r){
  return '<tr><td><span class="an-table-name">'+(anCountryFlag(r.country)?'<span class="an-flag" role="img" aria-label="'+anEsc(anCountryName(r.country))+'" title="'+anEsc(anCountryName(r.country))+'">'+anCountryFlag(r.country)+'</span>':'')+'<span>'+anEsc(r.label)+'</span>' +'</span></td>'+anCell(r.accounts)+'<td>'+anShare(r.accounts,selected.baseTotal)+'</td><td title="Аккаунты, обращавшиеся к серверу за последние 7 дней">'+anNum(r.active7)+'</td>'+anCell(r.premium)+'</tr>';
 }).join('')+'</tbody></table>':'<div class="an-empty">'+(q||country!=='all'?'Ничего не найдено':'Нет данных')+'</div>';
 var known=(geo[anGeoMode]||[]).reduce(function(n,r){return n+r.accounts;},0);
 var coverage=geo.total?Math.round(known/geo.total*100):0;
 cover.textContent='География известна: '+coverage+'%';
 cover.title=anNum(known)+' из '+anNum(geo.total)+' новых аккаунтов. По IP, приблизительно. Старые профили дополняются постепенно.';
 pager.innerHTML=selected.count?'<span>'+anNum(selected.start+1)+'–'+anNum(selected.end)+' из '+anNum(selected.count)+'</span><button type="button" data-page="-1" aria-label="Предыдущая страница"'+(selected.page===0?' disabled':'')+'>‹</button><button type="button" data-page="1" aria-label="Следующая страница"'+(selected.page===selected.pages-1?' disabled':'')+'>›</button>':'';
 document.getElementById('an-geo-reset').hidden=!q&&selector.value==='all';
 document.querySelectorAll('[data-geo]').forEach(function(b){b.classList.toggle('active',b.dataset.geo===anGeoMode);b.setAttribute('aria-pressed',String(b.dataset.geo===anGeoMode));});
}
function anRenderActivity(data) {
 var activity=data.users&&data.users.activity, days=activity?activity.days:[], available=days.filter(function(d){return d.total!=null;}), bars=[];
 var latest=available[available.length-1], sum=available.reduce(function(n,d){return n+d.total;},0);
 document.getElementById('an-activity-summary').innerHTML=latest?[
 ['Сегодня',latest.total],['Android',latest.android],['iOS',latest.ios],['Среднее за день',Math.round(sum/available.length)]
 ].map(function(m){return '<span>'+m[0]+'<b>'+anNum(m[1])+'</b></span>';}).join(''):'';
 available.forEach(function(d){
  var tip='<b>'+anDayLabel(d.date,true)+'</b>' + [['Всего аккаунтов',d.total],['Android',d.android],['iOS',d.ios],['Веб',d.web],['Неизвестно',d.unknown]].map(function(m){return '<div class="an-tip-row"><span>'+m[0]+'</span><b>'+anNum(m[1])+'</b></div>';}).join('');
  bars.push({value:d.android,color:'#0574F8',label:anDayLabel(d.date),tip:tip});
  bars.push({value:d.ios,color:'#22a875',label:'',tip:tip});
 });
 var el=document.getElementById('an-activity-chart');
 if(bars.length)anBars(el,bars,205);else el.innerHTML='<div class="an-empty">Нет истории активности за выбранный период</div>';
 document.getElementById('an-activity-caption').textContent=activity?'История с '+anDayLabel(activity.from)+' · МСК':'';
 document.getElementById('an-activity-table').innerHTML=days.length?anTable(['День','Всего','Android','iOS','Веб','Неизвестно'],days.slice().reverse().map(function(d){return '<tr><td>'+anDayLabel(d.date)+'</td>'+['total','android','ios','web','unknown'].map(function(k){return '<td>'+(d[k]==null?'—':anNum(d[k]))+'</td>';}).join('')+'</tr>';})):'<div class="an-empty">Нет данных</div>';
}
function renderDashboard(data) {
 if(!document.getElementById('an-kpis'))return;
 window.__anData=data;
 var t=data.totals||{},u=data.users,tl=data.timeline||[],today=currentDays===1;
 if(currentFeature==='analytics') document.getElementById('current-view-title').textContent='Аналитика';
 document.getElementById('an-period').innerHTML='<b>'+(tl.length?anDayLabel(tl[0].date)+' — '+anDayLabel(tl[tl.length-1].date):'Выбранный период')+'</b> · МСК';
 document.getElementById('an-period').title='Календарные дни. Сегодня — неполный день.';
 var metrics=[['Просмотры сайта',t.views,0,'#7890b0','Открытия страниц'],['Переходы в магазины',t.clicks,0,'#7890b0','Нажатия и прямые редиректы'],['Первые запуски',t.installs,0,'#0574F8','Новые установки по сигналам приложения'],['Новые аккаунты',u?u.registrations:null,u?u.previousRegistrations:null,'#22a875','По дате создания профиля']];
 document.getElementById('an-kpis').innerHTML=metrics.map(function(m,i){return '<div class="an-card an-kpi'+(i===2?' is-primary':'')+'" title="'+m[4]+'"><div class="an-kpi-top"><i class="an-dot" style="background:'+m[3]+'"></i>'+m[0]+'</div><div class="an-big">'+(m[1]==null?'—':anNum(m[1]))+'</div></div>';}).join('');
 anPlot(data);
 anRenderActivity(data);
 var src={};(data.sources||[]).forEach(function(r){if(!r.views&&!r.clicks)return;var k=anSourceKey(r.name);if(!src[k])src[k]={views:0,clicks:0};src[k].views+=r.views||0;src[k].clicks+=r.clicks||0;});
 var keys=Object.keys(src).sort(function(a,b){return src[b].views-src[a].views||src[b].clicks-src[a].clicks;});
 document.getElementById('an-sources').innerHTML=keys.length?anTable(['Источник','Просмотры','Переходы'],keys.map(function(k){return '<tr><td><div class="an-table-name">'+anLogo(AN_SOURCES[k])+anEsc(AN_SOURCES[k].name)+'</div></td>'+anCell(src[k].views)+anCell(src[k].clicks)+'</tr>';})):'<div class="an-empty">Нет событий сайта</div>';
 var stores={};tl.forEach(function(d){Object.keys(d.stores||{}).forEach(function(raw){var k=({'appstore':'App Store','app store':'App Store','gplay':'Google Play','googleplay':'Google Play','google play':'Google Play','rustore':'RuStore','testflight':'TestFlight','web':'Web'})[String(raw).toLowerCase()]||'—';stores[k]=(stores[k]||0)+d.stores[raw];});});
 var names=Object.keys(stores).sort(function(a,b){return stores[b]-stores[a];}),known=names.reduce(function(n,k){return n+stores[k];},0);
 if((t.installs||0)>known){stores['—']=t.installs-known;names.push('—');}
 document.getElementById('an-stores').innerHTML=names.length?anTable(['Магазин / платформа','Запуски','Доля'],names.map(function(k){var conf=AN_STORES[k]||{glyph:'globe'};return '<tr><td><div class="an-table-name">'+anLogo(conf)+anEsc(k)+'</div></td>'+anCell(stores[k])+'<td>'+anShare(stores[k],Math.max(1,t.installs,known))+'</td></tr>';})):'<div class="an-empty">Нет первых запусков</div>';
 var selector=document.getElementById('an-geo-country'),selected=selector.value,geo=u&&u.geography;
 selector.innerHTML='<option value="all">Все страны</option>'+(geo?geo.countries:[]).map(function(r){return '<option value="'+anEsc(r.country)+'">'+anCountryFlag(r.country)+' '+anEsc(anCountryName(r.country))+'</option>';}).join('');
 if(Array.from(selector.options).some(function(o){return o.value===selected;}))selector.value=selected;
 anRenderGeo();
 document.getElementById('an-now').innerHTML=u?[
 ['Всего аккаунтов',u.registered,'Все сохранённые аккаунты выбранного приложения'],['Активны · 24 ч',u.active1,'Обращались к серверу за 24 часа'],['Активны · 7 дней',u.active7,'Обращались к серверу за 7 дней'],['Premium',u.premium,'Действующий Premium, включая ручную выдачу']
 ].map(function(m){return '<span title="'+m[2]+'">'+m[0]+'<b>'+anNum(m[1])+'</b></span>';}).join(''):'';
}
document.getElementById('an-chart-tabs').addEventListener('click',function(e){var b=e.target.closest('[data-chart]');if(b){anChartMode=b.dataset.chart;if(window.__anData)anPlot(window.__anData);}});
document.getElementById('an-geo-tabs').addEventListener('click',function(e){var b=e.target.closest('[data-geo]');if(b){anGeoMode=b.dataset.geo;anGeoPage=0;anRenderGeo();}});
document.getElementById('an-geo-search').addEventListener('input',function(){anGeoPage=0;anRenderGeo();});
document.getElementById('an-geo-country').addEventListener('change',function(){anGeoPage=0;anRenderGeo();});
document.getElementById('an-geo-reset').addEventListener('click',function(){document.getElementById('an-geo-search').value='';document.getElementById('an-geo-country').value='all';anGeoPage=0;anRenderGeo();});
document.getElementById('an-geo').addEventListener('click',function(e){var b=e.target.closest('[data-sort]');if(!b)return;var key=b.dataset.sort;if(anGeoSort===key)anGeoDescending=!anGeoDescending;else{anGeoSort=key;anGeoDescending=key!=='name';}anGeoPage=0;anRenderGeo();});
document.getElementById('an-geo-pages').addEventListener('click',function(e){var b=e.target.closest('[data-page]');if(b&&!b.disabled){anGeoPage+=Number(b.dataset.page);anRenderGeo();}});
document.addEventListener('pointerdown',function(e){document.querySelectorAll('.an-help[open]').forEach(function(d){if(!d.contains(e.target))d.removeAttribute('open');});});
document.addEventListener('keydown',function(e){if(e.key==='Escape'){anTipHide();document.querySelectorAll('.an-help[open]').forEach(function(d){d.removeAttribute('open');});}});

window.addEventListener('resize', function () {
  clearTimeout(window.__anResize);
  window.__anResize = setTimeout(function () { if (window.__anData && currentFeature === 'analytics') renderDashboard(window.__anData); }, 150);
});
`;

export const ANALYTICS_CLIENT_JS = 'var AN_SELECT_GEO = ' + selectGeoRows.toString() + ';\n' + 'var AN_BRAND_PATHS = ' + JSON.stringify(BRAND_ICON_PATHS) + ';\n' + CLIENT;
