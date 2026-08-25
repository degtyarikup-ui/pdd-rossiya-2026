
// ────────────────────── State ──────────────────────
let currentFeature = 'analytics';
let currentDays = 7;
let currentApp = 'all'; // 'all' | 'ru' | 'rs'
let cachedBlogArticles = [];

let chartInstalls = null;
let chartTargets = null;
let chartWebFunnel = null;
let chartSources = null;

// Brand SVG Icons
const BRAND_SVGS = {
  gplay: '<svg viewBox="0 0 512 512" width="14" height="14" style="flex-shrink:0;"><path fill="#4285F4" d="M82.2 28.1C73.8 37 69 49.9 69 65.8v380.4c0 15.9 4.8 28.8 13.2 37.7l1.9 1.8 214.3-214.3v-5L84.1 26.3l-1.9 1.8z"/><path fill="#FFBA00" d="M369.3 328.7l-70.9-70.9v-5l70.9-70.9 2 1.1 84.1 47.8c24 13.6 24 35.9 0 49.5l-84.1 47.8-2 1.1z"/><path fill="#FF3A44" d="M298.4 257.8L82.2 474c7.9 8.4 21 9.4 35.7 1.1l253.4-144-72.9-73.3z"/><path fill="#00E676" d="M298.4 252.8l72.9-73.3L117.9 35.5C103.2 27.2 90.1 28.2 82.2 36.6L298.4 252.8z"/></svg>',
  rustore: '<svg viewBox="0 0 100 100" width="14" height="14" style="flex-shrink:0;"><path d="M57.8 61.6C55.1 61 53.2 58.5 53.2 55.8V23.2c0-3.1 3-5.4 6.1-4.7L78.6 23.4c2.7.7 4.6 3.1 4.6 5.8v32.6c0 3.1-3 5.4-6.1 4.7L57.8 61.6zM21.4 76.6C18.7 76 16.8 73.5 16.8 70.8V38.2c0-3.1 3-5.4 6.1-4.7L42.2 38.4c2.7.7 4.6 3.1 4.6 5.8v32.6c0 3.1-3 5.4-6.1 4.7L21.4 76.6z" fill="#0077ff"/></svg>',
  appstore: '<svg viewBox="0 0 24 24" width="14" height="14" fill="#0284c7" style="flex-shrink:0;"><path d="M18.7 19.5c-.8 1.2-1.7 2.4-3 2.4-1.4 0-1.8-.8-3.4-.8-1.6 0-2.1.8-3.4.8-1.3 0-2.3-1.3-3.1-2.5C4.2 17 3 13.6 3 10.4c0-5.1 3.3-7.8 6.5-7.8 1.7 0 3.3 1.2 4.3 1.2 1 0 2.9-1.5 4.9-1.3.8 0 3.2.3 4.7 2.5-3.9 2.3-3.3 7.5.7 9.1-.8 2-1.9 4-3.4 5.4zM15.9 2.6c.8-1 1.3-2.3 1.2-3.6-1.1.1-2.5.7-3.3 1.7-.7.8-1.4 2.2-1.2 3.5 1.3.1 2.5-.6 3.3-1.6z"/></svg>',
  web: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="#8b5cf6" stroke-width="2" style="flex-shrink:0;"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1 4-10z"/></svg>',
  youtube: '<svg viewBox="0 0 24 24" width="14" height="14" fill="#ef4444" style="flex-shrink:0;"><path d="M23.5 6.2a3 3 0 0 0-2.1-2.1C19.5 3.5 12 3.5 12 3.5s-7.5 0-9.4.5A3 3 0 0 0 .5 6.2 31.8 31.8 0 0 0 0 12a31.8 31.8 0 0 0 .5 5.8 3 3 0 0 0 2.1 2.1c1.9.5 9.4.5 9.4.5s7.5 0 9.4-.5a3 3 0 0 0 2.1-2.1A31.8 31.8 0 0 0 24 12a31.8 31.8 0 0 0-.5-5.8zM9.5 15.6V8.4l6.3 3.6-6.3 3.6z"/></svg>',
  instagram: '<svg viewBox="0 0 24 24" width="14" height="14" fill="#ec4899" style="flex-shrink:0;"><path d="M12 2.2c3.2 0 3.6 0 4.9.1 3.3.1 4.8 1.7 4.9 4.9.1 1.3.1 1.7.1 4.8s0 3.6-.1 4.9c-.1 3.2-1.7 4.8-4.9 4.9-1.3.1-1.7.1-4.9.1s-3.6 0-4.9-.1c-3.2-.1-4.8-1.7-4.9-4.9-.1-1.3-.1-1.7-.1-4.9s0-3.6.1-4.9c.1-3.2 1.7-4.8 4.9-4.9 1.3-.1 1.7-.1 4.9-.1zm0-2.2C8.7 0 8.3 0 7 .1 2.7.3.3 2.7.1 7 0 8.3 0 8.7 0 12s0 3.7.1 5c.2 4.3 2.6 6.7 6.9 6.9 1.3.1 1.7.1 5 .1s3.7 0 5-.1c4.3-.2 6.7-2.6 6.9-6.9.1-1.3.1-1.7.1-5s0-3.7-.1-5C23.8 2.7 21.4.3 17.1.1 15.8 0 15.4 0 12 0zm0 5.8a6.2 6.2 0 1 0 0 12.4 6.2 6.2 0 0 0 0-12.4zm0 10.2a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.4-11.8a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8z"/></svg>',
  tiktok: '<svg viewBox="0 0 24 24" width="14" height="14" style="flex-shrink:0;"><path fill="#06b6d4" d="M12.5.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/><path fill="#ef4444" d="M13.4.62c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/><path fill="#0f172a" d="M12.95.32c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>',
  telegram: '<svg viewBox="0 0 24 24" width="14" height="14" fill="#229ed9" style="flex-shrink:0;"><path d="M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.6 0 12 0zm5.9 8.2l-2 9.3c-.1.7-.5.8-1.1.5l-3-2.2-1.4 1.4c-.2.2-.3.3-.6.3l.2-3.1 5.6-5c.2-.2-.1-.3-.4-.1l-6.9 4.3-3-.9c-.6-.2-.7-.6.1-1l11.6-4.5c.5-.2 1 .1.8.9z"/></svg>',
  vk: '<svg viewBox="0 0 24 24" width="14" height="14" fill="#0077ff" style="flex-shrink:0;"><path d="M15.7 0H8.3C3 0 0 3 0 8.3v7.4C0 21 3 24 8.3 24h7.4c5.3 0 8.3-3 8.3-8.3V8.3C24 3 21 0 15.7 0zm3.7 17h-1.6c-.6 0-.8-.5-1.9-1.6-1-1-1.5-1.2-1.7-1.2-.4 0-.5.1-.5.6v1.5c0 .4-.1.7-1.2.7-1.8 0-3.7-1.1-5.1-3.1C5.3 12.5 4.7 10.3 4.7 9.8c0-.2.1-.5.6-.5h1.6c.5 0 .6.2.8.7.9 2.5 2.3 4.7 2.9 4.7.2 0 .3-.1.3-.7V11.4c-.1-1.2-.7-1.3-.7-1.7 0-.2.2-.4.4-.4h2.6c.4 0 .5.2.5.6v3.5c0 .4.2.5.3.5.2 0 .4-.1.8-.6 1.3-1.5 2.2-3.7 2.2-3.7.1-.3.3-.5.8-.5h1.6c.5 0 .6.3.5.6-.2 1-2.3 4-2.4 4.1-.3.4-.3.6 0 1 .3.3.1.3 1.6 1.8 1.1 1.1 2 2.1 2.2 2.5.2.4-.1.6-.6.6z"/></svg>',
  yandex: '<svg viewBox="0 0 24 24" width="14" height="14" fill="#f59e0b" style="flex-shrink:0;"><path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm3.627 18.707h-2.52L9.27 13.067l-1.36 1.48v4.16H5.733V5.293h2.177v7.507l4.987-7.507h2.64l-4.52 6.547 4.61 6.867z"/></svg>',
  direct: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="#64748b" stroke-width="2" style="flex-shrink:0;"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1 4-10z"/></svg>',
  other: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="#64748b" stroke-width="2" style="flex-shrink:0;"><circle cx="12" cy="12" r="10"/><path d="M12 8v8M8 12h8"/></svg>'
};

