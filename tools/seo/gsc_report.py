#!/usr/bin/env python3
"""Отчёт по Google Search Console: превращает данные поиска в список задач.

Зачем: без этого темы для статей выбираются наугад. С этим — видно, что люди
реально ищут, где мы близко к топу и что просело.

РАЗОВАЯ НАСТРОЙКА (нужен Сергей, ~5 минут) — см. docs/seo-automation.md.
Коротко: сервисный аккаунт в Google Cloud → JSON-ключ в secrets/gsc-service-account.json
→ добавить e-mail сервисного аккаунта как пользователя в Search Console.

    python3 tools/seo/gsc_report.py                 # отчёт за 28 дней
    python3 tools/seo/gsc_report.py --days 7
    python3 tools/seo/gsc_report.py --json out.json # машинно-читаемо

Что показывает:
  · Почти в топе (позиции 11-20) — дожать эти страницы дешевле, чем писать новые
  · Спрос без страницы — запросы с показами, под которые нет отдельного материала
  · Просадки — что потеряло позиции против предыдущего периода
  · Сводка по страницам — что реально приносит клики
"""
import argparse
import datetime
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
KEY_PATH = os.path.join(REPO, "secrets", "gsc-service-account.json")
SITE_URL = "sc-domain:pdd-drive.ru"   # доменное свойство, как подтверждено в GSC

SETUP_HINT = """
Нет ключа сервисного аккаунта: %s

Разовая настройка (инструкция целиком — docs/seo-automation.md):
  1. console.cloud.google.com → создать проект (или взять существующий)
  2. Включить "Google Search Console API"
  3. IAM → Service Accounts → создать аккаунт → Keys → Add key → JSON
  4. Положить скачанный JSON сюда: secrets/gsc-service-account.json
  5. В Search Console → Настройки → Пользователи → добавить e-mail
     сервисного аккаунта (вида ...@....iam.gserviceaccount.com) с ролью
     "Полный" или "Ограниченный"
""".strip()

DEPS_HINT = """
Нет библиотек Google API. Установить:
  pip3 install --user google-api-python-client google-auth
""".strip()


def build_service():
    if not os.path.isfile(KEY_PATH):
        print(SETUP_HINT % os.path.relpath(KEY_PATH, REPO))
        return None
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        print(DEPS_HINT)
        return None

    creds = service_account.Credentials.from_service_account_file(
        KEY_PATH,
        scopes=["https://www.googleapis.com/auth/webmasters.readonly"],
    )
    return build("searchconsole", "v1", credentials=creds, cache_discovery=False)


def query(service, start, end, dimensions, limit=25000):
    rows = []
    start_row = 0
    while True:
        resp = service.searchanalytics().query(
            siteUrl=SITE_URL,
            body={
                "startDate": start,
                "endDate": end,
                "dimensions": dimensions,
                "rowLimit": min(limit, 25000),
                "startRow": start_row,
            },
        ).execute()
        batch = resp.get("rows", [])
        rows.extend(batch)
        if len(batch) < 25000 or len(rows) >= limit:
            break
        start_row += len(batch)
    return rows


def site_slugs():
    """Слаги существующих статей — чтобы отличать спрос без страницы."""
    blog = os.path.join(REPO, "web_landing", "ru", "blog")
    if not os.path.isdir(blog):
        return set()
    return {d for d in os.listdir(blog)
            if os.path.isfile(os.path.join(blog, d, "source.json"))}


def article_words():
    """Слова из заголовков статей — грубый признак, что тема уже покрыта."""
    import json as _json
    import re
    blog = os.path.join(REPO, "web_landing", "ru", "blog")
    words = set()
    if not os.path.isdir(blog):
        return words
    for slug in os.listdir(blog):
        p = os.path.join(blog, slug, "source.json")
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8") as f:
            art = _json.load(f)
        for w in re.findall(r"\w{5,}", art.get("title", "").lower()):
            words.add(w[:6])          # грубая нормализация под словоформы
    return words


