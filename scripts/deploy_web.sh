#!/usr/bin/env bash
# Деплой веб-версии страны на её GitHub Pages:
#   ./scripts/deploy_web.sh {ru|by|rs} ["commit message"]
#
# ru → репо pdd-rossiya-app, ветка gh-pages, поддомен app.pdd-drive.ru
#     (главный домен pdd-drive.ru занят лендингом — scripts/deploy_landing.sh)
# by → репо pdd-belarus,  ветка gh-pages, домен pdd-drive.online
#     (локальный клон: /Users/sergei/Documents/pdd-belarus)
# rs → репо pdd-serbia,   ветка gh-pages, поддомен rs.pdd-drive.online
set -euo pipefail

COUNTRY="${1:?usage: deploy_web.sh ru|by|rs [message]}"
MSG="${2:-Deploy $COUNTRY web}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

case "$COUNTRY" in
  ru)
    REMOTE_REPO="https://github.com/degtyarikup-ui/pdd-rossiya-app.git"
    CNAME_DOMAIN="app.pdd-drive.ru"
    TITLE="ПДД Россия 2026 — билеты и экзамен"
    DESC="ПДД Россия 2026 — билеты, темы, экзамен. 800 вопросов, 40 билетов, категории A/B и C/D."
    SHORT="ПДД 2026"
    ;;
  by)
    REMOTE_REPO="https://github.com/degtyarikup-ui/pdd-belarus.git"
    CNAME_DOMAIN="pdd-drive.online"
    TITLE="ПДД Беларусь 2026 — билеты и экзамен ГАИ"
    DESC="ПДД Беларусь 2026 — билеты, темы, экзамен как в ГАИ РБ: 10 вопросов за 15 минут."
    SHORT="ПДД РБ 2026"
    ;;
  rs)
    REMOTE_REPO="https://github.com/degtyarikup-ui/pdd-serbia.git"
    CNAME_DOMAIN="rs.pdd-drive.online"
    TITLE="Auto testovi Srbija 2026 — testovi i vozački ispit"
    DESC="Auto testovi Srbija 2026 — testovi, oblasti, ispit kao na MUP-u: 41 pitanje za 45 minuta, bodovanje i prag 85%."
    SHORT="Auto testovi 2026"
    ;;
  *) echo "unknown country: $COUNTRY"; exit 1 ;;
esac

./scripts/build.sh "$COUNTRY" web

# Пост-обработка статических метаданных под страну.
python3 - "$COUNTRY" <<PYEOF
import json, re, sys
country = sys.argv[1]
title = """$TITLE"""
desc = """$DESC"""
short = """$SHORT"""

p = 'build/web/index.html'
s = open(p).read()
s = re.sub(r'<title>.*?</title>', f'<title>{title}</title>', s, flags=re.DOTALL)
s = re.sub(r'(<meta name="description" content=")[^"]*(">)', rf'\g<1>{desc}\g<2>', s)
s = re.sub(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(">)', rf'\g<1>{short}\g<2>', s)
open(p, 'w').write(s)

p = 'build/web/manifest.json'
m = json.load(open(p))
m['name'] = title
m['short_name'] = short
m['description'] = desc
json.dump(m, open(p, 'w'), ensure_ascii=False, indent=4)
print('patched web metadata for', country)
PYEOF

# Свежая одиночная ревизия gh-pages: git init надёжнее клона
# (пустые/непустые репо, отсутствующая ветка — без ветвлений).
WORKTREE="/tmp/pdd-deploy-$COUNTRY"
rm -rf "$WORKTREE"
mkdir -p "$WORKTREE"
(cd "$ROOT/build/web" && find . -mindepth 1 -maxdepth 1 -exec cp -R {} "$WORKTREE/" \;)

# Статические страницы страны (политика конфиденциальности и т.п.), не часть
# Flutter-сборки — просто лежат рядом и копируются поверх при каждом деплое.
if [ -d "$ROOT/web_static/$COUNTRY" ]; then
  cp -R "$ROOT/web_static/$COUNTRY/." "$WORKTREE/"
fi

touch "$WORKTREE/.nojekyll"
printf '%s' "$CNAME_DOMAIN" > "$WORKTREE/CNAME"

# RU-приложение живёт на поддомене app.* — из поиска его прячем, чтобы не
# конкурировало с лендингом pdd-drive.ru (SEO живёт на главном домене).
if [ "$COUNTRY" = "ru" ]; then
  printf 'User-agent: *\nDisallow: /\n' > "$WORKTREE/robots.txt"
fi

git -C "$WORKTREE" init >/dev/null
git -C "$WORKTREE" checkout -b gh-pages >/dev/null 2>&1 || git -C "$WORKTREE" branch -m gh-pages
git -C "$WORKTREE" add -A
git -C "$WORKTREE" -c user.email="degtyarik.up@gmail.com" -c user.name="degtyarikup-ui" \
  commit -m "$MSG" >/dev/null
git -C "$WORKTREE" push --force "$REMOTE_REPO" gh-pages:gh-pages
rm -rf "$WORKTREE"
echo "Deployed $COUNTRY → https://$CNAME_DOMAIN"
