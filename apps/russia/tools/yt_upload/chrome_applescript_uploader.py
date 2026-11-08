#!/usr/bin/env python3
"""
Автоматизация планирования YouTube Shorts в активном окне Google Chrome
через AppleScript и JavaScript (без перезапуска браузера).
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

# Папки с видео
DEFAULT_BILLETS_DIR = Path("/Users/sergei/Desktop/PDD_1")
DEFAULT_SIGNS_DIR = Path("/Users/sergei/Desktop/PDD_2")
STATE_FILE = Path(__file__).parent / "applescript_state.json"

TITLE = "ПДД"

DESCRIPTION_BILLET = """Ссылка на приложение для подготовки к экзамену — в шапке профиля

#пдд #пдд2026 #билетыпдд #автошкола #экзаменпдд #гибдд #водитель"""

DESCRIPTION_SIGN = """Ссылка на приложение для подготовки к экзамену — в шапке профиля

#пдд #пдд2026 #дорожныезнаки #автошкола #экзаменпдд #гибдд #водитель"""

START_DATE_NN2 = datetime(2026, 8, 16)


def run_applescript(script: str) -> str:
    """Выполняет AppleScript и возвращает stdout."""
    res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"AppleScript error: {res.stderr.strip()}")
    return res.stdout.strip()


def run_js(js_code: str) -> str:
    """Выполняет JavaScript в активной вкладке активного окна Chrome."""
    # Экранируем JavaScript для передачи в AppleScript
    # Обернем в самовызывающуюся функцию
    wrapped_js = f"(() => {{ {js_code} }})()"
    escaped_js = wrapped_js.replace("\\", "\\\\").replace('"', '\\"')
    as_script = f'tell application "Google Chrome" to execute active tab of front window javascript "{escaped_js}"'
    return run_applescript(as_script)


def set_clipboard(text: str):
    """Помещает строку в буфер обмена macOS."""
    p = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    p.communicate(text.encode("utf-8"))


def build_full_queue(billets_dir: Path, signs_dir: Path):
    """Строит очередь видео по формуле NN=2..30."""
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
        # Билет
        if nn in billets_files:
            bilet_date = START_DATE_NN2 + timedelta(days=(nn - 2) * 2)
            queue.append({
                "nn": nn,
                "type": "bilet",
                "path": str(billets_files[nn]),
                "date_str": bilet_date.strftime("%Y-%m-%d"),
                "date_obj": bilet_date,
                "time": "7:20 PM",
                "title": TITLE,
                "description": DESCRIPTION_BILLET,
            })
        # Знак
        if nn in signs_files:
            sign_date = START_DATE_NN2 + timedelta(days=(nn - 2) * 2 + 1)
            queue.append({
                "nn": nn,
                "type": "znak",
                "path": str(signs_files[nn]),
                "date_str": sign_date.strftime("%Y-%m-%d"),
                "date_obj": sign_date,
                "time": "7:20 PM",
                "title": TITLE,
                "description": DESCRIPTION_SIGN,
            })
    return queue


