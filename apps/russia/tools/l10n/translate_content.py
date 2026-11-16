#!/usr/bin/env python3
"""
tools/l10n/translate_content.py

Extracts all textual content (questions, answers, comments, topics, signs, markup, PDD sections)
from Russian JSON sources, translates unique strings into English and Kazakh, maintains a persistent
translation cache with checkpointing, and writes out localized JSON bundles.
"""

import copy
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import lru_cache
from fix_letter_markers import EXPLICIT_LETTER_ANSWERS, illustration_labels, validate_marker_overrides

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QUESTIONS_DIR = os.path.join(REPO_ROOT, "assets", "countries", "ru", "questions")
CACHE_EN_PATH = os.path.join(HERE, "cache_en.json")
CACHE_KK_PATH = os.path.join(HERE, "cache_kk.json")

CYRILLIC_PATTERN = re.compile(r'[а-яА-ЯёЁ]')
CYRILLIC_WORD = re.compile(r'[а-яА-ЯёЁ]{4,}')

@lru_cache(maxsize=2)
def fallback_translator(target_lang):
    from deep_translator import MyMemoryTranslator
    return MyMemoryTranslator(source='ru-RU', target='kk-KZ' if target_lang == 'kk' else 'en-GB')

def load_json(filepath):
    if not os.path.exists(filepath):
        return None
    with open(filepath, "r", encoding="utf-8") as f:
        return json.load(f)

def save_json(filepath, data):
    tmp_path = filepath + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, filepath)

def load_cache(filepath):
    if os.path.exists(filepath):
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: failed to load {filepath}: {e}")
    return {}

def translate_simple(text_stripped, target_lang, retries=5):
    if not text_stripped or not CYRILLIC_PATTERN.search(text_stripped):
        return text_stripped

    ru_words = [w for w in re.findall(r'\b[а-яА-ЯёЁ]{3,}\b', text_stripped) if w.lower() not in ('мм', 'см', 'км', 'мин', 'сек')]

    for attempt in range(retries):
        # 1. Google via translators
        try:
            import translators as ts
            res = ts.translate_text(
                text_stripped,
                from_language="ru",
                to_language=target_lang,
                translator="google",
                timeout=15,
            )
            if res and res.strip():
                if target_lang == "en":
                    if CYRILLIC_WORD.search(res):
                        raise ValueError(f"Cyrillic in English: {res[:40]}")
                    return res.strip()
                elif target_lang == "kk":
                    if ru_words and res.strip() == text_stripped:
                        raise ValueError(f"Failed to translate to kk: {res[:40]}")
                    return res.strip()
        except Exception:
            time.sleep(0.5 * (attempt + 1))

        # 2. MyMemory fallback if short
        if len(text_stripped) <= 450:
            try:
                tr = fallback_translator(target_lang)
                m_res = tr.translate(text_stripped)
                if m_res and m_res.strip():
                    if target_lang == "en" and not CYRILLIC_WORD.search(m_res):
                        return m_res.strip()
                    elif target_lang == "kk":
                        if not (ru_words and m_res.strip() == text_stripped):
                            return m_res.strip()
            except Exception:
                pass

        time.sleep(0.4)

    return None

def translate_single(text, target_lang, retries=5):
    text_stripped = text.strip()
    if not text_stripped or not CYRILLIC_PATTERN.search(text_stripped):
        return text

    prefix = text[: len(text) - len(text.lstrip())]
    suffix = text[len(text.rstrip()) :]

    # If text is reasonably sized, translate directly
    if len(text_stripped) <= 1500:
        res = translate_simple(text_stripped, target_lang, retries=retries)
        return prefix + res + suffix if res else None

    # For large texts (e.g. multi-KB PDD sections), split iteratively by lines
    lines = text_stripped.split('\n')
    chunks = []
    curr = []
    curr_len = 0
    for line in lines:
        if curr_len + len(line) > 1200 and curr:
            chunks.append('\n'.join(curr))
            curr = [line]
            curr_len = len(line)
        else:
            curr.append(line)
            curr_len += len(line)
    if curr:
        chunks.append('\n'.join(curr))

    translated_chunks = []
    for c in chunks:
        if not c.strip() or not CYRILLIC_PATTERN.search(c):
            translated_chunks.append(c)
            continue
        c_res = translate_simple(c.strip(), target_lang, retries=retries)
        if not c_res:
            # A partly translated rule section is not a successful translation.
            # Keep the previous reviewed cache entry; do not publish a mixed text.
            return None
        translated_chunks.append(c_res)

    joined = '\n'.join(translated_chunks)
    return prefix + joined + suffix

