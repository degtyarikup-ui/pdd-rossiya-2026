// Cloudflare Worker: уведомления о новых установках ПДД-приложения в Telegram
// + ежемесячная сводка (1-го числа). Токен бота — в секрете воркера (BOT_TOKEN),
// в приложение не попадает.
//
// Секреты (wrangler secret put <ИМЯ>):
//   BOT_TOKEN     — токен бота от @BotFather
//   CHAT_ID       — id чата/группы
//   SHARED_SECRET — (опц.) защита эндпоинта; если задан — приложение шлёт его
//                   в заголовке x-install-secret.
// KV (namespace INSTALLS): счётчик #N, дедуп по install_id, помесячные счётчики.
// Cron (см. wrangler.toml, "0 6 1 * *"): 1-го числа в 09:00 МСК — итоги месяца.

const FLAGS = { ru: '🇷🇺', by: '🇧🇾', rs: '🇷🇸' };

// CORS: веб-версия шлёт запрос из браузера с другого домена (pdd-drive.ru →
// воркер). Без этих заголовков браузер блокирует cross-origin POST.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type, x-install-secret',
  'Access-Control-Max-Age': '86400',
};

function esc(s) {
  return String(s ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

// Боты/краулеры/сканеры/HTTP-библиотеки по User-Agent. Применяется ТОЛЬКО к
// вебу — у приложения UA от Dart (dart:io), его фильтровать нельзя.
const BOT_UA_RE =
  /bot|crawl|spider|slurp|headless|phantom|puppeteer|playwright|selenium|webdriver|lighthouse|pagespeed|gtmetrix|pingdom|uptime|statuscake|monitor|preview|scan|python-requests|python-urllib|curl\/|wget|go-http|okhttp|java\/|apache-httpclient|axios|node-fetch|libwww|httpx|facebookexternalhit|whatsapp|discord|slack|twitter|linkedin|bingpreview|yandex|petal|ahrefs|semrush|mj12|dotbot|dataforseo|censys|masscan|zgrab|nuclei|google/i;

function isWebRequest(body) {
  return body.source === 'Web' || body.platform === 'web';
}

// Семейство ОС по UA-заголовку запроса.
function uaOsFamily(ua) {
  if (/android/i.test(ua)) return 'android';
  if (/iphone|ipad|ipod/i.test(ua)) return 'ios';
  if (/windows/i.test(ua)) return 'windows';
  if (/mac os x/i.test(ua)) return 'mac';
  if (/x11|linux/i.test(ua)) return 'linux';
  return '';
}

// Семейство ОС по navigator.platform (приходит в поле os веб-клиента).
function platformOsFamily(p) {
  p = String(p || '').toLowerCase();
  if (p.includes('iphone') || p.includes('ipad')) return 'ios';
  if (p.includes('armv') || p.includes('aarch') || p.includes('android')) return 'android';
  if (p.includes('win')) return 'windows';
  if (p.includes('mac')) return 'mac';
  if (p.includes('linux')) return 'linux';
  return '';
}

function looksLikeBot(request, body) {
  const ua = request.headers.get('user-agent') || '';
  if (ua.length < 15) return true; // «браузер» без нормального UA — почти всегда бот
  if (BOT_UA_RE.test(ua)) return true;
  if (body.webdriver === true) return true;
  // Десктопный Linux (X11; Linux x86_64) — для мобильной РФ-аудитории это почти
  // всегда headless-краулер, маскирующийся под обычный Chrome (реальные юзеры —
  // телефоны Android/iOS; Windows/Mac-десктоп при этом НЕ трогаем).
  if (/x11|linux x86_64/i.test(ua)) return true;
  // Рассогласование ОС в UA-заголовке и в navigator.platform — верный признак
  // спуфинга (боты подделывают их по-разному: напр. UA=Windows, platform=Linux).
  const uaOs = uaOsFamily(ua);
  const navOs = platformOsFamily(body.os);
  if (uaOs && navOs && uaOs !== navOs) return true;
  return false;
}

// Временный диагностический лог последних веб-UA (для проверки фильтра).
async function logUa(env, ua, bot) {
  if (!env.INSTALLS) return;
  try {
    const raw = await env.INSTALLS.get('ualog');
    const arr = raw ? JSON.parse(raw) : [];
    arr.push({ ua: String(ua).slice(0, 220), bot });
    while (arr.length > 25) arr.shift();
    await env.INSTALLS.put('ualog', JSON.stringify(arr));
  } catch (_) {}
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', ...CORS_HEADERS },
  });
}

