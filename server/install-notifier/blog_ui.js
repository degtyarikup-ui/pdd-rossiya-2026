// Планирование статей внутри общего раздела «Публикации».
// Модуль работает с существующей очередью воркера; тело статьи редактируется
// в локальной админке блога. После изменения плана обновляется общий календарь.
export const BLOG_VIEW_HTML = String.raw`
<div id="blog-view" style="display:none;">
  <style>
    #blog-view .bl-panel { background:#fff; border:0; border-radius:22px; overflow:visible; color:#17191e; }
    #blog-view .bl-head { display:flex; justify-content:space-between; align-items:center; gap:16px; padding:26px 28px 22px; }
    #blog-view .bl-heading { font-size:20px; font-weight:650; letter-spacing:-.5px; margin:0 0 6px; }
    #blog-view .bl-caption { color:#747b88; font-size:12px; line-height:1.5; margin:0; }
    #blog-view .bl-toolbar { display:flex; align-items:center; justify-content:space-between; gap:14px; padding:0 28px 18px; flex-wrap:wrap; }
    #blog-view .bl-search { display:flex; align-items:center; gap:10px; background:#f4f5f7; border:0; border-radius:12px; padding:0 14px; flex:1 1 240px; max-width:420px; color:#747b88; }
    #blog-view .bl-search input { min-width:0; width:100%; background:transparent; border:0; padding:12px 0; font-size:13px; box-shadow:none; }
    #blog-view .bl-search:focus-within { outline:2px solid #0574f8; outline-offset:3px; }
    #blog-view .bl-search input:focus { background:transparent; outline:0; }
    #blog-view .bl-filters { display:flex; padding:4px; border-radius:24px; gap:3px; background:#f4f5f7; }
    #blog-view .bl-filter { display:flex; align-items:center; gap:7px; padding:8px 13px; color:#747b88; background:transparent; border:0; border-radius:20px; font-size:12px; font-weight:550; cursor:pointer; white-space:nowrap; }
    #blog-view .bl-filter.active { background:#17191e; color:#fff; }
    #blog-view .bl-filter span { font-size:10px; font-weight:600; color:inherit; opacity:.65; font-variant-numeric:tabular-nums; }
    #blog-view .bl-summary { display:flex; justify-content:space-between; flex-wrap:wrap; gap:8px; padding:0 28px 16px; font-size:11px; color:#747b88; }
    #blog-view .bl-error { margin:0 28px 16px; padding:14px 16px; background:#fff0ec; color:#c34527; border:0; border-radius:14px; font-size:12px; line-height:1.5; }
    #blog-view .bl-row { display:grid; grid-template-columns:104px minmax(0,1fr) 146px 100px; gap:22px; align-items:center; padding:22px 28px; border-top:1px solid #f0f2f5; }
    #blog-view .bl-cover { display:block; width:104px; height:72px; border-radius:12px; background:#f4f5f7; overflow:hidden; }
    #blog-view .bl-cover img { width:100%; height:100%; object-fit:cover; }
    #blog-view .bl-title { font-size:14px; font-weight:600; color:#17191e; line-height:1.5; text-decoration:none; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
    #blog-view .bl-title:hover { color:#0574f8; }
    #blog-view .bl-meta { display:flex; align-items:center; flex-wrap:wrap; gap:12px; color:#747b88; font-size:11px; margin-top:8px; }
    #blog-view .bl-status { display:inline-flex; align-items:center; gap:5px; background:#e8f2ff; color:#0574f8; padding:4px 8px; border-radius:14px; font-size:10.5px; font-weight:550; }
    #blog-view .bl-status.today { color:#9b6900; background:#fff6da; }
    #blog-view .bl-status.past { background:#f4f5f7; color:#747b88; }
    #blog-view .bl-date { display:flex; flex-direction:column; gap:7px; min-width:146px; }
    #blog-view .bl-date label { font-size:10.5px; color:#747b88; font-weight:550; }
    #blog-view .bl-date input { width:146px; min-height:40px; padding:9px 12px; border:0; border-radius:11px; background:#f4f5f7; font-size:12px; font-weight:550; color:#17191e; font-variant-numeric:tabular-nums; }
    #blog-view .bl-date-actions { display:flex; gap:5px; }
    #blog-view .bl-date-actions[hidden] { display:none; }
    #blog-view .bl-date-actions button { font-size:11px; padding:7px 9px; border-radius:8px; }
    #blog-view .bl-row-actions { display:flex; align-items:center; justify-content:flex-end; gap:3px; }
    #blog-view .bl-icon { width:32px; height:32px; display:inline-flex; align-items:center; justify-content:center; background:transparent; border:0; border-radius:50%; color:#747b88; cursor:pointer; font-size:17px; text-decoration:none; }
    #blog-view .bl-icon:hover { background:#f0f2f5; color:#17191e; }
    #blog-view .bl-icon:disabled { opacity:.25; cursor:default; }
    #blog-view .bl-menu { position:relative; }
    #blog-view .bl-menu summary { list-style:none; }
    #blog-view .bl-menu summary::-webkit-details-marker { display:none; }
    #blog-view .bl-menu[open] summary { background:#f0f2f5; color:#17191e; }
    #blog-view .bl-menu-content { position:absolute; right:0; top:38px; z-index:20; width:226px; padding:8px; border:0; border-radius:16px; background:#fff; box-shadow:0 10px 35px rgba(23,25,30,.12); }
    #blog-view .bl-menu-content button, #blog-view .bl-menu-content a { display:flex; width:100%; text-align:left; padding:11px 12px; background:none; border:0; border-radius:10px; text-decoration:none; font-size:12px; color:#17191e; font-weight:550; cursor:pointer; }
    #blog-view .bl-menu-content button:hover, #blog-view .bl-menu-content a:hover { background:#f4f5f7; }
    #blog-view .bl-menu-content .bl-danger { color:#c34527; }
    #blog-view .bl-empty { text-align:center; padding:64px 24px; font-size:13px; color:#747b88; line-height:1.8; }
    #blog-view .bl-empty strong { display:block; color:#17191e; font-size:16px; font-weight:600; margin-bottom:6px; }
    #blog-view .bl-help { font-size:12px; color:#747b88; padding:18px 28px 22px; line-height:1.65; }
    #blog-view .bl-help summary { cursor:pointer; list-style:none; display:inline-flex; gap:7px; align-items:center; font-size:11px; }
    #blog-view .bl-help summary::before { content:'i'; width:16px; height:16px; border-radius:50%; background:#f0f2f5; display:inline-flex; align-items:center; justify-content:center; font-size:10px; font-weight:650; }
    #blog-view .bl-help summary::-webkit-details-marker { display:none; }
    #blog-view .bl-help p { margin:12px 0 0; max-width:720px; }
    #blog-view button:focus-visible, #blog-view a:focus-visible, #blog-view summary:focus-visible, #blog-view input:focus-visible { outline:2px solid #0574f8; outline-offset:3px; }
    #blog-view .bl-head-actions { display:flex; align-items:center; gap:8px; }
    #blog-view .bl-detail { margin-top:9px; font-size:12px; color:#747b88; line-height:1.65; overflow-wrap:anywhere; }
    #blog-view .bl-detail summary { display:inline-flex; gap:5px; align-items:center; cursor:pointer; font-size:11px; list-style:none; }
    #blog-view .bl-detail summary::after { content:'⌄'; font-size:11px; }
    #blog-view .bl-detail[open] summary::after { content:'⌃'; }
    #blog-view .bl-detail summary::-webkit-details-marker { display:none; }
    #blog-view .bl-detail p { margin:10px 0 0; }
    @media (max-width:1050px) { #blog-view .bl-row { grid-template-columns:88px minmax(0,1fr) 142px 32px; gap:16px; } #blog-view .bl-cover { width:88px; height:64px; } #blog-view .bl-row-actions { flex-direction:column; } }
    @media (max-width:760px) { #blog-view .bl-head { padding:22px 20px 18px; } #blog-view .bl-toolbar { padding:0 20px 16px; } #blog-view .bl-summary { padding:0 20px 14px; } #blog-view .bl-row { grid-template-columns:72px minmax(0,1fr) 32px; gap:10px 14px; padding:20px; } #blog-view .bl-cover { width:72px; height:54px; align-self:start; } #blog-view .bl-date { grid-column:2; grid-row:2; align-items:flex-start; } #blog-view .bl-row-actions { grid-column:3; grid-row:1 / span 2; align-self:start; } #blog-view .bl-head-actions .btn-action { font-size:11px; padding:8px 11px; } #blog-view .bl-help { padding:18px 20px; } #blog-view .bl-heading { font-size:18px; } }
    @media (max-width:560px) { #blog-view .bl-head { align-items:flex-start; gap:10px; } #blog-view .bl-search { max-width:none; flex-basis:100%; } #blog-view .bl-filters { width:100%; } #blog-view .bl-filter { flex:1; justify-content:center; padding:8px; } #blog-view .bl-row { grid-template-columns:60px minmax(0,1fr) 28px; gap:10px; } #blog-view .bl-cover { width:60px; height:46px; } #blog-view .bl-title { font-size:13px; } #blog-view .bl-caption { font-size:11px; } #blog-view .bl-icon { width:28px; height:30px; } #blog-view .bl-date { margin-top:3px; } }
  </style>
  <section class="bl-panel" aria-labelledby="blog-workspace-title">
    <div class="bl-head">
      <div><h2 class="bl-heading" id="blog-workspace-title">Статьи блога</h2><p class="bl-caption">pdd-drive.ru</p></div>
      <div class="bl-head-actions">
        <button type="button" class="btn-action" id="refresh-blog-btn">Обновить</button>
        <details class="bl-menu"><summary class="bl-icon" aria-label="Настройки плана статей" title="Настройки">⋯</summary><div class="bl-menu-content"><button type="button" class="bl-danger" id="reset-blog-btn">Вернуть исходный план</button></div></details>
      </div>
    </div>
    <div class="bl-toolbar">
      <label class="bl-search"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg><input type="search" id="blog-search" placeholder="Найти статью" aria-label="Поиск статей" autocomplete="off"></label>
      <div class="bl-filters" role="group" aria-label="Период статей">
        <button type="button" class="bl-filter active" data-blog-filter="upcoming" aria-pressed="true">В плане <span id="blog-upcoming-count">0</span></button>
        <button type="button" class="bl-filter" data-blog-filter="past" aria-pressed="false">Прошедшие <span id="blog-past-count">0</span></button>
        <button type="button" class="bl-filter" data-blog-filter="all" aria-pressed="false">Все <span id="blog-count">0</span></button>
      </div>
    </div>
    <div class="bl-summary"><span id="blog-results" aria-live="polite">Загрузка плана…</span><span>Даты по МСК</span></div>
    <div id="blog-load-error" class="bl-error" role="alert" hidden></div>
    <div id="blog-articles-container"><div class="bl-empty">Загрузка статей…</div></div>
    <details class="bl-help"><summary>Как работает план</summary><p>Дата сохраняется кнопкой «Сохранить». Стрелки меняют местами даты двух соседних статей. «Прошедшие» показывает статьи с датой до сегодняшнего дня. Это не подтверждение публикации на сайте.</p></details>
  </section>
</div>
`;

