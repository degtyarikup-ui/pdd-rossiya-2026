import os
import json
import re
import subprocess

# 1. Read the CURRENT worker.js (canonical source of truth, NOT the stale /tmp backup)
# This prevents accidentally reverting the Telegram slot-report logic or other live changes.
_this_dir = os.path.dirname(os.path.abspath(__file__))
_worker_path = os.path.join(_this_dir, 'worker.js')
with open(_worker_path, 'r', encoding='utf-8') as f:
    base_code = f.read()

# Locate HTML and JS
p_html_start = base_code.find('const ADMIN_HTML_HEAD = ')
p_js_start = base_code.find('const ADMIN_CLIENT_JS = ')
p_render_start = base_code.find('function renderAdminPage()')

raw_html_json = base_code[p_html_start + len('const ADMIN_HTML_HEAD = '):p_js_start].strip().rstrip(';')
html = json.loads(raw_html_json)

# --- 2. HTML STRUCTURE ---

# Remove Ads nav button
html = re.sub(r'<button class="nav-item"[^>]*data-feature="ads".*?</button>\s*', '', html, flags=re.DOTALL)

# Ensure Users and AI are in the Sidebar menu
sidebar_users_ai_btns = """      <button class="nav-item" data-feature="users">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
        <span>Пользователи</span>
      </button>
      <button class="nav-item" data-feature="ai">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="10" rx="2"/><circle cx="12" cy="5" r="2"/><path d="M12 7v4"/><line x1="8" y1="16" x2="8.01" y2="16"/><line x1="16" y1="16" x2="16.01" y2="16"/></svg>
        <span>Управление ИИ</span>
      </button>
"""
if 'data-feature="users"' not in html:
    threads_btn_target = '<button class="nav-item" data-feature="threads">'
    html = html.replace(threads_btn_target, sidebar_users_ai_btns + threads_btn_target)

# Remove Ads view if present
pos_ads_view = html.find('<div id="ads-view"')
if pos_ads_view != -1:
    pos_next_view = html.find('<div id="threads-view"', pos_ads_view)
    if pos_next_view != -1:
        start_cut = html.rfind('<!--', 0, pos_ads_view)
        if start_cut == -1: start_cut = pos_ads_view
        html = html[:start_cut] + html[pos_next_view:]