def fmt_rows(rows, key_name):
    out = []
    for r in rows:
        out.append({
            key_name: r["keys"][0],
            "clicks": r.get("clicks", 0),
            "impressions": r.get("impressions", 0),
            "ctr": round(r.get("ctr", 0) * 100, 2),
            "position": round(r.get("position", 0), 1),
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=28)
    ap.add_argument("--json", help="сохранить полный отчёт в файл")
    ap.add_argument("--min-impressions", type=int, default=5)
    args = ap.parse_args()

    service = build_service()
    if service is None:
        return 1

    today = datetime.date.today()
    # GSC отдаёт данные с задержкой ~2 дня
    end = today - datetime.timedelta(days=2)
    start = end - datetime.timedelta(days=args.days)
    prev_end = start - datetime.timedelta(days=1)
    prev_start = prev_end - datetime.timedelta(days=args.days)

    def iso(d):
        return d.isoformat()

    try:
        cur_q = fmt_rows(query(service, iso(start), iso(end), ["query"]), "query")
        prev_q = fmt_rows(query(service, iso(prev_start), iso(prev_end), ["query"]), "query")
        pages = fmt_rows(query(service, iso(start), iso(end), ["page"]), "page")
    except Exception as e:  # noqa: BLE001
        msg = str(e)
        if "403" in msg or "does not have sufficient permission" in msg:
            print("Google отказал в доступе. Скорее всего, e-mail сервисного "
                  "аккаунта не добавлен в пользователи Search Console.\n\n%s" % msg)
        else:
            print("Ошибка запроса к GSC: %s" % msg)
        return 1

    if not cur_q:
        print("GSC пока не отдаёт данных за %s — %s.\n"
              "Это нормально в первые дни после подтверждения сайта: "
              "статистика появляется через день-два, а накопится за пару недель."
              % (iso(start), iso(end)))
        return 0

    cur_q = [r for r in cur_q if r["impressions"] >= args.min_impressions]
    prev_pos = {r["query"]: r["position"] for r in prev_q}

    striking = sorted(
        [r for r in cur_q if 10.5 <= r["position"] <= 20.5],
        key=lambda r: -r["impressions"])
    covered = article_words()

    def looks_uncovered(q):
        import re
        toks = {w[:6] for w in re.findall(r"\w{5,}", q.lower())}
        return bool(toks) and not (toks & covered)

    gaps = sorted(
        [r for r in cur_q if looks_uncovered(r["query"]) and r["impressions"] >= 10],
        key=lambda r: -r["impressions"])

    drops = []
    for r in cur_q:
        p = prev_pos.get(r["query"])
        if p and r["position"] - p >= 3:
            drops.append(dict(r, prev_position=p,
                              delta=round(r["position"] - p, 1)))
    drops.sort(key=lambda r: -r["impressions"])

    tot_c = sum(r["clicks"] for r in cur_q)
    tot_i = sum(r["impressions"] for r in cur_q)

    print("=" * 66)
    print("Search Console: %s — %s (%d дней)" % (iso(start), iso(end), args.days))
    print("=" * 66)
    print("Клики: %d   Показы: %d   Запросов: %d" % (tot_c, tot_i, len(cur_q)))

    def block(title, rows, extra=None, limit=15):
        print("\n" + title)
        print("-" * 66)
        if not rows:
            print("  (пусто)")
            return
        for r in rows[:limit]:
            key = r.get("query") or r.get("page", "")
            line = "  %-44s поз %-5s пок %-5d кл %d" % (
                key[:44], r["position"], r["impressions"], r["clicks"])
            if extra:
                line += extra(r)
            print(line)
        if len(rows) > limit:
            print("  … ещё %d" % (len(rows) - limit))

    block("ПОЧТИ В ТОПЕ (позиции 11-20) — дожать дешевле, чем писать новое", striking)
    block("СПРОС БЕЗ СТРАНИЦЫ — есть показы, нет своего материала", gaps)
    block("ПРОСАДКИ (позиция упала на 3+ против прошлого периода)", drops,
          extra=lambda r: "  было %.1f (−%.1f)" % (r["prev_position"], r["delta"]))
    block("СТРАНИЦЫ ПО КЛИКАМ", sorted(pages, key=lambda r: -r["clicks"]))

    print("\nЧто делать: «почти в топе» — усилить существующую страницу "
          "(перелинковка, FAQ, полнота).\n«Спрос без страницы» — кандидаты "
          "на новую статью, но только если тема реально наша.\n")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({
                "period": {"start": iso(start), "end": iso(end)},
                "totals": {"clicks": tot_c, "impressions": tot_i},
                "striking_distance": striking,
                "content_gaps": gaps,
                "drops": drops,
                "pages": pages,
                "queries": cur_q,
            }, f, ensure_ascii=False, indent=2)
        print("JSON сохранён: %s" % args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
