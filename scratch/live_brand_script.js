

// ────────────────────── State ──────────────────────
let currentFeature = 'analytics';
let currentDays = 7;
let currentApp = 'all'; // 'all' | 'ru' | 'rs'
let cachedReels = [];
let cachedBlogArticles = [];

let chartInstalls = null;
let chartTargets = null;
let chartWebFunnel = null;
let chartSources = null;

// Brand color maps
const STORE_CONFIG = {
  appstore: { name: 'App Store', color: '#38bdf8' },
  gplay: { name: 'Google Play', color: '#10b981' },
  rustore: { name: 'RuStore', color: '#0077ff' },
  web: { name: 'Веб-версия', color: '#8b5cf6' }
};

const SOURCE_CONFIG = {
  youtube: { name: 'YouTube', color: '#ef4444' },
  instagram: { name: 'Instagram', color: '#ec4899' },
  tiktok: { name: 'TikTok', color: '#06b6d4' },
  telegram: { name: 'Telegram', color: '#229ed9' },
  vk: { name: 'ВКонтакте', color: '#0077ff' },
  yandex: { name: 'Яндекс', color: '#f59e0b' },
  direct: { name: 'Прямой переход', color: '#64748b' },
  organic_gplay: { name: 'Органика Google Play', color: '#10b981' },
  organic_rustore: { name: 'Органика RuStore', color: '#0077ff' },
  organic_appstore: { name: 'Органика App Store', color: '#38bdf8' },
  other: { name: 'Прочее', color: '#475569' }
};

function normalizeStore(raw) {
  const s = String(raw || '').toLowerCase().trim();
  if (s.includes('rustore') || s.includes('vk.store')) return 'rustore';
  if (s.includes('gplay') || s.includes('google') || s.includes('vending') || s.includes('android')) return 'gplay';
  if (s.includes('appstore') || s.includes('apple') || s.includes('ios')) return 'appstore';
  if (s.includes('web')) return 'web';
  return null; // Ignore non-published stores
}

function normalizeSource(raw) {
  const s = String(raw || '').toLowerCase().trim();
  if (s === 'yt' || s.includes('youtube')) return 'youtube';
  if (s === 'ig' || s.includes('instagram')) return 'instagram';
  if (s === 'tt' || s.includes('tiktok')) return 'tiktok';
  if (s === 'tg' || s.includes('telegram')) return 'telegram';
  if (s === 'vk' || s.includes('vkontakte')) return 'vk';
  if (s.includes('yandex') || s.includes('ya.ru')) return 'yandex';
  if (s.includes('rustore')) return 'organic_rustore';
  if (s.includes('google play') || s.includes('gplay') || s.includes('vending')) return 'organic_gplay';
  if (s.includes('app store') || s.includes('apple')) return 'organic_appstore';
  if (s.includes('galaxy') || s.includes('samsung')) return 'organic_gplay'; // Map Samsung to Google Play Android
  if (s === 'direct' || !s) return 'direct';
  return 'other';
}

// ────────────────────── Sidebar Navigation ──────────────────────
const VIEW_TITLES = {
  analytics: 'Аналитика продукта',
  reels: 'Видеоразборы (Рилсы)',
  links: 'Генератор ссылок и кампании',
  blog: 'Статьи блога',
  threads: 'Threads автопостер'
};

document.querySelectorAll('.sidebar-menu .nav-item').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.sidebar-menu .nav-item').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFeature = btn.dataset.feature;
    
    document.getElementById('current-view-title').innerText = VIEW_TITLES[currentFeature] || 'Панель управления';

    document.getElementById('analytics-view').style.display = currentFeature === 'analytics' ? 'block' : 'none';
    document.getElementById('reels-view').style.display = currentFeature === 'reels' ? 'block' : 'none';
    document.getElementById('links-view').style.display = currentFeature === 'links' ? 'block' : 'none';
    document.getElementById('blog-view').style.display = currentFeature === 'blog' ? 'block' : 'none';
    document.getElementById('threads-view').style.display = currentFeature === 'threads' ? 'block' : 'none';

    if (currentFeature === 'analytics') checkAuthAndLoad();
    else if (currentFeature === 'reels') loadAdminReels();
    else if (currentFeature === 'links') { checkAuthAndLoad(); updateGeneratedLink(); }
    else if (currentFeature === 'blog') loadBlogArticles();
    else if (currentFeature === 'threads') loadThreadsQueue();
  });
});

