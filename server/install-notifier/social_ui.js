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
    .sc-bulk { display:flex; gap:8px; align-items:center; flex-wrap:wrap; padding:11px 14px;
               background:var(--primary-subtle); border-radius:12px; margin-bottom:12px; }
    .sc-hint { font-size:12px; color:var(--text-muted); }
    .sc-modal-bg { position:fixed; inset:0; background:rgba(15,23,42,0.45); z-index:9999;
                   display:flex; align-items:center; justify-content:center; padding:20px; }
    .sc-modal { background:#fff; border-radius:16px; padding:22px 24px; width:100%; max-width:440px;
                box-shadow:0 20px 50px rgba(0,0,0,0.2); }
  </style>

  <div class="card">
    <div class="card-head" style="margin-bottom:14px;">
      <div class="card-title"><span>Состояние</span></div>
      <div style="display:flex; gap:8px;">
        <button class="btn-action" id="sc-check">Проверить</button>
        <button class="btn-action" id="sc-toggle-conn">Подключение</button>
      </div>
    </div>
    <div id="sc-status" style="display:flex; gap:8px; flex-wrap:wrap;"></div>
    <div id="sc-check-result" style="margin-top:12px;"></div>

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
        <span class="sc-hint">Пустые поля не меняются. Инструкция — SOCIAL_SETUP.md</span>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="card-head" style="margin-bottom:14px;">
      <div class="card-title"><span>Расписание</span></div>
      <button class="btn-action btn-primary" id="sc-plan">Расставить по датам</button>
    </div>
    <div style="display:flex; gap:20px; flex-wrap:wrap; align-items:flex-end;">
      <div class="form-group"><label class="form-label">Время</label>
        <input type="time" id="sc-time" class="sc-input" style="width:120px;"></div>
      <div class="form-group"><label class="form-label">Раз в сколько дней</label>
        <input type="number" id="sc-every" class="sc-input" min="1" max="30" value="1" style="width:90px;"></div>
      <div class="form-group"><label class="form-label">Куда постим</label>
        <div style="display:flex; gap:8px;">
          <button class="sc-tab" id="sc-t-ig" data-on="0">Instagram</button>
          <button class="sc-tab" id="sc-t-yt" data-on="0">YouTube</button>
        </div></div>
      <div style="flex:1; min-width:200px; text-align:right;" class="sc-hint" id="sc-next"></div>
    </div>
  </div>

  <div class="card">
    <div class="card-head" style="margin-bottom:14px;">
      <div class="sc-tabs">
        <button class="sc-tab active" data-filter="queued">В очереди <span id="sc-n-q">0</span></button>
        <button class="sc-tab" data-filter="published">Выложено <span id="sc-n-p">0</span></button>
        <button class="sc-tab" data-filter="failed">Ошибки <span id="sc-n-f">0</span></button>
      </div>
      <div style="display:flex; gap:8px;">
        <button class="btn-action" id="sc-refresh">Обновить</button>
        <button class="btn-action btn-primary" id="sc-sync">Забрать с Диска</button>
      </div>
    </div>
    <div id="sc-bulk" style="display:none;" class="sc-bulk"></div>
    <div id="sc-list" style="display:grid; gap:8px;"></div>
  </div>

  <div class="card">
    <div class="card-head" style="margin-bottom:10px;">
      <div class="card-title"><span>Журнал</span></div>
      <span class="sc-hint">Сервер (МСК): <b id="sc-clock">—</b></span>
    </div>
    <div id="sc-log" style="display:grid; gap:5px; font-size:12.5px;"></div>
  </div>

</div>
`;

export const SOCIAL_CLIENT_JS = `
// ────────────────────── Автопостинг (Instagram + YouTube) ──────────────────────

var scState = { accounts: [], posts: [], settings: {}, log: [] };
var scFilter = 'queued';
var scSelected = {};

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
  return await res.json();
}

