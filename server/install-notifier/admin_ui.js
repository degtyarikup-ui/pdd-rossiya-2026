// Общие улучшения оболочки админки. Исходная разметка старой панели хранится
// одной экранированной строкой в worker.js, поэтому поддерживаемые изменения
// применяем здесь во время сборки страницы.

export const ADMIN_UI_STYLES = `
<style id="admin-ui-enhancements">
  .sidebar-context {
    margin: 2px 12px 8px;
    padding: 12px;
    border-radius: 14px;
    background: var(--bg);
  }
  .sidebar-context .project-select-label { margin-bottom: 7px; }
  .sidebar-context .sidebar-select { background: #fff; }
  .sidebar-footer .project-picker-placeholder { display: none; }
  .admin-data-state {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    min-height: 36px;
    padding: 0 10px;
    border-radius: 10px;
    color: var(--text-muted);
    font-size: 11.5px;
    font-weight: 600;
    white-space: nowrap;
  }
  .admin-data-state::before {
    content: '';
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #B6BAC5;
  }
  .admin-data-state.loading::before { background: var(--primary); animation: adminPulse 1s ease-in-out infinite; }
  .admin-data-state.ready::before { background: var(--success); }
  .admin-data-state.error { color: var(--danger); background: var(--danger-subtle); }
  .admin-data-state.error::before { background: var(--danger); }
  @keyframes adminPulse { 50% { opacity: .35; } }
  .admin-error-banner {
    display: none;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    margin: -8px 0 18px;
    padding: 11px 14px;
    border-radius: 12px;
    color: #B52F16;
    background: var(--danger-subtle);
    font-size: 12.5px;
    font-weight: 600;
  }
  .admin-error-banner.visible { display: flex; }
  .admin-error-banner button { flex-shrink: 0; }
  .card-head { gap: 12px; }
  .blog-toolbar { margin: -2px 0 14px; }
  .blog-toolbar input { width: min(420px, 100%); }
  button:focus-visible, input:focus-visible, select:focus-visible, textarea:focus-visible, a:focus-visible {
    outline: 3px solid rgba(5,116,248,.22);
    outline-offset: 2px;
  }
  /* Сворачивание бокового меню */
  .sidebar {
    transition: width 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .sidebar-brand {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 14px 16px 16px;
    gap: 8px;
    border: none;
    box-sizing: border-box;
  }
  .brand-info {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    cursor: default;
    overflow: hidden;
  }
  .brand-info img {
    width: 34px;
    height: 34px;
    border-radius: 9px;
    flex-shrink: 0;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  }
  .brand-text, .sidebar-brand-title {
    font-size: 15px;
    font-weight: 800;
    color: var(--text);
    line-height: 1.2;
    letter-spacing: -0.3px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sidebar-toggle-btn {
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-muted);
    border-radius: 8px;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    flex-shrink: 0;
    transition: all 0.15s ease;
    padding: 0;
    position: relative;
  }
  .sidebar-toggle-btn:hover {
    background: var(--surface-gray, #F1F5F9);
    color: var(--text, #1E232D);
    border-color: var(--card-border, #E2E8F0);
  }
  .sidebar.collapsed {
    width: 68px;
  }
  /* Полностью скрываем весь текст и лишние блоки в свернутом меню */
  .sidebar.collapsed .brand-text,
  .sidebar.collapsed .sidebar-brand-title,
  .sidebar.collapsed .sidebar-brand > div:not(.brand-info),
  .sidebar.collapsed .brand-info > div,
  .sidebar.collapsed .brand-info .brand-text,
  .sidebar.collapsed .sidebar-context {
    display: none !important;
    visibility: hidden !important;
    opacity: 0 !important;
    width: 0 !important;
    height: 0 !important;
    margin: 0 !important;
    padding: 0 !important;
    overflow: hidden !important;
    pointer-events: none !important;
  }
  .sidebar.collapsed .sidebar-brand {
    padding: 14px 6px 10px;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    box-sizing: border-box;
  }
  .sidebar.collapsed .brand-info {
    display: flex !important;
    justify-content: center !important;
    cursor: pointer !important;
    width: 100% !important;
    margin: 0 !important;
  }
  .sidebar.collapsed .brand-info img {
    width: 36px !important;
    height: 36px !important;
    border-radius: 10px !important;
    box-shadow: 0 2px 6px rgba(0,0,0,0.08) !important;
    transition: transform 0.15s ease !important;
  }
  .sidebar.collapsed .brand-info:hover img {
    transform: scale(1.05);
  }
  .sidebar.collapsed .sidebar-toggle-btn {
    width: 36px !important;
    height: 28px !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    background: var(--surface-gray, #F3F4F6) !important;
    color: var(--text, #1E232D) !important;
    border: 1px solid var(--card-border, #E5E7EB) !important;
    border-radius: 8px !important;
  }
  .sidebar.collapsed .sidebar-toggle-btn:hover {
    background: #E5E7EB !important;
    color: #000 !important;
  }
  .sidebar.collapsed .toggle-icon-collapse {
    display: none !important;
  }
  .sidebar.collapsed .toggle-icon-expand {
    display: block !important;
  }
  .sidebar.collapsed .sidebar-menu {
    padding: 8px 6px;
    align-items: center;
    gap: 5px;
  }
  .sidebar.collapsed .nav-item {
    width: 44px;
    height: 44px;
    padding: 0;
    justify-content: center;
    border-radius: 12px;
    gap: 0;
    position: relative;
  }
  .sidebar.collapsed .nav-item span {
    display: none !important;
  }
  .sidebar.collapsed .nav-item svg {
    margin: 0;
  }
  .sidebar.collapsed .sidebar-footer {
    padding: 14px 6px;
    align-items: center;
  }
  .sidebar.collapsed .sidebar-footer > div {
    display: none !important;
  }
  .sidebar.collapsed .btn-logout {
    width: 44px;
    height: 44px;
    padding: 0;
    justify-content: center;
    border-radius: 12px;
    gap: 0;
    position: relative;
  }
  .sidebar.collapsed .btn-logout span {
    display: none !important;
  }
  /* Плавающий тултип для свернутого меню — вынесен на body, никогда не обрезается overflow */
  #sidebar-tooltip-el {
    position: fixed;
    background: #1E232D;
    color: #FFFFFF;
    padding: 6px 12px;
    border-radius: 8px;
    font-size: 12px;
    font-weight: 600;
    line-height: 1.3;
    white-space: nowrap;
    pointer-events: none;
    z-index: 999999;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.28);
    opacity: 0;
    visibility: hidden;
    transform: translateY(-50%) translateX(-4px);
    transition: opacity 0.12s cubic-bezier(0, 0, 0.2, 1), transform 0.12s cubic-bezier(0, 0, 0.2, 1);
  }
  #sidebar-tooltip-el.visible {
    opacity: 1;
    visibility: visible;
    transform: translateY(-50%) translateX(0);
  }
  #sidebar-tooltip-el::before {
    content: '';
    position: absolute;
    left: -5px;
    top: 50%;
    transform: translateY(-50%);
    border-width: 5px 5px 5px 0;
    border-style: solid;
    border-color: transparent #1E232D transparent transparent;
    width: 0;
    height: 0;
  }
  @media (max-width: 760px) {
    /* Телефон: меню — горизонтальная лента сверху, контент на всю ширину. */
    #app { flex-direction: column; }
    .sidebar { width: 100% !important; height: auto; position: static; }
    .sidebar-toggle-btn { display: none !important; }
    .sidebar.collapsed { width: 100% !important; }
    .sidebar-menu { flex-direction: row; overflow-x: auto; padding: 8px 12px; gap: 4px; }
    .nav-item { white-space: nowrap; flex-shrink: 0; width: auto !important; height: auto !important; padding: 9px 12px !important; }
    .nav-item span { display: inline !important; }
    .sidebar-context { margin: 0 12px; }
    .sidebar-footer { display: none; }
    .top-bar, .header { flex-direction: column; align-items: stretch; }
    .top-actions { justify-content: flex-start; }
    .admin-data-state { display: none; }
    .main-area, .content { padding: 20px 16px; }
    .top-bar, .header { align-items: flex-start; gap: 14px; }
    .top-actions { flex-wrap: wrap; justify-content: flex-end; }
  }
</style>`;

