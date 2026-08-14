#!/usr/bin/env python3
"""Монитор устаревания фактов в статьях блога.

Зачем: статьи ссылаются на суммы штрафов, статьи КоАП/УК и номера постановлений.
Законы меняются, а текст — нет. Мы это уже ловили вручную: в статье об обгоне
штраф по ч.4 ст.12.15 КоАП был 5000 ₽, хотя актуально 7500 ₽. Такая ошибка
не ломает сайт и не видна в аналитике — она просто подрывает доверие
и «съедает» E-E-A-T, ради которого всё и писалось.

Скрипт сам НЕ ходит в интернет: он находит проверяемые утверждения и ведёт
реестр с датой последней сверки. Собственно сверку делает агент (веб-поиск)
по списку из `due` — и отмечает результат через `verify`.

    python3 tools/seo/fact_watch.py scan          # обновить реестр
    python3 tools/seo/fact_watch.py due           # что пора перепроверить
    python3 tools/seo/fact_watch.py due --risk high
    python3 tools/seo/fact_watch.py verify <id> [--note "сверено с consultant.ru"]
    python3 tools/seo/fact_watch.py verify --all-listed   # отметить всё из последнего due

Реестр: docs/fact-registry.json (в гите, чтобы история сверок не терялась).
"""
import argparse
import datetime
import glob
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BLOG = os.path.join(REPO, "web_landing", "ru", "blog")
REGISTRY = os.path.join(REPO, "docs", "fact-registry.json")

TAG_RE = re.compile(r"<[^>]+>")

# Что считаем проверяемым утверждением. Риск = как часто это устаревает.
#   high   — меняется поправками к КоАП, ловили реальную ошибку
#   medium — номера актов и юридические сроки, заменяются новыми редакциями
#   low    — пункты ПДД и скорости: нумерация стабильна, а цифры у нас взяты
#            из официальной базы вопросов приложения, а не сочинены
PATTERNS = [
    ("high",   "сумма",        r"\d[\d\s  ]*(?:₽|руб\.?|рублей)"),
    ("high",   "КоАП/УК",      r"(?:ч\.\s*\d+\s*)?ст(?:атья|атьи|\.)\s*\d+(?:\.\d+)?\s*(?:КоАП|УК)"),
    ("medium", "НПА",          r"(?:постановлени\w+|приказ\w*|федеральн\w+ закон\w*)[^.]{0,70}?№\s*[\d/-]+"),
    ("medium", "срок",         r"\d+\s*(?:календарн\w+\s*)?(?:дней|дня|суток|месяц\w+|лет|года)"),
    ("low",    "пункт ПДД",    r"[Пп]ункт\w*\s*\d+\.\d+"),
    ("low",    "скорость",     r"\d+\s*км/ч"),
]

RISK_ORDER = {"high": 0, "medium": 1, "low": 2}
# Как часто пересверять, дней
DEFAULT_MAX_AGE = {"high": 90, "medium": 180, "low": 365}


def today():
    return datetime.date.today().isoformat()


def strip_tags(s):
    import html as html_mod
    return html_mod.unescape(TAG_RE.sub("", s))


def sentences(text):
    """Грубое деление на предложения — достаточно, чтобы дать контекст факту."""
    for part in re.split(r"(?<=[.!?])\s+", text):
        part = " ".join(part.split())
        if part:
            yield part


def claim_id(slug, snippet):
    """Стабильный id. Меняется, если правится сам текст утверждения —
    это правильно: изменённое утверждение надо сверить заново."""
    h = hashlib.sha1(("%s|%s" % (slug, snippet)).encode("utf-8")).hexdigest()
    return h[:10]


def scan_articles():
    found = {}
    for path in sorted(glob.glob(os.path.join(BLOG, "*", "source.json"))):
        with open(path, encoding="utf-8") as f:
            art = json.load(f)
        if not art.get("published", True):
            continue
        slug = art["slug"]
        text = strip_tags(art.get("bodyHtml", ""))
        for q in art.get("faq", []):
            text += " " + strip_tags(q.get("aHtml", ""))

        for sent in sentences(text):
            if len(sent) > 400:
                sent = sent[:400] + "…"
            for risk, kind, pat in PATTERNS:
                hits = re.findall(pat, sent)
                if not hits:
                    continue
                cid = claim_id(slug, sent)
                # у предложения берём самый рискованный тип
                prev = found.get(cid)
                if prev and RISK_ORDER[prev["risk"]] <= RISK_ORDER[risk]:
                    continue
                found[cid] = {
                    "id": cid,
                    "slug": slug,
                    "risk": risk,
                    "kind": kind,
                    "match": hits[0].strip() if isinstance(hits[0], str) else str(hits[0]),
                    "claim": sent,
                    "url": "https://pdd-drive.ru/blog/%s/" % slug,
                }
    return found


