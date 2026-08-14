#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Скачивает SVG знаков Сербии с Wikimedia Commons (свободная лицензия).

Кладёт в assets/countries/rs/images/signs/<code>.svg. Wikimedia требует
User-Agent. 404/пустые — пропускаем и логируем (в signs.json попадут только
успешно скачанные знаки).

Запуск: python3 tools/rs_content/download_signs.py
"""
import os
import sys
import time
import urllib.request
import urllib.error
import urllib.parse

sys.path.insert(0, os.path.dirname(__file__))
from signs_catalog import all_entries  # noqa: E402

UA = "pdd-drive-app/1.0 (non-commercial educational; contact degtyarik.up@gmail.com)"
BASE = "https://commons.wikimedia.org/wiki/Special:FilePath/"
OUT = os.path.join("assets", "countries", "rs", "images", "signs")


def fetch(wiki_name):
    url = BASE + urllib.parse.quote(wiki_name)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def main():
    os.makedirs(OUT, exist_ok=True)
    ok, fail = [], []
    for cat, code, wiki, en in all_entries():
        dest = os.path.join(OUT, f"{code}.svg")
        try:
            data = fetch(wiki)
            if not data.lstrip().startswith(b"<") or len(data) < 200:
                raise ValueError(f"not an SVG ({len(data)} bytes)")
            with open(dest, "wb") as f:
                f.write(data)
            ok.append(code)
            print(f"  ok  {code:10s} <- {wiki} ({len(data)} B)")
        except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as e:
            fail.append((code, str(e)))
            print(f"  MISS {code:10s} {wiki}: {e}")
        time.sleep(0.15)  # вежливо к Wikimedia
    print(f"\ndownloaded {len(ok)} / {len(ok) + len(fail)}; misses: {len(fail)}")
    if fail:
        print("misses:", ", ".join(c for c, _ in fail))


if __name__ == "__main__":
    main()