// Ключ месяца по московскому времени: "YYYY-MM".
function mskMonthKey(d) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Moscow',
    year: 'numeric',
    month: '2-digit',
  }).formatToParts(d);
  const y = parts.find((p) => p.type === 'year').value;
  const m = parts.find((p) => p.type === 'month').value;
  return `${y}-${m}`;
}

function mskTime(d) {
  return new Intl.DateTimeFormat('ru-RU', {
    timeZone: 'Europe/Moscow',
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(d);
}

// Регион из locale ("ru-RU" → "RU", "en-US" → "US"); без региона — весь locale.
function regionFromLocale(locale) {
  if (!locale) return null;
  const parts = String(locale).split(/[-_]/);
  return parts.length > 1 ? parts[parts.length - 1].toUpperCase() : String(locale);
}

// Осмысленный источник для показа: настоящие магазины (Google Play, RuStore,
// App Store, TestFlight и т.п.) — показываем. Технические установщики (сырой
// пакет com.android.shell = adb, com.apple.testflight и пр.), 'unknown',
// sideload, 'Web' — скрываем (это либо шум разработки, либо роль уже у иконки).
function displaySource(source) {
  if (!source) return null;
  if (source === 'Web' || source === 'unknown') return null;
  if (source.includes('.')) return null; // сырой пакет-установщик (com.*.*)
  const low = source.toLowerCase();
  if (low.includes('sideload') || low.includes('неизвест')) return null;
  return source;
}

// Магазин по пакету-установщику. Клиент уже пытается это отобразить, но его
// таблица регистрозависима (реальный installerStore — 'com.apple.testflight'),
// поэтому нормализуем ещё и на сервере — чинится без пересборки приложения.
const STORE_BY_PACKAGE = {
  'com.android.vending': 'Google Play',
  'ru.vk.store': 'RuStore',
  'com.apple.appstore': 'App Store',
  'com.apple.testflight': 'TestFlight',
  'com.amazon.venezia': 'Amazon',
  'com.huawei.appmarket': 'AppGallery',
  'com.sec.android.app.samsungapps': 'Galaxy Store',
  'com.xiaomi.mipicks': 'Xiaomi GetApps',
  'com.xiaomi.market': 'Xiaomi GetApps',
};
const KNOWN_STORE_NAMES = new Set(
  Object.values(STORE_BY_PACKAGE).map((s) => s.toLowerCase()),
);

/// Возвращает имя магазина или null, если установка НЕ из магазина
/// (adb, sideload, эмулятор, Firebase Test Lab).
function normalizeStore(source) {
  if (!source) return null;
  const low = String(source).trim().toLowerCase();
  if (STORE_BY_PACKAGE[low]) return STORE_BY_PACKAGE[low];
  if (KNOWN_STORE_NAMES.has(low)) return String(source).trim();
  return null;
}

// Эмуляторы и тестовые стенды по имени устройства.
function looksLikeEmulator(device) {
  return /sdk_gphone|emulator|generic|android sdk|simulator/i.test(
    String(device || ''),
  );
}

// Иконка по платформе входа: 🍎 iOS, 🤖 Android, 🌐 веб-версия.
function deviceEmoji(b) {
  const p = String(b.platform || '').toLowerCase();
  if (p === 'ios') return '🍎';
  if (p === 'android') return '🤖';
  if (p === 'web') return '🌐';
  if (b.source === 'Web') return '🌐'; // запасной вариант, если platform не пришла
  return '📱';
}

export function buildMessage(b, num) {
  const flag = FLAGS[b.country] || '🌍';
  const who = num != null
    ? `<b>Пользователь #${num}</b>`
    : b.install_id
      ? `<code>${esc(String(b.install_id).slice(0, 8))}</code>`
      : '';
  // Иконка = платформа входа (iOS/Android/веб). «Обновившиеся» до сюда не доходят.
  const header = `${deviceEmoji(b)} ${flag} ${who}`.trim();

  // Источник показываем только осмысленный (магазин). Технические установщики
  // (adb/TestFlight и пр.) и 'Web' скрываем — платформу уже показывает иконка.
  const parts = [];
  const src = displaySource(b.source);
  if (src) parts.push(src);
  if (b.device) parts.push(b.device);
  if (b.os) parts.push(b.os);
  const deviceLine = parts.map(esc).join(' • ');
  const region = regionFromLocale(b.locale);

  const lines = [
    header,
    '',
    deviceLine ? `- ${deviceLine}` : null,
    b.version ? `- v${esc(b.version)}` : null,
    region ? `- ${esc(region)}` : null,
    '',
    `🕓 ${mskTime(new Date())} MSK`,
  ].filter((l) => l !== null);

  return lines.join('\n');
}

// ───────────────────── Жалобы на вопросы из приложения ─────────────────────
// Пользователь пишет текст прямо в приложении (кнопка-флажок в карточке
// вопроса), клиент шлёт сюда {kind:'report', ...}. Раньше это был mailto —
// но почтовый клиент есть не у всех, и до отправки доходили единицы.

export function buildReportMessage(b) {
  const flag = FLAGS[b.country] || '🌍';
  const meta = [];
  if (b.ticket) meta.push(`билет ${esc(b.ticket)}`);
  if (b.topic) meta.push(esc(b.topic));
  if (b.mode) meta.push(esc(b.mode));

  const lines = [
    `🚩 ${flag} <b>Жалоба на вопрос</b>`,
    '',
    esc(String(b.message || '').slice(0, 1500)),
    '',
    meta.length ? `- ${meta.join(' • ')}` : null,
    b.question_id ? `- <code>${esc(b.question_id)}</code>` : null,
    // Текст вопроса — чтобы найти его глазами, не лазая в JSON по id.
    b.question_text ? `- «${esc(String(b.question_text).slice(0, 200))}»` : null,
    b.version ? `- v${esc(b.version)} • ${esc(b.platform || '')}` : null,
    '',
    `🕓 ${mskTime(new Date())} MSK`,
  ].filter((l) => l !== null);

  return lines.join('\n');
}

/// Простой антиспам: не больше N жалоб с одного устройства в сутки.
/// Без этого один недовольный человек (или бот, узнавший адрес воркера)
/// зальёт чат сотнями сообщений.
const REPORTS_PER_DAY = 10;

async function reportAllowed(env, installId) {
  if (!env.INSTALLS || !installId) return true;
  const day = new Date().toISOString().slice(0, 10);
  const key = `rep:${installId}:${day}`;
  const used = parseInt((await env.INSTALLS.get(key)) || '0', 10);
  if (used >= REPORTS_PER_DAY) return false;
  // Ключ живёт двое суток — счётчик сам исчезает, чистить не нужно.
  await env.INSTALLS.put(key, String(used + 1), { expirationTtl: 172800 });
  return true;
}

export function buildMonthlyMessage(monthKey, s) {
  const lines = [
    `📊 <b>Итоги месяца: ${monthKey}</b>`,
    `🆕 Новых установок: ${s.fresh}`,
  ];
  if (s.sources && s.sources.length) {
    lines.push('', '<b>Откуда пришли:</b>');
    for (const src of s.sources) {
      lines.push(`🏬 ${esc(src.name)}: ${src.count}`);
    }
  }
  lines.push('', `∑ Всего пользователей за всё время: ${s.grandTotal}`);
  return lines.join('\n');
}

async function kvIncr(env, key) {
  const cur = parseInt((await env.INSTALLS.get(key)) || '0', 10);
  const next = cur + 1;
  await env.INSTALLS.put(key, String(next));
  return next;
}

// Выдаёт порядковый номер установки. Идемпотентно по install_id.
async function assignNumber(env, installId) {
  if (!env.INSTALLS) return { value: null, isNew: true };
  if (installId) {
    const existing = await env.INSTALLS.get('id:' + installId);
    if (existing !== null) return { value: parseInt(existing, 10), isNew: false };
  }
  const next = await kvIncr(env, 'counter');
  if (installId) await env.INSTALLS.put('id:' + installId, String(next));
  return { value: next, isNew: true };
}

// ───────────────────────── Отзывы из сторов ─────────────────────────
// RuStore отдаёт отзывы прямо в публичной странице приложения — в разметке
// JSON-LD (schema.org Review). Ключей/токенов не требуется.
const RUSTORE_APP_URL = 'https://www.rustore.ru/catalog/app/ru.pdd.pdd_app';

/// Достаёт из HTML все JSON-LD блоки и собирает из них отзывы.
function extractJsonLdReviews(html) {
  const out = [];
  const re = /<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html)) !== null) {
    let data;
    try {
      data = JSON.parse(m[1]);
    } catch {
      continue;
    }
    // Рекурсивно ищем массивы review в любой глубине документа.
    const walk = (node) => {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) return node.forEach(walk);
      if (Array.isArray(node.review)) {
        for (const r of node.review) {
          if (r && r.reviewBody) {
            out.push({
              author: r.author?.name || 'Аноним',
              text: String(r.reviewBody),
              date: r.datePublished || '',
              rating: Number(r.reviewRating?.ratingValue) || null,
            });
          }
        }
      }
      for (const v of Object.values(node)) walk(v);
    };
    walk(data);
  }
  return out;
}