def load_registry():
    if os.path.isfile(REGISTRY):
        with open(REGISTRY, encoding="utf-8") as f:
            return json.load(f)
    return {"updated": None, "claims": {}}


def save_registry(reg):
    os.makedirs(os.path.dirname(REGISTRY), exist_ok=True)
    reg["updated"] = today()
    with open(REGISTRY, "w", encoding="utf-8") as f:
        json.dump(reg, f, ensure_ascii=False, indent=2, sort_keys=True)


def cmd_scan(args):
    reg = load_registry()
    found = scan_articles()
    claims = reg.get("claims", {})

    added = 0
    for cid, c in found.items():
        if cid in claims:
            claims[cid].update({k: c[k] for k in
                                ("slug", "risk", "kind", "match", "claim", "url")})
        else:
            c["verified_on"] = None
            c["note"] = ""
            claims[cid] = c
            added += 1

    # утверждения, которых больше нет в текстах (статья переписана/удалена)
    gone = [cid for cid in claims if cid not in found]
    for cid in gone:
        del claims[cid]

    reg["claims"] = claims
    save_registry(reg)

    by_risk = {}
    for c in claims.values():
        by_risk[c["risk"]] = by_risk.get(c["risk"], 0) + 1
    print("Реестр обновлён: %d утверждений (+%d новых, -%d исчезнувших)"
          % (len(claims), added, len(gone)))
    print("  по риску: " + ", ".join(
        "%s — %d" % (r, by_risk.get(r, 0)) for r in ("high", "medium", "low")))
    print("  файл: %s" % os.path.relpath(REGISTRY, REPO))
    return 0


def _due_claims(reg, risk_filter, max_age):
    now = datetime.date.today()
    due = []
    for c in reg.get("claims", {}).values():
        if risk_filter and c["risk"] != risk_filter:
            continue
        limit = max_age or DEFAULT_MAX_AGE[c["risk"]]
        v = c.get("verified_on")
        if not v:
            age = None
        else:
            age = (now - datetime.date.fromisoformat(v)).days
            if age < limit:
                continue
        due.append((c, age))
    due.sort(key=lambda x: (RISK_ORDER[x[0]["risk"]], x[0]["slug"]))
    return due


def cmd_due(args):
    reg = load_registry()
    if not reg.get("claims"):
        print("Реестр пуст — сначала запусти: python3 tools/seo/fact_watch.py scan")
        return 1

    due = _due_claims(reg, args.risk, args.days)
    if not due:
        print("Всё сверено — перепроверять нечего.")
        return 0

    print("К перепроверке: %d утверждений\n" % len(due))
    listed = []
    for c, age in due[: args.limit]:
        listed.append(c["id"])
        when = "никогда не сверялось" if age is None else "сверено %d дн. назад" % age
        print("[%s] %s · %s · %s" % (c["id"], c["risk"].upper(), c["kind"], when))
        print("    %s" % c["url"])
        print("    нашли: %s" % c["match"])
        print("    %s\n" % c["claim"])

    if len(due) > args.limit:
        print("… и ещё %d (покажи больше: --limit %d)"
              % (len(due) - args.limit, len(due)))

    with open(os.path.join(REPO, "docs", ".fact-watch-last-due.json"),
              "w", encoding="utf-8") as f:
        json.dump(listed, f)
    return 0


def cmd_verify(args):
    reg = load_registry()
    claims = reg.get("claims", {})

    if args.all_listed:
        p = os.path.join(REPO, "docs", ".fact-watch-last-due.json")
        if not os.path.isfile(p):
            print("Нет списка из последнего `due`.")
            return 1
        with open(p, encoding="utf-8") as f:
            ids = json.load(f)
    else:
        ids = args.ids

    if not ids:
        print("Укажи id утверждений или --all-listed")
        return 1

    n = 0
    for cid in ids:
        if cid not in claims:
            print("нет такого id: %s" % cid)
            continue
        claims[cid]["verified_on"] = today()
        if args.note:
            claims[cid]["note"] = args.note
        n += 1

    save_registry(reg)
    print("Отмечено сверенными сегодня: %d" % n)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("scan", help="обновить реестр утверждений из статей")
    p.set_defaults(func=cmd_scan)

    p = sub.add_parser("due", help="что пора перепроверить")
    p.add_argument("--risk", choices=["high", "medium", "low"])
    p.add_argument("--days", type=int, help="свой порог давности вместо стандартного")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=cmd_due)

    p = sub.add_parser("verify", help="отметить утверждения сверенными")
    p.add_argument("ids", nargs="*")
    p.add_argument("--all-listed", action="store_true",
                   help="отметить всё, что показал последний due")
    p.add_argument("--note", default="")
    p.set_defaults(func=cmd_verify)

    args = ap.parse_args()
    if not getattr(args, "func", None):
        ap.print_help()
        return 1
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
