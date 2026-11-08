import re
import json

with open('worker.js', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update getAllUsers to scan prefix user: as fallback and sort by lastSeenAt
old_get_all_users = """async function getAllUsers(env) {
  if (!env.INSTALLS) return [];
  let userIds = [];
  try {
    const rawList = await env.INSTALLS.get('users_list');
    if (rawList) userIds = JSON.parse(rawList);
  } catch (_) {}

  const users = [];
  for (const id of userIds) {
    try {
      const raw = await env.INSTALLS.get('user:' + id);
      if (raw) users.push(JSON.parse(raw));
    } catch (_) {}
  }
  return users;
}"""

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
}"""

if old_get_all_users in content:
    content = content.replace(old_get_all_users, new_get_all_users)
    print('Updated getAllUsers in backend!')
else:
    print('Warning: old_get_all_users exact string not found')

# 2. Add Users JS logic to ADMIN_CLIENT_JS
users_client_code = r"""

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

      const statusBadge = activePrem
        ? (isLifetime 
            ? '<span class="tag-badge" style="background:#ecfdf5;color:#059669;font-weight:700;border-color:#a7f3d0;">PRO Навсегда</span>'
            : '<span class="tag-badge" style="background:#ecfdf5;color:#059669;font-weight:700;border-color:#a7f3d0;">PRO Активен</span>')
        : (isPrem && isExp
            ? '<span class="tag-badge" style="background:#fef2f2;color:#dc2626;border-color:#fecaca;">Истёк</span>'
            : '<span class="tag-badge" style="background:#f1f5f9;color:#64748b;">Бесплатный</span>');

      let expiresText = '-';
      if (isLifetime) {
        expiresText = '<span style="color:#059669;font-weight:600;">Бессрочно</span>';
      } else if (u.premiumExpiresAt) {
        expiresText = formatEventTime(u.premiumExpiresAt);
      }

      const provider = String(u.provider || 'guest').toLowerCase();
      const provBadge = provider.includes('google')
        ? '<span style="display:inline-flex;align-items:center;gap:5px;font-weight:600;">' + BRAND_SVGS.google + ' Google</span>'
        : provider.includes('apple')
        ? '<span style="display:inline-flex;align-items:center;gap:5px;font-weight:600;">' + BRAND_SVGS.appstore + ' Apple ID</span>'
        : provider.includes('yandex')
        ? '<span style="display:inline-flex;align-items:center;gap:5px;font-weight:600;">' + BRAND_SVGS.yandex + ' Яндекс</span>'
        : '<span style="color:var(--text-muted);">Гость</span>';

      const lastSeen = formatEventTime(u.lastSeenAt || u.createdAt);
      const avatarHtml = u.avatarUrl
        ? '<img src="' + u.avatarUrl + '" style="width:30px;height:30px;border-radius:50%;object-fit:cover;border:1px solid var(--card-border);" onerror="this.style.display=\'none\'" />'
        : '<div style="width:30px;height:30px;border-radius:50%;background:#e2e8f0;color:#475569;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;">' + (u.name ? u.name.charAt(0).toUpperCase() : 'U') + '</div>';

      const escapedName = (u.name || 'Пользователь').replace(/'/g, "\\'");
      const grantBtn = activePrem
        ? '<button class="btn-action" style="padding:4px 9px;font-size:11.5px;color:var(--primary);" onclick="showGrantModal(\'' + u.id + '\', \'' + escapedName + '\')">Продлить PRO</button>'
        : '<button class="btn-action btn-primary" style="padding:4px 9px;font-size:11.5px;" onclick="showGrantModal(\'' + u.id + '\', \'' + escapedName + '\')">Выдать PRO</button>';

      const revokeBtn = activePrem
        ? '<button class="btn-action" style="padding:4px 9px;font-size:11.5px;color:var(--danger);border-color:#fecaca;margin-left:6px;" onclick="revokeUserPremium(\'' + u.id + '\')">Отозвать</button>'
        : '';

      return '<tr>'
        + '<td>'
          + '<div style="display:flex;align-items:center;gap:10px;">'
            + avatarHtml
            + '<div>'
              + '<div style="font-weight:600;font-size:13px;color:var(--text);">' + (u.name || 'Пользователь') + '</div>'
              + '<div style="font-size:11.5px;color:var(--text-muted);font-family:monospace;">' + (u.email || u.id) + '</div>'
            + '</div>'
          + '</div>'
        + '</td>'
        + '<td>' + provBadge + '</td>'
        + '<td>' + statusBadge + '</td>'
        + '<td>' + expiresText + '</td>'
        + '<td style="color:var(--text-muted);font-size:12px;">' + lastSeen + '</td>'
        + '<td><div style="display:flex;align-items:center;">' + grantBtn + revokeBtn + '</div></td>'
        + '</tr>';
    }).join('');
  } catch (err) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--danger);padding:24px;">Ошибка загрузки: ' + err.message + '</td></tr>';
  }
}

