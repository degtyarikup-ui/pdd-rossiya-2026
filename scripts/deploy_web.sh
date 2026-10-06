#!/usr/bin/env bash
# Деплой веб-версии страны на её GitHub Pages:
#   ./scripts/deploy_web.sh {ru|by|rs} ["commit message"]
#
# ru → /app/ в репо pdd-rossiya-2026, ветка gh-pages, https://pdd-drive.ru/app/
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
    REMOTE_REPO="https://github.com/degtyarikup-ui/pdd-rossiya-2026.git"
    CNAME_DOMAIN="pdd-drive.ru"
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

if [ "$COUNTRY" = "ru" ]; then
  WEB_BASE_HREF=/app/ ./scripts/build.sh "$COUNTRY" web
else
  ./scripts/build.sh "$COUNTRY" web
fi

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

# RU shares the landing repository: preserve its deployed files and replace
# only /app/. BY/RS retain their standalone deployments.
WORKTREE="$(mktemp -d -t pdd-web-deploy.XXXXXX)"
trap 'rm -rf "$WORKTREE"' EXIT
if [ "$COUNTRY" = "ru" ]; then
  git clone --quiet --depth 1 --branch gh-pages "$REMOTE_REPO" "$WORKTREE"
  mkdir -p "$WORKTREE/app"
  rsync -rc --delete "$ROOT/build/web/" "$WORKTREE/app/"
  DEST="$WORKTREE/app"
else
  DEST="$WORKTREE"
  cp -R "$ROOT/build/web/." "$DEST/"
  git -C "$WORKTREE" init >/dev/null
  git -C "$WORKTREE" checkout -b gh-pages >/dev/null 2>&1 || git -C "$WORKTREE" branch -m gh-pages
  printf '%s' "$CNAME_DOMAIN" > "$WORKTREE/CNAME"
fi
if [ -d "$ROOT/web_static/$COUNTRY" ]; then
  cp -R "$ROOT/web_static/$COUNTRY/." "$DEST/"
fi
touch "$WORKTREE/.nojekyll"
if [ "$COUNTRY" = "ru" ]; then
  printf 'User-agent: *\nDisallow: /\n' > "$DEST/robots.txt"
fi
git -C "$WORKTREE" add -A
if git -C "$WORKTREE" diff --cached --quiet; then
  echo "Web deployment unchanged"
else
  git -C "$WORKTREE" -c user.email="degtyarik.up@gmail.com" -c user.name="degtyarikup-ui" commit -m "$MSG" >/dev/null
  if [ "$COUNTRY" = "ru" ]; then
    git -C "$WORKTREE" push "$REMOTE_REPO" gh-pages:gh-pages
  else
    git -C "$WORKTREE" push --force "$REMOTE_REPO" gh-pages:gh-pages
  fi
fi
if [ "$COUNTRY" = "ru" ]; then
  echo "Deployed ru → https://pdd-drive.ru/app/"
else
  echo "Deployed $COUNTRY → https://$CNAME_DOMAIN"
fi
