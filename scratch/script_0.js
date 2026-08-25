

// ────────────────────── Feature Switcher ──────────────────────
let currentFeature = 'analytics';

document.querySelectorAll('#feature-tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#feature-tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFeature = btn.dataset.feature;
    document.getElementById('analytics-view').style.display = currentFeature === 'analytics' ? 'block' : 'none';
    document.getElementById('reels-view').style.display = currentFeature === 'reels' ? 'block' : 'none';
    document.getElementById('threads-view').style.display = currentFeature === 'threads' ? 'block' : 'none';
    document.getElementById('blog-view').style.display = currentFeature === 'blog' ? 'block' : 'none';
    if (currentFeature === 'analytics') checkAuthAndLoad();
    else if (currentFeature === 'reels') loadAdminReels();
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
        + '<button class="btn-action" data-id="' + p.id + '" onclick="savePost(this.dataset.id)">💾 Сохранить</button>'
        + '<button class="btn-action" style="color:#fb7185;border-color:rgba(251,113,133,0.3);" data-id="' + p.id + '" onclick="deletePost(this.dataset.id)">🗑 Удалить</button>'
        + '<button class="btn-action" style="color:#34d399;border-color:rgba(52,211,153,0.3);" data-id="' + p.id + '" onclick="publishPostNow(this.dataset.id)">🚀 Публикация</button>'
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
  const textEl = document.getElementById('text-' + id);
  const text = textEl ? textEl.value : '';

  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(11,15,25,0.92);backdrop-filter:blur(12px);display:flex;align-items:center;justify-content:center;z-index:9999;padding:20px;';
  const escapedId = id;
  overlay.innerHTML = [
    '<div style="background:#141c2e;border:1px solid #232f48;border-radius:24px;padding:32px;width:100%;max-width:580px;box-shadow:0 24px 60px rgba(0,0,0,0.6);">',
      '<div style="font-size:18px;font-weight:700;margin-bottom:16px;">📋 Готово к публикации</div>',
      '<p style="color:#8e9db5;font-size:13px;margin-bottom:12px;">Скопируйте текст и вставьте в Threads. Или нажмите — бот пришлёт его вам в Telegram.</p>',
      '<textarea id="publish-modal-text" style="width:100%;background:#0b0f19;border:1px solid #232f48;color:#f8fafc;padding:14px;border-radius:12px;font-size:14px;resize:vertical;min-height:140px;margin-bottom:16px;"></textarea>',
      '<div style="display:flex;gap:10px;flex-wrap:wrap;">',
        '<button id="pm-copy-btn" style="background:#232f48;border:1px solid #38bdf8;color:#38bdf8;padding:10px 18px;border-radius:10px;font-size:13px;font-weight:700;cursor:pointer;">📋 Скопировать текст</button>',
        '<button id="pm-tg-btn" style="background:#232f48;border:1px solid #34d399;color:#34d399;padding:10px 18px;border-radius:10px;font-size:13px;font-weight:700;cursor:pointer;">✈️ Отправить в Telegram</button>',
        '<button id="pm-close-btn" style="background:#232f48;border:1px solid #64748b;color:#94a3b8;padding:10px 18px;border-radius:10px;font-size:13px;font-weight:700;cursor:pointer;">Закрыть</button>',
      '</div>',
    '</div>'
  ].join('');
  document.body.appendChild(overlay);

  document.getElementById('publish-modal-text').value = text;

  document.getElementById('pm-copy-btn').onclick = function() {
    const ta = document.getElementById('publish-modal-text');
    ta.select();
    navigator.clipboard.writeText(ta.value);
    this.textContent = '✅ Скопировано!';
    setTimeout(() => { this.textContent = '📋 Скопировать текст'; }, 2000);
  };

  document.getElementById('pm-tg-btn').onclick = async function() {
    this.textContent = 'Отправляю...';
    try {
      const res = await fetch('/api/admin/threads/' + escapedId + '/publish', { method: 'POST' });
      const j = await res.json();
      this.textContent = j.ok ? '✅ Отправлено в Telegram!' : ('❌ ' + (j.error || 'Ошибка'));
    } catch(e) {
      this.textContent = '❌ Ошибка сети';
    }
  };

  document.getElementById('pm-close-btn').onclick = function() {
    overlay.remove();
    loadThreadsQueue();
  };
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
      var coverUrl = a.cover ? 'https://pdd-drive.ru/blog/' + a.slug + '/' + a.cover + '?v=20260823_v3' : 'https://pdd-drive.ru/assets/og-image.png';
      var isFirst = idx === 0;
      var isLast = idx === cachedBlogArticles.length - 1;
      var upDisabled = isFirst ? ' disabled style="opacity:0.3;cursor:not-allowed;width:32px;height:32px;"' : '';
      var downDisabled = isLast ? ' disabled style="opacity:0.3;cursor:not-allowed;width:32px;height:32px;"' : '';
      return '<div style="background:#0e1424;border:1px solid #232f48;border-radius:14px;padding:18px;display:flex;gap:18px;align-items:flex-start;flex-wrap:wrap;">'
        + '<div style="width:180px;height:101px;border-radius:10px;overflow:hidden;background:#141c2e;flex-shrink:0;border:1px solid #232f48;">'
        + '<img src="' + coverUrl + '" alt="" style="width:100%;height:100%;object-fit:cover;" onerror="this.onerror=null;this.src=&quot;https://pdd-drive.ru/assets/og-image.png&quot;;" />'
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
        + '<input type="date" id="date-' + a.slug + '" value="' + a.datePublished + '" data-slug="' + a.slug + '" onchange="updateArticleDate(this.dataset.slug)" style="background:#0b0f19;border:1px solid #232f48;border-radius:6px;color:#38bdf8;padding:4px 8px;font-size:12.5px;font-weight:600;cursor:pointer;outline:none;" />'
        + '</div>'
        + '<div style="font-size:11.5px;color:var(--text-muted);">' + a.slug + ' · ' + (a.readingMinutes || 5) + ' мин.</div>'
        + '</div></div>'
        + '<div style="display:flex;flex-direction:column;gap:6px;justify-content:center;flex-shrink:0;align-self:center;">'
        + '<div style="display:flex;gap:4px;">'
        + '<button class="btn-icon" style="width:32px;height:32px;" title="Вверх" onclick="swapArticle(' + idx + ', ' + (idx-1) + ')"' + upDisabled + '>▲</button>'
        + '<button class="btn-icon" style="width:32px;height:32px;" title="Вниз" onclick="swapArticle(' + idx + ', ' + (idx+1) + ')"' + downDisabled + '>▼</button>'
        + '</div>'
        + '<button class="btn-action" style="padding:6px 10px;font-size:12px;color:#fb7185;border-color:rgba(251,113,133,0.3);justify-content:center;" data-slug="' + a.slug + '" onclick="deleteBlogArticle(this.dataset.slug)">🗑 Удалить</button>'
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

let cachedReels = [];

function resolveReelVideoUrl(url) {
  if (!url) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('assets/videos/')) {
    return 'https://raw.githubusercontent.com/degtyarikup-ui/pdd-rossiya-2026/main/' + url;
  }
  return url;
}

