#!/usr/bin/env python3
"""Audit every A/B and C/D illustration through the real read-only HTTP route."""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys
import threading
from urllib.error import HTTPError
from urllib.request import urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import question_pool
import server


http = server.Server(("127.0.0.1", 0), server.Handler)
thread = threading.Thread(target=http.serve_forever, daemon=True)
thread.start()
base = f"http://127.0.0.1:{http.server_port}"
pool = question_pool.QuestionPool()
counts = {}
try:
    for category in ("ab", "cd"):
        data = json.loads((server.QUESTIONS / f"questions_{category}.json").read_text())
        count = {"questions": 0, "images": 0, "without_image": 0, "named_images": 0}
        for ti, ticket in enumerate(data["tickets"], 1):
            for number, question in enumerate(ticket["questions"], 1):
                count["questions"] += 1
                image = question.get("image")
                url = f"/asset/source/{category}/{image}.webp" if image else None
                if category == "ab":
                    source = pool.source(f"ticket_{ticket.get('number', ti)}_{number}")
                    assert source["imageUrl"] == url
                    assert source["image"] == image
                if not image:
                    count["without_image"] += 1
                    continue
                count["images"] += 1
                count["named_images"] += not bool(re.fullmatch(r"[a-f0-9]{32}", image))
                path = server.IMAGES / f"questions_{category}" / f"{image}.webp"
                assert server.source_image(image, category) == path, (category, ti, number, image)
                expected = path.read_bytes()
                assert expected.startswith(b"RIFF") and expected[8:12] == b"WEBP", path
                with urlopen(base + url) as response:
                    assert response.status == 200 and response.headers["Content-Type"] == "image/webp"
                    assert response.read() == expected, (category, ti, number)
        counts[category] = count

    # A named illustration is available through both current and old scene links.
    assert pool.source("ticket_4_9")["image"] == "verified_ab_4_9"
    with urlopen(base + "/asset/source/verified_ab_4_9.webp") as response:
        assert response.read() == server.source_image("verified_ab_4_9", "ab").read_bytes()
    for category, name in (("ab", "verified_cd_4_9"), ("cd", "verified_ab_4_9"),
                           ("ab", "../../questions/questions_ab"), ("../../", "verified_ab_4_9")):
        assert server.source_image(name, category) is None
    for url in ("/asset/source/ab/verified_cd_4_9.webp", "/asset/source/unknown/verified_ab_4_9.webp",
                "/asset/source/ab/%2e%2e%2fquestions_ab.webp", "/asset/source/ab/verified_ab_4_9.json"):
        try:
            urlopen(base + url)
            raise AssertionError(f"Invalid illustration path was accepted: {url}")
        except HTTPError as error:
            assert error.code == 404
finally:
    http.shutdown()
    http.server_close()
    thread.join()

print("Reference illustrations: all source links return exact WebP bytes; no missing files; PASS")
print(json.dumps(counts, ensure_ascii=False))
