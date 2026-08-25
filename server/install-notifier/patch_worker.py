import json

with open('server/install-notifier/worker.js', 'r', encoding='utf-8') as f:
    code = f.read()

articles = json.load(open('server/install-notifier/all_articles.json', encoding='utf-8'))
raw_articles_js = json.dumps(articles, ensure_ascii=False)

# 1. Add DEFAULT_BLOG_ARTICLES constant near top
default_const = 'const DEFAULT_BLOG_ARTICLES = ' + raw_articles_js + ';\n\n'
if 'const DEFAULT_BLOG_ARTICLES =' not in code:
    code = default_const + code

# 2. Add helper getBlogArticles
helper_code = '''
async function getBlogArticles(env) {
  if (env.INSTALLS) {
    try {
      const stored = await env.INSTALLS.get('blog_articles');
      if (stored) return JSON.parse(stored);
    } catch (_) {}
  }
  return DEFAULT_BLOG_ARTICLES;
}
'''
if 'async function getBlogArticles(' not in code:
    code = code.replace('function verifyAdminAuth(request, env) {', helper_code + '\nfunction verifyAdminAuth(request, env) {')

# 3. Add Feature Tab for Blog in renderAdminPage
tab_btn = '<button class="app-tab" data-feature="blog">📰 Запланированные статьи</button>'
if 'data-feature="blog"' not in code:
    code = code.replace('<button class="app-tab" data-feature="threads">🤖 Threads Автопостер</button>', '<button class="app-tab" data-feature="threads">🤖 Threads Автопостер</button>\n      ' + tab_btn)

# 4. Add Blog View HTML
blog_view_html = '''
  <!-- Blog Scheduled Publications View -->
  <div id="blog-view" style="display:none;">
    <div class="card" style="margin-bottom: 28px;">
      <div class="card-title-row">
        <div class="card-title">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#38bdf8" stroke-width="2"><path d="M19 20H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h10l6 6v10a2 2 0 0 1-2 2z"/><path d="M14 2v6h6"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><line x1="10" y1="9" x2="8" y2="9"/></svg>
          Запланированные публикации в блог (<span id="blog-count">0</span>)
        </div>
        <div style="display:flex; gap:10px; align-items:center;">
          <button class="btn-action" id="reset-blog-btn" style="color:#fb7185; border-color:rgba(251,113,133,0.3);" title="Сбросить к исходным статьям репозитория">Сбросить</button>
          <button class="btn-action" id="refresh-blog-btn">Обновить</button>
        </div>
      </div>
      <div style="font-size:13px; color:var(--text-muted); margin-bottom:20px;">
        Здесь отображаются только будущие статьи (дата публикации позже сегодняшнего дня). Вы можете менять дату выхода, менять статьи местами кнопками вверх/вниз и удалять ненужные.
      </div>
      <div id="blog-articles-container" style="display:grid; gap:16px;">
        <div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка запланированных статей...</div>
      </div>
    </div>
  </div>
'''

if 'id="blog-view"' not in code:
    code = code.replace('</div> <!-- End Analytics View -->', '</div> <!-- End Analytics View -->\n' + blog_view_html)