window.openReelModal = function(url, title) {
  const modal = document.getElementById('reel-player-modal');
  const video = document.getElementById('modal-video-element');
  const titleEl = document.getElementById('modal-video-title');
  titleEl.innerText = title || 'Видеоразбор';
  const resolved = resolveReelVideoUrl(url);
  video.src = resolved;
  modal.style.display = 'flex';
  video.play().catch(() => {});
};

window.closeReelModal = function() {
  const modal = document.getElementById('reel-player-modal');
  const video = document.getElementById('modal-video-element');
  modal.style.display = 'none';
  video.pause();
  video.removeAttribute('src');
  video.load();
};

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeReelModal();
});

function updateReelFormPreview() {
  const inputUrl = document.getElementById('reel-input-videourl').value.trim();
  const videoEl = document.getElementById('reel-form-preview-video');
  const emptyEl = document.getElementById('reel-form-preview-empty');
  const resolved = resolveReelVideoUrl(inputUrl);
  if (resolved) {
    videoEl.src = resolved;
    videoEl.style.display = 'block';
    emptyEl.style.display = 'none';
  } else {
    videoEl.removeAttribute('src');
    videoEl.load();
    videoEl.style.display = 'none';
    emptyEl.style.display = 'block';
  }
}

document.getElementById('reel-input-videourl').addEventListener('input', updateReelFormPreview);
document.getElementById('reel-input-videourl').addEventListener('change', updateReelFormPreview);

function updateTargetInputs() {
  const type = document.getElementById('reel-input-target-type').value;
  document.getElementById('reel-target-ticket-wrap').style.display = (type === 'ticket') ? 'block' : 'none';
  document.getElementById('reel-target-sign-wrap').style.display = (type === 'signs') ? 'block' : 'none';
  document.getElementById('reel-target-topic-wrap').style.display = (type === 'topic') ? 'block' : 'none';
}

document.getElementById('reel-input-target-type').addEventListener('change', updateTargetInputs);

document.getElementById('refresh-reels-btn').addEventListener('click', loadAdminReels);

document.getElementById('add-reel-toggle-btn').addEventListener('click', () => {
  const card = document.getElementById('reel-form-card');
  const isHidden = card.style.display === 'none';
  card.style.display = isHidden ? 'block' : 'none';
  if (isHidden) {
    document.getElementById('reel-edit-id').value = '';
    document.getElementById('reel-form-title').innerText = 'Новое видео в ленту';
    document.getElementById('reel-input-videourl').value = '';
    document.getElementById('reel-input-country').value = 'ru';
    document.getElementById('reel-input-target-type').value = 'ticket';
    document.getElementById('reel-input-ticket').value = '';
    document.getElementById('reel-input-question').value = '';
    document.getElementById('reel-input-sign-cat').value = 'Запрещающие знаки';
    document.getElementById('reel-input-topic').value = '';
    document.getElementById('reel-input-ig').value = '';
    document.getElementById('reel-input-tt').value = '';
    document.getElementById('reel-input-yt').value = '';
    updateTargetInputs();
    updateReelFormPreview();
  }
});

document.getElementById('reel-cancel-btn').addEventListener('click', () => {
  document.getElementById('reel-form-card').style.display = 'none';
});

