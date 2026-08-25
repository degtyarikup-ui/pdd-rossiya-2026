#!/usr/bin/env python3
"""Assemble the complete worker.js with admin dashboard + blog tab."""

import json

# 1. Read the minimal articles constant
with open('/tmp/blog_articles_min.js', 'r', encoding='utf-8') as f:
    articles_const = f.read().strip()

# 2. Read the original worker.js backend
with open('server/install-notifier/worker.js', 'r', encoding='utf-8') as f:
    original = f.read()

# 3. Read the deployed admin HTML
with open('/tmp/admin_page.html', 'r', encoding='utf-8') as f:
    admin_html = f.read()

# ── Split original into parts ──
# Part A: everything before "export default {"
idx_export = original.index('export default {')
backend_functions = original[:idx_export]

# Part B: the export default block
export_block = original[idx_export:]

# ── Build the admin HTML string for renderAdminPage() ──
# We need to escape backticks and ${} in the HTML so it can be inside a template literal
# But we ALSO need the JS inside <script> to work with template literals...
# Solution: use a regular string with concatenation for the HTML, not a template literal.

# Actually, the simplest approach: store the HTML as-is and return it,
# but we need to fix the bugs and add the blog tab.

# Fix 1: Add blog tab button
admin_html = admin_html.replace(
    '<button class="app-tab" data-feature="threads">🤖 Threads Автопостер</button>',
    '<button class="app-tab" data-feature="threads">🤖 Threads Автопостер</button>\n      <button class="app-tab" data-feature="blog">📰 Будущие статьи</button>'
)

# Fix 2: Add blog view HTML after analytics view
blog_view_html = '''
  <!-- Blog Scheduled Publications View -->
  <div id="blog-view" style="display:none;">
    <div class="card" style="margin-bottom: 28px;">
      <div class="card-title-row">
        <div class="card-title">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#38bdf8" stroke-width="2"><path d="M19 20H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h10l6 6v10a2 2 0 0 1-2 2z"/><path d="M14 2v6h6"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><line x1="10" y1="9" x2="8" y2="9"/></svg>
          Запланированные публикации (<span id="blog-count">0</span>)
        </div>
        <div style="display:flex; gap:10px; align-items:center;">
          <button class="btn-action" id="reset-blog-btn" style="color:#fb7185; border-color:rgba(251,113,133,0.3);" title="Сбросить к исходным данным">⟲ Сбросить</button>
          <button class="btn-action" id="refresh-blog-btn">Обновить</button>
        </div>
      </div>
      <div style="font-size:13px; color:var(--text-muted); margin-bottom:20px;">Только будущие статьи (дата публикации позже сегодня). Можно менять даты, перемещать и удалять.</div>
      <div id="blog-articles-container" style="display:grid; gap:16px;">
        <div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка...</div>
      </div>
    </div>
  </div>
'''
admin_html = admin_html.replace(
    '</div> <!-- End Analytics View -->',
    '</div> <!-- End Analytics View -->\n' + blog_view_html
)

# Fix 3: Replace the broken JS section (from line "// ────────────────────── Threads JS" to end of script)
# Find the LAST (inline) <script> section and replace the JS
script_start = admin_html.rfind('<script>')
script_end = admin_html.rfind('</script>')
old_js = admin_html[script_start + len('<script>'):script_end]

