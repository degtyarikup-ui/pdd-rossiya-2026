// ─────────────────────────────────────────────────────────────────────────────
// Раздел «Автопостинг» в админке: разметка и клиентский скрипт.
//
// Живёт отдельным файлом, а не внутри гигантских строк ADMIN_HTML_HEAD /
// ADMIN_CLIENT_JS: те собраны как экранированные однострочные литералы, и
// править их руками нельзя. renderAdminPage() вставляет этот раздел по якорям.
//
// Принцип экрана: сверху — состояние одной строкой, дальше расписание, дальше
// очередь с массовыми действиями. Всё, что нужно один раз (ключи Google,
// токены), спрятано в «Подключение» и раскрывается по клику.
// ─────────────────────────────────────────────────────────────────────────────

export const SOCIAL_NAV_HTML = `
      <button class="nav-item" data-feature="social">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
        <span>Автопостинг</span>
      </button>
`;

export const SOCIAL_VIEW_HTML = `
<div id="social-view" style="display:none;">

  <style>
    .sc-chip { display:inline-flex; align-items:center; gap:6px; padding:5px 11px; border-radius:8px;
               font-size:12.5px; font-weight:600; background:var(--surface-gray); color:var(--text-muted); }
    .sc-chip.ok { background:var(--success-subtle); color:var(--success); }
    .sc-chip.bad { background:var(--danger-subtle); color:var(--danger); }
    .sc-row { display:flex; align-items:center; gap:12px; padding:11px 14px; border-radius:12px;
              background:#fff; box-shadow:0 1px 2px rgba(0,0,0,0.04); }
    .sc-row.sel { box-shadow:0 0 0 2px var(--primary) inset; }
    .sc-name { font-size:13px; font-weight:600; flex:1; min-width:180px; overflow:hidden;
               text-overflow:ellipsis; white-space:nowrap; }
    .sc-dot { font-size:11px; font-weight:700; letter-spacing:0.3px; }
    .sc-input { background:#fff; border:1px solid #E5E7EB; border-radius:8px; padding:7px 10px;
                font-size:13px; color:var(--text); font-family:inherit; }
    .sc-tabs { display:flex; gap:6px; }
    .sc-tab { padding:6px 13px; border-radius:8px; font-size:13px; font-weight:600; cursor:pointer;
              border:none; background:var(--surface-gray); color:var(--text-muted); }
    .sc-tab.active { background:var(--primary-subtle); color:var(--primary); }
    .sc-bulk { display:flex; gap:7px; align-items:center; flex-wrap:wrap; row-gap:7px;
               padding:9px 11px; border-radius:12px; margin-bottom:14px; }
    .sc-bulk .btn-action { height:32px; padding:0 11px; font-size:12.5px; white-space:nowrap; }
    .sc-count { display:inline-flex; align-items:center; height:32px; padding:0 12px; border-radius:8px;
                background:var(--primary); color:#fff; font-size:12.5px; font-weight:700; white-space:nowrap; }
    .sc-sep { width:1px; height:20px; background:#D7DDE6; margin:0 3px; flex-shrink:0; }
    .sc-bulk .sc-danger { color:var(--danger); border-color:#FBD5CC; }
    .sc-bulk .sc-danger:hover { background:var(--danger-subtle); color:var(--danger); }
    .sc-hint { font-size:12px; color:var(--text-muted); }
    .sc-modal-bg { position:fixed; inset:0; background:rgba(15,23,42,0.5); z-index:9999;
                   display:flex; align-items:center; justify-content:center; padding:20px; }
    .sc-modal { background:#fff; border-radius:18px; padding:22px 24px; width:100%; max-width:460px;
                box-shadow:0 24px 60px rgba(0,0,0,0.24); max-height:90vh; overflow:auto; }
    .sc-modal.wide { max-width:820px; }

    /* Карточки роликов */
    .sc-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(170px,1fr)); gap:14px; }
    .sc-card { background:#fff; border-radius:14px; overflow:hidden; box-shadow:0 1px 3px rgba(0,0,0,0.06);
               transition:box-shadow .15s, transform .15s; position:relative; }
    .sc-card:hover { box-shadow:0 8px 24px rgba(0,0,0,0.12); transform:translateY(-2px); }
    .sc-card.sel { box-shadow:0 0 0 2px var(--primary), 0 8px 20px rgba(5,116,248,0.18); }
    .sc-poster { position:relative; aspect-ratio:9/16; background:#11131A; cursor:pointer;
                 display:flex; align-items:center; justify-content:center; overflow:hidden; }
    .sc-poster img { width:100%; height:100%; object-fit:cover; }
    .sc-play { position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
               background:rgba(10,12,18,0.25); opacity:0; transition:opacity .15s; }
    .sc-poster:hover .sc-play { opacity:1; }
    .sc-play span { width:44px; height:44px; border-radius:50%; background:rgba(255,255,255,0.94);
                    display:flex; align-items:center; justify-content:center; color:#11131A; }
    .sc-pick { position:absolute; top:8px; left:8px; z-index:2; width:20px; height:20px; cursor:pointer; }
    .sc-when { position:absolute; left:8px; right:8px; bottom:8px; background:rgba(10,12,18,0.72);
               color:#fff; border-radius:8px; padding:4px 7px; font-size:11px; font-weight:600;
               display:flex; align-items:center; gap:5px; backdrop-filter:blur(4px); }
    .sc-body { padding:9px 11px 11px; }
    .sc-title { font-size:12px; font-weight:600; line-height:1.35; height:32px; overflow:hidden; }
    .sc-meta { display:flex; align-items:center; gap:6px; margin-top:7px; }
    .sc-pill { display:inline-flex; align-items:center; gap:4px; padding:2px 7px; border-radius:6px;
               font-size:10.5px; font-weight:700; background:var(--surface-gray); color:var(--text-muted); }
    .sc-pill.ok { background:var(--success-subtle); color:var(--success); }
    .sc-pill.bad { background:var(--danger-subtle); color:var(--danger); }
    .sc-ico { width:15px; height:15px; flex-shrink:0; }
    #social-view .btn-action { display:inline-flex; align-items:center; gap:6px; }
    #social-view .card-title svg { color:var(--primary); }
    .sc-err { margin-top:7px; font-size:10.5px; line-height:1.35; color:var(--danger);
              background:var(--danger-subtle); border-radius:7px; padding:5px 7px;
              display:-webkit-box; -webkit-line-clamp:3; -webkit-box-orient:vertical; overflow:hidden; }
    .sc-retries { display:flex; gap:5px; margin-top:8px; }
    .sc-retries .btn-action { height:26px; padding:0 8px; font-size:11px; flex:1; justify-content:center; }
    .sc-empty { color:var(--text-muted); text-align:center; padding:34px; background:#F8F9FB; border-radius:14px; }

    /* Компактная библиотека с читаемыми статусами каждой площадки. */
    #social-view .card-head { margin-bottom:18px; flex-wrap:wrap; gap:12px; }
    #social-view .sc-actions { display:flex; gap:8px; flex-wrap:wrap; }
    #social-view .sc-connections-grid { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:12px; }
    #social-view .sc-connection { display:flex; align-items:center; gap:12px; background:var(--surface-gray); border-radius:12px; padding:14px 16px; min-width:0; }
    .sc-connection-logo { width:32px; height:32px; display:grid; place-items:center; flex-shrink:0; }
    .sc-connection-logo svg { width:25px; height:25px; }
    .sc-connection strong { display:block; font-size:12.5px; font-weight:600; }
    .sc-connection small { display:flex; align-items:center; gap:5px; font-size:11px; color:var(--text-muted); margin-top:3px; }
    .sc-connection small::before { content:''; width:5px; height:5px; border-radius:50%; background:currentColor; }
    .sc-connection small.ok { color:var(--success); }
    .sc-connection small.bad { color:var(--danger); }
    #sc-check-result:empty { display:none; }
    #sc-check-result:not(:empty) { margin-top:14px; }
    #social-view .sc-schedule-fields { display:flex; align-items:flex-end; gap:24px; flex-wrap:wrap; }
    #social-view .sc-targets { display:flex; gap:8px; flex-wrap:wrap; }
    .sc-target { display:inline-flex; align-items:center; gap:8px; border:0; border-radius:10px; padding:10px 12px; background:var(--surface-gray); color:var(--text-muted); font-size:12px; font-weight:550; cursor:pointer; min-height:38px; }
    .sc-target svg { width:16px; height:16px; }
    .sc-target-check { width:16px; height:16px; border-radius:50%; background:#fff; color:transparent; font-size:10px; display:grid; place-items:center; }
    .sc-target[aria-pressed="true"] { background:var(--primary-subtle); color:var(--primary); }
    .sc-target[aria-pressed="true"] .sc-target-check { background:var(--primary); color:#fff; }
    #social-view #sc-time { width:130px; min-height:38px; }
    #social-view .sc-save-group { display:flex; align-items:center; gap:12px; margin-left:auto; }
    #social-view .sc-schedule-foot { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-top:18px; padding-top:14px; border-top:1px solid var(--admin-divider); }
    .sc-switch { display:flex; align-items:center; gap:8px; cursor:pointer; }
    .sc-switch input { position:absolute; opacity:0; width:1px; height:1px; }
    .sc-switch>span { width:30px; height:18px; background:#D3D9E2; border-radius:12px; padding:3px; box-sizing:border-box; }
    .sc-switch>span::before { content:''; display:block; width:12px; height:12px; background:#fff; border-radius:50%; transition:transform .15s; }
    .sc-switch input:checked+span { background:var(--primary); }
    .sc-switch input:checked+span::before { transform:translateX(12px); }
    .sc-switch input:focus-visible+span { outline:2px solid var(--primary); outline-offset:3px; }
    .sc-switch b { font-size:11px; font-weight:500; color:var(--text-muted); }
    #social-view .sc-library-tools { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:14px; }
    #social-view #sc-search { width:260px; max-width:100%; }
    #social-view .sc-tabs { flex-wrap:wrap; }
    #social-view .sc-tabs span { opacity:.65; margin-left:5px; font-variant-numeric:tabular-nums; }
    #social-view .sc-bulk { background:var(--surface-gray); padding:8px; margin-bottom:8px; }
    #social-view .sc-count { background:transparent; color:var(--text); padding:0 6px; }
    #social-view .sc-bulk [data-extra] { position:relative; margin-left:auto; }
    .sc-menu { position:absolute; right:0; top:38px; z-index:5; min-width:190px; padding:6px; border-radius:12px; background:#fff; box-shadow:0 8px 32px #17223622; display:grid; gap:4px; }
    .sc-menu .btn-action { justify-content:flex-start; }
    #social-view .sc-video-list { display:grid; gap:2px; }
    #social-view .sc-card { display:grid; grid-template-columns:24px 68px minmax(130px,1fr) minmax(180px,.65fr) 140px 34px; align-items:center; gap:18px; padding:14px 10px; border-radius:12px; background:transparent; }
    #social-view .sc-card+.sc-card { border-top:1px solid var(--admin-divider)!important; }
    #social-view .sc-card:hover { background:#F8F9FB; }
    #social-view .sc-card.sel { background:var(--primary-subtle); }
    #social-view .sc-card.sel .sc-poster { opacity:1; }
    #social-view .sc-pick { position:static; width:17px; height:17px; margin:0; accent-color:var(--primary); }
    #social-view .sc-poster { border:0; padding:0; width:68px; aspect-ratio:9/16; border-radius:8px; }
    #social-view .sc-play { opacity:1; background:transparent; }
    #social-view .sc-play span { width:25px; height:25px; background:#FFFFFFDA; }
    #social-view .sc-body { padding:0; min-width:0; }
    #social-view .sc-title { display:block; border:0; padding:0; background:transparent; color:var(--text); text-align:left; height:auto; font-size:13px; font-weight:600; cursor:pointer; }
    #social-view .sc-file { margin-top:5px; font-size:11px; color:var(--text-muted); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    #social-view .sc-platforms { display:grid; gap:8px; justify-content:start; }
    #social-view .sc-platform { display:flex; align-items:center; gap:7px; font-size:11px; color:var(--text-muted); }
    #social-view .sc-platform svg { width:15px; height:15px; flex-shrink:0; }
    #social-view .sc-platform span { min-width:62px; color:var(--text); }
    #social-view .sc-platform small { font-size:10px; }
    #social-view .sc-platform.off { opacity:.45; }
    #social-view .sc-platform.ok small { color:var(--success); }
    #social-view .sc-platform.bad small { color:var(--danger); }
    #social-view .sc-date strong { display:block; font-size:12px; font-weight:550; }
    #social-view .sc-date small { display:block; color:var(--text-muted); font-size:11px; margin-top:4px; }
    #social-view .sc-edit { width:34px; height:34px; padding:0; justify-content:center; }
    #social-view .sc-more { margin:18px auto 0; }
    #social-view .sc-more[hidden] { display:none; }
    .sc-modal textarea.sc-input { background:var(--surface-gray); border:0; border-radius:10px; padding:10px 12px; }
    .sc-modal .sc-dialog-title { margin:0 0 18px; font-size:18px; font-weight:600; letter-spacing:-.3px; }
    .sc-modal .sc-targets { display:flex; gap:8px; flex-wrap:wrap; }
    .sc-modal .sc-dialog-error { color:var(--danger); font-size:12px; margin-top:12px; }
    .sc-modal .sc-dialog-error:empty { display:none; }
    .sc-modal .sc-preview-content { display:grid; grid-template-columns:210px minmax(0,1fr); gap:24px; }
    @media(max-width:1100px) {
      #social-view .sc-card { grid-template-columns:20px 60px minmax(100px,1fr) 175px 30px; gap:12px; }
      #social-view .sc-poster { width:60px; grid-row:1/3; }
      #social-view .sc-card>.sc-pick { grid-row:1/3; }
      #social-view .sc-date { grid-column:3/5; grid-row:2; display:flex; align-items:center; gap:8px; }
      #social-view .sc-date small { margin:0; }
      #social-view .sc-edit { grid-column:5; grid-row:1/3; }
    }
    @media(max-width:760px) {
      #social-view .sc-connections-grid { gap:6px; }
      #social-view .sc-connection { padding:12px 8px; gap:7px; flex-direction:column; align-items:flex-start; }
      #social-view .sc-connection-logo { width:24px; height:24px; }
      #social-view .sc-connection strong { font-size:11px; }
      #social-view .sc-connection small { font-size:9.5px; }
      #social-view .sc-schedule-fields { gap:16px; }
      #social-view .sc-save-group { margin-left:0; flex:1; justify-content:flex-end; }
      #social-view .sc-destinations { flex-basis:100%; }
      #social-view .sc-library-head { align-items:flex-start; }
      #social-view .sc-card { grid-template-columns:18px 56px minmax(0,1fr) 30px; gap:10px; padding:14px 4px; }
      #social-view .sc-poster { width:56px; grid-row:1/4; }
      #social-view .sc-card>.sc-pick { grid-row:1/4; }
      #social-view .sc-platforms { grid-column:3; grid-row:2; gap:4px; }
      #social-view .sc-platform { font-size:10px; gap:5px; }
      #social-view .sc-platform span { min-width:58px; }
      #social-view .sc-date { grid-column:3; grid-row:3; display:block; }
      #social-view .sc-date strong { font-size:11px; }
      #social-view .sc-date small { font-size:10px; }
      #social-view .sc-edit { grid-column:4; grid-row:1/4; }
      #social-view .sc-title { font-size:12px; }
      #social-view .sc-file { display:none; }
      #social-view .sc-library-tools { align-items:flex-start; }
      #social-view .sc-bulk { gap:6px; }
      #social-view .sc-bulk .btn-action { font-size:11px; padding:0 8px; }
      .sc-modal .sc-preview-content { grid-template-columns:minmax(0,1fr); }
      .sc-modal .sc-preview-media { max-width:160px; margin:auto; }
    }
  </style>

  <div class="card sc-connections">
    <div class="card-head">
      <div class="card-title">Подключения</div>
      <div class="sc-actions">
        <button class="btn-action" id="sc-check">Проверить доступ</button>
        <button class="btn-action" id="sc-toggle-conn" aria-expanded="false" aria-controls="sc-conn">Настроить</button>
      </div>
    </div>
    <div id="sc-status" class="sc-connections-grid"></div>
    <div id="sc-check-result" aria-live="polite"></div>
    <div id="sc-conn" style="display:none; margin-top:18px; padding-top:18px; border-top:1px solid #F1F2F6;">
      <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(230px,1fr)); gap:12px;">
        <div class="form-group"><label class="form-label">Google Client ID</label>
          <input type="text" id="sc-client-id" class="sc-input"></div>
        <div class="form-group"><label class="form-label">Client Secret</label>
          <input type="password" id="sc-client-secret" class="sc-input"></div>
        <div class="form-group"><label class="form-label">Refresh token</label>
          <input type="password" id="sc-refresh-token" class="sc-input"></div>
        <div class="form-group"><label class="form-label">Instagram токен</label>
          <input type="password" id="sc-ig-token" class="sc-input"></div>
        <div class="form-group"><label class="form-label">Папка Google Диска</label>
          <input type="text" id="sc-folder" class="sc-input" placeholder="ссылка на папку"></div>
      </div>
      <div style="display:flex; gap:8px; margin-top:12px; align-items:center;">
        <button class="btn-action btn-primary" id="sc-save-conn">Сохранить</button>
        <span class="sc-hint">Пустые поля сохраняют текущие значения</span>
      </div>
    </div>
  </div>

  <div class="card sc-schedule">
    <div class="card-head">
      <div class="card-title">Автопубликация</div>
      <label class="sc-switch"><input type="checkbox" id="sc-active"><span></span><b id="sc-active-label">Включена</b></label>
    </div>
    <div class="sc-schedule-fields">
      <div class="form-group sc-destinations"><label class="form-label">Соцсети · новые ролики и очередь</label>
        <div class="sc-targets" role="group" aria-label="Соцсети очереди">
          <button class="sc-target" id="sc-t-ig" data-on="0" aria-pressed="false">Instagram<span class="sc-target-check">✓</span></button>
          <button class="sc-target" id="sc-t-yt" data-on="0" aria-pressed="false">YouTube<span class="sc-target-check">✓</span></button>
        </div>
      </div>
      <div class="form-group"><label class="form-label" for="sc-time">Время при назначении дат · МСК</label>
        <input type="time" id="sc-time" class="sc-input" required></div>
      <div class="sc-save-group">
        <span id="sc-save-state" class="sc-hint" role="status"></span>
        <button class="btn-action btn-primary" id="sc-save-schedule" disabled>Сохранить</button>
      </div>
    </div>
    <div class="sc-schedule-foot"><span class="sc-hint" id="sc-next"></span>
      <button class="btn-action" id="sc-plan">Расставить даты…</button></div>
  </div>

  <div class="card sc-library">
    <div class="card-head sc-library-head">
      <div class="sc-tabs" role="tablist" aria-label="Статус видео">
        <button class="sc-tab active" role="tab" aria-selected="true" data-filter="queued">В очереди <span id="sc-n-q">0</span></button>
        <button class="sc-tab" role="tab" aria-selected="false" data-filter="published">Опубликовано <span id="sc-n-p">0</span></button>
        <button class="sc-tab" role="tab" aria-selected="false" data-filter="failed">Ошибки <span id="sc-n-f">0</span></button>
      </div>
      <div class="sc-actions">
        <button class="btn-action" id="sc-refresh" aria-label="Обновить видео">Обновить</button>
        <button class="btn-action btn-primary" id="sc-sync">Забрать с Диска</button>
      </div>
    </div>
    <div class="sc-library-tools"><input type="search" id="sc-search" class="sc-input" placeholder="Найти видео" aria-label="Найти видео"><span class="sc-hint" id="sc-found"></span></div>
    <div id="sc-bulk" style="display:none;" class="sc-bulk"></div>
    <div id="sc-list" class="sc-video-list"></div>
    <button class="btn-action sc-more" id="sc-more" hidden>Показать ещё</button>
  </div>

  <details class="admin-disclosure">
    <summary><span>Журнал</span><span class="sc-hint">МСК · <b id="sc-clock">—</b></span></summary>
    <div class="admin-disclosure-body">
    <div id="sc-log" style="display:grid; gap:5px; font-size:12.5px;"></div>
    </div>
  </details>

</div>
`;