function reviewKey(store, r) {
  // Автор + дата — стабильный идентификатор: правка отзыва меняет дату,
  // и такой отзыв придёт снова (это желаемое поведение).
  return `rev:${store}:${r.author}:${r.date}`.slice(0, 400);
}

function buildReviewMessage(store, storeIcon, r) {
  const stars = r.rating
    ? '⭐️'.repeat(r.rating) + '☆'.repeat(Math.max(0, 5 - r.rating))
    : '';
  const when = r.date
    ? new Intl.DateTimeFormat('ru-RU', {
        timeZone: 'Europe/Moscow',
        dateStyle: 'short',
      }).format(new Date(r.date))
    : '';
  return [
    `${storeIcon} <b>Новый отзыв — ${esc(store)}</b>`,
    stars ? `${stars}` : null,
    '',
    `<b>${esc(r.author)}</b>${when ? ` · ${when}` : ''}`,
    esc(r.text),
  ]
    .filter((l) => l !== null)
    .join('\n');
}

/// Проверяет новые отзывы и шлёт их в чат. Дедуп — по ключу в KV.
async function pollReviews(env) {
  if (!env.INSTALLS) return;
  let html;
  try {
    const r = await fetch(RUSTORE_APP_URL, {
      headers: {
        'user-agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        'accept-language': 'ru-RU,ru;q=0.9',
      },
    });
    if (!r.ok) return;
    html = await r.text();
  } catch {
    return;
  }

  const reviews = extractJsonLdReviews(html);
  for (const rev of reviews.slice(0, 20)) {
    const key = reviewKey('rustore', rev);
    if ((await env.INSTALLS.get(key)) !== null) continue; // уже отправляли
    await env.INSTALLS.put(key, '1');
    await sendTelegram(env, buildReviewMessage('RuStore', '🛒', rev));
  }
}