new_js = r'''

// ────────────────────── Feature Switcher ──────────────────────
let currentFeature = 'analytics';

document.querySelectorAll('#feature-tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#feature-tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFeature = btn.dataset.feature;
    document.getElementById('analytics-view').style.display = currentFeature === 'analytics' ? 'block' : 'none';
    document.getElementById('threads-view').style.display = currentFeature === 'threads' ? 'block' : 'none';
    document.getElementById('blog-view').style.display = currentFeature === 'blog' ? 'block' : 'none';
    if (currentFeature === 'analytics') checkAuthAndLoad();
    else if (currentFeature === 'threads') loadThreadsQueue();
    else if (currentFeature === 'blog') loadBlogArticles();
  });
});

document.getElementById('refresh-threads-btn').addEventListener('click', loadThreadsQueue);
document.getElementById('refresh-blog-btn').addEventListener('click', loadBlogArticles);
document.getElementById('reset-blog-btn').addEventListener('click', async () => {
  if (confirm('Сбросить список статей к исходному состоянию?')) {
    await fetch('/api/admin/blog/reset', { method: 'POST' });
    loadBlogArticles();
  }
});

async function loadThreadsQueue() {
  const container = document.getElementById('threads-queue-container');
  container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка...</div>';
  try {
    const res = await fetch('/api/admin/threads');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    const queue = await res.json();
    if (!queue.length) {
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Очередь постов пуста</div>';
      return;
    }
    container.innerHTML = queue.map(p => {
      return '<div style="background:#0e1424;border:1px solid #232f48;border-radius:12px;padding:16px;">'
        + '<div style="display:flex;justify-content:space-between;margin-bottom:10px;font-size:12px;color:var(--text-muted);">'
        + '<span>📅 ' + (p.scheduledDate || 'Без даты') + '</span>'
        + '<span class="rate-badge">' + (p.status || 'pending') + '</span>'
        + '</div>'
        + '<textarea id="text-' + p.id + '" style="width:100%;min-height:80px;background:#141c2e;border:1px solid #232f48;border-radius:8px;color:#fff;padding:10px;font-family:inherit;font-size:13px;margin-bottom:8px;">' + (p.text || '') + '</textarea>'
        + '<input type="text" id="img-' + p.id + '" value="' + (p.imageUrl || '') + '" placeholder="Image URL" style="width:100%;background:#141c2e;border:1px solid #232f48;border-radius:8px;color:#fff;padding:8px 10px;font-size:12px;margin-bottom:10px;" />'
        + '<div style="display:flex;gap:8px;justify-content:flex-end;">'
        + '<button class="btn-action" onclick="savePost(\'' + p.id + '\')">💾 Сохранить</button>'
        + '<button class="btn-action" style="color:#fb7185;border-color:rgba(251,113,133,0.3);" onclick="deletePost(\'' + p.id + '\')">🗑 Удалить</button>'
        + '<button class="btn-action" style="color:#34d399;border-color:rgba(52,211,153,0.3);" onclick="publishPostNow(\'' + p.id + '\')">🚀 Публикация</button>'
        + '</div></div>';
    }).join('');
  } catch (err) {
    container.innerHTML = '<div style="color:#fb7185;text-align:center;padding:20px;">Ошибка: ' + err.message + '</div>';
  }
}

window.savePost = async (id) => {
  const text = document.getElementById('text-' + id).value;
  const imageUrl = document.getElementById('img-' + id).value;
  await fetch('/api/admin/threads/' + id, { method: 'PUT', headers: {'content-type':'application/json'}, body: JSON.stringify({ text, imageUrl }) });
  loadThreadsQueue();
};
window.deletePost = async (id) => {
  if(confirm('Точно удалить?')) {
    await fetch('/api/admin/threads/' + id, { method: 'DELETE' });
    loadThreadsQueue();
  }
};
window.publishPostNow = async (id) => {
  if(confirm('Опубликовать прямо сейчас?')) {
    await fetch('/api/admin/threads/' + id + '/publish', { method: 'POST' });
    loadThreadsQueue();
  }
};

// ────────────────────── Blog Articles JS ──────────────────────
let cachedBlogArticles = [];

async function loadBlogArticles() {
  const container = document.getElementById('blog-articles-container');
  const countEl = document.getElementById('blog-count');
  container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка...</div>';
  try {
    const res = await fetch('/api/admin/blog/future');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    cachedBlogArticles = await res.json();
    countEl.innerText = cachedBlogArticles.length;
    if (!cachedBlogArticles.length) {
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:40px;background:#0e1424;border-radius:12px;border:1px dashed #232f48;">🎉 Все статьи уже опубликованы!</div>';
      return;
    }
    container.innerHTML = cachedBlogArticles.map(function(a, idx) {
      var coverUrl = a.cover ? 'https://pdd-drive.ru/blog/' + a.slug + '/' + a.cover : 'https://pdd-drive.ru/assets/og-image.png';
      var isFirst = idx === 0;
      var isLast = idx === cachedBlogArticles.length - 1;
      var upDisabled = isFirst ? ' disabled style="opacity:0.3;cursor:not-allowed;width:32px;height:32px;"' : '';
      var downDisabled = isLast ? ' disabled style="opacity:0.3;cursor:not-allowed;width:32px;height:32px;"' : '';
      return '<div style="background:#0e1424;border:1px solid #232f48;border-radius:14px;padding:18px;display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;">'
        + '<div style="width:180px;height:101px;border-radius:10px;overflow:hidden;background:#141c2e;flex-shrink:0;border:1px solid #232f48;">'
        + '<img src="' + coverUrl + '" alt="" style="width:100%;height:100%;object-fit:cover;" onerror="this.src=\'https://pdd-drive.ru/assets/og-image.png\'" />'
        + '</div>'
        + '<div style="flex:1;min-width:260px;">'
        + '<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;margin-bottom:6px;">'
        + '<div style="font-size:16px;font-weight:700;color:#fff;line-height:1.3;">' + a.title + '</div>'
        + '<span class="rate-badge" style="background:rgba(56,189,248,0.1);color:#38bdf8;border:1px solid rgba(56,189,248,0.2);flex-shrink:0;">#' + (idx+1) + '</span>'
        + '</div>'
        + '<div style="font-size:12.5px;color:var(--text-muted);margin-bottom:12px;line-height:1.4;">' + (a.description || '') + '</div>'
        + '<div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;background:#141c2e;padding:8px 12px;border-radius:8px;border:1px solid #232f48;">'
        + '<div style="display:flex;align-items:center;gap:6px;">'
        + '<span style="font-size:12px;color:var(--text-muted);font-weight:600;">📅 Дата:</span>'
        + '<input type="date" id="date-' + a.slug + '" value="' + a.datePublished + '" onchange="updateArticleDate(\'' + a.slug + '\')" style="background:#0b0f19;border:1px solid #232f48;border-radius:6px;color:#38bdf8;padding:4px 8px;font-size:12.5px;font-weight:600;cursor:pointer;outline:none;" />'
        + '</div>'
        + '<div style="font-size:11.5px;color:var(--text-muted);">' + a.slug + ' · ' + (a.readingMinutes || 5) + ' мин.</div>'
        + '</div></div>'
        + '<div style="display:flex;flex-direction:column;gap:6px;justify-content:center;flex-shrink:0;align-self:center;">'
        + '<div style="display:flex;gap:4px;">'
        + '<button class="btn-icon" style="width:32px;height:32px;" title="Вверх" onclick="swapArticle(' + idx + ', ' + (idx-1) + ')"' + upDisabled + '>▲</button>'
        + '<button class="btn-icon" style="width:32px;height:32px;" title="Вниз" onclick="swapArticle(' + idx + ', ' + (idx+1) + ')"' + downDisabled + '>▼</button>'
        + '</div>'
        + '<button class="btn-action" style="padding:6px 10px;font-size:12px;color:#fb7185;border-color:rgba(251,113,133,0.3);justify-content:center;" onclick="deleteBlogArticle(\'' + a.slug + '\')">🗑 Удалить</button>'
        + '</div></div>';
    }).join('');
  } catch (err) {
    container.innerHTML = '<div style="color:#fb7185;text-align:center;padding:20px;">Ошибка: ' + err.message + '</div>';
  }
}

window.updateArticleDate = async function(slug) {
  var newDate = document.getElementById('date-' + slug).value;
  if (!newDate) return;
  await fetch('/api/admin/blog/' + slug, { method: 'PUT', headers: {'content-type':'application/json'}, body: JSON.stringify({ datePublished: newDate }) });
  loadBlogArticles();
};

window.swapArticle = async function(idx1, idx2) {
  if (idx1 < 0 || idx2 < 0 || idx1 >= cachedBlogArticles.length || idx2 >= cachedBlogArticles.length) return;
  var a1 = cachedBlogArticles[idx1], a2 = cachedBlogArticles[idx2];
  await fetch('/api/admin/blog/' + a1.slug, { method: 'PUT', headers: {'content-type':'application/json'}, body: JSON.stringify({ datePublished: a2.datePublished }) });
  await fetch('/api/admin/blog/' + a2.slug, { method: 'PUT', headers: {'content-type':'application/json'}, body: JSON.stringify({ datePublished: a1.datePublished }) });
  loadBlogArticles();
};

window.deleteBlogArticle = async function(slug) {
  if (confirm('Удалить статью из публикаций?')) {
    await fetch('/api/admin/blog/' + slug, { method: 'DELETE' });
    loadBlogArticles();
  }
};

''' + old_js[old_js.index('let currentDays = 7;'):]

