// «Мои ссылки» админки: сохранённые отслеживаемые ссылки. Сама ссылка —
// адрес страницы + ?ref=<канал>_<метка>; статистика по ней — это счётчики
// кампании <метка> из day:* (визиты и переходы в магазин), их отдаёт
// /api/admin/stats. Здесь только список ссылок, одним ключом KV.

const KV_KEY = 'tracked_links';
const LIMIT = 200;
const TOKEN_RE = /^[a-z0-9-]{1,32}$/;
const CAMPAIGN_RE = /^[a-z0-9_-]{1,48}$/;
const PAGES = new Set([
  'https://pdd-drive.ru/',
  'https://pdd-drive.ru/links/',
  'https://pdd-drive.ru/go/gplay/',
  'https://pdd-drive.ru/go/rustore/',
  'https://pdd-drive.ru/go/appstore/',
  'https://pdd-drive.ru/go/web/',
  'https://pdd-drive.ru/go/rs-gplay/',
  'https://rs.pdd-drive.online/',
  'https://pdd-drive.online/',
]);

async function readLinks(env) {
  try {
    const raw = await env.INSTALLS.get(KV_KEY);
    const list = raw ? JSON.parse(raw) : [];
    return Array.isArray(list) ? list : [];
  } catch (_) { return []; }
}

export function linkUrl(link) {
  return link.page + '?ref=' + link.source + '_' + link.campaign;
}

export async function handleLinksAdmin(request, env, url, { verifyAdminAuth, jsonResponse }) {
  if (url.pathname !== '/api/admin/links') return null;
  if (!await verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
  if (!env.INSTALLS) return jsonResponse({ error: 'storage unavailable' }, 503);

  const links = await readLinks(env);
  if (request.method === 'GET') return jsonResponse({ ok: true, links });

  let body;
  try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }

  if (request.method === 'POST') {
    const source = String(body?.source || '').toLowerCase();
    const campaign = String(body?.campaign || '').toLowerCase();
    const page = String(body?.page || '');
    if (!TOKEN_RE.test(source)) return jsonResponse({ error: 'Канал: латиница и цифры' }, 400);
    if (!CAMPAIGN_RE.test(campaign) || campaign === 'none' || campaign === 'referrer') {
      return jsonResponse({ error: 'Метка: латиница, цифры, _ и -' }, 400);
    }
    if (!PAGES.has(page)) return jsonResponse({ error: 'Неизвестная страница' }, 400);
    // Статистика копится по метке, поэтому метка должна быть единственной.
    if (links.some(l => l.campaign === campaign)) return jsonResponse({ error: 'Такая метка уже есть — придумайте другую' }, 409);
    if (links.length >= LIMIT) return jsonResponse({ error: 'Слишком много ссылок' }, 400);
    const link = {
      id: crypto.randomUUID().slice(0, 8),
      source, campaign, page,
      title: String(body?.title || '').slice(0, 80),
      createdAt: new Date().toISOString(),
    };
    links.unshift(link);
    await env.INSTALLS.put(KV_KEY, JSON.stringify(links));
    return jsonResponse({ ok: true, link, links });
  }

  if (request.method === 'DELETE') {
    const id = String(body?.id || '');
    const next = links.filter(l => l.id !== id);
    if (next.length === links.length) return jsonResponse({ error: 'not found' }, 404);
    await env.INSTALLS.put(KV_KEY, JSON.stringify(next));
    return jsonResponse({ ok: true, links: next });
  }

  return jsonResponse({ error: 'method not allowed' }, 405);
}