document.getElementById('reel-save-btn').addEventListener('click', async () => {
  const id = document.getElementById('reel-edit-id').value;
  const videoUrl = document.getElementById('reel-input-videourl').value.trim();
  if (!videoUrl) {
    alert('Пожалуйста, укажите ссылку на видео!');
    return;
  }
  
  const targetType = document.getElementById('reel-input-target-type').value;
  const targetTicket = parseInt(document.getElementById('reel-input-ticket').value, 10) || null;
  const targetQuestion = parseInt(document.getElementById('reel-input-question').value, 10) || null;
  const targetSignCategory = document.getElementById('reel-input-sign-cat').value || null;
  const targetTopicId = document.getElementById('reel-input-topic').value.trim() || null;
  
  // Автоматический заголовок
  let title = 'Видеоразбор ПДД';
  if (targetType === 'ticket' && targetTicket) {
    title = 'Билет ' + targetTicket + (targetQuestion ? ', Вопрос ' + targetQuestion : '');
  } else if (targetType === 'signs' && targetSignCategory) {
    title = targetSignCategory;
  } else if (targetType === 'topic' && targetTopicId) {
    title = 'Тема: ' + targetTopicId;
  }

  const payload = {
    id: id || undefined,
    title,
    author: 'ПДД 2026',
    videoUrl,
    description: '',
    country: document.getElementById('reel-input-country').value,
    targetType,
    targetTicket,
    targetQuestion,
    targetSignCategory: (targetType === 'signs') ? targetSignCategory : null,
    targetTopicId: (targetType === 'topic') ? targetTopicId : null,
    instagramUrl: document.getElementById('reel-input-ig').value.trim(),
    tiktokUrl: document.getElementById('reel-input-tt').value.trim(),
    youtubeUrl: document.getElementById('reel-input-yt').value.trim(),
  };

  const btn = document.getElementById('reel-save-btn');
  btn.disabled = true;
  btn.innerText = 'Сохранение...';
  try {
    const res = await fetch('/api/admin/reels', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (res.ok) {
      document.getElementById('reel-form-card').style.display = 'none';
      loadAdminReels();
    } else {
      alert('Ошибка при сохранении: ' + res.statusText);
    }
  } catch (e) {
    alert('Ошибка сети: ' + e.message);
  } finally {
    btn.disabled = false;
    btn.innerText = 'Сохранить ролик';
  }
});

async function loadAdminReels() {
  const container = document.getElementById('reels-list-container');
  container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка роликов...</div>';
  try {
    const res = await fetch('/api/admin/reels');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    cachedReels = await res.json();
    document.getElementById('reels-count').innerText = cachedReels.length;
    if (!cachedReels.length) {
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">В ленте пока нет видеороликов. Нажмите «➕ Добавить видео» выше!</div>';
      return;
    }
    container.innerHTML = cachedReels.map((r, idx) => {
      const countryFlag = r.country === 'ru' ? '🇷🇺 RU' : r.country === 'by' ? '🇧🇾 BY' : r.country === 'rs' ? '🇷🇸 RS' : '🌐 ALL';
      const pddBadge = r.targetType === 'ticket' && r.targetTicket ? '🚗 Билет ' + r.targetTicket + (r.targetQuestion ? ', Вопрос ' + r.targetQuestion : '') : r.targetType === 'signs' ? '🚸 ' + (r.targetSignCategory || 'Знаки') : r.targetType === 'topic' ? '📚 Тема: ' + (r.targetTopicId || '') : '';
      const displayTitle = r.title || (r.targetType === 'ticket' && r.targetTicket ? 'Билет ' + r.targetTicket + (r.targetQuestion ? ', Вопрос ' + r.targetQuestion : '') : r.targetType === 'signs' ? (r.targetSignCategory || 'Знаки') : 'Видеоразбор ПДД');
      const safeTitle = displayTitle.replace(/'/g, "\'");
      const safeUrl = r.videoUrl.replace(/'/g, "\'");
      const icon = r.targetType === 'signs' ? '🚸' : '🚗';

      return '<div style="background:#0e1424;border:1px solid #232f48;border-radius:14px;padding:16px;display:flex;gap:16px;align-items:center;flex-wrap:wrap;">'
        + '<div onclick="openReelModal(\'' + safeUrl + '\', \'' + safeTitle + '\')" style="width:84px;height:112px;background:linear-gradient(135deg, #141c2e, #0b0f19);border:1px solid #232f48;border-radius:12px;cursor:pointer;flex-shrink:0;position:relative;display:flex;flex-direction:column;align-items:center;justify-content:center;transition:transform 0.15s, border-color 0.15s;box-shadow:0 4px 10px rgba(0,0,0,0.3);" onmouseover="this.style.transform=\'scale(1.04)\';this.style.borderColor=\'#38bdf8\'" onmouseout="this.style.transform=\'scale(1)\';this.style.borderColor=\'#232f48\'">'
        + '<div style="font-size:24px;margin-bottom:4px;">' + icon + '</div>'
        + '<div style="width:32px;height:32px;border-radius:50%;background:rgba(56,189,248,0.2);display:flex;align-items:center;justify-content:center;border:1px solid #38bdf8;">'
        + '<svg viewBox="0 0 24 24" width="14" height="14" fill="#38bdf8"><polygon points="6 4 20 12 6 20 6 4"/></svg>'
        + '</div>'
        + '</div>'
        + '<div style="flex:1;min-width:240px;">'
        + '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;gap:8px;flex-wrap:wrap;">'
        + '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">'
        + '<span class="rate-badge" style="background:#232f48;color:#38bdf8;font-weight:600;">' + countryFlag + '</span>'
        + (pddBadge ? '<span class="rate-badge" style="background:rgba(52,211,153,0.15);color:#34d399;font-weight:600;">' + pddBadge + '</span>' : '')
        + '<span style="font-size:12px;color:var(--text-muted);">❤️ ' + (r.likesCount || 0) + '</span>'
        + '</div>'
        + '<div style="display:flex;gap:8px;">'
        + '<button data-id="' + r.id + '" onclick="editReel(this.dataset.id)" class="btn-action" style="padding:4px 10px;font-size:12px;background:#1e293b;border-color:#334155;color:#fff;">✏️ Изменить</button>'
        + '<button data-id="' + r.id + '" onclick="deleteReel(this.dataset.id)" class="btn-action" style="padding:4px 8px;font-size:12px;color:#fb7185;border-color:rgba(251,113,133,0.3);">🗑️</button>'
        + '</div>'
        + '</div>'
        + '<h4 style="font-size:15px;font-weight:700;color:#fff;margin-bottom:6px;">' + displayTitle + '</h4>'
        + '<div style="font-size:11px;color:var(--text-muted);margin-bottom:10px;word-break:break-all;">'
        + '<code>' + r.videoUrl + '</code>'
        + '</div>'
        + '<div style="display:flex;gap:12px;font-size:12px;flex-wrap:wrap;align-items:center;">'
        + '<button onclick="openReelModal(\'' + safeUrl + '\', \'' + safeTitle + '\')" style="background:#38bdf8;color:#0b0f19;border:none;border-radius:6px;padding:5px 12px;font-weight:700;font-size:12px;cursor:pointer;display:inline-flex;align-items:center;gap:6px;"><svg viewBox="0 0 24 24" width="13" height="13" fill="#0b0f19"><polygon points="6 4 20 12 6 20 6 4"/></svg> Смотреть видео</button>'
        + (r.instagramUrl ? '<a href="' + r.instagramUrl + '" target="_blank" style="color:#ec4899;text-decoration:none;">Instagram</a>' : '')
        + (r.tiktokUrl ? '<a href="' + r.tiktokUrl + '" target="_blank" style="color:#06b6d4;text-decoration:none;">TikTok</a>' : '')
        + (r.youtubeUrl ? '<a href="' + r.youtubeUrl + '" target="_blank" style="color:#ef4444;text-decoration:none;">YouTube</a>' : '')
        + '</div>'
        + '</div>'
        + '</div>';
    }).join('');
  } catch (e) {
    container.innerHTML = '<div style="color:#fb7185;text-align:center;padding:20px;">Ошибка загрузки: ' + e.message + '</div>';
  }
}

window.editReel = function(id) {
  const r = cachedReels.find(x => x.id === id);
  if (!r) return;
  document.getElementById('reel-form-card').style.display = 'block';
  document.getElementById('reel-edit-id').value = r.id;
  document.getElementById('reel-form-title').innerText = 'Редактирование видео';
  document.getElementById('reel-input-videourl').value = r.videoUrl || '';
  document.getElementById('reel-input-country').value = r.country || 'ru';
  document.getElementById('reel-input-target-type').value = r.targetType || 'ticket';
  document.getElementById('reel-input-ticket').value = r.targetTicket || '';
  document.getElementById('reel-input-question').value = r.targetQuestion || '';
  document.getElementById('reel-input-sign-cat').value = r.targetSignCategory || 'Запрещающие знаки';
  document.getElementById('reel-input-topic').value = r.targetTopicId || '';
  document.getElementById('reel-input-ig').value = r.instagramUrl || '';
  document.getElementById('reel-input-tt').value = r.tiktokUrl || '';
  document.getElementById('reel-input-yt').value = r.youtubeUrl || '';
  updateTargetInputs();
  updateReelFormPreview();
  document.getElementById('reel-form-card').scrollIntoView({ behavior: 'smooth' });
};

window.deleteReel = async function(id) {
  if (confirm('Удалить этот ролик из ленты?')) {
    await fetch('/api/admin/reels/' + id, { method: 'DELETE' });
    loadAdminReels();
  }
};

let currentDays = 7;

let currentApp = 'all'; // 'all' | 'ru' | 'rs'
let timelineChart = null;
let sourcesChart = null;

const BRAND_ICONS = {
  youtube: '<span class="brand-icon-pill pill-yt"><svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M23.5 6.2a3 3 0 0 0-2.1-2.1C19.5 3.5 12 3.5 12 3.5s-7.5 0-9.4.5A3 3 0 0 0 .5 6.2 31.8 31.8 0 0 0 0 12a31.8 31.8 0 0 0 .5 5.8 3 3 0 0 0 2.1 2.1c1.9.5 9.4.5 9.4.5s7.5 0 9.4-.5a3 3 0 0 0 2.1-2.1A31.8 31.8 0 0 0 24 12a31.8 31.8 0 0 0-.5-5.8zM9.5 15.6V8.4l6.3 3.6-6.3 3.6z"/></svg></span>',
  tiktok: '<span class="brand-icon-pill pill-tt"><svg viewBox="0 0 24 24" width="14" height="14"><path fill="#25F4EE" d="M12.5.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/><path fill="#FE2C55" d="M13.4.62c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/><path fill="#fff" d="M12.95.32c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg></span>',
  instagram: '<span class="brand-icon-pill pill-ig"><svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M12 2.2c3.2 0 3.6 0 4.9.1 3.3.1 4.8 1.7 4.9 4.9.1 1.3.1 1.7.1 4.8s0 3.6-.1 4.9c-.1 3.2-1.7 4.8-4.9 4.9-1.3.1-1.7.1-4.9.1s-3.6 0-4.9-.1c-3.2-.1-4.8-1.7-4.9-4.9-.1-1.3-.1-1.7-.1-4.9s0-3.6.1-4.9c.1-3.2 1.7-4.8 4.9-4.9 1.3-.1 1.7-.1 4.9-.1zm0-2.2C8.7 0 8.3 0 7 .1 2.7.3.3 2.7.1 7 0 8.3 0 8.7 0 12s0 3.7.1 5c.2 4.3 2.6 6.7 6.9 6.9 1.3.1 1.7.1 5 .1s3.7 0 5-.1c4.3-.2 6.7-2.6 6.9-6.9.1-1.3.1-1.7.1-5s0-3.7-.1-5C23.8 2.7 21.4.3 17.1.1 15.8 0 15.4 0 12 0zm0 5.8a6.2 6.2 0 1 0 0 12.4 6.2 6.2 0 0 0 0-12.4zm0 10.2a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.4-11.8a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8z"/></svg></span>',
  telegram: '<span class="brand-icon-pill pill-tg"><svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.6 0 12 0zm5.9 8.2l-2 9.3c-.1.7-.5.8-1.1.5l-3-2.2-1.4 1.4c-.2.2-.3.3-.6.3l.2-3.1 5.6-5c.2-.2-.1-.3-.4-.1l-6.9 4.3-3-.9c-.6-.2-.7-.6.1-1l11.6-4.5c.5-.2 1 .1.8.9z"/></svg></span>',
  vk: '<span class="brand-icon-pill pill-vk"><svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M15.7 0H8.3C3 0 0 3 0 8.3v7.4C0 21 3 24 8.3 24h7.4c5.3 0 8.3-3 8.3-8.3V8.3C24 3 21 0 15.7 0zm3.7 17h-1.6c-.6 0-.8-.5-1.9-1.6-1-1-1.5-1.2-1.7-1.2-.4 0-.5.1-.5.6v1.5c0 .4-.1.7-1.2.7-1.8 0-3.7-1.1-5.1-3.1C5.3 12.5 4.7 10.3 4.7 9.8c0-.2.1-.5.6-.5h1.6c.5 0 .6.2.8.7.9 2.5 2.3 4.7 2.9 4.7.2 0 .3-.1.3-.7V11.4c-.1-1.2-.7-1.3-.7-1.7 0-.2.2-.4.4-.4h2.6c.4 0 .5.2.5.6v3.5c0 .4.2.5.3.5.2 0 .4-.1.8-.6 1.3-1.5 2.2-3.7 2.2-3.7.1-.3.3-.5.8-.5h1.6c.5 0 .6.3.5.6-.2 1-2.3 4-2.4 4.1-.3.4-.3.6 0 1 .3.3.1.3 1.6 1.8 1.1 1.1 2 2.1 2.2 2.5.2.4-.1.6-.6.6z"/></svg></span>',
  direct: '<span class="brand-icon-pill pill-direct"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg></span>'
};

const STORE_ICONS = {
  rustore: '<span class="brand-icon-pill pill-rustore"><svg viewBox="0 0 100 100" width="15" height="15"><path d="M57.8 61.6C55.1 61 53.2 58.5 53.2 55.8V23.2c0-3.1 3-5.4 6.1-4.7L78.6 23.4c2.7.7 4.6 3.1 4.6 5.8v32.6c0 3.1-3 5.4-6.1 4.7L57.8 61.6zM21.4 76.6C18.7 76 16.8 73.5 16.8 70.8V38.2c0-3.1 3-5.4 6.1-4.7L42.2 38.4c2.7.7 4.6 3.1 4.6 5.8v32.6c0 3.1-3 5.4-6.1 4.7L21.4 76.6z" fill="#fff"/></svg></span>',
  gplay: '<span class="brand-icon-pill pill-gplay"><svg viewBox="0 0 512 512" width="14" height="14"><path fill="#4285F4" d="M82.2 28.1C73.8 37 69 49.9 69 65.8v380.4c0 15.9 4.8 28.8 13.2 37.7l1.9 1.8 214.3-214.3v-5L84.1 26.3l-1.9 1.8z"/><path fill="#FFBA00" d="M369.3 328.7l-70.9-70.9v-5l70.9-70.9 2 1.1 84.1 47.8c24 13.6 24 35.9 0 49.5l-84.1 47.8-2 1.1z"/><path fill="#FF3A44" d="M298.4 257.8L82.2 474c7.9 8.4 21 9.4 35.7 1.1l253.4-144-72.9-73.3z"/><path fill="#00E676" d="M298.4 252.8l72.9-73.3L117.9 35.5C103.2 27.2 90.1 28.2 82.2 36.6L298.4 252.8z"/></svg></span>',
  appstore: '<span class="brand-icon-pill pill-appstore"><svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M18.7 19.5c-.8 1.2-1.7 2.4-3 2.4-1.4 0-1.8-.8-3.4-.8-1.6 0-2.1.8-3.4.8-1.3 0-2.3-1.3-3.1-2.5C4.2 17 3 13.6 3 10.4c0-5.1 3.3-7.8 6.5-7.8 1.7 0 3.3 1.2 4.3 1.2 1 0 2.9-1.5 4.9-1.3.8 0 3.2.3 4.7 2.5-3.9 2.3-3.3 7.5.7 9.1-.8 2-1.9 4-3.4 5.4zM15.9 2.6c.8-1 1.3-2.3 1.2-3.6-1.1.1-2.5.7-3.3 1.7-.7.8-1.4 2.2-1.2 3.5 1.3.1 2.5-.6 3.3-1.6z"/></svg></span>',
  web: '<span class="brand-icon-pill pill-web"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="#fff" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg></span>'
};

const SOURCE_COLORS = {
  youtube: '#ef4444',
  tiktok: '#06b6d4',
  instagram: '#ec4899',
  telegram: '#38bdf8',
  vk: '#0077FF',
  gplay: '#34d399',
  'google play': '#34d399',
  rustore: '#0077FF',
  appstore: '#38bdf8',
  'app store': '#38bdf8',
  web: '#0284c7',
  direct: '#64748b',
  other: '#94a3b8'
};

function getCountryFlag(code) {
  if (!code || typeof code !== 'string') return '🌐';
  const c = code.trim().toUpperCase();
  if (c.length !== 2) return '🌐';
  const codePoints = c.split('').map(char => 127397 + char.charCodeAt(0));
  return String.fromCodePoint(...codePoints);
}

function formatCountryCell(code) {
  const c = String(code || 'RU').toUpperCase();
  const flag = getCountryFlag(c);
  return '<span class="country-pill"><span class="flag-ico">' + flag + '</span><span>' + c + '</span></span>';
}

function formatBrandCell(src) {
  const raw = String(src || 'direct').trim();
  const s = raw.toLowerCase();
  if (s === 'google play' || s === 'googleplay' || s === 'gplay' || s === 'com.android.vending') {
    return '<div class="brand-cell">' + STORE_ICONS.gplay + '<span>Google Play</span></div>';
  }
  if (s === 'rustore' || s === 'ru.vk.store') {
    return '<div class="brand-cell">' + STORE_ICONS.rustore + '<span>RuStore</span></div>';
  }
  if (s === 'app store' || s === 'appstore' || s === 'apple' || s === 'com.apple.appstore') {
    return '<div class="brand-cell">' + STORE_ICONS.appstore + '<span>App Store</span></div>';
  }
  if (s === 'web' || s === 'web app') {
    return '<div class="brand-cell">' + STORE_ICONS.web + '<span>Веб-версия</span></div>';
  }
  if (s === 'yt' || s === 'youtube') {
    return '<div class="brand-cell">' + BRAND_ICONS.youtube + '<span>YouTube</span></div>';
  }
  if (s === 'tt' || s === 'tiktok') {
    return '<div class="brand-cell">' + BRAND_ICONS.tiktok + '<span>TikTok</span></div>';
  }
  if (s === 'ig' || s === 'instagram') {
    return '<div class="brand-cell">' + BRAND_ICONS.instagram + '<span>Instagram</span></div>';
  }
  if (s === 'tg' || s === 'telegram') {
    return '<div class="brand-cell">' + BRAND_ICONS.telegram + '<span>Telegram</span></div>';
  }
  if (s === 'vk') {
    return '<div class="brand-cell">' + BRAND_ICONS.vk + '<span>ВКонтакте</span></div>';
  }
  if (s === 'direct' || !s) {
    return '<div class="brand-cell">' + BRAND_ICONS.direct + '<span>Прямой переход</span></div>';
  }

  const icon = BRAND_ICONS[s] || STORE_ICONS[s] || BRAND_ICONS.direct;
  return '<div class="brand-cell">' + icon + '<span>' + raw + '</span></div>';
}

function formatTargetCell(tgt) {
  const raw = String(tgt || '').trim();
  const t = raw.toLowerCase();
  if (t === 'google play' || t === 'googleplay' || t === 'gplay' || t === 'rs-gplay' || t === 'rs') {
    return '<div class="brand-cell">' + STORE_ICONS.gplay + '<span>Google Play</span></div>';
  }
  if (t === 'rustore' || t === 'ru.vk.store') {
    return '<div class="brand-cell">' + STORE_ICONS.rustore + '<span>RuStore</span></div>';
  }
  if (t === 'app store' || t === 'appstore' || t === 'apple' || t === 'com.apple.appstore') {
    return '<div class="brand-cell">' + STORE_ICONS.appstore + '<span>App Store</span></div>';
  }
  if (t === 'web' || t === 'rs-web') {
    return '<div class="brand-cell">' + STORE_ICONS.web + '<span>Веб-версия</span></div>';
  }
  const icon = STORE_ICONS[t] || STORE_ICONS.web;
  return '<div class="brand-cell">' + icon + '<span>' + (raw || '-') + '</span></div>';
}

async function checkAuthAndLoad() {
  try {
    const r = await fetch('/api/admin/stats?days=' + currentDays + '&app=' + currentApp);
    if (r.status === 401 || r.status === 403) {
      document.getElementById('login-overlay').style.display = 'flex';
      document.getElementById('app').style.display = 'none';
      return;
    }
    if (!r.ok) {
      console.warn('Stats fetch non-ok status:', r.status);
      document.getElementById('login-overlay').style.display = 'none';
      document.getElementById('app').style.display = 'block';
      return;
    }
    const data = await r.json();
    document.getElementById('login-overlay').style.display = 'none';
    document.getElementById('app').style.display = 'block';

    renderDashboard(data);
  } catch (err) {
    console.error('checkAuthAndLoad error:', err);
  }
}

async function handleLoginSubmit() {
  const pwd = (document.getElementById('login-pwd').value || '').trim();
  const errDiv = document.getElementById('login-err');
  errDiv.style.display = 'none';
  if (!pwd) {
    errDiv.style.display = 'block';
    return;
  }
  try {
    const r = await fetch('/api/admin/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ password: pwd })
    });
    if (!r.ok) {
      errDiv.style.display = 'block';
      return;
    }
    document.getElementById('login-overlay').style.display = 'none';
    document.getElementById('app').style.display = 'block';
    checkAuthAndLoad();
  } catch (_) {
    errDiv.style.display = 'block';
  }
}

document.getElementById('login-submit-btn').addEventListener('click', handleLoginSubmit);
document.getElementById('login-pwd').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') handleLoginSubmit();
});