# Fix 4: Fix logout handler in new_js
new_js = new_js.replace(
    "await fetch('/api/admin/threads/' + id + '/publish', { method: 'POST' });",
    "await fetch('/api/admin/logout', { method: 'POST' });"
)

admin_html = admin_html[:script_start + len('<script>')] + new_js + admin_html[script_end:]

# ── Escape the admin HTML for embedding as a JS string ──
# We'll use a function that returns it as a regular string with proper escaping
# Escape backslashes first, then backticks, then ${
escaped_html = admin_html.replace('\\', '\\\\').replace('`', '\\`').replace('${', '\\${')

# ── Build the getBlogArticles helper ──
helper_fn = '''
async function getBlogArticles(env) {
  if (env.INSTALLS) {
    try {
      const stored = await env.INSTALLS.get('blog_articles');
      if (stored) return JSON.parse(stored);
    } catch (_) {}
  }
  return DEFAULT_BLOG_ARTICLES;
}

function htmlResponse(html) {
  return new Response(html, { status: 200, headers: { 'content-type': 'text/html;charset=UTF-8' } });
}
'''

# ── Build blog API endpoints ──
blog_api = '''
    // ────────────────────── Blog Management API ──────────────────────
    if (url.pathname === '/api/admin/blog/future' && request.method === 'GET') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      const articles = await getBlogArticles(env);
      const today = new Date().toISOString().slice(0, 10);
      const future = articles.filter(a => (a.datePublished || '') > today);
      future.sort((a, b) => (a.datePublished || '').localeCompare(b.datePublished || ''));
      return jsonResponse(future);
    }

    if (url.pathname === '/api/admin/blog/reset' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      if (env.INSTALLS) await env.INSTALLS.put('blog_articles', JSON.stringify(DEFAULT_BLOG_ARTICLES));
      return jsonResponse({ ok: true });
    }

    if (url.pathname.startsWith('/api/admin/blog/')) {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      const slug = url.pathname.replace('/api/admin/blog/', '').replace(/\\/$/, '');
      let articles = await getBlogArticles(env);
      const idx = articles.findIndex(a => a.slug === slug);
      if (idx === -1) return jsonResponse({ error: 'not found' }, 404);

      if (request.method === 'DELETE') {
        articles.splice(idx, 1);
        if (env.INSTALLS) await env.INSTALLS.put('blog_articles', JSON.stringify(articles));
        return jsonResponse({ ok: true });
      }

      if (request.method === 'PUT') {
        let body = {};
        try { body = await request.json(); } catch (_) {}
        articles[idx] = { ...articles[idx], ...body };
        if (env.INSTALLS) await env.INSTALLS.put('blog_articles', JSON.stringify(articles));
        return jsonResponse({ ok: true, article: articles[idx] });
      }
    }
'''

