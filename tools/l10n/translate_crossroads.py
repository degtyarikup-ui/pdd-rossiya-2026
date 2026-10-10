#!/usr/bin/env python3
"""
tools/l10n/translate_crossroads.py

Extracts all crossroads scenarios and their actors from crossroads_priority_model.dart,
translates title, subtitle, pddArticle, actor name, and ruleExplanation into English and Kazakh,
and generates lib/data/models/crossroads_translations.dart with type-safe const maps.
"""

import json
import os
import random
import re
import time
from curl_cffi import requests

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODEL_PATH = os.path.join(REPO_ROOT, "lib", "data", "models", "crossroads_priority_model.dart")
OUT_DART_PATH = os.path.join(REPO_ROOT, "lib", "data", "models", "crossroads_translations.dart")
CACHE_PATH = os.path.join(HERE, "crossroads_cache.json")

BROWSERS = ["chrome120", "safari17_0", "edge101", "chrome119"]

def load_cache():
    cache = {"en": {}, "kk": {}}
    for lang, path in [("en", os.path.join(HERE, "cache_en.json")), ("kk", os.path.join(HERE, "cache_kk.json"))]:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    cache[lang].update(json.load(f))
            except Exception:
                pass
    if os.path.exists(CACHE_PATH):
        try:
            with open(CACHE_PATH, "r", encoding="utf-8") as f:
                d = json.load(f)
                cache["en"].update(d.get("en", {}))
                cache["kk"].update(d.get("kk", {}))
        except Exception:
            pass
    return cache

def save_cache(cache):
    with open(CACHE_PATH, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)

from translate_content import ProxyPool, translate_single

def translate_str(text, target_lang, cache, proxy_pool):
    text_stripped = text.strip()
    if not text_stripped:
        return text
    if text_stripped in cache[target_lang]:
        return cache[target_lang][text_stripped]

    res = translate_single(text_stripped, target_lang, proxy_pool)
    cache[target_lang][text_stripped] = res
    return res

