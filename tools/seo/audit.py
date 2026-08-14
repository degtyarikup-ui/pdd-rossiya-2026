#!/usr/bin/env python3
"""Регресс-аудит статики лендинга: ловит поломки, которые молча убивают SEO.

    python3 tools/seo/audit.py            # проверить web_landing/ru
    python3 tools/seo/audit.py --quiet    # только ошибки (для CI/деплоя)

Выход: 0 — всё чисто (возможны warning'и), 1 — есть ERROR.
Подключён в scripts/deploy_landing.sh: деплой падает, если аудит нашёл ERROR.

Почему именно эти проверки: каждая из них — реальная поломка, которая
не видна глазом на странице, но стоит трафика (невалидный JSON-LD теряет
rich-результаты, битая ссылка тратит краулинговый бюджет, дубль title
заставляет поисковик выбирать между своими же страницами).
Только стандартная библиотека — скрипт должен запускаться где угодно.
"""
import argparse
import html as html_mod
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SITE = os.path.join(REPO, "web_landing", "ru")
BASE = "https://pdd-drive.ru"

# /app/ — временная копия Flutter-приложения (в .gitignore, закрыта в robots),
# её содержимое генерирует сборщик Flutter, аудитом не проверяем.
SKIP_DIRS = {"app", "assets", "glossary_data"}

# Файлы подтверждения прав в поисковых панелях: это не страницы сайта, а
# технические заглушки фиксированного формата — у них не должно быть ни title,
# ни canonical, и в sitemap/перелинковке им делать нечего.
# ВАЖНО: не удалять их с сайта — иначе подтверждение прав слетит.
VERIFICATION_RE = re.compile(r"^(yandex_[0-9a-f]+|google[0-9a-f]+)\.html$")

TITLE_MAX = 60      # больше — Google обрежет в выдаче
DESC_MIN, DESC_MAX = 100, 175

# Эмодзи в UI — против дизайн-правила проекта (используем SVG-иконки).
EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF]"
)


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, where, msg):
        self.errors.append((where, msg))

    def warn(self, where, msg):
        self.warnings.append((where, msg))


def html_files():
    """Все страницы сайта, кроме служебных каталогов."""
    out = []
    for root, dirs, files in os.walk(SITE):
        dirs[:] = [d for d in dirs
                   if d not in SKIP_DIRS and not d.startswith(".")]
        for f in files:
            if f.endswith(".html"):
                out.append(os.path.join(root, f))
    return sorted(out)


def rel(path):
    return os.path.relpath(path, SITE)


def is_verification(path):
    return bool(VERIFICATION_RE.match(os.path.basename(path)))


def is_utility_url(u):
    """Страницы, к которым не применяются требования индексируемого контента."""
    name = u.lstrip("/")
    return (name in ("404.html", "404/")
            or u.startswith("/app/")
            or VERIFICATION_RE.match(name) is not None)


def url_path(path):
    """Путь файла → URL-путь, каким его увидит посетитель."""
    r = rel(path).replace(os.sep, "/")
    if r.endswith("/index.html"):
        return "/" + r[: -len("index.html")]
    if r == "index.html":
        return "/"
    return "/" + r


def _first(pattern, text, flags=re.S):
    m = re.search(pattern, text, flags)
    return m.group(1).strip() if m else None


# --- проверки ----------------------------------------------------------------

def check_jsonld(rep, pages):
    """Невалидный JSON-LD = потерянные rich-результаты, и это не видно глазом."""
    for path, text in pages.items():
        for i, block in enumerate(
            re.findall(r'<script type="application/ld\+json">(.*?)</script>',
                       text, re.S)
        ):
            try:
                json.loads(block)
            except ValueError as e:
                rep.error(rel(path), "невалидный JSON-LD (блок %d): %s" % (i, e))


def check_meta(rep, pages):
    """title/description: наличие, длина, уникальность + canonical."""
    titles, descs = defaultdict(list), defaultdict(list)

    for path, text in pages.items():
        if is_verification(path):
            continue
        where = rel(path)
        # 404 намеренно noindex — требования к мете к ней не применяем
        noindex = 'name="robots" content="noindex"' in text

        title = _first(r"<title>(.*?)</title>", text)
        if not title:
            rep.error(where, "нет <title>")
        else:
            titles[title].append(where)
            if len(title) > TITLE_MAX:
                rep.warn(where, "title длиннее %d символов (%d) — обрежется в выдаче"
                         % (TITLE_MAX, len(title)))

        desc = _first(r'<meta name="description" content="(.*?)">', text)
        if not desc:
            if not noindex:
                rep.error(where, "нет meta description")
        elif not noindex:
            descs[desc].append(where)
            n = len(desc)
            if n < DESC_MIN or n > DESC_MAX:
                rep.warn(where, "description %d символов (норма %d-%d)"
                         % (n, DESC_MIN, DESC_MAX))

        if not noindex and 'rel="canonical"' not in text:
            rep.error(where, "нет canonical")

    for value, where_list in list(titles.items()) + list(descs.items()):
        if len(where_list) > 1:
            rep.error(where_list[0],
                      "дубль title/description с: %s" % ", ".join(where_list[1:]))