# ── Now modify the export default block ──
# The current fetch handler starts with OPTIONS check, then GET (returns ok text), then POST-only logic.
# We need to restructure the GET to also handle admin routes.

# Find the simple GET handler that returns 'pdd-install-notifier: ok'
# and replace it with a proper router

old_get = '''    if (request.method === 'GET') {
      const url = new URL(request.url);
      // Ручной прогон проверки отзывов (то же, что делает почасовой крон).
      if (url.searchParams.get('reviews') === 'check') {
        await pollReviews(env);
        return jsonResponse({ ok: true, checked: 'reviews' });
      }
      return new Response('pdd-install-notifier: ok', { status: 200 });
    }
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'method not allowed' }, 405);
    }'''

new_router = '''    const url = new URL(request.url);

    // ────────────────────── Admin Routes (any method) ──────────────────────
    if (url.pathname === '/admin' || url.pathname === '/admin/') {
      return htmlResponse(renderAdminPage());
    }

    if (url.pathname === '/api/admin/login' && request.method === 'POST') {
      let body = {};
      try { body = await request.json(); } catch (_) {}
      const expectedPassword = env.ADMIN_PASSWORD || 'pdd2026admin';
      if (body.password === expectedPassword) {
        return jsonResponse({ ok: true }, 200, {
          'Set-Cookie': `pdd_admin_token=${encodeURIComponent(expectedPassword)}; Path=/; Max-Age=2592000; HttpOnly; Secure; SameSite=Lax`,
        });
      }
      return jsonResponse({ error: 'invalid password' }, 401);
    }

    if (url.pathname === '/api/admin/logout' && request.method === 'POST') {
      return jsonResponse({ ok: true }, 200, {
        'Set-Cookie': 'pdd_admin_token=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax',
      });
    }

    if (url.pathname === '/api/admin/stats' && request.method === 'GET') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      const days = parseInt(url.searchParams.get('days') || '7', 10);
      const appFilter = url.searchParams.get('app') || 'all';
      const stats = await getStatsForPeriod(env, Math.min(Math.max(days, 1), 365), appFilter);
      return jsonResponse(stats);
    }

    if (url.pathname === '/api/threads/import' && request.method === 'POST') {
      if (!env.SHARED_SECRET || request.headers.get('x-install-secret') !== env.SHARED_SECRET) {
        return jsonResponse({ error: 'forbidden' }, 403);
      }
      let body; try { body = await request.json(); } catch { return jsonResponse({ error: 'bad json'}, 400); }
      let queue = [];
      try { queue = JSON.parse(await env.INSTALLS.get('threads_queue')) || []; } catch {}
      queue = queue.concat(body.posts || []);
      await env.INSTALLS.put('threads_queue', JSON.stringify(queue));
      return jsonResponse({ ok: true, imported: body.posts?.length });
    }

    if (url.pathname.startsWith('/api/admin/threads')) {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let queue = [];
      try { queue = JSON.parse(await env.INSTALLS.get('threads_queue')) || []; } catch {}

      if (url.pathname === '/api/admin/threads' && request.method === 'GET') {
        queue.sort((a,b) => new Date(a.scheduledDate).getTime() - new Date(b.scheduledDate).getTime());
        return jsonResponse(queue);
      }

      const match = url.pathname.match(/\\/api\\/admin\\/threads\\/([a-zA-Z0-9_-]+)(?:\\/publish)?/);
      if (match) {
        const id = match[1];
        const isPublish = url.pathname.endsWith('/publish');
        const idx = queue.findIndex(p => p.id === id);
        if (idx === -1) return jsonResponse({ error: 'not found' }, 404);

        if (request.method === 'DELETE') {
          queue.splice(idx, 1);
          await env.INSTALLS.put('threads_queue', JSON.stringify(queue));
          return jsonResponse({ ok: true });
        }

        if (request.method === 'PUT') {
          let body = await request.json();
          queue[idx] = { ...queue[idx], ...body };
          await env.INSTALLS.put('threads_queue', JSON.stringify(queue));
          return jsonResponse({ ok: true });
        }

        if (request.method === 'POST' && isPublish) {
          try {
            await publishToThreads(queue[idx], env);
            queue[idx].status = 'published';
            await env.INSTALLS.put('threads_queue', JSON.stringify(queue));
            return jsonResponse({ ok: true });
          } catch (e) {
            queue[idx].status = 'error';
            queue[idx].error = e.message;
            await env.INSTALLS.put('threads_queue', JSON.stringify(queue));
            return jsonResponse({ error: e.message }, 500);
          }
        }
      }
    }

''' + blog_api + '''

    // ────────────────────── Original GET/POST routes ──────────────────────
    if (request.method === 'GET') {
      // Ручной прогон проверки отзывов (то же, что делает почасовой крон).
      if (url.searchParams.get('reviews') === 'check') {
        await pollReviews(env);
        return jsonResponse({ ok: true, checked: 'reviews' });
      }
      return new Response('pdd-install-notifier: ok', { status: 200 });
    }
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'method not allowed' }, 405);
    }'''

