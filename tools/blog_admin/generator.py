#!/usr/bin/env python3
"""Генератор статического блога pdd-drive.ru.

Источник каждой статьи — web_landing/ru/blog/<slug>/source.json (схема ниже).
Из источников собираются: страницы статей, индекс блога, sitemap.xml,
llms.txt и llms-full.txt. Ручные правки в blog/*/index.html будут затёрты —
правьте source.json (или через админку tools/blog_admin/server.py).

CLI:
    python3 generator.py regen           # пересобрать весь блог
    python3 generator.py migrate <slug>  # разобрать готовую страницу в source.json

Схема source.json:
    {
      "schema": 1, "slug": "...", "title": "...", "shortTitle": "...",
      "description": "...", "datePublished": "YYYY-MM-DD",
      "dateModified": "YYYY-MM-DD", "readingMinutes": 8,
      "cover": "cover.png" | null, "coverAlt": "..." | null,
      "bodyHtml": "<h2>...</h2><p>...</p>",   # без h1/крошек/FAQ
      "faq": [{"q": "...", "aHtml": "..."}],
      "published": true
    }
"""
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SITE = os.path.join(REPO, "web_landing", "ru")
BLOG = os.path.join(SITE, "blog")
BASE = "https://pdd-drive.ru"
PREAMBLE_PATH = os.path.join(HERE, "llms_preamble.md")

RU_MONTHS = [
    "января", "февраля", "марта", "апреля", "мая", "июня",
    "июля", "августа", "сентября", "октября", "ноября", "декабря",
]

# --- Неизменные фрагменты страницы (единый источник шапки/футера/скрипта) ----

HEADER = """<header class="site-header">
  <div class="container">
    <a class="logo" href="/">
      <img src="/assets/icon-192.png" alt="ПДД Россия 2026 — логотип" width="32" height="32" loading="eager">
      ПДД Россия 2026
    </a>
    <nav class="site-nav">
      <a href="/#features">Возможности</a>
      <a href="/proverit-znaniya/">Проверить себя</a>
      <a href="/blog/">Блог</a>
      <a href="/#exam">Экзамен</a>
      <a class="nav-cta" href="/app/">Веб-версия приложения</a>
    </nav>
  </div>
</header>"""

FOOTER = """<footer class="site-footer">
  <div class="container">
    <nav>
      <a href="/blog/">Блог</a>
      <a href="/about/">О проекте</a>
      <a href="/links/">Соцсети</a>
      <a href="/slovar-pdd/">Словарь терминов</a>
      <a href="/privacy.html">Политика конфиденциальности</a>
      <a href="/terms.html">Пользовательское соглашение</a>
      <a href="https://play.google.com/store/apps/details?id=ru.pdd.pdd_app" rel="noopener">Google Play</a>
      <a href="https://apps.apple.com/ru/app/id6792369533" rel="noopener">App Store</a>
      <a href="/app/">Веб-версия</a>
      <a href="mailto:degtyarik.up@gmail.com">Поддержка</a>
    </nav>
    <div class="copy">
      <span class="age-badge">16+</span> © 2026 ПДД Россия 2026 · <a href="https://pdd-drive.online" rel="noopener">ПДД Беларусь</a> · <a href="https://rs.pdd-drive.online" rel="noopener">Auto testovi Srbija</a>
    </div>
    <div class="footer-disclaimer">
      Сайт pdd-drive.ru носит исключительно информационно-справочный и образовательный характер и не является официальным сайтом ГУОБДД МВД России или портала Госуслуг. Официальная информация и первоисточники нормативно-правовых актов РФ публикуются на гибдд.рф и pravo.gov.ru.
    </div>
  </div>
</footer>"""

DEGRADE = """<script src="/assets/tracker.js" defer></script>
<!-- Yandex.Metrika counter -->
<script type="text/javascript">
    (function(m,e,t,r,i,k,a){
        m[i]=m[i]||function(){(m[i].a=m[i].a||[]).push(arguments)};
        m[i].l=1*new Date();
        for (var j = 0; j < document.scripts.length; j++) {if (document.scripts[j].src === r) { return; }}
        k=e.createElement(t),a=e.getElementsByTagName(t)[0],k.async=1,k.src=r,a.parentNode.insertBefore(k,a)
    })(window, document,'script','https://mc.yandex.ru/metrika/tag.js?id=111960332', 'ym');

    ym(111960332, 'init', {ssr:true, webvisor:true, clickmap:true, ecommerce:"dataLayer", referrer: document.referrer, url: location.href, accurateTrackBounce:true, trackLinks:true});
</script>
<noscript><div><img src="https://mc.yandex.ru/watch/111960332" style="position:absolute; left:-9999px;" alt="" /></div></noscript>
<!-- /Yandex.Metrika counter -->"""

EYE_ICON_SVG = '<svg class="icon-eye" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>'

