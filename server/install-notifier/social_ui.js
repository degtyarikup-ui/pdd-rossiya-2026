// ─────────────────────────────────────────────────────────────────────────────
// Раздел «Автопостинг» в админке: разметка и клиентский скрипт.
//
// Живёт отдельным файлом, а не внутри гигантских строк ADMIN_HTML_HEAD /
// ADMIN_CLIENT_JS: те собраны как экранированные однострочные литералы, и
// править их руками нельзя. renderAdminPage() вставляет этот раздел по якорям.
// Стили используются готовые (card, btn-action, form-group, tag-badge).
// ─────────────────────────────────────────────────────────────────────────────

export const SOCIAL_NAV_HTML = `
      <button class="nav-item" data-feature="social">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
        <span>Автопостинг</span>
      </button>
`;

export const SOCIAL_VIEW_HTML = `
<div id="social-view" style="display:none;">

  <div class="card">
    <div class="card-head">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v20M2 12h20"/></svg>
        <span>Шаг 1. Доступ к Google (Диск + YouTube)</span>
      </div>
      <div style="display:flex; gap:8px;">
        <button class="btn-action" id="social-check-btn">Проверить подключение</button>
        <button class="btn-action btn-primary" id="social-save-settings-btn">Сохранить</button>
      </div>
    </div>
    <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:14px;">
      <div class="form-group">
        <label class="form-label">Client ID</label>
        <input type="text" id="social-client-id" class="sidebar-select" placeholder="…apps.googleusercontent.com">
      </div>
      <div class="form-group">
        <label class="form-label">Client Secret</label>
        <input type="password" id="social-client-secret" class="sidebar-select" placeholder="оставь пустым, чтобы не менять">
      </div>
      <div class="form-group">
        <label class="form-label">Refresh token</label>
        <input type="password" id="social-refresh-token" class="sidebar-select" placeholder="оставь пустым, чтобы не менять">
      </div>
      <div class="form-group">
        <label class="form-label">API-ключ (упрощённый режим)</label>
        <input type="password" id="social-api-key" class="sidebar-select" placeholder="оставь пустым, чтобы не менять">
        <span style="font-size:11.5px;color:var(--text-muted);">Только для чтения папки, открытой «по ссылке». YouTube с ним работать не будет.</span>
      </div>
    </div>
    <div id="social-mode-line" style="margin-top:12px;font-size:12.5px;"></div>
    <div id="social-settings-hint" style="margin-top:12px; font-size:12.5px; color:var(--text-muted);">
      Где взять эти три значения — в инструкции <b>server/install-notifier/SOCIAL_SETUP.md</b>. Одного доступа хватает и на чтение папки с роликами, и на заливку видео на канал.
    </div>
    <div id="social-check-result" style="margin-top:14px;"></div>
  </div>

  <div class="card">
    <div class="card-head">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg>
        <span>Шаг 2. Аккаунты и расписание</span>
      </div>
      <button class="btn-action btn-primary" id="social-add-account-btn">Добавить аккаунт</button>
    </div>
    <div id="social-accounts-container" style="display:grid; gap:16px;">
      <div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка…</div>
    </div>
  </div>

  <div class="card">
    <div class="card-head">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
        <span>Шаг 3. Очередь роликов (<span id="social-queue-count">0</span>)</span>
      </div>
      <div style="display:flex; gap:8px;">
        <button class="btn-action" id="social-run-btn" title="Проверить расписание прямо сейчас">Проверить расписание</button>
        <button class="btn-action" id="social-refresh-btn">Обновить</button>
        <button class="btn-action btn-primary" id="social-sync-btn">Забрать с Диска</button>
      </div>
    </div>
    <div id="social-queue-container" style="display:grid; gap:12px;">
      <div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка…</div>
    </div>
  </div>

  <div class="card">
    <div class="card-head">
      <div class="card-title">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
        <span>Журнал автопостинга</span>
      </div>
      <span style="font-size:12px;color:var(--text-muted);">Время сервера (МСК): <b id="social-server-time">—</b></span>
    </div>
    <div id="social-log-container" style="display:grid; gap:6px; font-size:12.5px;"></div>
  </div>

</div>
`;