// Brand configuration maps
const STORE_CONFIG = {
  appstore: { name: 'App Store', color: '#0284c7', icon: BRAND_SVGS.appstore },
  gplay: { name: 'Google Play', color: '#10b981', icon: BRAND_SVGS.gplay },
  rustore: { name: 'RuStore', color: '#0077ff', icon: BRAND_SVGS.rustore },
  web: { name: 'Веб-версия', color: '#8b5cf6', icon: BRAND_SVGS.web }
};

const SOURCE_CONFIG = {
  youtube: { name: 'YouTube', color: '#ef4444', icon: BRAND_SVGS.youtube },
  instagram: { name: 'Instagram', color: '#ec4899', icon: BRAND_SVGS.instagram },
  tiktok: { name: 'TikTok', color: '#06b6d4', icon: BRAND_SVGS.tiktok },
  telegram: { name: 'Telegram', color: '#229ed9', icon: BRAND_SVGS.telegram },
  vk: { name: 'ВКонтакте', color: '#0077ff', icon: BRAND_SVGS.vk },
  yandex: { name: 'Яндекс', color: '#f59e0b', icon: BRAND_SVGS.yandex },
  direct: { name: 'Прямой переход', color: '#64748b', icon: BRAND_SVGS.direct },
  organic_gplay: { name: 'Google Play', color: '#10b981', icon: BRAND_SVGS.gplay },
  organic_rustore: { name: 'RuStore', color: '#0077ff', icon: BRAND_SVGS.rustore },
  organic_appstore: { name: 'App Store', color: '#0284c7', icon: BRAND_SVGS.appstore },
  other: { name: 'Прочее', color: '#94a3b8', icon: BRAND_SVGS.other }
};