APP_CTA_BOX_HTML = """<div class="article-app-cta">
  <div class="article-app-cta-header">
    <img class="article-app-cta-icon" src="/assets/icon-192.png" alt="Приложение ПДД Россия 2026" width="64" height="64" style="width:64px;height:64px;min-width:64px;max-width:64px;border-radius:16px;object-fit:cover;margin:0;display:block;flex-shrink:0;box-shadow:0 6px 20px rgba(0,0,0,0.35);border:1px solid rgba(255,255,255,0.15);" loading="lazy">
    <div>
      <div class="article-app-cta-title">Тренируйте билеты ПДД 2026 бесплатно</div>
      <div class="article-app-cta-desc">Официальные экзаменационные билеты ГИБДД (категории A/B и C/D) с подсказками к каждому вопросу. Без рекламы и регистрации.</div>
    </div>
  </div>
  <div class="article-app-cta-buttons">
    <a class="article-app-cta-btn" href="https://play.google.com/store/apps/details?id=ru.pdd.pdd_app" target="_blank" rel="noopener" aria-label="Скачать в Google Play">
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M22.018 13.298l-3.919 2.218-3.515-3.493 3.543-3.521 3.891 2.202a1.49 1.49 0 0 1 0 2.594zM1.337.924a1.486 1.486 0 0 0-.112.568v21.017c0 .217.045.419.124.6l11.155-11.087L1.337.924zm12.207 10.065l3.258-3.238L3.45.195a1.466 1.466 0 0 0-.946-.179l11.04 10.973zm0 2.067l-11 10.933c.298.036.612-.016.906-.183l13.324-7.54-3.23-3.21z"/></svg>
      <div class="btn-text">
        <small>Доступно в</small>
        <span>Google Play</span>
      </div>
    </a>
    <a class="article-app-cta-btn" href="https://apps.apple.com/ru/app/id6792369533" target="_blank" rel="noopener" aria-label="Скачать в App Store">
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.05 12.54c-.03-2.89 2.36-4.27 2.47-4.34-1.35-1.97-3.44-2.24-4.18-2.27-1.78-.18-3.47 1.05-4.37 1.05-.9 0-2.29-1.02-3.77-1-1.94.03-3.72 1.13-4.72 2.86-2.01 3.49-.51 8.66 1.45 11.5.96 1.39 2.1 2.95 3.6 2.89 1.44-.06 1.99-.93 3.73-.93 1.74 0 2.23.93 3.76.9 1.56-.03 2.54-1.41 3.49-2.81 1.1-1.61 1.55-3.17 1.57-3.25-.03-.02-3-1.15-3.03-4.6zM14.16 4.06c.8-.96 1.33-2.3 1.19-3.63-1.15.05-2.53.76-3.35 1.72-.74.85-1.38 2.21-1.21 3.51 1.28.1 2.58-.65 3.37-1.6z"/></svg>
      <div class="btn-text">
        <small>Загрузите в</small>
        <span>App Store</span>
      </div>
    </a>
    <a class="article-app-cta-btn" href="https://www.rustore.ru/catalog/app/ru.pdd.pdd_app" target="_blank" rel="noopener" aria-label="Скачать в RuStore">
      <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M13.88 14.8c-.65-.14-1.1-.73-1.1-1.39V6.97c0-.75.72-1.3 1.46-1.13l5.06 1.25c.65.17 1.1.75 1.1 1.4v7.83c0 .75-.72 1.3-1.46 1.13l-5.06-1.65zm-8.74 3.6c-.65-.14-1.1-.73-1.1-1.39v-6.44c0-.75.72-1.3 1.46-1.13l5.06 1.25c.65.17 1.1.75 1.1 1.4v7.83c0 .75-.72 1.3-1.46 1.13l-5.06-1.65z"/></svg>
      <div class="btn-text">
        <small>Скачать в</small>
        <span>RuStore</span>
      </div>
    </a>
  </div>
</div>"""


def _calc_views(slug, date_str):
    """Детерминированный расчет просмотров на основе даты и хэша темы."""
    import hashlib
    h = int(hashlib.md5(slug.encode("utf-8")).hexdigest()[:6], 16)
    try:
        y, m, d = [int(x) for x in date_str.split("-")]
        days_factor = max(1, (2026 - y) * 365 + (8 - m) * 30 + (25 - d) + 40)
    except Exception:
        days_factor = 40
    base = 750 + (h % 1600) + (days_factor * 16)
    return base


def _format_views_short(num):
    """Короткий формат для карточек блога (напр. 1.8k или 950)."""
    if num >= 1000:
        return "%.1fk" % (num / 1000)
    return str(num)


def _format_views_full(num):
    """Полный формат для мета-заголовка статьи (напр. 1 840 просмотров)."""
    s = "{:,}".format(num).replace(",", " ")
    n = num % 100
    n1 = num % 10
    if 11 <= n <= 19:
        word = "просмотров"
    elif n1 == 1:
        word = "просмотр"
    elif 2 <= n1 <= 4:
        word = "просмотра"
    else:
        word = "просмотров"
    return "%s %s" % (s, word)


# --- Загрузка источников -----------------------------------------------------

def _fmt_date(iso):
    y, m, d = iso.split("-")
    return "%d %s %s" % (int(d), RU_MONTHS[int(m) - 1], y)


def load_articles(include_drafts=False):
    """Все статьи из blog/*/source.json, отсортированы по дате убыв."""
    arts = []
    if not os.path.isdir(BLOG):
        return arts
    for slug in sorted(os.listdir(BLOG)):
        p = os.path.join(BLOG, slug, "source.json")
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8") as f:
            a = json.load(f)
        a.setdefault("slug", slug)
        if a.get("published") or include_drafts:
            arts.append(a)
    arts.sort(key=lambda a: a.get("datePublished", ""), reverse=True)
    return arts


def _url(slug):
    return "%s/blog/%s/" % (BASE, slug)


def _cover_url(a):
    if a.get("cover"):
        return "%s/blog/%s/%s" % (BASE, a["slug"], a["cover"])
    return "%s/assets/og-image.png" % BASE


# --- Рендер страницы статьи ---------------------------------------------------

def _jsonld(obj):
    return ('  <script type="application/ld+json">\n  '
            + json.dumps(obj, ensure_ascii=False, indent=2).replace("\n", "\n  ")
            + "\n  </script>")