// App / Project Selector
document.getElementById('sidebar-app-select').addEventListener('change', (e) => {
  currentApp = e.target.value;
  checkAuthAndLoad();
});

// Period Selector
document.querySelectorAll('#period-buttons button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#period-buttons button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentDays = parseInt(btn.dataset.days, 10);
    checkAuthAndLoad();
  });
});

document.getElementById('refresh-btn').addEventListener('click', checkAuthAndLoad);

// ────────────────────── Auth ──────────────────────
async function checkAuthAndLoad() {
  try {
    const r = await fetch('/api/admin/stats?days=' + currentDays + '&app=' + currentApp);
    if (r.status === 401 || r.status === 403) {
      document.getElementById('login-overlay').style.display = 'flex';
      document.getElementById('app').style.display = 'none';
      return;
    }
    if (!r.ok) return;
    const data = await r.json();
    document.getElementById('login-overlay').style.display = 'none';
    document.getElementById('app').style.display = 'flex';
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
    document.getElementById('app').style.display = 'flex';
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

// ────────────────────── Dashboard Analytics Rendering ──────────────────────
function renderDashboard(data) {
  // 1. KPI Cards
  document.getElementById('m-installs').innerText = (data.totals.installs || 0).toLocaleString();
  document.getElementById('m-grand').innerText = (data.totals.grandTotal || 0).toLocaleString();
  document.getElementById('m-views').innerText = (data.totals.views || 0).toLocaleString();
  document.getElementById('m-clicks').innerText = (data.totals.clicks || 0).toLocaleString();
  document.getElementById('m-ctr').innerText = 'CTR: ' + (data.totals.ctr || 0) + '%';
  document.getElementById('m-cr').innerText = (data.totals.cr || 0) + '%';

  const labels = data.timeline.map(t => {
    const p = t.date.split('-');
    return p[2] + '.' + p[1];
  });

  // 2. Chart: App Installs Growth (Line with soft emerald gradient)
  const ctxInstalls = document.getElementById('chart-installs').getContext('2d');
  const gradInstalls = ctxInstalls.createLinearGradient(0, 0, 0, 240);
  gradInstalls.addColorStop(0, 'rgba(16, 185, 129, 0.28)');
  gradInstalls.addColorStop(1, 'rgba(16, 185, 129, 0.0)');

  if (chartInstalls) chartInstalls.destroy();
  chartInstalls = new Chart(ctxInstalls, {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'Установки приложения',
        data: data.timeline.map(t => t.installs),
        borderColor: '#10b981',
        backgroundColor: gradInstalls,
        borderWidth: 2.5,
        tension: 0.3,
        fill: true,
        pointRadius: 3,
        pointHoverRadius: 6
      }]
    },
    options: getChartOptions()
  });

  // 3. Chart: Platforms & Stores (Filtered & Mapped to Official Brand Colors)
  const storeAgg = {};
  (data.targets || []).forEach(t => {
    const key = normalizeStore(t.name);
    if (key) {
      storeAgg[key] = (storeAgg[key] || 0) + (t.clicks || 0);
    }
  });

  // If no clicks yet, show published stores structure
  const storeKeys = Object.keys(storeAgg).length ? Object.keys(storeAgg) : ['appstore', 'gplay', 'rustore'];
  const storeLabels = storeKeys.map(k => STORE_CONFIG[k] ? STORE_CONFIG[k].name : k);
  const storeValues = storeKeys.map(k => storeAgg[k] || 0);
  const storeColors = storeKeys.map(k => STORE_CONFIG[k] ? STORE_CONFIG[k].color : '#64748b');

  const ctxTargets = document.getElementById('chart-targets').getContext('2d');
  if (chartTargets) chartTargets.destroy();
  chartTargets = new Chart(ctxTargets, {
    type: 'doughnut',
    data: {
      labels: storeLabels,
      datasets: [{
        data: storeValues.some(v => v > 0) ? storeValues : [1, 1, 1],
        backgroundColor: storeColors,
        borderWidth: 0,
        hoverOffset: 4
      }]
    },
    options: getDoughnutOptions()
  });

  // 4. Chart: Web Marketing Funnel (Views vs Clicks)
  const ctxWeb = document.getElementById('chart-web-funnel').getContext('2d');
  const gradViews = ctxWeb.createLinearGradient(0, 0, 0, 240);
  gradViews.addColorStop(0, 'rgba(56, 189, 248, 0.25)');
  gradViews.addColorStop(1, 'rgba(56, 189, 248, 0.0)');

  if (chartWebFunnel) chartWebFunnel.destroy();
  chartWebFunnel = new Chart(ctxWeb, {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Визиты лендинга',
          data: data.timeline.map(t => t.views),
          borderColor: '#38bdf8',
          backgroundColor: gradViews,
          borderWidth: 2,
          tension: 0.3,
          fill: true,
          pointRadius: 2.5
        },
        {
          label: 'Клики в сторы',
          data: data.timeline.map(t => t.clicks),
          borderColor: '#f43f5e',
          backgroundColor: 'transparent',
          borderWidth: 2,
          tension: 0.3,
          pointRadius: 2.5
        }
      ]
    },
    options: getChartOptions()
  });

  // 5. Chart: Traffic Sources (Aggregated & Colored with Official Social Brand Colors)
  const sourceAgg = {};
  (data.sources || []).forEach(s => {
    const key = normalizeSource(s.name);
    const count = s.views || s.clicks || s.installs || 0;
    if (count > 0) {
      sourceAgg[key] = (sourceAgg[key] || 0) + count;
    }
  });

  const sourceKeys = Object.keys(sourceAgg).length ? Object.keys(sourceAgg) : ['direct'];
  const srcLabels = sourceKeys.map(k => SOURCE_CONFIG[k] ? SOURCE_CONFIG[k].name : k);
  const srcValues = sourceKeys.map(k => sourceAgg[k] || 0);
  const srcColors = sourceKeys.map(k => SOURCE_CONFIG[k] ? SOURCE_CONFIG[k].color : '#64748b');

  const ctxSources = document.getElementById('chart-sources').getContext('2d');
  if (chartSources) chartSources.destroy();
  chartSources = new Chart(ctxSources, {
    type: 'doughnut',
    data: {
      labels: srcLabels,
      datasets: [{
        data: srcValues.some(v => v > 0) ? srcValues : [1],
        backgroundColor: srcColors,
        borderWidth: 0,
        hoverOffset: 4
      }]
    },
    options: getDoughnutOptions()
  });

  // 6. Table: Channels / Sources
  const tbodySources = document.getElementById('table-sources');
  const validSources = (data.sources || []).filter(s => normalizeSource(s.name) !== null);
  if (!validSources.length) {
    tbodySources.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);">Нет данных за период</td></tr>';
  } else {
    tbodySources.innerHTML = validSources.map(s => {
      const srcKey = normalizeSource(s.name);
      const conf = SOURCE_CONFIG[srcKey] || { name: s.name, color: '#64748b' };
      return '<tr>'
        + '<td><span style="display:inline-flex;align-items:center;gap:8px;font-weight:600;"><span style="width:8px;height:8px;border-radius:50%;background:' + conf.color + ';"></span>' + conf.name + '</span></td>'
        + '<td>' + s.views + '</td>'
        + '<td>' + s.clicks + '</td>'
        + '<td><span class="tag-badge">' + s.ctr + '%</span></td>'
        + '<td><span style="color:#10b981;font-weight:600;">' + (s.installs || 0) + '</span></td>'
        + '</tr>';
    }).join('');
  }

  // 7. Table: Campaigns
  const tbodyCamp = document.getElementById('table-campaigns');
  if (!data.campaigns || !data.campaigns.length) {
    tbodyCamp.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);">Нет данных по кампаниям</td></tr>';
  } else {
    tbodyCamp.innerHTML = data.campaigns.map(c => {
      return '<tr>'
        + '<td><span class="code-badge">' + c.name + '</span></td>'
        + '<td>' + c.source + '</td>'
        + '<td>' + c.views + '</td>'
        + '<td>' + c.clicks + '</td>'
        + '<td><span class="tag-badge">' + c.ctr + '%</span></td>'
        + '</tr>';
    }).join('');
  }

  // 8. Table: Live Feed
  const tbodyLive = document.getElementById('table-live');
  if (!data.recentEvents || !data.recentEvents.length) {
    tbodyLive.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);">Ожидание событий...</td></tr>';
  } else {
    tbodyLive.innerHTML = data.recentEvents.slice(0, 15).map(ev => {
      const typeBadge = ev.type === 'install' 
        ? '<span class="kpi-badge badge-green">Установка</span>' 
        : ev.type === 'click' 
        ? '<span class="kpi-badge badge-blue">Клик в стор</span>' 
        : '<span class="tag-badge">Визит</span>';
      const cleanSrc = ev.source ? (SOURCE_CONFIG[normalizeSource(ev.source)]?.name || ev.source) : 'Прямой';
      return '<tr>'
        + '<td style="color:var(--text-muted);font-family:monospace;font-size:11.5px;">' + (ev.time || '') + '</td>'
        + '<td>' + typeBadge + '</td>'
        + '<td>' + cleanSrc + '</td>'
        + '<td>' + (ev.campaign ? '<span class="code-badge">' + ev.campaign + '</span>' : '-') + '</td>'
        + '<td><span class="tag-badge">' + (ev.country || 'RU') + '</span></td>'
        + '</tr>';
    }).join('');
  }
}