async function sendTelegram(env, text) {
  const url = `https://api.telegram.org/bot${env.BOT_TOKEN}/sendMessage`;
  return fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      chat_id: env.CHAT_ID,
      text,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
    }),
  });
}

export default {
  async fetch(request, env) {
    // Preflight от браузера (веб-версия) — отвечаем с CORS-заголовками.
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    if (request.method === 'GET') {
      const url = new URL(request.url);
      // Ручной прогон проверки отзывов (то же, что делает почасовой крон).
      if (url.searchParams.get('reviews') === 'check') {
        await pollReviews(env);
        return jsonResponse({ ok: true, checked: 'reviews' });
      }
      return new Response('pdd-install-notifier: ok', { status: 200 });
    }
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'method not allowed' }, 405);
    }
    if (!env.BOT_TOKEN || !env.CHAT_ID) {
      return jsonResponse({ error: 'server not configured' }, 500);
    }
    if (env.SHARED_SECRET) {
      const got = request.headers.get('x-install-secret');
      if (got !== env.SHARED_SECRET) {
        return jsonResponse({ error: 'forbidden' }, 403);
      }
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return jsonResponse({ error: 'invalid json' }, 400);
    }

    // Жалоба на вопрос. Обрабатываем ПЕРВОЙ, до всех фильтров установок:
    // жалоба должна доходить с любой платформы (включая веб) и независимо
    // от того, из магазина ли поставлено приложение.
    if (body.kind === 'report') {
      const text = String(body.message || '').trim();
      if (!text) return jsonResponse({ error: 'empty message' }, 400);

      if (!(await reportAllowed(env, body.install_id))) {
        // Отвечаем 200: для пользователя это выглядит как «отправлено», и он
        // не начинает долбить кнопку. В чат при этом ничего не летит.
        return jsonResponse({ ok: true, throttled: true });
      }

      const tg = await sendTelegram(env, buildReportMessage(body));
      if (!tg.ok) {
        const detail = await tg.text();
        return jsonResponse({ error: 'telegram failed', detail }, 502);
      }
      return jsonResponse({ ok: true, reported: true });
    }

    // Трекаем только новых пользователей: обновившихся (уже стоявших раньше)
    // молча игнорируем — не занимают номер, не попадают в статистику/чат.
    // Клиент получает 2xx и помечает себя «сообщено», чтобы не слать повторно.
    if (body.kind === 'update') {
      return jsonResponse({ ok: true, ignored: true });
    }

    // Веб-пинги ОТКЛЮЧЕНЫ (2026-07-19): публичный домен приносит практически
    // только ботов/краулеров, а не реальную аудиторию (веб не рекламируется).
    // Трекаем ТОЛЬКО установки приложения (Google Play / RuStore / App Store —
    // их ботом не накрутить). Фильтрующие функции (looksLikeBot, logUa и т.п.)
    // оставлены в файле — чтобы ВКЛЮЧИТЬ веб обратно, замени этот return на блок
    // фильтрации: if (looksLikeBot(request, body)) { …botcount++…; return bot }.
    if (isWebRequest(body)) {
      return jsonResponse({ ok: true, web: true, ignored: true });
    }

    // Считаем ТОЛЬКО установки из настоящих магазинов. Всё остальное — adb,
    // sideload, эмуляторы и автотесты сторов (Google во время ревью гоняет
    // сборку в Firebase Test Lab: те же модели устройств с разными локалями,
    // по одному запуску в минуту) — молча игнорируем, иначе счётчик
    // накручивается десятками несуществующих «пользователей».
    const store = normalizeStore(body.source);
    if (!store || looksLikeEmulator(body.device)) {
      if (env.INSTALLS) await kvIncr(env, 'skipped_nonstore');
      return jsonResponse({ ok: true, ignored: true, reason: 'not-a-store-install' });
    }
    // Показываем нормализованное имя магазина (чинит сырой com.apple.testflight).
    body.source = store;

    const number = await assignNumber(env, body.install_id);

    // Повтор того же install_id — номер уже выдан, в чат не дублируем.
    if (!number.isNew) {
      return jsonResponse({ ok: true, duplicate: true, number: number.value });
    }

    // Помесячные счётчики (для сводки 1-го числа): новые + по источнику.
    if (env.INSTALLS) {
      const mk = mskMonthKey(new Date());
      await kvIncr(env, `m:${mk}:new`);
      const source = String(body.source || 'unknown').slice(0, 60);
      await kvIncr(env, `m:${mk}:src:${source}`);
    }

    const tg = await sendTelegram(env, buildMessage(body, number.value));
    if (!tg.ok) {
      const detail = await tg.text();
      return jsonResponse({ error: 'telegram failed', detail }, 502);
    }
    return jsonResponse({ ok: true, number: number.value });
  },

  // Крон срабатывает 1-го числа — отчитываемся за предыдущий (завершившийся) месяц.
  async scheduled(event, env, ctx) {
    if (!env.BOT_TOKEN || !env.CHAT_ID || !env.INSTALLS) return;

    // Частый крон — проверка новых отзывов в сторах.
    // Месячный ('0 6 1 * *') — сводка по установкам.
    if (event.cron !== '0 6 1 * *') {
      ctx.waitUntil(pollReviews(env));
      return;
    }
    const fireTime = event.scheduledTime ? new Date(event.scheduledTime) : new Date();
    // Отступаем на несколько дней назад от 1-го числа → гарантированно попадаем
    // в предыдущий месяц, затем берём его ключ по МСК.
    const back = new Date(fireTime.getTime() - 5 * 24 * 60 * 60 * 1000);
    const mk = mskMonthKey(back);

    const num = async (k) => parseInt((await env.INSTALLS.get(k)) || '0', 10);

    // Разбивка по источникам за месяц (ключи m:YYYY-MM:src:<источник>).
    // Сырые технические установщики (com.android.shell = adb, com.apple.testflight,
    // симулятор и пр.) в сводке не показываем поимённо — сводим в «Другое».
    const srcPrefix = `m:${mk}:src:`;
    const listed = await env.INSTALLS.list({ prefix: srcPrefix });
    const merged = new Map();
    for (const k of listed.keys) {
      const raw = k.name.slice(srcPrefix.length);
      // 'Web' — осмысленный канал для сводки (в отличие от строки сообщения,
      // где его роль играет иконка 🌐), остальное — через displaySource().
      const name = raw === 'Web' ? 'Web' : displaySource(raw) || 'Другое';
      merged.set(name, (merged.get(name) || 0) + (await num(k.name)));
    }
    const sources = [...merged].map(([name, count]) => ({ name, count }));
    sources.sort((a, b) => b.count - a.count);

    const stats = {
      fresh: await num(`m:${mk}:new`),
      grandTotal: await num('counter'),
      sources,
    };
    ctx.waitUntil(sendTelegram(env, buildMonthlyMessage(mk, stats)));
  },
};