def render_article(slug, all_published=None):
    with open(os.path.join(BLOG, slug, "source.json"), encoding="utf-8") as f:
        a = json.load(f)
    a.setdefault("slug", slug)
    if all_published is None:
        all_published = load_articles()

    url = _url(slug)
    short = a.get("shortTitle") or a["title"]
    desc = a["description"]
    cover_url = _cover_url(a)

    blogposting = {
        "@context": "https://schema.org",
        "@type": "BlogPosting",
        "headline": a["title"],
        "description": desc,
        "datePublished": a["datePublished"],
        "dateModified": a.get("dateModified", a["datePublished"]),
        "author": {"@type": "Organization", "name": "ПДД Россия 2026"},
        "publisher": {
            "@type": "Organization",
            "name": "ПДД Россия 2026",
            "logo": {"@type": "ImageObject", "url": "%s/assets/icon-192.png" % BASE},
        },
        "image": cover_url,
        "mainEntityOfPage": {"@type": "WebPage", "@id": url},
        "inLanguage": "ru-RU",
    }
    if a.get("cluster") in CLUSTER_META:
        blogposting["articleSection"] = CLUSTER_META[a["cluster"]][1]
    breadcrumb = {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Главная", "item": BASE + "/"},
            {"@type": "ListItem", "position": 2, "name": "Блог", "item": BASE + "/blog/"},
            {"@type": "ListItem", "position": 3, "name": short, "item": url},
        ],
    }
    ld_blocks = [_jsonld(blogposting), _jsonld(breadcrumb)]

    faq = a.get("faq") or []
    if faq:
        faqpage = {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "mainEntity": [
                {
                    "@type": "Question",
                    "name": q["q"],
                    "acceptedAnswer": {"@type": "Answer", "text": _strip_tags(q["aHtml"])},
                }
                for q in faq
            ],
        }
        ld_blocks.append(_jsonld(faqpage))

    # HowTo-разметка для пошаговых статей: source.json → "howtoSteps": [{name, text}]
    # (даёт rich-результат «инструкция» в поиске). Опционально.
    steps = a.get("howtoSteps") or []
    if steps:
        howto = {
            "@context": "https://schema.org",
            "@type": "HowTo",
            "name": a["title"],
            "description": desc,
            "image": cover_url,
            "step": [
                {"@type": "HowToStep", "position": i + 1,
                 "name": s["name"], "text": s["text"], "url": "%s#step-%d" % (url, i + 1)}
                for i, s in enumerate(steps)
            ],
        }
        ld_blocks.append(_jsonld(howto))

    # breadcrumb-текст третьего уровня — короткий заголовок
    crumb_txt = short

    head = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <meta name="description" content="{desc}">
  <link rel="canonical" href="{url}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="ПДД Россия 2026">
  <meta property="og:title" content="{title}">
  <meta property="og:description" content="{desc}">
  <meta property="og:url" content="{url}">
  <meta property="article:published_time" content="{pub}">
  <meta property="article:modified_time" content="{mod}">{section}
  <meta property="og:image" content="{cover}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:locale" content="ru_RU">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="stylesheet" href="/assets/style.css?v=3">
  <link rel="alternate" type="application/rss+xml" title="Блог ПДД Россия 2026" href="/feed.xml">
{ld}
</head>""".format(
        title=html.escape(short),
        desc=html.escape(desc),
        url=url,
        pub=a["datePublished"],
        mod=a.get("dateModified", a["datePublished"]),
        section=('\n  <meta property="article:section" content="%s">'
                  % html.escape(CLUSTER_META[a["cluster"]][1])) if a.get("cluster") in CLUSTER_META else "",
        cover=cover_url,
        ld="\n".join(ld_blocks),
    )

    cover_html = ""
    if a.get("cover"):
        cover_html = ('\n      <img class="post-cover" src="/blog/%s/%s" alt="%s" '
                      'width="1200" height="630" loading="lazy">\n'
                      % (slug, a["cover"], html.escape(a.get("coverAlt") or a["title"])))

    faq_html = ""
    if faq:
        items = "\n".join(
            '        <details>\n'
            '          <summary>%s</summary>\n'
            '          <p>%s</p>\n'
            '        </details>' % (html.escape(q["q"]), q["aHtml"])
            for q in faq
        )
        faq_html = ('\n      <h2>Частые вопросы</h2>\n'
                    '      <div class="faq">\n%s\n      </div>\n' % items)

    # «Читайте также» — до 3 других статей; свой кластер (поле cluster
    # в source.json: exam|reference|prep) идёт первым, дальше по свежести.
    others = [x for x in all_published if x["slug"] != slug]
    cluster = a.get("cluster")
    # Две стабильные сортировки: внутри групп — свежие первыми, свой кластер — впереди
    others.sort(key=lambda x: x.get("datePublished", ""), reverse=True)
    others.sort(key=lambda x: 0 if cluster and x.get("cluster") == cluster else 1)
    related_html = ""
    if others:
        related_html = ('\n      <h2>Читайте также</h2>\n'
                        '      <div class="post-grid">\n%s\n      </div>\n'
                        % _post_cards_html(others[:3]))

    views_num = _calc_views(slug, a.get("datePublished", "2026-08-01"))
    views_full = _format_views_full(views_num)

    body = """{head}
<body>

{header}

<main>
  <section class="section">
  <div class="container">
    <article class="prose">
      <nav class="breadcrumbs">
        <a href="/">Главная</a> / <a href="/blog/">Блог</a> / {crumb}
      </nav>

      <header>
        <h1>{h1}</h1>
        <p class="post-meta">
          <time datetime="{iso}">{date}</time> · Команда ПДД Россия 2026 · ~{mins} мин чтения · 
          <span class="post-views" data-slug="{slug}" title="Количество просмотров">{eye} <span class="views-count">{views}</span></span>
        </p>
      </header>
{cover}
{content}
{cta}
{faq}{related}
    </article>
  </div>
  </section>
</main>

{footer}