export_block = export_block.replace(old_get, new_router)

# Also need to remove the duplicate admin routes that were in the original POST section
# (login, logout, stats, threads, store redirects - those are now handled above)
# The original had these after the POST body parsing. We need to remove them from the export block.
# Actually looking at the original, these admin routes weren't there - they were added in a previous session.
# The original only has the install tracking logic. So we're good.

# Replace the exact original jsonResponse function
old_jr_exact = """function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', ...CORS_HEADERS },
  });
}"""
new_jr_exact = """function jsonResponse(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json', ...CORS_HEADERS, ...extraHeaders },
  });
}"""
if old_jr_exact in backend_functions:
    backend_functions = backend_functions.replace(old_jr_exact, new_jr_exact)

# ── Also need verifyAdminAuth, getStatsForPeriod, publishToThreads ──
# These should already exist in the deployed version but may not be in the original 553-line file.
# Let's check:
has_verify_auth = 'function verifyAdminAuth' in backend_functions
has_stats = 'function getStatsForPeriod' in backend_functions
has_publish_threads = 'function publishToThreads' in backend_functions

extra_functions = ''

if not has_verify_auth:
    extra_functions += '''
function verifyAdminAuth(request, env) {
  const expectedPassword = env.ADMIN_PASSWORD || 'pdd2026admin';
  const authHeader = request.headers.get('authorization');
  if (authHeader && authHeader.startsWith('Bearer ')) {
    if (authHeader.slice(7) === expectedPassword) return true;
  }
  const cookie = request.headers.get('cookie') || '';
  const match = cookie.match(/pdd_admin_token=([^;]+)/);
  if (match && decodeURIComponent(match[1]) === expectedPassword) return true;
  return false;
}
'''

