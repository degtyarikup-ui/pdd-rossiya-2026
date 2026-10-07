#!/usr/bin/env bash
# Деплой веб-версии приложения:
#   ./scripts/deploy_web.sh ru ["commit message"]
#
# /app/ в репо pdd-rossiya-2026, ветка gh-pages, https://pdd-drive.ru/app/
# (главный домен pdd-drive.ru занят лендингом — scripts/deploy_landing.sh)
set -euo pipefail

COUNTRY="${1:?usage: deploy_web.sh ru [message]}"
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
  *) echo "unknown country: $COUNTRY"; exit 1 ;;
esac

WEB_BASE_HREF=/app/ ./scripts/build.sh "$COUNTRY" web

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

# The landing repository is shared: preserve its deployed files and replace
# only /app/.
WORKTREE="$(mktemp -d -t pdd-web-deploy.XXXXXX)"
trap 'rm -rf "$WORKTREE"' EXIT
git clone --quiet --depth 1 --branch gh-pages "$REMOTE_REPO" "$WORKTREE"
mkdir -p "$WORKTREE/app"
rsync -rc --delete "$ROOT/build/web/" "$WORKTREE/app/"
DEST="$WORKTREE/app"
if [ -d "$ROOT/web_static/$COUNTRY" ]; then
  cp -R "$ROOT/web_static/$COUNTRY/." "$DEST/"
fi
touch "$WORKTREE/.nojekyll"
printf 'User-agent: *\nDisallow: /\n' > "$DEST/robots.txt"
git -C "$WORKTREE" add -A
if git -C "$WORKTREE" diff --cached --quiet; then
  echo "Web deployment unchanged"
else
  git -C "$WORKTREE" -c user.email="degtyarik.up@gmail.com" -c user.name="degtyarikup-ui" commit -m "$MSG" >/dev/null
  git -C "$WORKTREE" push "$REMOTE_REPO" gh-pages:gh-pages
fi
echo "Deployed ru → https://pdd-drive.ru/app/"
