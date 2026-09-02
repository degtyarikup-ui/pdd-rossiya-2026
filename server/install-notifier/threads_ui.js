// ─────────────────────────────────────────────────────────────────────────────
// Раздел «Threads» в админке: разметка и клиентский скрипт.
//
// Устроен так же, как «Автопостинг»: состояние → расписание → очередь с
// массовыми действиями. Разметка старого раздела заменяется целиком в
// renderAdminPage() — она собрана внутри экранированной строки worker.js.
// Стили берём из раздела автопостинга (sc-*), чтобы не плодить копии.
// ─────────────────────────────────────────────────────────────────────────────

export const THREADS_VIEW_HTML = `
<div id="threads-view" style="display:none;">

  <div class="card">
    <div class="card-head" style="margin-bottom:14px;">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>
        <span>Состояние</span>
      </div>
      <div style="display:flex; gap:8px;">
        <button class="btn-action" id="th-check">Проверить</button>
        <button class="btn-action" id="th-toggle-conn">Подключение</button>
      </div>
    </div>
    <div id="th-status" style="display:flex; gap:8px; flex-wrap:wrap;"></div>
    <div id="th-check-result" style="margin-top:12px;"></div>

    <div id="th-conn" style="display:none; margin-top:18px; padding-top:18px; border-top:1px solid #F1F2F6;">
      <div class="form-group" style="max-width:520px;">
        <label class="form-label">Токен Threads</label>
        <input type="password" id="th-token" class="sc-input">
        <span class="sc-hint">Аккаунт определится сам. Где взять токен — в инструкции THREADS_SETUP.md</span>
      </div>
      <button class="btn-action btn-primary" id="th-save-conn" style="margin-top:12px;">Сохранить</button>
    </div>
  </div>

  <div class="card">
    <div class="card-head" style="margin-bottom:14px;">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
        <span>Расписание</span>
      </div>
      <button class="btn-action btn-primary" id="th-plan">Расставить по датам</button>
    </div>
    <div style="display:flex; gap:20px; flex-wrap:wrap; align-items:flex-end;">
      <div class="form-group"><label class="form-label">Время</label>
        <input type="time" id="th-time" class="sc-input" style="width:120px;"></div>
      <div class="form-group"><label class="form-label">Раз в сколько дней</label>
        <input type="number" id="th-every" class="sc-input" min="1" max="30" value="1" style="width:90px;"></div>
      <div style="flex:1; min-width:200px; text-align:right;" class="sc-hint" id="th-next"></div>
    </div>
  </div>

  <div class="card">
    <div class="card-head" style="margin-bottom:14px;">
      <div class="sc-tabs">
        <button class="sc-tab active" data-th-filter="queued">В очереди <span id="th-n-q">0</span></button>
        <button class="sc-tab" data-th-filter="published">Опубликовано <span id="th-n-p">0</span></button>
        <button class="sc-tab" data-th-filter="failed">Ошибки <span id="th-n-f">0</span></button>
      </div>
      <div style="display:flex; gap:8px;">
        <button class="btn-action" id="th-refresh">Обновить</button>
        <button class="btn-action btn-primary" id="th-add">Добавить посты</button>
      </div>
    </div>
    <div id="th-bulk" style="display:none;" class="sc-bulk"></div>
    <div id="th-list" style="display:grid; gap:10px;"></div>
  </div>

  <div class="card">
    <div class="card-head" style="margin-bottom:10px;">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
        <span>Журнал</span>
      </div>
      <span class="sc-hint">Сервер (МСК): <b id="th-clock">—</b></span>
    </div>
    <div id="th-log" style="display:grid; gap:5px; font-size:12.5px;"></div>
  </div>

</div>
`;

