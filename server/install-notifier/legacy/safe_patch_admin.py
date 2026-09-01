import os
import json
import re

worker_path = '/Users/sergei/Documents/pdd/server/install-notifier/worker.js'
with open(worker_path, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Locate ADMIN_HTML_HEAD and ADMIN_CLIENT_JS
pos_html_decl = code.find('const ADMIN_HTML_HEAD = ')
pos_js_decl = code.find('const ADMIN_CLIENT_JS = ')
pos_render_decl = code.find('function renderAdminPage()')

if pos_html_decl == -1 or pos_js_decl == -1 or pos_render_decl == -1:
    print('Error: Could not find variable declarations')
    exit(1)

# Extract raw json literals
html_json_literal = code[pos_html_decl + len('const ADMIN_HTML_HEAD = '):pos_js_decl].strip()
if html_json_literal.endswith(';'):
    html_json_literal = html_json_literal[:-1].strip()

js_json_literal = code[pos_js_decl + len('const ADMIN_CLIENT_JS = '):pos_render_decl].strip()
if js_json_literal.endswith(';'):
    js_json_literal = js_json_literal[:-1].strip()

html_str = json.loads(html_json_literal)
js_str = json.loads(js_json_literal)

print('Original HTML length:', len(html_str))
print('Original JS length:', len(js_str))

# --- HTML & CSS MODIFICATIONS ---

# 1. Remove Ads nav item
html_str = re.sub(r'<button class="nav-item"[^>]*data-feature="ads".*?</button>\s*', '', html_str, flags=re.DOTALL)

# 2. Remove ads-view div
pos_ads_view = html_str.find('<div id="ads-view"')
if pos_ads_view != -1:
    pos_users_view = html_str.find('<div id="users-view"', pos_ads_view)
    if pos_users_view != -1:
        # Find start of card or comment before ads-view
        start_cut = html_str.rfind('<!--', 0, pos_ads_view)
        if start_cut == -1:
            start_cut = pos_ads_view
        html_str = html_str[:start_cut] + html_str[pos_users_view:]
        print('Removed ads-view HTML block!')

# 3. Add ID to top period actions
html_str = html_str.replace('<div class="top-actions">', '<div class="top-actions" id="top-period-actions">')

# 4. Brand New CSS (App Colors, Flat Modern Surface, Zero Borders)
new_css = """
    :root {
      --bg: #F8F8FA;
      --sidebar-bg: #FFFFFF;
      --card-bg: #FFFFFF;
      --card-border: transparent;
      --text: #121212;
      --text-muted: #8E92A0;
      --text-light: #6B7280;
      --primary: #0574F8;
      --primary-hover: #0463D6;
      --primary-subtle: #E8F2FE;
      --success: #2BC280;
      --success-subtle: #E8F8F0;
      --danger: #ED4621;
      --danger-subtle: #FFECE8;
      --surface-gray: #EFF0F4;
      --surface-hover: #E5E7EB;
      --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: var(--font); -webkit-font-smoothing: antialiased; }
    body { background: var(--bg); color: var(--text); min-height: 100vh; overflow-x: hidden; display: flex; }

    /* Layout structure */
    .admin-wrapper { display: flex; width: 100vw; min-height: 100vh; }
    
    /* Sidebar */
    .sidebar {
      width: 250px;
      background: var(--sidebar-bg);
      border: none;
      display: flex;
      flex-direction: column;
      flex-shrink: 0;
      position: sticky;
      top: 0;
      height: 100vh;
      z-index: 50;
    }
    .sidebar-brand {
      padding: 22px 20px;
      display: flex;
      align-items: center;
      gap: 12px;
      border: none;
    }
    .sidebar-brand img { width: 34px; height: 34px; border-radius: 10px; }
    .sidebar-brand-title { font-size: 15px; font-weight: 800; color: var(--text); line-height: 1.2; letter-spacing: -0.3px; }
    .sidebar-brand-badge { display: inline-flex; align-items: center; gap: 4px; padding: 2px 6px; background: var(--success-subtle); color: var(--success); font-size: 10.5px; font-weight: 700; border-radius: 6px; }
    
    .sidebar-menu { padding: 12px; display: flex; flex-direction: column; gap: 4px; flex: 1; }
    .nav-item {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 11px 14px;
      border-radius: 12px;
      font-size: 13.5px;
      font-weight: 600;
      color: var(--text-muted);
      cursor: pointer;
      border: none;
      background: transparent;
      transition: all 0.15s ease;
      text-decoration: none;
    }
    .nav-item:hover { background: var(--surface-gray); color: var(--text); }
    .nav-item.active { background: var(--primary-subtle); color: var(--primary); font-weight: 700; }
    .nav-item svg { flex-shrink: 0; }

    .sidebar-footer { padding: 16px; border: none; }
    .app-selector {
      width: 100%;
      background: var(--surface-gray);
      border: none;
      color: var(--text);
      padding: 9px 12px;
      border-radius: 10px;
      font-size: 12.5px;
      font-weight: 600;
      outline: none;
      cursor: pointer;
    }

    /* Main Content */
    .content { flex: 1; padding: 28px 36px; max-width: 1440px; margin: 0 auto; width: 100%; min-width: 0; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; min-height: 42px; }
    .page-title { font-size: 22px; font-weight: 800; letter-spacing: -0.5px; color: var(--text); }
    
    .top-actions { display: flex; align-items: center; gap: 10px; }
    .segmented { display: flex; background: var(--surface-gray); padding: 4px; border-radius: 12px; border: none; gap: 2px; }
    .segmented button {
      border: none;
      background: transparent;
      padding: 6px 14px;
      border-radius: 9px;
      font-size: 12.5px;
      font-weight: 600;
      color: var(--text-muted);
      cursor: pointer;
      transition: all 0.15s;
    }
    .segmented button.active { background: var(--primary); color: #ffffff; font-weight: 700; }
    .btn-icon {
      width: 36px;
      height: 36px;
      border-radius: 10px;
      border: none;
      background: var(--surface-gray);
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--text-muted);
      cursor: pointer;
      transition: all 0.15s;
    }
    .btn-icon:hover { background: var(--surface-hover); color: var(--text); }
    .btn-action {
      padding: 7px 14px;
      border: none;
      background: var(--surface-gray);
      color: var(--text);
      border-radius: 10px;
      font-size: 12.5px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.15s;
    }
    .btn-action:hover { background: var(--surface-hover); color: var(--text); }
    .btn-primary { background: var(--primary); color: #ffffff; border: none; font-weight: 600; }
    .btn-primary:hover { background: var(--primary-hover); color: #ffffff; }
    .btn-danger { background: var(--danger-subtle); color: var(--danger); border: none; }
    .btn-danger:hover { background: var(--danger); color: #ffffff; }

    /* KPI Grid */
    .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-bottom: 22px; }
    .kpi-card { background: var(--card-bg); border: none; border-radius: 18px; padding: 20px 22px; }
    .kpi-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
    .kpi-label { font-size: 11.5px; font-weight: 700; text-transform: uppercase; color: var(--text-muted); letter-spacing: 0.5px; }
    .kpi-value { font-size: 28px; font-weight: 800; letter-spacing: -0.5px; color: var(--text); margin-bottom: 4px; }
    .kpi-footer { font-size: 12px; color: var(--text-muted); display: flex; align-items: center; gap: 6px; }
    .kpi-badge { display: inline-flex; padding: 3px 8px; border-radius: 6px; font-weight: 700; font-size: 11px; border: none; }
    .badge-blue { background: var(--primary-subtle); color: var(--primary); }
    .badge-green { background: var(--success-subtle); color: var(--success); }

    /* Chart Cards */
    .grid-2-1 { display: grid; grid-template-columns: 2fr 1fr; gap: 18px; margin-bottom: 22px; }
    .grid-1-1 { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin-bottom: 22px; }
    @media (max-width: 1000px) { .grid-2-1, .grid-1-1 { grid-template-columns: 1fr; } }

    .card { background: var(--card-bg); border: none; border-radius: 18px; padding: 22px 24px; margin-bottom: 22px; }
    .card-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 18px; }
    .card-title { font-size: 15px; font-weight: 700; color: var(--text); display: flex; align-items: center; gap: 8px; }
    .chart-box { position: relative; height: 260px; width: 100%; }

    /* Tables */
    table { width: 100%; border-collapse: separate; border-spacing: 0; text-align: left; font-size: 13px; }
    th {
      color: var(--text-muted);
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      padding: 12px 14px;
      background: var(--bg);
      border: none;
    }
    th:first-child { border-top-left-radius: 10px; border-bottom-left-radius: 10px; }
    th:last-child { border-top-right-radius: 10px; border-bottom-right-radius: 10px; }
    td { padding: 14px 14px; border: none; border-bottom: 1px solid #F4F5F8; color: var(--text); vertical-align: middle; }
    tr:last-child td { border-bottom: none; }
    tbody tr:hover { background: #FAFAFC; }

    .code-badge { font-family: ui-monospace, monospace; font-size: 11.5px; color: var(--primary); background: var(--primary-subtle); padding: 3px 8px; border-radius: 6px; border: none; font-weight: 600; }
    .tag-badge { display: inline-flex; padding: 3px 8px; border-radius: 6px; font-size: 11.5px; font-weight: 600; background: var(--surface-gray); color: var(--text-light); border: none; }

    /* Forms & Inputs */
    input, select, textarea {
      border: none;
      background: var(--surface-gray);
      color: var(--text);
      border-radius: 10px;
      outline: none;
      padding: 9px 12px;
      font-size: 13px;
      font-family: inherit;
    }
    input:focus, select:focus, textarea:focus { background: var(--primary-subtle); }
    .form-group { display: flex; flex-direction: column; gap: 6px; }
    .form-label { font-size: 11.5px; font-weight: 700; text-transform: uppercase; color: var(--text-muted); letter-spacing: 0.4px; }

    /* Login Modal */
    #login-overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, 0.4); backdrop-filter: blur(8px); display: flex; align-items: center; justify-content: center; z-index: 9999; padding: 20px; }
    .login-box { background: #ffffff; border: none; border-radius: 20px; padding: 36px 32px; width: 100%; max-width: 380px; text-align: center; }
    .login-box img { width: 56px; height: 56px; border-radius: 14px; margin-bottom: 14px; }
    .login-box h2 { font-size: 20px; font-weight: 800; margin-bottom: 6px; color: var(--text); }
    .login-box p { font-size: 13px; color: var(--text-muted); margin-bottom: 20px; }
    .login-box input { width: 100%; background: var(--surface-gray); border: none; color: var(--text); padding: 12px; border-radius: 12px; font-size: 15px; margin-bottom: 14px; text-align: center; letter-spacing: 2px; }
    .login-box input:focus { outline: none; background: var(--primary-subtle); }
    .login-box button { width: 100%; padding: 12px; font-size: 13.5px; font-weight: 700; border-radius: 12px; }
    .login-err-msg { color: var(--danger); font-size: 12px; margin-top: 10px; display: none; }
"""

html_str = re.sub(r'<style>.*?</style>', '<style>' + new_css + '  </style>', html_str, flags=re.DOTALL)

# --- CLIENT JS MODIFICATIONS ---

# 1. Remove Ads from VIEW_TITLES & views
js_str = js_str.replace("ads: 'Управление рекламой и промо-офферами',", "")
js_str = js_str.replace("const allViews = ['analytics-view', 'links-view', 'blog-view', 'threads-view', 'ads-view', 'users-view', 'ai-view'];", "const allViews = ['analytics-view', 'links-view', 'blog-view', 'threads-view', 'users-view', 'ai-view'];")

# 2. Update navigation listener to toggle period bar
new_nav_block = """
const VIEW_TITLES = {
  analytics: 'Аналитика продукта',
  links: 'Генератор ссылок и кампании',
  blog: 'Статьи блога',
  users: 'Пользователи и Премиум-доступ',
  ai: 'Управление искусственным интеллектом',
  threads: 'Threads автопостер'
};

document.querySelectorAll('.sidebar-menu .nav-item').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.sidebar-menu .nav-item').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFeature = btn.dataset.feature;
    
    document.getElementById('current-view-title').innerText = VIEW_TITLES[currentFeature] || 'Панель управления';

    // Show period selector ONLY on Analytics tab
    const topPeriodActions = document.getElementById('top-period-actions');
    if (topPeriodActions) {
      topPeriodActions.style.display = (currentFeature === 'analytics') ? 'flex' : 'none';
    }

    const allViews = ['analytics-view', 'links-view', 'blog-view', 'threads-view', 'users-view', 'ai-view'];
    allViews.forEach(vid => {
      const el = document.getElementById(vid);
      if (el) {
        el.style.display = (vid === currentFeature + '-view') ? 'block' : 'none';
      }
    });

    if (currentFeature === 'analytics') checkAuthAndLoad();
    else if (currentFeature === 'links') { checkAuthAndLoad(); updateGeneratedLink(); }
    else if (currentFeature === 'blog') loadBlogArticles();
    else if (currentFeature === 'threads') loadThreadsQueue();
    else if (currentFeature === 'users') loadUsersList();
    else if (currentFeature === 'ai') loadAiStats();
  });
});
"""

js_str = re.sub(r'const VIEW_TITLES = \{.*?\};.*?document\.querySelectorAll\(\'\.sidebar-menu \.nav-item\'\)\.forEach\(btn => \{.*?\}\);\s*;?', new_nav_block, js_str, flags=re.DOTALL)

# 3. Clean any old ads JS functions
js_str = re.sub(r'// ──+ Ads & Promo Management ──+.*?(?=// ──+ Users|\Z)', '', js_str, flags=re.DOTALL)
js_str = re.sub(r'let currentAdsConfig =.*?(?=// ──+ Users|\Z)', '', js_str, flags=re.DOTALL)
js_str = re.sub(r'window\.toggleYandexInput =.*?(?=// ──+ State|\Z)', '', js_str, flags=re.DOTALL)

# 4. Clean previous Users code if present and append fresh Users module
if "loadUsersList" in js_str:
    js_str = re.sub(r'// ──+ Users & Premium Management ──+.*', '', js_str, flags=re.DOTALL)

users_module_js = """

// ────────────────────── Users & Premium Management ──────────────────────
async function loadUsersList() {
  const tbody = document.getElementById('table-users');
  const countEl = document.getElementById('users-count');
  if (!tbody) return;
  tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted);padding:24px;">Загрузка пользователей...</td></tr>';

  try {
    const res = await fetch('/api/admin/users');
    if (res.status === 401 || res.status === 403) {
      checkAuthAndLoad();
      return;
    }
    const data = await res.json();
    const users = data.users || [];
    if (countEl) countEl.innerText = users.length;

    if (!users.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted);padding:32px;">Пока нет зарегистрированных пользователей в базе</td></tr>';
      return;
    }

    tbody.innerHTML = users.map(u => {
      const isPrem = u.isPremium === true;
      const isExp = u.premiumExpiresAt && new Date(u.premiumExpiresAt) < new Date();
      const isLifetime = isPrem && !u.premiumExpiresAt;
      const activePrem = isPrem && !isExp;

      // Solid brand badges with NO borders
      const statusBadge = activePrem
        ? (isLifetime 
            ? '<span style="display:inline-flex;align-items:center;padding:4px 10px;border-radius:8px;background:#2BC280;color:#ffffff;font-weight:700;font-size:11.5px;letter-spacing:0.3px;">PRO Навсегда</span>'
            : '<span style="display:inline-flex;align-items:center;padding:4px 10px;border-radius:8px;background:#2BC280;color:#ffffff;font-weight:700;font-size:11.5px;letter-spacing:0.3px;">PRO</span>')
        : (isPrem && isExp
            ? '<span style="display:inline-flex;align-items:center;padding:4px 10px;border-radius:8px;background:#FFECE8;color:#ED4621;font-weight:600;font-size:11.5px;">Истёк</span>'
            : '<span style="display:inline-flex;align-items:center;padding:4px 10px;border-radius:8px;background:#EFF0F4;color:#6B7280;font-weight:600;font-size:11.5px;">Бесплатный</span>');

      let expiresText = '-';
      if (isLifetime) {
        expiresText = '<span style="color:#2BC280;font-weight:700;">Бессрочно</span>';
      } else if (u.premiumExpiresAt) {
        expiresText = formatEventTime(u.premiumExpiresAt);
      }

      const provider = String(u.provider || 'guest').toLowerCase();
      const provBadge = provider.includes('google')
        ? '<span style="display:inline-flex;align-items:center;gap:6px;font-weight:600;font-size:12.5px;">' + BRAND_SVGS.google + ' Google</span>'
        : provider.includes('apple')
        ? '<span style="display:inline-flex;align-items:center;gap:6px;font-weight:600;font-size:12.5px;">' + BRAND_SVGS.appstore + ' Apple ID</span>'
        : provider.includes('yandex')
        ? '<span style="display:inline-flex;align-items:center;gap:6px;font-weight:600;font-size:12.5px;">' + BRAND_SVGS.yandex + ' Яндекс</span>'
        : '<span style="color:var(--text-muted);font-size:12.5px;">Гость</span>';

      const lastSeen = formatEventTime(u.lastSeenAt || u.createdAt);
      const avatarHtml = u.avatarUrl
        ? '<img src="' + u.avatarUrl + '" style="width:32px;height:32px;border-radius:50%;object-fit:cover;" onerror="this.style.display=\\'none\\'" />'
        : '<div style="width:32px;height:32px;border-radius:50%;background:#EFF0F4;color:#475569;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;">' + (u.name ? u.name.charAt(0).toUpperCase() : 'U') + '</div>';

      const escapedName = (u.name || 'Пользователь').replace(/'/g, "\\\\'");
      const grantBtn = activePrem
        ? '<button class="btn-action" style="padding:5px 10px;font-size:11.5px;color:var(--primary);background:var(--primary-subtle);border-radius:8px;" onclick="showGrantModal(\\'' + u.id + '\\', \\'' + escapedName + '\\')">Продлить PRO</button>'
        : '<button class="btn-action btn-primary" style="padding:5px 10px;font-size:11.5px;border-radius:8px;" onclick="showGrantModal(\\'' + u.id + '\\', \\'' + escapedName + '\\')">Выдать PRO</button>';

      const revokeBtn = activePrem
        ? '<button class="btn-action" style="padding:5px 10px;font-size:11.5px;color:var(--danger);background:var(--danger-subtle);border-radius:8px;margin-left:6px;" onclick="revokeUserPremium(\\'' + u.id + '\\')">Отозвать</button>'
        : '';

      const deleteBtn = '<button class="btn-action btn-danger" style="padding:5px 8px;font-size:11.5px;border-radius:8px;margin-left:6px;display:inline-flex;align-items:center;justify-content:center;" title="Удалить аккаунт" onclick="deleteUserAccount(\\'' + u.id + '\\', \\'' + escapedName + '\\')"><svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" style="flex-shrink:0;"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg></button>';

      return '<tr>'
        + '<td>'
          + '<div style="display:flex;align-items:center;gap:10px;">'
            + avatarHtml
            + '<div>'
              + '<div style="font-weight:700;font-size:13px;color:var(--text);">' + (u.name || 'Пользователь') + '</div>'
              + '<div style="font-size:11.5px;color:var(--text-muted);font-family:monospace;">' + (u.email || u.id) + '</div>'
            + '</div>'
          + '</div>'
        + '</td>'
        + '<td>' + provBadge + '</td>'
        + '<td>' + statusBadge + '</td>'
        + '<td>' + expiresText + '</td>'
        + '<td style="color:var(--text-muted);font-size:12px;">' + lastSeen + '</td>'
        + '<td><div style="display:flex;align-items:center;">' + grantBtn + revokeBtn + deleteBtn + '</div></td>'
        + '</tr>';
    }).join('');
  } catch (err) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--danger);padding:24px;">Ошибка загрузки: ' + err.message + '</td></tr>';
  }
}

window.showGrantModal = function(userId, userName) {
  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,0.4);backdrop-filter:blur(8px);display:flex;align-items:center;justify-content:center;z-index:9999;padding:20px;';
  overlay.innerHTML = [
    '<div style="background:#ffffff;border:none;border-radius:18px;padding:26px;width:100%;max-width:440px;box-shadow:0 20px 40px rgba(0,0,0,0.12);">',
      '<div style="font-size:17px;font-weight:800;margin-bottom:6px;color:var(--text);letter-spacing:-0.3px;">Выдать Premium доступ</div>',
      '<div style="font-size:13px;color:var(--text-muted);margin-bottom:18px;">Пользователь: <b>' + userName + '</b></div>',
      '<div style="margin-bottom:20px;">',
        '<label style="display:block;font-size:11.5px;font-weight:700;text-transform:uppercase;margin-bottom:8px;color:var(--text-muted);letter-spacing:0.4px;">Длительность подписки:</label>',
        '<select id="grant-duration" style="width:100%;background:var(--surface-gray);border:none;border-radius:12px;padding:11px 14px;font-size:13.5px;color:var(--text);outline:none;font-weight:600;">',
          '<option value="7">1 неделя (7 дней)</option>',
          '<option value="30" selected>1 месяц (30 дней)</option>',
          '<option value="90">3 месяца (90 дней)</option>',
          '<option value="365">1 год (365 дней)</option>',
          '<option value="lifetime">Бессрочно (Навсегда)</option>',
        '</select>',
      '</div>',
      '<div style="display:flex;gap:10px;justify-content:flex-end;">',
        '<button id="grant-cancel-btn" class="btn-action" style="padding:9px 16px;border-radius:10px;">Отмена</button>',
        '<button id="grant-confirm-btn" class="btn-action btn-primary" style="padding:9px 18px;border-radius:10px;font-weight:700;">Активировать PRO</button>',
      '</div>',
    '</div>'
  ].join('');
  document.body.appendChild(overlay);

  document.getElementById('grant-cancel-btn').onclick = () => overlay.remove();
  document.getElementById('grant-confirm-btn').onclick = async function() {
    const val = document.getElementById('grant-duration').value;
    const isLifetime = val === 'lifetime';
    const days = isLifetime ? null : parseInt(val, 10);
    this.innerText = 'Сохранение...';
    this.disabled = true;
    try {
      const res = await fetch('/api/admin/users/grant-premium', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ userId, days, isLifetime })
      });
      const data = await res.json();
      if (data.ok) {
        overlay.remove();
        loadUsersList();
      } else {
        alert('Ошибка: ' + (data.error || 'Не удалось активировать'));
        this.innerText = 'Активировать PRO';
        this.disabled = false;
      }
    } catch(e) {
      alert('Ошибка сети: ' + e);
      this.innerText = 'Активировать PRO';
      this.disabled = false;
    }
  };
};

window.revokeUserPremium = async function(userId) {
  if (!confirm('Вы точно хотите отозвать Premium-доступ у этого пользователя?')) return;
  try {
    const res = await fetch('/api/admin/users/revoke-premium', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userId })
    });
    const data = await res.json();
    if (data.ok) {
      loadUsersList();
    } else {
      alert('Ошибка: ' + (data.error || 'Не удалось отозвать'));
    }
  } catch(e) {
    alert('Ошибка сети: ' + e);
  }
};

window.deleteUserAccount = async function(userId, userName) {
  if (!confirm('Вы уверены, что хотите навсегда удалить аккаунт пользователя "' + userName + '" из базы?')) return;
  try {
    const res = await fetch('/api/admin/users/delete', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userId })
    });
    const data = await res.json();
    if (data.ok) {
      loadUsersList();
    } else {
      alert('Ошибка: ' + (data.error || 'Не удалось удалить аккаунт'));
    }
  } catch(e) {
    alert('Ошибка сети: ' + e);
  }
};

const refreshUsersBtn = document.getElementById('refresh-users-btn');
if (refreshUsersBtn) {
  refreshUsersBtn.addEventListener('click', loadUsersList);
}
"""

js_str = js_str + users_module_js

# --- ASSEMBLE WORKER CODE ---
code = (
    code[:pos_html_decl]
    + 'const ADMIN_HTML_HEAD = ' + json.dumps(html_str) + ';\n'
    + 'const ADMIN_CLIENT_JS = ' + json.dumps(js_str) + ';\n'
    + code[pos_render_decl:]
)

# --- BACKEND LOGIC: DELETE USER & GET ALL USERS ---
delete_backend_route = """    if (url.pathname === '/api/admin/users/delete' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { userId } = body || {};
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      let email = null;
      try {
        const raw = await env.INSTALLS.get('user:' + userId);
        if (raw) {
          const u = JSON.parse(raw);
          if (u.email) email = u.email;
        }
      } catch (_) {}

      await env.INSTALLS.delete('user:' + userId);
      if (email) {
        await env.INSTALLS.delete('user_email:' + email.toLowerCase().trim());
      }

      try {
        const rawList = await env.INSTALLS.get('users_list');
        if (rawList) {
          let userIds = JSON.parse(rawList);
          if (Array.isArray(userIds)) {
            userIds = userIds.filter(id => id !== userId);
            await env.INSTALLS.put('users_list', JSON.stringify(userIds));
          }
        }
      } catch (_) {}

      return jsonResponse({ ok: true, deleted: userId });
    }
"""

if "url.pathname === '/api/admin/users/delete'" not in code:
    pos_grant = code.find("if (url.pathname === '/api/admin/users/grant-premium'")
    if pos_grant != -1:
        code = code[:pos_grant] + delete_backend_route + '\n' + code[pos_grant:]

new_get_all_users = """async function getAllUsers(env) {
  if (!env.INSTALLS) return [];
  const idSet = new Set();
  try {
    const rawList = await env.INSTALLS.get('users_list');
    if (rawList) {
      const list = JSON.parse(rawList);
      if (Array.isArray(list)) list.forEach(id => idSet.add(id));
    }
  } catch (_) {}

  // Fallback: scan all user keys from KV
  try {
    const listRes = await env.INSTALLS.list({ prefix: 'user:' });
    if (listRes && listRes.keys) {
      listRes.keys.forEach(k => {
        const uId = k.name.replace(/^user:/, '');
        if (uId && !uId.startsWith('email:')) idSet.add(uId);
      });
    }
  } catch (_) {}

  const users = [];
  for (const id of idSet) {
    try {
      const raw = await env.INSTALLS.get('user:' + id);
      if (raw) {
        const u = JSON.parse(raw);
        users.push(u);
      }
    } catch (_) {}
  }

  // Sort by lastSeenAt desc
  users.sort((a, b) => {
    const ta = new Date(a.lastSeenAt || a.createdAt || 0).getTime();
    const tb = new Date(b.lastSeenAt || b.createdAt || 0).getTime();
    return tb - ta;
  });

  return users;
}"""

code = re.sub(r'async function getAllUsers\(env\)\s*\{.*?return users;\s*\}', new_get_all_users, code, flags=re.DOTALL)

with open(worker_path, 'w', encoding='utf-8') as f:
    f.write(code)

print('Successfully patched worker.js!')
