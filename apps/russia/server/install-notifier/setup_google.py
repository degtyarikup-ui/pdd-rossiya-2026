#!/usr/bin/env python3
"""Настроить доступ Google для автопостинга: Диск + YouTube.

Запуск:
    python3 /Users/sergei/Documents/pdd/server/install-notifier/setup_google.py

От тебя нужно:
  • Client ID и Client Secret — их выдаёт Google Cloud, когда создаёшь ключ
    типа «Desktop app» (ссылка есть в SOCIAL_SETUP.md);
  • один раз войти в браузере в тот Google-аккаунт, где лежит папка с роликами
    и YouTube-канал, и нажать «Разрешить»;
  • пароль админки.

Дальше скрипт сам получает refresh token, включает нужные API, записывает
доступ в админку и проверяет, что всё живо.

Почему нельзя обойтись без создания ключа: Google не разрешает сторонним
инструментам (в том числе своему же gcloud) запрашивать права на YouTube —
такая попытка заканчивается страницей «Приложение заблокировано». Права на
загрузку видео выдаются только собственному приложению проекта.
"""

import getpass
import glob
import http.server
import json
import os
import secrets
import socket
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

ADMIN_URL = "https://pdd-install-notifier.sergei-pdd.workers.dev"

SCOPES = [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
]

NEEDED_APIS = ["drive.googleapis.com", "youtube.googleapis.com"]

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"

PAGE_OK = """<!doctype html><meta charset="utf-8">
<body style="font-family:-apple-system,sans-serif;padding:60px;text-align:center">
<h2>Готово</h2><p>Возвращайся в Терминал.</p></body>"""

PAGE_FAIL = """<!doctype html><meta charset="utf-8">
<body style="font-family:-apple-system,sans-serif;padding:60px;text-align:center">
<h2>Не получилось</h2><p>Подробности — в Терминале.</p></body>"""


def say(step, text):
    print(f"\n{step} {text}", flush=True)


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    """Одноразовый приёмник ответа Google на локальном порту."""

    result: dict = {}

    def do_GET(self):  # noqa: N802 (имя задано базовым классом)
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        CallbackHandler.result = {k: v[0] for k, v in query.items()}
        body = (PAGE_OK if "code" in CallbackHandler.result else PAGE_FAIL).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, *args):  # тишина вместо логов http.server
        pass


def post_json(url, payload, headers=None):
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST")
    request.add_header("Content-Type", "application/json")
    # Cloudflare отбивает запросы с UA по умолчанию («Python-urllib») на входе,
    # до воркера — отсюда был непонятный 403.
    request.add_header("User-Agent", "pdd-setup-script/1.0")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    with urllib.request.urlopen(request, timeout=60) as resp:
        return json.loads(resp.read() or b"{}")


def get_refresh_token(client_id: str, client_secret: str):
    port = free_port()
    redirect_uri = f"http://localhost:{port}"
    state = secrets.token_urlsafe(16)

    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        # access_type=offline + prompt=consent — единственный способ получить
        # refresh token: без них Google отдаёт его только в самый первый раз.
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    }
    url = AUTH_URL + "?" + urllib.parse.urlencode(params)

    print("      Открываю браузер. Войди в аккаунт с папкой роликов и каналом,")
    print("      затем «Разрешить». Если Google скажет «приложение не проверено» —")
    print("      «Дополнительные настройки» → «Перейти».")
    print(f"\n      Если браузер не открылся сам:\n      {url}\n")

    server = http.server.HTTPServer(("127.0.0.1", port), CallbackHandler)
    webbrowser.open(url)
    server.serve_forever()

    result = CallbackHandler.result
    if result.get("state") != state:
        print("      Ответ пришёл с чужим state — останавливаюсь.")
        return None
    if "code" not in result:
        print("      Google вернул ошибку:", result.get("error", "без объяснения"))
        return None

    data = urllib.parse.urlencode({
        "code": result["code"],
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }).encode()

    try:
        with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=data)) as resp:
            tokens = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        print("      Google отклонил обмен кода на токен:", exc.read().decode("utf-8", "replace")[:300])
        return None

    refresh = tokens.get("refresh_token")
    if not refresh:
        print("      Refresh token не пришёл. Отзови доступ приложению на")
        print("      https://myaccount.google.com/permissions и запусти скрипт заново.")
        return None

    return refresh, tokens.get("access_token")


