#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Собирает assets/countries/rs/questions/{questions_ab,topics_ab}.json
ИСКЛЮЧИТЕЛЬНО из официальной базы MUP — без авторских вопросов (по прямому
требованию: максимальная идентичность вопросов и картинок с официальной базой,
без выдумок).

Источник — official_questions.json (см. build_official_questions.py): вопросы,
варианты, картинки и поены дословно из официальных PDF MUP; правильные ответы
определены и адверсариально верифицированы отдельным воркфлоу
(rs_official_answers_workflow.js) — в набор попадают только вопросы, где
сошлись два независимых прохода (либо их разрешил третий агент-судья).

Мультистрановое приложение: у Сербии балльная модель экзамена (вопрос весит
1/2/3 балла, сдал при ≥85% от максимума, 41 вопрос за 45 минут — регламент MUP).
"""
import json
import os

OFFICIAL_PATH = os.path.join(
    "assets", "countries", "rs", "questions", "official_questions.json")

# Размер «testa» на вкладке «Testovi» = размер официального экзамена MUP.
TICKET_SIZE = 41


def build():
    out_dir = os.path.join("assets", "countries", "rs", "questions")
    os.makedirs(out_dir, exist_ok=True)

    if not os.path.exists(OFFICIAL_PATH):
        raise SystemExit(
            f"{OFFICIAL_PATH} не найден — сначала запустить "
            "build_official_questions.py")
    parsed = json.load(open(OFFICIAL_PATH, encoding="utf-8"))

    # questions_ab.json — разбиваем на «тесты» по TICKET_SIZE.
    tickets = []
    for t_idx in range(0, len(parsed), TICKET_SIZE):
        chunk = parsed[t_idx:t_idx + TICKET_SIZE]
        number = t_idx // TICKET_SIZE + 1
        tickets.append({
            "number": number,
            "questions": [dict(q, ticketNumber=number) for q in chunk],
        })
    with open(os.path.join(out_dir, "questions_ab.json"), "w",
              encoding="utf-8") as f:
        json.dump({"tickets": tickets}, f, ensure_ascii=False, indent=2)

    # topics_ab.json — группировка по официальной категории MUP (порядок
    # первого появления = порядок, заданный build_official_questions.py).
    topic_order = []
    by_topic = {}
    for q in parsed:
        name = q["topic"][0]
        if name not in by_topic:
            by_topic[name] = []
            topic_order.append(name)
        by_topic[name].append(q)
    topics = [{"name": name, "questions": by_topic[name]} for name in topic_order]
    with open(os.path.join(out_dir, "topics_ab.json"), "w",
              encoding="utf-8") as f:
        json.dump({"topics": topics}, f, ensure_ascii=False, indent=2)

    total_points = sum(q["points"] for q in parsed)
    print(f"questions: {len(parsed)} | tickets: {len(tickets)} | "
          f"topics: {len(topics)} | total points: {total_points}")


if __name__ == "__main__":
    build()
