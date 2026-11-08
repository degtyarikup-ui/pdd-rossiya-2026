#!/usr/bin/env python3
"""
Автономный скрипт планирования YouTube Shorts для канала «ПДД 2026»
через браузер с помощью Playwright.
"""

import argparse
import asyncio
import json
import os
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

# Пути по умолчанию
DEFAULT_BILLETS_DIR = Path("/Users/sergei/Desktop/PDD_1")
DEFAULT_SIGNS_DIR = Path("/Users/sergei/Desktop/PDD_2")
USER_DATA_DIR = Path.home() / ".chrome-yt-automation"
STATE_FILE = Path(__file__).parent / "playwright_state.json"

STUDIO_URL = "https://studio.youtube.com/channel/UCYycIcL6qvFE3TyQ8qT58bg/videos/short?filter=%5B%5D&sort=%7B%22columnType%22%3A%22date%22%2C%22sortOrder%22%3A%22DESCENDING%22%7D"

TITLE = "ПДД"

DESCRIPTION_BILLET = (
    "Ссылка на приложение для подготовки к экзамену — в шапке профиля\n\n"
    "#пдд #пдд2026 #билетыпдд #автошкола #экзаменпдд #гибдд #водитель"
)

DESCRIPTION_SIGN = (
    "Ссылка на приложение для подготовки к экзамену — в шапке профиля\n\n"
    "#пдд #пдд2026 #дорожныезнаки #автошкола #экзаменпдд #гибдд #водитель"
)

START_DATE_NN2 = datetime(2026, 8, 16)


def build_full_queue(billets_dir: Path, signs_dir: Path):
    """Строит полную очередь роликов от NN=2 до NN=30 по формуле."""
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
                "date": bilet_date.strftime("%Y-%m-%d"),
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
                "date": sign_date.strftime("%Y-%m-%d"),
                "date_obj": sign_date,
                "time": "7:20 PM",
                "title": TITLE,
                "description": DESCRIPTION_SIGN,
            })

    return queue


def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"done": []}


def save_state(state):
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


async def ensure_authenticated(page):
    """Проверяет, авторизован ли пользователь, и ждет логина при необходимости."""
    print("Проверка авторизации в YouTube Studio...")
    await page.goto(STUDIO_URL, wait_until="domcontentloaded", timeout=60000)
    
    # Ждем либо появления элементов Studio, либо страницы логина
    for _ in range(300): # до 5 минут на ручной вход, если нужно
        url = page.url
        if "accounts.google.com" in url:
            print("\n" + "="*60)
            print("ТРЕБУЕТСЯ АВТОРИЗАЦИЯ:")
            print("Пожалуйста, войдите в аккаунт YouTube в открывшемся окне браузера.")
            print("="*60 + "\n")
            await asyncio.sleep(5)
        elif "studio.youtube.com" in url:
            try:
                # Проверим наличие основных элементов страницы
                create_btn = page.locator("#create-icon, ytcp-button#create-icon, [id='create-icon']")
                if await create_btn.count() > 0 or await page.locator("text=Create").count() > 0 or await page.locator("text=Создать").count() > 0:
                    print("Успешная авторизация в YouTube Studio!")
                    return True
            except Exception:
                pass
            await asyncio.sleep(2)
        else:
            await asyncio.sleep(2)
            
    return False


