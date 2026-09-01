#!/usr/bin/env python3
"""Получить refresh token Google для автопостинга (Google Диск + YouTube).

Как запустить: открой Терминал и вставь одну строку:

    python3 /Users/sergei/Documents/pdd/server/install-notifier/get_google_token.py

Скрипт спросит Client ID и Client Secret (их берём в Google Cloud, шаг 1
инструкции SOCIAL_SETUP.md), откроет браузер, попросит войти в тот Google-
аккаунт, где лежит папка с роликами и заведён YouTube-канал, и напечатает
refresh token — его нужно вставить в админку.

Ничего никуда не отправляется, кроме самого Google: обмен кода на токен идёт
напрямую с oauth2.googleapis.com, ответ печатается на экран.
"""

import http.server
import json
import secrets
import socket
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser

# drive.readonly — читать папку с роликами; youtube.upload — заливать Shorts.
SCOPES = [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube.readonly",
]

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"

PAGE_OK = """<!doctype html><meta charset="utf-8">
<body style="font-family:-apple-system,sans-serif;padding:60px;text-align:center">
<h2>Готово</h2><p>Возвращайся в Терминал — там напечатан refresh token.</p></body>"""

PAGE_FAIL = """<!doctype html><meta charset="utf-8">
<body style="font-family:-apple-system,sans-serif;padding:60px;text-align:center">
<h2>Не получилось</h2><p>Подробности — в Терминале.</p></body>"""


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    """Одноразовый приёмник ответа Google на локальном порту."""

    result: dict = {}

    def do_GET(self):  # noqa: N802 (имя задано базовым классом)
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        CallbackHandler.result = {k: v[0] for k, v in query.items()}
        ok = "code" in CallbackHandler.result
        body = (PAGE_OK if ok else PAGE_FAIL).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, *args):  # тишина вместо логов http.server
        pass


def main() -> int:
    print("\n=== Refresh token Google для автопостинга ПДД ===\n")
    client_id = input("Client ID (…apps.googleusercontent.com): ").strip()
    client_secret = input("Client Secret: ").strip()
    if not client_id or not client_secret:
        print("Пусто — заполни оба значения и запусти снова.")
        return 1

    port = free_port()
    redirect_uri = f"http://localhost:{port}"
    state = secrets.token_urlsafe(16)

    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        # access_type=offline + prompt=consent — единственный способ получить
        # refresh token: без prompt Google отдаёт его только в первый раз.
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    }
    url = AUTH_URL + "?" + urllib.parse.urlencode(params)

    print("\nСейчас откроется браузер. Войди в нужный Google-аккаунт и разреши доступ.")
    print("Если Google скажет «приложение не проверено» — «Дополнительные настройки» → «Перейти».")
    print(f"\nЕсли браузер не открылся сам, вставь в него эту ссылку:\n{url}\n")

    server = http.server.HTTPServer(("127.0.0.1", port), CallbackHandler)
    webbrowser.open(url)
    server.serve_forever()

    result = CallbackHandler.result
    if result.get("state") != state:
        print("Ответ пришёл с чужим state — на всякий случай останавливаюсь.")
        return 1
    if "code" not in result:
        print("Google вернул ошибку:", result.get("error", "без объяснения"))
        return 1

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
        print("Google отклонил обмен кода на токен:", exc.read().decode("utf-8", "replace"))
        return 1

    refresh = tokens.get("refresh_token")
    if not refresh:
        print("Refresh token не пришёл. Обычно помогает отозвать доступ приложению")
        print("на https://myaccount.google.com/permissions и запустить скрипт заново.")
        return 1

    print("\n────────────────────────────────────────────────────────")
    print("REFRESH TOKEN (вставь в админку, шаг 1):\n")
    print(refresh)
    print("\n────────────────────────────────────────────────────────")
    print("Туда же вставь Client ID и Client Secret и нажми «Сохранить»,")
    print("потом — «Проверить подключение».")
    return 0


if __name__ == "__main__":
    sys.exit(main())
