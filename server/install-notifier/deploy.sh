#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Полу-автоматический деплой воркера уведомлений о новой установке.
#
# Как запустить: открой Терминал и вставь ОДНУ строку:
#     bash /Users/sergei/Documents/pdd/server/install-notifier/deploy.sh
#
# Что нужно от тебя по ходу (скрипт сам подскажет, когда):
#   1) один раз нажать «Allow» в открывшемся браузере (вход в Cloudflare);
#   2) вставить токен бота (от @BotFather);
#   3) вставить id чата (число; узнать — добавь в чат бота @getidsbot).
# Всё остальное скрипт сделает сам. Токен вводишь ты — я его не вижу.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "✋ Не вижу Node.js. Открой обычный Терминал (где работает 'node -v') и запусти скрипт оттуда."
  exit 1
fi

# Запускаем wrangler без глобальной установки (через npx).
WR="npx --yes wrangler@4"

echo "==> 1/5  Вход в Cloudflare"
if $WR whoami >/dev/null 2>&1; then
  echo "         Уже вошёл — пропускаю."
else
  echo "         Сейчас откроется браузер. Нажми там кнопку «Allow»."
  echo "         Если аккаунта Cloudflare нет — там же будет «Sign up» (бесплатно)."
  echo "         (первый запуск чуть подумает — скачивает инструмент)"
  $WR login
fi

echo
echo "==> 2/5  Токен бота (от @BotFather)"
echo "         Вставь токен и нажми Enter. Ввод скрыт — так и должно быть."
$WR secret put BOT_TOKEN

echo
echo "==> 3/6  ID чата, куда слать уведомления"
echo "         Это число (у групп начинается с -100…). Узнать: @getidsbot в нужном чате."
$WR secret put CHAT_ID

echo
echo "==> 4/6  Пароль для входа в веб-админку (/admin)"
echo "         Придумай пароль для просмотра статистики в браузере."
$WR secret put ADMIN_PASSWORD

echo
echo "==> 5/6  Хранилище для аналитики и номеров #N"
if grep -qE 'id = "[0-9a-f]{32}"' wrangler.toml; then
  echo "         Уже настроено — пропускаю."
else
  KV_OUT="$($WR kv namespace create INSTALLS 2>&1 || true)"
  KV_ID="$(printf '%s' "$KV_OUT" | grep -oE '[0-9a-f]{32}' | head -1 || true)"
  if [[ -z "$KV_ID" ]]; then
    # Уже существует от прошлого запуска — берём id из списка (парсим JSON через node).
    KV_ID="$($WR kv namespace list 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const a=JSON.parse(s);const m=a.find(x=>/INSTALLS/.test(x.title||""));if(m)process.stdout.write(m.id)}catch(e){}})' || true)"
  fi
  if [[ -n "$KV_ID" ]]; then
    printf '\n[[kv_namespaces]]\nbinding = "INSTALLS"\nid = "%s"\n' "$KV_ID" >> wrangler.toml
    echo "         Готово (id: $KV_ID)."
  else
    echo "         ⚠ Не удалось создать автоматически — воркер выйдет без номера #N"
    echo "           (будет показывать install_id). Не критично, добавим позже."
  fi
fi

echo
echo "==> 6/6  Публикую воркер…"
# Запускаем деплой «вживую» (без перехвата вывода) — чтобы при ПЕРВОМ деплое
# wrangler мог спросить имя workers.dev-субдомена и показать ошибки/ссылку.
if ! $WR deploy; then
  echo
  echo "✋ Деплой не удался — скопируй ошибку выше и пришли мне."
  exit 1
fi

echo
echo "══════════════════════════════════════════════════════════════════════"
echo "  ✅ ГОТОВО. Найди выше строку вида"
echo "     https://pdd-install-notifier.***.workers.dev"
echo "  — это ссылка твоего воркера. Скопируй её и пришли мне."
echo "══════════════════════════════════════════════════════════════════════"
