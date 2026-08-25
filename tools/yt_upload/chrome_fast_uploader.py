#!/usr/bin/env python3
"""
Быстрый и надежный планировщик YouTube Shorts для канала «ПДД 2026»
через AppleScript + JS в активном окне Google Chrome.

Автоматически отслеживает суточный лимит загрузок YouTube (Daily upload limit reached)
и при его достижении аккуратно останавливает работу, сохраняя прогресс в state.json.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

DEFAULT_BILLETS_DIR = Path("/Users/sergei/Desktop/PDD_1")
DEFAULT_SIGNS_DIR = Path("/Users/sergei/Desktop/PDD_2")
STATE_FILE = Path(__file__).parent / "upload_state.json"
STUDIO_URL = "https://studio.youtube.com/channel/UCYycIcL6qvFE3TyQ8qT58bg/videos/short?filter=%5B%5D&sort=%7B%22columnType%22%3A%22date%22%2C%22sortOrder%22%3A%22DESCENDING%22%7D"

TITLE = "ПДД"

DESCRIPTION_BILLET = """Ссылка на приложение для подготовки к экзамену — в шапке профиля

#пдд #пдд2026 #билетыпдд #автошкола #экзаменпдд #гибдд #водитель"""

DESCRIPTION_SIGN = """Ссылка на приложение для подготовки к экзамену — в шапке профиля

#пдд #пдд2026 #дорожныезнаки #автошкола #экзаменпдд #гибдд #водитель"""

START_DATE_NN2 = datetime(2026, 8, 16)


def run_applescript(script: str) -> str:
    res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"AppleScript error: {res.stderr.strip()}")
    return res.stdout.strip()


def run_js(js_code: str, timeout_sec: int = 30) -> str:
    """Выполняет JavaScript во вкладке YouTube Studio в любом окне Chrome."""
    wrapped_js = f"(() => {{\n{js_code}\n}})()"
    temp_js_path = "/tmp/yt_exec.js"
    with open(temp_js_path, "w", encoding="utf-8") as f:
        f.write(wrapped_js)

    as_cmd = f"""
    set jsContent to read "{temp_js_path}" as «class utf8»
    tell application "Google Chrome"
        set foundTab to missing value
        repeat with w in windows
            repeat with t in tabs of w
                if URL of t contains "studio.youtube.com" then
                    set foundTab to t
                    exit repeat
                end if
            end repeat
            if foundTab is not missing value then exit repeat
        end repeat
        
        if foundTab is not missing value then
            execute foundTab javascript jsContent
        else
            execute active tab of front window javascript jsContent
        end if
    end tell
    """
    return run_applescript(as_cmd)


def check_daily_limit() -> bool:
    """
    Проверяет наличие сообщения о суточном лимите YouTube в любых элементах страницы.
    Возвращает True, если обнаружен лимит.
    """
    res = run_js("""
        const markers = [
            "Daily upload limit reached",
            "Upload more videos daily after a one-time verification",
            "wait 24 hours",
            "Достигнут дневной лимит",
            "Достигнут лимит загрузки",
            "Build your channel history"
        ];
        
        // 1. Проверяем весь текст страницы
        const fullText = document.body?.innerText || "";
        for (const m of markers) {
            if (fullText.includes(m)) return "LIMIT_FOUND";
        }
        
        // 2. Проверяем тосты и диалоги ошибок
        const toasts = Array.from(document.querySelectorAll("ytcp-toast, tp-yt-paper-toast, #error-container, ytcp-error-dialog, .error-message, ytcp-notification-container"));
        for (const t of toasts) {
            const txt = t.innerText || "";
            for (const m of markers) {
                if (txt.includes(m)) return "LIMIT_FOUND";
            }
        }
        
        return "OK";
    """)
    return res == "LIMIT_FOUND"


def close_dialog_safely():
    """Закрывает диалог загрузки или ошибки, чтобы сбросить UI."""
    run_js("""
        const closeBtn = document.querySelector("#ytcp-uploads-dialog-close-button, [aria-label='Save and close'], ytcp-button:has-text('Close'), ytcp-button:has-text('Закрыть'), #close-button");
        if (closeBtn) closeBtn.click();
    """)