export const SOCIAL_CLIENT_JS = `
// ────────────────────── Автопостинг (Instagram + YouTube) ──────────────────────

var socialState = { accounts: [], posts: [], settings: {}, log: [] };
var socialEditing = null; // id аккаунта, форма которого раскрыта

function socialEsc(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function socialStatusBadge(status) {
  var map = {
    queued:     ['В очереди', 'var(--text-muted)', 'var(--surface-gray)'],
    processing: ['Публикуется…', '#B45309', '#FEF3C7'],
    published:  ['Опубликовано', 'var(--success)', 'var(--success-subtle)'],
    failed:     ['Ошибка', 'var(--danger)', 'var(--danger-subtle)']
  };
  var item = map[status] || map.queued;
  return '<span class="tag-badge" style="color:' + item[1] + ';background:' + item[2] + ';">' + item[0] + '</span>';
}

function socialToast(message, isError) {
  var box = document.createElement('div');
  box.style.cssText = 'position:fixed;right:20px;bottom:20px;z-index:10000;padding:12px 16px;border-radius:12px;font-size:13px;font-weight:600;box-shadow:0 10px 30px rgba(0,0,0,0.15);background:' +
    (isError ? 'var(--danger)' : 'var(--success)') + ';color:#fff;max-width:380px;';
  box.textContent = message;
  document.body.appendChild(box);
  setTimeout(function () { box.remove(); }, isError ? 7000 : 3500);
}

async function socialApi(path, body) {
  var options = body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {};
  var res = await fetch('/api/admin/social/' + path, options);
  if (res.status === 401) { checkAuthAndLoad(); throw new Error('Нужно войти заново'); }
  return await res.json();
}

async function loadSocial() {
  try {
    var data = await socialApi('state');
    socialState = data;
    document.getElementById('social-server-time').textContent = data.serverTimeMsk || '—';
    var s = data.settings || {};
    var clientIdInput = document.getElementById('social-client-id');
    if (document.activeElement !== clientIdInput) clientIdInput.value = s.googleClientId || '';
    document.getElementById('social-client-secret').placeholder = s.hasGoogleClientSecret ? (s.googleClientSecretMask + ' — оставь пустым, чтобы не менять') : 'не задан';
    document.getElementById('social-refresh-token').placeholder = s.hasGoogleRefreshToken ? (s.googleRefreshTokenMask + ' — оставь пустым, чтобы не менять') : 'не задан';
    document.getElementById('social-api-key').placeholder = s.hasGoogleApiKey ? (s.googleApiKeyMask + ' — оставь пустым, чтобы не менять') : 'не задан';
    var modeLine = document.getElementById('social-mode-line');
    if (s.driveMode === 'oauth') {
      modeLine.innerHTML = '<span style="color:var(--success);font-weight:600;">Полный доступ:</span> читаем любую папку Диска, заливаем на YouTube.';
    } else if (s.driveMode === 'apikey') {
      modeLine.innerHTML = '<span style="color:#B45309;font-weight:600;">Упрощённый режим:</span> Диск по API-ключу — папка должна быть открыта «Доступ по ссылке». '
        + 'Instagram работает, <b>YouTube отключён</b>: для заливки на канал нужен Refresh token.';
    } else {
      modeLine.innerHTML = '<span style="color:var(--danger);font-weight:600;">Доступ к Google не настроен.</span> Заполни Refresh token (полный доступ) или API-ключ (только Диск).';
    }
    renderSocialAccounts();
    renderSocialQueue();
    renderSocialLog();
  } catch (e) {
    socialToast('Не удалось загрузить раздел: ' + e.message, true);
  }
}

function renderSocialAccounts() {
  var container = document.getElementById('social-accounts-container');
  var accounts = socialState.accounts || [];
  if (!accounts.length && socialEditing !== 'new') {
    container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:26px;background:#f8fafc;border-radius:12px;">Пока ни одного аккаунта. Нажми «Добавить аккаунт».</div>';
    return;
  }
  var html = accounts.map(function (a) {
    return socialEditing === a.id ? socialAccountForm(a) : socialAccountCard(a);
  }).join('');
  if (socialEditing === 'new') html += socialAccountForm(null);
  container.innerHTML = html;
}

function socialAccountCard(a) {
  var targets = (a.targets || []).map(function (t) {
    return '<span class="tag-badge">' + (t === 'instagram' ? 'Instagram Reels' : 'YouTube Shorts') + '</span>';
  }).join(' ');
  var queued = (socialState.posts || []).filter(function (p) { return p.accountId === a.id && p.status === 'queued'; }).length;
  return '<div style="background:#fff;border-radius:14px;padding:16px 18px;box-shadow:0 1px 3px rgba(0,0,0,0.05);">'
    + '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;">'
    + '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">'
    + '<b style="font-size:14.5px;">' + socialEsc(a.name) + '</b>'
    + (a.active ? '<span class="tag-badge" style="color:var(--success);background:var(--success-subtle);">Включён</span>'
                : '<span class="tag-badge">Выключен</span>')
    + targets + '</div>'
    + '<div style="display:flex;gap:8px;">'
    + '<button class="btn-action" onclick="socialEditAccount(\\'' + a.id + '\\')">Настроить</button>'
    + '<button class="btn-action" onclick="socialSyncAccount(\\'' + a.id + '\\')">Забрать с Диска</button>'
    + '</div></div>'
    + '<div style="margin-top:10px;font-size:12.5px;color:var(--text-muted);display:flex;gap:18px;flex-wrap:wrap;">'
    + '<span>Публикация в <b style="color:var(--text);">' + socialEsc(a.postTime) + '</b> МСК, 1 ролик в день</span>'
    + '<span>В очереди: <b style="color:var(--text);">' + queued + '</b></span>'
    + '<span>Последняя публикация: <b style="color:var(--text);">' + (a.lastPostedAt ? new Date(a.lastPostedAt).toLocaleString('ru-RU') : 'ещё не было') + '</b></span>'
    + '</div></div>';
}

function socialAccountForm(a) {
  var v = a || {};
  var id = v.id || 'new';
  var targets = v.targets || ['instagram', 'youtube'];
  function field(label, inputHtml, hint) {
    return '<div class="form-group"><label class="form-label">' + label + '</label>' + inputHtml
      + (hint ? '<span style="font-size:11.5px;color:var(--text-muted);">' + hint + '</span>' : '') + '</div>';
  }
  return '<div style="background:#fff;border-radius:14px;padding:18px 20px;box-shadow:0 1px 3px rgba(0,0,0,0.05);">'
    + '<div style="font-size:14.5px;font-weight:700;margin-bottom:14px;">' + (a ? 'Настройка аккаунта' : 'Новый аккаунт') + '</div>'
    + '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px;">'
    + field('Название', '<input type="text" id="sa-name-' + id + '" class="sidebar-select" value="' + socialEsc(v.name || 'ПДД Россия') + '">')
    + field('Время публикации (МСК)', '<input type="time" id="sa-time-' + id + '" class="sidebar-select" value="' + socialEsc(v.postTime || '19:00') + '">')
    + field('Папка Google Диска', '<input type="text" id="sa-folder-' + id + '" class="sidebar-select" value="' + socialEsc(v.driveFolderId || '') + '" placeholder="ID папки или ссылка на неё">', 'Можно вставить ссылку целиком — ID вытащу сам')
    + field('Instagram Account ID', '<input type="text" id="sa-igid-' + id + '" class="sidebar-select" value="' + socialEsc(v.instagramAccountId || '') + '" placeholder="можно не заполнять">', 'Оставь пустым — определю сам по токену')
    + field('Instagram токен', '<input type="password" id="sa-igtoken-' + id + '" class="sidebar-select" placeholder="' + (v.hasInstagramToken ? socialEsc(v.instagramTokenMask) + ' — пусто = не менять' : 'не задан') + '">')
    + field('YouTube refresh token', '<input type="password" id="sa-yttoken-' + id + '" class="sidebar-select" placeholder="' + (v.hasYoutubeRefreshToken ? socialEsc(v.youtubeRefreshTokenMask) + ' — пусто = не менять' : 'по умолчанию — общий из шага 1') + '">', 'Заполняй, только если канал на другом Google-аккаунте')
    + field('Теги YouTube', '<input type="text" id="sa-yttags-' + id + '" class="sidebar-select" value="' + socialEsc(v.youtubeTags || '') + '">')
    + field('Приватность на YouTube', '<select id="sa-ytpriv-' + id + '" class="sidebar-select">'
        + '<option value="public"' + ((v.youtubePrivacy || 'public') === 'public' ? ' selected' : '') + '>Открытое</option>'
        + '<option value="unlisted"' + (v.youtubePrivacy === 'unlisted' ? ' selected' : '') + '>По ссылке</option>'
        + '<option value="private"' + (v.youtubePrivacy === 'private' ? ' selected' : '') + '>Скрытое</option></select>')
    + '</div>'
    + '<div class="form-group" style="margin-top:14px;"><label class="form-label">Шаблон подписи</label>'
    + '<textarea id="sa-caption-' + id + '" class="sidebar-select" style="min-height:90px;padding:10px;font-family:inherit;">' + socialEsc(v.captionTemplate || '') + '</textarea>'
    + '<span style="font-size:11.5px;color:var(--text-muted);">{title} подставит название ролика. Если рядом с видео на Диске лежит одноимённый .txt — возьму текст оттуда.</span></div>'
    + '<div style="display:flex;gap:18px;flex-wrap:wrap;margin:14px 0;font-size:13px;">'
    + '<label style="display:flex;gap:7px;align-items:center;cursor:pointer;"><input type="checkbox" id="sa-ig-' + id + '"' + (targets.indexOf('instagram') !== -1 ? ' checked' : '') + '> Публиковать в Instagram</label>'
    + '<label style="display:flex;gap:7px;align-items:center;cursor:pointer;"><input type="checkbox" id="sa-yt-' + id + '"' + (targets.indexOf('youtube') !== -1 ? ' checked' : '') + '> Публиковать на YouTube</label>'
    + '<label style="display:flex;gap:7px;align-items:center;cursor:pointer;"><input type="checkbox" id="sa-active-' + id + '"' + (v.active !== false ? ' checked' : '') + '> Автопостинг включён</label>'
    + '</div>'
    + '<div style="display:flex;gap:8px;flex-wrap:wrap;">'
    + '<button class="btn-action btn-primary" onclick="socialSaveAccount(\\'' + id + '\\')">Сохранить</button>'
    + '<button class="btn-action" onclick="socialCancelEdit()">Отмена</button>'
    + (a ? '<button class="btn-action" style="color:var(--danger);border-color:#fecaca;margin-left:auto;" onclick="socialDeleteAccount(\\'' + a.id + '\\')">Удалить аккаунт</button>' : '')
    + '</div></div>';
}

function renderSocialQueue() {
  var container = document.getElementById('social-queue-container');
  var posts = socialState.posts || [];
  document.getElementById('social-queue-count').textContent = posts.filter(function (p) { return p.status === 'queued'; }).length;

  if (!posts.length) {
    container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:26px;background:#f8fafc;border-radius:12px;">Очередь пуста. Положи ролики в папку на Google Диске и нажми «Забрать с Диска».</div>';
    return;
  }

  container.innerHTML = posts.map(function (p) {
    var account = (socialState.accounts || []).find(function (a) { return a.id === p.accountId; });
    var links = '';
    if (p.instagramPermalink) links += '<a href="' + socialEsc(p.instagramPermalink) + '" target="_blank" rel="noopener" style="color:var(--primary);text-decoration:none;">Reels ↗</a>';
    if (p.youtubePermalink) links += ' <a href="' + socialEsc(p.youtubePermalink) + '" target="_blank" rel="noopener" style="color:var(--primary);text-decoration:none;">Shorts ↗</a>';

    var platformState = (p.targets || []).map(function (t) {
      var st = t === 'instagram' ? p.instagramStatus : p.youtubeStatus;
      var label = t === 'instagram' ? 'IG' : 'YT';
      var color = st === 'published' ? 'var(--success)' : (st === 'failed' ? 'var(--danger)' : 'var(--text-muted)');
      return '<span style="color:' + color + ';font-weight:700;">' + label + '</span>';
    }).join(' · ');

    return '<div style="background:#fff;border-radius:14px;padding:14px 16px;box-shadow:0 1px 3px rgba(0,0,0,0.05);">'
      + '<div style="display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:8px;">'
      + '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">'
      + '<b style="font-size:13.5px;">' + socialEsc(p.fileName) + '</b>'
      + socialStatusBadge(p.status)
      + '<span style="font-size:11.5px;color:var(--text-muted);">' + platformState + '</span>'
      + (account ? '<span style="font-size:11.5px;color:var(--text-muted);">' + socialEsc(account.name) + '</span>' : '')
      + '</div>'
      + '<div style="font-size:12px;">' + links + '</div>'
      + '</div>'
      + '<input type="text" id="sp-title-' + p.id + '" class="sidebar-select" value="' + socialEsc(p.title || '') + '" placeholder="Заголовок для YouTube" style="margin-bottom:8px;">'
      + '<textarea id="sp-caption-' + p.id + '" class="sidebar-select" style="min-height:70px;padding:10px;font-family:inherit;margin-bottom:8px;">' + socialEsc(p.caption || '') + '</textarea>'
      + (p.error ? '<div style="background:var(--danger-subtle);color:var(--danger);border-radius:8px;padding:8px 10px;font-size:12px;margin-bottom:8px;">' + socialEsc(p.error) + '</div>' : '')
      + '<div style="display:flex;gap:8px;flex-wrap:wrap;">'
      + '<button class="btn-action" onclick="socialSavePost(\\'' + p.id + '\\')">Сохранить текст</button>'
      + '<button class="btn-action btn-primary" onclick="socialPublishNow(\\'' + p.id + '\\')">'
      + (p.status === 'failed' ? 'Повторить' : 'Опубликовать сейчас') + '</button>'
      + '<button class="btn-action" style="color:var(--danger);border-color:#fecaca;margin-left:auto;" onclick="socialDeletePost(\\'' + p.id + '\\')">Убрать из очереди</button>'
      + '</div></div>';
  }).join('');
}

function renderSocialLog() {
  var container = document.getElementById('social-log-container');
  var log = socialState.log || [];
  if (!log.length) {
    container.innerHTML = '<div style="color:var(--text-muted);padding:8px 0;">Пока пусто</div>';
    return;
  }
  container.innerHTML = log.map(function (entry) {
    var color = entry.level === 'error' ? 'var(--danger)' : (entry.level === 'ok' ? 'var(--success)' : 'var(--text-muted)');
    var time = new Date(entry.ts).toLocaleString('ru-RU');
    return '<div style="display:flex;gap:10px;padding:6px 0;border-bottom:1px solid #F1F2F6;">'
      + '<span style="color:var(--text-muted);white-space:nowrap;">' + time + '</span>'
      + '<span style="color:' + color + ';">' + socialEsc(entry.message) + '</span></div>';
  }).join('');
}

window.socialEditAccount = function (id) { socialEditing = id; renderSocialAccounts(); };
window.socialCancelEdit = function () { socialEditing = null; renderSocialAccounts(); };

window.socialSaveAccount = async function (id) {
  var value = function (prefix) {
    var el = document.getElementById(prefix + '-' + id);
    return el ? el.value : '';
  };
  var checked = function (prefix) {
    var el = document.getElementById(prefix + '-' + id);
    return el ? el.checked : false;
  };
  var targets = [];
  if (checked('sa-ig')) targets.push('instagram');
  if (checked('sa-yt')) targets.push('youtube');
  if (!targets.length) { socialToast('Выбери хотя бы одну площадку', true); return; }

  var account = {
    id: id === 'new' ? undefined : id,
    name: value('sa-name'),
    postTime: value('sa-time'),
    driveFolderId: value('sa-folder'),
    instagramAccountId: value('sa-igid'),
    instagramToken: value('sa-igtoken'),
    youtubeRefreshToken: value('sa-yttoken'),
    youtubeTags: value('sa-yttags'),
    youtubePrivacy: value('sa-ytpriv'),
    captionTemplate: value('sa-caption'),
    active: checked('sa-active'),
    targets: targets
  };
  try {
    var saved = await socialApi('accounts', { account: account });
    socialEditing = null;
    socialToast(saved.note || 'Аккаунт сохранён', /не удалось/.test(saved.note || ''));
    await loadSocial();
  } catch (e) { socialToast('Ошибка: ' + e.message, true); }
};

window.socialDeleteAccount = async function (id) {
  if (!confirm('Удалить аккаунт вместе с его очередью роликов?')) return;
  await socialApi('accounts/delete', { id: id });
  socialEditing = null;
  await loadSocial();
};

window.socialSyncAccount = async function (id) {
  socialToast('Смотрю папку на Диске…');
  try {
    var res = await socialApi('sync', { accountId: id });
    var added = (res.results || []).reduce(function (sum, r) { return sum + (r.added || 0); }, 0);
    var failed = (res.results || []).filter(function (r) { return r.status === 'error'; });
    if (failed.length) socialToast(failed[0].message, true);
    else socialToast(added ? ('Добавлено роликов: ' + added) : 'Новых роликов на Диске нет');
    await loadSocial();
  } catch (e) { socialToast('Ошибка: ' + e.message, true); }
};

window.socialSavePost = async function (id) {
  await socialApi('posts/update', {
    id: id,
    title: document.getElementById('sp-title-' + id).value,
    caption: document.getElementById('sp-caption-' + id).value
  });
  socialToast('Сохранено');
};

window.socialDeletePost = async function (id) {
  if (!confirm('Убрать ролик из очереди? Файл на Google Диске останется.')) return;
  await socialApi('posts/delete', { id: id });
  await loadSocial();
};

window.socialPublishNow = async function (id) {
  if (!confirm('Опубликовать ролик прямо сейчас?')) return;
  try {
    await socialApi('posts/update', {
      id: id,
      title: document.getElementById('sp-title-' + id).value,
      caption: document.getElementById('sp-caption-' + id).value
    });
    var res = await socialApi('posts/publish', { id: id });
    socialToast(res.message || 'Публикация запущена');
    await loadSocial();
    // Instagram кодирует ролик несколько минут — подтягиваем статус сами.
    var ticks = 0;
    var timer = setInterval(async function () {
      ticks += 1;
      await loadSocial();
      var post = (socialState.posts || []).find(function (p) { return p.id === id; });
      if (ticks > 40 || !post || post.status !== 'processing') clearInterval(timer);
    }, 15000);
  } catch (e) { socialToast('Ошибка: ' + e.message, true); }
};

document.getElementById('social-add-account-btn').addEventListener('click', function () {
  socialEditing = 'new';
  renderSocialAccounts();
});

document.getElementById('social-save-settings-btn').addEventListener('click', async function () {
  try {
    await socialApi('settings', {
      googleClientId: document.getElementById('social-client-id').value,
      googleClientSecret: document.getElementById('social-client-secret').value,
      googleRefreshToken: document.getElementById('social-refresh-token').value,
      googleApiKey: document.getElementById('social-api-key').value
    });
    document.getElementById('social-client-secret').value = '';
    document.getElementById('social-refresh-token').value = '';
    document.getElementById('social-api-key').value = '';
    socialToast('Настройки сохранены');
    await loadSocial();
  } catch (e) { socialToast('Ошибка: ' + e.message, true); }
});

document.getElementById('social-check-btn').addEventListener('click', async function () {
  var box = document.getElementById('social-check-result');
  box.innerHTML = '<div style="color:var(--text-muted);font-size:13px;">Проверяю…</div>';
  try {
    var res = await socialApi('check', {});
    box.innerHTML = (res.checks || []).map(function (c) {
      var color = c.ok ? 'var(--success)' : 'var(--danger)';
      var bg = c.ok ? 'var(--success-subtle)' : 'var(--danger-subtle)';
      return '<div style="display:flex;gap:10px;align-items:flex-start;background:' + bg + ';border-radius:10px;padding:9px 12px;margin-bottom:6px;font-size:12.5px;">'
        + '<b style="color:' + color + ';white-space:nowrap;">' + (c.ok ? '✓' : '✕') + ' ' + socialEsc(c.name) + '</b>'
        + '<span style="color:var(--text);">' + socialEsc(c.message) + '</span></div>';
    }).join('') || '<div style="color:var(--text-muted);font-size:13px;">Нечего проверять — сначала добавь аккаунт.</div>';
  } catch (e) {
    box.innerHTML = '<div style="color:var(--danger);font-size:13px;">Ошибка: ' + socialEsc(e.message) + '</div>';
  }
});

document.getElementById('social-sync-btn').addEventListener('click', function () { window.socialSyncAccount(null); });
document.getElementById('social-refresh-btn').addEventListener('click', loadSocial);
document.getElementById('social-run-btn').addEventListener('click', async function () {
  var res = await socialApi('run', {});
  socialToast(res.message || 'Запущено');
  setTimeout(loadSocial, 4000);
});

// ── Тумблер доступа старых сборок к ИИ (карточка в разделе «Управление ИИ») ──
// Живёт здесь, а не в основном скрипте админки: тот собран экранированной
// строкой внутри worker.js и правится только скриптами.
(function () {
  var aiView = document.getElementById('ai-view');
  if (!aiView) return;

  var card = document.createElement('div');
  card.className = 'card';
  card.innerHTML = '<div class="card-head"><div class="card-title">'
    + '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>'
    + '<span>Доступ к ИИ извне</span></div>'
    + '<span id="ai-key-state" style="font-size:12px;color:var(--text-muted);"></span></div>'
    + '<label style="display:flex;gap:9px;align-items:flex-start;cursor:pointer;font-size:13.5px;">'
    + '<input type="checkbox" id="ai-legacy-toggle" style="margin-top:3px;">'
    + '<span>Пускать приложения без ключа<br><span style="font-size:12px;color:var(--text-muted);">'
    + 'Нужно, пока у людей стоят версии, выпущенные до появления ключа: им доступен только разбор вопроса, без чата и не более 40 запросов в сутки с адреса. '
    + 'Когда обновление разойдётся по магазинам — сними галочку, и посторонние потеряют доступ к нейросети полностью.</span></span></label>';
  aiView.appendChild(card);

  var toggle = card.querySelector('#ai-legacy-toggle');
  var state = card.querySelector('#ai-key-state');

  async function loadLegacyFlag() {
    try {
      var res = await fetch('/api/admin/ai/legacy');
      if (!res.ok) return;
      var data = await res.json();
      toggle.checked = data.open;
      state.textContent = data.hasAppKey ? 'ключ приложения задан' : 'ключ приложения не задан — подписывать запросы нечем';
      state.style.color = data.hasAppKey ? 'var(--success)' : 'var(--danger)';
    } catch (e) { /* раздел ИИ мог ещё не открываться */ }
  }

  toggle.addEventListener('change', async function () {
    await fetch('/api/admin/ai/legacy', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ open: toggle.checked })
    });
    socialToast(toggle.checked ? 'Старые сборки снова пускаем' : 'Доступ без ключа закрыт');
  });

  document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (btn) {
    if (btn.dataset.feature === 'ai') btn.addEventListener('click', loadLegacyFlag);
  });
  loadLegacyFlag();
})();

// Раздел добавлен после того, как основной скрипт уже разобрал меню, поэтому
// переключение вкладки довешиваем отдельно.
VIEW_TITLES.social = 'Автопостинг в Instagram и YouTube';
document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (btn) {
  btn.addEventListener('click', function () {
    var view = document.getElementById('social-view');
    if (btn.dataset.feature === 'social') {
      view.style.display = 'block';
      loadSocial();
    } else {
      view.style.display = 'none';
    }
  });
});
`;
