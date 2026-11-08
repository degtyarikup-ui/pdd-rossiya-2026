import os
import json
import subprocess
import re

# Read clean base worker
_this_dir = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_this_dir, 'worker.js'), 'r', encoding='utf-8') as f:
    code = f.read()

# --------------------------------------------------------------------------
# 1. HTML & CSS OVERHAUL (Zero borders, App Colors, Removed Ads, Period toggle)
# --------------------------------------------------------------------------
pos_html_decl = code.find('const ADMIN_HTML_HEAD = ')
pos_js_decl = code.find('const ADMIN_CLIENT_JS = ')
pos_render_decl = code.find('function renderAdminPage()')

html_json_literal = code[pos_html_decl + len('const ADMIN_HTML_HEAD = '):pos_js_decl].strip()
if html_json_literal.endswith(';'):
    html_json_literal = html_json_literal[:-1].strip()

html_str = json.loads(html_json_literal)

# Remove Ads nav button
html_str = re.sub(r'<button class="nav-item"[^>]*data-feature="ads".*?</button>\s*', '', html_str, flags=re.DOTALL)

# Remove ads-view div if present
pos_ads_view = html_str.find('<div id="ads-view"')
if pos_ads_view != -1:
    pos_users_view = html_str.find('<div id="users-view"', pos_ads_view)
    if pos_users_view != -1:
        start_cut = html_str.rfind('<!--', 0, pos_ads_view)
        if start_cut == -1:
            start_cut = pos_ads_view
        html_str = html_str[:start_cut] + html_str[pos_users_view:]

# Top period actions container ID
html_str = html_str.replace('<div class="top-actions">', '<div class="top-actions" id="top-period-actions">')

# New CSS with zero borders and exact app colors
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

# --------------------------------------------------------------------------
# 2. CLIENT JS (Tested without syntax errors)
# --------------------------------------------------------------------------
with open('/tmp/test_client_clean.js', 'r', encoding='utf-8') as f:
    js_code = f.read()

# --------------------------------------------------------------------------
# 3. BACKEND ROUTES & SECURITY HARDENING
# --------------------------------------------------------------------------
user_backend_helpers = """
// ────────────────────── User Profile & Premium Security ──────────────────────
async function saveUserProfile(env, user) {
  if (!env.INSTALLS || !user || !user.id) return user;
  const kvKey = 'user:' + user.id;
  let existing = null;
  try {
    const raw = await env.INSTALLS.get(kvKey);
    if (raw) existing = JSON.parse(raw);
  } catch (_) {}

  // SECURITY: Subscriptions are strictly server-authoritative!
  // Client can NEVER grant themselves premium by sending isPremium: true in /api/user/sync.
  // The server only respects existing database status or admin grants.
  let isPremium = existing ? (existing.isPremium || false) : false;
  let premiumExpiresAt = existing ? (existing.premiumExpiresAt || null) : null;
  let premiumSource = existing ? (existing.premiumSource || null) : null;

  // Check expiration
  if (isPremium && premiumExpiresAt && new Date(premiumExpiresAt) < new Date()) {
    isPremium = false;
  }

  const merged = {
    id: user.id,
    name: user.name || (existing ? existing.name : 'Пользователь'),
    email: user.email || (existing ? existing.email : null),
    avatarUrl: user.avatarUrl !== undefined ? user.avatarUrl : (existing ? existing.avatarUrl : null),
    provider: user.provider || (existing ? existing.provider : 'guest'),
    country: user.country || (existing ? existing.country : 'RU'),
    app: user.app || (existing ? existing.app : 'ru'),
    createdAt: (existing && existing.createdAt) ? existing.createdAt : (user.createdAt || new Date().toISOString()),
    lastSeenAt: new Date().toISOString(),
    isPremium,
    premiumExpiresAt,
    premiumSource,
  };

  await env.INSTALLS.put(kvKey, JSON.stringify(merged));

  if (merged.email) {
    await env.INSTALLS.put('user_email:' + merged.email.toLowerCase().trim(), merged.id);
  }

  let userIds = [];
  try {
    const rawList = await env.INSTALLS.get('users_list');
    if (rawList) userIds = JSON.parse(rawList);
  } catch (_) {}
  if (!userIds.includes(merged.id)) {
    userIds.unshift(merged.id);
    if (userIds.length > 5000) userIds = userIds.slice(0, 5000);
    await env.INSTALLS.put('users_list', JSON.stringify(userIds));
  }

  return merged;
}

async function getAllUsers(env) {
  if (!env.INSTALLS) return [];
  const idSet = new Set();
  try {
    const rawList = await env.INSTALLS.get('users_list');
    if (rawList) {
      const list = JSON.parse(rawList);
      if (Array.isArray(list)) list.forEach(id => idSet.add(id));
    }
  } catch (_) {}

  // Fallback: list all user keys from KV
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
}
"""

