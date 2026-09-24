// Раздел «Пользователи» админки: список с поиском и фильтрами и подробная
// карточка пользователя (#users/<id>). Заменяет старую таблицу из
// экранированной строки worker.js целиком. API — users_admin.js.
//
// Клиентский код — String.raw без обратных кавычек и ${ внутри: он вставляется
// в <script> страницы как есть.

export const USERS_VIEW_HTML = String.raw`
    <div id="users-view" style="display:none;">
      <style>
        .uv-kpis { display:grid; grid-template-columns:repeat(5,minmax(0,1fr)); gap:12px; margin-bottom:18px; }
        .uv-kpi { text-align:left; border:none; background:var(--card-bg); border-radius:16px; padding:14px 16px; cursor:pointer; font:inherit; color:var(--text); transition:background .15s, box-shadow .15s; }
        .uv-kpi:hover { background:#fff; box-shadow:0 0 0 2px var(--primary-subtle); }
        .uv-kpi.active { box-shadow:0 0 0 2px var(--primary); }
        .uv-kpi-label { font-size:11.5px; font-weight:600; color:var(--text-muted); }
        .uv-kpi-value { font-size:24px; font-weight:800; letter-spacing:-.5px; margin-top:4px; font-variant-numeric:tabular-nums; }
        .uv-toolbar { display:flex; flex-wrap:wrap; gap:10px; align-items:center; margin-bottom:6px; }
        .uv-search { position:relative; flex:1 1 200px; }
        .uv-toolbar .uv-search input { width:100%; padding-left:36px; }
        .uv-search svg { position:absolute; left:12px; top:50%; transform:translateY(-50%); color:var(--text-muted); pointer-events:none; }
        .uv-toolbar input, .uv-toolbar select, .uv-field { background:var(--surface-gray); border:none; border-radius:10px; padding:9px 12px; font:inherit; font-size:13px; color:var(--text); outline:none; min-height:38px; box-sizing:border-box; }
        .uv-seg { display:inline-flex; background:var(--surface-gray); border-radius:10px; padding:3px; gap:2px; flex-wrap:wrap; }
        .uv-seg button { border:none; background:transparent; border-radius:8px; padding:6px 11px; font:inherit; font-size:12.5px; font-weight:600; color:var(--text-light); cursor:pointer; }
        .uv-seg button.active { background:#fff; color:var(--text); box-shadow:0 1px 2px rgba(0,0,0,.06); }
        .uv-icon-btn { border:none; background:var(--surface-gray); color:var(--text); border-radius:10px; min-height:38px; padding:0 12px; font:inherit; font-size:12.5px; font-weight:600; cursor:pointer; display:inline-flex; align-items:center; gap:6px; }
        .uv-icon-btn:hover { background:var(--surface-hover); }
        .uv-meta { font-size:12px; color:var(--text-muted); margin:8px 2px 4px; }
        .uv-list { display:flex; flex-direction:column; }
        .uv-row { display:grid; grid-template-columns:minmax(0,2.4fr) 90px minmax(0,1.3fr) 120px 110px 16px; gap:14px; align-items:center; padding:11px 10px; border-radius:12px; cursor:pointer; border:none; background:transparent; font:inherit; color:inherit; text-align:left; width:100%; }
        .uv-row:hover { background:var(--bg); }
        .uv-row + .uv-row { box-shadow:0 -1px 0 var(--surface-gray); }
        .uv-row:hover + .uv-row, .uv-row:hover { box-shadow:none; }
        .uv-head { cursor:default; padding-top:4px; padding-bottom:6px; font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:.4px; color:var(--text-muted); }
        .uv-head:hover { background:transparent; }
        .uv-user { display:flex; align-items:center; gap:11px; min-width:0; }
        .uv-avatar { width:36px; height:36px; border-radius:50%; flex-shrink:0; object-fit:cover; background:var(--primary-subtle); color:var(--primary); display:flex; align-items:center; justify-content:center; font-weight:800; font-size:14px; }
        .uv-avatar.lg { width:64px; height:64px; font-size:24px; }
        .uv-name { font-weight:700; font-size:13.5px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .uv-sub { font-size:12px; color:var(--text-muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .uv-cell { font-size:12.5px; color:var(--text-light); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .uv-chev { color:#C4C7D0; }
        .uv-chip { display:inline-flex; align-items:center; gap:5px; padding:3px 9px; border-radius:7px; font-size:11.5px; font-weight:700; white-space:nowrap; background:var(--surface-gray); color:var(--text-light); }
        .uv-chip.pro { background:var(--success-subtle); color:#159461; }
        .uv-chip.soon { background:#FFF4E0; color:#B96A00; }
        .uv-chip.exp { background:var(--danger-subtle); color:var(--danger); }
        .uv-chip.blue { background:var(--primary-subtle); color:var(--primary); }
        .uv-chip.warn { background:#FFF4E0; color:#B96A00; }
        .uv-dot { width:6px; height:6px; border-radius:50%; background:currentColor; }
        .uv-empty { padding:40px 10px; text-align:center; color:var(--text-muted); font-size:13px; }
        .uv-more { display:flex; justify-content:center; padding-top:12px; }
        .uv-back { border:none; background:transparent; color:var(--primary); font:inherit; font-size:13px; font-weight:700; cursor:pointer; padding:6px 0; margin-bottom:12px; display:inline-flex; align-items:center; gap:6px; }
        .uv-hero { display:flex; align-items:center; gap:16px; flex-wrap:wrap; }
        .uv-hero-name { font-size:20px; font-weight:800; letter-spacing:-.4px; }
        .uv-hero-chips { display:flex; flex-wrap:wrap; gap:6px; margin-top:8px; }
        .uv-hero-actions { margin-left:auto; display:flex; gap:8px; flex-wrap:wrap; }
        .uv-grid { display:grid; grid-template-columns:minmax(0,1.35fr) minmax(0,1fr); gap:18px; margin-top:18px; align-items:start; }
        .uv-col { display:flex; flex-direction:column; gap:18px; min-width:0; }
        .uv-card { background:var(--card-bg); border-radius:18px; padding:20px; }
        .uv-card-title { font-size:12px; font-weight:800; text-transform:uppercase; letter-spacing:.5px; color:var(--text-muted); margin-bottom:14px; display:flex; justify-content:space-between; align-items:center; gap:10px; }
        .uv-prem-status { font-size:18px; font-weight:800; letter-spacing:-.3px; }
        .uv-prem-sub { font-size:13px; color:var(--text-light); margin-top:3px; }
        .uv-bar { height:6px; background:var(--surface-gray); border-radius:4px; overflow:hidden; margin-top:12px; }
        .uv-bar > div { height:100%; background:var(--success); border-radius:4px; }
        .uv-sep { height:1px; background:var(--surface-gray); margin:18px 0; }
        .uv-label { font-size:11.5px; font-weight:700; color:var(--text-muted); margin-bottom:8px; }
        .uv-presets { display:flex; flex-wrap:wrap; gap:6px; }
        .uv-presets button { border:none; background:var(--surface-gray); border-radius:9px; padding:8px 12px; font:inherit; font-size:12.5px; font-weight:700; color:var(--text); cursor:pointer; }
        .uv-presets button:hover { background:var(--surface-hover); }
        .uv-presets button.active { background:var(--primary); color:#fff; }
        .uv-form-row { display:flex; gap:8px; flex-wrap:wrap; margin-top:12px; align-items:center; }
        .uv-form-row .uv-field { flex:1 1 180px; }
        .uv-preview { font-size:13px; margin-top:12px; padding:10px 12px; border-radius:10px; background:var(--bg); color:var(--text-light); }
        .uv-preview b { color:var(--text); }
        .uv-actions { display:flex; gap:8px; margin-top:14px; flex-wrap:wrap; }
        .uv-btn { border:none; border-radius:10px; padding:10px 16px; font:inherit; font-size:13px; font-weight:700; cursor:pointer; background:var(--surface-gray); color:var(--text); }
        .uv-btn.primary { background:var(--primary); color:#fff; }
        .uv-btn.primary:hover { background:var(--primary-hover); }
        .uv-btn.danger { background:var(--danger-subtle); color:var(--danger); }
        .uv-btn.ghost { background:transparent; color:var(--text-light); }
        .uv-stats { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; }
        .uv-stat { background:var(--bg); border-radius:12px; padding:12px; }
        .uv-stat-v { font-size:19px; font-weight:800; font-variant-numeric:tabular-nums; }
        .uv-stat-l { font-size:11.5px; color:var(--text-muted); font-weight:600; margin-top:2px; }
        .uv-days { display:grid; grid-template-columns:repeat(30,1fr); gap:3px; margin-top:12px; }
        .uv-days span { aspect-ratio:1; border-radius:3px; background:var(--surface-gray); }
        .uv-days span.on { background:var(--success); }
        .uv-kv { display:grid; grid-template-columns:auto minmax(0,1fr); gap:9px 14px; font-size:13px; }
        .uv-kv dt { color:var(--text-muted); }
        .uv-kv dd { margin:0; text-align:right; font-weight:600; overflow-wrap:anywhere; }
        .uv-copy { border:none; background:none; color:var(--primary); cursor:pointer; font:inherit; font-size:12px; font-weight:700; padding:0 0 0 6px; }
        .uv-note { width:100%; min-height:84px; resize:vertical; background:var(--surface-gray); border:none; border-radius:12px; padding:11px 12px; font:inherit; font-size:13px; color:var(--text); outline:none; box-sizing:border-box; }
        .uv-note-state { font-size:11.5px; color:var(--text-muted); margin-top:6px; min-height:15px; }
        .uv-hist { list-style:none; margin:0; padding:0; display:flex; flex-direction:column; gap:12px; }
        .uv-hist li { display:flex; gap:10px; font-size:13px; }
        .uv-hist-dot { width:8px; height:8px; border-radius:50%; margin-top:6px; flex-shrink:0; background:var(--text-muted); }
        .uv-hist-dot.grant { background:var(--success); }
        .uv-hist-dot.revoke { background:var(--danger); }
        .uv-hist-time { font-size:11.5px; color:var(--text-muted); }
        .uv-exams { display:flex; flex-direction:column; }
        .uv-exam { display:flex; justify-content:space-between; gap:10px; font-size:13px; padding:8px 0; }
        .uv-exam + .uv-exam { border-top:1px solid var(--surface-gray); }
        .uv-raw { margin-top:10px; max-height:320px; overflow:auto; background:var(--bg); border-radius:12px; padding:12px; font-size:11.5px; white-space:pre-wrap; word-break:break-all; }
        .uv-skeleton { height:160px; border-radius:18px; background:linear-gradient(90deg,var(--card-bg),var(--surface-gray),var(--card-bg)); background-size:200% 100%; animation:uvShimmer 1.2s linear infinite; }
        @keyframes uvShimmer { to { background-position:-200% 0; } }
        @media (max-width: 1100px) { .uv-kpis { grid-template-columns:repeat(3,minmax(0,1fr)); } .uv-grid { grid-template-columns:1fr; } }
        @media (max-width: 760px) {
          .uv-kpis { grid-template-columns:repeat(2,minmax(0,1fr)); }
          .uv-row { grid-template-columns:minmax(0,1fr) auto 16px; }
          .uv-row > .uv-hide-sm { display:none; }
          .uv-stats { grid-template-columns:repeat(2,minmax(0,1fr)); }
          .uv-hero-actions { margin-left:0; }
          .uv-kv { grid-template-columns:1fr; gap:2px; }
          .uv-kv dd { text-align:left; margin-bottom:8px; }
        }
      </style>

      <div id="uv-list-screen">
        <div class="uv-kpis" id="uv-kpis"></div>
        <div class="card">
          <div class="uv-toolbar">
            <label class="uv-search">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
              <input id="uv-search" type="search" placeholder="Имя, email или ID" aria-label="Поиск пользователей" autocomplete="off">
            </label>
            <div class="uv-seg" id="uv-filter" role="tablist" aria-label="Статус">
              <button data-filter="all" class="active">Все</button>
              <button data-filter="premium">Premium</button>
              <button data-filter="soon">Истекает</button>
              <button data-filter="expired">Истёк</button>
              <button data-filter="free">Бесплатные</button>
            </div>
            <select id="uv-app" aria-label="Приложение">
              <option value="all">Все страны</option>
              <option value="ru">Россия</option>
              <option value="by">Беларусь</option>
              <option value="rs">Сербия</option>
            </select>
            <select id="uv-sort" aria-label="Сортировка">
              <option value="seen">Недавно заходили</option>
              <option value="created">Новые</option>
              <option value="expires">Premium скоро кончится</option>
              <option value="name">По имени</option>
            </select>
            <button class="uv-icon-btn" id="uv-export" title="Скачать CSV отфильтрованного списка">CSV</button>
            <button class="uv-icon-btn" id="refresh-users-btn" title="Обновить">
              <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/></svg>
            </button>
          </div>
          <div class="uv-meta" id="uv-meta">Загрузка…</div>
          <div class="uv-list" id="uv-list"></div>
          <div class="uv-more" id="uv-more"></div>
        </div>
      </div>

      <div id="uv-detail-screen" hidden></div>
    </div>
`;