def upload_single_video(item: dict) -> str:
    """Загружает одно видео в YouTube Studio."""
    print(f"\n==================================================")
    print(f"Загрузка: NN={item['nn']:02d} ({item['type'].upper()}) — {Path(item['path']).name}")
    print(f"Дата планирования: {item['date_str']} в {item['time']}")
    print(f"==================================================")

    # 1. Фокусируем Chrome
    run_applescript('tell application "Google Chrome" to activate')
    time.sleep(0.5)

    # 2. Клик по кнопке Create
    print("1. Открытие диалога загрузки...")
    res = run_js("""
        const createBtn = document.querySelector('#create-icon, [aria-label="Create"], [aria-label="Создать"]');
        if (createBtn) {
            createBtn.click();
            return 'OK';
        }
        return 'ERR_NO_CREATE_BTN';
    """)
    time.sleep(0.8)

    # Клик по "Upload videos" / "Добавить видео"
    run_js("""
        const uploadItem = document.querySelector('text-item[test-id="upload-beta"], #text-item-0, yt-formatted-string[title="Upload videos"], yt-formatted-string[title="Добавить видео"]');
        if (uploadItem) {
            uploadItem.click();
            return 'OK';
        }
        // Запасной вариант: клик по первому пункту меню
        const firstItem = document.querySelector('tp-yt-paper-item');
        if (firstItem) {
            firstItem.click();
            return 'OK_FALLBACK';
        }
        return 'ERR_NO_UPLOAD_ITEM';
    """)
    time.sleep(1.2)

    # Клик по кнопке "Select files" / "Выбрать файлы"
    run_js("""
        const selectBtn = document.querySelector('#select-files-button');
        if (selectBtn) {
            selectBtn.click();
            return 'OK';
        }
        return 'ERR_NO_SELECT_BTN';
    """)
    time.sleep(1.2)

    # 3. Выбор файла через диалог Finder (Cmd+Shift+G)
    print(f"2. Выбор файла: {item['path']}")
    set_clipboard(item["path"])
    
    applescript_choose_file = """
    tell application "System Events"
        delay 0.5
        keystroke "g" using {command down, shift down}
        delay 0.8
        keystroke "v" using {command down}
        delay 0.8
        keystroke return
        delay 0.8
        keystroke return
    end tell
    """
    run_applescript(applescript_choose_file)
    print("Файл передан в окно загрузки. Ожидание открытия экрана редактирования...")

    # 4. Ожидание появления экрана Details (до 30 сек)
    details_opened = False
    for attempt in range(30):
        time.sleep(1)
        res = run_js("""
            const titleBox = document.querySelector('#textbox[aria-label*="title"], #textbox[aria-label*="название"], #title-textarea #textbox');
            return titleBox ? 'OPENED' : 'WAIT';
        """)
        if res == "OPENED":
            details_opened = True
            break

    if not details_opened:
        print("Ошибка: экран редактирования не открылся вовремя.")
        return "ERR_TIMEOUT"

    time.sleep(1)
    print("3. Экран Details открыт. Заполнение заголовка и описания...")

    # 5. Установка Title = "ПДД"
    set_clipboard(item["title"])
    run_js("""
        const titleBox = document.querySelector('#textbox[aria-label*="title"], #textbox[aria-label*="название"], #title-textarea #textbox');
        if (titleBox) {
            titleBox.focus();
            titleBox.innerText = 'ПДД';
            titleBox.dispatchEvent(new Event('input', { bubbles: true }));
            titleBox.dispatchEvent(new Event('change', { bubbles: true }));
            return 'OK';
        }
        return 'ERR';
    """)
    time.sleep(0.5)

    # 6. Установка Description
    set_clipboard(item["description"])
    run_js("""
        const descBox = document.querySelector('#description-textarea #textbox, #textbox[aria-label*="description"], #textbox[aria-label*="описание"]');
        if (descBox) {
            descBox.focus();
            // Вставляем текст описания
            // Чтобы корректно передать многострочный текст:
            const desc = %s;
            descBox.innerText = desc;
            descBox.dispatchEvent(new Event('input', { bubbles: true }));
            descBox.dispatchEvent(new Event('change', { bubbles: true }));
            return 'OK';
        }
        return 'ERR';
    """ % json.dumps(item["description"]))
    time.sleep(0.5)

    # Кликаем по Title, чтобы закрыть автокомплит хэштегов
    run_js("""
        const titleBox = document.querySelector('#textbox[aria-label*="title"], #textbox[aria-label*="название"], #title-textarea #textbox');
        if (titleBox) titleBox.focus();
    """)
    time.sleep(0.5)

    # 7. Выбор "No, it's not made for kids"
    print("4. Выбор аудитории (Not made for kids)...")
    run_js("""
        const radio = document.querySelector("tp-yt-paper-radio-button[name='VIDEO_MADE_FOR_KIDS_NOT_MFK'], [name='VIDEO_MADE_FOR_KIDS_NOT_MFK']");
        if (radio) {
            radio.scrollIntoView({ behavior: 'smooth', block: 'center' });
            radio.click();
            return 'OK';
        }
        return 'ERR';
    """)
    time.sleep(1)

    # 8. Три клика "Next"
    print("5. Переход к шагу Visibility (3x Next)...")
    for step in range(3):
        run_js("""
            const nextBtn = document.querySelector('#next-button, ytcp-button#next-button');
            if (nextBtn) nextBtn.click();
        """)
        time.sleep(1.5)

    # 9. Экран Visibility: выбор Schedule
    print("6. Настройка расписания...")
    run_js("""
        const scheduleRadio = document.querySelector("tp-yt-paper-radio-button[name='SCHEDULE'], #schedule-radio-button, [aria-label*='Schedule'], [aria-label*='Запланировать']");
        if (scheduleRadio) {
            scheduleRadio.click();
            return 'OK';
        }
        return 'ERR';
    """)
    time.sleep(1)

    # Открытие календаря
    target_date = item["date_obj"]
    target_day = target_date.day
    target_month_ru = ["янв", "февр", "мар", "апр", "мая", "июн", "июл", "авг", "сент", "окт", "нояб", "дек"][target_date.month - 1]
    
    # Кликаем на выбор даты
    run_js("""
        const datePickerTrigger = document.querySelector('#datepicker-trigger, ytcp-dropdown-trigger[aria-label*="date"], #date-picker-trigger');
        if (datePickerTrigger) {
            datePickerTrigger.click();
            return 'OK';
        }
        return 'ERR';
    """)
    time.sleep(1)

    # Ищем ячейку нужного дня в открывшемся календаре
    # И при необходимости переключаем месяц
    run_js(f"""
        // Проверяем, отображается ли нужный месяц в заголовке календаря
        // Если нет — кликаем стрелку вперед
        const dayCells = Array.from(document.querySelectorAll('ytcp-calendar-dialog .day-cell, ytcp-date-picker .day, yt-formatted-string.day-cell'));
        // Ищем ячейку с числом {target_day}
        const cell = dayCells.find(c => c.innerText.trim() === '{target_day}');
        if (cell) {{
            cell.click();
            return 'CLICKED_DAY';
        }}
        // Если не найдено сразу, попробуем переключить месяц
        const nextMonthBtn = document.querySelector('ytcp-calendar-dialog #next-month-button, ytcp-calendar-dialog [aria-label*="Next"], ytcp-calendar-dialog [aria-label*="Следующий"]');
        if (nextMonthBtn) {{
            nextMonthBtn.click();
            return 'NEXT_MONTH';
        }}
        return 'NO_CELL';
    """)
    time.sleep(0.8)

    # Повторный поиск дня (на случай, если был переключен месяц)
    run_js(f"""
        const dayCells = Array.from(document.querySelectorAll('ytcp-calendar-dialog .day-cell, ytcp-date-picker .day, yt-formatted-string.day-cell'));
        const cell = dayCells.find(c => c.innerText.trim() === '{target_day}');
        if (cell) cell.click();
    """)
    time.sleep(0.8)

    # 10. Установка времени "7:20 PM"
    print("7. Установка времени 7:20 PM...")
    run_js("""
        const timeTrigger = document.querySelector('#time-of-day-trigger, input[aria-label*="time"], input[aria-label*="время"]');
        if (timeTrigger) {
            timeTrigger.click();
            return 'OK';
        }
        return 'ERR';
    """)
    time.sleep(0.5)

    # Вводим время через клавиши (тройной клик / очистка + ввод 7:20 PM + Tab)
    run_applescript("""
    tell application "System Events"
        keystroke "a" using {command down}
        delay 0.2
        keystroke "7:20 PM"
        delay 0.3
        keystroke tab
    end tell
    """)
    time.sleep(1)

    # 11. Клик по кнопке Schedule
    print("8. Нажатие кнопки Schedule...")
    run_js("""
        const doneBtn = document.querySelector('#done-button, ytcp-button#done-button, ytcp-button:has-text("Schedule"), ytcp-button:has-text("Запланировать")');
        if (doneBtn) {
            doneBtn.click();
            return 'OK';
        }
        return 'ERR';
    """)
    time.sleep(3)

    # 12. Проверка дневного лимита
    limit_check = run_js("""
        const bodyText = document.body.innerText;
        if (bodyText.includes('Daily upload limit reached') || bodyText.includes('Достигнут дневной лимит') || bodyText.includes('Build your channel history')) {
            return 'LIMIT_REACHED';
        }
        return 'OK';
    """)

    if limit_check == "LIMIT_REACHED":
        print("\n" + "!"*60)
        print("ВНИМАНИЕ: Достигнут дневной лимит загрузок YouTube!")
        print("!"*60 + "\n")
        return "LIMIT_REACHED"

    # Закрываем диалог "Video scheduled"
    print("9. Закрытие окна подтверждения...")
    for _ in range(15):
        time.sleep(1)
        res = run_js("""
            const closeBtn = document.querySelector('#close-button, ytcp-button#close-button, ytcp-button:has-text("Close"), ytcp-button:has-text("Закрыть")');
            if (closeBtn && closeBtn.offsetParent !== null) {
                closeBtn.click();
                return 'CLOSED';
            }
            return 'WAIT';
        """)
        if res == "CLOSED":
            break

    print(f"УСПЕШНО запланировано: {Path(item['path']).name} на {item['date_str']} 19:20.")
    return "OK"


