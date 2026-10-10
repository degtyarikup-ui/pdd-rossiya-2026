import os
import sys
import json
import re
import time
import urllib.request
import urllib.parse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))
RU_ARB = os.path.join(PROJECT_ROOT, 'lib', 'l10n', 'app_ru.arb')
EN_ARB = os.path.join(PROJECT_ROOT, 'lib', 'l10n', 'app_en.arb')
KK_ARB = os.path.join(PROJECT_ROOT, 'lib', 'l10n', 'app_kk.arb')

NEW_KEYS_RU = {
    "languageSetting": "Язык",
    "languageRu": "Русский",
    "languageEn": "English",
    "languageKk": "Қазақша",
}

NEW_KEYS_META = {
    "@languageSetting": {
        "description": "Пункт настроек выбора языка интерфейса"
    },
    "@languageRu": {
        "description": "Название русского языка"
    },
    "@languageEn": {
        "description": "Название английского языка"
    },
    "@languageKk": {
        "description": "Название казахского языка"
    }
}

PLURALS_EN = {
    "shareCardCorrectWord": "{count, plural, one{correct} other{correct}}",
    "shareCardWrongWord": "{count, plural, one{mistake} other{mistakes}}",
    "progressRemaining": "{count, plural, one{{count} question left until the exam} other{{count} questions left until the exam}}",
    "progressStreakDays": "{count, plural, one{{count} day} other{{count} days}}",
    "streakDaysWord": "{count, plural, one{day in a row} other{days in a row}}",
    "favoritesCountHint": "Currently in favorites: {count, plural, one{{count} question} other{{count} questions}}. Use this mode as your personal study set before the exam.",
    "gameGarageNextCar": "{count, plural, one{Next car in {count} correct answer} other{Next car in {count} correct answers}}",
    "gameRatingRuns": "{count, plural, one{{count} run} other{{count} runs}}",
    "gamePenaltyPoints": "{points, plural, one{−{points} point} other{−{points} points}}",
    "gameRunMistakes": "{count, plural, one{{count} mistake in run} other{{count} mistakes in run}}",
    "gameLobbyRunLength": "{count, plural, one{{count} question} other{{count} questions}}",
    "gamesRunsAvailable": "{count, plural, one{{count} run available} other{{count} runs available}}",
    "gameRatingResultsIn": "Leaderboard ends in: {days, plural, one{{days} day} other{{days} days}} {hours, plural, one{{hours} hour} other{{hours} hours}}"
}

PLURALS_KK = {
    "shareCardCorrectWord": "{count, plural, one{дұрыс} other{дұрыс}}",
    "shareCardWrongWord": "{count, plural, one{қате} other{қате}}",
    "progressRemaining": "{count, plural, one{Емтиханға дейін {count} сұрақ қалды} other{Емтиханға дейін {count} сұрақ қалды}}",
    "progressStreakDays": "{count, plural, one{{count} күн} other{{count} күн}}",
    "streakDaysWord": "{count, plural, one{күн қатарынан} other{күн қатарынан}}",
    "favoritesCountHint": "Қазір таңдаулыда {count, plural, one{{count} сұрақ} other{{count} сұрақ}} бар. Бұл режимді емтихан алдында жеке жинақ ретінде пайдаланыңыз.",
    "gameGarageNextCar": "{count, plural, one{Келесі көлік {count} дұрыс жауаптан кейін} other{Келесі көлік {count} дұрыс жауаптан кейін}}",
    "gameRatingRuns": "{count, plural, one{{count} жарыс} other{{count} жарыс}}",
    "gamePenaltyPoints": "{points, plural, one{−{points} ұпай} other{−{points} ұпай}}",
    "gameRunMistakes": "{count, plural, one{Жарыста {count} қате} other{Жарыста {count} қате}}",
    "gameLobbyRunLength": "{count, plural, one{{count} сұрақ} other{{count} сұрақ}}",
    "gamesRunsAvailable": "{count, plural, one{{count} жарыс қолжетімді} other{{count} жарыс қолжетімді}}",
    "gameRatingResultsIn": "Рейтинг қорытындысы: {days, plural, one{{days} күн} other{{days} күн}} {hours, plural, one{{hours} сағат} other{{hours} сағат}}"
}

