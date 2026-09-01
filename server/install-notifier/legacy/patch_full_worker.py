#!/usr/bin/env python3
import json

with open('server/install-notifier/worker.js', 'r', encoding='utf-8') as f:
    text = f.read()

# ─────────────────────────────────────────────────────────────────────────────
# 1. AI Pricing, Helpers & Stats Tracker + User Profiles helpers
# ─────────────────────────────────────────────────────────────────────────────
backend_helpers = r'''
// ────────────────────── User Profile & Premium Helpers ──────────────────────
async function saveUserProfile(env, user) {
  if (!env.INSTALLS || !user || !user.id) return user;
  const kvKey = 'user:' + user.id;
  let existing = null;
  try {
    const raw = await env.INSTALLS.get(kvKey);
    if (raw) existing = JSON.parse(raw);
  } catch (_) {}

  const merged = {
    id: user.id,
    name: user.name || (existing ? existing.name : 'Пользователь'),
    email: user.email || (existing ? existing.email : null),
    avatarUrl: user.avatarUrl !== undefined ? user.avatarUrl : (existing ? existing.avatarUrl : null),
    provider: user.provider || (existing ? existing.provider : 'guest'),
    createdAt: (existing && existing.createdAt) ? existing.createdAt : (user.createdAt || new Date().toISOString()),
    lastSeenAt: new Date().toISOString(),
    isPremium: (existing && existing.isPremium !== undefined) ? existing.isPremium : (user.isPremium || false),
    premiumExpiresAt: (existing && existing.premiumExpiresAt !== undefined) ? existing.premiumExpiresAt : (user.premiumExpiresAt || null),
    premiumSource: (existing && existing.premiumSource !== undefined) ? existing.premiumSource : (user.premiumSource || null),
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
}

// ────────────────────── AI Model Pricing & Analytics ──────────────────────
const GEMINI_PRICING = {
  'gemini-3.6-flash': { inputPerM: 0.10, outputPerM: 0.40, name: 'Gemini 3.6 Flash (Хит, супер-быстрый)' },
  'gemini-2.5-flash': { inputPerM: 0.10, outputPerM: 0.40, name: 'Gemini 2.5 Flash' },
  'gemini-1.5-flash': { inputPerM: 0.075, outputPerM: 0.30, name: 'Gemini 1.5 Flash (Эконом)' },
  'gemini-2.5-pro': { inputPerM: 1.25, outputPerM: 5.00, name: 'Gemini 2.5 Pro (Глубокое мышление)' },
  'gemini-1.5-pro': { inputPerM: 1.25, outputPerM: 5.00, name: 'Gemini 1.5 Pro' }
};

async function getActiveAiModel(env) {
  if (env.INSTALLS) {
    try {
      const customModel = await env.INSTALLS.get('ai_config_model');
      if (customModel && GEMINI_PRICING[customModel]) return customModel;
    } catch (_) {}
  }
  return 'gemini-3.6-flash';
}

async function recordAiUsage(env, model, promptTokens, candidateTokens) {
  if (!env.INSTALLS) return;
  try {
    const today = new Date().toISOString().slice(0, 10);
    const pricing = GEMINI_PRICING[model] || GEMINI_PRICING['gemini-3.6-flash'];
    const pTokens = Number(promptTokens) || 200;
    const cTokens = Number(candidateTokens) || 100;
    const costUsd = ((pTokens * pricing.inputPerM) + (cTokens * pricing.outputPerM)) / 1000000;

    const totalReq = (parseInt(await env.INSTALLS.get('ai_stats_total_req') || '0', 10)) + 1;
    const todayReq = (parseInt(await env.INSTALLS.get('ai_stats_today_req_' + today) || '0', 10)) + 1;
    const totalPrompt = (parseInt(await env.INSTALLS.get('ai_stats_prompt_tokens') || '0', 10)) + pTokens;
    const totalCandidate = (parseInt(await env.INSTALLS.get('ai_stats_candidate_tokens') || '0', 10)) + cTokens;
    const totalCost = (parseFloat(await env.INSTALLS.get('ai_stats_cost_usd') || '0')) + costUsd;

    await Promise.all([
      env.INSTALLS.put('ai_stats_total_req', String(totalReq)),
      env.INSTALLS.put('ai_stats_today_req_' + today, String(todayReq), { expirationTtl: 86400 * 30 }),
      env.INSTALLS.put('ai_stats_prompt_tokens', String(totalPrompt)),
      env.INSTALLS.put('ai_stats_candidate_tokens', String(totalCandidate)),
      env.INSTALLS.put('ai_stats_cost_usd', totalCost.toFixed(6))
    ]);
  } catch (e) {
    console.error('recordAiUsage error:', e);
  }
}

async function getAiAnalyticsStats(env) {
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
}
'''