def needs_translation(orig, trans, target_lang):
    if not trans or not trans.strip():
        return True
    if target_lang == 'en':
        if CYRILLIC_WORD.search(trans):
            return True
        return False
    elif target_lang == 'kk':
        if trans.strip() == orig.strip():
            ru_words = re.findall(r'\b[а-яА-ЯёЁ]{3,}\b', orig)
            real_words = [w for w in ru_words if w.lower() not in ('мм', 'см', 'км', 'мин', 'сек')]
            if real_words:
                return True
        return False
    return False

def populate_translation_cache(strings_to_translate, target_lang, cache, cache_file):
    to_retranslate = []
    for s in strings_to_translate:
        if not s or not s.strip():
            continue
        val = cache.get(s)
        if needs_translation(s, val, target_lang):
            to_retranslate.append(s)

    total = len(to_retranslate)
    if not total:
        print(f"All {len(strings_to_translate)} strings already valid in {target_lang} cache!")
        return cache

    print(f"Translating {total} strings to {target_lang} (cache currently has {len(cache)})...")
    completed = 0

    with ThreadPoolExecutor(max_workers=5) as executor:
        future_to_str = {
            executor.submit(translate_single, s, target_lang): s for s in to_retranslate
        }

        for future in as_completed(future_to_str):
            orig = future_to_str[future]
            try:
                translated = future.result()
                if translated:
                    cache[orig] = translated
                else:
                    print(f"[{target_lang}] Failed translation for: {repr(orig[:40])}")
            except Exception as e:
                print(f"[{target_lang}] Error for '{orig[:30]}': {e}")

            completed += 1
            if completed % 25 == 0 or completed == total:
                print(f"[{target_lang}] Progress: {completed}/{total} ({completed * 100 // total}%)")
                save_json(cache_file, cache)
            time.sleep(0.04)

    # Sequential retry for any remaining failures
    remaining = [s for s in strings_to_translate if needs_translation(s, cache.get(s), target_lang)]
    if remaining:
        print(f"[{target_lang}] Performing sequential retry for {len(remaining)} remaining strings...")
        for idx, s in enumerate(remaining):
            trans = translate_single(s, target_lang, retries=6)
            if trans:
                cache[s] = trans
            else:
                print(f"[{target_lang}] Final attempt failed for: {repr(s[:50])}")
            if (idx + 1) % 10 == 0:
                save_json(cache_file, cache)

    save_json(cache_file, cache)
    missing = [s for s in strings_to_translate if s.strip() and not cache.get(s)]
    if missing:
        raise RuntimeError(f'{target_lang}: {len(missing)} translations missing; content files were not written')
    print(f"Finished {target_lang} cache. Total valid cached items: {len(cache)}")
    return cache

def collect_all_strings():
    unique_strings = set()

    for fname in ["questions_ab.json", "questions_cd.json"]:
        path = os.path.join(QUESTIONS_DIR, fname)
        data = load_json(path)
        if not data: continue
        for ticket in data.get("tickets", []):
            for q in ticket.get("questions", []):
                if q.get("question"): unique_strings.add(q["question"])
                for a in q.get("answers", []):
                    if a.get("text"): unique_strings.add(a["text"])
                if q.get("comment"): unique_strings.add(q["comment"])
                for top in q.get("topic", []):
                    if top: unique_strings.add(top)

    for fname in ["topics_ab.json", "topics_cd.json"]:
        path = os.path.join(QUESTIONS_DIR, fname)
        data = load_json(path)
        if not data: continue
        for top in data.get("topics", []):
            if top.get("name"): unique_strings.add(top["name"])
            for q in top.get("questions", []):
                if q.get("question"): unique_strings.add(q["question"])
                for a in q.get("answers", []):
                    if a.get("text"): unique_strings.add(a["text"])
                if q.get("comment"): unique_strings.add(q["comment"])
                for t in q.get("topic", []):
                    if t: unique_strings.add(t)

    signs_data = load_json(os.path.join(QUESTIONS_DIR, "signs.json"))
    if signs_data:
        for cat, items in signs_data.items():
            unique_strings.add(cat)
            for num, item in items.items():
                if item.get("title"): unique_strings.add(item["title"])
                if item.get("description"): unique_strings.add(item["description"])
                if item.get("folkName"): unique_strings.add(item["folkName"])

    manifest_data = load_json(os.path.join(QUESTIONS_DIR, "signs_feed_manifest.json"))
    if manifest_data:
        for item in manifest_data:
            if item.get("category"): unique_strings.add(item["category"])
            if item.get("title"): unique_strings.add(item["title"])
            if item.get("description"): unique_strings.add(item["description"])
            if item.get("questionText"): unique_strings.add(item["questionText"])
            for a in item.get("answers", []):
                if a: unique_strings.add(a)

    markup_data = load_json(os.path.join(QUESTIONS_DIR, "markup.json"))
    if markup_data:
        for cat, items in markup_data.items():
            unique_strings.add(cat)
            for item in items:
                if item.get("title"): unique_strings.add(item["title"])
                if item.get("description"): unique_strings.add(item["description"])

    pdd_data = load_json(os.path.join(QUESTIONS_DIR, "pdd_sections.json"))
    if pdd_data:
        for s in pdd_data:
            if s.get("title"): unique_strings.add(s["title"])
            if s.get("content"): unique_strings.add(s["content"])

    return sorted(list(unique_strings))