user_api_routes = """
    // ────────────────────── User Profile & Sync API ──────────────────────
    if (url.pathname === '/api/user/sync' && request.method === 'POST') {
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
      if (!body || !body.id) {
        return jsonResponse({ error: 'missing user id' }, 400);
      }
      const updatedUser = await saveUserProfile(env, body);
      return jsonResponse({
        ok: true,
        user: updatedUser,
        isPremium: updatedUser ? updatedUser.isPremium : false,
        premiumExpiresAt: updatedUser ? updatedUser.premiumExpiresAt : null,
        premiumSource: updatedUser ? updatedUser.premiumSource : null
      });
    }

    if (url.pathname === '/api/user/status' && request.method === 'GET') {
      const userId = url.searchParams.get('id');
      const email = url.searchParams.get('email');
      let targetId = userId;
      if (!targetId && email && env.INSTALLS) {
        targetId = await env.INSTALLS.get('user_email:' + email.toLowerCase().trim());
      }
      if (!targetId) {
        return jsonResponse({ ok: false, error: 'user not found', isPremium: false }, 404);
      }
      let raw = null;
      if (env.INSTALLS) raw = await env.INSTALLS.get('user:' + targetId);
      if (!raw) return jsonResponse({ ok: false, error: 'user not found', isPremium: false }, 404);
      try {
        const user = JSON.parse(raw);
        return jsonResponse({
          ok: true,
          user,
          isPremium: user.isPremium || false,
          premiumExpiresAt: user.premiumExpiresAt || null,
          premiumSource: user.premiumSource || null
        });
      } catch (_) {
        return jsonResponse({ ok: false, error: 'parse error' }, 500);
      }
    }

    // ────────────────────── Admin Users API ──────────────────────
    if (url.pathname === '/api/admin/users' && request.method === 'GET') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      const users = await getAllUsers(env);
      return jsonResponse({ ok: true, users });
    }

    if (url.pathname === '/api/admin/users/grant-premium' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { userId, days, isLifetime } = body || {};
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      const raw = await env.INSTALLS.get('user:' + userId);
      if (!raw) return jsonResponse({ error: 'user not found' }, 404);
      const user = JSON.parse(raw);

      user.isPremium = true;
      user.premiumSource = 'admin_grant';
      if (isLifetime) {
        user.premiumExpiresAt = null;
      } else {
        const d = days ? parseInt(days, 10) : 30;
        const now = (user.premiumExpiresAt && new Date(user.premiumExpiresAt) > new Date())
          ? new Date(user.premiumExpiresAt)
          : new Date();
        now.setDate(now.getDate() + d);
        user.premiumExpiresAt = now.toISOString();
      }

      await env.INSTALLS.put('user:' + userId, JSON.stringify(user));
      return jsonResponse({ ok: true, user });
    }

    if (url.pathname === '/api/admin/users/revoke-premium' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { userId } = body || {};
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      const raw = await env.INSTALLS.get('user:' + userId);
      if (!raw) return jsonResponse({ error: 'user not found' }, 404);
      const user = JSON.parse(raw);

      user.isPremium = false;
      user.premiumSource = null;
      user.premiumExpiresAt = null;
      await env.INSTALLS.put('user:' + userId, JSON.stringify(user));
      return jsonResponse({ ok: true, user });
    }

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

# Reconstruct whole worker file
final_code = (
    code[:pos_html_decl]
    + 'const ADMIN_HTML_HEAD = ' + json.dumps(html_str) + ';\n\n'
    + 'const ADMIN_CLIENT_JS = ' + json.dumps(js_code) + ';\n\n'
    + user_backend_helpers + '\n\n'
    + code[pos_render_decl:]
)

# Insert API routes
pos_track = final_code.find("if (url.pathname === '/api/track'")
if pos_track != -1:
    final_code = final_code[:pos_track] + user_api_routes + '\n' + final_code[pos_track:]
else:
    pos_sched = final_code.find("async scheduled(")
    final_code = final_code[:pos_sched] + user_api_routes + '\n' + final_code[pos_sched:]

target_file = '/Users/sergei/Documents/pdd/server/install-notifier/worker.js'
with open(target_file, 'w', encoding='utf-8') as f:
    f.write(final_code)

print('Assembled worker.js!')