document.getElementById('logout-btn').addEventListener('click', async () => {
  await fetch('/api/admin/logout', { method: 'POST' });
  location.reload();
});

// Переключение проекта (Все / РФ / Сербия)
document.querySelectorAll('#app-tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#app-tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentApp = btn.dataset.app;
    
    // Обновляем заголовок и логотип шапки
    const appTitle = document.getElementById('header-app-title');
    const logoImg = document.getElementById('header-logo');
    if (currentApp === 'rs') {
      appTitle.innerText = 'Auto testovi Srbija (Google Play)';
    } else if (currentApp === 'ru') {
      appTitle.innerText = 'ПДД Россия 2026';
    } else {
      appTitle.innerText = 'ПДД Аналитика (Все проекты)';
    }

    checkAuthAndLoad();
  });
});

// Переключение периода (дни)
document.querySelectorAll('#period-buttons button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#period-buttons button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentDays = parseInt(btn.dataset.days, 10);
    checkAuthAndLoad();
  });
});

document.getElementById('refresh-btn').addEventListener('click', checkAuthAndLoad);

function renderDashboard(data) {
  // 1. KPI Cards
  document.getElementById('m-views').innerText = data.totals.views.toLocaleString();
  document.getElementById('m-clicks').innerText = data.totals.clicks.toLocaleString();
  document.getElementById('m-installs').innerText = data.totals.installs.toLocaleString();
  document.getElementById('m-grand').innerText = data.totals.grandTotal.toLocaleString();
  document.getElementById('m-ctr').innerText = 'CTR: ' + data.totals.ctr + '%';
  document.getElementById('m-cr').innerText = 'CR: ' + data.totals.cr + '%';

  const grandSub = document.getElementById('m-grand-sub');
  if (currentApp === 'rs') {
    grandSub.innerText = 'Установок Сербии в Google Play';
  } else if (currentApp === 'ru') {
    grandSub.innerText = 'Установок РФ за всё время';
  } else {
    grandSub.innerText = 'Суммарно по всем проектам';
  }

  // 2. Timeline Chart (Modern Gradient Line)
  const ctxTimeline = document.getElementById('chart-timeline').getContext('2d');
  const labels = data.timeline.map(t => {
    const p = t.date.split('-');
    return p[2] + '.' + p[1];
  });
  const viewsData = data.timeline.map(t => t.views);
  const clicksData = data.timeline.map(t => t.clicks);
  const installsData = data.timeline.map(t => t.installs);

  const gradViews = ctxTimeline.createLinearGradient(0, 0, 0, 260);
  gradViews.addColorStop(0, 'rgba(56, 189, 248, 0.25)');
  gradViews.addColorStop(1, 'rgba(56, 189, 248, 0.0)');

  if (timelineChart) timelineChart.destroy();
  timelineChart = new Chart(ctxTimeline, {
    type: 'line',
    data: {
      labels,
      datasets: [
        { label: 'Просмотры', data: viewsData, borderColor: '#38bdf8', backgroundColor: gradViews, borderWidth: 2.5, tension: 0.35, fill: true, pointRadius: 3, pointHoverRadius: 6 },
        { label: 'Клики в сторы', data: clicksData, borderColor: '#fb7185', backgroundColor: 'transparent', borderWidth: 2.5, tension: 0.35, pointRadius: 3, pointHoverRadius: 6 },
        { label: 'Установки', data: installsData, borderColor: '#34d399', backgroundColor: 'transparent', borderWidth: 2.5, tension: 0.35, pointRadius: 3, pointHoverRadius: 6 }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { labels: { color: '#8e9db5', boxWidth: 12, usePointStyle: true, font: { size: 12, weight: '600' } } },
        tooltip: {
          backgroundColor: '#141c2e',
          titleColor: '#fff',
          bodyColor: '#cbd5e1',
          borderColor: '#232f48',
          borderWidth: 1,
          padding: 12,
          boxPadding: 6,
          usePointStyle: true,
          cornerRadius: 10
        }
      },
      scales: {
        x: { grid: { color: 'rgba(255,255,255,0.04)' }, ticks: { color: '#8e9db5', font: { size: 11 } } },
        y: { grid: { color: 'rgba(255,255,255,0.04)' }, ticks: { color: '#8e9db5', font: { size: 11 } }, beginAtZero: true }
      }
    }
  });

  // 3. Sources Doughnut Chart (Трафик)
  const ctxSources = document.getElementById('chart-sources').getContext('2d');
  const validTrafficSources = (data.sources || []).filter(s => (s.views || 0) > 0 || (s.clicks || 0) > 0);
  const srcLabels = validTrafficSources.map(s => {
    const k = s.name.toLowerCase();
    return k === 'youtube' ? 'YouTube' : k === 'tiktok' ? 'TikTok' : k === 'instagram' ? 'Instagram' : k === 'telegram' ? 'Telegram' : k === 'vk' ? 'ВКонтакте' : k === 'direct' ? 'Прямой' : s.name;
  });
  const srcViews = validTrafficSources.map(s => (s.views || s.clicks || 0));
  const bgColors = validTrafficSources.map(s => SOURCE_COLORS[s.name.toLowerCase()] || '#64748b');

  if (sourcesChart) sourcesChart.destroy();
  sourcesChart = new Chart(ctxSources, {
    type: 'doughnut',
    data: {
      labels: srcLabels.length ? srcLabels : ['Нет данных'],
      datasets: [{
        data: srcViews.length ? srcViews : [1],
        backgroundColor: srcViews.length ? bgColors : ['#232f48'],
        borderWidth: 0,
        borderRadius: 4,
        spacing: 3
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: '72%',
      plugins: {
        legend: { position: 'bottom', labels: { color: '#8e9db5', boxWidth: 10, usePointStyle: true, padding: 14, font: { size: 11, weight: '600' } } },
        tooltip: {
          backgroundColor: '#141c2e',
          borderColor: '#232f48',
          borderWidth: 1,
          padding: 10,
          cornerRadius: 10
        }
      }
    }
  });

  // 4. Sources Table
  const tbodySources = document.getElementById('table-sources');
  if (!data.sources.length) {
    tbodySources.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#8e9db5;">Нет данных за выбранный период</td></tr>';
  } else {
    tbodySources.innerHTML = data.sources.map(s => \`
      <tr>
        <td>\${formatBrandCell(s.name)}</td>
        <td><b>\${s.views}</b></td>
        <td>\${s.clicks}</td>
        <td><span class="rate-badge">\${s.ctr}%</span></td>
        <td><span style="color:#34d399;font-weight:700;">\${s.installs}</span></td>
      </tr>
    \`).join('');
  }

  // 5. Targets Table
  const tbodyTargets = document.getElementById('table-targets');
  const totalClicks = data.totals.clicks || 1;
  if (!data.targets.length) {
    tbodyTargets.innerHTML = '<tr><td colspan="3" style="text-align:center;color:#8e9db5;">Кликов пока не было</td></tr>';
  } else {
    tbodyTargets.innerHTML = data.targets.map(t => {
      const share = ((t.clicks / totalClicks) * 100).toFixed(1);
      return \`
        <tr>
          <td>\${formatTargetCell(t.name)}</td>
          <td><b>\${t.clicks}</b></td>
          <td><span class="rate-badge">\${share}%</span></td>
        </tr>
      \`;
    }).join('');
  }

  // 6. Campaigns Table
  const tbodyCamp = document.getElementById('table-campaigns');
  if (!data.campaigns.length) {
    tbodyCamp.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#8e9db5;">Кампании пока не зафиксированы</td></tr>';
  } else {
    tbodyCamp.innerHTML = data.campaigns.map(c => \`
      <tr>
        <td><code style="background:#0e1424;padding:3px 8px;border-radius:6px;color:#38bdf8;border:1px solid #232f48;">\${c.name}</code></td>
        <td>\${formatBrandCell(c.source)}</td>
        <td>\${c.views}</td>
        <td><b>\${c.clicks}</b></td>
        <td><span class="rate-badge">\${c.ctr}%</span></td>
      </tr>
    \`).join('');
  }

  // 7. Live Activity Table
  const tbodyLive = document.getElementById('table-live');
  if (!data.recent || !data.recent.length) {
    tbodyLive.innerHTML = '<tr><td colspan="7" style="text-align:center;color:#8e9db5;">Ожидание событий...</td></tr>';
  } else {
    tbodyLive.innerHTML = data.recent.slice(0, 35).map(r => {
      const time = new Date(r.time).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
      const typeBadge = r.type === 'view' ? '<span class="event-type-badge ev-view">Просмотр</span>' : r.type === 'click' ? '<span class="event-type-badge ev-click">Клик</span>' : '<span class="event-type-badge ev-install">Установка</span>';
      const projBadge = r.app === 'rs' ? '<span class="project-pill pill-rs">🇷🇸 Сербия</span>' : '<span class="project-pill pill-ru">🇷🇺 РФ</span>';
      return \`
        <tr>
          <td class="time-badge">\${time}</td>
          <td>\${projBadge}</td>
          <td>\${typeBadge}</td>
          <td>\${formatBrandCell(r.source)}</td>
          <td>\${r.campaign ? '<code style="color:#38bdf8;">' + r.campaign + '</code>' : '<span style="color:#64748b;">-</span>'}</td>
          <td>\${r.target ? formatTargetCell(r.target) : '<span style="color:#8e9db5;">' + (r.platform || '-') + '</span>'}</td>
          <td>\${formatCountryCell(r.country)}</td>
        </tr>
      \`;
    }).join('');
  }
}

// Генератор ссылок
function updateGeneratedLink() {
  const page = document.getElementById('gen-page').value;
  const src = document.getElementById('gen-source').value;
  const camp = document.getElementById('gen-camp').value.trim().replace(/\\s+/g, '_');
  let refValue = src;
  if (camp) refValue += '_' + camp;
  const finalUrl = page + '?ref=' + encodeURIComponent(refValue);
  document.getElementById('gen-output').innerText = finalUrl;
}

document.getElementById('gen-page').addEventListener('change', updateGeneratedLink);
document.getElementById('gen-source').addEventListener('change', updateGeneratedLink);
document.getElementById('gen-camp').addEventListener('input', updateGeneratedLink);

document.getElementById('copy-link-btn').addEventListener('click', () => {
  const url = document.getElementById('gen-output').innerText;
  navigator.clipboard.writeText(url).then(() => {
    const btn = document.getElementById('copy-link-btn');
    btn.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>Скопировано!</span>';
    setTimeout(() => {
      btn.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg><span>Скопировать</span>';
    }, 1800);
  });
});

checkAuthAndLoad();
setInterval(checkAuthAndLoad, 30000);