def build_full_queue(billets_dir: Path, signs_dir: Path):
    """Строит полную очередь от NN=2 до NN=30."""
    billets_files = {
        int(p.name.split("_", 1)[0]): p
        for p in billets_dir.glob("*.mp4")
        if p.name.split("_", 1)[0].isdigit()
    }
    signs_files = {
        int(p.name.split("_", 1)[0]): p
        for p in signs_dir.glob("*.mp4")
        if p.name.split("_", 1)[0].isdigit()
    }

    queue = []
    for nn in range(2, 31):
        # 1. Билет
        if nn in billets_files:
            bilet_date = START_DATE_NN2 + timedelta(days=(nn - 2) * 2)
            queue.append({
                "nn": nn,
                "type": "bilet",
                "path": str(billets_files[nn]),
                "filename": billets_files[nn].name,
                "date_str": bilet_date.strftime("%Y-%m-%d"),
                "date_obj": bilet_date,
                "time": "7:20 PM",
                "title": TITLE,
                "description": DESCRIPTION_BILLET,
            })
        # 2. Знак
        if nn in signs_files:
            sign_date = START_DATE_NN2 + timedelta(days=(nn - 2) * 2 + 1)
            queue.append({
                "nn": nn,
                "type": "znak",
                "path": str(signs_files[nn]),
                "filename": signs_files[nn].name,
                "date_str": sign_date.strftime("%Y-%m-%d"),
                "date_obj": sign_date,
                "time": "7:20 PM",
                "title": TITLE,
                "description": DESCRIPTION_SIGN,
            })
    return queue