// Дата в МСК: сервер отдаёт UTC, человеку показываем московское время.
function scMsk(iso) {
  if (!iso) return null;
  var d = new Date(new Date(iso).getTime() + 3 * 3600000);
  return d.toISOString().slice(0, 16).replace('T', ' ');
}
function scMskShort(iso) {
  var s = scMsk(iso);
  return s ? s.slice(5).replace('-', '.') : '';
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
  var chips = [];
  chips.push(s.hasGoogleRefreshToken
    ? '<span class="sc-chip ok">Google</span>'
    : '<span class="sc-chip bad">Google не подключён</span>');
  chips.push(a && a.hasInstagramToken
    ? '<span class="sc-chip ok">Instagram</span>'
    : '<span class="sc-chip">Instagram не подключён</span>');
  chips.push(s.youtubeReady
    ? '<span class="sc-chip ok">YouTube</span>'
    : '<span class="sc-chip">YouTube не подключён</span>');
  chips.push('<span class="sc-chip">Роликов: ' + posts.length + '</span>');
  document.getElementById('sc-status').innerHTML = chips.join('');

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
  var t = document.getElementById('sc-time');
  if (document.activeElement !== t) t.value = a.postTime || '19:00';
  var tg = a.targets || [];
  scSetToggle('sc-t-ig', tg.indexOf('instagram') !== -1);
  scSetToggle('sc-t-yt', tg.indexOf('youtube') !== -1);

  var queued = (scState.posts || []).filter(function (p) { return p.status === 'queued'; });
  var scheduled = queued.filter(function (p) { return p.scheduledAt; })
    .sort(function (x, y) { return x.scheduledAt.localeCompare(y.scheduledAt); });
  var next = scheduled[0];
  document.getElementById('sc-next').innerHTML = next
    ? ('Ближайшая: <b style="color:var(--text)">' + scMsk(next.scheduledAt) + '</b> — ' + scEsc(next.fileName))
    : (queued.length ? 'Даты не расставлены — публикуется по одному в день в ' + scEsc(a.postTime || '19:00') : 'Очередь пуста');
}

function scSetToggle(id, on) {
  var el = document.getElementById(id);
  el.dataset.on = on ? '1' : '0';
  el.classList.toggle('active', !!on);
}

function scPosts() {
  return (scState.posts || []).filter(function (p) {
    if (scFilter === 'queued') return p.status === 'queued' || p.status === 'processing';
    if (scFilter === 'published') return p.status === 'published';
    return p.status === 'failed';
  }).sort(function (a, b) {
    if (a.scheduledAt && b.scheduledAt) return a.scheduledAt.localeCompare(b.scheduledAt);
    return String(a.fileName).localeCompare(String(b.fileName), 'ru', { numeric: true });
  });
}

function scRenderList() {
  var all = scState.posts || [];
  document.getElementById('sc-n-q').textContent = all.filter(function (p) { return p.status === 'queued' || p.status === 'processing'; }).length;
  document.getElementById('sc-n-p').textContent = all.filter(function (p) { return p.status === 'published'; }).length;
  document.getElementById('sc-n-f').textContent = all.filter(function (p) { return p.status === 'failed'; }).length;

  var list = scPosts();
  var box = document.getElementById('sc-list');
  if (!list.length) {
    box.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:26px;background:#f8fafc;border-radius:12px;">'
      + (scFilter === 'queued' ? 'Очередь пуста — нажми «Забрать с Диска»' : 'Пусто') + '</div>';
    scRenderBulk();
    return;
  }

  box.innerHTML =
    '<div style="display:flex;align-items:center;gap:10px;padding:0 14px 4px;">'
    + '<input type="checkbox" id="sc-all"><span class="sc-hint">выбрать все (' + list.length + ')</span></div>'
    + list.map(function (p) {
      var links = '';
      if (p.instagramPermalink) links += '<a href="' + scEsc(p.instagramPermalink) + '" target="_blank" rel="noopener" style="color:var(--primary);text-decoration:none;font-size:12px;">IG↗</a> ';
      if (p.youtubePermalink) links += '<a href="' + scEsc(p.youtubePermalink) + '" target="_blank" rel="noopener" style="color:var(--primary);text-decoration:none;font-size:12px;">YT↗</a>';
      var dots = (p.targets || []).map(function (t) {
        var st = t === 'instagram' ? p.instagramStatus : p.youtubeStatus;
        var color = st === 'published' ? 'var(--success)' : (st === 'failed' ? 'var(--danger)' : 'var(--text-muted)');
        return '<span class="sc-dot" style="color:' + color + '">' + (t === 'instagram' ? 'IG' : 'YT') + '</span>';
      }).join(' ');
      var when = p.status === 'published'
        ? '<span class="sc-hint">' + (p.publishedAt ? scMskShort(p.publishedAt) : 'вручную') + '</span>'
        : '<input type="datetime-local" class="sc-input" style="width:180px;font-size:12px;" data-id="' + p.id + '"'
          + ' value="' + (p.scheduledAt ? scMsk(p.scheduledAt).replace(' ', 'T') : '') + '" onchange="scSetDate(this)">';
      return '<div class="sc-row' + (scSelected[p.id] ? ' sel' : '') + '">'
        + '<input type="checkbox" data-pick="' + p.id + '"' + (scSelected[p.id] ? ' checked' : '') + '>'
        + '<span class="sc-name" title="' + scEsc(p.fileName) + '">' + scEsc(p.fileName) + '</span>'
        + when + '<span>' + dots + '</span><span>' + links + '</span>'
        + (p.status === 'processing' ? '<span class="sc-chip">публикуется…</span>' : '')
        + '<button class="btn-action" onclick="scOpen(\\'' + p.id + '\\')">Открыть</button>'
        + '</div>'
        + (p.error ? '<div style="background:var(--danger-subtle);color:var(--danger);border-radius:8px;padding:7px 12px;font-size:12px;margin:-4px 0 4px;">' + scEsc(p.error) + '</div>' : '');
    }).join('');

  document.getElementById('sc-all').onchange = function () {
    list.forEach(function (p) { scSelected[p.id] = this.checked; }, this);
    scRenderList();
  };
  box.querySelectorAll('[data-pick]').forEach(function (cb) {
    cb.onchange = function () { scSelected[cb.dataset.pick] = cb.checked; scRenderBulk(); scHighlight(); };
  });
  scRenderBulk();
}

