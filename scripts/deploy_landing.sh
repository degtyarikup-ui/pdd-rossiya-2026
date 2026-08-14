#!/usr/bin/env bash
# Деплой лендинга (маркетинговый сайт + блог + SEO-файлы) на главный домен:
#   ./scripts/deploy_landing.sh ru ["commit message"]
#
# ru → репо pdd-rossiya-2026, ветка gh-pages, домен pdd-drive.ru
# Источник: web_landing/ru/ — чистая статика, без сборки.
# Веб-версия самого приложения деплоится отдельно на app.pdd-drive.ru
# (scripts/deploy_web.sh ru).
set -euo pipefail

COUNTRY="${1:?usage: deploy_landing.sh ru [message]}"
MSG="${2:-Deploy $COUNTRY landing}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

case "$COUNTRY" in
  ru)
    REMOTE_REPO="https://github.com/degtyarikup-ui/pdd-rossiya-2026.git"
    CNAME_DOMAIN="pdd-drive.ru"
    ;;
  *) echo "unknown country: $COUNTRY (лендинг пока только ru)"; exit 1 ;;
esac

SRC="$ROOT/web_landing/$COUNTRY"
[ -d "$SRC" ] || { echo "нет исходников лендинга: $SRC"; exit 1; }

# SEO-регресс-аудит: битые ссылки/якоря, невалидный JSON-LD, дубли title,
# рассинхрон sitemap, картинки без alt. Ошибки блокируют деплой —
# такие поломки не видны глазом, но стоят трафика.
# Обойти в аварийном случае: SKIP_SEO_AUDIT=1 ./scripts/deploy_landing.sh ru "..."
if [ "${SKIP_SEO_AUDIT:-0}" != "1" ] && [ "$COUNTRY" = "ru" ]; then
  if ! python3 "$ROOT/tools/seo/audit.py" --quiet; then
    echo ""
    echo "Деплой остановлен: SEO-аудит нашёл ошибки (выше)."
    echo "Почини их или запусти с SKIP_SEO_AUDIT=1, если это осознанно."
    exit 1
  fi
fi

WORKTREE="/tmp/pdd-landing-deploy-$COUNTRY"
rm -rf "$WORKTREE"
mkdir -p "$WORKTREE"
cp -R "$SRC/." "$WORKTREE/"

touch "$WORKTREE/.nojekyll"
printf '%s' "$CNAME_DOMAIN" > "$WORKTREE/CNAME"

git -C "$WORKTREE" init >/dev/null
git -C "$WORKTREE" checkout -b gh-pages >/dev/null 2>&1 || git -C "$WORKTREE" branch -m gh-pages
git -C "$WORKTREE" add -A
git -C "$WORKTREE" -c user.email="degtyarik.up@gmail.com" -c user.name="degtyarikup-ui" \
  commit -m "$MSG" >/dev/null
git -C "$WORKTREE" push --force "$REMOTE_REPO" gh-pages:gh-pages
rm -rf "$WORKTREE"
echo "Deployed $COUNTRY landing → https://$CNAME_DOMAIN"