def upload_single_video(item: dict) -> str:
    """Полный цикл загрузки и планирования одного видео с постоянным контролем лимита."""
    print(f"\n========================================================")
    print(f"▶ Загрузка: {item['filename']} (NN={item['nn']:02d}, {item['type'].upper()})")
    print(f"  Дата: {item['date_str']} в {item['time']}")
    print(f"========================================================")

    # Предварительная проверка на лимит перед началом
    if check_daily_limit():
        print("\n[!] Обнаружен лимит загрузок YouTube перед стартом ролика.")
        close_dialog_safely()
        return "LIMIT_REACHED"

    # 1. Читаем видеофайл в Base64
    print("  [1/7] Подготовка файла...")
    with open(item["path"], "rb") as f:
        b64_data = base64.b64encode(f.read()).decode("ascii")

    # 2. Переходим на чистую страницу Studio и сбрасываем оверлеи
    close_dialog_safely()
    run_js(f'location.href = "{STUDIO_URL}";')
    time.sleep(3.5)

    # 3. Открываем меню Create и диалог Upload
    print("  [2/7] Открытие меню Create и диалога загрузки...")
    for attempt in range(15):
        if check_daily_limit():
            print("\n[!] Достигнут лимит загрузок YouTube.")
            close_dialog_safely()
            return "LIMIT_REACHED"

        has_input = run_js('return !!document.querySelector("input[type=file]");')
        if has_input == "true":
            break

        has_menu = run_js('return !!document.querySelector("text-item[test-id=\'upload-beta\'], #text-item-0, yt-formatted-string[title=\'Upload videos\'], yt-formatted-string[title=\'Добавить видео\']");')
        if has_menu == "true":
            run_js("""
                const uploadItem = document.querySelector("text-item[test-id='upload-beta'], #text-item-0, yt-formatted-string[title='Upload videos'], yt-formatted-string[title='Добавить видео']");
                if (uploadItem) uploadItem.click();
                else document.querySelector('tp-yt-paper-item')?.click();
            """)
            time.sleep(1.5)
        else:
            run_js("""
                const createBtn = document.querySelector('#create-icon, ytcp-button#create-icon, [aria-label="Create"], [aria-label="Создать"]');
                if (createBtn) createBtn.click();
            """)
            time.sleep(1.2)

    has_input = run_js('return !!document.querySelector("input[type=file]");')
    if has_input != "true":
        print("  Ошибка: не удалось открыть диалог загрузки (нет input[type=file]).")
        return "ERR_NO_INPUT"

    # 4. Отправляем файл через DataTransfer в input[type=file]
    print("  [3/7] Передача видеофайла в браузер...")
    upload_res = run_js(f"""
        const b64 = "{b64_data}";
        const byteCharacters = atob(b64);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {{
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }}
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], {{ type: "video/mp4" }});
        const file = new File([blob], "{item['filename']}", {{ type: "video/mp4" }});

        const dt = new DataTransfer();
        dt.items.add(file);

        const input = document.querySelector("input[type=file]");
        if (!input) return "NO_INPUT";

        input.files = dt.files;
        input.dispatchEvent(new Event("change", {{ bubbles: true }}));
        return "SUCCESS";
    """)

    if upload_res != "SUCCESS":
        print(f"  Ошибка при передаче файла: {upload_res}")
        return "ERR_UPLOAD"

    # 5. Ожидаем открытия экрана Details с постоянной проверкой лимита
    print("  [4/7] Ожидание экрана деталей...")
    details_ready = False
    for _ in range(35):
        time.sleep(1)
        if check_daily_limit():
            print("\n[!] Достигнут лимит загрузок YouTube.")
            close_dialog_safely()
            return "LIMIT_REACHED"

        res = run_js("""
            const titleBox = document.querySelector('#textbox[aria-label*="title"], #textbox[aria-label*="название"], #title-textarea #textbox');
            return titleBox ? 'READY' : 'WAIT';
        """)
        if res == "READY":
            details_ready = True
            break

    if not details_ready:
        print("  Ошибка: экран деталей не открылся.")
        return "ERR_DETAILS_TIMEOUT"

    time.sleep(1)

    # 6. Заполняем Title, Description, Not for kids
    print("  [5/7] Заполнение метаданных (Title='ПДД', Description, Not for kids)...")
    desc_json = json.dumps(item["description"])
    js_metadata = """
        // Title
        const titleBox = document.querySelector('#textbox[aria-label*="title"], #textbox[aria-label*="название"], #title-textarea #textbox');
        if (titleBox) {
            titleBox.focus();
            titleBox.innerText = "ПДД";
            titleBox.dispatchEvent(new Event("input", { bubbles: true }));
            titleBox.dispatchEvent(new Event("change", { bubbles: true }));
        }

        // Description
        const descBox = document.querySelector('#description-textarea #textbox, #textbox[aria-label*="description"], #textbox[aria-label*="описание"]');
        if (descBox) {
            descBox.focus();
            descBox.innerText = %s;
            descBox.dispatchEvent(new Event("input", { bubbles: true }));
            descBox.dispatchEvent(new Event("change", { bubbles: true }));
        }

        // Not made for kids
        const notForKids = document.querySelector("tp-yt-paper-radio-button[name='VIDEO_MADE_FOR_KIDS_NOT_MFK'], [name='VIDEO_MADE_FOR_KIDS_NOT_MFK']");
        if (notForKids) notForKids.click();
    """ % desc_json
    run_js(js_metadata)
    time.sleep(1)

    # 7. Шаги Next -> Next -> Next
    print("  [6/7] Переход к экрану Visibility (3x Next)...")
    for _ in range(3):
        if check_daily_limit():
            print("\n[!] Достигнут лимит загрузок YouTube.")
            close_dialog_safely()
            return "LIMIT_REACHED"
        run_js("document.querySelector('#next-button, ytcp-button#next-button')?.click();")
        time.sleep(1.5)

    # 8. Экран Visibility: Schedule -> Date -> Time 7:20 PM
    print(f"  [7/7] Установка расписания на {item['date_str']} 7:20 PM...")
    
    # 8.1 Раскрываем блок Schedule
    run_js("""
        const dp = document.querySelector("#datepicker-trigger");
        if (!dp) {
            const scheduleP = Array.from(document.querySelectorAll("p#visibility-title")).find(p => p.innerText?.includes("Schedule") || p.innerText?.includes("Запланировать"));
            scheduleP?.click();
        }
    """)
    time.sleep(1)

    # 8.2 Открываем календарь
    run_js("document.querySelector('#datepicker-trigger')?.click();")
    time.sleep(1)

    # 8.3 Кликаем нужный день в нужном месяце
    target_dt = item["date_obj"]
    target_day = str(target_dt.day)
    target_month_num = target_dt.month
    target_month_names = {
        8: ["AUG", "АВГ"],
        9: ["SEP", "СЕНТ"],
        10: ["OCT", "ОКТ"]
    }.get(target_month_num, [""])

    month_patterns_json = json.dumps(target_month_names)

    day_res = run_js(f"""
        const patterns = {month_patterns_json};
        const months = Array.from(document.querySelectorAll("div.calendar-month"));
        let targetMonth = months.find(m => {{
            const txt = (m.querySelector(".calendar-month-label")?.innerText || m.innerText).toUpperCase();
            return patterns.some(p => txt.includes(p));
        }});

        if (!targetMonth && months.length > 0) {{
            targetMonth = months[months.length - 1];
        }}

        if (targetMonth) {{
            const days = Array.from(targetMonth.querySelectorAll("span.calendar-day"));
            const dayCell = days.find(d => d.innerText.trim() === "{target_day}" && !d.classList.contains("disabled"));
            if (dayCell) {{
                dayCell.click();
                return "CLICKED_DAY";
            }}
        }}
        return "ERR_DAY_NOT_FOUND";
    """)

    if day_res != "CLICKED_DAY":
        print(f"  Предупреждение по календарю: {day_res}")

    time.sleep(1)

    # 8.4 Устанавливаем время 7:20 PM
    run_js("""
        const dp = document.querySelector("#datepicker-trigger");
        const container = dp?.closest("ytcp-video-visibility-schedule, ytcp-video-visibility-select");
        const timeInput = container?.querySelector("input");
        if (timeInput) {
            timeInput.focus();
            timeInput.value = "7:20 PM";
            timeInput.dispatchEvent(new Event("input", { bubbles: true }));
            timeInput.dispatchEvent(new Event("change", { bubbles: true }));
        }
    """)
    time.sleep(1)

    # 8.5 Кликаем Schedule
    run_js("document.querySelector('#done-button, ytcp-button#done-button')?.click();")
    time.sleep(3)

    # 8.6 Проверка лимита сразу после нажатия Schedule
    if check_daily_limit():
        print("\n" + "!" * 60)
        print("ВНИМАНИЕ: Достигнут суточный лимит загрузок YouTube (Daily upload limit reached)!")
        print("!" * 60 + "\n")
        close_dialog_safely()
        return "LIMIT_REACHED"

    # 8.7 Закрываем диалог "Video scheduled"
    for _ in range(15):
        time.sleep(1)
        if check_daily_limit():
            print("\n[!] Достигнут лимит загрузок YouTube.")
            close_dialog_safely()
            return "LIMIT_REACHED"

        res = run_js("""
            const closeBtn = document.querySelector("#ytcp-uploads-dialog-close-button, [aria-label='Save and close'], ytcp-button:has-text('Close'), ytcp-button:has-text('Закрыть')");
            if (closeBtn && closeBtn.offsetParent !== null) {
                closeBtn.click();
                return 'CLOSED';
            }
            return 'WAIT';
        """)
        if res == "CLOSED":
            break

    time.sleep(2)
    print(f"✓ УСПЕШНО: {item['filename']} запланирован на {item['date_str']} 19:20.")
    return "OK"