export function enhanceAdminHtml(html) {
  let result = html.replace('</head>', ADMIN_UI_STYLES + '\n</head>');

  result = result.replace(
    /<div class="sidebar-brand">[\s\S]*?<\/div>(?=\s*(?:<div class="sidebar-context"|<nav class="sidebar-menu"))/,
    `<div class="sidebar-brand">
      <div class="brand-info" title="PDD Drive">
        <img src="https://pdd-drive.ru/assets/icon-192.png" alt="PDD"><span class="admin-brand-name">PDD Drive</span>
      </div>
      <button id="sidebar-toggle-btn" class="sidebar-toggle-btn" type="button" title="Свернуть меню (Cmd+B)" aria-label="Свернуть меню">
        <svg class="toggle-icon-collapse" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M15 19l-7-7 7-7"/>
        </svg>
        <svg class="toggle-icon-expand" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" style="display:none">
          <path d="M9 5l7 7-7 7"/>
        </svg>
      </button>
    </div>`
  );

  // Работаем только с российской версией — убираем переключатель проекта из сайдбара.
  result = result.replace(
    /\s*<div>\s*<div class="project-select-label">Проект<\/div>\s*<select id="sidebar-app-select"[\s\S]*?<\/select>\s*<\/div>/,
    ''
  );
  result = result.replace('<span>Генератор ссылок</span>', '<span>Ссылки</span>');
  result = result.replace('type="text" id="login-pwd"', 'type="password" id="login-pwd" aria-label="Пароль администратора"');
  result = result.replace('Введите ключ доступа к аналитике', 'Панель управления PDD Drive');
  result = result.replace('class="btn-logout" id="logout-btn"', 'class="btn-logout" id="logout-btn" aria-label="Выйти" title="Выйти"');
  result = result.replace(
    '<span class="brand-badge"><span class="live-dot"></span>LIVE</span>',
    ''
  );

  // Периоды по возрастанию: Сегодня · 7 · 30 · 90.
  result = result.replace(
    '<button class="active" data-days="7">7 дней</button>\n          <button data-days="1">Сегодня</button>',
    '<button data-days="1">Сегодня</button>\n          <button class="active" data-days="7">7 дней</button>'
  );
  result = result.replace(
    '<div class="top-actions" id="top-period-actions">',
    '<div class="top-actions" id="top-period-actions">\n        <span class="admin-data-state" id="admin-data-state" aria-live="polite">Ещё не обновлено</span>'
  );
  result = result.replace(
    '<!-- 1. ANALYTICS VIEW -->',
    '<div class="admin-error-banner" id="admin-error-banner" role="alert">' +
      '<span id="admin-error-text">Не удалось загрузить данные</span>' +
      '<button class="btn-action" id="admin-error-retry">Повторить</button>' +
    '</div>\n\n    <!-- 1. ANALYTICS VIEW -->'
  );
  const blogContainer = '<div id="blog-articles-container" style="display:grid; gap:12px;">';
  result = result.replace(
    blogContainer,
    '<div class="blog-toolbar"><input id="blog-search" type="search" placeholder="Найти статью" aria-label="Поиск статей"></div>\n        ' + blogContainer
  );
  return result;
}