function scHighlight() {
  document.querySelectorAll('#sc-list [data-pick]').forEach(function (cb) {
    cb.closest('.sc-row').classList.toggle('sel', cb.checked);
  });
}

function scPicked() {
  return Object.keys(scSelected).filter(function (k) { return scSelected[k]; });
}

function scRenderBulk() {
  var ids = scPicked();
  var bar = document.getElementById('sc-bulk');
  if (!ids.length) { bar.style.display = 'none'; return; }
  bar.style.display = 'flex';
  bar.innerHTML = '<b style="font-size:13px;">Выбрано: ' + ids.length + '</b>'
    + '<button class="btn-action" onclick="scBulkDate()">Дата и время…</button>'
    + '<button class="btn-action" onclick="scBulkCaption()">Подпись…</button>'
    + '<button class="btn-action" onclick="scBulk(\\'mark\\')">Пометить выложенными</button>'
    + '<button class="btn-action" onclick="scBulk(\\'requeue\\')">Вернуть в очередь</button>'
    + '<button class="btn-action" onclick="scBulk(\\'unschedule\\')">Снять даты</button>'
    + '<button class="btn-action" style="color:var(--danger);border-color:#fecaca;margin-left:auto;" onclick="scBulk(\\'delete\\')">Убрать</button>';
}

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
  var bg = document.createElement('div');
  bg.className = 'sc-modal-bg';
  bg.innerHTML = '<div class="sc-modal">' + html
    + '<div style="display:flex;gap:8px;margin-top:16px;justify-content:flex-end;">'
    + '<button class="btn-action" data-x>Отмена</button>'
    + '<button class="btn-action btn-primary" data-ok>Применить</button></div></div>';
  document.body.appendChild(bg);
  bg.querySelector('[data-x]').onclick = function () { bg.remove(); };
  bg.querySelector('[data-ok]').onclick = async function () { await onOk(bg); bg.remove(); };
  return bg;
}

window.scBulkDate = function () {
  var ids = scPicked();
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
      if (!d || !t) return;
      var res = await scApi('posts/bulk', { ids: ids, action: 'schedule', startAt: d + 'T' + t, everyDays: every });
      scSelected = {};
      scToast('Расставлено: ' + (res.changed || 0));
      await loadSocial();
    }
  );
};

window.scBulkCaption = function () {
  var ids = scPicked();
  var tpl = (scAccount() || {}).captionTemplate || '';
  scModal(
    '<div style="font-size:15px;font-weight:700;margin-bottom:6px;">Подпись для ' + ids.length + ' роликов</div>'
    + '<div class="sc-hint" style="margin-bottom:10px;">{title} подставит название ролика</div>'
    + '<textarea id="sc-m-cap" class="sc-input" style="width:100%;min-height:140px;">' + scEsc(tpl) + '</textarea>',
    async function (bg) {
      await scApi('posts/bulk', { ids: ids, action: 'caption', caption: bg.querySelector('#sc-m-cap').value });
      scSelected = {};
      scToast('Подпись обновлена');
      await loadSocial();
    }
  );
};

window.scOpen = function (id) {
  var p = (scState.posts || []).find(function (x) { return x.id === id; });
  if (!p) return;
  scModal(
    '<div style="font-size:15px;font-weight:700;margin-bottom:12px;">' + scEsc(p.fileName) + '</div>'
    + '<div class="form-group"><label class="form-label">Заголовок (YouTube)</label>'
    + '<input type="text" id="sc-m-title" class="sc-input" value="' + scEsc(p.title || '') + '"></div>'
    + '<div class="form-group" style="margin-top:10px;"><label class="form-label">Подпись</label>'
    + '<textarea id="sc-m-cap2" class="sc-input" style="width:100%;min-height:130px;">' + scEsc(p.caption || '') + '</textarea></div>'
    + '<div style="margin-top:12px;"><button class="btn-action btn-primary" onclick="scPublishNow(\\'' + p.id + '\\')">'
    + (p.status === 'failed' ? 'Повторить публикацию' : 'Опубликовать сейчас') + '</button></div>',
    async function (bg) {
      await scApi('posts/update', {
        id: id,
        title: bg.querySelector('#sc-m-title').value,
        caption: bg.querySelector('#sc-m-cap2').value
      });
      scToast('Сохранено');
      await loadSocial();
    }
  );
};