function normalizeStore(raw) {
  const s = String(raw || '').toLowerCase().trim();
  if (s.includes('rustore') || s.includes('vk.store')) return 'rustore';
  if (s.includes('gplay') || s.includes('google') || s.includes('vending') || s.includes('android')) return 'gplay';
  if (s.includes('appstore') || s.includes('apple') || s.includes('ios')) return 'appstore';
  if (s.includes('web')) return 'web';
  return null;
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
  if (s.includes('galaxy') || s.includes('samsung')) return 'organic_gplay';
  if (s === 'direct' || !s) return 'direct';
  return 'other';
}

function formatEventTime(isoString) {
  if (!isoString) return '-';
  try {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;
    return new Intl.DateTimeFormat('ru-RU', {
      day: '2-digit',
      month: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      timeZone: 'Europe/Moscow'
    }).format(d).replace(',', '');
  } catch (_) {
    return isoString;
  }
}

function getCountryFlag(code) {
  if (!code || typeof code !== 'string') return '🌐';
  const c = code.trim().toUpperCase();
  if (c === 'RU') return '🇷🇺';
  if (c === 'RS') return '🇷🇸';
  if (c === 'BY') return '🇧🇾';
  if (c === 'KZ') return '🇰🇿';
  if (c === 'UA') return '🇺🇦';
  if (c === 'US') return '🇺🇸';
  if (c.length === 2) {
    const codePoints = c.split('').map(char => 127397 + char.charCodeAt(0));
    return String.fromCodePoint(...codePoints);
  }
  return '🌐';
}

function formatCountryBadge(code) {
  const c = String(code || 'RU').toUpperCase();
  const flag = getCountryFlag(c);
  return '<span class="tag-badge" style="display:inline-flex;align-items:center;gap:5px;font-size:11.5px;font-weight:600;"><span style="font-size:13px;line-height:1;">' + flag + '</span> ' + c + '</span>';
}

function formatBrandBadge(srcRaw) {
  const key = normalizeSource(srcRaw);
  const conf = SOURCE_CONFIG[key] || { name: srcRaw || 'Прямой', color: '#64748b', icon: BRAND_SVGS.other };
  return '<span style="display:inline-flex;align-items:center;gap:7px;font-weight:600;white-space:nowrap;color:var(--text);">'
    + conf.icon
    + '<span>' + conf.name + '</span>'
    + '</span>';
}