export function enhanceAdminClientJs(js) {
  let result = js
    .replace("links: 'Генератор ссылок и кампании',", "links: 'Ссылки',")
    .replace("ai: 'Управление искусственным интеллектом',", "ai: 'Управление ИИ',\n    economy: 'Экономика',")
    .replace("users: 'Пользователи и Премиум-доступ',", "users: 'Пользователи',")
    .replace("let currentFeature = 'analytics';", "let currentFeature = localStorage.getItem('pdd-admin-feature') || 'analytics';")
    .replace("let cachedBlogArticles = [];", "")
    .replace("let currentDays = 7;", "let currentDays = parseInt(localStorage.getItem('pdd-admin-days') || '7', 10);")
    .replace("let currentApp = 'all'; // 'all' | 'ru' | 'rs'", "let currentApp = 'ru';")
    .replace(
      "currentFeature = btn.dataset.feature;",
      "currentFeature = btn.dataset.feature;\n    localStorage.setItem('pdd-admin-feature', currentFeature);\n    if (history.pushState && location.hash.split('/')[0] !== '#' + currentFeature) history.pushState(null, '', '#' + currentFeature);"
    )
    .replace(
      "document.getElementById('sidebar-app-select').addEventListener('change', (e) => {\n  currentApp = e.target.value;\n  checkAuthAndLoad();\n});",
      ""
    )
    .replace(
      "currentDays = parseInt(btn.dataset.days, 10);\n    checkAuthAndLoad();",
      "currentDays = parseInt(btn.dataset.days, 10);\n    localStorage.setItem('pdd-admin-days', String(currentDays));\n    checkAuthAndLoad();"
    )
    .replace(
      "setInterval(checkAuthAndLoad, 30000);",
      "setInterval(() => { if (!document.hidden && currentFeature === 'analytics') checkAuthAndLoad(); }, 60000);"
    )
    .replace(
      "const allViews = ['analytics-view', 'links-view', 'blog-view', 'threads-view', 'users-view', 'ai-view'];",
      "const allViews = ['analytics-view', 'links-view', 'publications-view', 'blog-view', 'threads-view', 'users-view', 'ai-view', 'economy-view'];"
    )
    .replace("else if (currentFeature === 'blog') loadBlogArticles();", "")
    .replace(
      "else if (currentFeature === 'ai') loadAiStats();",
      "else if (currentFeature === 'ai') loadAiStats();\n    else if (currentFeature === 'economy' && typeof window.loadEconomy === 'function') window.loadEconomy();"
    );

  // Кампании и источники приходят с публичных ссылок — только через adminEsc.
  result = result
    .replace("'<td><span class=\"code-badge\">' + c.name + '</span></td>'", "'<td><span class=\"code-badge\">' + adminEsc(c.name) + '</span></td>'")
    .replace("'<span class=\"code-badge\">' + ev.campaign + '</span>'", "'<span class=\"code-badge\">' + adminEsc(ev.campaign) + '</span>'")
    .replace("+ '<span>' + conf.name + '</span>'", "+ '<span>' + adminEsc(conf.name) + '</span>'")
    .replace("+ flag + '</span> ' + c + '</span>';", "+ adminEsc(flag) + '</span> ' + adminEsc(c) + '</span>';");

  result = result.replace(
    "const res = await fetch('/api/admin/ai/stats');\n    if (res.status === 401) { checkAuthAndLoad(); return; }\n    const data = await res.json();",
    "const res = await fetch('/api/admin/ai/stats');\n    if (res.status === 401) { checkAuthAndLoad(); return; }\n    const data = await res.json();\n    if (!res.ok) throw new Error(data.error || ('ошибка сервера ' + res.status));"
  ).replace(
    "console.error('loadAiStats error:', err);",
    "console.error('loadAiStats error:', err);\n    if (typeof scToast === 'function') scToast('Статистика ИИ не загрузилась: ' + err.message, true);"
  ).replace(
    "document.getElementById('ai-m-model').innerText = activeModel;",
    "const modelOption = Array.from(document.getElementById('ai-model-select').options).find(option => option.value === activeModel);\n    document.getElementById('ai-m-model').innerText = modelOption ? modelOption.text : activeModel;"
  );

  // Старая отрисовка аналитики (Chart.js) заменена модулем analytics_ui.js.
  const dashStart = result.indexOf('// ────────────────────── Dashboard Analytics Rendering');
  const dashEnd = result.indexOf('// ────────────────────── Link Generator Module', dashStart);
  if (dashStart !== -1 && dashEnd > dashStart) {
    result = result.slice(0, dashStart) + result.slice(dashEnd);
  }

  // Старый генератор ссылок заменён модулем links_ui.js.
  const linkStart = result.indexOf('// ────────────────────── Link Generator Module');
  const linkEnd = result.indexOf('// ────────────────────── Blog Articles Module', linkStart);
  if (linkStart !== -1 && linkEnd > linkStart) {
    result = result.slice(0, linkStart) + result.slice(linkEnd);
  }

  // Старый список пользователей заменён модулем users_ui.js — вырезаем его
  // целиком, иначе он навесит обработчики на уже несуществующую таблицу.
  const usersStart = result.indexOf('// ────────────────────── Users & Premium Management');
  const usersEnd = result.indexOf('// ────────────────────── AI Management', usersStart);
  if (usersStart !== -1 && usersEnd > usersStart) {
    result = result.slice(0, usersStart) + result.slice(usersEnd);
  }

  // Статьи теперь управляются модулем blog_ui.js внутри публикаций. Удаляем старый
  // клиент целиком: его обработчики обращаются к отсутствующим кнопкам.
  const blogStart = result.indexOf('// ────────────────────── Blog Articles Module');
  const blogEnd = result.indexOf('// ────────────────────── Threads Module', blogStart);
  if (blogStart !== -1 && blogEnd > blogStart) {
    result = result.slice(0, blogStart) + result.slice(blogEnd);
  }

  const reliableLoader = `async function checkAuthAndLoad() {
  const requestId = ++window.__analyticsRequestId;
  const state = document.getElementById('admin-data-state');
  const banner = document.getElementById('admin-error-banner');
  if (state) { state.className = 'admin-data-state loading'; state.textContent = 'Обновление…'; }
  try {
    const r = await fetch('/api/admin/stats?days=' + currentDays + '&app=' + currentApp);
    if (requestId !== window.__analyticsRequestId) return;
    if (r.status === 401 || r.status === 403) {
      document.getElementById('login-overlay').style.display = 'flex';
      document.getElementById('app').style.display = 'none';
      return;
    }
    if (!r.ok) throw new Error('Сервер вернул ошибку ' + r.status);
    const data = await r.json();
    if (requestId !== window.__analyticsRequestId) return;
    document.getElementById('login-overlay').style.display = 'none';
    document.getElementById('app').style.display = 'flex';
    renderDashboard(data);
    window.__analyticsUpdatedAt = new Date();
    if (state) {
      state.className = 'admin-data-state ready';
      state.textContent = 'Обновлено ' + window.__analyticsUpdatedAt.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    }
    if (banner) banner.classList.remove('visible');
  } catch (err) {
    if (requestId !== window.__analyticsRequestId) return;
    if (state) { state.className = 'admin-data-state error'; state.textContent = 'Нет обновления'; }
    var errorText = document.getElementById('admin-error-text');
    if (errorText) errorText.textContent = 'Не удалось обновить данные. Последние загруженные значения оставлены на экране.';
    if (banner) banner.classList.add('visible');
    console.error('checkAuthAndLoad error:', err);
  }
}

async function handleLoginSubmit`;

  result = result.replace(
    /async function checkAuthAndLoad\(\) \{[\s\S]*?\n\}\n\nasync function handleLoginSubmit/,
    reliableLoader
  );
  // Начальная загрузка раздела могла получить 401 до входа. После успешного
  // входа загружаем его заново и отменяем ответы прежней попытки.
  const loginStart = result.indexOf('async function handleLoginSubmit()');
  const loginEnd = result.indexOf("document.getElementById('login-submit-btn')", loginStart);
  if (loginStart !== -1 && loginEnd > loginStart) {
    const loginJs = result.slice(loginStart, loginEnd).replace(
      '    checkAuthAndLoad();',
      `    await checkAuthAndLoad();
    if (currentFeature === 'publications' && typeof window.pubOpen === 'function') {
      if (typeof pbLoadId !== 'undefined') pbLoadId += 1;
      if (typeof pbLoading !== 'undefined') pbLoading = false;
      if (typeof pbLoaded !== 'undefined') pbLoaded = false;
      var publicationRefresh = document.getElementById('pb-refresh');
      if (publicationRefresh) publicationRefresh.disabled = false;
      window.pubOpen(typeof pbWorkspace !== 'undefined' ? pbWorkspace : 'plan', false);
    }`
    );
    result = result.slice(0, loginStart) + loginJs + result.slice(loginEnd);
  }
  const helpers = `window.__analyticsRequestId = 0;
function adminEsc(value) {
  return String(value == null ? '' : value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function adminInlineJs(value) {
  return adminEsc(String(value == null ? '' : value).replace(/\\\\/g, '\\\\\\\\')
    .replace(/'/g, "\\\\'").replace(/[\\r\\n]+/g, ' '));
}
async function adminFetchJson(url, options) {
  var response = await fetch(url, options);
  var data = null;
  try { data = await response.json(); } catch (_) {}
  if (!response.ok) throw new Error((data && data.error) || ('ошибка сервера ' + response.status));
  return data;
}
function adminToast(message, isError) {
  if (typeof scToast === 'function') scToast(message, Boolean(isError));
  else if (isError) alert(message);
}
`;
  return helpers + result;
}