# 5. Frontend JS
frontend_js = r'''
// ────────────────────── Feature Switcher (Analytics / Threads / Blog) ──────────────────────
let currentFeature = 'analytics';

document.querySelectorAll('#feature-tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#feature-tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFeature = btn.dataset.feature;
    
    document.getElementById('analytics-view').style.display = currentFeature === 'analytics' ? 'block' : 'none';
    document.getElementById('threads-view').style.display = currentFeature === 'threads' ? 'block' : 'none';
    document.getElementById('blog-view').style.display = currentFeature === 'blog' ? 'block' : 'none';

    if (currentFeature === 'analytics') {
      checkAuthAndLoad();
    } else if (currentFeature === 'threads') {
      loadThreadsQueue();
    } else if (currentFeature === 'blog') {
      loadBlogArticles();
    }
  });
});

document.getElementById('refresh-threads-btn').addEventListener('click', loadThreadsQueue);
document.getElementById('refresh-blog-btn').addEventListener('click', loadBlogArticles);
document.getElementById('reset-blog-btn').addEventListener('click', async () => {
  if (confirm('Сбросить список статей к исходному состоянию из репозитория?')) {
    await fetch('/api/admin/blog/reset', { method: 'POST' });
    loadBlogArticles();
  }
});

async function loadThreadsQueue() {
  const container = document.getElementById('threads-queue-container');
  container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка очереди...</div>';
  try {
    const res = await fetch('/api/admin/threads');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    const queue = await res.json();
    if (!queue.length) {
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Очередь постов пуста</div>';
      return;
    }
    container.innerHTML = queue.map(p => {
      return `
        <div style="background:#0e1424;border:1px solid #232f48;border-radius:12px;padding:16px;">
          <div style="display:flex;justify-content:space-between;margin-bottom:10px;font-size:12px;color:var(--text-muted);">
            <span>📅 \${p.scheduledDate || 'Без даты'}</span>
            <span class="rate-badge">\${p.status || 'pending'}</span>
          </div>
          <textarea id="text-\${p.id}" style="width:100%;min-height:80px;background:#141c2e;border:1px solid #232f48;border-radius:8px;color:#fff;padding:10px;font-family:inherit;font-size:13px;margin-bottom:8px;">\${p.text || ''}</textarea>
          <input type="text" id="img-\${p.id}" value="\${p.imageUrl || ''}" placeholder="Image URL" style="width:100%;background:#141c2e;border:1px solid #232f48;border-radius:8px;color:#fff;padding:8px 10px;font-size:12px;margin-bottom:10px;" />
          <div style="display:flex;gap:8px;justify-content:flex-end;">
            <button class="btn-action" onclick="savePost('\${p.id}')">💾 Сохранить</button>
            <button class="btn-action" style="color:#fb7185;border-color:rgba(251,113,133,0.3);" onclick="deletePost('\${p.id}')">🗑 Удалить</button>
            <button class="btn-action" style="color:#34d399;border-color:rgba(52,211,153,0.3);" onclick="publishPostNow('\${p.id}')">🚀 Опубликовать</button>
          </div>
        </div>
      `;
    }).join('');
  } catch (err) {
    container.innerHTML = '<div style="color:#fb7185;text-align:center;padding:20px;">Ошибка загрузки Threads: ' + err.message + '</div>';
  }
}

window.savePost = async (id) => {
  const text = document.getElementById('text-' + id).value;
  const imageUrl = document.getElementById('img-' + id).value;
  await fetch('/api/admin/threads/' + id, { method: 'PUT', headers: {'content-type':'application/json'}, body: JSON.stringify({ text, imageUrl }) });
  loadThreadsQueue();
};
window.deletePost = async (id) => {
  if(confirm('Точно удалить этот пост?')) {
    await fetch('/api/admin/threads/' + id, { method: 'DELETE' });
    loadThreadsQueue();
  }
};
window.publishPostNow = async (id) => {
  if(confirm('Опубликовать пост в Threads прямо сейчас?')) {
    await fetch('/api/admin/threads/' + id + '/publish', { method: 'POST' });
    loadThreadsQueue();
  }
};

// ────────────────────── Blog Articles JS ──────────────────────
let cachedBlogArticles = [];

async function loadBlogArticles() {
  const container = document.getElementById('blog-articles-container');
  const countEl = document.getElementById('blog-count');
  container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка запланированных статей...</div>';
  try {
    const res = await fetch('/api/admin/blog/future');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    cachedBlogArticles = await res.json();
    countEl.innerText = cachedBlogArticles.length;
    
    if (!cachedBlogArticles.length) {
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:40px;background:#0e1424;border-radius:12px;border:1px dashed #232f48;">🎉 Нет запланированных публикаций на будущее. Все статьи уже вышли!</div>';
      return;
    }

    container.innerHTML = cachedBlogArticles.map((a, idx) => {
      const coverUrl = a.cover ? 'https://pdd-drive.ru/blog/' + a.slug + '/' + a.cover : 'https://pdd-drive.ru/assets/og-image.png';
      const isFirst = idx === 0;
      const isLast = idx === cachedBlogArticles.length - 1;
      
      return `
        <div style="background:#0e1424;border:1px solid #232f48;border-radius:14px;padding:18px;display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;transition:all 0.15s;">
          <div style="width:180px;height:101px;border-radius:10px;overflow:hidden;background:#141c2e;flex-shrink:0;border:1px solid #232f48;position:relative;">
            <img src="\${coverUrl}" alt="" style="width:100%;height:100%;object-fit:cover;" onerror="this.src='https://pdd-drive.ru/assets/og-image.png'" />
            <div style="position:absolute;bottom:4px;right:4px;background:rgba(0,0,0,0.7);color:#cbd5e1;font-size:10px;font-weight:600;padding:1px 5px;border-radius:4px;">16:9</div>
          </div>
          <div style="flex:1;min-width:260px;">
            <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;margin-bottom:6px;">
              <div style="font-size:16px;font-weight:700;color:#fff;line-height:1.3;">\${a.title}</div>
              <span class="rate-badge" style="background:rgba(56,189,248,0.1);color:#38bdf8;border:1px solid rgba(56,189,248,0.2);flex-shrink:0;">#\${idx + 1} в очереди</span>
            </div>
            <div style="font-size:12.5px;color:var(--text-muted);margin-bottom:12px;line-height:1.4;">
              \${a.description || ''}
            </div>
            <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;background:#141c2e;padding:8px 12px;border-radius:8px;border:1px solid #232f48;">
              <div style="display:flex;align-items:center;gap:6px;">
                <span style="font-size:12px;color:var(--text-muted);font-weight:600;">📅 Дата выхода:</span>
                <input type="date" id="date-\${a.slug}" value="\${a.datePublished}" onchange="updateArticleDate('\${a.slug}')" style="background:#0b0f19;border:1px solid #232f48;border-radius:6px;color:#38bdf8;padding:4px 8px;font-size:12.5px;font-weight:600;cursor:pointer;outline:none;" />
              </div>
              <div style="font-size:11.5px;color:var(--text-muted);">
                Slug: <code style="color:#cbd5e1;">\${a.slug}</code> · \${a.readingMinutes || 5} мин. чтения
              </div>
            </div>
          </div>
          <div style="display:flex;flex-direction:column;gap:6px;justify-content:center;flex-shrink:0;align-self:center;">
            <div style="display:flex;gap:4px;">
              <button class="btn-icon" style="width:32px;height:32px;" title="Поднять выше (поменять дату с предыдущей)" onclick="swapArticle(\${idx}, \${idx - 1})" \${isFirst ? 'disabled style="opacity:0.3;cursor:not-allowed;"' : ''}>
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="18 15 12 9 6 15"/></svg>
              </button>
              <button class="btn-icon" style="width:32px;height:32px;" title="Опустить ниже (поменять дату со следующей)" onclick="swapArticle(\${idx}, \${idx + 1})" \${isLast ? 'disabled style="opacity:0.3;cursor:not-allowed;"' : ''}>
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>
              </button>
            </div>
            <button class="btn-action" style="padding:6px 10px;font-size:12px;color:#fb7185;border-color:rgba(251,113,133,0.3);justify-content:center;" onclick="deleteBlogArticle('\${a.slug}', '\${a.title.replace(/'/g, "\\\'")}')">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
              Удалить
            </button>
          </div>
        </div>
      `;
    }).join('');
  } catch (err) {
    container.innerHTML = '<div style="color:#fb7185;text-align:center;padding:20px;">Ошибка загрузки статей: ' + err.message + '</div>';
  }
}

window.updateArticleDate = async (slug) => {
  const newDate = document.getElementById('date-' + slug).value;
  if (!newDate) return;
  try {
    const res = await fetch('/api/admin/blog/' + slug, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ datePublished: newDate })
    });
    if (res.ok) {
      loadBlogArticles();
    } else {
      alert('Ошибка при сохранении даты');
    }
  } catch (e) {
    alert('Ошибка сети: ' + e.message);
  }
};

window.swapArticle = async (idx1, idx2) => {
  if (idx1 < 0 || idx2 < 0 || idx1 >= cachedBlogArticles.length || idx2 >= cachedBlogArticles.length) return;
  const art1 = cachedBlogArticles[idx1];
  const art2 = cachedBlogArticles[idx2];
  
  const date1 = art1.datePublished;
  const date2 = art2.datePublished;
  
  try {
    await fetch('/api/admin/blog/' + art1.slug, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ datePublished: date2 })
    });
    await fetch('/api/admin/blog/' + art2.slug, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ datePublished: date1 })
    });
    loadBlogArticles();
  } catch (e) {
    alert('Ошибка перемещения: ' + e.message);
  }
};

window.deleteBlogArticle = async (slug, title) => {
  if (confirm('Удалить статью из будущих публикаций?\n\n«' + title + '»')) {
    try {
      const res = await fetch('/api/admin/blog/' + slug, { method: 'DELETE' });
      if (res.ok) {
        loadBlogArticles();
      } else {
        alert('Ошибка при удалении');
      }
    } catch (e) {
      alert('Ошибка сети: ' + e.message);
    }
  }
};
'''