# ─────────────────────────────────────────────────────────────────────────────
# 2. Complete API Routes (Placed cleanly inside fetch before store redirect)
# ─────────────────────────────────────────────────────────────────────────────
api_routes = r'''    // ────────────────────── AI Assistant & Chat API ──────────────────────
    if (url.pathname === '/api/ai/chat' && request.method === 'POST') {
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
      const { questionText, answers, correctAnswerIndex, officialExplanation, messages, userMessage } = body || {};

      const correctAnswerText = (Array.isArray(answers) && correctAnswerIndex !== undefined && answers[correctAnswerIndex])
        ? answers[correctAnswerIndex]
        : 'Правильный вариант';

      const systemPrompt = `Ты — профессиональный преподаватель ПДД и персональный AI-автоинструктор.
Твоя задача — кратко, наглядно и человеческим языком объяснить дорожную ситуацию.

ОБЯЗАТЕЛЬНЫЕ ПРАВИЛА:
1. Пиши СТРОГО БЕЗ ПРИВЕТСТВИЙ, вступлений и общих фраз (запрещено писать "Привет!", "Давай разберем..."). Сразу начинай с сути.
2. Текст должен быть очень коротким и понятным (3-5 строк максимум).
3. Выделяй жирным шрифтом **главные термины**, **названия знаков** и **правильные действия**.

Вопрос: ${questionText || 'Вопрос ПДД'}
Варианты ответов:
${Array.isArray(answers) ? answers.map((a, i) => `${i + 1}. ${a}`).join('\n') : ''}
Правильный ответ: ${correctAnswerText}
Официальный комментарий: ${officialExplanation || 'Нет официального комментария'}`;

      let reply = '';
      const geminiKey = env.GEMINI_API_KEY || env.AI_API_KEY;
      const activeModel = await getActiveAiModel(env);

      if (geminiKey) {
        try {
          const contents = [];

          if (Array.isArray(messages) && messages.length > 0) {
            for (const m of messages) {
              const role = m.isUser ? 'user' : 'model';
              if (contents.length > 0 && contents[contents.length - 1].role === role) {
                contents[contents.length - 1].parts[0].text += '\n' + m.text;
              } else {
                contents.push({
                  role,
                  parts: [{ text: m.text }]
                });
              }
            }
          }

          if (userMessage) {
            if (contents.length > 0 && contents[contents.length - 1].role === 'user') {
              contents[contents.length - 1].parts[0].text += '\n' + userMessage;
            } else {
              contents.push({
                role: 'user',
                parts: [{ text: userMessage }]
              });
            }
          } else if (contents.length === 0) {
            contents.push({
              role: 'user',
              parts: [{ text: 'Объясни эту дорожную ситуацию кратко и по делу: 1) Суть на дороге, 2) Правило ПДД, 3) Подсказка.' }]
            });
          }

          const geminiResp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${activeModel}:generateContent?key=${geminiKey}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              systemInstruction: {
                parts: [{ text: systemPrompt }]
              },
              contents,
              generationConfig: {
                temperature: 0.35,
                maxOutputTokens: 2048
              }
            })
          });

          const data = await geminiResp.json();
          if (geminiResp.ok) {
            const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
            if (text) {
              reply = text.trim();
              const usage = data?.usageMetadata;
              const promptCnt = usage?.promptTokenCount || 240;
              const candCnt = usage?.candidatesTokenCount || 100;
              await recordAiUsage(env, activeModel, promptCnt, candCnt);
            }
          } else {
            console.error('Gemini API error status:', geminiResp.status, JSON.stringify(data));
          }
        } catch (e) {
          console.error('Gemini catch error:', e);
        }
      }

      if (!reply) {
        await recordAiUsage(env, activeModel, 150, 60);
        if (userMessage) {
          reply = `По этой ситуации главное: **правильный ответ — «${correctAnswerText}»**. ${officialExplanation || 'Ориентируйтесь на знаки приоритета, разметку и безопасность маневра.'}`;
        } else {
          reply = `🚗 **Что на дороге:** ${questionText ? questionText.replace(/\\?$/, '.') : 'Оценка дорожной обстановки.'}\n\n💡 **Логика ПДД:** ${officialExplanation || 'Согласно правилам, водитель обязан уступить дорогу имеющим преимущество.'}\n\n⚡ **Подсказка:** Правильный вариант — **«${correctAnswerText}»**.`;
        }
      }

      return jsonResponse({
        ok: true,
        reply,
        model: activeModel
      });
    }

    // ────────────────────── AI Admin API Endpoints ──────────────────────
    if (url.pathname === '/api/admin/ai/stats' && request.method === 'GET') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      const data = await getAiAnalyticsStats(env);
      return jsonResponse(data);
    }

    if (url.pathname === '/api/admin/ai/config' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
      const model = String(body.model || '').trim();
      if (!model || !GEMINI_PRICING[model]) {
        return jsonResponse({ error: 'unsupported model' }, 400);
      }
      if (env.INSTALLS) {
        await env.INSTALLS.put('ai_config_model', model);
      }
      return jsonResponse({ ok: true, model });
    }

    if (url.pathname === '/api/admin/ai/test' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
      const prompt = body.prompt || 'Объясни в 2 строках знак 3.20 Обгон запрещен';
      const geminiKey = env.GEMINI_API_KEY || env.AI_API_KEY;
      const activeModel = await getActiveAiModel(env);
      if (!geminiKey) return jsonResponse({ error: 'no gemini key in env' }, 400);

      const geminiResp = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${activeModel}:generateContent?key=${geminiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.3, maxOutputTokens: 1000 }
        })
      });
      const data = await geminiResp.json();
      const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (geminiResp.ok) {
        const usage = data?.usageMetadata;
        await recordAiUsage(env, activeModel, usage?.promptTokenCount || 100, usage?.candidatesTokenCount || 50);
      }
      return jsonResponse({ ok: true, model: activeModel, reply: text || JSON.stringify(data) });
    }

    // ────────────────────── User Profile & Premium API ──────────────────────
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
      user.premiumSource = 'revoked';
      user.premiumExpiresAt = new Date().toISOString();

      await env.INSTALLS.put('user:' + userId, JSON.stringify(user));
      return jsonResponse({ ok: true, user });
    }
'''

