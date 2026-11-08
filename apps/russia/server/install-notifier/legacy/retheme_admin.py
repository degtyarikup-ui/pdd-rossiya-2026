import os
import json
import re

path = '/Users/sergei/Documents/pdd/server/install-notifier/worker.js'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update CSS style block in ADMIN_HTML_HEAD
old_style_match = re.search(r'<style>.*?</style>', content, re.DOTALL)
if old_style_match:
    new_style = """<style>
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
      --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, -apple-system, sans-serif;
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

    /* Switch Toggle */
    .toggle-switch { position: relative; display: inline-block; width: 44px; height: 24px; flex-shrink: 0; }
    .toggle-switch input { opacity: 0; width: 0; height: 0; }
    .toggle-slider {
      position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0;
      background-color: #cbd5e1; transition: .25s ease; border-radius: 24px;
    }
    .toggle-slider:before {
      position: absolute; content: ""; height: 18px; width: 18px; left: 3px; bottom: 3px;
      background-color: white; transition: .25s ease; border-radius: 50%;
    }
    .toggle-switch input:checked + .toggle-slider { background-color: var(--success); }
    .toggle-switch input:checked + .toggle-slider:before { transform: translateX(20px); }

    /* Store Grid */
    .store-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }
    .store-card {
      background: var(--card-bg);
      border: none;
      border-radius: 16px;
      padding: 18px;
      display: flex;
      flex-direction: column;
      gap: 14px;
      background: var(--surface-gray);
    }
    .store-card-head { display: flex; align-items: center; justify-content: space-between; }
    .store-brand-badge { display: inline-flex; align-items: center; gap: 8px; font-size: 14px; font-weight: 700; color: var(--text); }

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
  </style>"""
    content = content[:old_style_match.start()] + new_style + content[old_style_match.end():]
    print('Updated CSS styles in ADMIN_HTML_HEAD!')

# 2. Update Header actions with ID top-period-actions
old_top_actions = '<div class="top-actions">'
new_top_actions = '<div class="top-actions" id="top-period-actions">'
if old_top_actions in content:
    content = content.replace(old_top_actions, new_top_actions, 1)
    print('Updated top-period-actions container!')

# 3. Add DELETE user route in worker
delete_route_code = """
    if (url.pathname === '/api/admin/users/delete' && request.method === 'POST') {
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

if "url.pathname === '/api/admin/users/delete'" not in content:
    pos_revoke = content.find("if (url.pathname === '/api/admin/users/revoke-premium'")
    if pos_revoke != -1:
        content = content[:pos_revoke] + delete_route_code + '\n' + content[pos_revoke:]
        print('Added delete user backend route!')
    else:
        print('Warning: pos_revoke not found')

# 4. Replace loadUsersList and show/hide top-period-actions in ADMIN_CLIENT_JS
# Update tab switching to hide top-period-actions
old_nav_logic = "if (currentFeature === 'analytics') checkAuthAndLoad();"
new_nav_logic = """const topPeriodActions = document.getElementById('top-period-actions');
    if (topPeriodActions) {
      topPeriodActions.style.display = (currentFeature === 'analytics') ? 'flex' : 'none';
    }

    if (currentFeature === 'analytics') checkAuthAndLoad();"""

if old_nav_logic in content and "const topPeriodActions =" not in content:
    content = content.replace(old_nav_logic, new_nav_logic, 1)
    print('Updated tab navigation to toggle period buttons visibility!')

# 5. Overhaul loadUsersList with exact colors, no borders, solid PRO badge, and delete button
users_js_pattern = re.search(r'// ──+ Users & Premium Management ──+.*?(?=const refreshUsersBtn|\Z)', content, re.DOTALL)
new_users_js = """// ────────────────────── Users & Premium Management ──────────────────────
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
"""

if users_js_pattern:
    escaped_new_users_js = json.dumps(new_users_js)[1:-1]
    # We replace the user management section inside ADMIN_CLIENT_JS string
    # Let's find its exact location
    pos_marker = content.find('Users & Premium Management')
    if pos_marker != -1:
        # find start of comment before it
        start_u = content.rfind('// ──', 0, pos_marker)
        end_u = content.find('const refreshUsersBtn', start_u)
        if start_u != -1 and end_u != -1:
            content = content[:start_u] + escaped_new_users_js + '\n' + content[end_u:]
            print('Replaced Users JS module with updated design!')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Successfully saved worker.js!')