def validate_answer_labels(source, translated, group_key):
    for source_group, target_group in zip(source[group_key], translated[group_key]):
        for source_question, target_question in zip(source_group['questions'], target_group['questions']):
            for source_answer, target_answer in zip(source_question['answers'], target_question['answers']):
                expected = illustration_labels(source_answer['text'], russian=True)
                if expected and illustration_labels(target_answer['text']) != expected:
                    raise ValueError(f"Illustration labels changed in {source_question['id']}: {source_answer['text']!r}")


def translate_questions_file(source_fname, target_fname, cache):
    src_data = load_json(os.path.join(QUESTIONS_DIR, source_fname))
    res = copy.deepcopy(src_data)
    for ticket in res.get("tickets", []):
        for q in ticket.get("questions", []):
            if q.get("question") in cache:
                q["question"] = cache[q["question"]]
            for a in q.get("answers", []):
                if a.get("text") in cache:
                    a["text"] = cache[a["text"]]
            if q.get("comment") and q["comment"] in cache:
                q["comment"] = cache[q["comment"]]
            if q.get("topic"):
                q["topic"] = [cache.get(t, t) for t in q["topic"]]

    validate_answer_labels(src_data, res, 'tickets')
    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def translate_topics_file(source_fname, target_fname, cache):
    src_data = load_json(os.path.join(QUESTIONS_DIR, source_fname))
    res = copy.deepcopy(src_data)
    for top in res.get("topics", []):
        if top.get("name") in cache:
            top["name"] = cache[top["name"]]
        for q in top.get("questions", []):
            if q.get("question") in cache:
                q["question"] = cache[q["question"]]
            for a in q.get("answers", []):
                if a.get("text") in cache:
                    a["text"] = cache[a["text"]]
            if q.get("comment") and q["comment"] in cache:
                q["comment"] = cache[q["comment"]]
            if q.get("topic"):
                q["topic"] = [cache.get(t, t) for t in q["topic"]]

    validate_answer_labels(src_data, res, 'topics')
    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def translate_signs_file(target_fname, cache):
    src_data = load_json(os.path.join(QUESTIONS_DIR, "signs.json"))
    res = {}
    for cat, items in src_data.items():
        trans_cat = cache.get(cat, cat)
        res[trans_cat] = {}
        for num, item in items.items():
            new_item = dict(item)
            if item.get("title") in cache:
                new_item["title"] = cache[item["title"]]
            if item.get("description") in cache:
                new_item["description"] = cache[item["description"]]
            if item.get("folkName") and item["folkName"] in cache:
                new_item["folkName"] = cache[item["folkName"]]
            res[trans_cat][num] = new_item

    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def translate_signs_feed_manifest(target_fname, cache):
    src_data = load_json(os.path.join(QUESTIONS_DIR, "signs_feed_manifest.json"))
    res = []
    for item in src_data:
        new_item = dict(item)
        if item.get("category") in cache:
            new_item["category"] = cache[item["category"]]
        if item.get("title") in cache:
            new_item["title"] = cache[item["title"]]
        if item.get("description") in cache:
            new_item["description"] = cache[item["description"]]
        if item.get("questionText") in cache:
            new_item["questionText"] = cache[item["questionText"]]
        if item.get("answers"):
            new_item["answers"] = [cache.get(a, a) for a in item["answers"]]
        res.append(new_item)

    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def translate_markup_file(target_fname, cache):
    src_data = load_json(os.path.join(QUESTIONS_DIR, "markup.json"))
    res = {}
    for cat, items in src_data.items():
        trans_cat = cache.get(cat, cat)
        res[trans_cat] = []
        for item in items:
            new_item = dict(item)
            if item.get("title") in cache:
                new_item["title"] = cache[item["title"]]
            if item.get("description") in cache:
                new_item["description"] = cache[item["description"]]
            res[trans_cat].append(new_item)

    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def translate_pdd_sections_file(target_fname, cache):
    src_data = load_json(os.path.join(QUESTIONS_DIR, "pdd_sections.json"))
    res = []
    for s in src_data:
        new_s = dict(s)
        if s.get("title") in cache:
            new_s["title"] = cache[s["title"]]
        if s.get("content") in cache:
            new_s["content"] = cache[s["content"]]
        point_start = re.compile(r'^(\d{1,2}(?:\.\d{1,2}){1,3})\.', re.MULTILINE)
        if point_start.findall(s['content']) != point_start.findall(new_s['content']):
            raise ValueError(f"Rule point numbering changed in {target_fname}: {s['title']}")
        res.append(new_s)

    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def audit_file(filepath, lang):
    """Limited leftover-text checks; Cyrillic illustration labels are intentional."""
    data = load_json(filepath)
    if not data:
        return [f"{filepath}: Failed to load file"]
    issues = []
    text_content = json.dumps(data, ensure_ascii=False)

    if lang == "en":
        cyr_words = CYRILLIC_WORD.findall(text_content)
        if len(cyr_words) > 0:
            issues.append(f"{os.path.basename(filepath)}: found {len(cyr_words)} Cyrillic words! Samples: {cyr_words[:5]}")
    elif lang == "kk":
        ru_samples = re.findall(r'\b(Перед знаком|Перед перекрестком|Разрешен ли|Разрешено|Запрещено во всех случаях|Остановиться перед|у линии разметки)\b', text_content, re.IGNORECASE)
        if len(ru_samples) > 0:
            issues.append(f"{os.path.basename(filepath)}: found {len(ru_samples)} Russian phrases! Samples: {ru_samples[:5]}")
    return issues

