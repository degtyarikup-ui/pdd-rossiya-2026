#!/usr/bin/env python3
"""Планирует Shorts на YouTube через Data API v3, чередуя два каталога через день.

Первый запуск откроет браузер для OAuth (нужен client_secret.json из Google Cloud).
Состояние в state.json — повторный запуск продолжает с места остановки.
"""

import argparse
import json
from datetime import datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]
HERE = Path(__file__).parent
STATE = HERE / "state.json"

TITLE = "ПДД"
DESCRIPTION = (
    "Ссылка на приложение для подготовки к экзамену — в шапке профиля\n\n"
    "#пдд #пдд2026 #дорожныйзнак #автошкола #экзаменгибдд #гибдд #водитель"
)
TAGS = ["пдд", "пдд2026", "дорожныйзнак", "автошкола", "экзаменгибдд", "гибдд", "водитель"]
PUBLISH_AT = time(19, 20)
TZ = ZoneInfo("Europe/Moscow")

# videos.insert стоит 1600 unit, дефолтная квота 10000/день
DAILY_LIMIT = 6


def authenticate():
    creds = None
    token = HERE / "token.json"
    if token.exists():
        creds = Credentials.from_authorized_user_file(str(token), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                str(HERE / "client_secret.json"), SCOPES
            )
            creds = flow.run_local_server(port=0)
        token.write_text(creds.to_json())
    return build("youtube", "v3", credentials=creds)


def build_queue(billets_dir: Path, signs_dir: Path, start: datetime, skip_upto: int):
    """Чередует билет/знак: билеты на чётные шаги, знаки на нечётные.

    Файлы с числовым префиксом <= skip_upto пропускаются — они уже запланированы
    вручную через YouTube Studio.
    """

    def pool(d: Path):
        return sorted(p for p in d.glob("*.mp4") if int(p.name.split("_", 1)[0]) > skip_upto)

    billets = pool(billets_dir)
    signs = pool(signs_dir)
    queue = []
    for i in range(len(billets) + len(signs)):
        pool, idx = (billets, i // 2) if i % 2 == 0 else (signs, i // 2)
        if idx < len(pool):
            publish_date = (start + timedelta(days=i)).date()
            queue.append(
                {
                    "path": str(pool[idx]),
                    "publish_at": datetime.combine(publish_date, PUBLISH_AT, TZ).isoformat(),
                }
            )
    return queue


def upload(youtube, item):
    body = {
        "snippet": {"title": TITLE, "description": DESCRIPTION, "tags": TAGS, "categoryId": "2"},
        "status": {
            "privacyStatus": "private",
            "publishAt": item["publish_at"],
            "selfDeclaredMadeForKids": False,
        },
    }
    media = MediaFileUpload(item["path"], chunksize=-1, resumable=True)
    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)
    response = None
    while response is None:
        _, response = request.next_chunk()
    return response["id"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--billets", type=Path, default=Path.home() / "Desktop/pdd_reels")
    parser.add_argument("--signs", type=Path, default=Path.home() / "Desktop/123")
    parser.add_argument("--start", default="2026-08-30", help="дата первой публикации YYYY-MM-DD")
    parser.add_argument("--limit", type=int, default=DAILY_LIMIT)
    parser.add_argument(
        "--skip-upto", type=int, default=8, help="пропустить файлы с префиксом <= N (уже залиты)"
    )
    args = parser.parse_args()

    if STATE.exists():
        state = json.loads(STATE.read_text())
    else:
        start = datetime.fromisoformat(args.start)
        state = {
            "queue": build_queue(args.billets, args.signs, start, args.skip_upto),
            "done": [],
        }

    pending = [i for i in state["queue"] if i["path"] not in state["done"]]
    if not pending:
        print("Очередь пуста — всё запланировано.")
        return

    youtube = authenticate()
    for item in pending[: args.limit]:
        video_id = upload(youtube, item)
        state["done"].append(item["path"])
        STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2))
        print(f"{Path(item['path']).name} → {item['publish_at'][:10]} (https://youtu.be/{video_id})")

    left = len(pending) - min(args.limit, len(pending))
    print(f"\nОсталось: {left}. Запустите скрипт снова завтра.")


if __name__ == "__main__":
    main()
