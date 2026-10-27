#!/usr/bin/env python3
"""План серии «Тест по знакам»: выпуски по 9 знаков без повторов.

Пул — знаки, годные как загадка в «Успей узнать знак» (`content.load_signs`:
уникальные название и картинка, без табличек), чьё название помещается
в клетку одной строкой при кегле не мельче MIN_SIZE. Каждый знак выходит
ровно в одном выпуске. Выпуск 1 — первый ролик, собранный вручную
(`overview.QUIZ`), остальные набираются автоматически.

Неверные варианты — настоящие названия других знаков, причём такие, что
название уникально по всей базе (иначе вариант двусмыслен). Берутся
ближайшие: сначала из той же серии номеров (3.18.1 к 3.18.2), потом
из той же категории с ближайшим номером. Вариант не может совпадать
с верным ответом другой клетки того же выпуска — иначе ответ угадывается
исключением.

    /usr/bin/python3 -m tools.signs_grid.series     # пересобрать episodes.json
"""

from __future__ import annotations

import json
import random
import re
from pathlib import Path

from tools.signs_reel.content import EXCLUDED_CATEGORIES, _clean, _group, load_signs
from tools.signs_reel.frames import font

from . import overview as O

PLAN = Path(__file__).resolve().parent / "episodes.json"
PER_EPISODE = 9
MIN_SIZE = 21            # мельче варианты на общем плане не читаются
MAX_PER_CATEGORY = 3     # в выпуске — смесь категорий, как в первом ролике
SEED = 2026


def fits(title: str) -> bool:
    return font("medium", MIN_SIZE).getlength(title) <= O.CELL_W - 18 - O.BOX - 12 - 10


def num_key(number: str) -> tuple:
    return tuple(int(p) if p.isdigit() else 0 for p in number.split("."))


def distance(a: str, b: str) -> float:
    """Насколько номер b «рядом» с a: та же серия < та же категория < остальное."""
    if _group(a) == _group(b):
        return 0.0
    ka, kb = num_key(a), num_key(b)
    if ka[0] != kb[0]:
        return 100.0
    return 1.0 + abs(ka[1] - kb[1]) + 0.1 * abs((ka[2:] or (0,))[0] - (kb[2:] or (0,))[0])


def stems(title: str) -> set[str]:
    return {w[:5] for w in re.findall(r"[а-яё]{4,}", title.lower())}


def option_titles() -> dict[str, str]:
    """Номер → название для всех знаков, годных как неверный вариант."""
    raw = json.loads((O.ROOT / "questions" / "signs.json").read_text(encoding="utf-8"))
    count: dict[str, int] = {}
    for items in raw.values():
        for item in items.values():
            t = _clean(item.get("title", "")).rstrip(".").lower()
            count[t] = count.get(t, 0) + 1
    out = {}
    for category, items in raw.items():
        if category in EXCLUDED_CATEGORIES:
            continue
        for n, item in items.items():
            title = _clean(item.get("title", "")).rstrip(".")
            if title and count[title.lower()] == 1 and fits(title):
                out[item.get("number", n)] = title
    return out


def pick_distractors(number: str, answers: set[str], titles: dict[str, str],
                     rnd: random.Random) -> list[str]:
    own = titles.get(number) or O.load_db()[number]["title"].strip().rstrip(".")
    # Общее слово с верным ответом («Главная дорога» к «Конец главной
    # дороги») делает вариант правдоподобным сильнее, чем соседний номер:
    # без этого у малых категорий в варианты попадал «Кемпинг».
    own_stems = stems(own)
    cands = [(distance(number, n) - 30 * len(own_stems & stems(t)), rnd.random(), t)
             for n, t in titles.items() if t != own and t not in answers]
    cands.sort()
    # Берём из пяти ближайших, а не три первых подряд — иначе у соседних
    # номеров варианты были бы почти одинаковыми из выпуска в выпуск.
    near = [t for _, _, t in cands[:5]]
    return rnd.sample(near, 3)


def build() -> list[list]:
    rnd = random.Random(SEED)
    pool = [s for signs in load_signs().values() for s in signs if fits(s.title)]
    first = [n for n, _ in O.QUIZ]
    rest = [s for s in pool if s.number not in first]
    rnd.shuffle(rest)

    titles = option_titles()
    episodes: list[list] = [[[n, opts] for n, opts in O.QUIZ]]
    while True:
        chosen, groups, per_cat = [], set(), {}
        # Сначала категории, где знаков осталось больше, — чтобы под конец
        # не остаться с одними сервисными.
        left: dict[str, int] = {}
        for s in rest:
            left[s.category] = left.get(s.category, 0) + 1
        for s in sorted(rest, key=lambda s: -left[s.category]):
            if _group(s.number) in groups or per_cat.get(s.category, 0) >= MAX_PER_CATEGORY:
                continue
            chosen.append(s)
            groups.add(_group(s.number))
            per_cat[s.category] = per_cat.get(s.category, 0) + 1
            if len(chosen) == PER_EPISODE:
                break
        if len(chosen) < PER_EPISODE:
            break
        rest = [s for s in rest if s not in chosen]
        rnd.shuffle(chosen)

        answers = {s.title for s in chosen}
        # Позиция верного ответа — равномерно по выпуску, а не случайно:
        # иначе в каком-то ролике он может три раза подряд оказаться первым.
        slots = [i % 4 for i in range(PER_EPISODE)]
        rnd.shuffle(slots)
        quiz = []
        for s, slot in zip(chosen, slots):
            opts = pick_distractors(s.number, answers, titles, rnd)
            opts.insert(slot, s.title)
            quiz.append([s.number, opts])
        episodes.append(quiz)
    return episodes


def load(episode: int) -> list[tuple[str, list[str]]]:
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    return [(n, opts) for n, opts in plan[episode - 1]]


def main() -> None:
    episodes = build()
    PLAN.write_text(json.dumps(episodes, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    db = O.load_db()
    for e, quiz in enumerate(episodes, 1):
        print(f"\n── Выпуск {e}")
        for n, opts in quiz:
            title = db[n]["title"].strip().rstrip(".")
            print(f"  {n:>7}  " + " | ".join(f"[{o}]" if o == title else o for o in opts))
    print(f"\n{len(episodes)} выпусков → {PLAN}")


if __name__ == "__main__":
    main()
