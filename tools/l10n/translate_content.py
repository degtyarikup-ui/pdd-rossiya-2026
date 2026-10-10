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
import random
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QUESTIONS_DIR = os.path.join(REPO_ROOT, "assets", "countries", "ru", "questions")
CACHE_EN_PATH = os.path.join(HERE, "cache_en.json")
CACHE_KK_PATH = os.path.join(HERE, "cache_kk.json")

CYRILLIC_PATTERN = re.compile(r'[а-яА-ЯёЁ]')
BROWSERS = ["chrome120", "safari17_0", "edge101", "chrome119"]

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

import threading

class ProxyPool:
    def __init__(self):
        self.working = []
        self.lock = threading.Lock()

    def refresh(self):
        with self.lock:
            if len(self.working) >= 1:
                return
            print("Refreshing proxy pool from multiple sources...")
            urls = [
                'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt',
                'https://raw.githubusercontent.com/roosterkid/openproxylist/main/HTTPS_RAW.txt',
                'https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/http.txt',
                'https://raw.githubusercontent.com/sunny9577/proxy-scraper/master/generated/http_proxies.txt',
                'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/http.txt',
                'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/https.txt',
                'https://api.proxyscrape.com/v2/?request=displayproxies&protocol=http&timeout=2500&country=all&ssl=yes&anonymity=elite',
            ]
            candidates = set()
            for u in urls:
                try:
                    r = requests.get(u, timeout=3)
                    if r.status_code == 200:
                        for line in r.text.splitlines():
                            line_s = line.strip()
                            if line_s and ":" in line_s:
                                candidates.add(line_s)
                except Exception:
                    pass

            def test_p(p):
                try:
                    pr = {'http': f'http://{p}', 'https': f'http://{p}'}
                    res = requests.get(
                        'https://translate.googleapis.com/translate_a/single?client=at&sl=ru&tl=en&dt=t&q=Тест',
                        proxies=pr,
                        timeout=2.0
                    )
                    if res.status_code == 200:
                        return p
                except Exception:
                    pass
                return None

            found = []
            cand_list = list(candidates)
            random.shuffle(cand_list)
            executor = ThreadPoolExecutor(max_workers=80)
            try:
                futures = [executor.submit(test_p, p) for p in cand_list[:1200]]
                for f in as_completed(futures):
                    res = f.result()
                    if res:
                        found.append(res)
                        if len(found) >= 12:
                            break
            finally:
                executor.shutdown(wait=False, cancel_futures=True)

            self.working = found
            print(f"Proxy pool ready with {len(self.working)} working proxies.")

    def get_proxy(self):
        if len(self.working) < 1:
            self.refresh()
        with self.lock:
            if not self.working:
                return None
            return random.choice(self.working)

    def remove_proxy(self, p):
        with self.lock:
            if p in self.working:
                self.working.remove(p)

import urllib.parse
from deep_translator import MyMemoryTranslator

tr_kk = MyMemoryTranslator(source='ru-RU', target='kk-KZ')
tr_en = MyMemoryTranslator(source='ru-RU', target='en-GB')

def translate_single(text, target_lang, proxy_pool=None, retries=3):
    text_stripped = text.strip()
    if not text_stripped:
        return text

    tr = tr_kk if target_lang == 'kk' else tr_en
    prefix = text[: len(text) - len(text.lstrip())]
    suffix = text[len(text.rstrip()) :]

    if len(text_stripped) <= 450:
        for attempt in range(retries):
            try:
                res = tr.translate(text_stripped)
                if res and res.strip() and res.strip() != text_stripped:
                    return prefix + res.strip() + suffix
            except Exception:
                time.sleep(0.3)
        return None

    # Chunk long strings
    parts = re.split(r'(\n+|\.\s+)', text_stripped)
    translated_parts = []
    chunk = ''
    for p in parts:
        if len(chunk) + len(p) < 400:
            chunk += p
        else:
            if chunk.strip():
                try:
                    c_res = tr.translate(chunk.strip())
                    translated_parts.append(c_res if c_res else chunk)
                except Exception:
                    translated_parts.append(chunk)
            else:
                translated_parts.append(chunk)
            chunk = p
    if chunk:
        if chunk.strip():
            try:
                c_res = tr.translate(chunk.strip())
                translated_parts.append(c_res if c_res else chunk)
            except Exception:
                translated_parts.append(chunk)
        else:
            translated_parts.append(chunk)

    joined = ''.join(translated_parts)
    return prefix + joined + suffix if joined else None

def populate_translation_cache(strings_to_translate, target_lang, cache, cache_file, proxy_pool):
    # Clean cache of any failed translations (where value equals Russian key)
    to_retranslate = []
    for s in strings_to_translate:
        if not s or not s.strip():
            continue
        val = cache.get(s)
        if not val:
            to_retranslate.append(s)
        elif target_lang == "en" and val == s and CYRILLIC_PATTERN.search(s):
            to_retranslate.append(s)
        elif target_lang == "kk" and val == s and len(s) > 10:
            to_retranslate.append(s)

    total = len(to_retranslate)
    if not total:
        print(f"All {len(strings_to_translate)} strings already cached for {target_lang}!")
        return cache

    print(f"Translating {total} strings to {target_lang} (cache already has {len(cache)})...")
    completed = 0

    with ThreadPoolExecutor(max_workers=8) as executor:
        future_to_str = {
            executor.submit(translate_single, s, target_lang, proxy_pool): s for s in to_retranslate
        }

        for future in as_completed(future_to_str):
            orig = future_to_str[future]
            try:
                translated = future.result()
                if translated:
                    cache[orig] = translated
            except Exception as e:
                print(f"Error for '{orig[:30]}': {e}")

            completed += 1
            if completed % 25 == 0 or completed == total:
                print(f"[{target_lang}] Completed {completed}/{total} ({completed * 100 // total}%)")
                save_json(cache_file, cache)
            time.sleep(0.02)

    save_json(cache_file, cache)
    print(f"Finished {target_lang} cache. Total cached items: {len(cache)}")
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
        res.append(new_s)

    save_json(os.path.join(QUESTIONS_DIR, target_fname), res)
    print(f"Generated {target_fname}")

def main():
    print("Collecting all unique strings from Russian content sources...")
    strings = collect_all_strings()
    print(f"Total unique strings found: {len(strings)}")

    cache_en = load_cache(CACHE_EN_PATH)
    cache_kk = load_cache(CACHE_KK_PATH)

    proxy_pool = ProxyPool()

    print("\n--- Processing English Translations ---")
    cache_en = populate_translation_cache(strings, "en", cache_en, CACHE_EN_PATH, proxy_pool)

    print("\n--- Processing Kazakh Translations ---")
    cache_kk = populate_translation_cache(strings, "kk", cache_kk, CACHE_KK_PATH, proxy_pool)

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

    print("\nAll localized files successfully generated!")

if __name__ == "__main__":
    main()