def main():
    parser = argparse.ArgumentParser(description="Планирование Shorts в активном Chrome")
    parser.add_argument("--billets", type=Path, default=DEFAULT_BILLETS_DIR)
    parser.add_argument("--signs", type=Path, default=DEFAULT_SIGNS_DIR)
    parser.add_argument("--start-nn", type=int, default=12, help="Стартовый номер NN (по умолчанию 12)")
    parser.add_argument("--start-type", choices=["bilet", "znak"], default="bilet", help="Тип (bilet/znak)")
    parser.add_argument("--limit", type=int, default=1, help="Сколько роликов загрузить (по умолчанию 1)")
    args = parser.parse_args()

    full_queue = build_full_queue(args.billets, args.signs)
    
    start_found = False
    pending_queue = []
    for item in full_queue:
        if not start_found:
            if item["nn"] > args.start_nn or (item["nn"] == args.start_nn and (args.start_type == "bilet" or item["type"] == args.start_type)):
                start_found = True
        if start_found:
            pending_queue.append(item)

    print(f"Всего в очереди: {len(pending_queue)} видео.")
    
    state = {}
    if STATE_FILE.exists():
        try:
            state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    if "done" not in state:
        state["done"] = []

    uploaded = 0
    for item in pending_queue[: args.limit]:
        if item["path"] in state["done"]:
            print(f"Пропуск (уже загружен): {Path(item['path']).name}")
            continue

        res = upload_single_video(item)
        if res == "LIMIT_REACHED":
            break
        elif res == "OK":
            uploaded += 1
            state["done"].append(item["path"])
            STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
            time.sleep(3)
        else:
            print(f"Ошибка при загрузке: {res}")
            break

    print(f"\nЗавершено. Запланировано роликов за сессию: {uploaded}.")


if __name__ == "__main__":
    main()
