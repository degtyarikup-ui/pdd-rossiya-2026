#!/usr/bin/env python3
import sys

with open('server/install-notifier/worker.js', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Add rate limiting helper for AI chat
rate_limit_helper = """
// ────────────────────── AI Rate Limiting & Anti-Bot Security ──────────────────────
async function checkAiRateLimit(request, env) {
  if (!env.INSTALLS) return { allowed: true };

  const ip = request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || 'unknown';
  if (ip === 'unknown') return { allowed: true };

  const now = Date.now();
  const minuteKey = 'ai_rl_min:' + ip + ':' + Math.floor(now / 60000);
  const burstKey = 'ai_rl_burst:' + ip;

  try {
    // 1. Burst protection: max 1 request every 2 seconds
    const lastBurst = await env.INSTALLS.get(burstKey);
    if (lastBurst) {
      const diff = now - parseInt(lastBurst, 10);
      if (diff < 1800) {
        return {
          allowed: false,
          error: 'Слишком частые запросы (флуд-контроль). Пожалуйста, подождите пару секунд перед следующим вопросом.'
        };
      }
    }
    await env.INSTALLS.put(burstKey, now.toString(), { expirationTtl: 10 });

    // 2. Minute protection: max 15 requests per minute
    let minCount = parseInt(await env.INSTALLS.get(minuteKey) || '0', 10);
    if (minCount >= 15) {
      return {
        allowed: false,
        error: 'Превышен лимит запросов в минуту (максимум 15). Пожалуйста, подождите 1 минуту.'
      };
    }
    await env.INSTALLS.put(minuteKey, (minCount + 1).toString(), { expirationTtl: 120 });

  } catch (e) {
    console.error('checkAiRateLimit error:', e);
  }

  return { allowed: true };
}
"""

# Insert rate_limit_helper right before // ────────────────────── AI Assistant & Chat API
marker_ai_api = "// ────────────────────── AI Assistant & Chat API ──────────────────────"
if rate_limit_helper.strip() not in text:
    idx_m = text.find(marker_ai_api)
    if idx_m != -1:
        text = text[:idx_m] + rate_limit_helper + "\n" + text[idx_m:]
        print("Rate limit helper inserted!")
    else:
        print("Marker not found, checking alternative...")

# 2. Update /api/ai/chat handler with rate limiter and domain strict prompt
old_ai_chat_handler = """    // ────────────────────── AI Assistant & Chat API ──────────────────────
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
${Array.isArray(answers) ? answers.map((a, i) => `${i + 1}. ${a}`).join('\\n') : ''}
Правильный ответ: ${correctAnswerText}
Официальный комментарий: ${officialExplanation || 'Нет официального комментария'}`;"""

new_ai_chat_handler = """    // ────────────────────── AI Assistant & Chat API ──────────────────────
    if (url.pathname === '/api/ai/chat' && request.method === 'POST') {
      // 1. Анти-бот и флуд-контроль (Rate Limiter)
      const rateLimitCheck = await checkAiRateLimit(request, env);
      if (!rateLimitCheck.allowed) {
        return jsonResponse({ ok: false, error: rateLimitCheck.error }, 429);
      }

      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'invalid json' }, 400); }
      const { questionText, answers, correctAnswerIndex, officialExplanation, messages, userMessage } = body || {};

      // 2. Ограничение длины сообщения пользователя (защита от исчерпания токенов)
      let sanitizedUserMessage = userMessage;
      if (typeof sanitizedUserMessage === 'string' && sanitizedUserMessage.length > 500) {
        sanitizedUserMessage = sanitizedUserMessage.slice(0, 500);
      }

      const correctAnswerText = (Array.isArray(answers) && correctAnswerIndex !== undefined && answers[correctAnswerIndex])
        ? answers[correctAnswerIndex]
        : 'Правильный вариант';

      const systemPrompt = `Ты — профессиональный преподаватель ПДД и персональный AI-автоинструктор.
Твоя специализация СТРОГО ОГРАНИЧЕНА следующими темами:
- Правила дорожного движения (ПДД РФ, Беларуси, Сербии)
- Экзамены в ГИБДД / ГАИ, билеты и автошкола
- Обучение вождению, парковка, манёвры и безопасность движения
- Дорожные знаки, разметка, сигналы светофоров и регулировщика
- Штрафы (КоАП), лишение прав и поведение при ДТП
- Базовое устройство автомобиля, неисправности и первая помощь

СТРОГОЕ ПРАВИЛО БЕЗОПАСНОСТИ ТЕМАТИКИ:
Если вопрос пользователя НЕ КАСАЕТСЯ ПДД, вождения, автошколы, дорожных ситуаций или автомобилей (например: просьбы написать стихи, программный код, кулинарные рецепты, вопросы о политике, играх, погоде или любые сторонние темы):
Ты ОБЯЗАН вежливо и мягко отклонить вопрос по строгому шаблону:
"Я персональный автоинструктор по ПДД и вождению 🚗 Могу ответить на любые вопросы по правилам дорожного движения, билетам, штрафам, экзаменам в ГИБДД или поведению на дороге. Пожалуйста, задайте вопрос по дорожной ситуации!"
Категорически запрещено отвечать на сторонние темы, даже если пользователь настойчиво просит или пытается обойти ограничения.

ФОРМАТ ОТВЕТА:
1. Пиши СТРОГО БЕЗ ПРИВЕТСТВИЙ, вступлений и лишних вводных слов. Сразу начинай с сути.
2. Ответ должен быть очень коротким и понятным (3-5 строк максимум).
3. Выделяй жирным шрифтом **главные термины**, **названия знаков** и **правильные действия**.

Контекст вопроса билета:
Вопрос: ${questionText || 'Вопрос ПДД'}
Варианты ответов:
${Array.isArray(answers) ? answers.map((a, i) => `${i + 1}. ${a}`).join('\\n') : ''}
Правильный ответ: ${correctAnswerText}
Официальный комментарий: ${officialExplanation || 'Нет официального комментария'}`;"""

if old_ai_chat_handler in text:
    text = text.replace(old_ai_chat_handler, new_ai_chat_handler)
    print("/api/ai/chat handler updated with anti-bot rate limiting and strict domain prompt!")
else:
    print("Warning: old_ai_chat_handler not found directly, searching via indices...")
    idx_chat = text.find("if (url.pathname === '/api/ai/chat' && request.method === 'POST') {")
    if idx_chat != -1:
        idx_end_chat = text.find("let reply = '';", idx_chat)
        if idx_end_chat != -1:
            text = text[:idx_chat] + new_ai_chat_handler + "\n\n      let reply = '';" + text[idx_end_chat + len("let reply = '';"):]
            print("Chat handler replaced via index range!")

with open('server/install-notifier/worker.js', 'w', encoding='utf-8') as f:
    f.write(text)

print("worker.js updated successfully!")