def main():
    parser = argparse.ArgumentParser(description="Автозагрузка YouTube Shorts в Chrome")
    parser.add_argument("--billets", type=Path, default=DEFAULT_BILLETS_DIR)
    parser.add_argument("--signs", type=Path, default=DEFAULT_SIGNS_DIR)
    parser.add_argument("--limit", type=int, default=100, help="Максимум видео за сессию")
    args = parser.parse_args()

    full_queue = build_full_queue(args.billets, args.signs)

    state = {}
    if STATE_FILE.exists():
        try:
            state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    if "done" not in state:
        state["done"] = []

    # Формируем список оставшихся видео
    pending = [item for item in full_queue if item["path"] not in state["done"]]

    print(f"Всего файлов в очереди: {len(full_queue)}")
    print(f"Уже запланировано ранее: {len(state['done'])}")
    print(f"Осталось загрузить: {len(pending)}")

    if not pending:
        print("Все видео уже запланированы!")
        return

    print("\nСледующие ролики к публикации:")
    for it in pending[:5]:
        print(f"  - [{it['date_str']} 19:20] NN={it['nn']:02d} ({it['type']}): {it['filename']}")
    if len(pending) > 5:
        print(f"  ... и еще {len(pending) - 5} роликов до [{pending[-1]['date_str']}].\n")

    uploaded = 0
    for item in pending[: args.limit]:
        res = upload_single_video(item)
        if res == "LIMIT_REACHED":
            print(f"\nСкрипт остановлен из-за суточного лимита YouTube.")
            break
        elif res == "OK":
            uploaded += 1
            state["done"].append(item["path"])
            STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            time.sleep(3)
        else:
            print(f"Ошибка при загрузке {item['filename']}: {res}. Остановка.")
            break

    print("\n" + "=" * 60)
    print(f"ИТОГ СЕССИИ:")
    print(f"  - Запланировано роликов за сессию: {uploaded}")
    if pending and uploaded > 0:
        print(f"  - Диапазон дат: с {pending[0]['date_str']} по {pending[uploaded - 1]['date_str']}")
        if uploaded < len(pending):
            print(f"  - Следующий ролик в очереди: {pending[uploaded]['filename']} ({pending[uploaded]['date_str']})")
        else:
            print(f"  - Все ролики из очереди успешно запланированы!")
    elif pending and uploaded == 0:
        print(f"  - Лимит все еще активен. Следующий ролик: {pending[0]['filename']} ({pending[0]['date_str']})")
    print("=" * 60)


if __name__ == "__main__":
    main()