# 1. Insert helpers before "export default {"
export_idx = text.find('export default {')
text = text[:export_idx] + backend_helpers + '\n\n' + text[export_idx:]

# 2. Insert API routes before "if (url.pathname.startsWith('/go/'))"
go_idx = text.find("if (url.pathname.startsWith('/go/'))")
text = text[:go_idx] + api_routes + '\n\n    ' + text[go_idx:]

# 3. Add Sidebar buttons (Users + AI)
escaped_sidebar_buttons = r'\n      <button class=\"nav-item\" data-feature=\"users\">\n        <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2\"/><circle cx=\"9\" cy=\"7\" r=\"4\"/><path d=\"M23 21v-2a4 4 0 0 0-3-3.87\"/><path d=\"M16 3.13a4 4 0 0 1 0 7.75\"/></svg>\n        <span>Пользователи</span>\n      </button>\n      <button class=\"nav-item\" data-feature=\"ai\">\n        <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"3\" y=\"11\" width=\"18\" height=\"10\" rx=\"2\"/><circle cx=\"12\" cy=\"5\" r=\"2\"/><path d=\"M12 7v4\"/><line x1=\"8\" y1=\"16\" x2=\"8.01\" y2=\"16\"/><line x1=\"16\" y1=\"16\" x2=\"16.01\" y2=\"16\"/></svg>\n        <span>Управление ИИ</span>\n      </button>'
target_nav_threads = r'\n      <button class=\"nav-item\" data-feature=\"threads\">'
text = text.replace(target_nav_threads, escaped_sidebar_buttons + target_nav_threads, 1)