def main():
    print("Reading crossroads_priority_model.dart...")
    with open(MODEL_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    cache = load_cache()

    # Split into scenario blocks
    scen_blocks = re.split(r'const CrossroadsScenario\(', content)[1:]
    scenarios_data = []

    for block in scen_blocks:
        m_id = re.search(r'id:\s*\'([^\']+)\'', block)
        m_title = re.search(r'title:\s*\'([^\']+)\'', block)
        m_sub = re.search(r'subtitle:\s*\'([^\']+)\'', block)
        m_pdd = re.search(r'pddArticle:\s*\'([^\']+)\'', block)
        if not (m_id and m_title and m_sub and m_pdd):
            continue

        scen_id = m_id.group(1)
        title = m_title.group(1)
        sub = m_sub.group(1)
        pdd = m_pdd.group(1)

        actors_data = []
        actor_matches = re.finditer(
            r'CrossroadsActor\(\s*id:\s*\'([^\']+)\'[\s\S]*?name:\s*\'([^\']+)\'[\s\S]*?ruleExplanation:\s*\'([^\']+)\'',
            block
        )
        for am in actor_matches:
            actors_data.append({
                "id": am.group(1),
                "name": am.group(2),
                "explanation": am.group(3)
            })

        scenarios_data.append({
            "id": scen_id,
            "title": title,
            "subtitle": sub,
            "pddArticle": pdd,
            "actors": actors_data
        })

    print(f"Extracted {len(scenarios_data)} scenarios.")

    proxy_pool = ProxyPool()

    # Collect all unique strings across scenarios
    all_strings = set()
    for sc in scenarios_data:
        if sc["title"]: all_strings.add(sc["title"].strip())
        if sc["subtitle"]: all_strings.add(sc["subtitle"].strip())
        if sc["pddArticle"]: all_strings.add(sc["pddArticle"].strip())
        for a in sc["actors"]:
            if a["name"]: all_strings.add(a["name"].strip())
            if a["explanation"]: all_strings.add(a["explanation"].strip())

    print(f"Total unique strings to localize for crossroads: {len(all_strings)}")

    from concurrent.futures import ThreadPoolExecutor, as_completed

    # Translate for EN and KK
    translations = {"en": {}, "kk": {}}
    for lang in ["en", "kk"]:
        missing = [s for s in all_strings if s not in cache[lang]]
        print(f"Translating {len(missing)} missing strings to {lang} (already in cache: {len(all_strings) - len(missing)})...")

        if missing:
            with ThreadPoolExecutor(max_workers=10) as executor:
                future_to_s = {
                    executor.submit(translate_single, s, lang, proxy_pool): s for s in missing
                }
                for future in as_completed(future_to_s):
                    orig = future_to_s[future]
                    try:
                        res = future.result()
                        cache[lang][orig] = res
                    except Exception as e:
                        cache[lang][orig] = orig

        save_cache(cache)

        # Build scenario structures from cache
        for sc in scenarios_data:
            t_title = cache[lang].get(sc["title"], sc["title"])
            t_sub = cache[lang].get(sc["subtitle"], sc["subtitle"])
            t_pdd = cache[lang].get(sc["pddArticle"], sc["pddArticle"])

            actors_tr = {}
            for a in sc["actors"]:
                a_name = cache[lang].get(a["name"], a["name"])
                a_exp = cache[lang].get(a["explanation"], a["explanation"])
                actors_tr[a["id"]] = {
                    "name": a_name,
                    "explanation": a_exp
                }

            translations[lang][sc["id"]] = {
                "title": t_title,
                "subtitle": t_sub,
                "pddArticle": t_pdd,
                "actors": actors_tr
            }

    print("Generating lib/data/models/crossroads_translations.dart...")
    dart_lines = [
        "// Generated file by tools/l10n/translate_crossroads.py. Do not edit manually.",
        "",
        "class LocalizedScenarioText {",
        "  const LocalizedScenarioText({",
        "    required this.title,",
        "    required this.subtitle,",
        "    required this.pddArticle,",
        "    required this.actors,",
        "  });",
        "",
        "  final String title;",
        "  final String subtitle;",
        "  final String pddArticle;",
        "  final Map<String, LocalizedActorText> actors;",
        "}",
        "",
        "class LocalizedActorText {",
        "  const LocalizedActorText({",
        "    required this.name,",
        "    required this.ruleExplanation,",
        "  });",
        "",
        "  final String name;",
        "  final String ruleExplanation;",
        "}",
        "",
        "class CrossroadsTranslations {",
        "  CrossroadsTranslations._();",
        "",
        "  static const Map<String, Map<String, LocalizedScenarioText>> localizedScenarios = {",
    ]

    for lang in ["en", "kk"]:
        dart_lines.append(f"    '{lang}': {{")
        for sc_id, sc in translations[lang].items():
            t_title = sc["title"].replace("'", "\\'")
            t_sub = sc["subtitle"].replace("'", "\\'")
            t_pdd = sc["pddArticle"].replace("'", "\\'")
            dart_lines.append(f"      '{sc_id}': LocalizedScenarioText(")
            dart_lines.append(f"        title: '{t_title}',")
            dart_lines.append(f"        subtitle: '{t_sub}',")
            dart_lines.append(f"        pddArticle: '{t_pdd}',")
            dart_lines.append("        actors: {")
            for a_id, a_data in sc["actors"].items():
                a_name = a_data["name"].replace("'", "\\'")
                a_exp = a_data["explanation"].replace("'", "\\'")
                dart_lines.append(f"          '{a_id}': LocalizedActorText(")
                dart_lines.append(f"            name: '{a_name}',")
                dart_lines.append(f"            ruleExplanation: '{a_exp}',")
                dart_lines.append("          ),")
            dart_lines.append("        },")
            dart_lines.append("      ),")
        dart_lines.append("    },")

    dart_lines.append("  };")
    dart_lines.append("}")
    dart_lines.append("")

    with open(OUT_DART_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(dart_lines))

    print(f"Successfully generated {OUT_DART_PATH}!")

if __name__ == "__main__":
    main()