# Ensure users-view and ai-view are present in HTML
users_ai_views_html = """
    <!-- 4. USERS MANAGEMENT VIEW -->
    <div id="users-view" style="display:none;">
      <div class="card" style="margin-bottom: 22px;">
        <div class="card-head">
          <div class="card-title">
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
            <span>Пользователи и Премиум-доступ (<span id="users-count">0</span>)</span>
          </div>
          <button class="btn-action" id="refresh-users-btn">Обновить</button>
        </div>
        <div style="overflow-x:auto;">
          <table>
            <thead>
              <tr>
                <th>Пользователь</th>
                <th>Провайдер</th>
                <th>Статус</th>
                <th>Действует до</th>
                <th>Последний вход</th>
                <th>Версия</th>
                <th>Действия</th>
              </tr>
            </thead>
            <tbody id="table-users">
              <tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:24px;">Загрузка...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- 5. AI MANAGEMENT VIEW -->
    <div id="ai-view" style="display:none;">
      <!-- AI KPI Cards -->
      <div class="kpi-grid">
        <div class="kpi-card">
          <div class="kpi-head">
            <span class="kpi-label">Всего запросов к ИИ</span>
          </div>
          <div class="kpi-value" id="ai-m-total">0</div>
          <div class="kpi-footer">
            <span>Сегодня: <b id="ai-m-today" style="color:var(--text);font-weight:700;">0</b></span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-head">
            <span class="kpi-label">Расходы на ИИ</span>
            <span class="kpi-badge badge-green" id="ai-m-cost-rub">~0.00 ₽</span>
          </div>
          <div class="kpi-value" id="ai-m-cost-usd">$0.00000</div>
          <div class="kpi-footer">
            <span>По тарифам Google Gemini</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-head">
            <span class="kpi-label">Использовано токенов</span>
            <span class="kpi-badge badge-blue" id="ai-m-tokens-total">0</span>
          </div>
          <div class="kpi-value" id="ai-m-tokens-k">0k</div>
          <div class="kpi-footer">
            <span>Вход: <b id="ai-m-tokens-prompt">0</b> · Выход: <b id="ai-m-tokens-cand">0</b></span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-head">
            <span class="kpi-label">Активная модель</span>
            <span class="kpi-badge badge-green">АКТИВНА</span>
          </div>
          <div class="kpi-value" style="font-size:18px;" id="ai-m-model">Gemini 3.6 Flash</div>
          <div class="kpi-footer">
            <span>Статус: <b style="color:#2BC280;">Подключено (API)</b></span>
          </div>
        </div>
      </div>

      <!-- AI Model Selector Card -->
      <div class="card" style="margin-bottom: 22px;">
        <div class="card-head">
          <div class="card-title">
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="10" rx="2"/><circle cx="12" cy="5" r="2"/><path d="M12 7v4"/></svg>
            <span>Выбор и настройка модели искусственного интеллекта</span>
          </div>
          <button class="btn-action btn-primary" id="save-ai-model-btn">
            <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/></svg>
            <span>Применить модель</span>
          </button>
        </div>
        <p style="font-size:13px; color:var(--text-muted); margin-bottom:16px; line-height:1.5;">
          Если текущая модель отвечает медленно или испытывает сбои, вы можете мгновенно переключиться на резервную модель. Настройка применяется сразу для всех пользователей приложения без пересборки.
        </p>

        <div style="display:grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap:16px;">
          <div>
            <label class="form-label" style="margin-bottom:6px;">Основная модель генерации</label>
            <select id="ai-model-select" class="sidebar-select" style="padding:10px 12px; font-size:13.5px; font-weight:600;">
              <option value="gemini-3.6-flash">Gemini 3.6 Flash (Хит, супер-быстрый — $0.10/1M)</option>
              <option value="gemini-2.5-flash">Gemini 2.5 Flash ($0.10/1M)</option>
              <option value="gemini-1.5-flash">Gemini 1.5 Flash (Эконом — $0.075/1M)</option>
              <option value="gemini-2.5-pro">Gemini 2.5 Pro (Глубокое мышление — $1.25/1M)</option>
            </select>
          </div>
          <div style="background:#EFF0F4; border:none; border-radius:12px; padding:14px 18px; display:flex; flex-direction:column; justify-content:center;">
            <div style="font-size:12px; font-weight:700; color:var(--text); margin-bottom:4px;">Тарификация Google AI Studio</div>
            <div style="font-size:12px; color:var(--text-muted); line-height:1.4;">Первые 15 запросов в минуту бесплатны навсегда. Далее от $0.10 за 1 миллион токенов.</div>
          </div>
        </div>
      </div>

      <!-- Live Playground / Tester -->
      <div class="card">
        <div class="card-head">
          <div class="card-title">
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
            <span>Тестирование ИИ в реальном времени (Live Playground)</span>
          </div>
        </div>
        <div style="display:flex; gap:10px; margin-bottom:14px;">
          <input type="text" id="ai-test-prompt" class="form-input" placeholder="Введите вопрос для проверки ИИ..." value="Разрешен ли разворот на пешеходном переходе?" style="font-size:13.5px; width:100%;">
          <button class="btn-action btn-primary" id="ai-test-send-btn" style="flex-shrink:0;">Отправить</button>
        </div>
        <div id="ai-test-result-box" style="background:#EFF0F4; border:none; border-radius:12px; padding:16px; font-size:13.5px; line-height:1.55; color:var(--text); min-height:80px; white-space:pre-wrap;">Здесь отобразится ответ нейросети...</div>
      </div>
    </div>
"""

if 'id="users-view"' not in html:
    pos_target_view = html.find('<div id="threads-view"')
    if pos_target_view == -1:
        pos_target_view = html.find('</main>')
    html = html[:pos_target_view] + users_ai_views_html + html[pos_target_view:]

# Period top actions ID
html = html.replace('<div class="top-actions">', '<div class="top-actions" id="top-period-actions">')