{degrade}
</body>
</html>
""".format(
        head=head,
        header=HEADER,
        crumb=html.escape(crumb_txt),
        h1=html.escape(a["title"]),
        iso=a["datePublished"],
        date=_fmt_date(a["datePublished"]),
        mins=a.get("readingMinutes", 6),
        slug=slug,
        eye=EYE_ICON_SVG,
        views=views_full,
        cover=cover_html,
        content=re.sub(r'<div class="note">\s*(?:Уверенность|Тренируйте|Готовьтесь|Изучайте|Решайте|Закрепляйте|Сдавайте|Повторяйте).*?</div>', '', a["bodyHtml"], flags=re.S).strip("\n"),
        cta=APP_CTA_BOX_HTML,
        faq=faq_html,
        related=related_html,
        footer=FOOTER,
        degrade=DEGRADE,
    )

    out = os.path.join(BLOG, slug, "index.html")
    _write(out, body)
    return out


# --- Индекс блога ------------------------------------------------------------

# Хабы кластеров: cluster в source.json -> (slug страницы, заголовок, лид-абзац)
CLUSTER_META = {
    "exam": (
        "ekzamen-i-prava",
        "Экзамен и получение прав",
        "Как получить водительские права, сдать теоретический и практический экзамен в ГИБДД: регламент, сроки, документы.",
    ),
    "reference": (
        "spravochnik-pdd",
        "Справочник ПДД",
        "Дорожные знаки, разметка, сигналы светофора и регулировщика, проезд перекрёстков — разборы по правилам дорожного движения.",
    ),
    "prep": (
        "podgotovka-k-ekzamenu",
        "Подготовка к экзамену",
        "Методики и планы подготовки к теоретическому экзамену: как быстро выучить билеты и не растерять знания к дню экзамена.",
    ),
}


def _cluster_url(cluster):
    meta = CLUSTER_META.get(cluster)
    return "%s/blog/%s/" % (BASE, meta[0]) if meta else None


def _post_cards_html(arts):
    """Карточки статей в общем виде (используется индексом блога и хабами кластеров)."""
    cards = []
    for a in arts:
        cover = ""
        if a.get("cover"):
            cover = ('\n          <img class="post-card-cover" src="/blog/%s/%s" alt="%s" '
                     'width="1200" height="630" loading="lazy">'
                     % (a["slug"], a["cover"], html.escape(a.get("coverAlt") or a["title"])))
        views_num = _calc_views(a["slug"], a.get("datePublished", "2026-08-01"))
        views_short = _format_views_short(views_num)
        cards.append(
            '        <a class="post-card" href="/blog/{slug}/">{cover}\n'
            '          <div class="post-card-meta">\n'
            '            <time datetime="{iso}">{date}</time>\n'
            '            <span class="post-card-views" data-slug="{slug}" title="Просмотры">{eye} <span class="views-count">{views}</span></span>\n'
            '          </div>\n'
            '          <h2>{title}</h2>\n'
            '        </a>'.format(
                slug=a["slug"], cover=cover, iso=a["datePublished"],
                date=_fmt_date(a["datePublished"]), title=html.escape(a["title"]),
                eye=EYE_ICON_SVG, views=views_short,
            )
        )
    return "\n".join(cards)


def render_cluster_hubs(arts=None):
    """Хаб-страницы кластеров (/blog/<cluster-slug>/): группируют статьи по теме —
    усиливают внутреннюю перелинковку и тематическую авторитетность (topic cluster)."""
    if arts is None:
        arts = load_articles()

    by_cluster = {}
    for a in arts:
        by_cluster.setdefault(a.get("cluster"), []).append(a)

    out_paths = []
    for cluster, (slug, title, lead) in CLUSTER_META.items():
        members = by_cluster.get(cluster, [])
        if not members:
            continue
        url = "%s/blog/%s/" % (BASE, slug)

        haspart = [
            {"@type": "BlogPosting", "headline": a["title"], "url": _url(a["slug"]),
             "datePublished": a["datePublished"], "inLanguage": "ru-RU"}
            for a in members
        ]
        graph = {
            "@context": "https://schema.org",
            "@graph": [
                {
                    "@type": "CollectionPage", "@id": url, "url": url,
                    "name": title, "description": lead, "inLanguage": "ru-RU",
                    "isPartOf": {"@type": "WebSite", "name": "ПДД Россия 2026", "url": BASE + "/"},
                    "hasPart": haspart,
                },
                {
                    "@type": "BreadcrumbList",
                    "itemListElement": [
                        {"@type": "ListItem", "position": 1, "name": "Главная", "item": BASE + "/"},
                        {"@type": "ListItem", "position": 2, "name": "Блог", "item": BASE + "/blog/"},
                        {"@type": "ListItem", "position": 3, "name": title, "item": url},
                    ],
                },
            ],
        }

        page = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title} — блог ПДД Россия 2026</title>
  <meta name="description" content="{desc}">
  <link rel="canonical" href="{url}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="ПДД Россия 2026">
  <meta property="og:title" content="{title} — блог ПДД Россия 2026">
  <meta property="og:description" content="{desc}">
  <meta property="og:url" content="{url}">
  <meta property="og:image" content="{base}/assets/og-image.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:locale" content="ru_RU">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="stylesheet" href="/assets/style.css?v=3">
  <link rel="alternate" type="application/rss+xml" title="Блог ПДД Россия 2026" href="/feed.xml">
{ld}
</head>
<body>

{header}

<main>
  <section class="section">
    <div class="container">
      <nav class="breadcrumbs"><a href="/">Главная</a> / <a href="/blog/">Блог</a> / {title}</nav>
      <h1 class="section-title" style="text-align:left">{title}</h1>
      <p class="section-lead" style="text-align:left;margin-left:0">{desc}</p>
      <div class="post-grid" style="margin-top:32px">
{cards}
      </div>
    </div>
  </section>
</main>

{footer}

{degrade}
</body>
</html>
""".format(title=html.escape(title), desc=html.escape(lead), url=url, base=BASE,
           ld=_jsonld(graph), header=HEADER, cards=_post_cards_html(members),
           footer=FOOTER, degrade=DEGRADE)

        out_dir = os.path.join(SITE, "blog", slug)
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, "index.html")
        _write(out, page)
        out_paths.append(out)
    return out_paths