async def upload_single_video(page, item):
    """Загружает и планирует один Shorts."""
    print(f"\n--- Загрузка: {Path(item['path']).name} (NN={item['nn']}, {item['type']}, дата={item['date']}) ---")
    
    # 1. Открываем студию
    await page.goto(STUDIO_URL, wait_until="domcontentloaded")
    await asyncio.sleep(2)

    # 2. Кнопка "Create" / "Создать"
    create_btn = page.locator("#create-icon, ytcp-button#create-icon, [aria-label='Create'], [aria-label='Создать']").first
    await create_btn.click()
    await asyncio.sleep(1)

    # Пункт меню "Upload videos" / "Добавить видео"
    upload_item = page.locator("text-item[test-id='upload-beta'], ytp-menu-item, [id='text-item-0'], yt-formatted-string:has-text('Upload videos'), yt-formatted-string:has-text('Добавить видео')").first
    await upload_item.click()
    await asyncio.sleep(1)

    # 3. Загрузка файла через input[type=file]
    file_input = page.locator("input[type='file']")
    await file_input.set_input_files(item["path"])
    print(f"Файл {Path(item['path']).name} отправлен на загрузку...")

    # 4. Ожидание открытия окна "Details" (появление поля заголовка)
    title_box = page.locator("#textbox[aria-label*='title'], #textbox[aria-label*='название'], #title-textarea #textbox").first
    await title_box.wait_for(state="visible", timeout=60000)
    await asyncio.sleep(2)

    # 5. Ввод Title: строго "ПДД"
    await title_box.click()
    # Очищаем поле через Select All -> Backspace
    await page.keyboard.press("Meta+A" if sys.platform == "darwin" else "Control+A")
    await page.keyboard.press("Backspace")
    await title_box.fill(item["title"])
    print("Заголовок 'ПДД' установлен.")

    # 6. Ввод Description
    desc_box = page.locator("#description-textarea #textbox, #textbox[aria-label*='description'], #textbox[aria-label*='описание']").first
    await desc_box.click()
    await page.keyboard.press("Meta+A" if sys.platform == "darwin" else "Control+A")
    await page.keyboard.press("Backspace")
    await desc_box.fill(item["description"])
    print("Описание и хэштеги установлены.")

    # Кликаем в заголовок или нейтральное место, чтобы скрыть всплывающие подсказки хэштегов
    await title_box.click()
    await asyncio.sleep(1)

    # 7. Выбор аудитории: "No, it's not made for kids" / "Нет, это видео не для детей"
    not_for_kids_radio = page.locator("tp-yt-paper-radio-button[name='VIDEO_MADE_FOR_KIDS_NOT_MFK'], [name='VIDEO_MADE_FOR_KIDS_NOT_MFK']").first
    await not_for_kids_radio.scroll_into_view_if_needed()
    await not_for_kids_radio.click()
    await asyncio.sleep(1)

    # 8. Трижды жмем "Next" / "Далее"
    next_btn = page.locator("#next-button, ytcp-button#next-button").first
    for step_i in range(3):
        await next_btn.click()
        print(f"Шаг {step_i + 1}/3 (Next)...")
        await asyncio.sleep(2)

    # 9. Экран Visibility: выбираем Schedule
    schedule_radio = page.locator("tp-yt-paper-radio-button[name='SCHEDULE'], #schedule-radio-button, [aria-label*='Schedule'], [aria-label*='Запланировать']").first
    await schedule_radio.click()
    await asyncio.sleep(1)

    # Открываем выбор даты
    date_picker = page.locator("#datepicker-trigger, ytcp-dropdown-trigger[aria-label*='date'], #date-picker-trigger").first
    if await date_picker.count() > 0:
        await date_picker.click()
        await asyncio.sleep(1)
        
        target_date = item["date_obj"] # datetime
        day_str = str(target_date.day)
        
        day_cell = page.locator(f"ytcp-calendar-dialog .day-cell:has-text('{day_str}'), ytcp-date-picker .day:text-is('{day_str}'), yt-formatted-string.day-cell:text-is('{day_str}')").first
        if await day_cell.count() > 0:
            await day_cell.click()
            print(f"Выбрана дата {item['date']} в календаре.")
        else:
            date_input = page.locator("ytcp-date-picker input, ytcp-dropdown-trigger input").first
            if await date_input.count() > 0:
                await date_input.fill(target_date.strftime("%b %d, %Y"))
    else:
        print("Внимание: стандартный datepicker-trigger не найден.")

    await asyncio.sleep(1)

    # 10. Установка времени: "7:20 PM"
    time_trigger = page.locator("#time-of-day-trigger, input[aria-label*='time'], input[aria-label*='время'], ytcp-dropdown-trigger[aria-label*='time'] input").first
    if await time_trigger.count() > 0:
        await time_trigger.click()
        await page.keyboard.press("Meta+A" if sys.platform == "darwin" else "Control+A")
        await page.keyboard.press("Backspace")
        await time_trigger.fill("7:20 PM")
        await page.keyboard.press("Tab")
        print("Установлено время 7:20 PM.")
    else:
        print("Поле времени не найдено по стандартному селектору.")

    await asyncio.sleep(2)

    # 11. Кнопка "Schedule" / "Запланировать"
    done_btn = page.locator("#done-button, ytcp-button#done-button, ytcp-button:has-text('Schedule'), ytcp-button:has-text('Запланировать')").first
    await done_btn.click()
    print("Нажата кнопка Schedule...")

    # 12. Ожидание подтверждения ("Video scheduled" / "Видео запланировано")
    await asyncio.sleep(3)
    
    # Проверка на дневной лимит
    limit_warning = page.locator("text=Daily upload limit reached, text=Достигнут дневной лимит загрузки, text=Build your channel history")
    if await limit_warning.count() > 0:
        print("\n" + "!"*60)
        print("ВНИМАНИЕ: Достигнут дневной лимит загрузок YouTube (Daily upload limit reached)!")
        print("!"*60 + "\n")
        return "LIMIT_REACHED"

    # Закрываем диалог завершения
    close_btn = page.locator("#close-button, ytcp-button#close-button, ytcp-button:has-text('Close'), ytcp-button:has-text('Закрыть')").first
    try:
        await close_btn.wait_for(state="visible", timeout=30000)
        await close_btn.click()
        print(f"Видео {Path(item['path']).name} успешно запланировано!")
        return "OK"
    except Exception as e:
        print(f"Предупреждение при закрытии окна подтверждения: {e}")
        return "OK"