export const ADMIN_UI_CLIENT_JS = `
// Общая оболочка: контекст проекта, восстановление раздела и состояния данных.
(function () {
  var projectSelect = document.getElementById('sidebar-app-select');
  var projectContext = document.getElementById('sidebar-context');
  if (projectSelect && projectContext) {
    var picker = projectSelect.parentElement;
    projectContext.appendChild(picker);
    projectSelect.value = currentApp;
  }

  function syncProjectContext() {
    if (projectContext) projectContext.style.display = currentFeature === 'analytics' ? 'block' : 'none';
  }
  document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (button) {
    button.addEventListener('click', syncProjectContext);
  });

  document.querySelectorAll('#period-buttons button').forEach(function (button) {
    button.classList.toggle('active', parseInt(button.dataset.days, 10) === currentDays);
  });

  var retry = document.getElementById('admin-error-retry');
  if (retry) retry.addEventListener('click', checkAuthAndLoad);

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') return;
    var dialogs = document.querySelectorAll('.sc-modal-bg, .admin-dialog-backdrop');
    if (dialogs.length) dialogs[dialogs.length - 1].remove();
  });

  // #users/<id> — карточка пользователя внутри раздела «Пользователи».
  // Сохраняем прежние ссылки и выбранные в прошлой панели разделы.
  var publicationAliases = Object.assign(Object.create(null), { blog: 'blog', threads: 'threads', social: 'videos' });
  function adminRouteFeature(rawRoute) {
    var feature = String(rawRoute || '').split('/')[0];
    var workspace = publicationAliases[feature];
    if (workspace) {
      if (history.replaceState) history.replaceState(null, '', '#publications/' + workspace);
      return 'publications';
    }
    return feature;
  }
  var initial = adminRouteFeature(location.hash ? location.hash.slice(1) : currentFeature);
  var allowed = ['analytics', 'tasks', 'links', 'publications', 'users', 'ai', 'economy', 'notifications'];
  if (allowed.indexOf(initial) === -1) initial = 'analytics';
  var initialButton = document.querySelector('.sidebar-menu .nav-item[data-feature="' + initial + '"]');
  if (initialButton) initialButton.click();
  if (initial === 'economy' && typeof window.loadEconomy === 'function') window.loadEconomy();

  window.addEventListener('popstate', function () {
    var oldFeature = location.hash.slice(1).split('/')[0];
    var feature = adminRouteFeature(location.hash.slice(1));
    if (feature === 'publications' && publicationAliases[oldFeature] && typeof window.pubOpen === 'function') {
      window.pubOpen(publicationAliases[oldFeature], false);
    }
    if (feature === 'economy' && typeof window.loadEconomy === 'function') {
      window.loadEconomy();
    }
    if (feature === currentFeature || allowed.indexOf(feature) === -1) return;
    var button = document.querySelector('.sidebar-menu .nav-item[data-feature="' + feature + '"]');
    if (button) button.click();
    if (feature === 'economy' && typeof window.loadEconomy === 'function') {
      window.loadEconomy();
    }
  });
  // Сворачивание и разворачивание левого меню
  var sidebar = document.querySelector('.sidebar');
  var toggleBtn = document.getElementById('sidebar-toggle-btn');
  var brandInfo = document.querySelector('.brand-info');
  var isSidebarCollapsed = localStorage.getItem('pdd-admin-sidebar-collapsed') === 'true';

  // Плавающий тултип вне сайдбара (на body), чтобы он никогда не обрезался overflow контейнеров
  var floatingTip = document.createElement('div');
  floatingTip.id = 'sidebar-tooltip-el';
  document.body.appendChild(floatingTip);

  var tipActiveEl = null;

  function showSidebarTooltip(el, text) {
    if (!text || !sidebar || !sidebar.classList.contains('collapsed')) {
      hideSidebarTooltip();
      return;
    }
    tipActiveEl = el;
    floatingTip.textContent = text;
    var rect = el.getBoundingClientRect();
    floatingTip.style.left = (rect.right + 10) + 'px';
    floatingTip.style.top = (rect.top + rect.height / 2) + 'px';
    floatingTip.classList.add('visible');
  }

  function hideSidebarTooltip() {
    tipActiveEl = null;
    floatingTip.classList.remove('visible');
  }

  document.querySelectorAll('.sidebar-menu .nav-item').forEach(function (btn) {
    var span = btn.querySelector('span');
    if (span && !btn.dataset.tooltip) {
      btn.dataset.tooltip = span.textContent.trim();
    }
  });
  var logoutBtn = document.getElementById('logout-btn');
  if (logoutBtn && !logoutBtn.dataset.tooltip) {
    logoutBtn.dataset.tooltip = 'Выйти';
  }

  function setSidebarCollapsed(collapsed) {
    if (!sidebar) return;
    sidebar.classList.toggle('collapsed', collapsed);
    localStorage.setItem('pdd-admin-sidebar-collapsed', collapsed ? 'true' : 'false');
    hideSidebarTooltip();
    if (toggleBtn) {
      toggleBtn.setAttribute('aria-label', collapsed ? 'Развернуть меню (Cmd+B)' : 'Свернуть меню (Cmd+B)');
      if (collapsed) {
        toggleBtn.removeAttribute('title');
        toggleBtn.dataset.tooltip = 'Развернуть (Cmd+B)';
      } else {
        toggleBtn.title = 'Свернуть меню (Cmd+B)';
        delete toggleBtn.dataset.tooltip;
      }
    }
    if (brandInfo) {
      if (collapsed) {
        brandInfo.removeAttribute('title');
        brandInfo.dataset.tooltip = 'Развернуть (Cmd+B)';
      } else {
        brandInfo.title = 'PDD Drive';
        delete brandInfo.dataset.tooltip;
      }
    }
  }

  if (isSidebarCollapsed) {
    setSidebarCollapsed(true);
  } else {
    setSidebarCollapsed(false);
  }

  if (toggleBtn) {
    toggleBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      setSidebarCollapsed(!sidebar.classList.contains('collapsed'));
    });
  }

  if (brandInfo) {
    brandInfo.addEventListener('click', function () {
      if (sidebar && sidebar.classList.contains('collapsed')) {
        setSidebarCollapsed(false);
      }
    });
  }

  document.addEventListener('mouseover', function (e) {
    if (!sidebar || !sidebar.classList.contains('collapsed')) return;
    var target = e.target.closest('.sidebar [data-tooltip]');
    if (target) {
      showSidebarTooltip(target, target.dataset.tooltip);
    }
  });

  document.addEventListener('mouseout', function (e) {
    if (!tipActiveEl) return;
    var target = e.target.closest('.sidebar [data-tooltip]');
    if (target && target === tipActiveEl) {
      hideSidebarTooltip();
    }
  });

  window.addEventListener('scroll', hideSidebarTooltip, true);

  document.addEventListener('keydown', function (e) {
    if ((e.metaKey || e.ctrlKey) && (e.key === 'b' || e.key === 'B' || e.key === 'и' || e.key === 'И')) {
      e.preventDefault();
      setSidebarCollapsed(!sidebar.classList.contains('collapsed'));
    }
  });

  syncProjectContext();
})();
`;