# 4. Add Views HTML (Users View + AI View)
escaped_views_html = r'''\n\n    <!-- 4. USERS MANAGEMENT VIEW -->\n    <div id=\"users-view\" style=\"display:none;\">\n      <div class=\"card\" style=\"margin-bottom: 22px;\">\n        <div class=\"card-head\">\n          <div class=\"card-title\">\n            <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><path d=\"M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2\"/><circle cx=\"9\" cy=\"7\" r=\"4\"/><path d=\"M23 21v-2a4 4 0 0 0-3-3.87\"/><path d=\"M16 3.13a4 4 0 0 1 0 7.75\"/></svg>\n            <span>Пользователи и Премиум-доступ (<span id=\"users-count\">0</span>)</span>\n          </div>\n          <button class=\"btn-action\" id=\"refresh-users-btn\">Обновить</button>\n        </div>\n        <div style=\"overflow-x:auto;\">\n          <table>\n            <thead>\n              <tr>\n                <th>Пользователь</th>\n                <th>Провайдер</th>\n                <th>Статус</th>\n                <th>Действует до</th>\n                <th>Последний вход</th>\n                <th>Действия</th>\n              </tr>\n            </thead>\n            <tbody id=\"table-users\">\n              <tr><td colspan=\"6\" style=\"text-align:center;color:var(--text-muted);\">Загрузка...</td></tr>\n            </tbody>\n          </table>\n        </div>\n      </div>\n    </div>\n\n    <!-- 6. AI MANAGEMENT VIEW -->\n    <div id=\"ai-view\" style=\"display:none;\">\n      <!-- AI KPI Cards -->\n      <div class=\"kpi-grid\">\n        <div class=\"kpi-card\">\n          <div class=\"kpi-head\">\n            <span class=\"kpi-label\">Всего запросов к ИИ</span>\n          </div>\n          <div class=\"kpi-value\" id=\"ai-m-total\">0</div>\n          <div class=\"kpi-footer\">\n            <span>Сегодня: <b id=\"ai-m-today\" style=\"color:var(--text);font-weight:700;\">0</b></span>\n          </div>\n        </div>\n\n        <div class=\"kpi-card\">\n          <div class=\"kpi-head\">\n            <span class=\"kpi-label\">Расходы на ИИ</span>\n            <span class=\"kpi-badge badge-green\" id=\"ai-m-cost-rub\">~0.00 ₽</span>\n          </div>\n          <div class=\"kpi-value\" id=\"ai-m-cost-usd\">$0.00000</div>\n          <div class=\"kpi-footer\">\n            <span>По тарифам Google Gemini</span>\n          </div>\n        </div>\n\n        <div class=\"kpi-card\">\n          <div class=\"kpi-head\">\n            <span class=\"kpi-label\">Использовано токенов</span>\n            <span class=\"kpi-badge badge-blue\" id=\"ai-m-tokens-total\">0</span>\n          </div>\n          <div class=\"kpi-value\" id=\"ai-m-tokens-k\">0k</div>\n          <div class=\"kpi-footer\">\n            <span>Вход: <b id=\"ai-m-tokens-prompt\">0</b> · Выход: <b id=\"ai-m-tokens-cand\">0</b></span>\n          </div>\n        </div>\n\n        <div class=\"kpi-card\">\n          <div class=\"kpi-head\">\n            <span class=\"kpi-label\">Активная модель</span>\n            <span class=\"kpi-badge badge-green\">АКТИВНА</span>\n          </div>\n          <div class=\"kpi-value\" style=\"font-size:18px;\" id=\"ai-m-model\">Gemini 3.6 Flash</div>\n          <div class=\"kpi-footer\">\n            <span>Статус: <b style=\"color:#059669;\">Подключено (API)</b></span>\n          </div>\n        </div>\n      </div>\n\n      <!-- AI Model Selector Card -->\n      <div class=\"card\" style=\"margin-bottom: 22px;\">\n        <div class=\"card-head\">\n          <div class=\"card-title\">\n            <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><rect x=\"3\" y=\"11\" width=\"18\" height=\"10\" rx=\"2\"/><circle cx=\"12\" cy=\"5\" r=\"2\"/><path d=\"M12 7v4\"/></svg>\n            <span>Выбор и настройка модели искусственного интеллекта</span>\n          </div>\n          <button class=\"btn-action btn-primary\" id=\"save-ai-model-btn\">\n            <svg viewBox=\"0 0 24 24\" width=\"15\" height=\"15\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><path d=\"M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z\"/><polyline points=\"17 21 17 13 7 13 7 21\"/><polyline points=\"7 3 7 8 15 8\"/></svg>\n            <span>Применить модель</span>\n          </button>\n        </div>\n        <p style=\"font-size:13px; color:var(--text-muted); margin-bottom:16px; line-height:1.5;\">\n          Если текущая модель отвечает медленно или испытывает сбои, вы можете мгновенно переключиться на резервную модель. Настройка применяется сразу для всех пользователей приложения без пересборки.\n        </p>\n\n        <div style=\"display:grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap:16px;\">\n          <div>\n            <label class=\"form-label\" style=\"margin-bottom:6px;\">Основная модель генерации</label>\n            <select id=\"ai-model-select\" class=\"sidebar-select\" style=\"padding:10px 12px; font-size:13.5px; font-weight:600;\">\n              <option value=\"gemini-3.6-flash\">Gemini 3.6 Flash (Хит, супер-быстрый — $0.10/1M)</option>\n              <option value=\"gemini-2.5-flash\">Gemini 2.5 Flash ($0.10/1M)</option>\n              <option value=\"gemini-1.5-flash\">Gemini 1.5 Flash (Эконом — $0.075/1M)</option>\n              <option value=\"gemini-2.5-pro\">Gemini 2.5 Pro (Глубокое мышление — $1.25/1M)</option>\n            </select>\n          </div>\n          <div style=\"background:#fafbfc; border:1px solid var(--card-border); border-radius:10px; padding:12px 16px; display:flex; flex-direction:column; justify-content:center;\">\n            <div style=\"font-size:12px; font-weight:600; color:var(--text); margin-bottom:4px;\">Тарификация Google AI Studio</div>\n            <div style=\"font-size:12px; color:var(--text-muted); line-height:1.4;\">Первые 15 запросов в минуту бесплатны навсегда. Далее от $0.10 за 1 миллион токенов.</div>\n          </div>\n        </div>\n      </div>\n\n      <!-- Live Playground / Tester -->\n      <div class=\"card\">\n        <div class=\"card-head\">\n          <div class=\"card-title\">\n            <svg viewBox=\"0 0 24 24\" width=\"18\" height=\"18\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><path d=\"M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z\"/></svg>\n            <span>Тестирование ИИ в реальном времени (Live Playground)</span>\n          </div>\n        </div>\n        <div style=\"display:flex; gap:10px; margin-bottom:14px;\">\n          <input type=\"text\" id=\"ai-test-prompt\" class=\"form-input\" placeholder=\"Введите вопрос для проверки ИИ...\" value=\"Разрешен ли разворот на пешеходном переходе?\" style=\"font-size:13.5px;\">\n          <button class=\"btn-action btn-primary\" id=\"ai-test-send-btn\" style=\"flex-shrink:0;\">Отправить</button>\n        </div>\n        <div id=\"ai-test-result-box\" style=\"background:#fafbfc; border:1px solid var(--card-border); border-radius:10px; padding:16px; font-size:13.5px; line-height:1.55; color:var(--text); min-height:80px; white-space:pre-wrap;\">Здесь отобразится ответ нейросети...</div>\n      </div>\n    </div>'''

