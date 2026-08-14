#!/usr/bin/env python3
"""План серии роликов «вопрос из билета» по всем вопросам с картинками.

    python3 -m tools.signs_reel.question_plan            # посчитать и показать сводку
    python3 -m tools.signs_reel.question_plan --write    # записать план в файлы

План — это список выпусков с номером, фоном, расчётным хронометражом и
подсказкой, что на кадре подсвечивать. Сами ролики он не собирает: рамку
подсветки всё равно ставит человек, а автопоиск в этом формате не работает
(см. QUESTION_REELS.md).
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from . import backgrounds, question as Q

PLAN_JSON = Path(__file__).resolve().parent / "question_plan.json"
PLAN_MD = Path(__file__).resolve().parent / "QUESTION_PLAN.md"

MAX_SECONDS = 58.0        # после минуты Shorts перестают показываться лентой

# Подсказки по подсветке. Решает человек, но по тексту вопроса и разбора
# почти всегда видно, к какому из трёх случаев он относится.
NO_HIGHLIGHT = re.compile(
    r"(сколько (полос|проезжих частей|перекрёстков|перекрестков)"
    r"|какая дорога|разрешено ли вам движение|что означает эта разметка)",
    re.IGNORECASE,
)
MULTI_HINT = re.compile(
    r"(\bоба\b|\bобе\b|обоим|и\s+[АБВA-C]\b|[АБВ]\s+и\s+[АБВ]|обеим|"
    r"кому вы обязаны уступить|очередност|в какой последовательности)",
    re.IGNORECASE,
)


def speech(text: str) -> float:
    """Оценка длительности реплики по тексту (та же формула, что в verify)."""
    return 0.32 + len(text) * 0.075


def estimate(q) -> float:
    explanation, _ = Q.explanation(q.comment)
    seconds = (
        speech(q.text) + Q.T_QUESTION_TAIL
        + sum(speech(f"{Q.ORDINALS[i]}. {o}") + Q.T_OPTION_TAIL
              for i, o in enumerate(q.options))
        + Q.T_THINK
        + speech(f"Правильный ответ — {Q.ORDINALS[q.correct].lower()}.") + Q.T_REVEAL_TAIL
        + (speech(explanation) + Q.T_EXPLAIN_TAIL if explanation else 0)
        + speech(Q.CTA_TEXT) + Q.T_OUTRO_TAIL
    )
    return round(seconds, 1)


def highlight_hint(q) -> str:
    """Что подсвечивать: «нет», «один объект», «несколько», «решить вручную»."""
    if NO_HIGHLIGHT.search(q.text):
        return "нет"
    if MULTI_HINT.search(q.text) or MULTI_HINT.search(q.comment or ""):
        return "несколько"
    if Q.sign_number(q):
        return "один объект"
    return "решить вручную"


def build(country: str = "ru") -> dict:
    scenes = [p.stem for p in backgrounds.available()]
    if not scenes:
        raise SystemExit("нет фонов в tools/signs_reel/backgrounds")

    questions = Q.load_questions(country)
    # Порядок — по билетам: так серию удобно вести и видно, что уже снято.
    questions.sort(key=lambda q: (q.ticket, q.id))

    plan, skipped = [], []
    index = 0
    for q in questions:
        seconds = estimate(q)
        if seconds > MAX_SECONDS:
            skipped.append({"id": q.id, "ticket": q.ticket, "question": q.text,
                            "seconds": seconds, "reason": "длиннее минуты"})
            continue
        index += 1
        plan.append({
            "index": index,
            "id": q.id,
            "ticket": q.ticket,
            "question": q.text,
            "answers": q.options,
            "correct": q.correct + 1,
            "image": q.image.name,
            "seconds": seconds,
            # Фоны идут вперемешку по кругу: одинаковый фон у соседних
            # роликов делает ленту однообразной.
            "background": scenes[(index * 7) % len(scenes)],
            "highlight": highlight_hint(q),
            "sign": Q.sign_number(q),
            "file": f"{index:03d}_bilet{q.ticket:02d}_{Q.slugify(q.text)}.mp4",
        })
    return {"episodes": plan, "skipped": skipped, "scenes": scenes}


def summary(data: dict) -> str:
    plan, skipped = data["episodes"], data["skipped"]
    total = sum(e["seconds"] for e in plan)
    hints = {}
    for e in plan:
        hints[e["highlight"]] = hints.get(e["highlight"], 0) + 1
    lines = [
        f"Выпусков в плане: {len(plan)}",
        f"Отложено (длиннее минуты): {len(skipped)}",
        f"Суммарный хронометраж: {total / 60:.0f} мин ({total / 3600:.1f} ч)",
        f"Средняя длина ролика: {total / len(plan):.1f} с",
        "Подсветка: " + ", ".join(f"{k} — {v}" for k, v in sorted(hints.items())),
        f"Фонов в ротации: {len(data['scenes'])}",
    ]
    return "\n".join(lines)


def write(data: dict) -> None:
    PLAN_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    rows = ["| № | Билет | Вопрос | Ответ | Длина | Фон | Подсветка |",
            "|---|---|---|---|---|---|---|"]
    for e in data["episodes"]:
        question = e["question"].replace("|", "/")
        answer = e["answers"][e["correct"] - 1].replace("|", "/")
        rows.append(f"| {e['index']:03d} | {e['ticket']} | {question} | {answer} | "
                    f"{e['seconds']:.0f} с | {e['background']} | {e['highlight']} |")

    PLAN_MD.write_text(
        "# План серии «вопрос из билета»\n\n"
        "Сгенерирован `question_plan.py`. Правила формата — QUESTION_REELS.md.\n\n"
        "```\n" + summary(data) + "\n```\n\n"
        "Столбец «Подсветка» — подсказка, а не приговор: рамку ставит человек,\n"
        "и решать надо по логике вопроса. «Нет» означает, что выделять нечего\n"
        "(например, «сколько полос имеет дорога»).\n\n"
        + "\n".join(rows) + "\n",
        encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser(description="План роликов по вопросам билетов")
    p.add_argument("--country", default="ru")
    p.add_argument("--write", action="store_true", help="записать план в файлы")
    args = p.parse_args()

    data = build(args.country)
    print(summary(data))
    if args.write:
        write(data)
        print(f"\nЗаписано: {PLAN_JSON.name}, {PLAN_MD.name}")


if __name__ == "__main__":
    main()