window.scPublishNow = async function (id) {
  if (!confirm('Опубликовать прямо сейчас?')) return;
  var res = await scApi('posts/publish', { id: id });
  scToast(res.message || 'Публикация запущена');
  document.querySelectorAll('.sc-modal-bg').forEach(function (m) { m.remove(); });
  await loadSocial();
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
    if (a && (ig || folder)) {
      await scApi('accounts', { account: { id: a.id, instagramToken: ig, driveFolderId: folder || a.driveFolderId } });
    }
    ['sc-client-secret', 'sc-refresh-token', 'sc-ig-token'].forEach(function (id) { document.getElementById(id).value = ''; });
    scToast('Сохранено');
    await loadSocial();
  } catch (e) { scToast('Ошибка: ' + e.message, true); }
};

document.getElementById('sc-check').onclick = async function () {
  var box = document.getElementById('sc-check-result');
  box.innerHTML = '<span class="sc-hint">проверяю…</span>';
  try {
    var res = await scApi('check', {});
    box.innerHTML = (res.checks || []).map(function (c) {
      return '<div style="font-size:12.5px;padding:5px 0;color:' + (c.ok ? 'var(--success)' : 'var(--danger)') + ';">'
        + (c.ok ? '✓ ' : '✕ ') + scEsc(c.name) + ' — <span style="color:var(--text);">' + scEsc(c.message) + '</span></div>';
    }).join('');
  } catch (e) { box.innerHTML = '<span style="color:var(--danger)">' + scEsc(e.message) + '</span>'; }
};

document.getElementById('sc-plan').onclick = async function () {
  var a = scAccount();
  if (!a) { scToast('Сначала подключи аккаунт', true); return; }
  var targets = [];
  if (document.getElementById('sc-t-ig').dataset.on === '1') targets.push('instagram');
  if (document.getElementById('sc-t-yt').dataset.on === '1') targets.push('youtube');
  if (!targets.length) { scToast('Выбери хотя бы одну площадку', true); return; }

  await scApi('accounts', { account: { id: a.id, postTime: document.getElementById('sc-time').value, targets: targets } });
  var ids = (scState.posts || []).filter(function (p) { return p.status === 'queued'; }).map(function (p) { return p.id; });
  if (!ids.length) { scToast('Очередь пуста'); await loadSocial(); return; }

  await scApi('posts/bulk', { ids: ids, action: 'targets', targets: targets });
  var tomorrow = new Date(Date.now() + 3 * 3600000 + 86400000).toISOString().slice(0, 10);
  var res = await scApi('posts/bulk', {
    ids: ids, action: 'schedule',
    startAt: tomorrow + 'T' + document.getElementById('sc-time').value,
    everyDays: document.getElementById('sc-every').value
  });
  scToast('Расставлено роликов: ' + (res.changed || 0));
  await loadSocial();
};

['sc-t-ig', 'sc-t-yt'].forEach(function (id) {
  document.getElementById(id).onclick = function () { scSetToggle(id, this.dataset.on !== '1'); };
});

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
    scFilter = tab.dataset.filter;
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

  var card = document.createElement('div');
  card.className = 'card';
  card.innerHTML = '<div class="card-head"><div class="card-title"><span>Доступ к ИИ извне</span></div>'
    + '<span id="ai-key-state" style="font-size:12px;color:var(--text-muted);"></span></div>'
    + '<label style="display:flex;gap:9px;align-items:flex-start;cursor:pointer;font-size:13.5px;">'
    + '<input type="checkbox" id="ai-legacy-toggle" style="margin-top:3px;">'
    + '<span>Пускать приложения без ключа<br><span style="font-size:12px;color:var(--text-muted);">'
    + 'Нужно, пока у людей стоят версии, выпущенные до появления ключа. Когда обновление разойдётся — сними галочку.'
    + '</span></span></label>';
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
    await fetch('/api/admin/ai/legacy', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ open: toggle.checked })
    });
    scToast(toggle.checked ? 'Старые сборки пускаем' : 'Доступ без ключа закрыт');
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