def enable_apis(access_token: str, project: str):
    for api in NEEDED_APIS:
        url = f"https://serviceusage.googleapis.com/v1/projects/{project}/services/{api}:enable"
        try:
            post_json(url, {}, {"Authorization": "Bearer " + access_token})
            print(f"      ✓ {api}")
        except urllib.error.HTTPError as exc:
            print(f"      ! {api}: включить не вышло ({exc.code}) — включи вручную:")
            print(f"        https://console.cloud.google.com/apis/library/{api}?project={project}")


def main() -> int:
    print("\n=== Доступ Google для автопостинга ===")
    print("Client ID и Client Secret берутся при создании ключа «Desktop app»")
    print("в Google Cloud (ссылка — в SOCIAL_SETUP.md).\n")

    # Файл ключа, скачанный из Google Cloud, избавляет от ручного копирования.
    client_file = None
    for arg in sys.argv[1:]:
        if arg.startswith("--client-file="):
            client_file = os.path.expanduser(arg.split("=", 1)[1])
    if not client_file:
        candidates = sorted(
            glob.glob(os.path.expanduser("~/Downloads/client_secret_*.json")),
            key=os.path.getmtime, reverse=True,
        )
        client_file = candidates[0] if candidates else None

    if client_file and os.path.exists(client_file):
        data = json.load(open(client_file))
        block = data.get("installed") or data.get("web") or {}
        client_id = block.get("client_id", "")
        client_secret = block.get("client_secret", "")
        print(f"Беру ключ из файла: {os.path.basename(client_file)}")
    else:
        client_id = input("Client ID (…apps.googleusercontent.com): ").strip()
        client_secret = input("Client Secret: ").strip()
    if not client_id or not client_secret:
        print("Пусто — заполни оба значения и запусти снова.")
        return 1

    say("1/4", "Вход в Google")
    tokens = get_refresh_token(client_id, client_secret)
    if not tokens:
        return 1
    refresh_token, access_token = tokens
    print("      ✓ доступ получен")

    say("2/4", "Включаю нужные API")
    # Номер проекта зашит в Client ID: 1234567890-xxxx.apps.googleusercontent.com
    project = client_id.split("-")[0] if "-" in client_id else ""
    if project.isdigit() and access_token:
        enable_apis(access_token, project)
    else:
        print("      Проект по Client ID не определился — включи API вручную:")
        for api in NEEDED_APIS:
            print(f"        https://console.cloud.google.com/apis/library/{api}")

    say("3/4", "Записываю доступ в админку")
    # В неинтерактивном запуске пароль передаётся переменной окружения.
    password = (os.environ.get("PDD_ADMIN_PASSWORD") or "").strip()
    if not password:
        password = getpass.getpass("      Пароль админки (ввод скрыт): ").strip()
    try:
        result = post_json(
            ADMIN_URL + "/api/admin/social/settings",
            {
                "googleClientId": client_id,
                "googleClientSecret": client_secret,
                "googleRefreshToken": refresh_token,
            },
            {"Authorization": "Bearer " + password},
        )
    except urllib.error.HTTPError as exc:
        print("      Админка не приняла настройки (HTTP %s). Пароль верный?" % exc.code)
        print("\n      Refresh token на случай ручного ввода:\n      " + refresh_token)
        return 1

    if not result.get("ok"):
        print("      Админка не приняла настройки:", result)
        return 1
    print("      ✓ записано")

    say("4/4", "Проверяю доступ")
    checks = post_json(ADMIN_URL + "/api/admin/social/check", {},
                       {"Authorization": "Bearer " + password}).get("checks", [])
    for check in checks:
        print(f"      {'✓' if check.get('ok') else '✕'} {check.get('name')}: {check.get('message')}")

    print("\nГотово. Дальше — в админке добавить аккаунт и указать папку с роликами.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