CURATED_EN = {
    "languageSetting": "Language",
    "languageRu": "Русский",
    "languageEn": "English",
    "languageKk": "Қазақша",
    "pdd": "Traffic Rules",
    "tickets": "Tickets",
    "exam": "Exam",
    "training": "Training",
    "mistakes": "Mistakes",
    "favorites": "Favorites",
    "marathon": "Marathon",
    "topics": "Topics",
    "signs": "Road Signs",
    "markup": "Road Markings",
    "game": "Game",
    "feed": "Feed",
    "profile": "Profile",
    "settings": "Settings",
    "themeSetting": "Theme",
    "themeSystem": "System",
    "themeLight": "Light",
    "themeDark": "Dark",
    "ticketCategorySetting": "Category",
    "confirmAnswerSetting": "Confirm answer",
    "hapticFeedback": "Vibration",
    "soundEffects": "Sound effects",
    "voiceOverQuestions": "Voiceover questions",
    "notificationsSetting": "Daily reminder",
    "resetStats": "Reset statistics",
    "techSupport": "Technical support",
    "termsOfUse": "Terms of Use",
    "privacyPolicy": "Privacy Policy",
    "questionOfTotal": "Question {current} of {total}",
    "examAdditionalQuestionOfTotal": "Additional question {current} of {total}",
    "valueOfTotal": "{value} of {total}",
    "ticketNumber": "Ticket {number}",
    "examShareText": "{result}\nCorrect answers: {correct} of {total}\n\n{title}\n{url}",
    "continueSessionSubtitle": "{title} · question {index} of {total}",
}

CURATED_KK = {
    "languageSetting": "Тіл",
    "languageRu": "Русский",
    "languageEn": "English",
    "languageKk": "Қазақша",
    "pdd": "Жол жүрісі қағидалары",
    "tickets": "Билеттер",
    "exam": "Емтихан",
    "training": "Жаттығу",
    "mistakes": "Қателермен жұмыс",
    "favorites": "Таңдаулы",
    "marathon": "Марафон",
    "topics": "Тақырыптар",
    "signs": "Жол белгілері",
    "markup": "Жол таңбасы",
    "game": "Ойын",
    "feed": "Лента",
    "profile": "Профиль",
    "settings": "Баптаулар",
    "themeSetting": "Тақырып",
    "themeSystem": "Жүйелік",
    "themeLight": "Ашық",
    "themeDark": "Күңгірт",
    "ticketCategorySetting": "Санат",
    "confirmAnswerSetting": "Жауапты растау",
    "hapticFeedback": "Діріл",
    "soundEffects": "Дыбыстық әсерлер",
    "voiceOverQuestions": "Сұрақтарды дауыстап оқу",
    "notificationsSetting": "Күнделікті еске салғыш",
    "resetStats": "Статистиканы нөлдеу",
    "techSupport": "Техникалық қолдау",
    "termsOfUse": "Пайдалану шарттары",
    "privacyPolicy": "Құпиялылық саясаты",
    "questionOfTotal": "{current} / {total} сұрақ",
    "examAdditionalQuestionOfTotal": "Қосымша {current} / {total} сұрақ",
    "valueOfTotal": "{value} / {total}",
    "ticketNumber": "{number}-билет",
    "examShareText": "{result}\nДұрыс жауаптар: {correct} / {total}\n\n{title}\n{url}",
    "continueSessionSubtitle": "{title} · {index} / {total} сұрақ",
}

def translate_single(text, target_lang):
    url = 'https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=ru&tl=' + target_lang + '&q=' + urllib.parse.quote(text)
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                if isinstance(data, list) and len(data) > 0:
                    return data[0]
                return str(data)
        except Exception as e:
            time.sleep(0.5 + attempt * 0.5)
    return text

def translate_batch(texts, target_lang):
    joined = '\n'.join(texts)
    url = 'https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=ru&tl=' + target_lang + '&q=' + urllib.parse.quote(joined)
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                res = json.loads(resp.read().decode('utf-8'))[0]
                parts = res.split('\n')
                if len(parts) == len(texts):
                    return [p.strip() for p in parts]
        except Exception:
            time.sleep(0.5 + attempt * 0.5)
    # Fallback to single translate
    return [translate_single(t, target_lang) for t in texts]

def clean_placeholders(text, original_placeholders):
    for p in original_placeholders:
        var_name = p.strip('{}')
        pattern = re.compile(r'\{\s*' + re.escape(var_name) + r'\s*\}', re.IGNORECASE)
        text = pattern.sub('{' + var_name + '}', text)
    return text