// ────────────────────── Sidebar Navigation ──────────────────────
const VIEW_TITLES = {
  analytics: 'Аналитика продукта',
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
    document.getElementById('links-view').style.display = currentFeature === 'links' ? 'block' : 'none';
    document.getElementById('blog-view').style.display = currentFeature === 'blog' ? 'block' : 'none';
    document.getElementById('threads-view').style.display = currentFeature === 'threads' ? 'block' : 'none';

    if (currentFeature === 'analytics') checkAuthAndLoad();
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
  
  // Real Landing CR = Clicks / Views
  const views = data.totals.views || 0;
  const clicks = data.totals.clicks || 0;
  const landingCr = views > 0 ? ((clicks / views) * 100).toFixed(1) : '0.0';
  document.getElementById('m-ctr').innerText = 'CTR: ' + landingCr + '%';
  document.getElementById('m-cr').innerText = landingCr + '%';

  const labels = data.timeline.map(t => {
    const p = t.date.split('-');
    return p[2] + '.' + p[1];
  });

  // 2. Chart: App Installs Growth (Line with soft emerald gradient, NO LEGEND)
  const ctxInstalls = document.getElementById('chart-installs').getContext('2d');
  const gradInstalls = ctxInstalls.createLinearGradient(0, 0, 0, 240);
  gradInstalls.addColorStop(0, 'rgba(16, 185, 129, 0.18)');
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
        pointRadius: 3.5,
        pointHoverRadius: 6,
        pointBackgroundColor: '#10b981'
      }]
    },
    options: getChartOptions(false)
  });

  // 3. Chart: Platforms & Stores (Filtered & Mapped to Official Brand Colors)
  const storeAgg = {};
  (data.targets || []).forEach(t => {
    const key = normalizeStore(t.name);
    if (key) {
      storeAgg[key] = (storeAgg[key] || 0) + (t.clicks || 0);
    }
  });

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
        borderWidth: 2,
        borderColor: '#ffffff',
        hoverOffset: 4
      }]
    },
    options: getDoughnutOptions()
  });

  // 4. Chart: Web Marketing Funnel (Views vs Clicks)
  const ctxWeb = document.getElementById('chart-web-funnel').getContext('2d');
  const gradViews = ctxWeb.createLinearGradient(0, 0, 0, 240);
  gradViews.addColorStop(0, 'rgba(2, 132, 199, 0.15)');
  gradViews.addColorStop(1, 'rgba(2, 132, 199, 0.0)');

  if (chartWebFunnel) chartWebFunnel.destroy();
  chartWebFunnel = new Chart(ctxWeb, {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Визиты лендинга',
          data: data.timeline.map(t => t.views),
          borderColor: '#0284c7',
          backgroundColor: gradViews,
          borderWidth: 2,
          tension: 0.3,
          fill: true,
          pointRadius: 3,
          pointBackgroundColor: '#0284c7'
        },
        {
          label: 'Клики в сторы',
          data: data.timeline.map(t => t.clicks),
          borderColor: '#ef4444',
          backgroundColor: 'transparent',
          borderWidth: 2,
          tension: 0.3,
          pointRadius: 3,
          pointBackgroundColor: '#ef4444'
        }
      ]
    },
    options: getChartOptions(true)
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
        borderWidth: 2,
        borderColor: '#ffffff',
        hoverOffset: 4
      }]
    },
    options: getDoughnutOptions()
  });

  // 6. Table: Channels / Sources (Aggregated with Brand Logos)
  const tbodySources = document.getElementById('table-sources');
  const sourceGroups = {};
  (data.sources || []).forEach(s => {
    const key = normalizeSource(s.name);
    if (!sourceGroups[key]) {
      sourceGroups[key] = { name: s.name, views: 0, clicks: 0, installs: 0 };
    }
    sourceGroups[key].views += s.views || 0;
    sourceGroups[key].clicks += s.clicks || 0;
    sourceGroups[key].installs += s.installs || 0;
  });

  const sourceGroupList = Object.entries(sourceGroups).map(([k, d]) => {
    const ctr = d.views > 0 ? ((d.clicks / d.views) * 100).toFixed(1) : '0.0';
    return { key: k, ...d, ctr };
  });
  sourceGroupList.sort((a, b) => b.clicks - a.clicks || b.views - a.views || b.installs - a.installs);

  if (!sourceGroupList.length) {
    tbodySources.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);">Нет данных за период</td></tr>';
  } else {
    tbodySources.innerHTML = sourceGroupList.map(s => {
      return '<tr>'
        + '<td>' + formatBrandBadge(s.key) + '</td>'
        + '<td>' + s.views + '</td>'
        + '<td>' + s.clicks + '</td>'
        + '<td><span class="tag-badge">' + s.ctr + '%</span></td>'
        + '<td><span style="color:#059669;font-weight:600;">' + s.installs + '</span></td>'
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
        + '<td>' + formatBrandBadge(c.source) + '</td>'
        + '<td>' + c.views + '</td>'
        + '<td>' + c.clicks + '</td>'
        + '<td><span class="tag-badge">' + c.ctr + '%</span></td>'
        + '</tr>';
    }).join('');
  }

  // 8. Table: Live Feed (Clean Timestamps, Brand Logos & Flags)
  const tbodyLive = document.getElementById('table-live');
  const liveEvents = data.recent || data.recentEvents || [];
  if (!liveEvents.length) {
    tbodyLive.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);">Ожидание событий...</td></tr>';
  } else {
    tbodyLive.innerHTML = liveEvents.slice(0, 20).map(ev => {
      const typeBadge = ev.type === 'install' 
        ? '<span class="kpi-badge badge-green">Установка</span>' 
        : ev.type === 'click' 
        ? '<span class="kpi-badge badge-blue">Клик в стор</span>' 
        : '<span class="tag-badge">Визит</span>';
      
      const formattedTime = formatEventTime(ev.time || ev.createdAt);
      const brandBadge = formatBrandBadge(ev.source);
      const countryBadge = formatCountryBadge(ev.country || 'RU');

      return '<tr>'
        + '<td style="color:var(--text-muted);font-family:monospace;font-size:11.5px;white-space:nowrap;">' + formattedTime + '</td>'
        + '<td>' + typeBadge + '</td>'
        + '<td>' + brandBadge + '</td>'
        + '<td>' + (ev.campaign ? '<span class="code-badge">' + ev.campaign + '</span>' : '-') + '</td>'
        + '<td>' + countryBadge + '</td>'
        + '</tr>';
    }).join('');
  }
}

