#!/usr/bin/env python3
import sys

with open('server/install-notifier/worker.js', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix VIEW_TITLES in ADMIN_CLIENT_JS
if "const VIEW_TITLES = {" in content:
    idx_vt = content.find("const VIEW_TITLES = {")
    end_vt = content.find("};", idx_vt) + 2
    new_vt = r"""const VIEW_TITLES = {
  analytics: 'Аналитика продукта',
  links: 'Генератор ссылок и кампании',
  blog: 'Статьи блога',
  ads: 'Управление рекламой и промо-офферами',
  users: 'Пользователи и Премиум-доступ',
  ai: 'Управление искусственным интеллектом',
  threads: 'Threads автопостер'
};"""
    escaped_vt = new_vt.replace('\n', r'\n')
    content = content[:idx_vt] + escaped_vt + content[end_vt:]
    print("VIEW_TITLES replaced!")

# 2. Fix nav-item click listener
old_nav_block_start = "document.querySelectorAll('.sidebar-menu .nav-item').forEach(btn => {"
idx_nav = content.find(old_nav_block_start)
if idx_nav != -1:
    end_nav = content.find("});\\n});", idx_nav)
    if end_nav == -1:
        end_nav = content.find("});\n});", idx_nav)
    if end_nav != -1:
        end_nav += 7
        new_nav_block = r"""document.querySelectorAll('.sidebar-menu .nav-item').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.sidebar-menu .nav-item').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentFeature = btn.dataset.feature;
    
    document.getElementById('current-view-title').innerText = VIEW_TITLES[currentFeature] || 'Панель управления';

    const allViews = ['analytics-view', 'links-view', 'blog-view', 'threads-view', 'ads-view', 'users-view', 'ai-view'];
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
    else if (currentFeature === 'ads') loadAdsConfig();
    else if (currentFeature === 'users') loadUsersList();
    else if (currentFeature === 'ai') loadAiStats();
  });
});"""
        escaped_nav = new_nav_block.replace('\n', r'\n').replace('"', r'\"')
        content = content[:idx_nav] + escaped_nav + content[end_nav:]
        print("Nav block replaced!")

# 3. Add AI and Users JS modules before the end of ADMIN_CLIENT_JS
ai_and_users_js = r"""
// ────────────────────── Users Management Module ──────────────────────
async function loadUsersList() {
  const container = document.getElementById('table-users');
  const countEl = document.getElementById('users-count');
  if (!container) return;
  container.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted);padding:20px;">Загрузка...</td></tr>';
  try {
    const res = await fetch('/api/admin/users');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    const data = await res.json();
    const users = data.users || [];
    if (countEl) countEl.innerText = users.length;
    if (!users.length) {
      container.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-muted);padding:20px;">Пользователей пока нет</td></tr>';
      return;
    }
    container.innerHTML = users.map(u => {
      const isPrem = u.isPremium;
      const premBadge = isPrem
        ? '<span class="kpi-badge badge-green">PREMIUM</span>'
        : '<span class="tag-badge">FREE</span>';
      const expText = u.premiumExpiresAt
        ? formatEventTime(u.premiumExpiresAt)
        : (isPrem ? 'Бессрочно' : '—');
      const lastSeen = formatEventTime(u.lastSeenAt);
      const btnAction = isPrem
        ? '<button class="btn-action" style="color:var(--danger);border-color:#fecaca;padding:4px 8px;font-size:11.5px;" onclick="revokeUserPremium(\'' + u.id + '\')">Забрать Премиум</button>'
        : '<button class="btn-action btn-primary" style="padding:4px 8px;font-size:11.5px;" onclick="grantUserPremium(\'' + u.id + '\')">+ Выдать Премиум</button>';
      return '<tr>'
        + '<td><div style="font-weight:600;color:var(--text);">' + (u.name || 'Без имени') + '</div><div style="font-size:11px;color:var(--text-muted);font-family:monospace;">' + u.id + (u.email ? ' · ' + u.email : '') + '</div></td>'
        + '<td><span class="tag-badge">' + (u.provider || 'guest') + '</span></td>'
        + '<td>' + premBadge + '</td>'
        + '<td>' + expText + '</td>'
        + '<td>' + lastSeen + '</td>'
        + '<td>' + btnAction + '</td>'
        + '</tr>';
    }).join('');
  } catch (err) {
    container.innerHTML = '<tr><td colspan="6" style="color:var(--danger);text-align:center;padding:20px;">Ошибка: ' + err.message + '</td></tr>';
  }
}

window.grantUserPremium = async function(userId) {
  const days = prompt('На сколько дней выдать Премиум? (введите 0 или оставьте пустым для бессрочного)', '30');
  if (days === null) return;
  const isLifetime = (days.trim() === '0' || days.trim() === '');
  try {
    const r = await fetch('/api/admin/users/grant-premium', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userId, days: isLifetime ? 0 : parseInt(days, 10), isLifetime })
    });
    if (r.ok) {
      alert('Премиум успешно выдан!');
      loadUsersList();
    } else {
      alert('Ошибка: ' + r.status);
    }
  } catch (e) {
    alert('Ошибка сети: ' + e);
  }
};

window.revokeUserPremium = async function(userId) {
  if (!confirm('Забрать Премиум у пользователя?')) return;
  try {
    const r = await fetch('/api/admin/users/revoke-premium', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userId })
    });
    if (r.ok) {
      alert('Премиум отозван!');
      loadUsersList();
    } else {
      alert('Ошибка: ' + r.status);
    }
  } catch (e) {
    alert('Ошибка сети: ' + e);
  }
};

const refreshUsersBtn = document.getElementById('refresh-users-btn');
if (refreshUsersBtn) refreshUsersBtn.addEventListener('click', loadUsersList);


// ────────────────────── AI Management Module ──────────────────────
async function loadAiStats() {
  try {
    const res = await fetch('/api/admin/ai/stats');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    if (!res.ok) return;
    const data = await res.json();
    const s = data.stats;

    const elTotal = document.getElementById('ai-m-total');
    if (elTotal) elTotal.innerText = (s.totalRequests || 0).toLocaleString();

    const elToday = document.getElementById('ai-m-today');
    if (elToday) elToday.innerText = (s.todayRequests || 0).toLocaleString();

    const elCostUsd = document.getElementById('ai-m-cost-usd');
    if (elCostUsd) elCostUsd.innerText = '$' + (s.costUsd || 0).toFixed(5);

    const elCostRub = document.getElementById('ai-m-cost-rub');
    if (elCostRub) elCostRub.innerText = '~' + (s.costRub || 0) + ' ₽';

    const totalK = ((s.totalTokens || 0) / 1000).toFixed(1);
    const elTokensK = document.getElementById('ai-m-tokens-k');
    if (elTokensK) elTokensK.innerText = totalK + 'k';

    const elTokensTotal = document.getElementById('ai-m-tokens-total');
    if (elTokensTotal) elTokensTotal.innerText = (s.totalTokens || 0).toLocaleString();

    const elTokensPrompt = document.getElementById('ai-m-tokens-prompt');
    if (elTokensPrompt) elTokensPrompt.innerText = (s.promptTokens || 0).toLocaleString();

    const elTokensCand = document.getElementById('ai-m-tokens-cand');
    if (elTokensCand) elTokensCand.innerText = (s.candidateTokens || 0).toLocaleString();

    const elModel = document.getElementById('ai-m-model');
    if (elModel) elModel.innerText = s.activeModel;

    const select = document.getElementById('ai-model-select');
    if (select) select.value = s.activeModel;
  } catch (err) {
    console.error('loadAiStats error:', err);
  }
}

const saveAiModelBtn = document.getElementById('save-ai-model-btn');
if (saveAiModelBtn) {
  saveAiModelBtn.addEventListener('click', async () => {
    const select = document.getElementById('ai-model-select');
    if (!select) return;
    const model = select.value;
    saveAiModelBtn.innerText = 'Сохраняю...';
    try {
      const r = await fetch('/api/admin/ai/config', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ model })
      });
      if (r.ok) {
        saveAiModelBtn.innerText = 'Успешно сохранено!';
        setTimeout(() => { saveAiModelBtn.innerText = 'Применить модель'; }, 1800);
        loadAiStats();
      } else {
        alert('Ошибка при сохранении модели: ' + r.status);
        saveAiModelBtn.innerText = 'Применить модель';
      }
    } catch (e) {
      alert('Ошибка сети: ' + e);
      saveAiModelBtn.innerText = 'Применить модель';
    }
  });
}

const aiTestSendBtn = document.getElementById('ai-test-send-btn');
if (aiTestSendBtn) {
  aiTestSendBtn.addEventListener('click', async () => {
    const input = document.getElementById('ai-test-prompt');
    if (!input) return;
    const prompt = input.value.trim();
    if (!prompt) return;
    const box = document.getElementById('ai-test-result-box');
    aiTestSendBtn.innerText = 'Генерация...';
    if (box) box.innerText = 'ИИ генерирует ответ...';
    try {
      const r = await fetch('/api/admin/ai/test', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ prompt })
      });
      const d = await r.json();
      if (d.ok) {
        if (box) box.innerText = '[' + d.model + ']:\n\n' + d.reply;
      } else {
        if (box) box.innerText = 'Ошибка: ' + (d.error || 'не удалось получить ответ');
      }
    } catch (e) {
      if (box) box.innerText = 'Ошибка сети: ' + e;
    } finally {
      aiTestSendBtn.innerText = 'Отправить';
    }
  });
}
"""

escaped_ai_users_js = ai_and_users_js.replace('\n', r'\n').replace('"', r'\"')
if "loadAiStats" not in content:
    idx_close_quote = content.rfind('";\n\nasync function handleAdminHtml')
    if idx_close_quote != -1:
        content = content[:idx_close_quote] + escaped_ai_users_js + content[idx_close_quote:]
        print("AI and Users JS modules appended into ADMIN_CLIENT_JS!")
    else:
        print("Could not find closing quote of ADMIN_CLIENT_JS")

with open('server/install-notifier/worker.js', 'w', encoding='utf-8') as f:
    f.write(content)

print("worker.js fixed successfully!")