async def main():
    parser = argparse.ArgumentParser(description="Автозагрузка YouTube Shorts")
    parser.add_argument("--billets", type=Path, default=DEFAULT_BILLETS_DIR)
    parser.add_argument("--signs", type=Path, default=DEFAULT_SIGNS_DIR)
    parser.add_argument("--start-nn", type=int, default=12, help="Начальный номер NN (по умолчанию 12)")
    parser.add_argument("--start-type", choices=["bilet", "znak"], default="bilet", help="Начать с билета или знака")
    parser.add_argument("--limit", type=int, default=100, help="Максимальное количество роликов за запуск")
    parser.add_argument("--dry-run", action="store_true", help="Только показать очередь без загрузки")
    args = parser.parse_args()

    full_queue = build_full_queue(args.billets, args.signs)
    
    # Фильтруем очередь начиная с указанного стартового элемента
    start_found = False
    pending_queue = []
    for item in full_queue:
        if not start_found:
            if item["nn"] > args.start_nn or (item["nn"] == args.start_nn and (args.start_type == "bilet" or item["type"] == args.start_type)):
                start_found = True
        if start_found:
            pending_queue.append(item)

    print(f"Всего в очереди на загрузку: {len(pending_queue)} видео.")
    if not pending_queue:
        print("Очередь пуста.")
        return

    print("\nПервые 5 видео в очереди:")
    for it in pending_queue[:5]:
        print(f"  - [{it['date']} {it['time']}] NN={it['nn']:02d} ({it['type']}): {Path(it['path']).name}")
    print(f"Последнее видео в очереди: [{pending_queue[-1]['date']}] NN={pending_queue[-1]['nn']:02d} ({pending_queue[-1]['type']})\n")

    if args.dry_run:
        print("Режим dry-run завершен.")
        return

    state = load_state()

    async with async_playwright() as p:
        USER_DATA_DIR.mkdir(parents=True, exist_ok=True)
        print(f"Запуск Chrome (профиль: {USER_DATA_DIR})...")
        
        context = await p.chromium.launch_persistent_context(
            user_data_dir=str(USER_DATA_DIR),
            channel="chrome",
            headless=False,
            viewport={"width": 1400, "height": 900},
            args=["--start-maximized", "--no-sandbox"],
        )
        
        page = context.pages[0] if context.pages else await context.new_page()

        auth_ok = await ensure_authenticated(page)
        if not auth_ok:
            print("Не удалось авторизоваться в YouTube Studio. Завершение работы.")
            await context.close()
            return

        uploaded_count = 0
        for item in pending_queue[: args.limit]:
            if item["path"] in state["done"]:
                print(f"Пропуск (уже было загружено ранее): {Path(item['path']).name}")
                continue

            result = await upload_single_video(page, item)
            if result == "LIMIT_REACHED":
                print(f"Остановлено из-за дневного лимита YouTube. За сессию запланировано: {uploaded_count}.")
                break
            elif result == "OK":
                uploaded_count += 1
                state["done"].append(item["path"])
                save_state(state)
                await asyncio.sleep(4)
            else:
                print(f"Ошибка при загрузке {Path(item['path']).name}, прерывание.")
                break

        print("\n" + "="*60)
        print(f"ИТОГ СЕССИИ: Запланировано роликов: {uploaded_count}")
        print("="*60)

        await context.close()


if __name__ == "__main__":
    asyncio.run(main())
