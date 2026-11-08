// Minimal public build input. Article bodies, titles and admin data stay private.
// Never use the fallback catalogue here: a missing KV must stop publication.

function validDay(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const day = new Date(value + 'T00:00:00.000Z');
  return Number.isFinite(day.getTime()) && day.toISOString().slice(0, 10) === value;
}

export function publicBlogSchedule(catalogue) {
  if (!Array.isArray(catalogue) || catalogue.length > 1000) throw new Error('invalid catalogue');
  const seen = new Set();
  const articles = catalogue.map(article => {
    if (!article || typeof article !== 'object' || Array.isArray(article)
      || typeof article.slug !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(article.slug)
      || article.slug.length > 200 || seen.has(article.slug)
      || !validDay(article.datePublished) || typeof article.published !== 'boolean') {
      throw new Error('invalid article schedule');
    }
    seen.add(article.slug);
    return { slug: article.slug, datePublished: article.datePublished, published: article.published };
  });
  return { schema: 1, complete: true, count: articles.length, articles };
}

export async function handlePublicBlogSchedule(request, env) {
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Robots-Tag': 'noindex',
  };
  if (request.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405, headers: { ...headers, Allow: 'GET' } });
  }
  try {
    const raw = await env.INSTALLS?.get('blog_articles');
    if (raw == null) throw new Error('missing catalogue');
    return new Response(JSON.stringify(publicBlogSchedule(JSON.parse(raw))), { headers });
  } catch (_) {
    return new Response(JSON.stringify({ error: 'blog schedule unavailable' }), { status: 503, headers });
  }
}