function getChartOptions() {
  return {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { labels: { color: '#64748b', boxWidth: 10, usePointStyle: true, font: { size: 11.5 } } },
      tooltip: {
        backgroundColor: '#0f172a',
        titleColor: '#fff',
        bodyColor: '#94a3b8',
        borderColor: '#1e293b',
        borderWidth: 1,
        padding: 10,
        cornerRadius: 8
      }
    },
    scales: {
      x: { grid: { color: 'rgba(255,255,255,0.03)' }, ticks: { color: '#64748b', font: { size: 11 } } },
      y: { grid: { color: 'rgba(255,255,255,0.03)' }, ticks: { color: '#64748b', font: { size: 11 } }, beginAtZero: true }
    }
  };
}

function getDoughnutOptions() {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { position: 'bottom', labels: { color: '#94a3b8', boxWidth: 10, usePointStyle: true, font: { size: 11 } } }
    },
    cutout: '72%'
  };
}

// ────────────────────── Reels Module ──────────────────────
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
    btn.innerText = 'Сохранить';
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
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">В ленте пока нет видеороликов.</div>';
      return;
    }
    container.innerHTML = cachedReels.map((r, idx) => {
      const countryCode = (r.country || 'ru').toUpperCase();
      const pddBadge = r.targetType === 'ticket' && r.targetTicket 
        ? 'Билет ' + r.targetTicket + (r.targetQuestion ? ', Вопрос ' + r.targetQuestion : '') 
        : r.targetType === 'signs' 
        ? (r.targetSignCategory || 'Знаки') 
        : r.targetType === 'topic' 
        ? 'Тема ' + (r.targetTopicId || '') 
        : '';
      const displayTitle = r.title || pddBadge || 'Видеоразбор ПДД';
      const safeTitle = displayTitle.replace(/'/g, "\\'");
      const safeUrl = r.videoUrl.replace(/'/g, "\\'");

      return '<div style="background:#0b1120;border:1px solid var(--card-border);border-radius:12px;padding:14px 16px;display:flex;gap:14px;align-items:center;flex-wrap:wrap;">'
        + '<div onclick="openReelModal(\'' + safeUrl + '\', \'' + safeTitle + '\')" style="width:70px;height:95px;background:#141c2e;border:1px solid var(--card-border);border-radius:9px;cursor:pointer;flex-shrink:0;display:flex;flex-direction:column;align-items:center;justify-content:center;transition:all 0.15s;" onmouseover="this.style.borderColor=\'var(--primary)\'" onmouseout="this.style.borderColor=\'var(--card-border)\'">'
        + '<div style="width:28px;height:28px;border-radius:50%;background:rgba(56,189,248,0.15);display:flex;align-items:center;justify-content:center;color:var(--primary);">'
        + '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>'
        + '</div>'
        + '</div>'
        + '<div style="flex:1;min-width:220px;">'
        + '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;gap:8px;flex-wrap:wrap;">'
        + '<div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;">'
        + '<span class="tag-badge">' + countryCode + '</span>'
        + (pddBadge ? '<span class="kpi-badge badge-blue">' + pddBadge + '</span>' : '')
        + '<span style="font-size:11.5px;color:var(--text-muted);margin-left:4px;">Лайки: ' + (r.likesCount || 0) + '</span>'
        + '</div>'
        + '<div style="display:flex;gap:6px;">'
        + '<button data-id="' + r.id + '" onclick="editReel(this.dataset.id)" class="btn-action" style="padding:4px 8px;font-size:11.5px;">Изменить</button>'
        + '<button data-id="' + r.id + '" onclick="deleteReel(this.dataset.id)" class="btn-action" style="padding:4px 8px;font-size:11.5px;color:var(--danger);border-color:rgba(244,63,94,0.2);">Удалить</button>'
        + '</div>'
        + '</div>'
        + '<div style="font-size:14.5px;font-weight:700;color:#fff;margin-bottom:4px;">' + displayTitle + '</div>'
        + '<div style="font-size:11px;color:var(--text-muted);margin-bottom:8px;word-break:break-all;">'
        + '<code>' + r.videoUrl + '</code>'
        + '</div>'
        + '<div style="display:flex;gap:10px;font-size:11.5px;flex-wrap:wrap;align-items:center;">'
        + '<button onclick="openReelModal(\'' + safeUrl + '\', \'' + safeTitle + '\')" style="background:var(--primary);color:#090d16;border:none;border-radius:6px;padding:4px 10px;font-weight:700;font-size:11.5px;cursor:pointer;display:inline-flex;align-items:center;gap:5px;"><svg viewBox="0 0 24 24" width="11" height="11" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg> Смотреть</button>'
        + (r.instagramUrl ? '<a href="' + r.instagramUrl + '" target="_blank" style="color:var(--text-light);text-decoration:none;">Instagram</a>' : '')
        + (r.tiktokUrl ? '<a href="' + r.tiktokUrl + '" target="_blank" style="color:var(--text-light);text-decoration:none;">TikTok</a>' : '')
        + (r.youtubeUrl ? '<a href="' + r.youtubeUrl + '" target="_blank" style="color:var(--text-light);text-decoration:none;">YouTube</a>' : '')
        + '</div>'
        + '</div>'
        + '</div>';
    }).join('');
  } catch (e) {
    container.innerHTML = '<div style="color:var(--danger);text-align:center;padding:20px;">Ошибка загрузки: ' + e.message + '</div>';
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

// ────────────────────── Link Generator Module ──────────────────────
function updateGeneratedLink() {
  const page = document.getElementById('gen-page').value;
  const src = document.getElementById('gen-source').value;
  const camp = document.getElementById('gen-camp').value.trim().replace(/\s+/g, '_');
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
    btn.innerText = 'Скопировано!';
    setTimeout(() => { btn.innerText = 'Скопировать'; }, 1800);
  });
});