function getChartOptions(showLegend = true) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: {
        display: showLegend,
        labels: { color: '#475569', boxWidth: 10, usePointStyle: true, font: { size: 11.5 } }
      },
      tooltip: {
        backgroundColor: '#0f172a',
        titleColor: '#ffffff',
        bodyColor: '#cbd5e1',
        borderColor: '#334155',
        borderWidth: 1,
        padding: 10,
        cornerRadius: 8
      }
    },
    scales: {
      x: { grid: { color: 'rgba(0,0,0,0.04)' }, ticks: { color: '#64748b', font: { size: 11 } } },
      y: { grid: { color: 'rgba(0,0,0,0.04)' }, ticks: { color: '#64748b', font: { size: 11 } }, beginAtZero: true }
    }
  };
}

function getDoughnutOptions() {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { position: 'bottom', labels: { color: '#475569', boxWidth: 10, usePointStyle: true, font: { size: 11 } } }
    },
    cutout: '72%'
  };
}

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
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:30px;background:#f8fafc;border-radius:8px;border:1px dashed var(--card-border);">Все статьи уже опубликованы</div>';
      return;
    }
    container.innerHTML = cachedBlogArticles.map(function(a, idx) {
      var coverUrl = a.cover ? 'https://pdd-drive.ru/blog/' + a.slug + '/' + a.cover + '?v=20260823_v3' : 'https://pdd-drive.ru/assets/og-image.png';
      var isFirst = idx === 0;
      var isLast = idx === cachedBlogArticles.length - 1;
      var upDisabled = isFirst ? ' disabled style="opacity:0.3;cursor:not-allowed;"' : '';
      var downDisabled = isLast ? ' disabled style="opacity:0.3;cursor:not-allowed;"' : '';
      return '<div style="background:#ffffff;border:1px solid var(--card-border);border-radius:10px;padding:14px 16px;display:flex;gap:16px;align-items:center;flex-wrap:wrap;box-shadow:0 1px 2px rgba(0,0,0,0.03);">'
        + '<div style="width:140px;height:78px;border-radius:6px;overflow:hidden;background:#f1f5f9;flex-shrink:0;border:1px solid var(--card-border);">'
        + '<img src="' + coverUrl + '" alt="" style="width:100%;height:100%;object-fit:cover;" onerror="this.onerror=null;this.src=\'https://pdd-drive.ru/assets/og-image.png\';" />'
        + '</div>'
        + '<div style="flex:1;min-width:240px;">'
        + '<div style="font-size:14.5px;font-weight:700;color:var(--text);margin-bottom:4px;">' + a.title + '</div>'
        + '<div style="font-size:11.5px;color:var(--text-muted);margin-bottom:8px;">' + (a.description || '') + '</div>'
        + '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">'
        + '<input type="date" id="date-' + a.slug + '" value="' + a.datePublished + '" data-slug="' + a.slug + '" onchange="updateArticleDate(this.dataset.slug)" style="background:#f8fafc;border:1px solid var(--card-border);border-radius:6px;color:var(--primary);padding:3px 6px;font-size:12px;font-weight:600;outline:none;" />'
        + '<span style="font-size:11px;color:var(--text-muted);">' + a.slug + ' · ' + (a.readingMinutes || 5) + ' мин.</span>'
        + '</div>'
        + '</div>'
        + '<div style="display:flex;gap:6px;align-items:center;flex-shrink:0;">'
        + '<button class="btn-icon" style="width:30px;height:30px;" title="Вверх" onclick="swapArticle(' + idx + ', ' + (idx-1) + ')"' + upDisabled + '>▲</button>'
        + '<button class="btn-icon" style="width:30px;height:30px;" title="Вниз" onclick="swapArticle(' + idx + ', ' + (idx+1) + ')"' + downDisabled + '>▼</button>'
        + '<button class="btn-action" style="padding:4px 8px;font-size:11.5px;color:var(--danger);border-color:#fecaca;" data-slug="' + a.slug + '" onclick="deleteBlogArticle(this.dataset.slug)">Удалить</button>'
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
      container.innerHTML = '<div style="color:var(--text-muted);text-align:center;padding:30px;background:#f8fafc;border-radius:8px;border:1px dashed var(--card-border);">Очередь постов пуста</div>';
      return;
    }
    container.innerHTML = queue.map(p => {
      return '<div style="background:#ffffff;border:1px solid var(--card-border);border-radius:10px;padding:16px;box-shadow:0 1px 2px rgba(0,0,0,0.03);">'
        + '<div style="display:flex;justify-content:space-between;margin-bottom:8px;font-size:11.5px;color:var(--text-muted);">'
        + '<span>Дата: ' + (p.scheduledDate || 'Без даты') + '</span>'
        + '<span class="tag-badge">' + (p.status || 'pending') + '</span>'
        + '</div>'
        + '<textarea id="text-' + p.id + '" style="width:100%;min-height:70px;background:#f8fafc;border:1px solid var(--card-border);border-radius:6px;color:var(--text);padding:8px 10px;font-family:inherit;font-size:12.5px;margin-bottom:8px;">' + (p.text || '') + '</textarea>'
        + '<input type="text" id="img-' + p.id + '" value="' + (p.imageUrl || '') + '" placeholder="Image URL" style="width:100%;background:#f8fafc;border:1px solid var(--card-border);border-radius:6px;color:var(--text);padding:6px 10px;font-size:11.5px;margin-bottom:10px;" />'
        + '<div style="display:flex;gap:8px;">'
        + '<button class="btn-action" data-id="' + p.id + '" onclick="savePost(this.dataset.id)">Сохранить</button>'
        + '<button class="btn-action" style="color:var(--danger);border-color:#fecaca;" data-id="' + p.id + '" onclick="deletePost(this.dataset.id)">Удалить</button>'
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
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,0.5);backdrop-filter:blur(6px);display:flex;align-items:center;justify-content:center;z-index:9999;padding:20px;';
  const escapedId = id;
  overlay.innerHTML = [
    '<div style="background:#ffffff;border:1px solid var(--card-border);border-radius:14px;padding:24px;width:100%;max-width:500px;box-shadow:0 20px 40px rgba(0,0,0,0.15);">',
      '<div style="font-size:16px;font-weight:700;margin-bottom:12px;color:var(--text);">Публикация поста</div>',
      '<textarea id="publish-modal-text" style="width:100%;background:#f8fafc;border:1px solid var(--card-border);color:var(--text);padding:12px;border-radius:8px;font-size:13px;resize:vertical;min-height:120px;margin-bottom:14px;"></textarea>',
      '<div style="display:flex;gap:8px;flex-wrap:wrap;">',
        '<button id="pm-copy-btn" class="btn-action btn-primary">Скопировать текст</button>',
        '<button id="pm-tg-btn" class="btn-action" style="color:#059669;border-color:#a7f3d0;">Отправить в Telegram</button>',
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
