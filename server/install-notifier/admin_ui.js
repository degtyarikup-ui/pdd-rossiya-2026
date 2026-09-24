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
  button:disabled { cursor: not-allowed; opacity: .55; }
  @media (max-width: 760px) {
    /* Телефон: меню — горизонтальная лента сверху, контент на всю ширину. */
    #app { flex-direction: column; }
    .sidebar { width: 100%; height: auto; position: static; }
    .sidebar-menu { flex-direction: row; overflow-x: auto; padding: 8px 12px; gap: 4px; }
    .nav-item { white-space: nowrap; flex-shrink: 0; width: auto; padding: 9px 12px; }
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

  // Проект задаёт контекст данных, поэтому он расположен до навигации, а не
  // рядом с выходом. Сам select переносится клиентским кодом без дублирования.
  result = result.replace(
    '<nav class="sidebar-menu">',
    '<div class="sidebar-context" id="sidebar-context"></div>\n    <nav class="sidebar-menu">'
  );
  result = result.replace(
    '<div class="project-select-label">Проект</div>',
    '<div class="project-select-label">Данные аналитики</div>'
  );
  result = result.replace(
    '<option value="ru">Россия (RU)</option>',
    '<option value="ru">Россия (RU)</option>\n          <option value="by">Беларусь (BY)</option>'
  );
  result = result.replace('<span>Генератор ссылок</span>', '<span>Ссылки</span>');
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
    .replace("let currentFeature = 'analytics';", "let currentFeature = localStorage.getItem('pdd-admin-feature') || 'analytics';")
    .replace("let currentDays = 7;", "let currentDays = parseInt(localStorage.getItem('pdd-admin-days') || '7', 10);")
    .replace("let currentApp = 'all'; // 'all' | 'ru' | 'rs'", "let currentApp = localStorage.getItem('pdd-admin-app') || 'all'; // 'all' | 'ru' | 'by' | 'rs'")
    .replace(
      "currentFeature = btn.dataset.feature;",
      "currentFeature = btn.dataset.feature;\n    localStorage.setItem('pdd-admin-feature', currentFeature);\n    if (history.pushState && location.hash.split('/')[0] !== '#' + currentFeature) history.pushState(null, '', '#' + currentFeature);"
    )
    .replace(
      "currentApp = e.target.value;\n  checkAuthAndLoad();",
      "currentApp = e.target.value;\n  localStorage.setItem('pdd-admin-app', currentApp);\n  checkAuthAndLoad();"
    )
    .replace(
      "currentDays = parseInt(btn.dataset.days, 10);\n    checkAuthAndLoad();",
      "currentDays = parseInt(btn.dataset.days, 10);\n    localStorage.setItem('pdd-admin-days', String(currentDays));\n    checkAuthAndLoad();"
    )
    .replace(
      "setInterval(checkAuthAndLoad, 30000);",
      "setInterval(() => { if (!document.hidden && currentFeature === 'analytics') checkAuthAndLoad(); }, 60000);"
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

  const blogStart = result.indexOf('async function loadBlogArticles()');
  const blogEnd = result.indexOf('// ────────────────────── Threads Module', blogStart);
  if (blogStart !== -1 && blogEnd > blogStart) {
    let blogJs = result.slice(blogStart, blogEnd);
    blogJs = blogJs
      .replace(
        "cachedBlogArticles = await res.json();",
        "cachedBlogArticles = await res.json();\n    if (!res.ok) throw new Error(cachedBlogArticles.error || ('ошибка сервера ' + res.status));"
      )
      .replace("+ coverUrl +", "+ adminEsc(coverUrl) +")
      .replace('width:140px;height:78px', 'width:112px;height:63px')
      .replace("+ a.title +", "+ adminEsc(a.title) +")
      .replace(/\s*\+ '<div style="font-size:11\.5px;color:var\(--text-muted\);margin-bottom:8px;">' \+ \(a\.description \|\| ''\) \+ '<\/div>'/, '')
      .replaceAll("+ a.slug +", "+ adminEsc(a.slug) +")
      .replace("+ a.datePublished +", "+ adminEsc(a.datePublished) +")
      .replace("+ err.message +", "+ adminEsc(err.message) +")
      .replace(
        /window\.updateArticleDate = async function\(slug\) \{[\s\S]*?\n\};/,
        `window.updateArticleDate = async function(slug) {
  var input = document.getElementById('date-' + slug);
  var newDate = input ? input.value : '';
  if (!newDate || window.__blogBusy) return;
  window.__blogBusy = true;
  try {
    await adminFetchJson('/api/admin/blog/' + encodeURIComponent(slug), {
      method: 'PUT', headers: {'content-type':'application/json'}, body: JSON.stringify({ datePublished: newDate })
    });
    await loadBlogArticles();
  } catch (err) {
    adminToast('Дата не сохранилась: ' + err.message, true);
    await loadBlogArticles();
  } finally { window.__blogBusy = false; }
};`
      )
      .replace(
        /window\.swapArticle = async function\(idx1, idx2\) \{[\s\S]*?\n\};/,
        `window.swapArticle = async function(idx1, idx2) {
  if (window.__blogBusy || idx1 < 0 || idx2 < 0 || idx1 >= cachedBlogArticles.length || idx2 >= cachedBlogArticles.length) return;
  var a1 = cachedBlogArticles[idx1], a2 = cachedBlogArticles[idx2];
  window.__blogBusy = true;
  try {
    await adminFetchJson('/api/admin/blog/reorder', {
      method: 'POST', headers: {'content-type':'application/json'},
      body: JSON.stringify({ changes: [
        { slug: a1.slug, datePublished: a2.datePublished },
        { slug: a2.slug, datePublished: a1.datePublished }
      ] })
    });
    await loadBlogArticles();
  } catch (err) {
    adminToast('Порядок статей не изменился: ' + err.message, true);
  } finally { window.__blogBusy = false; }
};`
      )
      .replace(
        /window\.deleteBlogArticle = async function\(slug\) \{[\s\S]*?\n\};/,
        `window.deleteBlogArticle = async function(slug) {
  if (window.__blogBusy || !confirm('Удалить статью из публикаций?')) return;
  window.__blogBusy = true;
  try {
    await adminFetchJson('/api/admin/blog/' + encodeURIComponent(slug), { method: 'DELETE' });
    await loadBlogArticles();
  } catch (err) {
    adminToast('Статья не удалена: ' + err.message, true);
  } finally { window.__blogBusy = false; }
};`
      )
      .replace(
        /document\.getElementById\('reset-blog-btn'\)\.addEventListener\('click', async \(\) => \{[\s\S]*?\n\}\);/,
        `document.getElementById('reset-blog-btn').addEventListener('click', async () => {
  if (window.__blogBusy || !confirm('Сбросить список статей к исходному состоянию?')) return;
  window.__blogBusy = true;
  try {
    await adminFetchJson('/api/admin/blog/reset', { method: 'POST' });
    await loadBlogArticles();
  } catch (err) {
    adminToast('Список не сброшен: ' + err.message, true);
  } finally { window.__blogBusy = false; }
});`
      );
    result = result.slice(0, blogStart) + blogJs + result.slice(blogEnd);
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

  var blogSearch = document.getElementById('blog-search');
  var blogContainer = document.getElementById('blog-articles-container');
  function filterBlogArticles() {
    if (!blogContainer) return;
    var query = (blogSearch ? blogSearch.value : '').trim().toLocaleLowerCase('ru');
    Array.from(blogContainer.children).forEach(function (card) {
      card.style.display = !query || card.textContent.toLocaleLowerCase('ru').indexOf(query) !== -1 ? '' : 'none';
    });
  }
  if (blogSearch) blogSearch.addEventListener('input', filterBlogArticles);
  if (blogContainer) new MutationObserver(filterBlogArticles).observe(blogContainer, { childList: true });

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape') return;
    var dialogs = document.querySelectorAll('.sc-modal-bg, .admin-dialog-backdrop');
    if (dialogs.length) dialogs[dialogs.length - 1].remove();
  });

  // #users/<id> — карточка пользователя внутри раздела «Пользователи».
  var initial = (location.hash ? location.hash.slice(1) : currentFeature).split('/')[0];
  var allowed = ['analytics', 'links', 'blog', 'users', 'ai', 'threads', 'social'];
  if (allowed.indexOf(initial) === -1) initial = 'analytics';
  var initialButton = document.querySelector('.sidebar-menu .nav-item[data-feature="' + initial + '"]');
  if (initialButton) initialButton.click();

  window.addEventListener('popstate', function () {
    var feature = location.hash.slice(1).split('/')[0];
    if (feature === currentFeature || allowed.indexOf(feature) === -1) return;
    var button = document.querySelector('.sidebar-menu .nav-item[data-feature="' + feature + '"]');
    if (button) button.click();
  });
  syncProjectContext();
})();
`;