target_modal_dialog = r'\n\n    <!-- Promo Card Modal Dialog -->'
text = text.replace(target_modal_dialog, escaped_views_html + target_modal_dialog, 1)

# 5. Add JS Client Modules (Users + AI)
escaped_modules_js = r'''\n// ────────────────────── Users Management Module ──────────────────────\nVIEW_TITLES.users = \"Учет пользователей и Премиум\";\n\nasync function loadUsersList() {\n  const container = document.getElementById(\"table-users\");\n  const countEl = document.getElementById(\"users-count\");\n  container.innerHTML = \"<tr><td colspan=\\\"6\\\" style=\\\"text-align:center;color:var(--text-muted);padding:20px;\\\">Загрузка...</td></tr>\";\n  try {\n    const res = await fetch(\"/api/admin/users\");\n    if (res.status === 401) { checkAuthAndLoad(); return; }\n    const data = await res.json();\n    const users = data.users || [];\n    countEl.innerText = users.length;\n    if (!users.length) {\n      container.innerHTML = \"<tr><td colspan=\\\"6\\\" style=\\\"text-align:center;color:var(--text-muted);padding:20px;\\\">Пользователей пока нет</td></tr>\";\n      return;\n    }\n    container.innerHTML = users.map(u => {\n      const isPrem = u.isPremium;\n      const premBadge = isPrem\n        ? \"<span class=\\\"kpi-badge badge-green\\\">PREMIUM</span>\"\n        : \"<span class=\\\"tag-badge\\\">FREE</span>\";\n      const expText = u.premiumExpiresAt\n        ? formatEventTime(u.premiumExpiresAt)\n        : (isPrem ? \"Бессрочно\" : \"—\");\n      const lastSeen = formatEventTime(u.lastSeenAt);\n      const btnAction = isPrem\n        ? \"<button class=\\\"btn-action\\\" style=\\\"color:var(--danger);border-color:#fecaca;padding:4px 8px;font-size:11.5px;\\\" onclick=\\\"revokeUserPremium('\" + u.id + \"')\\\">Забрать Премиум</button>\"\n        : \"<button class=\\\"btn-action btn-primary\\\" style=\\\"padding:4px 8px;font-size:11.5px;\\\" onclick=\\\"grantUserPremium('\" + u.id + \"')\\\">+ Выдать Премиум</button>\";\n      return \"<tr>\"\n        + \"<td><div style=\\\"font-weight:600;color:var(--text);\\\">\" + (u.name || \"Без имени\") + \"</div><div style=\\\"font-size:11px;color:var(--text-muted);font-family:monospace;\\\">\" + u.id + (u.email ? \" · \" + u.email : \"\") + \"</div></td>\"\n        + \"<td><span class=\\\"tag-badge\\\">\" + (u.provider || \"guest\") + \"</span></td>\"\n        + \"<td>\" + premBadge + \"</td>\"\n        + \"<td>\" + expText + \"</td>\"\n        + \"<td>\" + lastSeen + \"</td>\"\n        + \"<td>\" + btnAction + \"</td>\"\n        + \"</tr>\";\n    }).join(\"\");\n  } catch (err) {\n    container.innerHTML = \"<tr><td colspan=\\\"6\\\" style=\\\"color:var(--danger);text-align:center;padding:20px;\\\">Ошибка: \" + err.message + \"</td></tr>\";\n  }\n}\n\nwindow.grantUserPremium = async function(userId) {\n  const days = prompt(\"На сколько дней выдать Премиум? (введите 0 или оставьте пустым для бессрочного)\", \"30\");\n  if (days === null) return;\n  const isLifetime = (days.trim() === \"0\" || days.trim() === \"\");\n  try {\n    const r = await fetch(\"/api/admin/users/grant-premium\", {\n      method: \"POST\",\n      headers: { \"content-type\": \"application/json\" },\n      body: JSON.stringify({ userId, days: isLifetime ? 0 : parseInt(days, 10), isLifetime })\n    });\n    if (r.ok) {\n      alert(\"Премиум успешно выдан!\");\n      loadUsersList();\n    } else {\n      alert(\"Ошибка: \" + r.status);\n    }\n  } catch (e) {\n    alert(\"Ошибка сети: \" + e);\n  }\n};\n\nwindow.revokeUserPremium = async function(userId) {\n  if (!confirm(\"Забрать Премиум у пользователя?\")) return;\n  try {\n    const r = await fetch(\"/api/admin/users/revoke-premium\", {\n      method: \"POST\",\n      headers: { \"content-type\": \"application/json\" },\n      body: JSON.stringify({ userId })\n    });\n    if (r.ok) {\n      alert(\"Премиум отозван!\");\n      loadUsersList();\n    } else {\n      alert(\"Ошибка: \" + r.status);\n    }\n  } catch (e) {\n    alert(\"Ошибка сети: \" + e);\n  }\n};\n\ndocument.getElementById(\"refresh-users-btn\").addEventListener(\"click\", loadUsersList);\n\n// ────────────────────── AI Management Module ──────────────────────\nVIEW_TITLES.ai = \"Управление искусственным интеллектом и расходами\";\n\nasync function loadAiStats() {\n  try {\n    const res = await fetch(\"/api/admin/ai/stats\");\n    if (res.status === 401) { checkAuthAndLoad(); return; }\n    if (!res.ok) return;\n    const data = await res.json();\n    const s = data.stats;\n\n    document.getElementById(\"ai-m-total\").innerText = (s.totalRequests || 0).toLocaleString();\n    document.getElementById(\"ai-m-today\").innerText = (s.todayRequests || 0).toLocaleString();\n    document.getElementById(\"ai-m-cost-usd\").innerText = \"$\" + (s.costUsd || 0).toFixed(5);\n    document.getElementById(\"ai-m-cost-rub\").innerText = \"~\" + (s.costRub || 0) + \" ₽\";\n\n    const totalK = ((s.totalTokens || 0) / 1000).toFixed(1);\n    document.getElementById(\"ai-m-tokens-k\").innerText = totalK + \"k\";\n    document.getElementById(\"ai-m-tokens-total\").innerText = (s.totalTokens || 0).toLocaleString();\n    document.getElementById(\"ai-m-tokens-prompt\").innerText = (s.promptTokens || 0).toLocaleString();\n    document.getElementById(\"ai-m-tokens-cand\").innerText = (s.candidateTokens || 0).toLocaleString();\n\n    document.getElementById(\"ai-m-model\").innerText = s.activeModel;\n\n    const select = document.getElementById(\"ai-model-select\");\n    if (select) {\n      select.value = s.activeModel;\n    }\n  } catch (err) {\n    console.error(\"loadAiStats error:\", err);\n  }\n}\n\ndocument.getElementById(\"save-ai-model-btn\").addEventListener(\"click\", async () => {\n  const model = document.getElementById(\"ai-model-select\").value;\n  const btn = document.getElementById(\"save-ai-model-btn\");\n  btn.innerText = \"Сохраняю...\";\n  try {\n    const r = await fetch(\"/api/admin/ai/config\", {\n      method: \"POST\",\n      headers: { \"content-type\": \"application/json\" },\n      body: JSON.stringify({ model })\n    });\n    if (r.ok) {\n      btn.innerText = \"Успешно сохранено!\";\n      setTimeout(() => { btn.innerText = \"Применить модель\"; }, 1800);\n      loadAiStats();\n    } else {\n      alert(\"Ошибка при сохранении модели: \" + r.status);\n      btn.innerText = \"Применить модель\";\n    }\n  } catch (e) {\n    alert(\"Ошибка сети: \" + e);\n    btn.innerText = \"Применить модель\";\n  }\n});\n\ndocument.getElementById(\"ai-test-send-btn\").addEventListener(\"click\", async () => {\n  const prompt = document.getElementById(\"ai-test-prompt\").value.trim();\n  if (!prompt) return;\n  const box = document.getElementById(\"ai-test-result-box\");\n  const btn = document.getElementById(\"ai-test-send-btn\");\n  btn.innerText = \"Генерация...\";\n  box.innerText = \"ИИ генерирует ответ...\";\n  try {\n    const r = await fetch(\"/api/admin/ai/test\", {\n      method: \"POST\",\n      headers: { \"content-type\": \"application/json\" },\n      body: JSON.stringify({ prompt })\n    });\n    const d = await r.json();\n    if (d.ok) {\n      box.innerText = \"[\" + d.model + \"]:\\n\\n\" + d.reply;\n    } else {\n      box.innerText = \"Ошибка: \" + (d.error || \"не удалось получить ответ\");\n    }\n  } catch (e) {\n    box.innerText = \"Ошибка сети: \" + e;\n  } finally {\n    btn.innerText = \"Отправить\";\n  }\n});\n'''