export const SOCIAL_CLIENT_JS = `
// ────────────────────── Автопостинг (Instagram + YouTube) ──────────────────────

var scState = { accounts: [], posts: [], settings: {}, log: [] };
var scFilter = 'queued';
var scSelected = {};
var scBusy = {};
var scScheduleDirty = false;
var scLimit = 24;
var scQuery = '';
var scChecks = {};

function scEsc(v) {
  return String(v == null ? '' : v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function scToast(msg, bad) {
  var b = document.createElement('div');
  b.style.cssText = 'position:fixed;right:20px;bottom:20px;z-index:10000;padding:12px 16px;border-radius:12px;'
    + 'font-size:13px;font-weight:600;color:#fff;max-width:400px;box-shadow:0 10px 30px rgba(0,0,0,0.16);background:'
    + (bad ? 'var(--danger)' : 'var(--success)');
  b.textContent = msg;
  document.body.appendChild(b);
  setTimeout(function () { b.remove(); }, bad ? 7000 : 3000);
}

async function scApi(path, body) {
  var opts = body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {};
  var res = await fetch('/api/admin/social/' + path, opts);
  if (res.status === 401) { checkAuthAndLoad(); throw new Error('нужно войти заново'); }
  var data = await res.json().catch(function () { return {}; });
  if (!res.ok) throw new Error(data.error || ('ошибка сервера ' + res.status));
  if (body) document.dispatchEvent(new CustomEvent('pdd:publications-changed'));
  return data;
}

// Дата в МСК: сервер отдаёт UTC, человеку показываем московское время.
function scMsk(iso) {
  if (!iso) return null;
  var d = new Date(new Date(iso).getTime() + 3 * 3600000);
  return d.toISOString().slice(0, 16).replace('T', ' ');
}
function scMskShort(iso) {
  var s = scMsk(iso);           // 2026-09-02 19:00
  if (!s) return '';
  return s.slice(8, 10) + '.' + s.slice(5, 7) + ' ' + s.slice(11);   // 02.09 19:00
}

async function loadSocial() {
  try {
    scState = await scApi('state');
    document.getElementById('sc-clock').textContent = scState.serverTimeMsk || '—';
    scRenderStatus();
    scRenderSchedule();
    scRenderList();
    scRenderLog();
  } catch (e) { scToast('Не загрузилось: ' + e.message, true); }
}

function scAccount() { return (scState.accounts || [])[0] || null; }

function scRenderStatus() {
  var s = scState.settings || {};
  var a = scAccount();
  var posts = scState.posts || [];
  var configured = { drive: !!(a && a.driveFolderId && s.driveMode !== 'none'), instagram: !!(a && a.hasInstagramToken && a.instagramAccountId), youtube: !!(s.youtubeReady || (a && a.hasYoutubeRefreshToken)) };
  var names = { drive: 'Google Диск', instagram: 'Instagram', youtube: 'YouTube' };
  document.getElementById('sc-status').innerHTML = ['drive', 'instagram', 'youtube'].map(function (key) {
    var check = scChecks[key];
    var label = check ? (check.ok ? 'Доступ проверен' : 'Ошибка доступа') : (configured[key] ? 'Настроен' : 'Не подключён');
    var cls = check ? (check.ok ? 'ok' : 'bad') : '';
    var icon = typeof BRAND_SVGS !== 'undefined' ? BRAND_SVGS[key === 'drive' ? 'google' : key] : '';
    if (!icon && key === 'instagram') icon = SC_ICONS.ig;
    return '<div class="sc-connection"><span class="sc-connection-logo">' + (icon || '') + '</span><div><strong>' + names[key] + '</strong><small class="' + cls + '">' + label + '</small></div></div>';
  }).join('');

  var conn = document.getElementById('sc-conn');
  var idEl = document.getElementById('sc-client-id');
  if (document.activeElement !== idEl) idEl.value = s.googleClientId || '';
  document.getElementById('sc-client-secret').placeholder = s.hasGoogleClientSecret ? 'задан' : 'не задан';
  document.getElementById('sc-refresh-token').placeholder = s.hasGoogleRefreshToken ? 'задан' : 'не задан';
  document.getElementById('sc-ig-token').placeholder = (a && a.hasInstagramToken) ? 'задан' : 'не задан';
  var f = document.getElementById('sc-folder');
  if (a && document.activeElement !== f && !f.value) f.value = a.driveFolderId || '';
}

function scRenderSchedule() {
  var a = scAccount();
  if (!a) return;
  if (!scScheduleDirty) {
    document.getElementById('sc-time').value = a.postTime || '19:00';
    document.getElementById('sc-active').checked = a.active !== false;
    scSetToggle('sc-t-ig', (a.targets || []).indexOf('instagram') !== -1);
    scSetToggle('sc-t-yt', (a.targets || []).indexOf('youtube') !== -1);
  }
  document.getElementById('sc-active-label').textContent = document.getElementById('sc-active').checked ? 'Включена' : 'На паузе';
  var queued = (scState.posts || []).filter(function (p) { return p.status === 'queued'; });
  var scheduled = queued.filter(function (p) { return p.scheduledAt; }).sort(function (x, y) { return x.scheduledAt.localeCompare(y.scheduledAt); });
  document.getElementById('sc-next').textContent = a.active === false ? 'Автопубликация на паузе' : scheduled.length ? 'Ближайшая дата · ' + scMskShort(scheduled[0].scheduledAt) + ' МСК' : 'Без даты · ожидают планирования';
}

function scSetToggle(id, on) {
  var el = document.getElementById(id);
  el.dataset.on = on ? '1' : '0';
  el.setAttribute('aria-pressed', on ? 'true' : 'false');
  el.classList.toggle('active', !!on);
}

function scTargetsOf(p) {
  var a = (scState.accounts || []).find(function (a) { return a.id === p.accountId; }) || scAccount() || {};
  return p.targets && p.targets.length ? p.targets : (a.targets || ['instagram', 'youtube']);
}
function scCanEditTargets(p) { return ['queued', 'failed'].indexOf(p.status) !== -1 && p.instagramStatus !== 'processing' && p.youtubeStatus !== 'processing'; }
function scScheduleChanged() {
  scScheduleDirty = true;
  document.getElementById('sc-save-schedule').disabled = false;
  document.getElementById('sc-save-state').textContent = 'Есть изменения';
  scRenderSchedule();
}

function scPosts() {
  // Наверх — то, что прямо сейчас публикуется, следом неудачи: именно за ними
  // и следят после нажатия «Опубликовать сейчас».
  var weight = { processing: 0, failed: 1, queued: 2, published: 3 };
  return (scState.posts || []).filter(function (p) {
    if (scQuery && (String(p.title || '') + ' ' + String(p.fileName || '')).toLocaleLowerCase('ru').indexOf(scQuery) === -1) return false;
    if (scFilter === 'queued') return p.status === 'queued' || p.status === 'processing';
    if (scFilter === 'published') return p.status === 'published';
    return p.status === 'failed';
  }).sort(function (a, b) {
    var wa = weight[a.status] != null ? weight[a.status] : 4;
    var wb = weight[b.status] != null ? weight[b.status] : 4;
    if (wa !== wb) return wa - wb;
    if (a.scheduledAt && b.scheduledAt) return a.scheduledAt.localeCompare(b.scheduledAt);
    return String(a.fileName).localeCompare(String(b.fileName), 'ru', { numeric: true });
  });
}

// Небольшие иконки для карточек: рисуем строкой, чтобы не тащить шрифт.
var SC_ICONS = {
  play: '<svg class="sc-ico" viewBox="0 0 24 24" fill="currentColor" width="20" height="20"><path d="M8 5v14l11-7z"/></svg>',
  clock: '<svg class="sc-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 14"/></svg>',
  check: '<svg class="sc-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>',
  alert: '<svg class="sc-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M12 9v4"/><path d="M12 17h.01"/><circle cx="12" cy="12" r="9"/></svg>',
  ig: (typeof BRAND_SVGS !== 'undefined' && BRAND_SVGS && BRAND_SVGS.instagram) ? BRAND_SVGS.instagram : '<svg class="sc-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="3.6"/><circle cx="17.5" cy="6.5" r="1.1" fill="currentColor" stroke="none"/></svg>',
  yt: (typeof BRAND_SVGS !== 'undefined' && BRAND_SVGS && BRAND_SVGS.youtube) ? BRAND_SVGS.youtube : '<svg class="sc-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="5" width="20" height="14" rx="4"/><polygon points="11,9.2 15,12 11,14.8" fill="currentColor" stroke="none"/></svg>',
  film: '<svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="#3A3F4B" stroke-width="1.6"><rect x="2" y="2" width="20" height="20" rx="3"/><line x1="7" y1="2" x2="7" y2="22"/><line x1="17" y1="2" x2="17" y2="22"/><line x1="2" y1="12" x2="22" y2="12"/></svg>'
};

function scPrettyName(fileName) {
  return String(fileName || '').replace(/\.[^.]+$/, '').replace(/^\d+_/, '').replace(/[_-]+/g, ' ');
}

// Кнопка повтора рисуется отдельно для каждой площадки: если ролик ушёл в
// Instagram, но не на YouTube, повторять нужно только YouTube — иначе в ленте
// появится дубль.
function scRetryButtons(p) {
  if (p.status === 'published' || p.status === 'processing') return '';
  var targets = scTargetsOf(p);
  var out = [];
  if (targets.indexOf('instagram') !== -1 && p.instagramStatus !== 'published' && p.instagramStatus !== 'processing') {
    out.push('<button class="btn-action sc-retry" onclick="scRetry(event, \\'' + p.id + '\\', \\'instagram\\')">'
      + SC_ICONS.ig + 'Повторить</button>');
  }
  if (targets.indexOf('youtube') !== -1 && p.youtubeStatus !== 'published' && p.youtubeStatus !== 'processing') {
    out.push('<button class="btn-action sc-retry" onclick="scRetry(event, \\'' + p.id + '\\', \\'youtube\\')">'
      + SC_ICONS.yt + 'Повторить</button>');
  }
  // Пока ролик просто ждёт очереди, кнопки повтора не нужны — только при сбое.
  if (p.status !== 'failed') return '';
  return '<div class="sc-retries">' + out.join('') + '</div>';
}

window.scRetry = async function (ev, id, platform) {
  ev.stopPropagation();
  var key = id + ':' + platform;
  if (scBusy[key]) return;
  scBusy[key] = true;
  if (ev.currentTarget) ev.currentTarget.disabled = true;
  try {
    var res = await scApi('posts/publish-platform', { id: id, platform: platform });
    if (res.ok === false) throw new Error(res.message || res.error || 'не получилось');
    scToast(res.message || 'Запустил');
    await loadSocial();
  } catch (e) {
    scToast('Не удалось запустить: ' + e.message, true);
    return;
  } finally {
    delete scBusy[key];
    if (ev.currentTarget && ev.currentTarget.isConnected) ev.currentTarget.disabled = false;
  }
  var ticks = 0;
  var timer = setInterval(async function () {
    ticks += 1;
    await loadSocial();
    var post = (scState.posts || []).find(function (x) { return x.id === id; });
    if (ticks > 40 || !post || post.status !== 'processing') clearInterval(timer);
  }, 15000);
};

function scRenderList() {
  var all = scState.posts || [];
  document.getElementById('sc-n-q').textContent = all.filter(function (p) { return p.status === 'queued' || p.status === 'processing'; }).length;
  document.getElementById('sc-n-p').textContent = all.filter(function (p) { return p.status === 'published'; }).length;
  document.getElementById('sc-n-f').textContent = all.filter(function (p) { return p.status === 'failed'; }).length;

  var list = scPosts();
  var box = document.getElementById('sc-list');
  document.getElementById('sc-found').textContent = scQuery ? 'Найдено: ' + list.length : '';
  document.getElementById('sc-more').hidden = list.length <= scLimit;
  var visibleIds = list.map(function (p) { return p.id; });
  Object.keys(scSelected).forEach(function (id) { if (visibleIds.indexOf(id) === -1) delete scSelected[id]; });
  if (!list.length) {
    box.innerHTML = '<div class="sc-empty">' + (scQuery ? 'Видео не найдены' : scFilter === 'queued' ? 'В очереди пока нет видео' : scFilter === 'failed' ? 'Все публикации без ошибок' : 'Опубликованных видео пока нет') + '</div>';
    scRenderBulk();
    return;
  }
  box.innerHTML = list.slice(0, scLimit).map(function (p) {
    var targets = scTargetsOf(p);
    var platforms = ['instagram', 'youtube'].map(function (t) {
      var chosen = targets.indexOf(t) !== -1;
      var st = t === 'instagram' ? p.instagramStatus : p.youtubeStatus;
      var text = !chosen ? 'Не выбрано' : st === 'published' ? 'Опубликовано' : st === 'failed' ? 'Ошибка' : st === 'processing' ? 'Публикуется' : 'В очереди';
      var cls = !chosen ? ' off' : st === 'published' ? ' ok' : st === 'failed' ? ' bad' : '';
      return '<div class="sc-platform' + cls + '">' + (t === 'instagram' ? SC_ICONS.ig : SC_ICONS.yt) + '<span>' + (t === 'instagram' ? 'Instagram' : 'YouTube') + '</span><small>' + text + '</small></div>';
    }).join('');
    var a = (scState.accounts || []).find(function (a) { return a.id === p.accountId; }) || {};
    var date = p.status === 'published' ? (p.publishedAt ? scMskShort(p.publishedAt) : 'Опубликовано') : p.status === 'processing' ? 'Публикуется…' : p.status === 'failed' ? 'Нужен повтор' : p.scheduledAt ? scMskShort(p.scheduledAt) : 'Без даты';
    var sub = p.status === 'published' ? 'Опубликовано · МСК' : p.scheduledAt ? 'По дате · МСК' : a.active === false ? 'Автопубликация на паузе' : 'Ожидает планирования';
    return '<article class="sc-card' + (scSelected[p.id] ? ' sel' : '') + '" data-post="' + scEsc(p.id) + '">'
      + '<input type="checkbox" class="sc-pick" data-pick="' + scEsc(p.id) + '" aria-label="Выбрать ' + scEsc(p.title || scPrettyName(p.fileName)) + '"' + (scSelected[p.id] ? ' checked' : '') + '>'
      + '<button class="sc-poster" data-preview="' + scEsc(p.id) + '" aria-label="Смотреть ' + scEsc(p.title || scPrettyName(p.fileName)) + '">'
      + '<img src="/s/t/' + scEsc(p.streamToken) + '" loading="lazy" alt="" onerror="this.style.display=\\'none\\'">'
      + '<div class="sc-play"><span>' + SC_ICONS.play + '</span></div></button>'
      + '<div class="sc-body"><button class="sc-title" data-preview="' + scEsc(p.id) + '">' + scEsc(p.title || scPrettyName(p.fileName)) + '</button>'
      + '<div class="sc-file" title="' + scEsc(p.fileName) + '">' + scEsc(p.fileName) + '</div>'
      + (p.error ? '<div class="sc-err" title="' + scEsc(p.error) + '">' + scEsc(p.error) + '</div>' : '')
      + scRetryButtons(p) + '</div><div class="sc-platforms">' + platforms + '</div>'
      + '<div class="sc-date"><strong>' + scEsc(date) + '</strong><small>' + sub + '</small></div>'
      + '<button class="btn-action sc-edit" data-preview="' + scEsc(p.id) + '" aria-label="Открыть настройки ' + scEsc(p.title || scPrettyName(p.fileName)) + '">↗</button></article>';
  }).join('');
  box.querySelectorAll('[data-preview]').forEach(function (el) { el.onclick = function () { scPreview(el.dataset.preview); }; });

  box.querySelectorAll('[data-pick]').forEach(function (cb) {
    cb.onclick = function (e) { e.stopPropagation(); };
    cb.onchange = function () {
      scSelected[cb.dataset.pick] = cb.checked;
      cb.closest('.sc-card').classList.toggle('sel', cb.checked);
      scRenderBulk();
    };
  });
  scRenderBulk();
}

function scSelectAll(on) {
  scPosts().forEach(function (p) { scSelected[p.id] = on; });
  scRenderList();
}

function scPicked() {
  return Object.keys(scSelected).filter(function (k) { return scSelected[k]; });
}

// Иконки кнопок панели — рядом с текстом, одного размера с ним.
function scBtnIcon(path) {
  return '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor"'
    + ' stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + path + '</svg>';
}
var SC_BTN = {
  send: '<polygon points="22 2 15 22 11 13 2 9 22 2"/>',
  cal: '<rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>',
  text: '<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="14" y2="17"/>',
  done: '<polyline points="20 6 9 17 4 12"/>',
  back: '<polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>',
  clear: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
  trash: '<polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/>',
  pick: '<polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>'
};

function scRenderBulk() {
  var ids = scPicked();
  var bar = document.getElementById('sc-bulk');
  var total = scPosts().length;

  if (!ids.length) {
    bar.style.display = total ? 'flex' : 'none';
    bar.innerHTML = '<button class="btn-action" onclick="scSelectAll(true)">' + scBtnIcon(SC_BTN.pick) + 'Выбрать все · ' + total + '</button>';
    return;
  }
  var published = scFilter === 'published';
  bar.style.display = 'flex';
  bar.innerHTML = '<span class="sc-count">Выбрано · ' + ids.length + '</span>'
    + (published ? '' : '<button class="btn-action btn-primary" onclick="scPublishSelected()">' + scBtnIcon(SC_BTN.send) + 'Опубликовать</button>')
    + (published ? '' : '<button class="btn-action" id="sc-bulk-targets">Соцсети</button><button class="btn-action" onclick="scBulkDate()">' + scBtnIcon(SC_BTN.cal) + 'Дата</button>')
    + '<button class="btn-action" onclick="scBulkCaption()">Описание</button>'
    + '<details data-extra><summary class="btn-action">Ещё…</summary><div class="sc-menu">'
    + (published ? '<button class="btn-action" data-bulk="requeue">Вернуть в очередь</button>' : '<button class="btn-action" data-bulk="mark">Уже опубликовано</button><button class="btn-action" data-bulk="unschedule">Снять даты</button>')
    + '<button class="btn-action sc-danger" data-bulk="delete">Убрать из списка</button></div></details>'
    + '<button class="btn-action" onclick="scSelectAll(false)" aria-label="Снять выбор">×</button>';
  if (!published) bar.querySelector('#sc-bulk-targets').onclick = function () { scEditTargets(ids); };
  bar.querySelectorAll('[data-bulk]').forEach(function (el) { el.onclick = function () { scBulk(el.dataset.bulk); }; });
}

// Публикация выбранных без расписания — по очереди, пачками до пяти.
window.scPublishSelected = async function () {
  if (scScheduleDirty) { scToast('Сначала сохраните настройки соцсетей', true); document.getElementById('sc-save-schedule').focus(); return; }
  var ids = scPicked();
  if (!ids.length) return;
  if (!confirm(ids.length === 1
      ? 'Опубликовать ролик прямо сейчас?'
      : 'Опубликовать ' + ids.length + ' роликов? Уйдут по очереди, не больше пяти за раз.')) return;

  if (scBusy.publishSelected) return;
  scBusy.publishSelected = true;
  try {
    var res = await scApi('posts/publish-now', { ids: ids });
    if (!res.ok) throw new Error(res.message || res.error || 'не получилось');
    scToast(res.message + (res.skipped ? ' (остальные ' + res.skipped + ' — следующим заходом)' : ''));
    scSelected = {};
    await loadSocial();
  } catch (e) {
    scToast('Публикация не запущена: ' + e.message, true);
    return;
  } finally {
    scBusy.publishSelected = false;
  }

  // Instagram кодирует каждый ролик минуты — подтягиваем статусы сами.
  var ticks = 0;
  var timer = setInterval(async function () {
    ticks += 1;
    await loadSocial();
    var busy = (scState.posts || []).some(function (p) { return p.status === 'processing'; });
    if (!busy || ticks > 60) clearInterval(timer);
  }, 15000);
};

window.scBulk = async function (action) {
  var ids = scPicked();
  if (!ids.length) return;
  if (action === 'delete' && !confirm('Убрать ' + ids.length + ' роликов из очереди? Файлы на Диске останутся.')) return;
  await scApi('posts/bulk', { ids: ids, action: action });
  scSelected = {};
  scToast('Готово');
  await loadSocial();
};

window.scSetDate = async function (input) {
  var value = input.value ? input.value + ':00.000Z' : null;
  // Введено московское время — переводим в UTC перед отправкой.
  var iso = value ? new Date(new Date(value).getTime() - 3 * 3600000).toISOString() : null;
  await scApi('posts/update', { id: input.dataset.id, scheduledAt: iso });
  await loadSocial();
};

function scModal(html, onOk) {
  var previous = document.activeElement;
  var bg = document.createElement('div');
  bg.className = 'sc-modal-bg';
  bg.innerHTML = '<div class="sc-modal" role="dialog" aria-modal="true" tabindex="-1">' + html
    + '<div class="sc-dialog-error" role="alert"></div><div style="display:flex;gap:8px;margin-top:20px;justify-content:flex-end;">'
    + '<button class="btn-action" data-x>Закрыть</button><button class="btn-action btn-primary" data-ok>Сохранить</button></div></div>';
  var modal = bg.querySelector('.sc-modal');
  var title = modal.querySelector('.sc-dialog-title');
  if (title) { title.id = 'sc-dialog-title'; modal.setAttribute('aria-labelledby', title.id); }
  else modal.setAttribute('aria-label', 'Настройки видео');
  document.body.appendChild(bg);
  var close = function () { bg.querySelectorAll('video').forEach(function (v) { v.pause(); }); bg.remove(); if (previous && previous.isConnected) previous.focus(); };
  bg.querySelector('[data-x]').onclick = close;
  bg.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { e.preventDefault(); close(); }
    if (e.key !== 'Tab') return;
    var nodes = Array.from(modal.querySelectorAll('button:not(:disabled), input:not(:disabled), textarea:not(:disabled), a[href]')).filter(function (n) { return n.offsetParent !== null; });
    if (!nodes.length) { e.preventDefault(); return; }
    if (e.shiftKey && (document.activeElement === nodes[0] || document.activeElement === modal)) { e.preventDefault(); nodes[nodes.length - 1].focus(); }
    else if (!e.shiftKey && document.activeElement === nodes[nodes.length - 1]) { e.preventDefault(); nodes[0].focus(); }
  });
  bg.querySelector('[data-ok]').onclick = async function () {
    var btn = this;
    btn.disabled = true;
    try { if (await onOk(bg) !== false) close(); }
    catch (e) { bg.querySelector('.sc-dialog-error').textContent = e.message; }
    finally { btn.disabled = false; }
  };
  modal.focus();
  return bg;
}

function scTargetFields(targets, disabled) {
  return '<div class="sc-targets" role="group" aria-label="Соцсети ролика">' + ['instagram', 'youtube'].map(function (t) {
    return '<button class="sc-target" type="button" data-target="' + t + '" aria-pressed="' + (targets.indexOf(t) !== -1 ? 'true' : 'false') + '"' + (disabled ? ' disabled' : '') + '>'
      + (t === 'instagram' ? SC_ICONS.ig + 'Instagram' : SC_ICONS.yt + 'YouTube') + '<span class="sc-target-check">✓</span></button>';
  }).join('') + '</div>';
}
function scBindTargets(bg) {
  bg.querySelectorAll('[data-target]').forEach(function (el) { el.onclick = function () { el.setAttribute('aria-pressed', el.getAttribute('aria-pressed') === 'true' ? 'false' : 'true'); }; });
}
function scReadTargets(bg) {
  return Array.from(bg.querySelectorAll('[data-target][aria-pressed="true"]')).map(function (el) { return el.dataset.target; });
}
window.scEditTargets = function (ids) {
  var posts = (scState.posts || []).filter(function (p) { return ids.indexOf(p.id) !== -1 && scCanEditTargets(p); });
  if (!posts.length) { scToast('Площадки уже публикуемых роликов изменить нельзя', true); return; }
  var common = scTargetsOf(posts[0]);
  var bg = scModal('<h3 class="sc-dialog-title">Соцсети · ' + posts.length + '</h3>' + scTargetFields(common, false), async function (box) {
    var targets = scReadTargets(box);
    if (!targets.length) throw new Error('Выберите хотя бы одну соцсеть');
    var res = await scApi('posts/bulk', { ids: posts.map(function (p) { return p.id; }), action: 'targets', targets: targets });
    scToast('Соцсети сохранены · ' + res.changed);
    await loadSocial();
  });
  scBindTargets(bg);
};

window.scBulkDate = function (chosenIds) {
  var ids = chosenIds || scPicked();
  var now = new Date(Date.now() + 3 * 3600000 + 86400000).toISOString().slice(0, 10);
  var time = (scAccount() || {}).postTime || '19:00';
  scModal(
    '<div style="font-size:15px;font-weight:700;margin-bottom:14px;">Расставить ' + ids.length + ' роликов</div>'
    + '<div style="display:flex;gap:12px;flex-wrap:wrap;">'
    + '<div class="form-group"><label class="form-label">С какого дня</label><input type="date" id="sc-m-date" class="sc-input" value="' + now + '"></div>'
    + '<div class="form-group"><label class="form-label">Во сколько (МСК)</label><input type="time" id="sc-m-time" class="sc-input" value="' + time + '"></div>'
    + '<div class="form-group"><label class="form-label">Раз в N дней</label><input type="number" id="sc-m-every" class="sc-input" min="1" max="30" value="1" style="width:80px;"></div>'
    + '</div><div class="sc-hint" style="margin-top:10px;">Порядок — по имени файла.</div>',
    async function (bg) {
      var d = bg.querySelector('#sc-m-date').value;
      var t = bg.querySelector('#sc-m-time').value;
      var every = bg.querySelector('#sc-m-every').value;
      if (!d || !t) throw new Error('Укажите дату и время');
      var res = await scApi('posts/bulk', { ids: ids, action: 'schedule', startAt: d + 'T' + t, everyDays: every });
      scSelected = {};
      scToast('Расставлено: ' + (res.changed || 0));
      await loadSocial();
    }
  );
};

window.scBulkCaption = function () {
  var ids = scPicked();
  var acc = scAccount() || {};
  scModal(
    '<div style="font-size:15px;font-weight:700;margin-bottom:4px;">Описание для ' + ids.length + ' роликов</div>'
    + '<div class="sc-hint" style="margin-bottom:14px;">Один текст уходит и в подпись Instagram, и в описание YouTube. '
    + '<b>{title}</b> подставит название ролика.</div>'
    + '<div class="form-group"><label class="form-label">Заголовок YouTube</label>'
    + '<input type="text" id="sc-m-tpl" class="sc-input" value="' + scEsc(acc.titleTemplate || '{title}') + '"></div>'
    + '<div class="form-group" style="margin-top:12px;"><label class="form-label">Описание</label>'
    + '<textarea id="sc-m-cap" class="sc-input" style="width:100%;min-height:170px;">' + scEsc(acc.captionTemplate || '') + '</textarea></div>'
    + '<label style="display:flex;gap:8px;align-items:center;margin-top:12px;font-size:13px;cursor:pointer;">'
    + '<input type="checkbox" id="sc-m-tpl-save" checked> Запомнить как шаблон для новых роликов</label>',
    async function (box) {
      var caption = box.querySelector('#sc-m-cap').value;
      var titleTpl = box.querySelector('#sc-m-tpl').value;
      await scApi('posts/bulk', { ids: ids, action: 'caption', caption: caption, titleTemplate: titleTpl });
      if (box.querySelector('#sc-m-tpl-save').checked && acc.id) {
        await scApi('accounts', { account: { id: acc.id, captionTemplate: caption, titleTemplate: titleTpl } });
      }
      scSelected = {};
      scToast('Описание обновлено у ' + ids.length + ' роликов');
      await loadSocial();
    }
  );
};

window.scPreview = function (id) {
  var p = (scState.posts || []).find(function (x) { return x.id === id; });
  if (!p) return;
  var editable = scCanEditTargets(p);
  var when = p.scheduledAt ? scMsk(p.scheduledAt).replace(' ', 'T') : '';
  var links = '';
  if (p.instagramPermalink && p.instagramPermalink.startsWith('https://')) links += '<a href="' + scEsc(p.instagramPermalink) + '" target="_blank" rel="noopener" class="sc-pill ok">Instagram ↗</a> ';
  if (p.youtubePermalink && p.youtubePermalink.startsWith('https://')) links += '<a href="' + scEsc(p.youtubePermalink) + '" target="_blank" rel="noopener" class="sc-pill ok">YouTube ↗</a>';
  var save = async function (box) {
    var w = box.querySelector('#sc-m-when').value;
    var patch = { id: id, title: box.querySelector('#sc-m-title').value, caption: box.querySelector('#sc-m-cap2').value };
    if (editable) {
      patch.targets = scReadTargets(box);
      if (!patch.targets.length) throw new Error('Выберите хотя бы одну соцсеть');
      patch.scheduledAt = w ? new Date(new Date(w + ':00.000Z').getTime() - 3 * 3600000).toISOString() : null;
    }
    await scApi('posts/update', patch);
    await loadSocial();
  };
  var bg = scModal('<div class="sc-preview-content"><div class="sc-preview-media">'
    + '<video src="/s/v/' + scEsc(p.streamToken) + '" poster="/s/t/' + scEsc(p.streamToken) + '" controls playsinline preload="none" style="width:100%;aspect-ratio:9/16;background:#17191E;border-radius:12px;object-fit:cover;"></video>'
    + '<div style="margin-top:10px">' + links + '</div></div><div>'
    + '<h3 class="sc-dialog-title">' + scEsc(p.title || scPrettyName(p.fileName)) + '</h3>'
    + '<div class="form-group"><label class="form-label">Соцсети</label>' + scTargetFields(scTargetsOf(p), !editable) + '</div>'
    + '<div class="form-group" style="margin-top:16px"><label class="form-label" for="sc-m-title">Заголовок YouTube</label><input id="sc-m-title" class="sc-input" value="' + scEsc(p.title || '') + '"></div>'
    + '<div class="form-group" style="margin-top:12px"><label class="form-label" for="sc-m-cap2">Описание</label><textarea id="sc-m-cap2" class="sc-input" style="width:100%;min-height:110px">' + scEsc(p.caption || '') + '</textarea></div>'
    + '<div class="form-group" style="margin-top:12px"><label class="form-label" for="sc-m-when">Дата и время · МСК</label><input type="datetime-local" id="sc-m-when" class="sc-input" value="' + when + '"' + (!editable ? ' disabled' : '') + '></div>'
    + (editable ? '<div style="margin-top:18px"><button class="btn-action btn-primary" id="sc-preview-publish">' + (p.status === 'failed' ? 'Повторить публикацию' : 'Опубликовать сейчас') + '</button></div>' : '')
    + '</div></div>', async function (box) { await save(box); scToast('Сохранено'); });
  bg.querySelector('.sc-modal').classList.add('wide');
  scBindTargets(bg);
  if (editable) bg.querySelector('#sc-preview-publish').onclick = async function () {
    this.disabled = true;
    try { await save(bg); await scPublishNow(id); }
    catch (e) { bg.querySelector('.sc-dialog-error').textContent = e.message; }
    finally { this.disabled = false; }
  };
};

window.scOne = async function (id, action) {
  await scApi('posts/bulk', { ids: [id], action: action });
  document.querySelectorAll('.sc-modal-bg').forEach(function (m) { m.remove(); });
  scToast('Готово');
  await loadSocial();
};

window.scPublishNow = async function (id) {
  if (scScheduleDirty) { scToast('Сначала сохраните настройки соцсетей', true); return; }
  if (!confirm('Опубликовать прямо сейчас?')) return;
  var key = 'publish:' + id;
  if (scBusy[key]) return;
  scBusy[key] = true;
  try {
    var res = await scApi('posts/publish', { id: id });
    if (res.ok === false) throw new Error(res.message || res.error || 'не получилось');
    scToast(res.message || 'Публикация запущена');
    document.querySelectorAll('.sc-modal-bg').forEach(function (m) { m.remove(); });
    await loadSocial();
  } catch (e) {
    scToast('Публикация не запущена: ' + e.message, true);
    return;
  } finally {
    delete scBusy[key];
  }
  // Instagram кодирует ролик несколько минут — подтягиваем статус сами.
  var ticks = 0;
  var timer = setInterval(async function () {
    ticks += 1;
    await loadSocial();
    var p = (scState.posts || []).find(function (x) { return x.id === id; });
    if (ticks > 40 || !p || p.status !== 'processing') clearInterval(timer);
  }, 15000);
};

function scRenderLog() {
  var log = (scState.log || []).slice(0, 12);
  document.getElementById('sc-log').innerHTML = log.length ? log.map(function (e) {
    var color = e.level === 'error' ? 'var(--danger)' : (e.level === 'ok' ? 'var(--success)' : 'var(--text-muted)');
    return '<div style="display:flex;gap:10px;padding:5px 0;border-bottom:1px solid #F5F6F8;">'
      + '<span class="sc-hint" style="white-space:nowrap;">' + scMskShort(e.ts) + '</span>'
      + '<span style="color:' + color + ';">' + scEsc(e.message) + '</span></div>';
  }).join('') : '<div class="sc-hint">пока пусто</div>';
}

// ── обработчики ──

document.getElementById('sc-toggle-conn').onclick = function () {
  var c = document.getElementById('sc-conn');
  c.style.display = c.style.display === 'none' ? 'block' : 'none';
  this.setAttribute('aria-expanded', c.style.display !== 'none' ? 'true' : 'false');
};

document.getElementById('sc-save-conn').onclick = async function () {
  try {
    var ig = document.getElementById('sc-ig-token').value;
    var folder = document.getElementById('sc-folder').value;
    await scApi('settings', {
      googleClientId: document.getElementById('sc-client-id').value,
      googleClientSecret: document.getElementById('sc-client-secret').value,
      googleRefreshToken: document.getElementById('sc-refresh-token').value
    });
    var a = scAccount();
    if (ig || folder) {
      await scApi('accounts', { account: { id: a && a.id, instagramToken: ig, driveFolderId: folder || (a && a.driveFolderId) || '' } });
    }
    ['sc-client-secret', 'sc-refresh-token', 'sc-ig-token'].forEach(function (id) { document.getElementById(id).value = ''; });
    scToast('Сохранено');
    await loadSocial();
  } catch (e) { scToast('Ошибка: ' + e.message, true); }
};

document.getElementById('sc-check').onclick = async function () {
  this.disabled = true;
  var box = document.getElementById('sc-check-result');
  box.innerHTML = '<span class="sc-hint">проверяю…</span>';
  try {
    var res = await scApi('check', {});
    (res.checks || []).forEach(function (c) { var key = c.name.indexOf('Instagram') === 0 ? 'instagram' : c.name.indexOf('YouTube') === 0 ? 'youtube' : c.name.indexOf('Папка') === 0 ? 'drive' : null; if (key) scChecks[key] = c; });
    scRenderStatus();
    box.innerHTML = (res.checks || []).map(function (c) {
      return '<div style="font-size:12.5px;padding:5px 0;color:' + (c.ok ? 'var(--success)' : 'var(--danger)') + ';">'
        + (c.ok ? '✓ ' : '✕ ') + scEsc(c.name) + ' — <span style="color:var(--text);">' + scEsc(c.message) + '</span></div>';
    }).join('');
  } catch (e) { box.innerHTML = '<span style="color:var(--danger)">' + scEsc(e.message) + '</span>'; }
  finally { this.disabled = false; }
};

document.getElementById('sc-save-schedule').onclick = async function () {
  var a = scAccount();
  if (!a) { scToast('Сначала подключите папку с видео', true); return; }
  var targets = [];
  if (document.getElementById('sc-t-ig').dataset.on === '1') targets.push('instagram');
  if (document.getElementById('sc-t-yt').dataset.on === '1') targets.push('youtube');
  if (!targets.length) { scToast('Выберите хотя бы одну соцсеть', true); return; }
  var time = document.getElementById('sc-time');
  if (!time.reportValidity()) return;
  this.disabled = true;
  try {
    await scApi('accounts', { account: { id: a.id, postTime: time.value, targets: targets, active: document.getElementById('sc-active').checked }, applyToQueued: true });
    scScheduleDirty = false;
    document.getElementById('sc-save-state').textContent = 'Сохранено';
    scToast('Настройки и соцсети очереди сохранены');
    await loadSocial();
  } catch (e) { scToast('Не удалось сохранить: ' + e.message, true); this.disabled = false; }
};

document.getElementById('sc-plan').onclick = function () {
  var ids = (scState.posts || []).filter(function (p) { return p.status === 'queued'; }).map(function (p) { return p.id; });
  if (!ids.length) { scToast('Очередь пуста'); return; }
  scBulkDate(ids);
};

['sc-t-ig', 'sc-t-yt'].forEach(function (id) {
  var el = document.getElementById(id);
  el.insertAdjacentHTML('afterbegin', id === 'sc-t-ig' ? SC_ICONS.ig : SC_ICONS.yt);
  el.onclick = function () { scSetToggle(id, this.dataset.on !== '1'); scScheduleChanged(); };
});
document.getElementById('sc-time').oninput = scScheduleChanged;
document.getElementById('sc-active').onchange = scScheduleChanged;
document.getElementById('sc-search').oninput = function () { scQuery = this.value.trim().toLocaleLowerCase('ru'); scLimit = 24; scRenderList(); };
document.getElementById('sc-more').onclick = function () { scLimit += 24; scRenderList(); };

document.getElementById('sc-sync').onclick = async function () {
  scToast('Смотрю папку…');
  try {
    var res = await scApi('sync', {});
    var added = (res.results || []).reduce(function (s, r) { return s + (r.added || 0); }, 0);
    var bad = (res.results || []).filter(function (r) { return r.status === 'error'; });
    if (bad.length) scToast(bad[0].message, true);
    else scToast(added ? ('Добавлено: ' + added) : 'Новых роликов нет');
    await loadSocial();
  } catch (e) { scToast('Ошибка: ' + e.message, true); }
};

document.getElementById('sc-refresh').onclick = loadSocial;

document.querySelectorAll('#social-view .sc-tabs .sc-tab').forEach(function (tab) {
  tab.onclick = function () {
    document.querySelectorAll('#social-view .sc-tabs .sc-tab').forEach(function (t) { t.classList.remove('active'); });
    tab.classList.add('active');
    document.querySelectorAll('#social-view .sc-tabs .sc-tab').forEach(function (t) { t.setAttribute('aria-selected', t === tab ? 'true' : 'false'); });
    scFilter = tab.dataset.filter;
    scLimit = 24;
    scSelected = {};
    scRenderList();
  };
});

// ── Тумблер доступа старых сборок к ИИ (карточка в разделе «Управление ИИ») ──
// Живёт здесь, а не в основном скрипте админки: тот собран экранированной
// строкой внутри worker.js и правится только скриптами.
(function () {
  var aiView = document.getElementById('ai-view');
  if (!aiView) return;

  var card = document.createElement('details');
  card.className = 'admin-disclosure ai-access';
  card.innerHTML = '<summary>Доступ старых версий'
    + '<span id="ai-key-state"></span></summary><div class="admin-disclosure-body">'
    + '<label style="display:flex;gap:9px;align-items:flex-start;cursor:pointer;font-size:12px;">'
    + '<input type="checkbox" id="ai-legacy-toggle" style="margin-top:3px;">'
    + '<span>Разрешить доступ без ключа<br><span style="font-size:11px;color:var(--text-muted);">'
    + 'Для версий, выпущенных до появления ключа приложения.'
    + '</span></span></label></div>';
  aiView.appendChild(card);

  var toggle = card.querySelector('#ai-legacy-toggle');
  var state = card.querySelector('#ai-key-state');

  async function loadFlag() {
    try {
      var res = await fetch('/api/admin/ai/legacy');
      if (!res.ok) return;
      var data = await res.json();
      toggle.checked = data.open;
      state.textContent = data.hasAppKey ? 'ключ приложения задан' : 'ключ приложения не задан';
      state.style.color = data.hasAppKey ? 'var(--success)' : 'var(--danger)';
    } catch (e) { /* раздел мог ещё не открываться */ }
  }

  toggle.addEventListener('change', async function () {
    var next = toggle.checked;
    toggle.disabled = true;
    try {
      var res = await fetch('/api/admin/ai/legacy', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ open: next })
      });
      var data = await res.json().catch(function () { return {}; });
      if (!res.ok || data.ok === false) throw new Error(data.error || ('ошибка сервера ' + res.status));
      scToast(next ? 'Старые сборки пускаем' : 'Доступ без ключа закрыт');
    } catch (e) {
      toggle.checked = !next;
      scToast('Настройка не сохранена: ' + e.message, true);
    } finally {
      toggle.disabled = false;
    }
  });

  document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (btn) {
    if (btn.dataset.feature === 'ai') btn.addEventListener('click', loadFlag);
  });
  loadFlag();
})();

// Раздел добавлен после того, как основной скрипт уже разобрал меню, поэтому
// переключение вкладки довешиваем отдельно.
VIEW_TITLES.social = 'Автопостинг';
document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (btn) {
  btn.addEventListener('click', function () {
    var view = document.getElementById('social-view');
    if (btn.dataset.feature === 'social') { view.style.display = 'block'; loadSocial(); }
    else { view.style.display = 'none'; }
  });
});
`;