def check_links(rep, pages, page_urls):
    """Внутренние ссылки и якоря словаря — битая ссылка тратит краулинговый бюджет."""
    anchors_by_page = {}
    for path, text in pages.items():
        anchors_by_page[url_path(path)] = set(re.findall(r'id="([^"]+)"', text))

    for path, text in pages.items():
        where = rel(path)
        for href in re.findall(r'href="(/[^"]*)"', text):
            target, _, frag = href.partition("#")
            if not target or target.startswith("/app/"):
                continue
            # файлы (privacy.html, *.xml, *.txt) — проверяем существование на диске
            if not target.endswith("/"):
                if not os.path.isfile(os.path.join(SITE, target.lstrip("/"))):
                    rep.error(where, "битая ссылка на файл: %s" % href)
                continue
            if target not in page_urls:
                rep.error(where, "ссылка на несуществующую страницу: %s" % href)
            elif frag and frag not in anchors_by_page.get(target, set()):
                rep.error(where, "битый якорь: %s" % href)


def check_images(rep, pages):
    """alt у картинок + физическое наличие файла."""
    for path, text in pages.items():
        where = rel(path)
        for tag in re.findall(r"<img\s[^>]*>", text):
            if not re.search(r'\salt="', tag):
                rep.error(where, "у <img> нет alt: %s" % tag[:90])
            src = _first(r'src="([^"]+)"', tag, flags=0)
            if src and src.startswith("/"):
                if not os.path.isfile(os.path.join(SITE, src.lstrip("/"))):
                    rep.error(where, "картинка не найдена: %s" % src)


def check_sitemap(rep, page_urls):
    """sitemap должен совпадать с реальностью в обе стороны."""
    sm = os.path.join(SITE, "sitemap.xml")
    if not os.path.isfile(sm):
        rep.error("sitemap.xml", "файл отсутствует")
        return set()

    with open(sm, encoding="utf-8") as f:
        text = f.read()
    listed = set()
    for loc in re.findall(r"<loc>(.*?)</loc>", text):
        if not loc.startswith(BASE):
            rep.error("sitemap.xml", "чужой домен в <loc>: %s" % loc)
            continue
        listed.add(loc[len(BASE):] or "/")

    for loc in sorted(listed):
        if loc.endswith("/") and loc not in page_urls:
            rep.error("sitemap.xml", "в sitemap есть, а страницы нет: %s" % loc)

    # Обратная сторона: страница есть, в sitemap не попала (значит, не индексируется).
    # 404, /app/ и файлы верификации там быть не должны — это норма.
    for u in sorted(page_urls):
        if is_utility_url(u):
            continue
        if u not in listed:
            rep.warn("sitemap.xml", "страница не попала в sitemap: %s" % u)
    return listed


def check_orphans(rep, pages, page_urls):
    """Страница без входящих ссылок — тупик и для читателя, и для краулера."""
    linked = set()
    for text in pages.values():
        # ссылки и на каталоги (/blog/), и на файлы (/privacy.html)
        for href in re.findall(r'href="(/[^"#]*)"', text):
            linked.add(href)
    for u in sorted(page_urls):
        if u == "/" or is_utility_url(u):
            continue
        if u not in linked:
            rep.warn(u, "нет ни одной внутренней ссылки на страницу (орфан)")


def check_emoji(rep, pages):
    """Эмодзи в вёрстке — против дизайн-правила (только SVG-иконки)."""
    for path, text in pages.items():
        body = re.sub(r"<script.*?</script>", "", text, flags=re.S)
        found = EMOJI_RE.findall(body)
        if found:
            rep.warn(rel(path), "эмодзи в разметке (%s) — нужны SVG-иконки"
                     % " ".join(sorted(set(found))[:5]))


def check_robots_and_llms(rep, page_urls):
    """robots.txt не должен закрывать сайт; llms.txt — ссылаться на живые страницы."""
    robots = os.path.join(SITE, "robots.txt")
    if not os.path.isfile(robots):
        rep.error("robots.txt", "файл отсутствует")
    else:
        with open(robots, encoding="utf-8") as f:
            text = f.read()
        for line in text.splitlines():
            if re.match(r"^\s*Disallow:\s*/\s*$", line):
                rep.error("robots.txt", "весь сайт закрыт от индексации: %r" % line)
        if "Sitemap:" not in text:
            rep.warn("robots.txt", "не указан Sitemap:")

    for name in ("llms.txt", "llms-full.txt"):
        p = os.path.join(SITE, name)
        if not os.path.isfile(p):
            rep.warn(name, "файл отсутствует")
            continue
        with open(p, encoding="utf-8") as f:
            text = f.read()
        for url in set(re.findall(re.escape(BASE) + r"(/[^\s\)]*)", text)):
            if url.endswith("/") and url not in page_urls:
                rep.error(name, "ссылка на несуществующую страницу: %s" % url)


# --- запуск ------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true",
                    help="печатать только ошибки")
    args = ap.parse_args()

    if not os.path.isdir(SITE):
        print("нет каталога сайта: %s" % SITE)
        return 1

    paths = html_files()
    pages = {}
    for p in paths:
        with open(p, encoding="utf-8") as f:
            pages[p] = f.read()
    page_urls = {url_path(p) for p in paths}

    rep = Report()
    check_jsonld(rep, pages)
    check_meta(rep, pages)
    check_links(rep, pages, page_urls)
    check_images(rep, pages)
    check_sitemap(rep, page_urls)
    check_orphans(rep, pages, page_urls)
    check_emoji(rep, pages)
    check_robots_and_llms(rep, page_urls)

    if rep.errors:
        print("\nОШИБКИ (%d):" % len(rep.errors))
        for where, msg in rep.errors:
            print("  ✗ %-42s %s" % (where, msg))
    if rep.warnings and not args.quiet:
        print("\nПредупреждения (%d):" % len(rep.warnings))
        for where, msg in rep.warnings:
            print("  · %-42s %s" % (where, msg))

    print("\nSEO-аудит: %d страниц, %d ошибок, %d предупреждений"
          % (len(paths), len(rep.errors), len(rep.warnings)))
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