def render_blog_index(arts=None):
    if arts is None:
        arts = load_articles()

    haspart = [
        {
            "@type": "BlogPosting",
            "headline": a["title"],
            "url": _url(a["slug"]),
            "datePublished": a["datePublished"],
            "inLanguage": "ru-RU",
        }
        for a in arts
    ]
    graph = {
        "@context": "https://schema.org",
        "@graph": [
            {
                "@type": "CollectionPage",
                "@id": BASE + "/blog/",
                "url": BASE + "/blog/",
                "name": "Блог о ПДД и экзамене в ГИБДД",
                "description": "Статьи о подготовке к теоретическому экзамену в ГИБДД: разборы правил дорожного движения, изменения законодательства и советы по обучению в автошколе.",
                "inLanguage": "ru-RU",
                "isPartOf": {"@type": "WebSite", "name": "ПДД Россия 2026", "url": BASE + "/"},
                "hasPart": haspart,
            },
            {
                "@type": "BreadcrumbList",
                "itemListElement": [
                    {"@type": "ListItem", "position": 1, "name": "Главная", "item": BASE + "/"},
                    {"@type": "ListItem", "position": 2, "name": "Блог", "item": BASE + "/blog/"},
                ],
            },
        ],
    }

    # Карточки — тот же компактный вид, что и в блоке «Из блога» на главной.
    cards_html = _post_cards_html(arts)

    # Чипы-навигация по кластерам (хаб-страницам) — только те, где есть статьи.
    by_cluster = set(a.get("cluster") for a in arts)
    cat_chips = "\n".join(
        '        <a href="/blog/%s/">%s</a>' % (CLUSTER_META[c][0], html.escape(CLUSTER_META[c][1]))
        for c in CLUSTER_META if c in by_cluster
    )
    cat_nav = ('\n      <div class="glossary-nav">\n%s\n      </div>' % cat_chips) if cat_chips else ""

    page = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Блог о ПДД и экзамене в ГИБДД — ПДД Россия 2026</title>
  <meta name="description" content="Статьи о подготовке к теоретическому экзамену в ГИБДД: разборы правил дорожного движения, изменения законодательства и советы по обучению в автошколе.">
  <link rel="canonical" href="https://pdd-drive.ru/blog/">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="ПДД Россия 2026">
  <meta property="og:title" content="Блог о ПДД и экзамене в ГИБДД — ПДД Россия 2026">
  <meta property="og:description" content="Статьи о подготовке к теоретическому экзамену в ГИБДД: разборы правил дорожного движения, изменения законодательства и советы по обучению в автошколе.">
  <meta property="og:url" content="https://pdd-drive.ru/blog/">
  <meta property="og:image" content="https://pdd-drive.ru/assets/og-image.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:locale" content="ru_RU">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="stylesheet" href="/assets/style.css?v=3">
  <link rel="alternate" type="application/rss+xml" title="Блог ПДД Россия 2026" href="/feed.xml">
{ld}
</head>
<body>

{header}

<main>
  <section class="section">
    <div class="container">
      <h1 class="section-title">Блог о ПДД и экзамене в ГИБДД</h1>
      <p class="section-lead">Разборы правил дорожного движения, изменения законодательства и советы по подготовке к экзамену в ГИБДД.</p>{cat_nav}
      <div class="post-grid" style="margin-top:32px">
{cards}
      </div>
    </div>
  </section>
</main>

{footer}

{degrade}
</body>
</html>
""".format(ld=_jsonld(graph), header=HEADER, cards=cards_html, cat_nav=cat_nav,
           footer=FOOTER, degrade=DEGRADE)

    out = os.path.join(BLOG, "index.html")
    _write(out, page)
    return out


# --- Блок «Из блога» на главной ----------------------------------------------

def render_home_blog(arts=None):
    """Обновляет секцию между <!-- BLOG:START --> и <!-- BLOG:END --> в index.html."""
    if arts is None:
        arts = load_articles()
    path = os.path.join(SITE, "index.html")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        s = f.read()
    if "<!-- BLOG:START -->" not in s or "<!-- BLOG:END -->" not in s:
        return None

    cards = []
    for a in arts[:3]:
        cover = ""
        if a.get("cover"):
            cover = ('\n          <img class="post-card-cover" src="/blog/%s/%s" alt="%s" '
                     'width="1200" height="630" loading="lazy">'
                     % (a["slug"], a["cover"], html.escape(a.get("coverAlt") or a["title"])))
        cards.append(
            '        <a class="post-card" href="/blog/{slug}/">{cover}\n'
            '          <time datetime="{iso}">{date}</time>\n'
            '          <h3>{title}</h3>\n'
            '        </a>'.format(
                slug=a["slug"], cover=cover, iso=a["datePublished"],
                date=_fmt_date(a["datePublished"]), title=html.escape(a["title"])))

    block = ""
    if cards:
        block = """
  <section class="section alt" id="blog">
    <div class="container">
      <h2 class="section-title">Из блога</h2>
      <p class="section-lead">Разборы правил и практические планы подготовки к экзамену.</p>
      <div class="post-grid">
{cards}
      </div>
      <div class="blog-all-link"><a class="btn btn-primary" href="/blog/">Все статьи</a></div>
    </div>
  </section>