if not has_stats:
    extra_functions += '''
async function getStatsForPeriod(env, days, appFilter) {
  if (!env.INSTALLS) return { totals: { views: 0, clicks: 0, installs: 0, grandTotal: 0, ctr: '0.0', cr: '0.0' }, timeline: [], sources: [], targets: [], campaigns: [], recent: [] };

  const now = new Date();
  const timeline = [];
  let totalViews = 0, totalClicks = 0, totalInstalls = 0;
  const sourceMap = {};
  const targetMap = {};
  const campaignMap = {};

  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 86400000);
    const dk = mskDayKey(d);
    const prefix = appFilter === 'all' ? '' : appFilter + ':';

    const views = parseInt(await env.INSTALLS.get(prefix + 'v:' + dk) || '0', 10);
    const clicks = parseInt(await env.INSTALLS.get(prefix + 'c:' + dk) || '0', 10);
    const installs = parseInt(await env.INSTALLS.get(prefix + 'i:' + dk) || '0', 10);

    timeline.push({ date: dk, views, clicks, installs });
    totalViews += views;
    totalClicks += clicks;
    totalInstalls += installs;

    // Sources
    const srcList = await env.INSTALLS.list({ prefix: prefix + 'src:' + dk + ':' });
    for (const k of srcList.keys) {
      const name = k.name.split(':').pop();
      if (!sourceMap[name]) sourceMap[name] = { views: 0, clicks: 0, installs: 0 };
      sourceMap[name].views += parseInt(await env.INSTALLS.get(k.name) || '0', 10);
    }
    const srcClickList = await env.INSTALLS.list({ prefix: prefix + 'srcc:' + dk + ':' });
    for (const k of srcClickList.keys) {
      const name = k.name.split(':').pop();
      if (!sourceMap[name]) sourceMap[name] = { views: 0, clicks: 0, installs: 0 };
      sourceMap[name].clicks += parseInt(await env.INSTALLS.get(k.name) || '0', 10);
    }

    // Targets
    const tgtList = await env.INSTALLS.list({ prefix: prefix + 'tgt:' + dk + ':' });
    for (const k of tgtList.keys) {
      const name = k.name.split(':').pop();
      if (!targetMap[name]) targetMap[name] = { clicks: 0 };
      targetMap[name].clicks += parseInt(await env.INSTALLS.get(k.name) || '0', 10);
    }

    // Campaigns
    const campList = await env.INSTALLS.list({ prefix: prefix + 'camp:' + dk + ':' });
    for (const k of campList.keys) {
      const parts = k.name.split(':');
      const campName = parts[parts.length - 1];
      const campSrc = parts.length > 4 ? parts[parts.length - 2] : '';
      const campKey = campName + '|' + campSrc;
      if (!campaignMap[campKey]) campaignMap[campKey] = { name: campName, source: campSrc, views: 0, clicks: 0 };
      campaignMap[campKey].views += parseInt(await env.INSTALLS.get(k.name) || '0', 10);
    }
  }

  const grandTotal = parseInt(await env.INSTALLS.get(appFilter === 'all' ? 'counter' : appFilter + ':counter') || '0', 10);
  const ctr = totalViews > 0 ? ((totalClicks / totalViews) * 100).toFixed(1) : '0.0';
  const cr = totalClicks > 0 ? ((totalInstalls / totalClicks) * 100).toFixed(1) : '0.0';

  const sources = Object.entries(sourceMap).map(([name, d]) => ({
    name,
    views: d.views,
    clicks: d.clicks,
    installs: d.installs,
    ctr: d.views > 0 ? ((d.clicks / d.views) * 100).toFixed(1) : '0.0'
  })).sort((a, b) => b.views - a.views);

  const targets = Object.entries(targetMap).map(([name, d]) => ({
    name, clicks: d.clicks
  })).sort((a, b) => b.clicks - a.clicks);

  const campaigns = Object.values(campaignMap).map(c => ({
    ...c,
    ctr: c.views > 0 ? ((c.clicks / c.views) * 100).toFixed(1) : '0.0'
  })).sort((a, b) => b.views - a.views);

  // Recent events
  let recent = [];
  try { recent = JSON.parse(await env.INSTALLS.get('recent_events') || '[]'); } catch {}
  if (appFilter !== 'all') {
    recent = recent.filter(r => r.app === appFilter);
  }

  return {
    totals: { views: totalViews, clicks: totalClicks, installs: totalInstalls, grandTotal, ctr, cr },
    timeline, sources, targets, campaigns, recent
  };
}
'''

if not has_publish_threads:
    extra_functions += '''
async function publishToThreads(post, env) {
  // Placeholder for Threads publishing
  throw new Error('Threads publishing not configured');
}
'''

# ── Assemble the final file ──
# Add renderAdminPage function
render_fn = '\nfunction renderAdminPage() {\n  return `' + escaped_html + '`;\n}\n'

final = articles_const + '\n\n'
final += backend_functions
final += helper_fn
final += extra_functions
final += render_fn + '\n'
final += export_block

with open('server/install-notifier/worker.js', 'w', encoding='utf-8') as f:
    f.write(final)

print(f'worker.js written: {len(final)} bytes')
print(f'Articles const: {len(articles_const)} bytes')
print(f'Backend functions: {len(backend_functions)} bytes')
print(f'Admin HTML (escaped): {len(escaped_html)} bytes')
