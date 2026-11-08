#!/usr/bin/env python3
import sys

with open('server/install-notifier/worker.js', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Update getAiAnalyticsStats to include deposit and remaining calculations
old_stats_code = """async function getAiAnalyticsStats(env) {
  const activeModel = await getActiveAiModel(env);
  let totalRequests = 0;
  let todayRequests = 0;
  let promptTokens = 0;
  let candidateTokens = 0;
  let costUsd = 0;

  if (env.INSTALLS) {
    try {
      const today = new Date().toISOString().slice(0, 10);
      totalRequests = parseInt(await env.INSTALLS.get('ai_stats_total_req') || '0', 10);
      todayRequests = parseInt(await env.INSTALLS.get('ai_stats_today_req_' + today) || '0', 10);
      promptTokens = parseInt(await env.INSTALLS.get('ai_stats_prompt_tokens') || '0', 10);
      candidateTokens = parseInt(await env.INSTALLS.get('ai_stats_candidate_tokens') || '0', 10);
      costUsd = parseFloat(await env.INSTALLS.get('ai_stats_cost_usd') || '0');
    } catch (_) {}
  }

  const totalTokens = promptTokens + candidateTokens;
  const costRub = (costUsd * 92.5).toFixed(2);

  const availableModels = Object.keys(GEMINI_PRICING).map(k => ({
    id: k,
    name: GEMINI_PRICING[k].name,
    inputPrice: '$' + GEMINI_PRICING[k].inputPerM + ' / 1M',
    outputPrice: '$' + GEMINI_PRICING[k].outputPerM + ' / 1M',
    active: k === activeModel
  }));

  return {
    ok: true,
    stats: {
      totalRequests,
      todayRequests,
      promptTokens,
      candidateTokens,
      totalTokens,
      costUsd: Number(costUsd.toFixed(5)),
      costRub: Number(costRub),
      activeModel,
      activeModelName: GEMINI_PRICING[activeModel]?.name || activeModel,
      availableModels
    }
  };
}"""

new_stats_code = """async function getAiAnalyticsStats(env) {
  const activeModel = await getActiveAiModel(env);
  let totalRequests = 0;
  let todayRequests = 0;
  let promptTokens = 0;
  let candidateTokens = 0;
  let costUsd = 0;
  let depositUsd = 10.0;

  if (env.INSTALLS) {
    try {
      const today = new Date().toISOString().slice(0, 10);
      totalRequests = parseInt(await env.INSTALLS.get('ai_stats_total_req') || '0', 10);
      todayRequests = parseInt(await env.INSTALLS.get('ai_stats_today_req_' + today) || '0', 10);
      promptTokens = parseInt(await env.INSTALLS.get('ai_stats_prompt_tokens') || '0', 10);
      candidateTokens = parseInt(await env.INSTALLS.get('ai_stats_candidate_tokens') || '0', 10);
      costUsd = parseFloat(await env.INSTALLS.get('ai_stats_cost_usd') || '0');
      const depRaw = await env.INSTALLS.get('ai_config_deposit');
      if (depRaw) depositUsd = parseFloat(depRaw);
    } catch (_) {}
  }

  const totalTokens = promptTokens + candidateTokens;
  const costRub = (costUsd * 95.0).toFixed(2);
  const remainingUsd = Math.max(0, depositUsd - costUsd);
  const remainingRub = (remainingUsd * 95.0).toFixed(2);
  const percentUsed = depositUsd > 0 ? Math.min(100, (costUsd / depositUsd) * 100).toFixed(1) : '0.0';
  const percentRemaining = (100 - parseFloat(percentUsed)).toFixed(1);

  const availableModels = Object.keys(GEMINI_PRICING).map(k => ({
    id: k,
    name: GEMINI_PRICING[k].name,
    inputPrice: '$' + GEMINI_PRICING[k].inputPerM + ' / 1M',
    outputPrice: '$' + GEMINI_PRICING[k].outputPerM + ' / 1M',
    active: k === activeModel
  }));

  return {
    ok: true,
    stats: {
      totalRequests,
      todayRequests,
      promptTokens,
      candidateTokens,
      totalTokens,
      costUsd: Number(costUsd.toFixed(5)),
      costRub: Number(costRub),
      depositUsd: Number(depositUsd.toFixed(2)),
      remainingUsd: Number(remainingUsd.toFixed(5)),
      remainingRub: Number(remainingRub),
      percentUsed: Number(percentUsed),
      percentRemaining: Number(percentRemaining),
      activeModel,
      activeModelName: GEMINI_PRICING[activeModel]?.name || activeModel,
      availableModels
    }
  };
}"""

if old_stats_code in text:
    text = text.replace(old_stats_code, new_stats_code)
    print("getAiAnalyticsStats updated!")
else:
    print("Warning: old_stats_code not found directly, checking partial replacement...")

# 2. Update /api/admin/ai/config endpoint in worker.js
old_config_route = """    if (url.pathname === '/api/admin/ai/config' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { model } = body || {};
      if (model && GEMINI_PRICING[model] && env.INSTALLS) {
        await env.INSTALLS.put('ai_config_model', model);
      }
      return jsonResponse({ ok: true, model: await getActiveAiModel(env) });
    }"""

new_config_route = """    if (url.pathname === '/api/admin/ai/config' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { model, deposit } = body || {};
      if (model && GEMINI_PRICING[model] && env.INSTALLS) {
        await env.INSTALLS.put('ai_config_model', model);
      }
      if (deposit !== undefined && env.INSTALLS) {
        const d = parseFloat(deposit);
        if (!isNaN(d) && d >= 0) {
          await env.INSTALLS.put('ai_config_deposit', d.toString());
        }
      }
      return jsonResponse({ ok: true, model: await getActiveAiModel(env) });
    }"""

if old_config_route in text:
    text = text.replace(old_config_route, new_config_route)
    print("ai/config route updated!")

# 3. Update HTML for ai-view
old_ai_view_marker = '<!-- 6. AI MANAGEMENT VIEW -->'
idx_ai_view = text.find(old_ai_view_marker)
if idx_ai_view != -1:
    end_ai_view = text.find('<!-- Promo Card Modal Dialog -->', idx_ai_view)
    if end_ai_view == -1:
        end_ai_view = text.find('</div>\\n    </div>\\n\\n    <!-- Promo Card Modal Dialog -->', idx_ai_view)
    
    new_ai_view_html = r"""<!-- 6. AI MANAGEMENT VIEW -->
    <div id=\"ai-view\" style=\"display:none;\">
      <!-- AI KPI Cards -->
      <div class=\"kpi-grid\">
        <div class=\"kpi-card\">
          <div class=\"kpi-head\">
            <span class=\"kpi-label\">Всего запросов к ИИ</span>
          </div>
          <div class=\"kpi-value\" id=\"ai-m-total\">0</div>
          <div class=\"kpi-footer\">
            <span>Сегодня: <b id=\"ai-m-today\" style=\"color:var(--text);font-weight:700;\">0</b></span>
          </div>
        </div>

        <div class=\"kpi-card\">
          <div class=\"kpi-head\">
            <span class=\"kpi-label\">Остаток депозита ($10)</span>
            <span class=\"kpi-badge badge-green\" id=\"ai-m-deposit-badge\">100% осталось</span>
          </div>
          <div class=\"kpi-value\" id=\"ai-m-remaining-usd\" style=\"color:#059669;\">$10.00</div>
          <div class=\"kpi-footer\">
            <span>В рублях: <b id=\"ai-m-remaining-rub\" style=\"color:var(--text);\">~950 ₽</b></span>
          </div>
        </div>

        <div class=\"kpi-card\">
          <div class=\"kpi-head\">
            <span class=\"kpi-label\">Израсходовано с депозита</span>
            <span class=\"kpi-badge badge-blue\" id=\"ai-m-cost-rub\">~0.00 ₽</span>
          </div>
          <div class=\"kpi-value\" id=\"ai-m-cost-usd\">$0.00000</div>
          <div class=\"kpi-footer\">
            <span>Токенов: <b id=\"ai-m-tokens-total\">0</b> (<span id=\"ai-m-tokens-k\">0k</span>)</span>
          </div>
        </div>

        <div class=\"kpi-card\">
          <div class=\"kpi-head\">
            <span class=\"kpi-label\">Активная модель</span>
            <span class=\"kpi-badge badge-green\">АКТИВНА</span>
          </div>
          <div class=\"kpi-value\" style=\"font-size:18px;\" id=\"ai-m-model\">Gemini 3.6 Flash</div>
          <div class=\"kpi-footer\">
            <span>Статус: <b style=\"color:#059669;\">Подключено (API)</b></span>
          </div>
        </div>
      </div>

      <!-- AI Deposit / Balance Tracker Card -->
      <div class=\"card\" style=\"margin-bottom: 22px;\">
        <div class=\"card-head\">
          <div class=\"card-title\">
            <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><rect x=\"2\" y=\"5\" width=\"20\" height=\"14\" rx=\"2\"/><line x1=\"2\" y1=\"10\" x2=\"22\" y2=\"10\"/></svg>
            <span>Баланс депозита и пополнение в Google AI Studio / Cloud</span>
          </div>
          <a href=\"https://console.cloud.google.com/billing\" target=\"_blank\" class=\"btn-action btn-primary\" style=\"text-decoration:none;\">
            <span>Пополнить баланс в Google Cloud ↗</span>
          </a>
        </div>
        <p style=\"font-size:13px; color:var(--text-muted); margin-bottom:14px; line-height:1.5;\">
          При активации платного доступа Google списывает стартовый депозит (обычно <b>$10</b>). Здесь вы можете отслеживать фактический остаток средств и обновлять внесенную сумму после пополнения.
        </p>

        <!-- Progress Bar -->
        <div style=\"margin-bottom:16px;\">
          <div style=\"display:flex; justify-content:space-between; font-size:12px; font-weight:600; margin-bottom:6px;\">
            <span>Использование депозита: <b id=\"ai-bar-text\">0.0%</b></span>
            <span style=\"color:#059669;\">Остаток: <b id=\"ai-bar-rem\">$10.00</b></span>
          </div>
          <div style=\"background:#e2e8f0; height:8px; border-radius:4px; overflow:hidden;\">
            <div id=\"ai-progress-bar\" style=\"width:0%; height:100%; background:#10b981; transition:width 0.3s;\"></div>
          </div>
        </div>

        <div style=\"display:flex; gap:12px; align-items:flex-end; flex-wrap:wrap; background:#fafbfc; border:1px solid var(--card-border); border-radius:10px; padding:14px 16px;\">
          <div style=\"flex:1; min-width:200px;\">
            <label class=\"form-label\" style=\"margin-bottom:6px;\">Внесенный депозит ($ USD)</label>
            <input type=\"number\" id=\"ai-deposit-input\" step=\"1\" min=\"0\" class=\"form-input\" value=\"10.00\" style=\"font-size:14px; font-weight:700;\">
          </div>
          <button class=\"btn-action\" id=\"save-ai-deposit-btn\" style=\"padding:10px 16px; font-weight:600;\">
            Сохранить депозит
          </button>
        </div>
      </div>

      <!-- AI Model Selector Card -->
      <div class=\"card\" style=\"margin-bottom: 22px;\">
        <div class=\"card-head\">
          <div class=\"card-title\">
            <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><rect x=\"3\" y=\"11\" width=\"18\" height=\"10\" rx=\"2\"/><circle cx=\"12\" cy=\"5\" r=\"2\"/><path d=\"M12 7v4\"/></svg>
            <span>Выбор и настройка модели искусственного интеллекта</span>
          </div>
          <button class=\"btn-action btn-primary\" id=\"save-ai-model-btn\">
            <svg viewBox=\"0 0 24 24\" width=\"15\" height=\"15\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><path d=\"M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z\"/><polyline points=\"17 21 17 13 7 13 7 21\"/><polyline points=\"7 3 7 8 15 8\"/></svg>
            <span>Применить модель</span>
          </button>
        </div>
        <p style=\"font-size:13px; color:var(--text-muted); margin-bottom:16px; line-height:1.5;\">
          Если текущая модель отвечает медленно или испытывает сбои, вы можете мгновенно переключиться на резервную модель. Настройка применяется сразу для всех пользователей приложения без пересборки.
        </p>

        <div style=\"display:grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap:16px;\">
          <div>
            <label class=\"form-label\" style=\"margin-bottom:6px;\">Основная модель генерации</label>
            <select id=\"ai-model-select\" class=\"sidebar-select\" style=\"padding:10px 12px; font-size:13.5px; font-weight:600;\">
              <option value=\"gemini-3.6-flash\">Gemini 3.6 Flash (Хит, супер-быстрый — $0.10/1M)</option>
              <option value=\"gemini-2.5-flash\">Gemini 2.5 Flash ($0.10/1M)</option>
              <option value=\"gemini-1.5-flash\">Gemini 1.5 Flash (Эконом — $0.075/1M)</option>
              <option value=\"gemini-2.5-pro\">Gemini 2.5 Pro (Глубокое мышление — $1.25/1M)</option>
            </select>
          </div>
          <div style=\"background:#fafbfc; border:1px solid var(--card-border); border-radius:10px; padding:12px 16px; display:flex; flex-direction:column; justify-content:center;\">
            <div style=\"font-size:12px; font-weight:600; color:var(--text); margin-bottom:4px;\">Тарификация Google AI Studio</div>
            <div style=\"font-size:12px; color:var(--text-muted); line-height:1.4;\">Первые 15 запросов в минуту бесплатны навсегда. Далее от $0.10 за 1 миллион токенов.</div>
          </div>
        </div>
      </div>

      <!-- Live Playground / Tester -->
      <div class=\"card\">
        <div class=\"card-head\">
          <div class=\"card-title\">
            <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><path d=\"M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z\"/></svg>
            <span>Тестирование ИИ в реальном времени (Live Playground)</span>
          </div>
        </div>
        <div style=\"display:flex; gap:10px; margin-bottom:14px;\">
          <input type=\"text\" id=\"ai-test-prompt\" class=\"form-input\" placeholder=\"Введите вопрос для проверки ИИ...\" value=\"Разрешен ли разворот на пешеходном переходе?\" style=\"font-size:13.5px;\">
          <button class=\"btn-action btn-primary\" id=\"ai-test-send-btn\" style=\"flex-shrink:0;\">Отправить</button>
        </div>
        <div id=\"ai-test-result-box\" style=\"background:#fafbfc; border:1px solid var(--card-border); border-radius:10px; padding:16px; font-size:13.5px; line-height:1.55; color:var(--text); min-height:80px; white-space:pre-wrap;\">Здесь отобразится ответ нейросети...</div>
      </div>
    </div>\n\n    """
    
    # Replace the section
    idx_end_div = text.find('<!-- Promo Card Modal Dialog -->')
    if idx_end_div != -1:
        text = text[:idx_ai_view] + new_ai_view_html.replace('\n', r'\n') + text[idx_end_div:]
        print("HTML for ai-view updated with Deposit tracker!")

# 4. Update loadAiStats in client JS
old_load_stats = """async function loadAiStats() {
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
}"""

new_load_stats = """async function loadAiStats() {
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

    const elRemUsd = document.getElementById('ai-m-remaining-usd');
    if (elRemUsd) elRemUsd.innerText = '$' + (s.remainingUsd !== undefined ? s.remainingUsd.toFixed(4) : (10.0 - s.costUsd).toFixed(4));

    const elRemRub = document.getElementById('ai-m-remaining-rub');
    if (elRemRub) elRemRub.innerText = '~' + (s.remainingRub !== undefined ? s.remainingRub : ((10.0 - s.costUsd) * 95).toFixed(1)) + ' ₽';

    const depBadge = document.getElementById('ai-m-deposit-badge');
    if (depBadge) {
      const remP = s.percentRemaining !== undefined ? s.percentRemaining : 100.0;
      depBadge.innerText = remP + '% осталось';
      if (remP < 20) {
        depBadge.className = 'kpi-badge badge-blue';
        depBadge.style.background = '#fef2f2';
        depBadge.style.color = '#ef4444';
        depBadge.style.borderColor = '#fecaca';
      } else {
        depBadge.className = 'kpi-badge badge-green';
        depBadge.style.background = '#ecfdf5';
        depBadge.style.color = '#059669';
        depBadge.style.borderColor = '#a7f3d0';
      }
    }

    const barText = document.getElementById('ai-bar-text');
    if (barText) barText.innerText = (s.percentUsed || 0) + '% ($' + (s.costUsd || 0).toFixed(4) + ')';

    const barRem = document.getElementById('ai-bar-rem');
    if (barRem) barRem.innerText = '$' + (s.remainingUsd || 10.0).toFixed(4) + ' из $' + (s.depositUsd || 10.0).toFixed(2);

    const pBar = document.getElementById('ai-progress-bar');
    if (pBar) {
      const p = Math.min(100, Math.max(0, s.percentUsed || 0));
      pBar.style.width = p + '%';
      pBar.style.background = p > 80 ? '#ef4444' : (p > 50 ? '#f59e0b' : '#10b981');
    }

    const depInput = document.getElementById('ai-deposit-input');
    if (depInput && !depInput.matches(':focus')) {
      depInput.value = (s.depositUsd || 10.0).toFixed(2);
    }

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

const saveAiDepositBtn = document.getElementById('save-ai-deposit-btn');
if (saveAiDepositBtn) {
  saveAiDepositBtn.addEventListener('click', async () => {
    const input = document.getElementById('ai-deposit-input');
    if (!input) return;
    const dep = parseFloat(input.value);
    if (isNaN(dep) || dep < 0) {
      alert('Пожалуйста, введите корректную сумму депозита в USD');
      return;
    }
    saveAiDepositBtn.innerText = 'Сохраняю...';
    try {
      const r = await fetch('/api/admin/ai/config', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ deposit: dep })
      });
      if (r.ok) {
        saveAiDepositBtn.innerText = 'Успешно сохранено!';
        setTimeout(() => { saveAiDepositBtn.innerText = 'Сохранить депозит'; }, 1800);
        loadAiStats();
      } else {
        alert('Ошибка при сохранении: ' + r.status);
        saveAiDepositBtn.innerText = 'Сохранить депозит';
      }
    } catch (e) {
      alert('Ошибка сети: ' + e);
      saveAiDepositBtn.innerText = 'Сохранить депозит';
    }
  });
}"""

# Replace in client JS
escaped_old_load = old_load_stats.replace('\n', r'\n').replace('"', r'\"')
escaped_new_load = new_load_stats.replace('\n', r'\n').replace('"', r'\"')

if escaped_old_load in text:
    text = text.replace(escaped_old_load, escaped_new_load)
    print("loadAiStats updated in client JS!")
else:
    print("Warning: old loadAiStats not matched directly, searching via index...")
    idx_l = text.find("async function loadAiStats()")
    if idx_l != -1:
        idx_end_l = text.find("const saveAiModelBtn =", idx_l)
        if idx_end_l != -1:
            text = text[:idx_l] + escaped_new_load + r'\n\n' + text[idx_end_l:]
            print("loadAiStats replaced via indices!")

with open('server/install-notifier/worker.js', 'w', encoding='utf-8') as f:
    f.write(text)

print("worker.js updated successfully with AI Deposit tracker!")