def process_language(target_lang, ru_data, plurals_dict, curated_dict, target_file):
    print(f"\n--- Processing {target_lang.upper()} ({target_file}) ---")
    existing_data = {}
    if os.path.exists(target_file):
        try:
            with open(target_file, 'r', encoding='utf-8') as f:
                existing_data = json.load(f)
        except Exception:
            existing_data = {}

    out = {'@@locale': target_lang}
    
    keys_to_translate = []
    keys_metadata = {}

    for k, v in ru_data.items():
        if k.startswith('@'):
            continue
        
        # Check curated / plural / existing
        if k in plurals_dict:
            out[k] = plurals_dict[k]
        elif k in curated_dict:
            out[k] = curated_dict[k]
        elif k in existing_data and existing_data[k]:
            out[k] = existing_data[k]
        else:
            placeholders = re.findall(r'\{[a-zA-Z0-9_]+\}', v)
            keys_to_translate.append(k)
            keys_metadata[k] = {
                'ru_text': v,
                'placeholders': placeholders
            }

    print(f"Total keys: {len(ru_data) - len([k for k in ru_data if k.startswith('@')])}")
    print(f"Keys needing translation: {len(keys_to_translate)}")

    # Batch translate in chunks of 20
    chunk_size = 20
    for i in range(0, len(keys_to_translate), chunk_size):
        chunk_keys = keys_to_translate[i:i + chunk_size]
        batch_texts = []
        for ck in chunk_keys:
            raw_text = keys_metadata[ck]['ru_text']
            # Protect placeholders
            protected = raw_text
            for idx, p in enumerate(keys_metadata[ck]['placeholders']):
                protected = protected.replace(p, f'__VAR{idx}__')
            batch_texts.append(protected)

        translations = translate_batch(batch_texts, target_lang)
        for ck, trans in zip(chunk_keys, translations):
            res = trans
            for idx, p in enumerate(keys_metadata[ck]['placeholders']):
                res = re.sub(rf'__\s*VAR{idx}\s*__', p, res)
            res = clean_placeholders(res, keys_metadata[ck]['placeholders'])
            out[ck] = res

        print(f"Translated {min(i + chunk_size, len(keys_to_translate))}/{len(keys_to_translate)}")
        time.sleep(0.05)

    # Reorder according to ru_data order
    ordered_out = {'@@locale': target_lang}
    missing = []
    placeholder_mismatches = []
    for k, v in ru_data.items():
        if k.startswith('@'):
            continue
        if k not in out:
            missing.append(k)
        else:
            ordered_out[k] = out[k]
            # Check placeholders
            if 'plural' not in v:
                ru_vars = set(re.findall(r'\{[a-zA-Z0-9_]+\}', v))
                target_vars = set(re.findall(r'\{[a-zA-Z0-9_]+\}', ordered_out[k]))
                if ru_vars != target_vars:
                    placeholder_mismatches.append((k, ru_vars, target_vars))

    if missing:
        print(f"WARNING: Missing keys in {target_lang}: {missing}")
    if placeholder_mismatches:
        print(f"WARNING: Placeholder mismatches in {target_lang}: {len(placeholder_mismatches)}")
        for k, ru_vars, target_vars in placeholder_mismatches[:5]:
            print(f"  {k}: ru={ru_vars} != {target_lang}={target_vars}")

    with open(target_file, 'w', encoding='utf-8') as f:
        json.dump(ordered_out, f, ensure_ascii=False, indent=2)
    print(f"Successfully saved {target_file}")

def main():
    with open(RU_ARB, 'r', encoding='utf-8') as f:
        ru_data = json.load(f)

    # Check and insert new keys in ru_data
    updated_ru = False
    for k, v in NEW_KEYS_RU.items():
        if k not in ru_data:
            ru_data[k] = v
            updated_ru = True
    for k, v in NEW_KEYS_META.items():
        if k not in ru_data:
            ru_data[k] = v
            updated_ru = True

    if updated_ru:
        with open(RU_ARB, 'w', encoding='utf-8') as f:
            json.dump(ru_data, f, ensure_ascii=False, indent=2)
        print("Updated app_ru.arb with language keys")

    process_language('en', ru_data, PLURALS_EN, CURATED_EN, EN_ARB)
    process_language('kk', ru_data, PLURALS_KK, CURATED_KK, KK_ARB)

if __name__ == '__main__':
    main()
