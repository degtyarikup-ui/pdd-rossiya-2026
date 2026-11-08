#!/usr/bin/env python3
"""Batch audio generator for all PDD questions and road signs.

Uses Microsoft Dmitry Neural (+16% rate, short pause dashes)
Outputs: assets/audio/feed/q_<id>.mp3 and assets/audio/feed/sign_<id>.mp3
Also saves assets/countries/ru/questions/signs_feed_manifest.json for deterministic sign quizzes.
"""

import asyncio
import edge_tts
import json
import os
import random
import re
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent
QUESTIONS_AB = ROOT_DIR / "assets" / "countries" / "ru" / "questions" / "questions_ab.json"
SIGNS_JSON = ROOT_DIR / "assets" / "countries" / "ru" / "questions" / "signs.json"
SIGNS_MANIFEST = ROOT_DIR / "assets" / "countries" / "ru" / "questions" / "signs_feed_manifest.json"
AUDIO_DIR = ROOT_DIR / "assets" / "audio" / "feed"

NUMBER_WORDS = {1: 'Один', 2: 'Два', 3: 'Три', 4: 'Четыре', 5: 'Пять', 6: 'Шесть'}
VOICE = "ru-RU-DmitryNeural"
RATE = "+16%"
CONCURRENCY = 30

def clean_text_for_speech(text: str) -> str:
    t = text.strip().rstrip('.').rstrip('?')
    t = re.sub(r'\s+', ' ', t)
    return t

def format_speech_text(question: str, answers: list[str]) -> str:
    q_clean = clean_text_for_speech(question)
    parts = [f"{q_clean}?"]
    for i, ans in enumerate(answers):
        num_word = NUMBER_WORDS.get(i + 1, str(i + 1))
        ans_clean = clean_text_for_speech(ans)
        parts.append(f"{num_word} — {ans_clean}.")
    return " ".join(parts)