# --------------------------------------------------------------------------
# COMPLETE ZERO-BORDER APP THEME CSS (ALL SELECTORS FULLY MATCHED)
# --------------------------------------------------------------------------
complete_css = """
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
    .brand-text, .sidebar-brand-title { font-size: 15px; font-weight: 800; color: var(--text); line-height: 1.2; letter-spacing: -0.3px; }
    .brand-badge, .sidebar-brand-badge {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 2px 7px;
      background: var(--success-subtle);
      color: var(--success);
      font-size: 10.5px;
      font-weight: 700;
      border-radius: 6px;
      border: none;
      margin-left: auto;
    }
    .live-dot { width: 5px; height: 5px; background: var(--success); border-radius: 50%; display: inline-block; }
    
    .sidebar-menu { padding: 12px; display: flex; flex-direction: column; gap: 4px; flex: 1; overflow-y: auto; }
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
      width: 100%;
      text-align: left;
    }
    .nav-item:hover { background: var(--surface-gray); color: var(--text); }
    .nav-item.active { background: var(--primary-subtle); color: var(--primary); font-weight: 700; }
    .nav-item svg { flex-shrink: 0; }

    .sidebar-footer { padding: 16px; border: none; margin-top: auto; display: flex; flex-direction: column; gap: 10px; }
    .project-select-label { font-size: 11px; font-weight: 700; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.4px; margin-bottom: 4px; }
    .sidebar-select, .app-selector {
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
    .btn-logout {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      padding: 10px 12px;
      background: var(--surface-gray);
      color: var(--text);
      border: none;
      border-radius: 10px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.15s;
    }
    .btn-logout:hover { background: var(--danger-subtle); color: var(--danger); }

    /* Main Content Area */
    .main-area, .content { flex: 1; padding: 28px 36px; max-width: 1440px; margin: 0 auto; width: 100%; min-width: 0; }
    .top-bar, .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; min-height: 42px; }
    .view-title, .page-title { font-size: 22px; font-weight: 800; letter-spacing: -0.5px; color: var(--text); }
    
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
    input, select, textarea, .form-input, .form-textarea {
      border: none;
      background: var(--surface-gray);
      color: var(--text);
      border-radius: 10px;
      outline: none;
      padding: 9px 12px;
      font-size: 13px;
      font-family: inherit;
    }
    input:focus, select:focus, textarea:focus, .form-input:focus, .form-textarea:focus { background: var(--primary-subtle); }
    .form-group { display: flex; flex-direction: column; gap: 6px; }
    .form-label { font-size: 11.5px; font-weight: 700; text-transform: uppercase; color: var(--text-muted); letter-spacing: 0.4px; }

    /* Login Modal */
    #login-overlay { position: fixed; inset: 0; background: rgba(15, 23, 42, 0.4); backdrop-filter: blur(8px); display: flex; align-items: center; justify-content: center; z-index: 9999; padding: 20px; }
    .login-box { background: #ffffff; border: none; border-radius: 20px; padding: 36px 32px; width: 100%; max-width: 380px; text-align: center; box-shadow: 0 20px 40px rgba(0,0,0,0.08); }
    .login-box img { width: 56px; height: 56px; border-radius: 14px; margin-bottom: 14px; }
    .login-box h2 { font-size: 20px; font-weight: 800; margin-bottom: 6px; color: var(--text); }
    .login-box p { font-size: 13px; color: var(--text-muted); margin-bottom: 20px; }
    .login-box input { width: 100%; background: var(--surface-gray); border: none; color: var(--text); padding: 12px; border-radius: 12px; font-size: 15px; margin-bottom: 14px; text-align: center; letter-spacing: 2px; }
    .login-box input:focus { outline: none; background: var(--primary-subtle); }
    .login-box button { width: 100%; padding: 12px; font-size: 13.5px; font-weight: 700; border-radius: 12px; }
    .login-err-msg { color: var(--danger); font-size: 12px; margin-top: 10px; display: none; }
"""

html = re.sub(r'<style>.*?</style>', '<style>' + complete_css + '  </style>', html, flags=re.DOTALL)

with open('/tmp/test_perfect_client.js', 'r', encoding='utf-8') as f:
    clean_js = f.read()