export const BLOG_CLIENT_JS = String.raw`
// ────────────────────── Blog workspace ──────────────────────
var blState = { articles: [], loaded: false, loading: false, busy: false, filter: 'upcoming', search: '', drafts: {}, requestId: 0 };

function blToday() {
  var parts = new Intl.DateTimeFormat('en-CA', {timeZone:'Europe/Moscow', year:'numeric', month:'2-digit', day:'2-digit'}).formatToParts(new Date());
  var values = {}; parts.forEach(function(part) { values[part.type] = part.value; });
  return values.year + '-' + values.month + '-' + values.day;
}
function blArticleUrl(article) { return 'https://pdd-drive.ru/blog/' + encodeURIComponent(article.slug) + '/'; }
function blCoverUrl(article) {
  if (!article.cover) return 'https://pdd-drive.ru/assets/og-image.png';
  return blArticleUrl(article) + String(article.cover).split('/').map(encodeURIComponent).join('/');
}
function blVisibleArticles() {
  var today = blToday();
  var list = blState.articles.filter(function(article) {
    var upcoming = (article.datePublished || '') >= today;
    if (blState.filter === 'upcoming' && !upcoming) return false;
    if (blState.filter === 'past' && upcoming) return false;
    return !blState.search || [article.title, article.shortTitle, article.description, article.slug].join(' ').toLowerCase().includes(blState.search);
  });
  if (blState.filter === 'past') list.reverse();
  return list;
}
function blRenderArticles() {
  var container = document.getElementById('blog-articles-container');
  if (!container) return;
  var today = blToday();
  var upcoming = blState.articles.filter(function(a) { return (a.datePublished || '') >= today; }).length;
  document.getElementById('blog-count').textContent = blState.articles.length;
  document.getElementById('blog-upcoming-count').textContent = upcoming;
  document.getElementById('blog-past-count').textContent = blState.articles.length - upcoming;
  document.querySelectorAll('[data-blog-filter]').forEach(function(btn) {
    var active = btn.dataset.blogFilter === blState.filter;
    btn.classList.toggle('active', active); btn.setAttribute('aria-pressed', String(active));
  });
  var refresh = document.getElementById('refresh-blog-btn');
  refresh.disabled = blState.loading || blState.busy;
  refresh.textContent = blState.loading ? 'Обновление…' : 'Обновить';
  document.getElementById('reset-blog-btn').disabled = blState.busy || blState.loading;
  if (!blState.loaded) return;
  var articles = blVisibleArticles();
  document.getElementById('blog-results').textContent = 'Показано ' + articles.length + ' из ' + blState.articles.length;
  if (!articles.length) {
    var heading = blState.search ? 'Статьи не найдены' : blState.filter === 'upcoming' ? 'В плане пока нет статей' : 'Здесь пока нет статей';
    container.innerHTML = '<div class="bl-empty"><strong>' + heading + '</strong>' + (blState.search ? 'Попробуйте изменить запрос или выбрать «Все».' : 'Выберите другой период или обновите список.') + '</div>';
    return;
  }
  var disabled = blState.busy ? ' disabled' : '';
  var planned = blState.articles.filter(function(a) { return (a.datePublished || '') >= today; });
  container.innerHTML = articles.map(function(article) {
    var slug = adminEsc(article.slug), date = article.datePublished || '';
    var index = planned.findIndex(function(a) { return a.slug === article.slug; });
    var previous = index > 0 ? planned[index - 1] : null;
    var next = index >= 0 && index < planned.length - 1 ? planned[index + 1] : null;
    var value = Object.prototype.hasOwnProperty.call(blState.drafts, article.slug) ? blState.drafts[article.slug] : date;
    var dirty = value !== date;
    var status = date === today ? 'Сегодня' : date > today ? 'Запланирована' : 'Дата прошла';
    var statusClass = date === today ? ' today' : date < today ? ' past' : '';
    return '<article class="bl-row" data-blog-slug="' + slug + '">'
      + '<a class="bl-cover" href="' + adminEsc(blArticleUrl(article)) + '" target="_blank" rel="noopener" tabindex="-1" aria-hidden="true"><img src="' + adminEsc(blCoverUrl(article)) + '" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'https://pdd-drive.ru/assets/og-image.png\';"></a>'
      + '<div class="bl-copy"><a class="bl-title" href="' + adminEsc(blArticleUrl(article)) + '" target="_blank" rel="noopener">' + adminEsc(article.title || article.slug) + '</a>'
      + '<div class="bl-meta"><span class="bl-status' + statusClass + '">' + status + '</span><span>' + adminEsc(article.readingMinutes || 5) + ' мин. чтения</span></div>'
      + '<details class="bl-detail"><summary>Описание</summary><p>' + adminEsc(article.description || 'Описание не добавлено.') + '</p></details></div>'
      + '<div class="bl-date"><label for="date-' + slug + '">Дата выхода</label><input type="date" id="date-' + slug + '" data-blog-date="' + slug + '" value="' + adminEsc(value) + '"' + disabled + '>'
      + '<div class="bl-date-actions"' + (dirty ? '' : ' hidden') + '><button type="button" class="btn-action btn-primary" data-blog-action="save"' + disabled + '>Сохранить</button><button type="button" class="btn-action" data-blog-action="cancel"' + disabled + '>Отмена</button></div></div>'
      + '<div class="bl-row-actions"><button type="button" class="bl-icon" data-blog-action="previous" title="Обменять дату с предыдущей статьёй" aria-label="Обменять дату с предыдущей статьёй"' + (!previous || previous.datePublished === date || blState.busy ? ' disabled' : '') + '>↑</button>'
      + '<button type="button" class="bl-icon" data-blog-action="next" title="Обменять дату со следующей статьёй" aria-label="Обменять дату со следующей статьёй"' + (!next || next.datePublished === date || blState.busy ? ' disabled' : '') + '>↓</button>'
      + '<details class="bl-menu"><summary class="bl-icon" aria-label="Действия со статьёй" title="Действия">⋯</summary><div class="bl-menu-content"><a href="' + adminEsc(blArticleUrl(article)) + '" target="_blank" rel="noopener">Открыть страницу ↗</a><button type="button" class="bl-danger" data-blog-action="delete"' + disabled + '>Убрать из плана</button></div></details></div></article>';
  }).join('');
}

window.loadBlogArticles = async function() {
  if (!document.getElementById('blog-view')) return;
  var requestId = ++blState.requestId;
  blState.loading = true;
  blRenderArticles();
  var errorBox = document.getElementById('blog-load-error');
  errorBox.hidden = true;
  try {
    var data = await adminFetchJson('/api/admin/blog');
    if (requestId !== blState.requestId) return;
    if (!Array.isArray(data)) throw new Error('Некорректный ответ сервера');
    blState.articles = data.slice().sort(function(a,b) { return String(a.datePublished || '').localeCompare(String(b.datePublished || '')) || String(a.slug).localeCompare(String(b.slug)); });
    blState.loaded = true;
    Object.keys(blState.drafts).forEach(function(slug) {
      var article = blState.articles.find(function(a) { return a.slug === slug; });
      if (!article || article.datePublished === blState.drafts[slug]) delete blState.drafts[slug];
    });
  } catch(err) {
    if (requestId !== blState.requestId) return;
    errorBox.textContent = 'Не удалось загрузить план: ' + err.message + (blState.loaded ? '. Показаны данные предыдущего обновления.' : '. Нажмите «Обновить», чтобы повторить.');
    errorBox.hidden = false;
    if (!blState.loaded) {
      document.getElementById('blog-results').textContent = 'План не загружен';
      document.getElementById('blog-articles-container').innerHTML = '<div class="bl-empty">План не загрузился</div>';
    }
  } finally {
    if (requestId === blState.requestId) { blState.loading = false; blRenderArticles(); }
  }
};

async function blMutate(path, options, message, apply) {
  if (blState.busy) return;
  blState.busy = true; blRenderArticles();
  try {
    await adminFetchJson('/api/admin/blog/' + path, options);
    if (apply) apply();
    adminToast(message, false);
    document.dispatchEvent(new CustomEvent('pdd:publications-changed', { detail: { channel:'blog' } }));
    await loadBlogArticles();
  } catch(err) {
    adminToast('Изменение не сохранилось: ' + err.message, true);
  } finally { blState.busy = false; blRenderArticles(); }
}
window.updateArticleDate = async function(slug) {
  var article = blState.articles.find(function(a) { return a.slug === slug; });
  var input = document.getElementById('date-' + slug);
  var date = input ? input.value : blState.drafts[slug];
  if (!article || blState.busy || date === article.datePublished) return;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '')) { adminToast('Выберите дату выхода', true); return; }
  await blMutate(encodeURIComponent(slug), { method:'PUT', headers:{'content-type':'application/json'}, body:JSON.stringify({datePublished:date}) }, 'Дата статьи сохранена', function() { article.datePublished = date; delete blState.drafts[slug]; });
};
window.swapArticle = async function(index1,index2) {
  var a = blState.articles[index1], b = blState.articles[index2];
  if (!a || !b || index1 === index2 || a.datePublished === b.datePublished || blState.busy) return;
  if (Object.prototype.hasOwnProperty.call(blState.drafts, a.slug) || Object.prototype.hasOwnProperty.call(blState.drafts, b.slug)) { adminToast('Сначала сохраните или отмените изменённую дату', true); return; }
  var dateA = a.datePublished, dateB = b.datePublished;
  await blMutate('reorder', { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify({changes:[{slug:a.slug,datePublished:dateB},{slug:b.slug,datePublished:dateA}]}) }, 'Даты статей поменялись местами', function() { a.datePublished = dateB; b.datePublished = dateA; });
};
window.deleteBlogArticle = async function(slug) {
  if (blState.busy || !confirm('Удалить статью из публикаций?')) return;
  await blMutate(encodeURIComponent(slug), {method:'DELETE'}, 'Статья убрана из плана', function() { blState.articles = blState.articles.filter(function(a) { return a.slug !== slug; }); delete blState.drafts[slug]; });
};

(function() {
  var view = document.getElementById('blog-view');
  if (!view) return;
  document.getElementById('blog-search').addEventListener('input', function() { blState.search = this.value.trim().toLowerCase(); blRenderArticles(); });
  view.querySelectorAll('[data-blog-filter]').forEach(function(button) {
    button.addEventListener('click', function() { blState.filter = this.dataset.blogFilter; blRenderArticles(); });
  });
  document.getElementById('refresh-blog-btn').addEventListener('click', loadBlogArticles);
  document.getElementById('reset-blog-btn').addEventListener('click', async function() {
    if (blState.busy || !confirm('Сбросить список статей к исходному состоянию?')) return;
    await blMutate('reset', {method:'POST'}, 'Исходный план восстановлен', function() { blState.drafts = {}; });
  });
  view.addEventListener('change', function(event) {
    var input = event.target.closest('[data-blog-date]');
    if (!input || blState.busy) return;
    var article = blState.articles.find(function(a) { return a.slug === input.dataset.blogDate; });
    if (!article) return;
    if (input.value === article.datePublished) delete blState.drafts[article.slug];
    else blState.drafts[article.slug] = input.value;
    input.closest('.bl-date').querySelector('.bl-date-actions').hidden = input.value === article.datePublished;
  });
  view.addEventListener('click', function(event) {
    var button = event.target.closest('[data-blog-action]');
    if (!button || blState.busy) return;
    var row = button.closest('[data-blog-slug]');
    if (!row) return;
    var slug = row.dataset.blogSlug, action = button.dataset.blogAction;
    if (action === 'save') updateArticleDate(slug);
    else if (action === 'cancel') { delete blState.drafts[slug]; blRenderArticles(); }
    else if (action === 'delete') deleteBlogArticle(slug);
    else {
      var planned = blState.articles.filter(function(a) { return (a.datePublished || '') >= blToday(); });
      var index = planned.findIndex(function(a) { return a.slug === slug; });
      if (index < 0) return;
      var other = planned[index + (action === 'previous' ? -1 : 1)];
      if (other) swapArticle(blState.articles.findIndex(function(a) { return a.slug === slug; }), blState.articles.indexOf(other));
    }
  });
})();
`;