""".format(cards="\n".join(cards))

    new = re.sub(r"<!-- BLOG:START -->.*?<!-- BLOG:END -->",
                 "<!-- BLOG:START -->%s  <!-- BLOG:END -->" % block, s, flags=re.S)
    _write(path, new)
    return path


# --- sitemap.xml -------------------------------------------------------------

def render_sitemap(arts=None):
    if arts is None:
        arts = load_articles()
    latest = max([a.get("dateModified", a["datePublished"]) for a in arts], default="2026-07-19")

    rows = [
        ("%s/" % BASE, latest, "weekly", "1.0"),
        ("%s/blog/" % BASE, latest, "weekly", "0.8"),
        ("%s/proverit-znaniya/" % BASE, "2026-07-23", "monthly", "0.9"),
    ]
    for a in arts:
        rows.append((_url(a["slug"]), a.get("dateModified", a["datePublished"]), "monthly", "0.7"))
    by_cluster = set(a.get("cluster") for a in arts)
    for c in CLUSTER_META:
        if c in by_cluster:
            rows.append((_cluster_url(c), latest, "weekly", "0.75"))
    rows.append(("%s/about/" % BASE, "2026-07-21", "monthly", "0.5"))
    rows.append(("%s/links/" % BASE, "2026-08-15", "monthly", "0.4"))
    if os.path.isdir(GLOSSARY_DIR):
        rows.append((GLOSSARY_URL, "2026-07-22", "monthly", "0.6"))
    rows.append(("%s/privacy.html" % BASE, "2026-08-25", "yearly", "0.3"))
    rows.append(("%s/terms.html" % BASE, "2026-08-25", "yearly", "0.3"))

    # обложки статей — в sitemap как image:image (индексация в Картинках)
    covers = {_url(a["slug"]): "%s/blog/%s/%s" % (BASE, a["slug"], a["cover"])
              for a in arts if a.get("cover")}

    body = ['<?xml version="1.0" encoding="UTF-8"?>',
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"',
            '        xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">']
    for loc, mod, freq, pri in rows:
        body.append("  <url>")
        body.append("    <loc>%s</loc>" % loc)
        body.append("    <lastmod>%s</lastmod>" % mod)
        body.append("    <changefreq>%s</changefreq>" % freq)
        body.append("    <priority>%s</priority>" % pri)
        if loc in covers:
            body.append("    <image:image><image:loc>%s</image:loc></image:image>" % covers[loc])
        body.append("  </url>")
    body.append("</urlset>")
    out = os.path.join(SITE, "sitemap.xml")
    _write(out, "\n".join(body) + "\n")
    return out


# --- RSS-фид -----------------------------------------------------------------

def render_rss(arts=None):
    """feed.xml: RSS 2.0 — дзен-агрегаторы, Яндекс и часть AI-краулеров любят фиды."""
    if arts is None:
        arts = load_articles()
    items = []
    for a in arts:
        cov = ""
        if a.get("cover"):
            cov = ('\n      <enclosure url="%s/blog/%s/%s" type="image/jpeg" length="0"/>'
                   % (BASE, a["slug"], a["cover"]))
        items.append("""    <item>
      <title>%s</title>
      <link>%s</link>
      <guid isPermaLink="true">%s</guid>
      <pubDate>%s</pubDate>
      <description>%s</description>%s
    </item>""" % (html.escape(a["title"]), _url(a["slug"]), _url(a["slug"]),
                  _rfc822(a["datePublished"]), html.escape(a["description"]), cov))

    feed = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Блог ПДД Россия 2026</title>
    <link>%s/blog/</link>
    <atom:link href="%s/feed.xml" rel="self" type="application/rss+xml"/>
    <description>Статьи о ПДД и подготовке к теоретическому экзамену в ГИБДД: знаки, разметка, регламент экзамена, методики подготовки.</description>
    <language>ru</language>
%s
  </channel>
</rss>
""" % (BASE, BASE, "\n".join(items))
    out = os.path.join(SITE, "feed.xml")
    _write(out, feed)
    return out


def _rfc822(iso):
    y, m, d = (int(x) for x in iso.split("-"))
    import calendar
    import datetime
    dt = datetime.date(y, m, d)
    return "%s, %02d %s %d 08:00:00 +0300" % (
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][dt.weekday()], d,
        calendar.month_abbr[m], y)


# --- llms.txt / llms-full.txt ------------------------------------------------

def _preamble():
    if os.path.isfile(PREAMBLE_PATH):
        with open(PREAMBLE_PATH, encoding="utf-8") as f:
            return f.read().rstrip("\n")
    # запасной вариант — текущий llms.txt до раздела «## Ссылки»
    return "# ПДД Россия 2026\n"


def render_llms(arts=None):
    if arts is None:
        arts = load_articles()
    pre = _preamble()

    # llms.txt = преамбула + раздел «## Категории» + «## Статьи»
    lines = [pre, "",
              "## Инструменты", "",
              "- [Проверьте знание ПДД](%s/proverit-znaniya/): бесплатный интерактивный "
              "мини-тест из 12 вопросов официальной базы билетов ГИБДД с разбором "
              "каждого ответа, без регистрации." % BASE, ""]
    by_cluster = set(a.get("cluster") for a in arts)
    active_clusters = [c for c in CLUSTER_META if c in by_cluster]
    if active_clusters:
        lines += ["## Категории блога", ""]
        for c in active_clusters:
            slug, title, lead = CLUSTER_META[c]
            lines.append("- [%s](%s/blog/%s/): %s" % (title, BASE, slug, lead))
        lines.append("")
    lines += ["## Статьи", ""]
    for a in arts:
        lines.append("- [%s](%s): %s" % (a["title"], _url(a["slug"]), a["description"]))
    categories, _ = _load_glossary()
    if categories:
        n = sum(len(terms) for _, terms in categories)
        lines += ["", "## Словарь терминов", "",
                  "- [Словарь терминов ПДД](%s): %d точных определений терминов ПДД "
                  "(знаки, разметка, манёвры, скорость, документы)." % (GLOSSARY_URL, n)]
    lines += ["", "## Полные тексты", "",
              "- [llms-full.txt](%s/llms-full.txt): полный текст всех статей блога "
              "одним файлом, без HTML-разметки." % BASE]
    _write(os.path.join(SITE, "llms.txt"), "\n".join(lines) + "\n")

    # llms-full.txt = преамбула + полный текст статей и словарь терминов в маркдауне
    full = [pre]
    if categories:
        full += ["", "## Словарь терминов ПДД", ""]
        for label, terms in categories:
            full.append("### %s" % label)
            full.append("")
            for t in terms:
                full.append("**%s** — %s" % (t["term"], _strip_tags(t["definition"])))
            full.append("")
    full += ["", "## Статьи (полный текст)", ""]
    for a in arts:
        full.append("---")
        full.append("")
        full.append("# %s" % a["title"])
        full.append("")
        full.append("_Опубликовано: %s. %s_" % (_fmt_date(a["datePublished"]), _url(a["slug"])))
        full.append("")
        full.append(_html_to_md(a["bodyHtml"]))
        if a.get("faq"):
            full.append("")
            full.append("## Частые вопросы")
            full.append("")
            for q in a["faq"]:
                full.append("### %s" % q["q"])
                full.append("")
                full.append(_strip_tags(q["aHtml"]))
                full.append("")
    _write(os.path.join(SITE, "llms-full.txt"), "\n".join(full).rstrip("\n") + "\n")