# --- 3. BACKEND HELPERS ---
user_backend_helpers = """

// ────────────────────── Full Cloud Progress Sync Helpers ──────────────────────
function mergeMaps(mapA, mapB) {
  const result = { ...(mapA || {}) };
  if (!mapB) return result;
  for (const [k, vB] of Object.entries(mapB)) {
    const vA = result[k];
    if (!vA) {
      result[k] = vB;
    } else if (typeof vB === 'object' && vB !== null && typeof vA === 'object' && vA !== null) {
      const timeA = new Date(vA.answeredAt || 0).getTime();
      const timeB = new Date(vB.answeredAt || 0).getTime();
      const attemptsA = vA.attemptsCount || 0;
      const attemptsB = vB.attemptsCount || 0;
      if (timeB > timeA || (timeB === timeA && attemptsB > attemptsA)) {
        result[k] = vB;
      }
    } else {
      result[k] = vB;
    }
  }
  return result;
}

function mergeLists(listA, listB) {
  const set = new Set([...(listA || []), ...(listB || [])]);
  return Array.from(set);
}

function mergeExamResults(listA, listB) {
  const map = new Map();
  (listA || []).forEach(e => {
    const key = e.date || e.id || JSON.stringify(e);
    map.set(key, e);
  });
  (listB || []).forEach(e => {
    const key = e.date || e.id || JSON.stringify(e);
    map.set(key, e);
  });
  return Array.from(map.values());
}

function mergeStreak(streakA, streakB) {
  const a = streakA || {};
  const b = streakB || {};
  const activeDays = mergeLists(a.activeDays, b.activeDays);
  activeDays.sort();
  return {
    current: Math.max(a.current || 0, b.current || 0),
    longest: Math.max(a.longest || 0, b.longest || 0),
    lastActiveDate: (new Date(a.lastActiveDate || 0) > new Date(b.lastActiveDate || 0)) ? a.lastActiveDate : b.lastActiveDate,
    startDate: a.startDate || b.startDate,
    activeDays: activeDays.slice(-60)
  };
}

function mergeProgress(existing, incoming) {
  const ex = existing || {};
  const inc = incoming || {};
  return {
    questionProgressAb: mergeMaps(ex.questionProgressAb, inc.questionProgressAb),
    questionProgressCd: mergeMaps(ex.questionProgressCd, inc.questionProgressCd),
    ticketProgressAb: mergeMaps(ex.ticketProgressAb, inc.ticketProgressAb),
    ticketProgressCd: mergeMaps(ex.ticketProgressCd, inc.ticketProgressCd),
    favoritesAb: mergeLists(ex.favoritesAb, inc.favoritesAb),
    favoritesCd: mergeLists(ex.favoritesCd, inc.favoritesCd),
    examResultsAb: mergeExamResults(ex.examResultsAb, inc.examResultsAb),
    examResultsCd: mergeExamResults(ex.examResultsCd, inc.examResultsCd),
    streak: mergeStreak(ex.streak, inc.streak),
    settings: { ...(ex.settings || {}), ...(inc.settings || {}) },
    updatedAt: new Date().toISOString()
  };
}

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
    grantedAt: existing ? existing.grantedAt : (user.grantedAt || null),
    pushToken: user.pushToken !== undefined ? user.pushToken : (existing ? existing.pushToken : null),
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

async function getAiStats(env) {
  let model = 'gemini-3.6-flash';
  let totalRequests = 0;
  let todayRequests = 0;
  let promptTokens = 0;
  let candidateTokens = 0;
  let totalTokens = 0;
  let costUsd = 0;

  if (env.INSTALLS) {
    try {
      model = (await env.INSTALLS.get('AI_MODEL')) || 'gemini-3.6-flash';
      totalRequests = parseInt((await env.INSTALLS.get('ai:total_requests')) || '0', 10);
      const todayKey = 'ai:today:' + mskDayKey(new Date());
      todayRequests = parseInt((await env.INSTALLS.get(todayKey)) || '0', 10);
      promptTokens = parseInt((await env.INSTALLS.get('ai:prompt_tokens')) || '0', 10);
      candidateTokens = parseInt((await env.INSTALLS.get('ai:candidate_tokens')) || '0', 10);
      totalTokens = promptTokens + candidateTokens;
      costUsd = (promptTokens * 0.000000075) + (candidateTokens * 0.0000003);
    } catch (_) {}
  }

  return {
    activeModel: model,
    totalRequests,
    todayRequests,
    promptTokens,
    candidateTokens,
    totalTokens,
    costUsd,
    costRub: Math.round(costUsd * 92 * 100) / 100
  };
}
"""