# Replace from // ────────────────────── Threads JS ────────────────────── up to let currentDays = 7;
idx_threads_js = code.find('// ────────────────────── Threads JS ──────────────────────')
idx_current_days = code.find('let currentDays = 7;')
if idx_threads_js != -1 and idx_current_days != -1:
    code = code[:idx_threads_js] + frontend_js + '\n\n' + code[idx_current_days:]

# 6. Fix logout button in admin HTML
code = code.replace("await fetch('/api/admin/threads/' + id + '/publish', { method: 'POST' });\n  location.reload();", "await fetch('/api/admin/logout', { method: 'POST' });\n  location.reload();")

# 7. Add Backend API endpoints for blog management
backend_api_code = '''
    // ────────────────────── API Управление Блогом ──────────────────────
    if (url.pathname === '/api/admin/blog/future' && request.method === 'GET') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      
      const articles = await getBlogArticles(env);
      const todayMsk = mskDayKey(new Date());
      // Фильтруем только будущие (дата публикации строго позже сегодняшнего дня)
      const future = articles.filter(a => (a.datePublished || '') > todayMsk);
      future.sort((a, b) => (a.datePublished || '').localeCompare(b.datePublished || ''));
      return jsonResponse(future);
    }

    if (url.pathname === '/api/admin/blog/reset' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      if (env.INSTALLS) {
        await env.INSTALLS.put('blog_articles', JSON.stringify(DEFAULT_BLOG_ARTICLES));
      }
      return jsonResponse({ ok: true });
    }

    if (url.pathname.startsWith('/api/admin/blog/')) {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      
      const slug = url.pathname.replace('/api/admin/blog/', '').replace(/\/$/, '');
      let articles = await getBlogArticles(env);
      const idx = articles.findIndex(a => a.slug === slug);
      
      if (idx === -1) return jsonResponse({ error: 'not found' }, 404);

      if (request.method === 'DELETE') {
        articles.splice(idx, 1);
        if (env.INSTALLS) {
          await env.INSTALLS.put('blog_articles', JSON.stringify(articles));
        }
        return jsonResponse({ ok: true });
      }

      if (request.method === 'PUT') {
        let body = {};
        try { body = await request.json(); } catch (_) {}
        articles[idx] = { ...articles[idx], ...body };
        if (env.INSTALLS) {
          await env.INSTALLS.put('blog_articles', JSON.stringify(articles));
        }
        return jsonResponse({ ok: true, article: articles[idx] });
      }
    }
'''

if '/api/admin/blog/future' not in code:
    code = code.replace('// 1. Маршрут веб-админки', backend_api_code + '\n    // 1. Маршрут веб-админки')

with open('server/install-notifier/worker.js', 'w', encoding='utf-8') as f:
    f.write(code)

print('worker.js successfully patched!')