export const THREADS_CLIENT_JS = `
// ────────────────────── Threads ──────────────────────

var thState = { posts: [], settings: {}, log: [] };
var thFilter = 'queued';
var thSelected = {};

async function thApi(path, body) {
  var opts = body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {};
  var res = await fetch('/api/admin/threads/' + path, opts);
  if (res.status === 401) { checkAuthAndLoad(); throw new Error('нужно войти заново'); }
  return await res.json();
}

async function loadThreads() {
  try {
    thState = await thApi('state');
    document.getElementById('th-clock').textContent = thState.serverTimeMsk || '—';
    thRenderStatus();
    thRenderList();
    thRenderLog();
  } catch (e) { scToast('Не загрузилось: ' + e.message, true); }
}

function thRenderStatus() {
  var s = thState.settings || {};
  var posts = thState.posts || [];
  document.getElementById('th-status').innerHTML =
    (s.hasToken
      ? '<span class="sc-chip ok">Threads' + (s.username ? ' @' + scEsc(s.username) : '') + '</span>'
      : '<span class="sc-chip bad">Threads не подключён</span>')
    + '<span class="sc-chip">Постов: ' + posts.length + '</span>'
    + '<span class="sc-chip">Запланировано: ' + posts.filter(function (p) { return p.status === 'queued' && p.scheduledAt; }).length + '</span>';

  document.getElementById('th-token').placeholder = s.hasToken ? (s.tokenMask + ' — пусто = не менять') : 'не задан';
  var t = document.getElementById('th-time');
  if (document.activeElement !== t) t.value = s.postTime || '10:00';

  var next = posts.filter(function (p) { return p.status === 'queued' && p.scheduledAt; })
    .sort(function (a, b) { return a.scheduledAt.localeCompare(b.scheduledAt); })[0];
  document.getElementById('th-next').innerHTML = next
    ? ('Ближайший: <b style="color:var(--text)">' + scMskShort(next.scheduledAt) + '</b> — ' + scEsc(next.text.slice(0, 60)) + '…')
    : (posts.length ? 'Даты не расставлены' : 'Постов пока нет');
}

function thPosts() {
  var weight = { failed: 0, queued: 1, published: 2 };
  return (thState.posts || []).filter(function (p) {
    if (thFilter === 'queued') return p.status === 'queued';
    if (thFilter === 'published') return p.status === 'published';
    return p.status === 'failed';
  }).sort(function (a, b) {
    var wa = weight[a.status] != null ? weight[a.status] : 3;
    var wb = weight[b.status] != null ? weight[b.status] : 3;
    if (wa !== wb) return wa - wb;
    if (a.scheduledAt && b.scheduledAt) return a.scheduledAt.localeCompare(b.scheduledAt);
    if (a.scheduledAt) return -1;
    if (b.scheduledAt) return 1;
    return 0;
  });
}

function thRenderList() {
  var all = thState.posts || [];
  document.getElementById('th-n-q').textContent = all.filter(function (p) { return p.status === 'queued'; }).length;
  document.getElementById('th-n-p').textContent = all.filter(function (p) { return p.status === 'published'; }).length;
  document.getElementById('th-n-f').textContent = all.filter(function (p) { return p.status === 'failed'; }).length;

  var list = thPosts();
  var box = document.getElementById('th-list');
  if (!list.length) {
    box.innerHTML = '<div class="sc-empty">'
      + (thFilter === 'queued' ? 'Постов нет — нажми «Добавить посты»' : 'Пусто') + '</div>';
    thRenderBulk();
    return;
  }

  box.innerHTML = list.map(function (p) {
    var when = p.scheduledAt
      ? '<span class="sc-pill">' + SC_ICONS.clock + scMskShort(p.scheduledAt) + '</span>'
      : '<span class="sc-pill">без даты</span>';
    var state = p.status === 'published'
      ? '<span class="sc-pill ok">' + SC_ICONS.check + (p.publishedAt ? scMskShort(p.publishedAt) : 'опубликован') + '</span>'
      : (p.status === 'failed' ? '<span class="sc-pill bad">' + SC_ICONS.alert + 'ошибка</span>' : when);
    var link = p.permalink
      ? '<a href="' + scEsc(p.permalink) + '" target="_blank" rel="noopener" style="color:var(--primary);text-decoration:none;font-size:12px;">открыть ↗</a>'
      : '';

    return '<div class="sc-row' + (thSelected[p.id] ? ' sel' : '') + '" style="align-items:flex-start;">'
      + '<input type="checkbox" data-th-pick="' + p.id + '"' + (thSelected[p.id] ? ' checked' : '') + ' style="margin-top:4px;">'
      + '<div style="flex:1; min-width:0;">'
      + '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:6px;">'
      + state + link + '<span style="font-size:11px;color:var(--text-muted);">' + p.text.length + ' знаков</span></div>'
      + '<textarea class="sc-input" style="width:100%;min-height:64px;font-size:12.5px;" data-th-text="' + p.id + '"'
      + ' onchange="thSaveText(this)">' + scEsc(p.text) + '</textarea>'
      + (p.error ? '<div class="sc-err" style="font-size:11.5px;">' + scEsc(p.error) + '</div>' : '')
      + '</div>'
      + '<div style="display:flex;flex-direction:column;gap:6px;align-items:flex-end;">'
      + '<input type="datetime-local" class="sc-input" style="width:180px;font-size:12px;" data-th-date="' + p.id + '"'
      + ' value="' + (p.scheduledAt ? scMsk(p.scheduledAt).replace(' ', 'T') : '') + '" onchange="thSetDate(this)">'
      + (p.status === 'published' ? '' : '<button class="btn-action" onclick="thPublishOne(\\'' + p.id + '\\')">'
          + (p.status === 'failed' ? 'Повторить' : 'Опубликовать') + '</button>')
      + '</div></div>';
  }).join('');

  box.querySelectorAll('[data-th-pick]').forEach(function (cb) {
    cb.onchange = function () {
      thSelected[cb.dataset.thPick] = cb.checked;
      cb.closest('.sc-row').classList.toggle('sel', cb.checked);
      thRenderBulk();
    };
  });
  thRenderBulk();
}

function thPicked() {
  return Object.keys(thSelected).filter(function (k) { return thSelected[k]; });
}

function thRenderBulk() {
  var ids = thPicked();
  var bar = document.getElementById('th-bulk');
  var total = thPosts().length;
  if (!ids.length) {
    bar.style.display = total ? 'flex' : 'none';
    bar.style.background = '#F6F7F9';
    bar.innerHTML = '<button class="btn-action" onclick="thSelectAll(true)">Выбрать все (' + total + ')</button>'
      + '<span class="sc-hint">или отметь нужные галочкой</span>';
    return;
  }
  var published = thFilter === 'published';
  bar.style.display = 'flex';
  bar.style.background = 'var(--primary-subtle)';
  bar.innerHTML = '<span class="sc-count">Выбрано: ' + ids.length + '</span>'
    + (published ? '' : '<button class="btn-action btn-primary" onclick="thPublishSelected()">Опубликовать сейчас</button>')
    + '<span class="sc-sep"></span>'
    + '<button class="btn-action" onclick="thBulkDate()">Дата и время</button>'
    + (published
        ? '<button class="btn-action" onclick="thBulk(\\'requeue\\')">Вернуть в очередь</button>'
        : '<button class="btn-action" onclick="thBulk(\\'mark\\')">Уже опубликован</button>'
          + '<button class="btn-action" onclick="thBulk(\\'unschedule\\')">Снять даты</button>')
    + '<span class="sc-sep"></span>'
    + '<button class="btn-action" onclick="thSelectAll(false)">Снять выбор</button>'
    + '<button class="btn-action sc-danger" onclick="thBulk(\\'delete\\')">Удалить</button>';
}

window.thSelectAll = function (on) {
  thPosts().forEach(function (p) { thSelected[p.id] = on; });
  thRenderList();
};

window.thBulk = async function (action) {
  var ids = thPicked();
  if (!ids.length) return;
  if (action === 'delete' && !confirm('Удалить ' + ids.length + ' постов?')) return;
  await thApi('bulk', { ids: ids, action: action });
  thSelected = {};
  scToast('Готово');
  await loadThreads();
};

window.thBulkDate = function () {
  var ids = thPicked();
  var tomorrow = new Date(Date.now() + 3 * 3600000 + 86400000).toISOString().slice(0, 10);
  var time = (thState.settings || {}).postTime || '10:00';
  scModal(
    '<div style="font-size:15px;font-weight:700;margin-bottom:14px;">Расставить ' + ids.length + ' постов</div>'
    + '<div style="display:flex;gap:12px;flex-wrap:wrap;">'
    + '<div class="form-group"><label class="form-label">С какого дня</label><input type="date" id="th-m-date" class="sc-input" value="' + tomorrow + '"></div>'
    + '<div class="form-group"><label class="form-label">Во сколько (МСК)</label><input type="time" id="th-m-time" class="sc-input" value="' + time + '"></div>'
    + '<div class="form-group"><label class="form-label">Раз в N дней</label><input type="number" id="th-m-every" class="sc-input" min="1" max="30" value="1" style="width:80px;"></div>'
    + '</div>',
    async function (box) {
      var res = await thApi('bulk', {
        ids: ids, action: 'schedule',
        startAt: box.querySelector('#th-m-date').value + 'T' + box.querySelector('#th-m-time').value,
        everyDays: box.querySelector('#th-m-every').value
      });
      thSelected = {};
      scToast('Расставлено: ' + (res.changed || 0));
      await loadThreads();
    }
  );
};

window.thSaveText = async function (el) {
  await thApi('update', { id: el.dataset.thText, text: el.value });
  scToast('Сохранено');
};

window.thSetDate = async function (el) {
  var v = el.value ? new Date(new Date(el.value + ':00.000Z').getTime() - 3 * 3600000).toISOString() : null;
  await thApi('update', { id: el.dataset.thDate, scheduledAt: v });
  await loadThreads();
};

window.thPublishOne = async function (id) {
  if (!confirm('Опубликовать в Threads прямо сейчас?')) return;
  var res = await thApi('publish-now', { ids: [id] });
  scToast(res.message || 'Запущено');
  thWatch();
};

window.thPublishSelected = async function () {
  var ids = thPicked();
  if (!ids.length) return;
  if (!confirm('Опубликовать ' + ids.length + ' постов? Уйдут по очереди, не больше трёх за раз.')) return;
  var res = await thApi('publish-now', { ids: ids });
  scToast(res.message || 'Запущено', !res.ok);
  thSelected = {};
  thWatch();
};

// Публикация занимает около минуты на пост: контейнеру нужно время дозреть.
function thWatch() {
  var ticks = 0;
  var timer = setInterval(async function () {
    ticks += 1;
    await loadThreads();
    if (ticks > 12) clearInterval(timer);
  }, 12000);
  loadThreads();
}

function thRenderLog() {
  var log = (thState.log || []).slice(0, 10);
  document.getElementById('th-log').innerHTML = log.length ? log.map(function (e) {
    var color = e.level === 'error' ? 'var(--danger)' : (e.level === 'ok' ? 'var(--success)' : 'var(--text-muted)');
    return '<div style="display:flex;gap:10px;padding:5px 0;border-bottom:1px solid #F5F6F8;">'
      + '<span class="sc-hint" style="white-space:nowrap;">' + scMskShort(e.ts) + '</span>'
      + '<span style="color:' + color + ';">' + scEsc(e.message) + '</span></div>';
  }).join('') : '<div class="sc-hint">пока пусто</div>';
}

document.getElementById('th-toggle-conn').onclick = function () {
  var c = document.getElementById('th-conn');
  c.style.display = c.style.display === 'none' ? 'block' : 'none';
};

document.getElementById('th-save-conn').onclick = async function () {
  var res = await thApi('settings', {
    token: document.getElementById('th-token').value,
    postTime: document.getElementById('th-time').value
  });
  document.getElementById('th-token').value = '';
  scToast(res.note || 'Сохранено');
  await loadThreads();
};

document.getElementById('th-check').onclick = async function () {
  var box = document.getElementById('th-check-result');
  box.innerHTML = '<span class="sc-hint">проверяю…</span>';
  var res = await thApi('check', {});
  box.innerHTML = (res.checks || []).map(function (c) {
    return '<div style="font-size:12.5px;padding:5px 0;color:' + (c.ok ? 'var(--success)' : 'var(--danger)') + ';">'
      + (c.ok ? '✓ ' : '✕ ') + scEsc(c.name) + ' — <span style="color:var(--text);">' + scEsc(c.message) + '</span></div>';
  }).join('');
};

document.getElementById('th-add').onclick = function () {
  scModal(
    '<div style="font-size:15px;font-weight:700;margin-bottom:6px;">Добавить посты</div>'
    + '<div class="sc-hint" style="margin-bottom:12px;">Один пост — один абзац. Разделяй пустой строкой, и добавятся сразу все.</div>'
    + '<textarea id="th-m-text" class="sc-input" style="width:100%;min-height:240px;" placeholder="Первый пост…&#10;&#10;Второй пост…"></textarea>',
    async function (box) {
      var res = await thApi('add', { text: box.querySelector('#th-m-text').value });
      scToast(res.ok ? ('Добавлено постов: ' + res.added) : (res.message || 'Пусто'), !res.ok);
      await loadThreads();
    }
  );
};

document.getElementById('th-plan').onclick = async function () {
  var ids = (thState.posts || []).filter(function (p) { return p.status === 'queued'; }).map(function (p) { return p.id; });
  if (!ids.length) { scToast('Нечего расставлять'); return; }
  await thApi('settings', { postTime: document.getElementById('th-time').value });
  var tomorrow = new Date(Date.now() + 3 * 3600000 + 86400000).toISOString().slice(0, 10);
  var res = await thApi('bulk', {
    ids: ids, action: 'schedule',
    startAt: tomorrow + 'T' + document.getElementById('th-time').value,
    everyDays: document.getElementById('th-every').value
  });
  scToast('Расставлено постов: ' + (res.changed || 0));
  await loadThreads();
};

document.getElementById('th-refresh').onclick = loadThreads;

document.querySelectorAll('#threads-view .sc-tab[data-th-filter]').forEach(function (tab) {
  tab.onclick = function () {
    document.querySelectorAll('#threads-view .sc-tab[data-th-filter]').forEach(function (t) { t.classList.remove('active'); });
    tab.classList.add('active');
    thFilter = tab.dataset.thFilter;
    thSelected = {};
    thRenderList();
  };
});

VIEW_TITLES.threads = 'Threads';
document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (btn) {
  btn.addEventListener('click', function () {
    if (btn.dataset.feature === 'threads') loadThreads();
  });
});
`;