window.showGrantModal = function(userId, userName) {
  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,0.5);backdrop-filter:blur(6px);display:flex;align-items:center;justify-content:center;z-index:9999;padding:20px;';
  overlay.innerHTML = [
    '<div style="background:#ffffff;border:1px solid var(--card-border);border-radius:14px;padding:24px;width:100%;max-width:440px;box-shadow:0 20px 40px rgba(0,0,0,0.15);">',
      '<div style="font-size:16px;font-weight:700;margin-bottom:6px;color:var(--text);">Выдать Premium доступ</div>',
      '<div style="font-size:12.5px;color:var(--text-muted);margin-bottom:16px;">Пользователь: <b>' + userName + '</b></div>',
      '<div style="margin-bottom:16px;">',
        '<label style="display:block;font-size:12px;font-weight:600;margin-bottom:6px;color:var(--text);">Длительность подписки:</label>',
        '<select id="grant-duration" style="width:100%;background:#f8fafc;border:1px solid var(--card-border);border-radius:8px;padding:9px 12px;font-size:13px;color:var(--text);outline:none;">',
          '<option value="7">1 неделя (7 дней)</option>',
          '<option value="30" selected>1 месяц (30 дней)</option>',
          '<option value="90">3 месяца (90 дней)</option>',
          '<option value="365">1 год (365 дней)</option>',
          '<option value="lifetime">Бессрочно (Навсегда)</option>',
        '</select>',
      '</div>',
      '<div style="display:flex;gap:8px;justify-content:flex-end;">',
        '<button id="grant-cancel-btn" class="btn-action">Отмена</button>',
        '<button id="grant-confirm-btn" class="btn-action btn-primary">Активировать PRO</button>',
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

const refreshUsersBtn = document.getElementById('refresh-users-btn');
if (refreshUsersBtn) {
  refreshUsersBtn.addEventListener('click', loadUsersList);
}
"""

# Find where ADMIN_CLIENT_JS ends and append users_client_code inside the string
marker = 'function renderAdminPage() {'
pos = content.find(marker)
if pos != -1:
    # Look right before pos for the closing of ADMIN_CLIENT_JS = "...";
    # We can insert users_client_code right before the closing quote
    last_quote = content.rfind('";', 0, pos)
    if last_quote != -1:
        # Convert users_client_code to escaped JS string representation
        escaped_js = json.dumps(users_client_code)[1:-1]
        content = content[:last_quote] + escaped_js + content[last_quote:]
        print('Appended Users JS module to ADMIN_CLIENT_JS!')
    else:
        print('Error: closing quote of ADMIN_CLIENT_JS not found')
else:
    print('Error: renderAdminPage not found')

with open('worker.js', 'w', encoding='utf-8') as f:
    f.write(content)

print('Done writing worker.js!')