// ────────────────────── Blog Articles Module ──────────────────────
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
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:30px;background:#0b1120;border-radius:10px;border:1px dashed var(--card-border);">Все статьи уже опубликованы</div>';
      return;
    }
    container.innerHTML = cachedBlogArticles.map(function(a, idx) {
      var coverUrl = a.cover ? 'https://pdd-drive.ru/blog/' + a.slug + '/' + a.cover + '?v=20260823_v3' : 'https://pdd-drive.ru/assets/og-image.png';
      var isFirst = idx === 0;
      var isLast = idx === cachedBlogArticles.length - 1;
      var upDisabled = isFirst ? ' disabled style="opacity:0.3;cursor:not-allowed;"' : '';
      var downDisabled = isLast ? ' disabled style="opacity:0.3;cursor:not-allowed;"' : '';
      return '<div style="background:#0b1120;border:1px solid var(--card-border);border-radius:12px;padding:14px 16px;display:flex;gap:16px;align-items:center;flex-wrap:wrap;">'
        + '<div style="width:140px;height:78px;border-radius:8px;overflow:hidden;background:#141c2e;flex-shrink:0;border:1px solid var(--card-border);">'
        + '<img src="' + coverUrl + '" alt="" style="width:100%;height:100%;object-fit:cover;" onerror="this.onerror=null;this.src=\'https://pdd-drive.ru/assets/og-image.png\';" />'
        + '</div>'
        + '<div style="flex:1;min-width:240px;">'
        + '<div style="font-size:14.5px;font-weight:700;color:#fff;margin-bottom:4px;">' + a.title + '</div>'
        + '<div style="font-size:11.5px;color:var(--text-muted);margin-bottom:8px;">' + (a.description || '') + '</div>'
        + '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">'
        + '<input type="date" id="date-' + a.slug + '" value="' + a.datePublished + '" data-slug="' + a.slug + '" onchange="updateArticleDate(this.dataset.slug)" style="background:#141c2e;border:1px solid var(--card-border);border-radius:6px;color:var(--primary);padding:3px 6px;font-size:12px;font-weight:600;outline:none;" />'
        + '<span style="font-size:11px;color:var(--text-muted);">' + a.slug + ' · ' + (a.readingMinutes || 5) + ' мин.</span>'
        + '</div>'
        + '</div>'
        + '<div style="display:flex;gap:6px;align-items:center;flex-shrink:0;">'
        + '<button class="btn-icon" style="width:30px;height:30px;" title="Вверх" onclick="swapArticle(' + idx + ', ' + (idx-1) + ')"' + upDisabled + '>▲</button>'
        + '<button class="btn-icon" style="width:30px;height:30px;" title="Вниз" onclick="swapArticle(' + idx + ', ' + (idx+1) + ')"' + downDisabled + '>▼</button>'
        + '<button class="btn-action" style="padding:4px 8px;font-size:11.5px;color:var(--danger);border-color:rgba(244,63,94,0.2);" data-slug="' + a.slug + '" onclick="deleteBlogArticle(this.dataset.slug)">Удалить</button>'
        + '</div>'
        + '</div>';
    }).join('');
  } catch (err) {
    container.innerHTML = '<div style="color:var(--danger);text-align:center;padding:20px;">Ошибка: ' + err.message + '</div>';
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

document.getElementById('refresh-blog-btn').addEventListener('click', loadBlogArticles);
document.getElementById('reset-blog-btn').addEventListener('click', async () => {
  if (confirm('Сбросить список статей к исходному состоянию?')) {
    await fetch('/api/admin/blog/reset', { method: 'POST' });
    loadBlogArticles();
  }
});

// ────────────────────── Threads Module ──────────────────────
async function loadThreadsQueue() {
  const container = document.getElementById('threads-queue-container');
  container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:20px;">Загрузка...</div>';
  try {
    const res = await fetch('/api/admin/threads');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    const queue = await res.json();
    if (!queue.length) {
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:30px;background:#0b1120;border-radius:10px;border:1px dashed var(--card-border);">Очередь постов пуста</div>';
      return;
    }
    container.innerHTML = queue.map(p => {
      return '<div style="background:#0b1120;border:1px solid var(--card-border);border-radius:12px;padding:16px;">'
        + '<div style="display:flex;justify-content:space-between;margin-bottom:8px;font-size:11.5px;color:var(--text-muted);">'
        + '<span>Дата: ' + (p.scheduledDate || 'Без даты') + '</span>'
        + '<span class="tag-badge">' + (p.status || 'pending') + '</span>'
        + '</div>'
        + '<textarea id="text-' + p.id + '" style="width:100%;min-height:70px;background:#141c2e;border:1px solid var(--card-border);border-radius:8px;color:#fff;padding:8px 10px;font-family:inherit;font-size:12.5px;margin-bottom:8px;">' + (p.text || '') + '</textarea>'
        + '<input type="text" id="img-' + p.id + '" value="' + (p.imageUrl || '') + '" placeholder="Image URL" style="width:100%;background:#141c2e;border:1px solid var(--card-border);border-radius:6px;color:#fff;padding:6px 10px;font-size:11.5px;margin-bottom:10px;" />'
        + '<div style="display:flex;gap:8px;">'
        + '<button class="btn-action" data-id="' + p.id + '" onclick="savePost(this.dataset.id)">Сохранить</button>'
        + '<button class="btn-action" style="color:var(--danger);border-color:rgba(244,63,94,0.2);" data-id="' + p.id + '" onclick="deletePost(this.dataset.id)">Удалить</button>'
        + '<button class="btn-action btn-primary" data-id="' + p.id + '" onclick="publishPostNow(this.dataset.id)">Опубликовать</button>'
        + '</div></div>';
    }).join('');
  } catch (err) {
    container.innerHTML = '<div style="color:var(--danger);text-align:center;padding:20px;">Ошибка: ' + err.message + '</div>';
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
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(9,13,22,0.92);backdrop-filter:blur(8px);display:flex;align-items:center;justify-content:center;z-index:9999;padding:20px;';
  const escapedId = id;
  overlay.innerHTML = [
    '<div style="background:#0f172a;border:1px solid var(--card-border);border-radius:18px;padding:24px;width:100%;max-width:500px;box-shadow:0 24px 60px rgba(0,0,0,0.6);">',
      '<div style="font-size:16px;font-weight:700;margin-bottom:12px;color:#fff;">Публикация поста</div>',
      '<textarea id="publish-modal-text" style="width:100%;background:#090d16;border:1px solid var(--card-border);color:#f8fafc;padding:12px;border-radius:10px;font-size:13px;resize:vertical;min-height:120px;margin-bottom:14px;"></textarea>',
      '<div style="display:flex;gap:8px;flex-wrap:wrap;">',
        '<button id="pm-copy-btn" class="btn-action btn-primary">Скопировать текст</button>',
        '<button id="pm-tg-btn" class="btn-action" style="color:var(--success);border-color:rgba(16,185,129,0.3);">Отправить в Telegram</button>',
        '<button id="pm-close-btn" class="btn-action">Закрыть</button>',
      '</div>',
    '</div>'
  ].join('');
  document.body.appendChild(overlay);

  document.getElementById('publish-modal-text').value = text;

  document.getElementById('pm-copy-btn').onclick = function() {
    const ta = document.getElementById('publish-modal-text');
    ta.select();
    navigator.clipboard.writeText(ta.value);
    this.textContent = 'Скопировано!';
    setTimeout(() => { this.textContent = 'Скопировать текст'; }, 2000);
  };

  document.getElementById('pm-tg-btn').onclick = async function() {
    this.textContent = 'Отправляю...';
    try {
      const res = await fetch('/api/admin/threads/' + escapedId + '/publish', { method: 'POST' });
      const j = await res.json();
      this.textContent = j.ok ? 'Отправлено в Telegram!' : ('Ошибка: ' + (j.error || ''));
    } catch(e) {
      this.textContent = 'Ошибка сети';
    }
  };

  document.getElementById('pm-close-btn').onclick = function() {
    overlay.remove();
    loadThreadsQueue();
  };
};

document.getElementById('refresh-threads-btn').addEventListener('click', loadThreadsQueue);

// Initial load
checkAuthAndLoad();
setInterval(checkAuthAndLoad, 30000);

