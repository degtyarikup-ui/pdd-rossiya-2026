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
  .kpi-card { min-height: 112px; }
  .kpi-value { font-variant-numeric: tabular-nums; }
  .kpi-change { display: block; min-height: 16px; margin-top: 4px; color: var(--text-muted); font-size: 11.5px; font-weight: 600; }
  .kpi-change.up { color: #159461; }
  .kpi-change.down { color: var(--danger); }
  .card-head { gap: 12px; }
  .blog-toolbar { margin: -2px 0 14px; }
  .blog-toolbar input { width: min(420px, 100%); }
  button:focus-visible, input:focus-visible, select:focus-visible, textarea:focus-visible, a:focus-visible {
    outline: 3px solid rgba(5,116,248,.22);
    outline-offset: 2px;
  }
  button:disabled { cursor: not-allowed; opacity: .55; }
  @media (max-width: 760px) {
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
  result = result.replace(
    '<span class="brand-badge"><span class="live-dot"></span>LIVE</span>',
    ''
  );

  // Процент показываем один раз и называем формулой, которую действительно
  // считает аналитика. Число кликов остаётся самостоятельным показателем.
  result = result.replace(
    '<span class="kpi-badge badge-blue" id="m-ctr">CTR: 0%</span>',
    '<span id="m-ctr" hidden></span>'
  );
  result = result.replace(
    '<span class="kpi-label">Конверсия лендинга</span>\n            <span class="kpi-badge badge-green">CR %</span>',
    '<span class="kpi-label">Доля переходов</span>\n            <span class="kpi-badge badge-blue">Клики / визиты</span>'
  );
  result = result
    .replace('<div class="kpi-value" id="m-installs">0</div>', '<div class="kpi-value" id="m-installs">0</div><span class="kpi-change" id="m-installs-change"></span>')
    .replace('<div class="kpi-value" id="m-views">0</div>', '<div class="kpi-value" id="m-views">0</div><span class="kpi-change" id="m-views-change"></span>')
    .replace('<div class="kpi-value" id="m-clicks">0</div>', '<div class="kpi-value" id="m-clicks">0</div><span class="kpi-change" id="m-clicks-change"></span>');
  result = result
    .replace('Воронка веб-маркетинга (Визиты и Клики)', 'Визиты и переходы')
    .replace('Живая лента событий', 'Последние события')
    .replace('<span class="kpi-badge badge-green">АКТИВНА</span>', '');

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
    .replace('tension: 0.3,', 'tension: 0,')
    .replace('tension: 0.3,', 'tension: 0,')
    .replace("chartInstalls = new Chart(ctxInstalls, {\n    type: 'line',", "chartInstalls = new Chart(ctxInstalls, {\n    type: 'bar',")
    .replaceAll("type: 'doughnut',", "type: 'bar',")
    .replace('data: storeValues.some(v => v > 0) ? storeValues : [1, 1, 1],', 'data: storeValues,')
    .replace('data: srcValues.some(v => v > 0) ? srcValues : [1],', 'data: srcValues,')
    .replace("y: { grid: { color: 'rgba(0,0,0,0.04)' }, ticks: { color: '#64748b', font: { size: 11 } }, beginAtZero: true }", "y: { grid: { color: 'rgba(0,0,0,0.04)' }, ticks: { color: '#64748b', precision: 0, font: { size: 11 } }, beginAtZero: true }")
    .replace(
      "setInterval(checkAuthAndLoad, 30000);",
      "setInterval(() => { if (!document.hidden && currentFeature === 'analytics') checkAuthAndLoad(); }, 30000);"
    );

  // Кампании и источники приходят с публичных ссылок — только через adminEsc.
  result = result
    .replace("'<td><span class=\"code-badge\">' + c.name + '</span></td>'", "'<td><span class=\"code-badge\">' + adminEsc(c.name) + '</span></td>'")
    .replace("'<span class=\"code-badge\">' + ev.campaign + '</span>'", "'<span class=\"code-badge\">' + adminEsc(ev.campaign) + '</span>'")
    .replace("+ '<span>' + conf.name + '</span>'", "+ '<span>' + adminEsc(conf.name) + '</span>'")
    .replace("+ flag + '</span> ' + c + '</span>';", "+ adminEsc(flag) + '</span> ' + adminEsc(c) + '</span>';");

  result = result.replace(
    "document.getElementById('m-clicks').innerText = (data.totals.clicks || 0).toLocaleString();",
    "document.getElementById('m-clicks').innerText = (data.totals.clicks || 0).toLocaleString();\n  const previous = data.previous || {};\n  adminRenderChange('m-installs-change', data.totals.installs || 0, previous.installs || 0);\n  adminRenderChange('m-views-change', data.totals.views || 0, previous.views || 0);\n  adminRenderChange('m-clicks-change', data.totals.clicks || 0, previous.clicks || 0);"
  );

  result = result.replace(
    /document\.getElementById\('copy-link-btn'\)\.addEventListener\('click', \(\) => \{[\s\S]*?\n\}\);/,
    `document.getElementById('copy-link-btn').addEventListener('click', async () => {
  const url = document.getElementById('gen-output').innerText;
  const btn = document.getElementById('copy-link-btn');
  const original = btn.innerText;
  try {
    await navigator.clipboard.writeText(url);
    btn.innerText = 'Скопировано';
  } catch (_) {
    var range = document.createRange();
    range.selectNodeContents(document.getElementById('gen-output'));
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
    btn.innerText = 'Выделено — нажмите Ctrl+C';
  }
  setTimeout(() => { btn.innerText = original; }, 2200);
});`
  );

  result = result.replace(
    /function getDoughnutOptions\(\) \{[\s\S]*?\n\}/,
    `function getDoughnutOptions() {
  return {
    indexAxis: 'y',
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: { backgroundColor: '#0f172a', padding: 10, cornerRadius: 8 }
    },
    scales: {
      x: { beginAtZero: true, grid: { color: 'rgba(0,0,0,0.04)' }, ticks: { precision: 0, color: '#64748b' } },
      y: { grid: { display: false }, ticks: { color: '#475569', font: { size: 11.5, weight: '600' } } }
    }
  };
}`
  );

  result = result.replace(
    "const res = await fetch('/api/admin/ai/stats');\n    if (res.status === 401) { checkAuthAndLoad(); return; }\n    const data = await res.json();",
    "const res = await fetch('/api/admin/ai/stats');\n    if (res.status === 401) { checkAuthAndLoad(); return; }\n    const data = await res.json();\n    if (!res.ok) throw new Error(data.error || ('ошибка сервера ' + res.status));"
  ).replace(
    "console.error('loadAiStats error:', err);",
    "console.error('loadAiStats error:', err);\n    if (typeof scToast === 'function') scToast('Статистика ИИ не загрузилась: ' + err.message, true);"
  );

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
function adminRenderChange(id, current, previous) {
  var element = document.getElementById(id);
  if (!element) return;
  var delta = Number(current || 0) - Number(previous || 0);
  element.className = 'kpi-change' + (delta > 0 ? ' up' : delta < 0 ? ' down' : '');
  element.textContent = delta === 0 ? '' : (delta > 0 ? '+' : '') + delta.toLocaleString('ru-RU') + ' к прошлому периоду';
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