export const USERS_CLIENT_JS = String.raw`
// ────────────────────── Users & Premium (users_ui.js) ──────────────────────
var uvState = { users: [], filter: 'all', app: 'all', sort: 'seen', query: '', limit: 50, loaded: false, openId: null, detail: null, grant: null };
var UV_DAY = 86400000;
var UV_PRESETS = [[7, '7 дней'], [30, '1 месяц'], [90, '3 месяца'], [180, '6 месяцев'], [365, '1 год']];
var UV_APPS = { ru: 'Россия', by: 'Беларусь', rs: 'Сербия' };
var UV_SOURCES = { admin_grant: 'Выдан вручную', google_play: 'Google Play', play: 'Google Play', app_store: 'App Store', apple: 'App Store', rustore: 'RuStore' };

function uvEsc(v) {
  return String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function uvTime(v) { var t = v ? Date.parse(v) : NaN; return isFinite(t) ? t : 0; }
function uvDate(v, withTime) {
  var t = uvTime(v); if (!t) return '—';
  var o = { day: 'numeric', month: 'short', year: 'numeric' };
  if (withTime) { o.hour = '2-digit'; o.minute = '2-digit'; }
  return new Date(t).toLocaleString('ru-RU', o).replace(' г.', '');
}
function uvAgo(v) {
  var t = uvTime(v); if (!t) return '—';
  var s = Math.round((Date.now() - t) / 1000);
  if (s < 60) return 'только что';
  if (s < 3600) return Math.floor(s / 60) + ' мин назад';
  if (s < 86400) return Math.floor(s / 3600) + ' ч назад';
  var d = Math.floor(s / 86400);
  if (d === 1) return 'вчера';
  if (d < 30) return d + ' ' + uvPlural(d, 'день', 'дня', 'дней') + ' назад';
  return uvDate(v);
}
function uvPlural(n, one, few, many) {
  var a = Math.abs(n) % 100, b = a % 10;
  if (a > 10 && a < 20) return many;
  if (b > 1 && b < 5) return few;
  if (b === 1) return one;
  return many;
}
function uvDaysLeft(v) { return Math.ceil((uvTime(v) - Date.now()) / UV_DAY); }

// Статус Premium: active | soon (≤7 дней) | lifetime | expired | free
function uvStatus(u) {
  if (!u.isPremium) return 'free';
  if (!u.premiumExpiresAt) return 'lifetime';
  var left = uvTime(u.premiumExpiresAt) - Date.now();
  if (left <= 0) return 'expired';
  return left <= 7 * UV_DAY ? 'soon' : 'active';
}
function uvIsPro(s) { return s === 'active' || s === 'soon' || s === 'lifetime'; }
function uvStatusChip(u) {
  var s = uvStatus(u);
  if (s === 'lifetime') return '<span class="uv-chip pro"><span class="uv-dot"></span>Premium навсегда</span>';
  if (s === 'active') return '<span class="uv-chip pro"><span class="uv-dot"></span>Premium до ' + uvEsc(uvDate(u.premiumExpiresAt)) + '</span>';
  if (s === 'soon') { var d = uvDaysLeft(u.premiumExpiresAt); return '<span class="uv-chip soon"><span class="uv-dot"></span>Ещё ' + d + ' ' + uvPlural(d, 'день', 'дня', 'дней') + '</span>'; }
  if (s === 'expired') return '<span class="uv-chip exp">Истёк ' + uvEsc(uvDate(u.premiumExpiresAt)) + '</span>';
  return '<span class="uv-chip">Бесплатный</span>';
}
function uvAvatar(u, lg) {
  var letter = uvEsc(String(u.name || u.email || '?').trim().charAt(0).toUpperCase() || '?');
  var cls = 'uv-avatar' + (lg ? ' lg' : '');
  if (u.avatarUrl) return '<img class="' + cls + '" src="' + uvEsc(u.avatarUrl) + '" alt="" data-letter="' + letter + '" referrerpolicy="no-referrer" onerror="uvAvatarFallback(this)">';
  return '<div class="' + cls + '">' + letter + '</div>';
}
function uvAvatarFallback(img) {
  var div = document.createElement('div');
  div.className = img.className;
  div.textContent = img.getAttribute('data-letter') || '?';
  img.replaceWith(div);
}
function uvProvider(u) {
  var p = String(u.provider || 'guest').toLowerCase();
  if (p.indexOf('google') !== -1) return 'Google';
  if (p.indexOf('apple') !== -1) return 'Apple';
  if (p.indexOf('yandex') !== -1) return 'Яндекс';
  return 'Гость';
}
function uvPlatform(u) {
  var p = String(u.platform || '').toLowerCase();
  return p === 'ios' ? 'iOS' : p === 'android' ? 'Android' : p === 'web' ? 'Веб' : (u.platform || '');
}
function uvAppCode(u) { return String(u.app || 'ru').toLowerCase(); }

async function uvFetch(url, body) {
  var opts = body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : undefined;
  var res = await fetch(url, opts);
  if (res.status === 401 || res.status === 403) { checkAuthAndLoad(); throw new Error('нужно войти заново'); }
  var data = null;
  try { data = await res.json(); } catch (_) {}
  if (!res.ok || !data || data.ok === false) throw new Error((data && data.error) || ('ошибка сервера ' + res.status));
  return data;
}
function uvToast(msg, isError) {
  if (typeof adminToast === 'function') adminToast(msg, isError);
  else if (isError) alert(msg);
}

// ── Список ──
async function loadUsersList() {
  var meta = document.getElementById('uv-meta');
  if (!uvState.loaded && meta) meta.textContent = 'Загрузка…';
  try {
    var data = await uvFetch('/api/admin/users');
    uvState.users = data.users || [];
    uvState.loaded = true;
    uvRenderList();
    uvSyncRoute();
  } catch (err) {
    if (meta) meta.innerHTML = '<span style="color:var(--danger)">Не удалось загрузить: ' + uvEsc(err.message) + '</span>';
  }
}

function uvFiltered() {
  var q = uvState.query.trim().toLocaleLowerCase('ru');
  var list = uvState.users.filter(function (u) {
    var s = uvStatus(u);
    if (uvState.filter === 'premium' && !uvIsPro(s)) return false;
    if (uvState.filter === 'soon' && s !== 'soon') return false;
    if (uvState.filter === 'expired' && s !== 'expired') return false;
    if (uvState.filter === 'free' && s !== 'free') return false;
    if (uvState.filter === 'new' && Date.now() - uvTime(u.createdAt) > 7 * UV_DAY) return false;
    if (uvState.app !== 'all' && uvAppCode(u) !== uvState.app) return false;
    if (q) {
      var hay = [u.name, u.email, u.id, u.appVersion].join(' ').toLocaleLowerCase('ru');
      if (hay.indexOf(q) === -1) return false;
    }
    return true;
  });
  var by = {
    seen: function (a, b) { return uvTime(b.lastSeenAt || b.createdAt) - uvTime(a.lastSeenAt || a.createdAt); },
    created: function (a, b) { return uvTime(b.createdAt) - uvTime(a.createdAt); },
    name: function (a, b) { return String(a.name || '').localeCompare(String(b.name || ''), 'ru'); },
    expires: function (a, b) {
      var ea = uvStatus(a) === 'active' || uvStatus(a) === 'soon' ? uvTime(a.premiumExpiresAt) : Infinity;
      var eb = uvStatus(b) === 'active' || uvStatus(b) === 'soon' ? uvTime(b.premiumExpiresAt) : Infinity;
      return ea - eb;
    }
  }[uvState.sort];
  return list.sort(by);
}

function uvRenderKpis() {
  var users = uvState.users, now = Date.now();
  var pro = 0, soon = 0, fresh = 0, active = 0;
  users.forEach(function (u) {
    var s = uvStatus(u);
    if (uvIsPro(s)) pro++;
    if (s === 'soon') soon++;
    if (now - uvTime(u.createdAt) <= 7 * UV_DAY) fresh++;
    if (now - uvTime(u.lastSeenAt) <= 7 * UV_DAY) active++;
  });
  var tiles = [
    ['all', 'Всего', users.length],
    ['premium', 'Premium', pro],
    ['soon', 'Истекает за 7 дней', soon],
    ['new', 'Новые за 7 дней', fresh],
    ['seen7', 'Заходили за 7 дней', active]
  ];
  document.getElementById('uv-kpis').innerHTML = tiles.map(function (t) {
    var on = uvState.filter === t[0] || (t[0] === 'seen7' && uvState.filter === 'seen7');
    return '<button class="uv-kpi' + (on ? ' active' : '') + '" data-kpi="' + t[0] + '"><div class="uv-kpi-label">' + t[1] + '</div><div class="uv-kpi-value">' + t[2].toLocaleString('ru-RU') + '</div></button>';
  }).join('');
}

function uvRenderList() {
  uvRenderKpis();
  var list = uvState.filter === 'seen7'
    ? uvFiltered().filter(function (u) { return Date.now() - uvTime(u.lastSeenAt) <= 7 * UV_DAY; })
    : uvFiltered();
  uvState.visible = list;
  document.querySelectorAll('#uv-filter button').forEach(function (b) { b.classList.toggle('active', b.dataset.filter === uvState.filter); });
  var meta = document.getElementById('uv-meta');
  meta.textContent = list.length === uvState.users.length
    ? uvState.users.length + ' ' + uvPlural(uvState.users.length, 'пользователь', 'пользователя', 'пользователей')
    : 'Найдено ' + list.length + ' из ' + uvState.users.length;
  var box = document.getElementById('uv-list');
  if (!list.length) {
    box.innerHTML = '<div class="uv-empty">' + (uvState.users.length ? 'Никого не нашли — попробуйте изменить фильтры' : 'Пользователей пока нет') + '</div>';
    document.getElementById('uv-more').innerHTML = '';
    return;
  }
  var head = '<div class="uv-row uv-head"><div>Пользователь</div><div class="uv-hide-sm">Страна</div><div>Статус</div><div class="uv-hide-sm">Заходил</div><div class="uv-hide-sm">Регистрация</div><div></div></div>';
  box.innerHTML = head + list.slice(0, uvState.limit).map(function (u) {
    var sub = u.email || ('ID ' + u.id);
    var flags = u.suspect ? ' <span class="uv-chip warn" title="Отмечен как подозрительный">!</span>' : '';
    return '<button class="uv-row" data-user="' + uvEsc(u.id) + '">'
      + '<div class="uv-user">' + uvAvatar(u) + '<div style="min-width:0"><div class="uv-name">' + uvEsc(u.name || 'Пользователь') + flags + '</div><div class="uv-sub">' + uvEsc(sub) + '</div></div></div>'
      + '<div class="uv-cell uv-hide-sm">' + uvEsc(uvAppCode(u).toUpperCase()) + (uvPlatform(u) ? ' · ' + uvEsc(uvPlatform(u)) : '') + '</div>'
      + '<div>' + uvStatusChip(u) + '</div>'
      + '<div class="uv-cell uv-hide-sm" title="' + uvEsc(uvDate(u.lastSeenAt, true)) + '">' + uvEsc(uvAgo(u.lastSeenAt || u.createdAt)) + '</div>'
      + '<div class="uv-cell uv-hide-sm">' + uvEsc(uvDate(u.createdAt)) + '</div>'
      + '<svg class="uv-chev" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4"><path d="m9 6 6 6-6 6"/></svg>'
      + '</button>';
  }).join('');
  var rest = list.length - uvState.limit;
  document.getElementById('uv-more').innerHTML = rest > 0 ? '<button class="uv-btn" id="uv-more-btn">Показать ещё ' + Math.min(rest, 50) + ' из ' + rest + '</button>' : '';
}

function uvExportCsv() {
  var rows = [['id', 'name', 'email', 'provider', 'app', 'platform', 'version', 'status', 'premium_until', 'premium_source', 'created', 'last_seen']];
  (uvState.visible || []).forEach(function (u) {
    rows.push([u.id, u.name, u.email, uvProvider(u), uvAppCode(u), u.platform, u.appVersion, uvStatus(u), u.premiumExpiresAt, u.premiumSource, u.createdAt, u.lastSeenAt]);
  });
  var csv = rows.map(function (r) { return r.map(function (v) { v = v == null ? '' : String(v); return /[",;\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }).join(','); }).join('\n');
  var a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
  a.download = 'users-' + new Date().toISOString().slice(0, 10) + '.csv';
  a.click();
  setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
}

// ── Маршрут #users/<id> ──
function uvRouteId() {
  var m = /^#users\/(.+)$/.exec(location.hash);
  return m ? decodeURIComponent(m[1]) : null;
}
function uvOpen(id) {
  if (history.pushState) history.pushState(null, '', '#users/' + encodeURIComponent(id));
  uvSyncRoute();
}
function uvClose() {
  if (uvRouteId() && history.pushState) history.pushState(null, '', '#users');
  uvSyncRoute();
}
function uvSyncRoute() {
  if (typeof currentFeature !== 'undefined' && currentFeature !== 'users') return;
  var id = uvRouteId();
  var list = document.getElementById('uv-list-screen');
  var detail = document.getElementById('uv-detail-screen');
  if (!list || !detail) return;
  if (!id) {
    uvState.openId = null;
    detail.hidden = true; detail.innerHTML = '';
    list.hidden = false;
    return;
  }
  list.hidden = true; detail.hidden = false;
  if (uvState.openId === id && uvState.detail) return;
  uvState.openId = id;
  uvLoadDetail(id);
}

// ── Карточка ──
async function uvLoadDetail(id) {
  var box = document.getElementById('uv-detail-screen');
  var cached = uvState.users.find(function (u) { return u.id === id; });
  uvState.detail = null;
  box.innerHTML = uvBackBtn() + (cached ? '<div class="uv-card">' + uvHeroHtml(cached) + '</div>' : '') + '<div class="uv-grid"><div class="uv-skeleton"></div><div class="uv-skeleton"></div></div>';
  try {
    var data = await uvFetch('/api/admin/users/detail?id=' + encodeURIComponent(id));
    if (uvState.openId !== id) return;
    uvState.detail = data;
    uvState.grant = { days: 30, mode: 'extend', until: '', lifetime: false };
    uvRenderDetail();
  } catch (err) {
    if (uvState.openId !== id) return;
    box.innerHTML = uvBackBtn() + '<div class="uv-card uv-empty">Не удалось открыть карточку: ' + uvEsc(err.message) + '</div>';
  }
}
function uvBackBtn() {
  return '<button class="uv-back" data-uv="back"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4"><path d="m15 18-6-6 6-6"/></svg>Все пользователи</button>';
}
function uvHeroHtml(u) {
  var chips = [uvStatusChip(u), '<span class="uv-chip">' + uvEsc(uvProvider(u)) + '</span>',
    '<span class="uv-chip">' + uvEsc(UV_APPS[uvAppCode(u)] || uvAppCode(u).toUpperCase()) + '</span>'];
  if (uvPlatform(u)) chips.push('<span class="uv-chip">' + uvEsc(uvPlatform(u)) + (u.appVersion ? ' · v' + uvEsc(u.appVersion) : '') + '</span>');
  if (u.suspect) chips.push('<span class="uv-chip warn">Подозрительный</span>');
  return '<div class="uv-hero">' + uvAvatar(u, true)
    + '<div style="min-width:0"><div class="uv-hero-name">' + uvEsc(u.name || 'Пользователь') + '</div>'
    + '<div class="uv-sub">' + (u.email ? uvEsc(u.email) + '<button class="uv-copy" data-copy="' + uvEsc(u.email) + '">копировать</button>' : 'без email') + '</div>'
    + '<div class="uv-hero-chips">' + chips.join('') + '</div></div>'
    + '<div class="uv-hero-actions">'
    + (u.email ? '<a class="uv-btn" href="mailto:' + uvEsc(u.email) + '" style="text-decoration:none">Написать</a>' : '')
    + '</div></div>';
}

function uvRenderDetail() {
  var d = uvState.detail; if (!d) return;
  var u = d.user;
  var box = document.getElementById('uv-detail-screen');
  box.innerHTML = uvBackBtn()
    + '<div class="uv-card">' + uvHeroHtml(u) + '</div>'
    + '<div class="uv-grid"><div class="uv-col">'
    + uvPremiumCard(u) + uvProgressCard(d.progress, d.weeklyGame) + uvExamsCard(d.progress)
    + '</div><div class="uv-col">'
    + uvInfoCard(u) + uvNoteCard(d.admin) + uvHistoryCard(d.admin) + uvDangerCard(u) + uvRawCard(u)
    + '</div></div>';
  uvUpdateGrantPreview();
}

function uvPremiumCard(u) {
  var s = uvStatus(u), g = uvState.grant, pro = uvIsPro(s);
  var title, sub = '', bar = '';
  if (s === 'lifetime') { title = 'Premium навсегда'; }
  else if (pro) {
    var left = uvDaysLeft(u.premiumExpiresAt);
    title = 'Premium активен';
    sub = 'До ' + uvDate(u.premiumExpiresAt, true) + ' · осталось ' + left + ' ' + uvPlural(left, 'день', 'дня', 'дней');
    var start = uvTime(u.grantedAt || u.purchasedAt);
    var end = uvTime(u.premiumExpiresAt);
    if (start && end > start) {
      var pct = Math.max(2, Math.min(100, Math.round((end - Date.now()) / (end - start) * 100)));
      bar = '<div class="uv-bar" title="Осталось ' + pct + '% срока"><div style="width:' + pct + '%;' + (s === 'soon' ? 'background:#F5A524' : '') + '"></div></div>';
    }
  } else if (s === 'expired') { title = 'Premium истёк'; sub = 'Закончился ' + uvDate(u.premiumExpiresAt, true); }
  else { title = 'Бесплатный доступ'; }
  if (u.isPremium && u.premiumSource) sub += (sub ? ' · ' : '') + (UV_SOURCES[u.premiumSource] || u.premiumSource);
  var storeNote = pro && u.premiumSource && u.premiumSource !== 'admin_grant'
    ? '<div class="uv-preview" style="margin-top:12px">Подписка оплачена через магазин. Выдача вручную заменит её срок, а магазин может перезаписать его при следующей проверке.</div>' : '';

  var presets = UV_PRESETS.map(function (p) {
    return '<button data-days="' + p[0] + '" class="' + (!g.lifetime && !g.until && g.days === p[0] ? 'active' : '') + '">' + p[1] + '</button>';
  }).join('') + '<button data-days="lifetime" class="' + (g.lifetime ? 'active' : '') + '">Навсегда</button>';
  var canExtend = s === 'active' || s === 'soon';
  var tomorrow = new Date(Date.now() + UV_DAY).toISOString().slice(0, 10);

  return '<div class="uv-card"><div class="uv-card-title">Premium</div>'
    + '<div class="uv-prem-status" style="color:' + (pro ? '#159461' : s === 'expired' ? 'var(--danger)' : 'var(--text)') + '">' + title + '</div>'
    + (sub ? '<div class="uv-prem-sub">' + uvEsc(sub) + '</div>' : '') + bar + storeNote
    + '<div class="uv-sep"></div>'
    + '<div class="uv-label">' + (pro ? 'Продлить или изменить срок' : 'Выдать Premium') + '</div>'
    + '<div class="uv-presets" id="uv-presets">' + presets + '</div>'
    + '<div class="uv-form-row">'
    + '<input class="uv-field" type="number" min="1" max="3650" id="uv-days" placeholder="Своё число дней" value="' + (!g.lifetime && !g.until && UV_PRESETS.every(function (p) { return p[0] !== g.days; }) ? g.days : '') + '">'
    + '<input class="uv-field" type="date" id="uv-until" min="' + tomorrow + '" value="' + uvEsc(g.until) + '" title="Действует до конца выбранного дня">'
    + '</div>'
    + (canExtend ? '<div class="uv-form-row"><div class="uv-seg" id="uv-mode"><button data-mode="extend" class="' + (g.mode === 'extend' ? 'active' : '') + '">Прибавить к сроку</button><button data-mode="set" class="' + (g.mode === 'set' ? 'active' : '') + '">Считать с сегодня</button></div></div>' : '')
    + '<div class="uv-form-row"><input class="uv-field" id="uv-comment" maxlength="200" placeholder="Причина — попадёт в историю (необязательно)"></div>'
    + '<div class="uv-preview" id="uv-preview"></div>'
    + '<div class="uv-actions"><button class="uv-btn primary" data-uv="grant">' + (pro ? 'Сохранить срок' : 'Выдать Premium') + '</button>'
    + (u.isPremium ? '<button class="uv-btn danger" data-uv="revoke">Отозвать</button>' : '') + '</div>'
    + '</div>';
}

function uvGrantResult() {
  var g = uvState.grant, u = uvState.detail.user;
  if (g.lifetime) return { expires: null, body: { isLifetime: true } };
  if (g.until) {
    var p = g.until.split('-');
    var end = Date.UTC(+p[0], +p[1] - 1, +p[2], 23, 59, 59);
    if (!isFinite(end) || end <= Date.now()) return { error: 'Дата должна быть в будущем' };
    return { expires: end, body: { until: g.until } };
  }
  var days = parseInt(g.days, 10);
  if (!(days >= 1 && days <= 3650)) return { error: 'Укажите от 1 до 3650 дней' };
  var cur = u.isPremium && u.premiumExpiresAt ? uvTime(u.premiumExpiresAt) : 0;
  var base = g.mode !== 'set' && cur > Date.now() ? cur : Date.now();
  return { expires: base + days * UV_DAY, body: { days: days, mode: g.mode } };
}
function uvUpdateGrantPreview() {
  var el = document.getElementById('uv-preview'); if (!el) return;
  var r = uvGrantResult();
  if (r.error) { el.innerHTML = '<span style="color:var(--danger)">' + uvEsc(r.error) + '</span>'; return; }
  if (r.expires === null) { el.innerHTML = 'Будет: <b>Premium навсегда</b>'; return; }
  var total = Math.ceil((r.expires - Date.now()) / UV_DAY);
  el.innerHTML = 'Будет действовать до <b>' + uvEsc(uvDate(new Date(r.expires).toISOString(), true)) + '</b> · ' + total + ' ' + uvPlural(total, 'день', 'дня', 'дней') + ' от сегодня';
}

function uvStat(v, l) { return '<div class="uv-stat"><div class="uv-stat-v">' + v + '</div><div class="uv-stat-l">' + l + '</div></div>'; }
function uvProgressCard(p, weekly) {
  if (!p) return '<div class="uv-card"><div class="uv-card-title">Прогресс</div><div class="uv-empty" style="padding:18px 0">Прогресс ещё не синхронизирован с облаком</div></div>';
  var ab = p.ab, cd = p.cd;
  var acc = ab.answered ? Math.round(ab.correct / ab.answered * 100) + '%' : '—';
  var html = '<div class="uv-card"><div class="uv-card-title"><span>Прогресс · A/B</span><span style="text-transform:none;letter-spacing:0;font-weight:600">синхр. ' + uvEsc(uvAgo(p.updatedAt)) + '</span></div>'
    + '<div class="uv-stats">'
    + uvStat(ab.answered, 'вопросов решено') + uvStat(acc, 'верных ответов')
    + uvStat(ab.ticketsSolved + ' / ' + ab.ticketsStarted, 'билетов без ошибок')
    + uvStat(ab.examsPassed + ' / ' + ab.exams, 'экзаменов сдано')
    + uvStat(p.streak.current + ' · ' + p.streak.longest, 'серия · рекорд')
    + uvStat(ab.favorites, 'в избранном')
    + '</div>';
  if (cd && (cd.answered || cd.exams)) {
    html += '<div class="uv-label" style="margin-top:14px">C/D</div><div class="uv-stats">'
      + uvStat(cd.answered, 'вопросов') + uvStat(cd.answered ? Math.round(cd.correct / cd.answered * 100) + '%' : '—', 'верных')
      + uvStat(cd.examsPassed + ' / ' + cd.exams, 'экзаменов') + '</div>';
  }
  if (p.game && (p.game.bestScore || weekly)) {
    html += '<div class="uv-label" style="margin-top:14px">Игра</div><div class="uv-stats">'
      + uvStat(p.game.bestScore, 'лучший счёт') + uvStat(weekly && weekly.score != null ? weekly.score : '—', 'на этой неделе') + uvStat(p.game.cars, 'машин в гараже') + '</div>';
  }
  var days = {};
  (p.streak.activeDays || []).forEach(function (d) { days[String(d).slice(0, 10)] = true; });
  var cells = [];
  for (var i = 29; i >= 0; i--) {
    var key = new Date(Date.now() - i * UV_DAY).toISOString().slice(0, 10);
    cells.push('<span class="' + (days[key] ? 'on' : '') + '" title="' + key + '"></span>');
  }
  html += '<div class="uv-label" style="margin-top:14px">Активность за 30 дней</div><div class="uv-days">' + cells.join('') + '</div>';
  return html + '</div>';
}
function uvExamsCard(p) {
  var list = p && p.ab ? p.ab.recentExams : [];
  if (!list || !list.length) return '';
  return '<div class="uv-card"><div class="uv-card-title">Последние экзамены</div><div class="uv-exams">'
    + list.map(function (e) {
      return '<div class="uv-exam"><span>' + (e.ticketNumber ? 'Билет ' + uvEsc(e.ticketNumber) : 'Экзамен') + ' · <span style="color:var(--text-muted)">' + uvEsc(uvDate(e.completedAt, true)) + '</span></span>'
        + '<span>' + e.correctAnswers + ' / ' + (e.correctAnswers + e.wrongAnswers) + ' ' + (e.passed ? '<span class="uv-chip pro">сдал</span>' : '<span class="uv-chip exp">не сдал</span>') + '</span></div>';
    }).join('') + '</div></div>';
}
function uvInfoCard(u) {
  var rows = [
    ['ID', uvEsc(u.id) + '<button class="uv-copy" data-copy="' + uvEsc(u.id) + '">копировать</button>'],
    ['Регистрация', uvEsc(uvDate(u.createdAt, true))],
    ['Последний вход', uvEsc(uvDate(u.lastSeenAt, true)) + ' <span style="color:var(--text-muted);font-weight:500">(' + uvEsc(uvAgo(u.lastSeenAt)) + ')</span>'],
    ['Вход через', uvEsc(uvProvider(u))],
    ['Приложение', uvEsc(UV_APPS[uvAppCode(u)] || uvAppCode(u))],
    ['Устройство', uvEsc([uvPlatform(u), u.appVersion ? 'v' + u.appVersion : ''].filter(Boolean).join(' · ') || '—')],
    ['Страна по IP', uvEsc(u.ipCountry || '—')],
    ['Push-уведомления', u.hasPushToken ? 'подключены' : 'нет'],
  ];
  if (u.purchasedAt) rows.push(['Покупка', uvEsc(uvDate(u.purchasedAt, true))]);
  if (u.grantedAt) rows.push(['Выдан вручную', uvEsc(uvDate(u.grantedAt, true))]);
  if (u.userAgent) rows.push(['User-Agent', '<span style="font-weight:500;font-size:11.5px;color:var(--text-light)">' + uvEsc(u.userAgent) + '</span>']);
  return '<div class="uv-card"><div class="uv-card-title">Информация</div><dl class="uv-kv">'
    + rows.map(function (r) { return '<dt>' + r[0] + '</dt><dd>' + r[1] + '</dd>'; }).join('') + '</dl></div>';
}
function uvNoteCard(admin) {
  return '<div class="uv-card"><div class="uv-card-title">Заметка</div>'
    + '<textarea class="uv-note" id="uv-note" maxlength="2000" placeholder="Видна только в админке. Сохраняется автоматически.">' + uvEsc(admin.note) + '</textarea>'
    + '<div class="uv-note-state" id="uv-note-state">' + (admin.noteUpdatedAt ? 'Изменена ' + uvEsc(uvAgo(admin.noteUpdatedAt)) : '') + '</div></div>';
}
function uvHistoryText(h) {
  var until = h.until ? uvDate(h.until, true) : 'навсегда';
  if (h.action === 'grant') {
    var what = h.mode === 'lifetime' ? 'Выдан Premium навсегда'
      : h.mode === 'until' ? 'Premium до ' + until
      : (h.mode === 'set' ? 'Срок с сегодня: ' : 'Продлено на ') + h.days + ' ' + uvPlural(h.days, 'день', 'дня', 'дней') + ' → до ' + until;
    return what;
  }
  if (h.action === 'revoke') return 'Premium отозван';
  if (h.action === 'sessions') return 'Выход на всех устройствах';
  if (h.action === 'flag') return 'Отмечен как подозрительный';
  if (h.action === 'unflag') return 'Снята отметка «подозрительный»';
  return h.action;
}
function uvHistoryCard(admin) {
  var items = admin.history || [];
  return '<div class="uv-card"><div class="uv-card-title">История действий</div>'
    + (items.length ? '<ul class="uv-hist">' + items.map(function (h) {
      return '<li><span class="uv-hist-dot ' + uvEsc(h.action) + '"></span><div><div>' + uvEsc(uvHistoryText(h)) + '</div>'
        + (h.comment ? '<div class="uv-sub" style="white-space:normal">«' + uvEsc(h.comment) + '»</div>' : '')
        + '<div class="uv-hist-time">' + uvEsc(uvDate(h.at, true)) + '</div></div></li>';
    }).join('') + '</ul>' : '<div class="uv-sub">Действий администратора пока не было</div>')
    + '</div>';
}
function uvDangerCard(u) {
  return '<div class="uv-card"><div class="uv-card-title">Управление</div><div class="uv-actions" style="margin-top:0">'
    + '<button class="uv-btn" data-uv="sessions" title="Приложение попросит войти заново">Выйти на всех устройствах</button>'
    + '<button class="uv-btn" data-uv="suspect">' + (u.suspect ? 'Снять отметку' : 'Пометить подозрительным') + '</button>'
    + '<button class="uv-btn danger" data-uv="delete">Удалить аккаунт</button>'
    + '</div></div>';
}
function uvRawCard(u) {
  return '<div class="uv-card"><details><summary style="cursor:pointer;font-size:12px;font-weight:800;text-transform:uppercase;letter-spacing:.5px;color:var(--text-muted)">Сырые данные</summary>'
    + '<pre class="uv-raw">' + uvEsc(JSON.stringify(u, null, 2)) + '</pre></details></div>';
}

// Карточка обновляется из ответа сервера, список — тем же объектом.
function uvApplyUser(user, admin) {
  var d = uvState.detail;
  if (user) {
    d.user = user;
    var i = uvState.users.findIndex(function (x) { return x.id === user.id; });
    if (i !== -1) uvState.users[i] = user;
  }
  if (admin) d.admin = admin;
  uvRenderDetail();
  uvRenderList();
}

async function uvAction(action, btn) {
  var d = uvState.detail; if (!d) return;
  var u = d.user, id = u.id, name = u.name || u.email || id;
  var busy = function (on) { if (btn) { btn.disabled = on; } };
  try {
    if (action === 'grant') {
      var r = uvGrantResult();
      if (r.error) { uvToast(r.error, true); return; }
      var comment = (document.getElementById('uv-comment') || {}).value || '';
      busy(true);
      var res = await uvFetch('/api/admin/users/grant-premium', Object.assign({ userId: id, comment: comment.trim() || undefined }, r.body));
      uvState.grant = { days: 30, mode: 'extend', until: '', lifetime: false };
      uvApplyUser(res.user, res.admin);
      uvToast('Premium сохранён');
    } else if (action === 'revoke') {
      if (!confirm('Отозвать Premium у «' + name + '»?')) return;
      busy(true);
      var rv = await uvFetch('/api/admin/users/revoke-premium', { userId: id });
      uvApplyUser(rv.user, rv.admin);
      uvToast('Premium отозван');
    } else if (action === 'sessions') {
      if (!confirm('Завершить все сессии «' + name + '»? Приложение попросит войти заново.')) return;
      busy(true);
      var rs = await uvFetch('/api/admin/users/revoke-sessions', { userId: id });
      uvApplyUser(null, rs.admin);
      uvToast('Сессии завершены');
    } else if (action === 'suspect') {
      busy(true);
      var sp = await uvFetch('/api/admin/users/suspect', { userId: id, suspect: !u.suspect });
      uvApplyUser(sp.user, sp.admin);
    } else if (action === 'delete') {
      var typed = prompt('Аккаунт, прогресс и заметки будут удалены без возможности восстановления.\nДля подтверждения введите: удалить');
      if (typed == null) return;
      if (typed.trim().toLowerCase() !== 'удалить') { uvToast('Не удалено: подтверждение не совпало', true); return; }
      busy(true);
      await uvFetch('/api/admin/users/delete', { userId: id });
      uvState.users = uvState.users.filter(function (x) { return x.id !== id; });
      uvState.detail = null;
      uvClose();
      uvRenderList();
      uvToast('Аккаунт удалён');
    }
  } catch (err) {
    uvToast('Не получилось: ' + err.message, true);
  } finally { busy(false); }
}

var uvNoteTimer = null;
function uvSaveNoteSoon() {
  var state = document.getElementById('uv-note-state');
  if (state) state.textContent = 'Сохранение…';
  clearTimeout(uvNoteTimer);
  var id = uvState.openId;
  uvNoteTimer = setTimeout(async function () {
    var el = document.getElementById('uv-note');
    if (!el || uvState.openId !== id) return;
    try {
      var res = await uvFetch('/api/admin/users/note', { userId: id, note: el.value });
      if (uvState.detail && uvState.openId === id) uvState.detail.admin = res.admin;
      var st = document.getElementById('uv-note-state');
      if (st) st.textContent = 'Сохранено';
    } catch (err) {
      var st2 = document.getElementById('uv-note-state');
      if (st2) st2.innerHTML = '<span style="color:var(--danger)">Не сохранено: ' + uvEsc(err.message) + '</span>';
    }
  }, 700);
}

(function () {
  var view = document.getElementById('users-view');
  if (!view) return;
  var searchTimer = null;
  document.getElementById('uv-search').addEventListener('input', function (e) {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(function () { uvState.query = e.target.value; uvState.limit = 50; uvRenderList(); }, 120);
  });
  document.getElementById('uv-app').addEventListener('change', function (e) { uvState.app = e.target.value; uvState.limit = 50; uvRenderList(); });
  document.getElementById('uv-sort').addEventListener('change', function (e) { uvState.sort = e.target.value; uvRenderList(); });
  document.getElementById('uv-export').addEventListener('click', uvExportCsv);
  document.getElementById('refresh-users-btn').addEventListener('click', loadUsersList);

  view.addEventListener('click', function (e) {
    var t = e.target;
    var f = t.closest('#uv-filter button');
    if (f) { uvState.filter = f.dataset.filter; uvState.limit = 50; uvRenderList(); return; }
    var k = t.closest('[data-kpi]');
    if (k) { uvState.filter = k.dataset.kpi; uvState.limit = 50; uvRenderList(); return; }
    if (t.closest('#uv-more-btn')) { uvState.limit += 50; uvRenderList(); return; }
    var copy = t.closest('[data-copy]');
    if (copy) {
      e.stopPropagation();
      var text = copy.dataset.copy;
      (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject()).then(function () {
        copy.textContent = 'скопировано'; setTimeout(function () { copy.textContent = 'копировать'; }, 1500);
      }).catch(function () { prompt('Скопируйте:', text); });
      return;
    }
    var row = t.closest('.uv-row[data-user]');
    if (row) { uvOpen(row.dataset.user); window.scrollTo(0, 0); return; }
    var preset = t.closest('#uv-presets button');
    if (preset) {
      var g = uvState.grant;
      g.lifetime = preset.dataset.days === 'lifetime';
      if (!g.lifetime) g.days = parseInt(preset.dataset.days, 10);
      g.until = '';
      document.querySelectorAll('#uv-presets button').forEach(function (b) { b.classList.toggle('active', b === preset); });
      var di = document.getElementById('uv-days'); if (di) di.value = '';
      var ui = document.getElementById('uv-until'); if (ui) ui.value = '';
      uvUpdateGrantPreview();
      return;
    }
    var mode = t.closest('#uv-mode button');
    if (mode) {
      uvState.grant.mode = mode.dataset.mode;
      document.querySelectorAll('#uv-mode button').forEach(function (b) { b.classList.toggle('active', b === mode); });
      uvUpdateGrantPreview();
      return;
    }
    var act = t.closest('[data-uv]');
    if (act) {
      if (act.dataset.uv === 'back') uvClose();
      else uvAction(act.dataset.uv, act);
    }
  });
  view.addEventListener('input', function (e) {
    var g = uvState.grant;
    if (e.target.id === 'uv-days') {
      g.lifetime = false; g.until = ''; g.days = parseInt(e.target.value, 10) || 0;
      var ui = document.getElementById('uv-until'); if (ui) ui.value = '';
      document.querySelectorAll('#uv-presets button').forEach(function (b) { b.classList.toggle('active', parseInt(b.dataset.days, 10) === g.days); });
      uvUpdateGrantPreview();
    } else if (e.target.id === 'uv-until') {
      g.lifetime = false; g.until = e.target.value;
      var di = document.getElementById('uv-days'); if (di) di.value = '';
      document.querySelectorAll('#uv-presets button').forEach(function (b) { b.classList.remove('active'); });
      uvUpdateGrantPreview();
    } else if (e.target.id === 'uv-note') {
      uvSaveNoteSoon();
    }
  });
  document.addEventListener('keydown', function (e) {
    if (typeof currentFeature === 'undefined' || currentFeature !== 'users') return;
    var typing = /INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || '');
    if (e.key === '/' && !typing && !uvState.openId) { e.preventDefault(); document.getElementById('uv-search').focus(); }
    if (e.key === 'Escape' && uvState.openId && !typing && !document.querySelector('.sc-modal-bg, .admin-dialog-backdrop')) uvClose();
  });
  window.addEventListener('popstate', uvSyncRoute);
})();
`;