# Update nav handler in ADMIN_CLIENT_JS
old_nav_views = r'document.getElementById(\"ads-view\").style.display = currentFeature === \"ads\" ? \"block\" : \"none\";'
new_nav_views = r'document.getElementById(\"ads-view\").style.display = currentFeature === \"ads\" ? \"block\" : \"none\";\n    document.getElementById(\"users-view\").style.display = currentFeature === \"users\" ? \"block\" : \"none\";\n    document.getElementById(\"ai-view\").style.display = currentFeature === \"ai\" ? \"block\" : \"none\";'

old_nav_loads = r'else if (currentFeature === \"ads\") loadAdsConfig();'
new_nav_loads = r'else if (currentFeature === \"ads\") loadAdsConfig();\n    else if (currentFeature === \"users\") loadUsersList();\n    else if (currentFeature === \"ai\") loadAiStats();'

text = text.replace(old_nav_views, new_nav_views, 1)
text = text.replace(old_nav_loads, new_nav_loads, 1)

js_end_marker = r'\n// ────────────────────── Ads & Promo Management ──────────────────────'
text = text.replace(js_end_marker, escaped_modules_js + js_end_marker, 1)

with open('server/install-notifier/worker.js', 'w', encoding='utf-8') as f:
    f.write(text)

print('Full worker.js patched and written successfully!')