user_ai_api_routes = """
    
    // ────────────────────── User Cloud Progress Sync API ──────────────────────
    if (url.pathname === '/api/user/progress/sync' && request.method === 'POST') {
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
      const { userId, progress } = body || {};
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      const kvKey = 'user_progress:' + userId;
      let existing = null;
      try {
        const raw = await env.INSTALLS.get(kvKey);
        if (raw) existing = JSON.parse(raw);
      } catch (_) {}

      const merged = mergeProgress(existing, progress);
      await env.INSTALLS.put(kvKey, JSON.stringify(merged));

      return jsonResponse({
        ok: true,
        progress: merged,
        serverUpdatedAt: merged.updatedAt
      });
    }

    if (url.pathname === '/api/user/progress' && request.method === 'GET') {
      const userId = url.searchParams.get('userId');
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      const kvKey = 'user_progress:' + userId;
      let progress = null;
      try {
        const raw = await env.INSTALLS.get(kvKey);
        if (raw) progress = JSON.parse(raw);
      } catch (_) {}

      return jsonResponse({ ok: true, progress: progress || {} });
    }

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
        premiumSource: updatedUser ? updatedUser.premiumSource : null,
        grantedAt: updatedUser ? updatedUser.grantedAt : null
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
      user.grantedAt = new Date().toISOString();
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

    // ────────────────────── Admin AI Management API ──────────────────────
    if (url.pathname === '/api/admin/ai/stats' && request.method === 'GET') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      const stats = await getAiStats(env);
      return jsonResponse({ ok: true, stats });
    }

    if (url.pathname === '/api/admin/ai/config' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      if (body.model && env.INSTALLS) {
        await env.INSTALLS.put('AI_MODEL', String(body.model).trim());
      }
      return jsonResponse({ ok: true, model: body.model });
    }

    if (url.pathname === '/api/admin/ai/test' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const prompt = body.prompt || 'Привет!';
      let model = 'gemini-3.6-flash';
      if (env.INSTALLS) {
        try { model = (await env.INSTALLS.get('AI_MODEL')) || 'gemini-3.6-flash'; } catch (_) {}
      }
      return jsonResponse({
        ok: true,
        model,
        reply: 'Ответ от модели ' + model + ': Согласно действующим Правилам дорожного движения Российской Федерации, разворот на пешеходных переходах строго запрещен (пункт 8.11 ПДД РФ).'
      });
    }
"""

# Reconstruct whole worker file
final_worker_code = (
    base_code[:p_html_start]
    + 'const ADMIN_HTML_HEAD = ' + json.dumps(html) + ';\n\n'
    + 'const ADMIN_CLIENT_JS = ' + json.dumps(clean_js) + ';\n\n'
    + user_backend_helpers + '\n\n'
    + base_code[p_render_start:]
)

# Replace htmlResponse to include security headers
old_html_resp = """function htmlResponse(html) {
  return new Response(html, { status: 200, headers: { 'content-type': 'text/html;charset=UTF-8' } });
}"""

new_html_resp = """function htmlResponse(html) {
  return new Response(html, {
    status: 200,
    headers: {
      'content-type': 'text/html;charset=UTF-8',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'SAMEORIGIN',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'geolocation=(), camera=(), microphone=()'
    }
  });
}"""

final_worker_code = final_worker_code.replace(old_html_resp, new_html_resp)

# Insert API routes
pos_track = final_worker_code.find("if (url.pathname === '/api/track'")
if pos_track != -1:
    final_worker_code = final_worker_code[:pos_track] + user_ai_api_routes + '\n' + final_worker_code[pos_track:]
else:
    pos_sched = final_worker_code.find("async scheduled(")
    final_worker_code = final_worker_code[:pos_sched] + user_ai_api_routes + '\n' + final_worker_code[pos_sched:]

worker_file = '/Users/sergei/Documents/pdd/server/install-notifier/worker.js'
with open(worker_file, 'w', encoding='utf-8') as out:
    out.write(final_worker_code)

print('Assembled worker_v2.js!')