def main():
    print("Collecting all unique strings from Russian content sources...")
    strings = collect_all_strings()
    print(f"Total unique strings found: {len(strings)}")

    cache_en = load_cache(CACHE_EN_PATH)
    cache_kk = load_cache(CACHE_KK_PATH)

    print("\n--- Processing English Translations ---")
    cache_en = populate_translation_cache(strings, "en", cache_en, CACHE_EN_PATH)

    print("\n--- Processing Kazakh Translations ---")
    cache_kk = populate_translation_cache(strings, "kk", cache_kk, CACHE_KK_PATH)

    print("\n--- Applying Explicit Cyrillic Letter Marker Overrides ---")
    validate_marker_overrides()
    for ru_text, (en_val, kk_val) in EXPLICIT_LETTER_ANSWERS.items():
        cache_en[ru_text] = en_val
        cache_kk[ru_text] = kk_val

    print("\n--- Generating Localized Content Files ---")
    for lang, cache in [("en", cache_en), ("kk", cache_kk)]:
        print(f"\nWriting files for language: {lang}")
        translate_questions_file("questions_ab.json", f"questions_ab_{lang}.json", cache)
        translate_questions_file("questions_cd.json", f"questions_cd_{lang}.json", cache)
        translate_topics_file("topics_ab.json", f"topics_ab_{lang}.json", cache)
        translate_topics_file("topics_cd.json", f"topics_cd_{lang}.json", cache)
        translate_signs_file(f"signs_{lang}.json", cache)
        translate_signs_feed_manifest(f"signs_feed_manifest_{lang}.json", cache)
        translate_markup_file(f"markup_{lang}.json", cache)
        translate_pdd_sections_file(f"pdd_sections_{lang}.json", cache)

    print("\n--- Auditing Generated Files ---")
    all_issues = []
    for lang in ["en", "kk"]:
        for fpattern in [f"questions_ab_{lang}.json", f"questions_cd_{lang}.json", f"topics_ab_{lang}.json", f"topics_cd_{lang}.json", f"signs_{lang}.json", f"signs_feed_manifest_{lang}.json", f"markup_{lang}.json", f"pdd_sections_{lang}.json"]:
            path = os.path.join(QUESTIONS_DIR, fpattern)
            issues = audit_file(path, lang)
            all_issues.extend(issues)

    if all_issues:
        print("AUDIT FAILED with issues:")
        for iss in all_issues:
            print("  -", iss)
        sys.exit(1)
    else:
        print("Basic checks passed. Semantic review and illustration-label tests are still required.")

if __name__ == "__main__":
    main()