# --- Полный ре-генератор -----------------------------------------------------

def regen_all():
    arts = load_articles()
    for a in arts:
        render_article(a["slug"], all_published=arts)
    render_blog_index(arts)
    render_cluster_hubs(arts)
    render_home_blog(arts)
    render_glossary()
    render_sitemap(arts)
    render_rss(arts)
    render_llms(arts)
    return [a["slug"] for a in arts]


# --- Утилиты -----------------------------------------------------------------

def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # писать только при изменении — идемпотентность и стабильный mtime
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


_TAG_RE = re.compile(r"<[^>]+>")


def _strip_tags(s):
    return html.unescape(_TAG_RE.sub("", s)).strip()


def _html_to_md(body):
    """Грубая, но достаточная конвертация bodyHtml → markdown для llms-full."""
    s = body
    s = re.sub(r"<h2[^>]*>(.*?)</h2>", lambda m: "\n## " + _strip_tags(m.group(1)) + "\n", s, flags=re.S)
    s = re.sub(r"<h3[^>]*>(.*?)</h3>", lambda m: "\n### " + _strip_tags(m.group(1)) + "\n", s, flags=re.S)
    s = re.sub(r'<div class="note"[^>]*>(.*?)</div>', lambda m: "\n> " + _strip_tags(m.group(1)) + "\n", s, flags=re.S)
    s = re.sub(r"<li[^>]*>(.*?)</li>", lambda m: "- " + _strip_tags(m.group(1)) + "\n", s, flags=re.S)
    # таблицы: строки через " | "
    def _row(m):
        cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", m.group(1), flags=re.S)
        return "| " + " | ".join(_strip_tags(c) for c in cells) + " |\n"
    s = re.sub(r"<tr[^>]*>(.*?)</tr>", _row, s, flags=re.S)
    s = re.sub(r"</?(ul|ol|table|tbody|thead)[^>]*>", "", s)
    s = re.sub(r"<p[^>]*>(.*?)</p>", lambda m: "\n" + _strip_tags(m.group(1)) + "\n", s, flags=re.S)
    s = _TAG_RE.sub("", s)
    s = html.unescape(s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


# --- migrate: готовая страница → source.json ---------------------------------

def migrate(slug):
    """Разобрать blog/<slug>/index.html в source.json (одноразово)."""
    path = os.path.join(BLOG, slug, "index.html")
    with open(path, encoding="utf-8") as f:
        s = f.read()

    def _find(pat, default=""):
        m = re.search(pat, s, flags=re.S)
        return m.group(1).strip() if m else default

    title = _find(r"<h1>(.*?)</h1>")
    short = _find(r"<title>(.*?)</title>")
    desc = _find(r'<meta name="description" content="(.*?)">')
    pub = _find(r'article:published_time" content="(.*?)"', "2026-07-19")
    mins_m = re.search(r"~(\d+)\s*мин", s)
    mins = int(mins_m.group(1)) if mins_m else 6

    # body = от </header> внутри article до <h2>Частые вопросы</h2>
    art = _find(r'<article class="prose">(.*?)</article>')
    after_header = art.split("</header>", 1)[1] if "</header>" in art else art
    body = re.split(r"<h2>\s*Частые вопросы\s*</h2>", after_header)[0]
    # выкинуть возможный блок «Читайте также»
    body = re.sub(r'<div class="note">\s*<strong>Читайте также.*?</div>', "", body, flags=re.S)
    body = body.strip()

    # faq: пары h3/p после «Частые вопросы»
    faq = []
    faq_zone = ""
    m = re.search(r"<h2>\s*Частые вопросы\s*</h2>(.*)$", after_header, flags=re.S)
    if m:
        faq_zone = m.group(1)
        for qm in re.finditer(r"<h3>(.*?)</h3>\s*<p>(.*?)</p>", faq_zone, flags=re.S):
            faq.append({"q": _strip_tags(qm.group(1)), "aHtml": qm.group(2).strip()})

    src = {
        "schema": 1, "slug": slug, "title": title, "shortTitle": short,
        "description": desc, "datePublished": pub, "dateModified": pub,
        "readingMinutes": mins, "cover": None, "coverAlt": None,
        "bodyHtml": body, "faq": faq, "published": True,
    }
    out = os.path.join(BLOG, slug, "source.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(src, f, ensure_ascii=False, indent=2)
    return out


# --- Словарь терминов (/slovar-pdd/) ------------------------------------------

GLOSSARY_DIR = os.path.join(SITE, "glossary_data")
GLOSSARY_URL = "%s/slovar-pdd/" % BASE
GLOSSARY_BATCHES = [
    ("batch-signs-priority.json", "Знаки и приоритет"),
    ("batch-markings-lanes.json", "Разметка и полосы"),
    ("batch-maneuvers.json", "Манёвры и остановка"),
    ("batch-speed-distance.json", "Скорость, дистанция и дорога"),
    ("batch-docs-exam.json", "Документы и экзамен"),
    ("batch-special.json", "Особые ситуации"),
]


def _load_glossary():
    """Список (category_label, [terms...]) + карта slug -> название термина."""
    categories = []
    by_slug = {}
    for fname, label in GLOSSARY_BATCHES:
        path = os.path.join(GLOSSARY_DIR, fname)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        terms = data["terms"]
        categories.append((label, terms))
        for t in terms:
            by_slug[t["slug"]] = t["term"]
    return categories, by_slug


def render_glossary():
    categories, by_slug = _load_glossary()
    if not categories:
        return None

    all_terms = [t for _, terms in categories for t in terms]
    article_titles = {_url(a["slug"]).replace(BASE, ""): (a.get("shortTitle") or a["title"])
                      for a in load_articles()}

    nav_items = "\n".join(
        '        <a href="#cat-%d">%s</a>' % (i, html.escape(label))
        for i, (label, _) in enumerate(categories)
    )

    sections = []
    for i, (label, terms) in enumerate(categories):
        cards = []
        for t in terms:
            see_also = ""
            sa_slug = t.get("seeAlso")
            if sa_slug and sa_slug in by_slug:
                see_also = ('\n          <p class="see-also">См. также: '
                            '<a href="#%s">%s</a></p>' % (sa_slug, html.escape(by_slug[sa_slug])))
            article_link = ""
            art_url = t.get("article")
            if art_url and art_url in article_titles:
                article_link = ('\n          <p class="read-more">'
                                 '<a href="%s">Подробнее: %s →</a></p>'
                                 % (art_url, html.escape(article_titles[art_url])))
            cards.append(
                '        <article class="term-card" id="%s">\n'
                '          <h3>%s</h3>\n'
                '          <p>%s</p>%s%s\n'
                '        </article>' % (t["slug"], html.escape(t["term"]), t["definition"], see_also, article_link)
            )
        sections.append(
            '      <h2 id="cat-%d">%s</h2>\n'
            '      <div class="term-list">\n%s\n      </div>' % (i, html.escape(label), "\n".join(cards))
        )

    defined_terms = [
        {
            "@type": "DefinedTerm",
            "name": t["term"],
            "description": _strip_tags(t["definition"]),
            "url": "%s#%s" % (GLOSSARY_URL, t["slug"]),
            "inDefinedTermSet": GLOSSARY_URL,
        }
        for t in all_terms
    ]
    term_set = {
        "@context": "https://schema.org",
        "@type": "DefinedTermSet",
        "name": "Словарь терминов ПДД",
        "description": "Определения ключевых терминов Правил дорожного движения РФ: знаки, разметка, манёвры, скорость и документы.",
        "url": GLOSSARY_URL,
        "inLanguage": "ru-RU",
        "hasDefinedTerm": defined_terms,
    }
    breadcrumb = {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Главная", "item": BASE + "/"},
            {"@type": "ListItem", "position": 2, "name": "Словарь терминов", "item": GLOSSARY_URL},
        ],
    }

    title = "Словарь терминов ПДД — определения простыми словами"
    desc = ("%d терминов ПДД с точными определениями: обгон и опережение, остановка и стоянка, "
            "главная и второстепенная дорога, разметка, манёвры и документы." % len(all_terms))

    page = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <meta name="description" content="{desc}">
  <link rel="canonical" href="{url}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="ПДД Россия 2026">
  <meta property="og:title" content="{title}">
  <meta property="og:description" content="{desc}">
  <meta property="og:url" content="{url}">
  <meta property="og:image" content="{base}/assets/og-image.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:locale" content="ru_RU">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="stylesheet" href="/assets/style.css?v=3">
  <link rel="alternate" type="application/rss+xml" title="Блог ПДД Россия 2026" href="/feed.xml">
{ld1}
{ld2}
</head>
<body>

{header}

<main>
  <section class="section">
    <div class="container">
      <nav class="breadcrumbs"><a href="/">Главная</a> / Словарь терминов</nav>
      <h1 class="section-title" style="text-align:left">Словарь терминов ПДД</h1>
      <p class="section-lead" style="text-align:left;margin-left:0">{count} терминов из Правил дорожного движения РФ — точные определения простыми словами, с примерами и перекрёстными ссылками.</p>
      <div class="glossary-nav">
{nav}
      </div>
{sections}
      <div class="note" style="margin-top:32px">
        Тренируйте эти термины на практике в бесплатном приложении «<a href="https://play.google.com/store/apps/details?id=ru.pdd.pdd_app" rel="noopener">ПДД Россия 2026</a>»: билеты с пояснением к каждому вопросу и справочник ПДД. Смотрите также <a href="/blog/">блог</a> — подробные разборы тем.
      </div>
    </div>
  </section>
</main>

{footer}

{degrade}
</body>
</html>
""".format(
        title=html.escape(title), desc=html.escape(desc), url=GLOSSARY_URL, base=BASE,
        ld1=_jsonld(term_set), ld2=_jsonld(breadcrumb),
        header=HEADER, count=len(all_terms), nav=nav_items,
        sections="\n\n".join(sections), footer=FOOTER, degrade=DEGRADE,
    )

    out_dir = os.path.join(SITE, "slovar-pdd")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "index.html")
    _write(out, page)
    return out


# --- CLI ---------------------------------------------------------------------

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "regen"
    if cmd == "regen":
        slugs = regen_all()
        print("regen: %d статей → %s" % (len(slugs), ", ".join(slugs)))
    elif cmd == "migrate":
        out = migrate(sys.argv[2])
        print("migrate → %s" % out)
    else:
        print("usage: generator.py [regen|migrate <slug>]")
        sys.exit(1)