def build_signs_manifest():
    with open(SIGNS_JSON, "r", encoding="utf-8") as f:
        all_signs_data = json.load(f)

    # Category -> List of {number, title, description, image}
    category_signs = {}
    all_signs_flat = []

    for cat_name, signs_map in all_signs_data.items():
        if isinstance(signs_map, dict):
            signs_list = []
            for s_num, s_data in signs_map.items():
                if isinstance(s_data, dict):
                    title = s_data.get('title') or s_data.get('name') or s_num
                    desc = s_data.get('description', '')
                    raw_img = s_data.get('image', '')
                    img_filename = raw_img.split('/')[-1] if raw_img else ''
                    if title and img_filename:
                        item = {
                            'number': s_num,
                            'title': title,
                            'description': desc,
                            'image': img_filename,
                            'category': cat_name
                        }
                        signs_list.append(item)
                        all_signs_flat.append(item)
            if signs_list:
                category_signs[cat_name] = signs_list

    # Deterministic RNG for consistent distractor options
    rng = random.Random(20260824)
    manifest = []

    for cat_name, signs_list in category_signs.items():
        for sign in signs_list:
            correct_title = sign['title']
            sign_num = sign['number']
            sign_img = sign['image']
            sign_desc = sign['description']

            pool = [s['title'] for s in signs_list if s['title'] != correct_title]
            rng.shuffle(pool)
            chosen = pool[:3]

            if len(chosen) < 3:
                fallback_pool = [s['title'] for s in all_signs_flat if s['title'] != correct_title and s['title'] not in chosen]
                rng.shuffle(fallback_pool)
                chosen.extend(fallback_pool[:3 - len(chosen)])

            options = [correct_title] + chosen
            rng.shuffle(options)
            correct_idx = options.index(correct_title)

            # Safe ID for filename: e.g. warning_1_1 or number sanitized
            safe_cat = re.sub(r'[^a-zA-Z0-9]', '', cat_name.encode('ascii', 'ignore').decode('ascii')) or 'cat'
            safe_num = sign_num.replace('.', '_').replace('/', '_').replace('-', '_')
            sign_id = f"sign_{safe_num}"

            manifest.append({
                'id': sign_id,
                'category': cat_name,
                'number': sign_num,
                'title': correct_title,
                'description': sign_desc,
                'image': sign_img,
                'questionText': 'Что означает этот дорожный знак?',
                'answers': options,
                'correctAnswerIndex': correct_idx,
                'audioFileName': f"{sign_id}.mp3"
            })

    SIGNS_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(SIGNS_MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(f"Generated signs quiz manifest with {len(manifest)} items -> {SIGNS_MANIFEST}")
    return manifest

async def generate_single_audio(sem: asyncio.Semaphore, text: str, output_file: Path, label: str):
    if output_file.exists() and output_file.stat().st_size > 1024:
        return True, "skipped"

    async with sem:
        for attempt in range(4):
            try:
                communicate = edge_tts.Communicate(text, voice=VOICE, rate=RATE)
                await communicate.save(str(output_file))
                if output_file.exists() and output_file.stat().st_size > 1024:
                    return True, "generated"
            except Exception as e:
                if attempt == 3:
                    print(f"  [ERROR] Failed {label}: {e}")
                    return False, str(e)
                await asyncio.sleep(1.0 * (attempt + 1))
    return False, "unknown"

async def main():
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Load questions AB
    with open(QUESTIONS_AB, "r", encoding="utf-8") as f:
        ab_data = json.load(f)

    ticket_tasks = []
    total_tickets_count = 0
    for ticket in ab_data.get('tickets', []):
        for q in ticket.get('questions', []):
            q_id = q['id']
            q_text = q['question']
            answers = [a['text'] for a in q.get('answers', [])]
            if not answers:
                continue

            speech_text = format_speech_text(q_text, answers)
            out_file = AUDIO_DIR / f"q_{q_id}.mp3"
            ticket_tasks.append((speech_text, out_file, f"Ticket Q {q_id}"))
            total_tickets_count += 1

    # 2. Build signs manifest & tasks
    signs_manifest = build_signs_manifest()
    signs_tasks = []
    for s in signs_manifest:
        speech_text = format_speech_text(s['questionText'], s['answers'])
        out_file = AUDIO_DIR / s['audioFileName']
        signs_tasks.append((speech_text, out_file, f"Sign {s['number']}"))

    all_tasks = ticket_tasks + signs_tasks
    print(f"\n=======================================================")
    print(f"Total audio files to generate: {len(all_tasks)}")
    print(f"  - Ticket Questions AB : {len(ticket_tasks)}")
    print(f"  - Road Signs Quizzes  : {len(signs_tasks)}")
    print(f"  - Voice               : {VOICE} ({RATE})")
    print(f"  - Concurrency         : {CONCURRENCY} workers")
    print(f"=======================================================\n")

    sem = asyncio.Semaphore(CONCURRENCY)
    generated_count = 0
    skipped_count = 0
    failed_count = 0

    progress_step = 50
    total = len(all_tasks)

    # Chunk execution for progress reporting
    chunk_size = 50
    for i in range(0, total, chunk_size):
        chunk = all_tasks[i:i + chunk_size]
        coros = [generate_single_audio(sem, text, out_p, label) for text, out_p, label in chunk]
        results = await asyncio.gather(*coros)

        for ok, reason in results:
            if ok:
                if reason == "skipped":
                    skipped_count += 1
                else:
                    generated_count += 1
            else:
                failed_count += 1

        done = min(i + chunk_size, total)
        percent = (done / total) * 100
        print(f"Progress: [{done}/{total}] ({percent:.1f}%) | Gen: {generated_count}, Skipped: {skipped_count}, Failed: {failed_count}", flush=True)

    # Calculate total size
    total_bytes = sum(f.stat().st_size for f in AUDIO_DIR.glob("*.mp3"))
    print(f"\n=======================================================")
    print(f"COMPLETED!")
    print(f"Total files in {AUDIO_DIR}: {len(list(AUDIO_DIR.glob('*.mp3')))}")
    print(f"Total size: {total_bytes / 1024 / 1024:.2f} MB")
    print(f"=======================================================\n")

if __name__ == "__main__":
    asyncio.run(main())
